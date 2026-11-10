local actionLabels = {
    ['goto'] = 'teleportou ate o jogador',
    bring = 'trouxe o jogador',
    heal = 'curou o jogador',
    revive = 'reviveu o jogador',
    revive_full = 'restaurou completamente o jogador',
    kick = 'expulsou o jogador',
    slots = 'alterou os slots do jogador',
    fix_vehicle = 'restaurou o veiculo do jogador',
    delete_character = 'excluiu o personagem',
    block_character = 'bloqueou o personagem',
    reset_appearance = 'abriu a recriacao de aparencia',
}

local actionPermissions = {
    ['goto'] = 'player.goto',
    bring = 'player.bring',
    heal = 'player.heal',
    revive = 'player.revive',
    revive_full = 'player.revive_full',
    kick = 'player.kick',
    slots = 'character.slots',
    fix_vehicle = 'vehicle.fix',
    delete_character = 'character.delete',
    block_character = 'character.block',
    reset_appearance = 'player.appearance',
}

local utilityPermissions = {
    car = 'vehicle.spawn',
    dv = 'vehicle.delete',
    dvarea = 'vehicle.delete',
    noclip = 'tools.noclip',
    wall = 'tools.wall',
    wallmap = 'tools.wallmap',
}

local lastActionAt = {}
local pendingVehicleSpawns = {}

local function vehicleSpawnConfig()
    local config = type(ORAdminConfig.VehicleSpawn) == 'table' and ORAdminConfig.VehicleSpawn or {}
    return {
        atPlayer = config.SpawnAtPlayerPosition ~= false,
        replaceDriver = config.ReplaceCurrentVehicleForDriver ~= false,
        passengerGhostMs = math.max(0, math.min(30000, tonumber(config.PassengerGhostDurationMs) or 6000)),
    }
end

local function getCorePlayer(playerSource)
    playerSource = tonumber(playerSource)
    if not playerSource or playerSource <= 0 then return nil end
    return exports.ob_core:GetPlayer(playerSource)
end

local function getRole(playerSource)
    local player = getCorePlayer(playerSource)
    local character = player and player.character
    if character then
        local role = AdminDatabase.getCharacterRole(character.userId)
        if role then return role end
    end

    -- O ACE continua como acesso de emergencia e para o primeiro bootstrap.
    return exports.ob_core:IsAdmin(playerSource) == true and 'admin' or nil
end

local function hasPermission(playerSource, permission)
    local role = getRole(playerSource)
    local definition = role and ORAdminConfig.Roles[role]
    local permissions = definition and definition.permissions
    return permissions and (permissions['*'] == true or permissions[permission] == true) or false
end

local function isAdmin(playerSource)
    return hasPermission(playerSource, 'panel.open')
end

local function roleLevel(role)
    if not role then return 0 end
    if role == 'owner' then return math.huge end -- nenhum cargo customizado supera o owner
    local definition = ORAdminConfig.Roles[role]
    local level = definition and tonumber(definition.level)
    if not level or level ~= level or level <= 0 or level == math.huge then return nil end
    return level
end

local function outranks(actorSource, targetRole)
    local actorLevel, targetLevel = roleLevel(getRole(actorSource)), roleLevel(targetRole)
    return actorLevel ~= nil and targetLevel ~= nil and actorLevel > targetLevel
end

local function canTarget(actorSource, targetSource)
    return actorSource ~= targetSource and outranks(actorSource, getRole(targetSource))
end

local function canResetAppearance(actorSource, targetSource)
    return hasPermission(actorSource, 'player.appearance')
        and (actorSource == targetSource or getRole(targetSource) == nil)
end

exports('CanResetAppearance', function(actorSource, targetSource)
    actorSource, targetSource = tonumber(actorSource), tonumber(targetSource)
    return actorSource ~= nil and targetSource ~= nil and canResetAppearance(actorSource, targetSource)
end)

exports('CanTarget', function(actorSource, targetSource)
    actorSource, targetSource = tonumber(actorSource), tonumber(targetSource)
    return actorSource ~= nil and targetSource ~= nil and canTarget(actorSource, targetSource)
end)

local protectedActions = {kick=true, ban=true, bring=true, slots=true, delete_character=true, block_character=true}

-- API publica para menus administrativos sem duplicar a regra de cargos.
exports('HasPermission', function(playerSource, permission)
    return hasPermission(tonumber(playerSource), permission or 'panel.open')
end)

-- O gerenciador offline usa a mesma fonte de verdade do painel online. Nao
-- duplica o cache de cargos em outro resource e, principalmente, nao aceita
-- cargo informado pelo cliente sem validar novamente o owner no servidor.
exports('GetRole', function(playerSource)
    return getRole(tonumber(playerSource))
end)

exports('GetCharacterRole', function(userId)
    return AdminDatabase.getCharacterRole(tonumber(userId))
end)

