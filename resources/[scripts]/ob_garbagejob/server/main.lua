local config = GarbageServerConfig
local sharedConfig = GarbageSharedConfig

assert(config and sharedConfig, '[ob_garbagejob] Configuracoes nao foram carregadas pelo fxmanifest.')

local routes = {} -- routes[leaderSource]
local crews = {} -- crews[leaderSource] = { members = { [source] = true } }
local memberCrew = {} -- memberCrew[source] = leaderSource
local pendingInvites = {}
local databaseReady = false

local function characterIdColumnType()
    local deadline = GetGameTimer() + 30000
    repeat
        local columnType = exports.ob_core:GetCharacterIdColumnType()
        if columnType then return columnType end
        Wait(100)
    until GetGameTimer() >= deadline
end

local function getUserId(source)
    return exports.ob_core:GetUserId(source)
end

local function getLeader(source)
    return memberCrew[source] or source
end

local function getCrew(source, create)
    local leader = getLeader(source)
    local crew = crews[leader]
    if not crew and create then
        crew = { leader = leader, members = { [leader] = true } }
        crews[leader] = crew
        memberCrew[leader] = leader
    end
    return leader, crew
end

local function crewSources(leader)
    local crew = crews[leader]
    local sources = {}
    if crew then
        for source in pairs(crew.members) do
            if getUserId(source) then
                sources[#sources + 1] = source
            else
                crew.members[source] = nil
                memberCrew[source] = nil
            end
        end
    end
    return sources
end

local function crewSize(leader)
    return #crewSources(leader)
end

local function getLevelFromXp(xp)
    local progress = config.progress
    return math.min(math.floor((tonumber(xp) or 0) / progress.levelStep) + 1, progress.maxLevel)
end

local function ensureProgress(userId)
    userId = tonumber(userId)
    if not databaseReady or not userId then return nil end

    OR.Database.update.await([[INSERT IGNORE INTO ob_garbage_progress
        (user_id, xp, level, routes_completed, total_earned) VALUES (?, 0, 1, 0, 0)]], { userId })

    local row = OR.Database.single.await('SELECT * FROM ob_garbage_progress WHERE user_id = ?', { userId })
    if row then
        local expectedLevel = getLevelFromXp(row.xp)
        if row.level ~= expectedLevel then
            row.level = expectedLevel
            OR.Database.update.await('UPDATE ob_garbage_progress SET level = ? WHERE user_id = ?', { expectedLevel, userId })
        end
    end
    return row
end

local function getPlayerDisplayName(firstname, lastname, userId)
    local first = type(firstname) == 'string' and firstname or ''
    local last = type(lastname) == 'string' and lastname or ''
    local name = (first .. ' ' .. last):gsub('^%s*(.-)%s*$', '%1')
    return name ~= '' and name or ('ID %s'):format(userId or '?')
end

local function fetchLeaderboard(userId, progressRow)
    local xpRows = OR.Database.query.await([[ 
        SELECT t.user_id, t.xp, t.routes_completed, p.firstname, p.lastname
        FROM ob_garbage_progress t
        LEFT JOIN ob_characters p ON p.user_id = t.user_id
        ORDER BY t.xp DESC, t.routes_completed DESC, t.user_id ASC
        LIMIT 25
    ]])

    local routeRows = OR.Database.query.await([[ 
        SELECT t.user_id, t.xp, t.routes_completed, p.firstname, p.lastname
        FROM ob_garbage_progress t
        LEFT JOIN ob_characters p ON p.user_id = t.user_id
        ORDER BY t.routes_completed DESC, t.xp DESC, t.user_id ASC
        LIMIT 25
    ]])

    local function buildList(rows)
        local list = {}
        for rank, row in ipairs(rows or {}) do
            list[#list + 1] = {
                rank = rank,
                name = getPlayerDisplayName(row.firstname, row.lastname, row.user_id),
                xp = tonumber(row.xp) or 0,
                routes = tonumber(row.routes_completed) or 0
            }
        end
        return list
    end

    local myXp = tonumber(progressRow and progressRow.xp or 0) or 0
    local myRoutes = tonumber(progressRow and progressRow.routes_completed or 0) or 0
    local myXpRank, myRoutesRank = 0, 0
    if userId then
        local xpCount = OR.Database.single.await([[ 
            SELECT COUNT(*) AS total FROM ob_garbage_progress
            WHERE xp > ?
               OR (xp = ? AND routes_completed > ?)
               OR (xp = ? AND routes_completed = ? AND user_id < ?)
        ]], { myXp, myXp, myRoutes, myXp, myRoutes, userId })
        local routeCount = OR.Database.single.await([[ 
            SELECT COUNT(*) AS total FROM ob_garbage_progress
            WHERE routes_completed > ?
               OR (routes_completed = ? AND xp > ?)
               OR (routes_completed = ? AND xp = ? AND user_id < ?)
        ]], { myRoutes, myRoutes, myXp, myRoutes, myXp, userId })
        myXpRank = (tonumber(xpCount and xpCount.total) or 0) + 1
        myRoutesRank = (tonumber(routeCount and routeCount.total) or 0) + 1
    end

    return {
        xp = { list = buildList(xpRows), myRank = myXpRank, myValue = myXp },
        routes = { list = buildList(routeRows), myRank = myRoutesRank, myValue = myRoutes }
    }
end

local function groupPayload(source)
    local leader, crew = getCrew(source, false)
    if not crew then
        return {
            leader = source,
            isLeader = true,
            maxMembers = config.group.maxMembers,
            members = {{ id = source, name = GetPlayerName(source) or ('ID %s'):format(source), leader = true }}
        }
    end

    local members = {}
    for _, memberSource in ipairs(crewSources(leader)) do
        members[#members + 1] = {
            id = memberSource,
            name = GetPlayerName(memberSource) or ('ID %s'):format(memberSource),
            leader = memberSource == leader
        }
    end

    return {
        leader = leader,
        isLeader = source == leader,
        maxMembers = config.group.maxMembers,
        members = members
    }
end

local function routePayload(leader)
    local route = routes[leader]
    if not route then return nil end

    local current = route.stops[route.currentStop]
    local remainingBagsTotal = route.remainingBags or 0
    for stopIndex = (route.currentStop or 0) + 1, #route.stops do
        remainingBagsTotal = remainingBagsTotal + (route.stops[stopIndex].bags or 0)
    end
    return {
        active = not route.finished,
        finished = route.finished == true,
        nextStop = current and current.stop or 0,
        bags = route.remainingBags or 0,
        remainingBagsTotal = remainingBagsTotal,
        totalStops = route.totalStops or 0,
        completedStops = route.completedStops or 0,
        collectedBags = route.collectedBags or 0,
        vehicleNet = route.vehicleNet,
        leader = leader
    }
end

local function broadcastPanel(leader)
    for _, memberSource in ipairs(crewSources(leader)) do
        TriggerClientEvent('orbis-garbagejob:client:groupUpdated', memberSource, groupPayload(memberSource))
    end
end

local function broadcastRoute(leader)
    local payload = routePayload(leader)
    for _, memberSource in ipairs(crewSources(leader)) do
        TriggerClientEvent('orbis-garbagejob:client:syncRoute', memberSource, payload)
    end
end

local function createStops(memberCount)
    local maxStops = math.min(config.maxStops or #sharedConfig.locations.trashcan, #sharedConfig.locations.trashcan)
    local totalStops = math.random(math.min(config.minStops, maxStops), maxStops)
    local stops = {}
    local extraBags = math.max(0, memberCount - 1) * (config.group.extraBagsPerMember or 0)

    for _ = 1, totalStops do
        stops[#stops + 1] = {
            stop = math.random(#sharedConfig.locations.trashcan),
            bags = (math.random(100) <= (config.twoBagsChance or 50) and config.maxBagsPerStop or config.minBagsPerStop) + extraBags
        }
    end

    return stops
end

local function getTruckDeposit()
    return math.max(0, tonumber(sharedConfig.truckPrice) or 0)
end

local function canPayDeposit(source)
    local deposit = getTruckDeposit()
    -- Caminhao gratuito nao deve consultar nem remover o item de dinheiro.
    if deposit <= 0 then return true end

    return (exports.ob_inventory:GetItemCount(source, 'money') or 0) >= deposit
end

local function makePanelData(source)
    local userId = getUserId(source)
    local row = ensureProgress(userId)
    if not row then return nil end

    local leader = getLeader(source)
    local progress = config.progress
    local level = row.level or 1
    local levelBase = (level - 1) * progress.levelStep
    local paymentBonus = math.min((level - 1) * progress.paymentBonusPerLevel, progress.maxPaymentBonus)

    return {
        progress = {
            level = level,
            xp = row.xp or 0,
            xpInLevel = (row.xp or 0) - levelBase,
            xpRequired = progress.levelStep,
            routesCompleted = row.routes_completed or 0,
            totalEarned = row.total_earned or 0,
            paymentBonus = math.floor(paymentBonus * 100),
            paymentBonusStep = progress.paymentBonusPerLevel * 100
        },
        group = groupPayload(source),
        route = routePayload(leader),
        leaderboard = fetchLeaderboard(userId, row)
    }
end

local function payoutRoute(leader, continue)
    local route = routes[leader]
    if not route then return false, 'Nenhuma rota ativa.' end
    if not route.finished and not continue then return false, 'Conclua todas as paradas antes de receber.' end

    local sources = crewSources(leader)
    if #sources == 0 then
        if route.vehicleNet then exports.ob_core:DeleteTemporaryVehicle(leader, route.vehicleNet) end
        routes[leader] = nil
        return false, 'Nenhum membro do grupo esta online.'
    end

    local deposit = (route.finished and not continue) and route.depositPay or 0
    local baseShare = math.floor((route.actualPay or 0) / #sources)
    local xpGain = math.max(0, math.floor(route.collectedBags * config.progress.xpPerBag))

    for _, memberSource in ipairs(sources) do
        local userId = getUserId(memberSource)
        if userId then
            local row = ensureProgress(userId)
            if row then
                local bonus = math.min(math.max((row.level or 1) - 1, 0) * config.progress.paymentBonusPerLevel, config.progress.maxPaymentBonus)
                local reward = math.floor(baseShare * (1.0 + bonus))
                if memberSource == leader then reward = reward + deposit end
                -- O bonus do lider e intencionalmente interno: nao aparece na NUI.
                local memberXp = xpGain
                if memberSource == leader then
                    memberXp = math.ceil(memberXp * 1.02)
                end
                local newXp = (row.xp or 0) + memberXp
                local newLevel = getLevelFromXp(newXp)

                local paid = exports.ob_inventory:AddMoney(memberSource, 'money', reward)
                if not paid then
                    TriggerClientEvent('ob_notification:client:notify', memberSource, 'Pagamento pendente: mochila sem espaco.', 'error')
                else
                OR.Database.update.await([[UPDATE ob_garbage_progress
                    SET xp = ?, level = ?, routes_completed = routes_completed + ?, total_earned = total_earned + ?
                    WHERE user_id = ?]], {
                    newXp, newLevel, route.finished and 1 or 0, reward, userId
                })

                TriggerClientEvent('orbis-garbagejob:client:shiftPaid', memberSource, {
                    reward = reward,
                    xp = memberXp,
                    panel = makePanelData(memberSource)
                })
                end
            end
        end
    end

    routes[leader] = nil
    for _, memberSource in ipairs(sources) do
        TriggerClientEvent('orbis-garbagejob:client:shiftEnded', memberSource, leader)
    end
    return true
end

OR.Callback.register('garbagejob:server:getPanelData', function(source)
    return makePanelData(source)
end)

OR.Callback.register('garbagejob:server:newShift', function(source)
    if not getUserId(source) then return false, 'Jogador invalido.' end

    local leader, crew = getCrew(source, true)
    if source ~= leader then return false, 'Somente o lider pode iniciar a rota.' end
    if routes[leader] then return false, 'Ja existe uma rota ativa.' end
    local deposit = getTruckDeposit()
    if not canPayDeposit(source) then return false, ('Voce precisa de %s em dinheiro para o deposito.'):format(OR.FormatMoney(deposit)) end

    local stops = createStops(crewSize(leader))
    routes[leader] = {
        stops = stops,
        currentStop = 1,
        remainingBags = stops[1].bags,
        totalStops = #stops,
        completedStops = 0,
        collectedBags = 0,
        actualPay = 0,
        depositPay = deposit,
        depositCharged = false,
        vehicleNet = nil,
        finished = false
    }

    broadcastRoute(leader)
    return true, routePayload(leader)
end)

OR.Callback.register('garbagejob:server:spawnVehicle', function(source, coords)
    local leader = getLeader(source)
    local route = routes[leader]
    if source ~= leader or not route then return nil end

    -- O cliente apenas escolhe uma das vagas configuradas. Nunca usamos uma
    -- coordenada arbitraria recebida pela rede para criar a entidade.
    local approvedSpawn
    if coords and coords.x and coords.y and coords.z then
        for _, candidate in pairs(sharedConfig.locations.vehicle.coords or {}) do
            if #(vector3(coords.x, coords.y, coords.z) - candidate.xyz) <= 1.0 then approvedSpawn = candidate break end
        end
    end
    if not approvedSpawn then return nil end

    local deposit = getTruckDeposit()
    if deposit > 0 then
        local paidDeposit = exports.ob_inventory:RemoveItem(source, 'money', deposit)
        if not paidDeposit then
            return nil
        end
        route.depositCharged = true
    end

    local spawned, vehicleData = exports.ob_core:SpawnTemporaryVehicle(source, config.vehicle, approvedSpawn, {
        platePrefix = 'GBGE', fuel = 100.0, clearRadius = 2.5, maxDistance = 100.0,
        serverSetterType = 'automobile',
    })
    if not spawned then
        if deposit > 0 and exports.ob_inventory:AddMoney(source,'money',deposit) then route.depositCharged=false end
        TriggerClientEvent('ob_notification:client:notify', source, vehicleData or 'Nao foi possivel criar o caminhao.', 'error')
        return nil
    end

    route.vehicleNet = vehicleData.netId
    route.vehiclePlate = vehicleData.plate
    broadcastRoute(leader)
    return vehicleData.netId
end)

OR.Callback.register('garbagejob:server:cancelShift',function(source)
    if not OR.Security.rateLimit(source,'garbage:cancel_shift',1,3000) then return false,'Aguarde antes de cancelar novamente.' end
    local leader=getLeader(source)
    if source~=leader then return false,'Somente o lider pode cancelar a rota.' end
    local route=routes[leader]
    if not route then return false,'Nao existe rota ativa para cancelar.' end
    local members=crewSources(leader)
    if route.vehicleNet then exports.ob_core:DeleteTemporaryVehicle(leader,route.vehicleNet) end
    local refunded=0
    if route.depositCharged and (tonumber(route.depositPay) or 0)>0 then
        refunded=tonumber(route.depositPay) or 0
        if not exports.ob_inventory:AddMoney(leader,'money',refunded) then
            TriggerClientEvent('ob_notification:client:notify',leader,'Nao foi possivel devolver o deposito: libere espaco na mochila e procure a administracao.','error')
            refunded=0
        end
    end
    routes[leader]=nil
    for _,member in ipairs(members) do TriggerClientEvent('orbis-garbagejob:client:shiftEnded',member,leader) end
    print(('[ob_garbagejob] CANCEL leader=%s collected=%s deposit_refund=%s'):format(leader,route.collectedBags or 0,refunded))
    return true,refunded>0 and ('Rota cancelada. Deposito de %s devolvido.'):format(OR.FormatMoney(refunded)) or 'Rota cancelada sem pagamento.'
end)

OR.Callback.register('garbagejob:server:depositBag', function(source)
    if not OR.Security.rateLimit(source, 'garbage:deposit_bag', 1, 1500) then return false, 'Aguarde antes de colocar outro saco.' end
    local leader = getLeader(source)
    local route = routes[leader]
    if not route or route.finished then return false, 'Nao ha rota ativa.' end

    local current = route.stops[route.currentStop]
    local playerPed = GetPlayerPed(source)
    if not current or playerPed == 0 then return false, 'Parada invalida.' end

    local playerCoords = GetEntityCoords(playerPed)
    if #(playerCoords - sharedConfig.locations.trashcan[current.stop].coords.xyz) > 30.0 then
        return false, 'Voce esta muito longe do ponto de entrega.'
    end

    if route.remainingBags <= 0 then return false, 'Esta parada ja foi concluida.' end

    route.remainingBags = route.remainingBags - 1
    route.collectedBags = route.collectedBags + 1
    route.actualPay = route.actualPay + math.random(config.bagLowerWorth, config.bagUpperWorth)

    if route.remainingBags > 0 then
        broadcastRoute(leader)
        return true, routePayload(leader)
    end

    route.completedStops = route.completedStops + 1
    -- Mantem a recompensa adicional do script original para quem concluiu a parada.
    if config.giveItemReward and math.random(100) >= config.itemRewardChance then
        if getUserId(source) then
            local awarded = exports.ob_inventory:AddItem(source, config.itemRewardName, 1)
            if awarded then TriggerClientEvent('ob_notification:client:notify', source, 'Voce encontrou um item na coleta.', 'success') end
        end
    end
    if route.currentStop >= route.totalStops then
        route.finished = true
    else
        route.currentStop = route.currentStop + 1
        route.remainingBags = route.stops[route.currentStop].bags
    end

    broadcastRoute(leader)
    return true, routePayload(leader)
end)

OR.Callback.register('garbagejob:server:finishShift', function(source)
    local leader = getLeader(source)
    if source ~= leader then return false, 'Somente o lider pode finalizar a rota.' end
    return false, 'Leve o caminhao ao ponto de descarga para finalizar.'
end)

OR.Callback.register('garbagejob:server:unloadRoute', function(source, clientVehicleNet)
    if not OR.Security.rateLimit(source, 'garbage:unload_route', 1, 5000) then return false, 'Aguarde antes de descarregar novamente.' end
    local leader = getLeader(source)
    local route = routes[leader]
    if source ~= leader or not route or not route.finished then
        return false, 'A rota ainda nao esta pronta para descarga.'
    end

    local unload = sharedConfig.locations.unload
    local playerPed = GetPlayerPed(source)
    if not unload or playerPed == 0 then return false, 'Ponto de descarga indisponivel.' end

    local maxDistance = (unload.radius or 8.0) + 3.0
    if #(GetEntityCoords(playerPed) - unload.coords.xyz) > maxDistance then
        return false, 'Estacione o caminhao dentro do ponto de descarga.'
    end

    -- A entidade pode migrar para o cliente; tenta tanto o netId salvo quanto
    -- o netId atual enviado pelo motorista sem bloquear o pagamento por isso.
    local vehicle = 0
    local vehicleNetIds = { route.vehicleNet, tonumber(clientVehicleNet) }
    for index = 1, 2 do
        local netId = vehicleNetIds[index]
        if netId and netId > 0 then
            local candidate = NetworkGetEntityFromNetworkId(netId)
            if candidate ~= 0 and DoesEntityExist(candidate) then
                vehicle = candidate
                break
            end
        end
    end
    if vehicle ~= 0 and #(GetEntityCoords(vehicle) - unload.coords.xyz) > maxDistance then
        return false, 'Estacione o caminhao dentro do ponto de descarga.'
    end

    local jobVehicleNet = route.vehicleNet
    local paid, message = payoutRoute(leader, false)
    if paid and vehicle ~= 0 then
        exports.ob_core:DeleteTemporaryVehicle(leader, jobVehicleNet)
    end
    return paid, message
end)

OR.Callback.register('garbagejob:server:inviteMember', function(source, targetSource)
    targetSource = tonumber(targetSource)
    local leader, crew = getCrew(source, true)
    if source ~= leader then return false, 'Somente o lider pode convidar.' end
    if not targetSource or targetSource == source or not getUserId(targetSource) then return false, 'Jogador invalido.' end
    if memberCrew[targetSource] then return false, 'Esse jogador ja esta em um grupo.' end
    if crewSize(leader) >= config.group.maxMembers then return false, 'O grupo ja esta cheio.' end

    local leaderPed, targetPed = GetPlayerPed(source), GetPlayerPed(targetSource)
    if leaderPed == 0 or targetPed == 0 or #(GetEntityCoords(leaderPed) - GetEntityCoords(targetPed)) > config.group.inviteDistance then
        return false, 'O jogador precisa estar proximo.'
    end

    pendingInvites[targetSource] = { leader = leader, expires = os.time() + 30 }
    TriggerClientEvent('orbis-garbagejob:client:groupInvite', targetSource, {
        leader = leader,
        name = GetPlayerName(source) or ('ID %s'):format(source)
    })
    return true
end)

OR.Callback.register('garbagejob:server:answerInvite', function(source, accept)
    local invite = pendingInvites[source]
    pendingInvites[source] = nil
    if not invite or invite.expires < os.time() or not crews[invite.leader] then return false, 'Convite expirado.' end
    if not accept then return true, 'Convite recusado.' end

    local crew = crews[invite.leader]
    if memberCrew[source] or crewSize(invite.leader) >= config.group.maxMembers then return false, 'Grupo indisponivel.' end
    crew.members[source] = true
    memberCrew[source] = invite.leader
    local route = routes[invite.leader]
    if route and route.vehiclePlate then
        TriggerClientEvent('vehiclekeys:client:SetOwner', source, route.vehiclePlate)
    end
    broadcastPanel(invite.leader)
    if route then broadcastRoute(invite.leader) end
    return true, 'Voce entrou no grupo.'
end)

OR.Callback.register('garbagejob:server:leaveGroup', function(source)
    local leader, crew = getCrew(source, false)
    if not crew then return true end
    if routes[leader] then return false, 'Finalize a rota antes de sair do grupo.' end

    if source == leader then
        for memberSource in pairs(crew.members) do
            memberCrew[memberSource] = nil
            TriggerClientEvent('orbis-garbagejob:client:groupUpdated', memberSource, groupPayload(memberSource))
        end
        crews[leader] = nil
    else
        crew.members[source] = nil
        memberCrew[source] = nil
        TriggerClientEvent('orbis-garbagejob:client:groupUpdated', source, groupPayload(source))
        broadcastPanel(leader)
    end
    return true
end)

AddEventHandler('playerDropped', function()
    local source = source
    pendingInvites[source] = nil
    local leader, crew = getCrew(source, false)
    if not crew then return end

    if source == leader then
        crew.members[source] = nil
        memberCrew[source] = nil

        local nextLeader
        for memberSource in pairs(crew.members) do
            if getUserId(memberSource) then
                nextLeader = memberSource
                break
            end
            crew.members[memberSource] = nil
            memberCrew[memberSource] = nil
        end

        if nextLeader then
            crews[leader] = nil
            crew.leader = nextLeader
            crews[nextLeader] = crew
            for memberSource in pairs(crew.members) do
                memberCrew[memberSource] = nextLeader
            end

            local route = routes[leader]
            routes[leader] = nil
            if route then
                routes[nextLeader] = route
                if route.vehicleNet then
                    local granted, keyError = exports.ob_vehiclekeys:GrantTemporaryKey(nextLeader, route.vehicleNet)
                    if not granted then
                        TriggerClientEvent('ob_notification:client:notify', nextLeader,
                            keyError or 'Nao foi possivel receber a chave do caminhao.', 'error')
                    end
                end
            end
            broadcastPanel(nextLeader)
            if route then broadcastRoute(nextLeader) end
        else
            crews[leader] = nil
            local route = routes[leader]
            if route and route.vehicleNet then exports.ob_core:DeleteTemporaryVehicle(leader, route.vehicleNet) end
            routes[leader] = nil
        end
    else
        crew.members[source] = nil
        memberCrew[source] = nil
        broadcastPanel(leader)
    end
end)

CreateThread(function()
    if not OR.Database.waitForReady(30000) then
        print('[ob_garbagejob] Banco indisponivel; emprego nao iniciado.')
        return
    end
    local userIdType = characterIdColumnType()
    if not userIdType then
        print('[ob_garbagejob] Tipo de ob_characters.user_id indisponivel.')
        return
    end
    local created, errorMessage = OR.Database.query.await(([[CREATE TABLE IF NOT EXISTS ob_garbage_progress (
        user_id %s NOT NULL PRIMARY KEY,
        xp INT NOT NULL DEFAULT 0,
        level INT NOT NULL DEFAULT 1,
        routes_completed INT NOT NULL DEFAULT 0,
        total_earned INT NOT NULL DEFAULT 0,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        CONSTRAINT fk_ob_garbage_progress_character FOREIGN KEY (user_id) REFERENCES ob_characters(user_id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]]):format(userIdType))
    databaseReady = created ~= nil
    if not databaseReady then print(('[ob_garbagejob] Falha ao criar tabela: %s'):format(errorMessage or 'desconhecida')) end
end)