exports('GetRoles', function()
    local roles = AdminDatabase.getRoles()
    for index = #roles, 1, -1 do
        if roles[index].key == 'owner' then table.remove(roles, index) end
    end
    roles[#roles + 1] = { key = 'player', label = 'Player' }
    return roles
end)

exports('SetOfflineRole', function(actorSource, userId, role)
    actorSource, userId = tonumber(actorSource), tonumber(userId)
    role = type(role) == 'string' and role:lower() or ''
    if not actorSource or not hasPermission(actorSource, 'roles.manage') or getRole(actorSource) ~= 'owner' then
        return false, 'Somente o owner pode alterar cargos offline.'
    end
    if not userId or userId < 1 or userId ~= math.floor(userId) then
        return false, 'ID fixo do personagem invalido.'
    end
    local current = AdminDatabase.getCharacterRole(userId)
    if current == 'owner' then return false, 'O owner so pode ser alterado pelo console do txAdmin.' end

    local actor = getCorePlayer(actorSource)
    if role == '' or role == 'player' then
        local success, removedOrMessage = AdminDatabase.revokeCharacterAdmin(userId)
        if not success then return false, removedOrMessage end
        if not removedOrMessage then return true, 'O personagem ja era player.' end
        AdminDatabase.record(actor, nil, 'offline_role_revoke', ('user_id=%s previous=%s'):format(userId, current or 'player'))
        return true, 'Cargo administrativo removido; o personagem agora e player.'
    end
    if role == 'owner' or not ORAdminConfig.Roles[role] then return false, 'Cargo administrativo invalido.' end

    local actorUserId = actor and actor.character and actor.character.userId or nil
    local success, message = AdminDatabase.grantCharacterAdmin(userId, role, actorUserId)
    if not success then return false, message end
    AdminDatabase.record(actor, nil, 'offline_role_set', ('user_id=%s role=%s previous=%s'):format(userId, role, current or 'player'))
    return true, ('Cargo alterado para %s.'):format(ORAdminConfig.Roles[role].label or role)
end)

exports('RecordOfflineAudit', function(actorSource, targetUserId, action, details)
    local actor = getCorePlayer(tonumber(actorSource))
    if not actor or not isAdmin(actorSource) then return false end
    AdminDatabase.record(actor, nil, tostring(action or 'offline_action'):sub(1, 64),
        ('target_user_id=%s %s'):format(tonumber(targetUserId) or 'none', tostring(details or ''):sub(1, 900)))
    return true
end)

local function panelPermissions(playerSource)
    local permissions = {}
    for _, permission in pairs(actionPermissions) do
        permissions[permission] = hasPermission(playerSource, permission)
    end
    for _, permission in pairs(utilityPermissions) do
        permissions[permission] = hasPermission(playerSource, permission)
    end
    permissions['roles.manage'] = hasPermission(playerSource, 'roles.manage')
    return permissions
end

local function notify(playerSource, message, notificationType)
    TriggerClientEvent('ob_admin:client:notify', playerSource, message, notificationType or 'info')
end

local function characterName(player)
    local character = player and player.character
    if not character then return 'Selecionando personagem' end

    local first = character.firstname or ''
    local last = character.lastname or ''
    local fullName = ('%s %s'):format(first, last):gsub('^%s+', ''):gsub('%s+$', '')
    return fullName ~= '' and fullName or 'Sem nome'
end

local function listPlayers(actorSource)
    local players = {}

    for _, playerId in ipairs(GetPlayers()) do
        local playerSource = tonumber(playerId)
        local player = getCorePlayer(playerSource)
        local character = player and player.character or nil

        players[#players + 1] = {
            source = playerSource,
            name = GetPlayerName(playerSource) or ('ID %s'):format(playerSource),
            characterName = characterName(player),
            userId = character and character.userId or nil,
            spawned = player and player.spawned == true or false,
            ping = GetPlayerPing(playerSource),
            slots = player and exports.ob_core:GetCharacterSlotLimit(player.license) or 1,
            role = character and AdminDatabase.getCharacterRole(character.userId) or nil,
            canResetAppearance = canResetAppearance(actorSource, playerSource),
        }
    end

    table.sort(players, function(a, b)
        return a.source < b.source
    end)

    return players
end

local function playerCoords(playerSource)
    local ped = GetPlayerPed(playerSource)
    if not ped or ped == 0 then return nil end

    local coords = GetEntityCoords(ped)
    if not coords then return nil end

    return {
        x = coords.x,
        y = coords.y,
        z = coords.z + 0.15,
        heading = GetEntityHeading(ped) or 0.0,
    }
end

local function performAction(actorSource, targetSource, action, value)
    local actor = getCorePlayer(actorSource)
    local target = getCorePlayer(targetSource)
    if not actor then return false, 'Sua sessao ainda nao esta pronta.' end
    if not target or not GetPlayerName(targetSource) then return false, 'Jogador indisponivel.' end
    if not actionLabels[action] then return false, 'Acao administrativa invalida.' end
    if not hasPermission(actorSource, actionPermissions[action]) then
        return false, 'Seu cargo nao possui permissao para essa acao.'
    end
    if protectedActions[action] and not canTarget(actorSource, targetSource) then
        return false, 'Voce nao pode agir contra si mesmo ou um cargo igual/superior ao seu.'
    end
    if action == 'reset_appearance' and not canResetAppearance(actorSource, targetSource) then
        return false, 'Voce pode refazer sua aparencia e a de jogadores comuns, nunca a de outro staff.'
    end
    if action == 'kick' and actorSource == targetSource then
        return false, 'Voce nao pode se expulsar pelo painel.'
    end
    if (action == 'delete_character' or action == 'block_character') and actorSource == targetSource then
        return false, 'Voce nao pode alterar seu proprio personagem pelo painel.'
    end

    if action == 'reset_appearance' then
        if GetResourceState('ob_creator') ~= 'started' then return false, 'O criador de aparencia esta indisponivel.' end
        local opened, message = exports.ob_creator:BeginAppearanceEdit(targetSource, actorSource)
        if not opened then return false, message or 'Nao foi possivel abrir a aparencia.' end
    elseif action == 'goto' then
        local coords = playerCoords(targetSource)
        if not coords then return false, 'Nao foi possivel localizar o jogador.' end
        TriggerClientEvent('ob_admin:client:teleport', actorSource, coords)
    elseif action == 'bring' then
        local coords = playerCoords(actorSource)
        if not coords then return false, 'Nao foi possivel obter sua posicao.' end
        TriggerClientEvent('ob_admin:client:teleport', targetSource, coords)
    elseif action == 'heal' then
        TriggerClientEvent('ob_admin:client:heal', targetSource, false)
    elseif action == 'revive' then
        if GetResourceState('ob_health') == 'started' then
            local revived, reviveError = exports.ob_health:RestorePlayer(targetSource, actorSource)
            if not revived then return false, reviveError or 'Nao foi possivel reanimar o jogador.' end
        else
            TriggerClientEvent('ob_admin:client:heal', targetSource, true)
        end
    elseif action == 'revive_full' then
        if GetResourceState('ob_health') == 'started' then
            -- Revive administrativo deve devolver o controle imediatamente;
            -- a animacao de levantar continua reservada para revive em RP.
            local revived, reviveError = exports.ob_health:RestorePlayer(targetSource, actorSource)
            if not revived then return false, reviveError or 'Nao foi possivel reanimar o jogador.' end
        else
            TriggerClientEvent('ob_admin:client:restore', targetSource)
        end
        if GetResourceState('ob_inventory') == 'started' then
            exports.ob_inventory:SetNeeds(targetSource, 100, 100, 0)
        end
    elseif action == 'slots' then
        local slots = tonumber(value)
        if not slots then return false, 'Quantidade de slots invalida.' end

        local ok, err = exports.ob_core:SetCharacterSlotLimit(target.license, slots)
        if not ok then return false, err or 'Nao foi possivel alterar os slots.' end
        value = exports.ob_core:GetCharacterSlotLimit(target.license)
    elseif action == 'fix_vehicle' then
        TriggerClientEvent('ob_admin:client:fixVehicle', targetSource)
    elseif action == 'kick' then
        AdminDatabase.record(actor, target, action, 'Removido pelo painel administrativo.')
        -- Exports serializam tabelas: compare a identidade, nao a referencia Lua.
        local currentActor, currentTarget = getCorePlayer(actorSource), getCorePlayer(targetSource)
        if not currentActor or not currentTarget
            or currentActor.license ~= actor.license or currentTarget.license ~= target.license
            or (currentActor.character and currentActor.character.userId) ~= (actor.character and actor.character.userId)
            or (currentTarget.character and currentTarget.character.userId) ~= (target.character and target.character.userId)
            or not canTarget(actorSource, targetSource) then return false, 'Sessao ou hierarquia alterada. Tente novamente.' end
        DropPlayer(targetSource, 'Removido pela equipe administrativa.')
        return true, ('%s foi removido do servidor.'):format(GetPlayerName(targetSource) or ('ID %s'):format(targetSource))
    elseif action == 'delete_character' then
        local character = target.character
        if not character then return false, 'O jogador ainda nao selecionou um personagem.' end
        local ok, err = exports.ob_core:DeleteCharacter(character.userId)
        if not ok then return false, err or 'Nao foi possivel excluir o personagem.' end
        AdminDatabase.record(actor, target, action, 'Excluido pelo painel administrativo.')
        DropPlayer(targetSource, 'Seu personagem foi excluido pela administracao.')
        return true, ('O personagem de %s foi excluido.'):format(GetPlayerName(targetSource) or ('ID %s'):format(targetSource))
    elseif action == 'block_character' then
        local character = target.character
        local actorCharacter = actor.character
        if not character then return false, 'O jogador ainda nao selecionou um personagem.' end
        if not actorCharacter then return false, 'Seu personagem ainda nao esta pronto.' end
        local ok, err = exports.ob_core:BlockCharacter(character.userId, 'Bloqueado pela administracao.', actorCharacter.userId)
        if not ok then return false, err or 'Nao foi possivel bloquear o personagem.' end
        AdminDatabase.record(actor, target, action, 'Bloqueado pelo painel administrativo.')
        DropPlayer(targetSource, 'Seu personagem foi bloqueado pela administracao.')
        return true, ('O personagem de %s foi bloqueado e a vaga foi liberada.'):format(GetPlayerName(targetSource) or ('ID %s'):format(targetSource))
    end

    local detail = action == 'slots' and ('slots=%s'):format(value) or nil
    AdminDatabase.record(actor, target, action, detail)
    return true, ('Voce %s: %s.'):format(actionLabels[action], GetPlayerName(targetSource) or ('ID %s'):format(targetSource))
end

OR.Callback.register('listPlayers', function(playerSource)
    if not hasPermission(playerSource, 'players.view') then
        return nil, 'Sem permissao administrativa.'
    end

    local role = getRole(playerSource)
    return {
        players = listPlayers(playerSource),
        maxCharacterSlots = exports.ob_core:GetMaximumCharacterSlots(),
        permissions = panelPermissions(playerSource),
        roles = AdminDatabase.getRoles(),
        role = role,
        roleLabel = role and ORAdminConfig.Roles[role] and ORAdminConfig.Roles[role].label or 'Admin',
    }
end)

RegisterNetEvent('ob_admin:server:requestOpen', function()
    local playerSource = source
    if not isAdmin(playerSource) then
        local player = getCorePlayer(playerSource)
        local character = player and player.character
        local fivemIdentifier
        for _, identifier in ipairs(GetPlayerIdentifiers(playerSource)) do
            if identifier:sub(1, 6) == 'fivem:' then
                fivemIdentifier = identifier
                break
            end
        end
        print(('[ob_admin] Acesso negado para %s (ID %s). admin=%s developer=%s devMode=%s'):format(
            GetPlayerName(playerSource) or 'desconhecido',
            playerSource,
            tostring(exports.ob_core:HasPermission(playerSource, 'or.admin')),
            tostring(exports.ob_core:HasPermission(playerSource, 'or.developer')),
            GetConvar('ob_development_mode', 'false')
        ))
        print(('[ob_admin] Diagnostico: fivem=%s user_id=%s characterAdmin=%s. Bootstrap no console: oradmin_addsource %s'):format(
            fivemIdentifier or 'nao encontrado',
            character and character.userId or 'nenhum',
            tostring(character and AdminDatabase.isCharacterAdmin(character.userId) or false),
            playerSource
        ))
        notify(playerSource, 'Sem permissao para abrir o painel administrativo.', 'error')
        return
    end

    TriggerClientEvent('ob_admin:client:open', playerSource)
end)

local function executeActionRequest(actorSource, action, targetSource, value)
    if not isAdmin(actorSource) then
        notify(actorSource, 'Sem permissao administrativa.', 'error')
        return
    end

    local now = GetGameTimer()
    if lastActionAt[actorSource] and now - lastActionAt[actorSource] < 300 then
        return
    end
    lastActionAt[actorSource] = now

    targetSource = tonumber(targetSource)
    if not targetSource or targetSource <= 0 then
        notify(actorSource, 'Jogador invalido.', 'error')
        return
    end

    local success, message = performAction(actorSource, targetSource, action, value)
    notify(actorSource, message, success and 'success' or 'error')
    TriggerClientEvent('ob_admin:client:actionResult', actorSource)
end

RegisterNetEvent('ob_admin:server:execute', function(action, targetSource, value)
    executeActionRequest(source, action, targetSource, value)
end)

-- Comandos digitados sempre recebem o ID fixo do personagem. A conversao
-- para source acontece apenas no servidor, perto do momento de executar.
RegisterNetEvent('ob_admin:server:executeByUserId', function(action, targetUserId, value)
    local actorSource = source
    if targetUserId == nil or tostring(targetUserId):match('^%s*$') then
        targetUserId = tonumber(exports.ob_core:GetUserId(actorSource))
    else
        targetUserId = tonumber(targetUserId)
    end
    targetUserId = math.floor(targetUserId or 0)
    local targetSource = targetUserId > 0 and exports.ob_core:GetSourceByUserId(targetUserId) or nil
    if not targetSource or not GetPlayerName(targetSource) then
        notify(actorSource, 'Personagem indisponivel. Confira o ID fixo e se ele esta na cidade.', 'error')
        return
    end

    executeActionRequest(actorSource, action, targetSource, value)
end)

local areaReviveBusy = {}
RegisterCommand('revivearea', function(actorSource, args)
    actorSource = tonumber(actorSource)
    if not actorSource or actorSource <= 0 then return print('[ob_admin] Use revivearea dentro do jogo.') end
    if not hasPermission(actorSource, 'player.revive_full') then
        return notify(actorSource, 'Sem permissao para revive em area.', 'error')
    end
    local radius = args[1] == nil and 10 or tonumber(args[1])
    if not radius or radius ~= radius or radius < 1 or radius > 100 then
        return notify(actorSource, 'Use /revivearea [raio de 1 a 100 metros].', 'error')
    end
    if areaReviveBusy[actorSource] or not OR.Security.rateLimit(actorSource, 'admin:revive_area', 1, 5000) then
        return notify(actorSource, 'Aguarde antes de restaurar a area novamente.', 'error')
    end
    local origin = playerCoords(actorSource)
    if not origin then return notify(actorSource, 'Posicao indisponivel.', 'error') end
    local bucket = GetPlayerRoutingBucket(actorSource)
    areaReviveBusy[actorSource] = true
    local ok, count = pcall(function()
        local restored = 0
        for _, target in ipairs(GetPlayers()) do
            target = tonumber(target)
            if target and GetPlayerRoutingBucket(target) == bucket then
                local coords = playerCoords(target)
                if coords then
                    local dx, dy, dz = coords.x-origin.x, coords.y-origin.y, coords.z-origin.z
                    if dx*dx+dy*dy+dz*dz <= radius*radius then
                        if performAction(actorSource, target, 'revive_full') then restored = restored + 1 end
                    end
                end
            end
        end
        return restored
    end)
    areaReviveBusy[actorSource] = nil
    notify(actorSource, ok and ('%s jogador(es) restaurado(s) em %s metros.'):format(count, radius)
        or 'Nao foi possivel concluir o revive em area.', ok and 'success' or 'error')
end, false)

OR.Callback.register('getWallMapPlayers', function(playerSource)
    if not hasPermission(playerSource, 'tools.wallmap') then
        return nil, 'Sem permissao para usar wallmap.'
    end

    local players = {}
    for _, targetSource in ipairs(GetPlayers()) do
        targetSource = tonumber(targetSource)
        if targetSource and GetPlayerName(targetSource) then
            players[#players + 1] = {
                source = targetSource,
                isAdmin = isAdmin(targetSource),
            }
        end
    end
    return players
end)

RegisterNetEvent('ob_admin:server:utility', function(action, value)
    local actorSource = source
    local permission = utilityPermissions[action]
    if not permission or not hasPermission(actorSource, permission) then
        notify(actorSource, 'Seu cargo nao possui permissao para essa ferramenta.', 'error')
        return
    end

    local actor = getCorePlayer(actorSource)
    if action == 'car' then
        local vehicle = type(value) == 'string' and value:lower() or ''
        if vehicle == '' or #vehicle > 32 or not vehicle:match('^[a-z0-9_]+$') then
            notify(actorSource, 'Modelo de veiculo invalido. Use apenas letras, numeros e _.', 'error')
            return
        end
        local ped = GetPlayerPed(actorSource)
        if not ped or ped == 0 then
            notify(actorSource, 'Seu personagem nao esta disponivel.', 'error')
            return
        end
        local config = vehicleSpawnConfig()
        local currentVehicle = GetVehiclePedIsIn(ped, false)
        local isDriver = currentVehicle ~= 0 and GetPedInVehicleSeat(currentVehicle, -1) == ped
        local spawnEntity = currentVehicle ~= 0 and currentVehicle or ped
        local coords, heading = GetEntityCoords(spawnEntity), GetEntityHeading(spawnEntity)
        local x, y, z = coords.x, coords.y, coords.z
        if not config.atPlayer then
            local radians = math.rad(heading)
            x = x - math.sin(radians) * 3.5
            y = y + math.cos(radians) * 3.5
            z = z + 0.5
        end
        if GetResourceState('ob_vehiclekeys') ~= 'started' then
            notify(actorSource, 'Sistema de chaves indisponivel.', 'error')
            return
        end
        local function finishSpawn(ghostMs, previousNetId)
            local spawned, vehicleData = exports.ob_core:SpawnTemporaryVehicle(actorSource, vehicle, {
                x = x, y = y, z = z, w = heading,
            }, {
                platePrefix = 'ADMIN', fuel = 100.0, clearRadius = false,
                maxDistance = 15.0, temporaryKind = 'admin',
            })
            if not spawned then
                notify(actorSource, vehicleData or 'Nao foi possivel criar o veiculo no servidor.', 'error')
                return false
            end
            TriggerClientEvent('ob_admin:client:enterSpawnedVehicle', actorSource, vehicleData.netId, ghostMs or 0, previousNetId)
            AdminDatabase.record(actor, nil, 'spawn_vehicle', ('model=%s'):format(vehicle))
            notify(actorSource, ('Veiculo %s criado com chave temporaria.'):format(vehicle), 'success')
            return true
        end

        if isDriver and config.replaceDriver then
            local previousNetId = NetworkGetNetworkIdFromEntity(currentVehicle)
            local token = ('%s:%s:%s'):format(actorSource, GetGameTimer(), math.random(100000, 999999))
            pendingVehicleSpawns[actorSource] = {
                token = token,
                model = vehicle,
                coords = { x = x, y = y, z = z, w = heading },
                previousNetId = previousNetId,
                expiresAt = GetGameTimer() + 12000,
            }
            TriggerClientEvent('ob_admin:client:replaceVehicleForSpawn', actorSource, token, previousNetId, vehicle)
            return
        end

        local previousNetId = currentVehicle ~= 0 and NetworkGetNetworkIdFromEntity(currentVehicle) or nil
        local ghostMs = currentVehicle ~= 0 and config.passengerGhostMs or 0
        finishSpawn(ghostMs, previousNetId)
        return
    end

    local eventName = {
        dv = 'ob_admin:client:deleteVehicle',
        dvarea = 'ob_admin:client:deleteVehiclesArea',
        noclip = 'ob_admin:client:toggleNoclip',
        wall = 'ob_admin:client:toggleWall',
        wallmap = 'ob_admin:client:toggleWallMap',
    }
    TriggerClientEvent(eventName[action], actorSource)
    AdminDatabase.record(actor, nil, ('toggle_%s'):format(action), nil)
end)

RegisterNetEvent('ob_admin:server:completeVehicleReplacement', function(token, deleted)
    local actorSource = source
    local pending = pendingVehicleSpawns[actorSource]
    pendingVehicleSpawns[actorSource] = nil
    if not pending or pending.token ~= token or GetGameTimer() > pending.expiresAt then return end
    if deleted ~= true or not hasPermission(actorSource, 'vehicle.spawn') then
        notify(actorSource, 'O veiculo atual nao foi removido; o novo nao foi criado.', 'error')
        return
    end

    local previous = NetworkGetEntityFromNetworkId(tonumber(pending.previousNetId) or 0)
    local deadline = GetGameTimer() + 2000
    while previous ~= 0 and DoesEntityExist(previous) and GetGameTimer() < deadline do
        Wait(50)
        previous = NetworkGetEntityFromNetworkId(tonumber(pending.previousNetId) or 0)
    end
    if previous ~= 0 and DoesEntityExist(previous) then
        notify(actorSource, 'O servidor ainda reconhece o veiculo antigo; tente novamente.', 'error')
        return
    end

    local actor = getCorePlayer(actorSource)
    local spawned, vehicleData = exports.ob_core:SpawnTemporaryVehicle(actorSource, pending.model, pending.coords, {
        platePrefix = 'ADMIN', fuel = 100.0, clearRadius = false,
        maxDistance = 20.0, temporaryKind = 'admin',
    })
    if not spawned then
        notify(actorSource, vehicleData or 'Nao foi possivel criar o veiculo no servidor.', 'error')
        return
    end
    TriggerClientEvent('ob_admin:client:enterSpawnedVehicle', actorSource, vehicleData.netId, 0, nil)
    AdminDatabase.record(actor, nil, 'replace_vehicle', ('model=%s'):format(pending.model))
    notify(actorSource, ('Veiculo atual substituido por %s.'):format(pending.model), 'success')
end)

RegisterNetEvent('ob_admin:server:setRole', function(targetSource, role)
    local actorSource = source
    if not hasPermission(actorSource, 'roles.manage') then
        notify(actorSource, 'Somente o owner pode alterar cargos.', 'error')
        return
    end

    targetSource = tonumber(targetSource)
    local target = targetSource and getCorePlayer(targetSource)
    local character = target and target.character
    if not target or not character then
        notify(actorSource, 'O jogador ainda nao selecionou um personagem.', 'error')
        return
    end
    if AdminDatabase.getCharacterRole(character.userId) == 'owner' then
        notify(actorSource, 'O cargo owner nao pode ser alterado pelo painel.', 'error')
        return
    end
    if type(role) ~= 'string' or role:lower() == 'owner' then
        notify(actorSource, 'Owner so pode ser definido pelo console do txAdmin.', 'error')
        return
    end
    if not canTarget(actorSource, targetSource) or not outranks(actorSource, role:lower()) then
        return notify(actorSource, 'Voce so pode gerenciar cargos abaixo do seu.', 'error')
    end

    local actor = getCorePlayer(actorSource)
    local actorUserId = actor and actor.character and actor.character.userId
    local success, message = AdminDatabase.grantCharacterAdmin(character.userId, role, actorUserId)
    if success then
        AdminDatabase.record(actor, target, 'set_role', ('role=%s'):format(role:lower()))
        message = ('Cargo de %s definido como %s.'):format(characterName(target), ORAdminConfig.Roles[role:lower()].label)
    end
    notify(actorSource, message, success and 'success' or 'error')
    if success then TriggerClientEvent('ob_admin:client:actionResult', actorSource) end
end)

local function grantCharacterAdmin(actorSource, userId)
    if not outranks(actorSource, AdminDatabase.getCharacterRole(userId)) or not outranks(actorSource, 'admin') then
        return false, 'Voce so pode conceder cargos abaixo do seu e a personagens inferiores.'
    end
    local actor = getCorePlayer(actorSource)
    local actorUserId = actor and actor.character and actor.character.userId or nil
    local success, message = AdminDatabase.grantCharacterAdmin(userId, 'admin', actorUserId)
    if success then
        AdminDatabase.record(actor, nil, 'grant_admin', ('user_id=%s'):format(tonumber(userId)))
        return true, ('O personagem de ID fixo %s agora possui acesso administrativo.'):format(tonumber(userId))
    end
    return false, message
end

local function revokeCharacterAdmin(actorSource, userId)
    if not outranks(actorSource, AdminDatabase.getCharacterRole(userId)) then
        return false, 'Voce nao pode remover acesso de um cargo igual/superior ao seu.'
    end
    local actor = getCorePlayer(actorSource)
    local actorUserId = actor and actor.character and actor.character.userId or nil
    if actorUserId and actorUserId == tonumber(userId) and not exports.ob_core:IsAdmin(actorSource) then
        return false, 'Voce nao pode remover seu proprio ultimo acesso administrativo.'
    end

    local success, removedOrMessage = AdminDatabase.revokeCharacterAdmin(userId)
    if not success then return false, removedOrMessage end
    if not removedOrMessage then return false, 'Esse personagem nao possuia permissao administrativa.' end

    AdminDatabase.record(actor, nil, 'revoke_admin', ('user_id=%s'):format(tonumber(userId)))
    return true, ('O acesso administrativo do personagem de ID fixo %s foi removido.'):format(tonumber(userId))
end

RegisterNetEvent('ob_admin:server:requestCharacterId', function()
    local player = getCorePlayer(source)
    local character = player and player.character
    if not character then
        notify(source, 'Selecione um personagem antes de consultar o ID fixo.', 'error')
        return
    end
    notify(source, ('Seu ID fixo de personagem: %s'):format(character.userId), 'info')
end)

RegisterNetEvent('ob_admin:server:grantCharacterAdmin', function(userId)
    local actorSource = source
    if not hasPermission(actorSource, 'roles.manage') then
        notify(actorSource, 'Somente o owner pode adicionar administradores.', 'error')
        return
    end

    local success, message = grantCharacterAdmin(actorSource, userId)
    notify(actorSource, message, success and 'success' or 'error')
end)

RegisterNetEvent('ob_admin:server:revokeCharacterAdmin', function(userId)
    local actorSource = source
    if not hasPermission(actorSource, 'roles.manage') then
        notify(actorSource, 'Somente o owner pode remover administradores.', 'error')
        return
    end

    local success, message = revokeCharacterAdmin(actorSource, userId)
    notify(actorSource, message, success and 'success' or 'error')
end)

-- Entrega administrativa. O catalogo e a persistencia continuam no
-- ob_inventory; permissao e auditoria pertencem ao ob_admin.
local GIVE_ITEM_MAXIMUM = 1000000
local GIVE_CURRENCY_MAXIMUM = 1000000000

RegisterCommand('giveitem', function(playerSource, args)
    playerSource = tonumber(playerSource) or 0
    if playerSource <= 0 then
        print('[ob_admin] /giveitem deve ser usado dentro do jogo por um administrador.')
        return
    end
    if not hasPermission(playerSource, 'inventory.give') then
        notify(playerSource, 'Seu cargo nao possui permissao para entregar itens.', 'error')
        return
    end

    -- O primeiro argumento e o ID fixo do personagem, nunca o source da
    -- sessao. O source muda a cada entrada no servidor.
    local targetUserId = math.floor(tonumber(args[1]) or 0)
    local targetSource = targetUserId > 0 and exports.ob_core:GetSourceByUserId(targetUserId) or nil
    local itemName = type(args[2]) == 'string' and args[2]:lower() or ''
    local amount = math.floor(tonumber(args[3]) or 1)
    local maximum = (itemName == 'money' or itemName == 'black_money')
        and GIVE_CURRENCY_MAXIMUM or GIVE_ITEM_MAXIMUM
    if not targetSource or not GetPlayerName(targetSource) or not itemName:match('^[a-z0-9_]+$') or amount < 1 or amount > maximum then
        notify(playerSource, ('Uso: /giveitem [ID fixo] [item] [quantidade de 1 a %s]. O personagem precisa estar na cidade.'):format(maximum), 'error')
        return
    end

    local added, errorMessage = exports.ob_inventory:AddItem(targetSource, itemName, amount)
    if not added then
        notify(playerSource, errorMessage or 'Nao foi possivel entregar o item.', 'error')
        return
    end

    local actor = getCorePlayer(playerSource)
    local target = getCorePlayer(targetSource)
    AdminDatabase.record(actor, target, 'give_item', ('item=%s amount=%s'):format(itemName, amount))
    notify(playerSource, ('Entregue: %sx %s para ID fixo %s.'):format(amount, itemName, targetUserId), 'success')
    if targetSource ~= playerSource then
        notify(targetSource, ('Voce recebeu %sx %s de um administrador.'):format(amount, itemName), 'success')
    end
end, false)

RegisterCommand('oradmin_add', function(playerSource, args)
    local userId = args[1]
    if not userId then
        print('[ob_admin] Uso: oradmin_add <user_id>')
        return
    end

    playerSource = tonumber(playerSource) or 0
    if playerSource == 0 then
        local success, message = AdminDatabase.grantCharacterAdmin(userId, 'admin', nil)
        print(('[ob_admin] %s'):format(message))
        return
    end

    if not hasPermission(playerSource, 'roles.manage') then
        notify(playerSource, 'Somente o owner pode adicionar administradores.', 'error')
        return
    end

    local success, message = grantCharacterAdmin(playerSource, userId)
    notify(playerSource, message, success and 'success' or 'error')
end, false)

-- Exclusivo do console do txAdmin. Recebe o ID temporario da sessao e grava
-- a permissao no user_id fixo do personagem que esta selecionado.
RegisterCommand('oradmin_addsource', function(playerSource, args)
    playerSource = tonumber(playerSource) or 0
    if playerSource ~= 0 then
        notify(playerSource, 'Esse comando so pode ser usado no console do txAdmin.', 'error')
        return
    end

    local targetSource = tonumber(args[1])
    if not targetSource or targetSource <= 0 then
        print('[ob_admin] Uso: oradmin_addsource <id_da_sessao>')
        return
    end

    local target = getCorePlayer(targetSource)
    local character = target and target.character
    if not character then
        print('[ob_admin] O jogador ainda nao selecionou um personagem. Entre na cidade e tente novamente.')
        return
    end

    local success, message = AdminDatabase.grantCharacterAdmin(character.userId, 'admin', nil)
    print(('[ob_admin] %s'):format(success and ('O personagem %s (ID fixo %s) agora possui acesso administrativo.'):format(characterName(target), character.userId) or message))
end, false)

-- O console do txAdmin e o unico meio de definir owner. Isso impede que um
-- owner promovido por engano transforme outro personagem em owner pelo painel.
RegisterCommand('oradmin_setrole', function(playerSource, args)
    playerSource = tonumber(playerSource) or 0
    if playerSource ~= 0 then
        notify(playerSource, 'Use o painel para cargos; este comando e exclusivo do console do txAdmin.', 'error')
        return
    end

    local userId, role = args[1], args[2]
    if not userId or not role then
        print('[ob_admin] Uso: oradmin_setrole <user_id> <owner|admin|dev|staff|var>')
        return
    end

    local success, message = AdminDatabase.grantCharacterAdmin(userId, role, nil)
    print(('[ob_admin] %s'):format(success and ('Cargo do personagem de ID fixo %s definido como %s.'):format(tonumber(userId), role:lower()) or message))
end, false)

RegisterCommand('oradmin_setrolesource', function(playerSource, args)
    playerSource = tonumber(playerSource) or 0
    if playerSource ~= 0 then
        notify(playerSource, 'Esse comando so pode ser usado no console do txAdmin.', 'error')
        return
    end

    local targetSource, role = tonumber(args[1]), args[2]
    if not targetSource or not role then
        print('[ob_admin] Uso: oradmin_setrolesource <id_da_sessao> <owner|admin|dev|staff|var>')
        return
    end

    local target = getCorePlayer(targetSource)
    local character = target and target.character
    if not character then
        print('[ob_admin] O jogador ainda nao selecionou um personagem.')
        return
    end

    local success, message = AdminDatabase.grantCharacterAdmin(character.userId, role, nil)
    print(('[ob_admin] %s'):format(success and ('Cargo de %s (ID fixo %s) definido como %s.'):format(characterName(target), character.userId, role:lower()) or message))
end, false)

RegisterCommand('oradmin_remove', function(playerSource, args)
    local userId = args[1]
    if not userId then
        print('[ob_admin] Uso: oradmin_remove <user_id>')
        return
    end

    playerSource = tonumber(playerSource) or 0
    if playerSource == 0 then
        local success, removedOrMessage = AdminDatabase.revokeCharacterAdmin(userId)
        local message = success and (removedOrMessage and ('O acesso administrativo do personagem de ID fixo %s foi removido.'):format(tonumber(userId)) or 'Esse personagem nao possuia permissao administrativa.') or removedOrMessage
        print(('[ob_admin] %s'):format(message))
        return
    end

    if not hasPermission(playerSource, 'roles.manage') then
        notify(playerSource, 'Somente o owner pode remover administradores.', 'error')
        return
    end

    local success, message = revokeCharacterAdmin(playerSource, userId)
    notify(playerSource, message, success and 'success' or 'error')
end, false)

AddEventHandler('playerDropped', function()
    lastActionAt[source] = nil
    pendingVehicleSpawns[source] = nil
end)
