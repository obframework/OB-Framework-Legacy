local playerOptions = {}
local entityOptions = {}
local zoneOptions = {}
local shownOptionId, lastTargetShowAt
local targetActive = false
local currentOption
local targetNuiFocused = false
local targetFocusPending = false
local indicatorVisible = false
local indicatorActive = false
local debugTargets = false
local suppressAttackUntil = 0
local rays
local lastRayEntity, lastRayAt
local nextScanAt = 0
local function callable(value)
    if type(value) == 'function' then return true end
    if type(value) ~= 'table' then return false end
    local mt = getmetatable(value)
    return type(rawget(value, '__cfx_functionReference')) == 'string'
        or (type(mt) == 'table' and type(mt.__call) == 'function')
end

local function notify(message, kind)
    if OR and OR.Notify then
        OR.Notify(message, kind or 'inform')
    end
end

local function hideTarget()
    if not shownOptionId then return end
    shownOptionId = nil
    lastTargetShowAt = nil
    SendNUIMessage({ action = 'hide' })
end

local function setTargetFocus(enabled)
    enabled = enabled == true
    if targetNuiFocused == enabled then return end
    targetNuiFocused = enabled
    suppressAttackUntil = GetGameTimer() + 350
    if not enabled then targetFocusPending = false end
    SetNuiFocus(enabled, enabled)
    SetNuiFocusKeepInput(false)
    if enabled and ORTargetConfig.CenterCursorOnOption ~= false then
        local width = GetActiveScreenResolution()
        SetCursorLocation(math.min(0.95, 0.5 + 142 / math.max(1, width)), 0.5)
    end
end

local function setIndicator(visible, active)
    visible = visible == true
    active = active == true
    if indicatorVisible == visible and indicatorActive == active then return end
    indicatorVisible, indicatorActive = visible, active
    SendNUIMessage({ action = 'indicator', visible = visible, active = active })
end

local function showTarget(target)
    local option, choices, ids = target.option, {}, {}
    for _, entry in ipairs(target.choices or {target.option}) do
        choices[#choices+1] = {id = entry.id, label = entry.label, icon = entry.icon or '+'}
        ids[#ids+1] = entry.id
    end
    local signature = table.concat(ids, '|') .. ':' .. tostring(target.entity or target.targetSource or '')
    local now = GetGameTimer()
    -- Reenvia periodicamente enquanto o alvo continua valido. Em Legacy e
    -- Enhanced a mensagem inicial pode coincidir com a troca de foco/estado
    -- da NUI; antes o cache mantinha apenas o indicador aceso para sempre.
    if shownOptionId == signature and lastTargetShowAt and now - lastTargetShowAt < 250 then return end
    shownOptionId = signature
    lastTargetShowAt = now
    SendNUIMessage({
        action = 'show',
        options = choices,
        label = option.label,
        icon = option.icon or '+',
    })
end

local function rotationToDirection(rotation)
    local radians = {
        x = math.rad(rotation.x),
        y = math.rad(rotation.y),
        z = math.rad(rotation.z),
    }

    return vector3(
        -math.sin(radians.z) * math.abs(math.cos(radians.x)),
        math.cos(radians.z) * math.abs(math.cos(radians.x)),
        math.sin(radians.x)
    )
end

local function getLookedEntity(distance)
    local origin = GetGameplayCamCoord()
    local direction = rotationToDirection(GetGameplayCamRot(2))
    local destination = origin + (direction * distance)

    local now = GetGameTimer()
    if rays then
        local dot = direction.x*rays.direction.x + direction.y*rays.direction.y + direction.z*rays.direction.z
        if #(origin-rays.origin)>0.5 or dot<0.995 or now-rays.started>250 then
            rays, lastRayEntity = nil, nil
        end
    end
    if rays then
        local finished = true
        for _, probe in ipairs(rays.probes) do
            if not probe.done then
                local status, hit, _, _, entity = GetShapeTestResult(probe.handle)
                if status ~= 1 then
                    probe.done = true
                    -- Somente status 2 tem resultado valido. BOOL pode chegar
                    -- como boolean no Lua, nao apenas como o numero 1.
                    if status == 2 and (hit == true or hit == 1) and entity and entity>0 then probe.entity=entity end
                end
            end
            if not probe.done then finished=false end
        end
        local candidate=rays.probes[1].entity or rays.probes[2].entity
        if candidate then
            lastRayEntity,lastRayAt=candidate,now
        end
        if finished then
            lastRayEntity = rays.probes[1].entity or rays.probes[2].entity
            lastRayAt, rays = now, nil
        end
    end
    -- Testes paralelos, sem Wait: a procura nunca bloqueia o frame do clique.
    if not rays then
        rays={started=now,origin=origin,direction=direction,probes={}}
        for _, flags in ipairs({511,26}) do
            rays.probes[#rays.probes+1]={handle=StartShapeTestLosProbe(
                origin.x,origin.y,origin.z,destination.x,destination.y,destination.z,flags,PlayerPedId(),4)}
        end
    end
    if lastRayEntity and now-(lastRayAt or 0)<=100 and DoesEntityExist(lastRayEntity) then return lastRayEntity end
end

local function getPlayerFromPed(ped)
    if not ped or ped <= 0 or not IsEntityAPed(ped) then return nil end

    local playerIndex = NetworkGetPlayerIndexFromPed(ped)
    if playerIndex and playerIndex >= 0 and NetworkIsPlayerActive(playerIndex) then return playerIndex end

    for _, activePlayer in ipairs(GetActivePlayers()) do
        if GetPlayerPed(activePlayer) == ped then return activePlayer end
    end
end

local function canUsePlayerOption(option, targetPlayer, targetPed)
    if type(option) ~= 'table' or type(option.event) ~= 'string' then return false end
    local targetSource = GetPlayerServerId(targetPlayer)
    if targetSource <= 0 then return false end
    if option.stateKey and Player(targetSource).state[option.stateKey] ~= option.stateValue then return false end
    if option.canInteract ~= nil then
        if not callable(option.canInteract) then return false end
        local ok, allowed = pcall(option.canInteract, targetSource, targetPed)
        if not ok or allowed ~= true then return false end
    end

    local maximumDistance = tonumber(option.distance) or ORTargetConfig.DefaultDistance
    local firstCoords = GetEntityCoords(PlayerPedId())
    local secondCoords = GetEntityCoords(targetPed)
    return #(firstCoords - secondCoords) <= maximumDistance
end

local function canUseEntityOption(option, entity)
    if type(option) ~= 'table' or (type(option.event) ~= 'string' and not callable(option.action)) then return false end
    if option.entity and option.entity ~= entity then return false end
    if option.netId and NetworkGetNetworkIdFromEntity(entity) ~= option.netId then return false end
    if option.entityType and GetEntityType(entity) ~= option.entityType then return false end
    if option.model and GetEntityModel(entity) ~= option.model then return false end

    local maximumDistance = tonumber(option.distance) or ORTargetConfig.DefaultDistance
    if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(entity)) > maximumDistance then return false end
    if option.canInteract ~= nil then
        if not callable(option.canInteract) then return false end
        local ok, allowed = pcall(option.canInteract, entity)
        if not ok or allowed ~= true then return false end
    end
    return true
end

-- Entidades registradas por handle/NetID tambem sao avaliadas por projecao de
-- tela quando o shape test do Enhanced nao devolve o alvo diante da camera.
local function getEntityTargetPoint(entity, option)
    if option and callable(option.targetPoint) then
        local ok,custom=pcall(option.targetPoint,entity)
        if ok and custom and custom.x and custom.y and custom.z then return custom end
    end
    local coords = GetEntityCoords(entity)
    local entityType = GetEntityType(entity)

    if entityType == 1 then
        -- Use o torax real: adicionar uma altura fixa ao ped caido aponta
        -- acima do paciente, dificultando selecionar o atendimento no chao.
        local bone = GetPedBoneCoords(entity, 24818, 0.0, 0.0, 0.0)
        if bone then return bone end
        return vector3(coords.x, coords.y, coords.z + 0.65)
    end

    if entityType == 2 then
        return GetOffsetFromEntityInWorldCoords(entity, 0.0, 0.0, 0.45)
    end

    return coords
end

local function isEntityNearReticle(entity, origin, direction, option)
    local targetPoint = getEntityTargetPoint(entity, option)

    -- Em camera de terceira pessoa a camera pode ficar mais de 4 metros do
    -- ped, mesmo quando o jogador esta dentro da distancia de interacao.
    -- A projecao da posicao do torso na tela e a verificacao mais fiel de que
    -- a mira esta no NPC e nao depende do alcance da camera/raycast.
    local onScreen, screenX, screenY = World3dToScreen2d(targetPoint.x, targetPoint.y, targetPoint.z)
    if onScreen then
        local dx, dy = screenX - 0.5, screenY - 0.5
        local screenDistance = math.sqrt(dx * dx + dy * dy)
        local screenRadius=math.max(0.005,math.min(0.25,tonumber(option and option.screenRadius) or 0.09))
        if screenDistance <= screenRadius then return true, 1.0 - screenDistance end
    end

    local offset = targetPoint - origin
    local length = #offset
    if length <= 0.01 or length > ORTargetConfig.MaxRayDistance then return false end

    local dot = (offset.x * direction.x + offset.y * direction.y + offset.z * direction.z) / length
    local minimumDot=math.max(0.5,math.min(0.9999,tonumber(option and option.minimumDot) or 0.88))
    return dot >= minimumDot, dot
end

local function getEntityNearReticle()
    local origin = GetGameplayCamCoord()
    local direction = rotationToDirection(GetGameplayCamRot(2))
    local bestEntity, bestOption, bestDot
    local candidates, seen = {}, {}

    local function addCandidate(entity)
        if not entity or entity <= 0 or seen[entity] or not DoesEntityExist(entity) then return end
        seen[entity] = true
        candidates[#candidates + 1] = entity
    end

    -- Entidades registradas pelo handle ou network id nao dependem do pool.
    for _, option in pairs(entityOptions) do
        addCandidate(option.entity)
        if option.netId then addCandidate(NetworkGetEntityFromNetworkId(option.netId)) end
    end

    -- Nao enumere pools globais no Enhanced. Opcoes por modelo continuam
    -- funcionando pelo shape test; a reserva usa apenas handle/NetID registrado.

    for _, entity in ipairs(candidates) do
        for _, option in pairs(entityOptions) do
            if canUseEntityOption(option, entity) then
                local nearReticle, dot = isEntityNearReticle(entity, origin, direction, option)
                if nearReticle and (not bestDot or dot > bestDot) then
                    bestEntity, bestOption, bestDot = entity, option, dot
                end
            end
        end
    end

    return bestEntity, bestOption
end

local function getPlayerNearReticle()
    local origin = GetGameplayCamCoord()
    local direction = rotationToDirection(GetGameplayCamRot(2))
    local bestPlayer, bestPed, bestOption, bestDot

    -- GetActivePlayers e uma lista curta e segura nas duas versoes. Este
    -- fallback evita depender do shape test para reconhecer peds de jogador.
    for _, playerIndex in ipairs(GetActivePlayers()) do
        if playerIndex ~= PlayerId() and NetworkIsPlayerActive(playerIndex) then
            local ped = GetPlayerPed(playerIndex)
            if ped and ped > 0 and DoesEntityExist(ped) then
                local nearReticle, dot = isEntityNearReticle(ped, origin, direction)
                if nearReticle then
                    for _, option in pairs(playerOptions) do
                        if canUsePlayerOption(option, playerIndex, ped) and (not bestDot or dot > bestDot) then
                            bestPlayer, bestPed, bestOption, bestDot = playerIndex, ped, option, dot
                        end
                    end
                end
            end
        end
    end

    return bestPlayer, bestPed, bestOption
end

local function pointInsideZone(zone, point)
    local coords = zone.coords
    if not coords then return false end
    if zone.kind == 'sphere' then
        return #(point - coords) <= (tonumber(zone.radius) or 1.0)
    end

    local size = zone.size or vector3(1.0, 1.0, 1.0)
    local rotation = math.rad(tonumber(zone.rotation) or 0.0)
    local dx, dy = point.x - coords.x, point.y - coords.y
    local localX = dx * math.cos(rotation) + dy * math.sin(rotation)
    local localY = -dx * math.sin(rotation) + dy * math.cos(rotation)
    return math.abs(localX) <= (size.x / 2)
        and math.abs(localY) <= (size.y / 2)
        and math.abs(point.z - coords.z) <= (size.z / 2 + 1.0)
end

local function canUseZoneOption(option, zone)
    if type(option) ~= 'table' or (type(option.event) ~= 'string' and not callable(option.action)) then return false end
    if not pointInsideZone(zone, GetEntityCoords(PlayerPedId())) then return false end
    if option.canInteract ~= nil then
        if not callable(option.canInteract) then return false end
        local ok, allowed = pcall(option.canInteract, zone.coords)
        if not ok or allowed ~= true then return false end
    end
    return true
end

local function playerTarget(playerIndex, ped)
    local choices = {}
    for _, option in pairs(playerOptions) do
        if canUsePlayerOption(option, playerIndex, ped) then choices[#choices+1] = option end
    end
    table.sort(choices, function(a,b) return a.id < b.id end)
    if #choices == 0 then return nil end
    return {option = choices[1], choices = choices, targetSource = GetPlayerServerId(playerIndex), entity = ped}
end

local function getActiveOption()
    if LocalPlayer.state['or:loaded'] ~= true
        or LocalPlayer.state['or:downed'] == true
        or LocalPlayer.state['or:restrained'] == true
        or LocalPlayer.state['ob:restrained'] == true
        or LocalPlayer.state['ob:takedown'] == true then return nil end
    if IsNuiFocused() and not targetNuiFocused then return nil end

    local entity = getLookedEntity(ORTargetConfig.MaxRayDistance)
    local playerIndex = getPlayerFromPed(entity)
    if playerIndex and playerIndex ~= PlayerId() then
        local selected = playerTarget(playerIndex, entity)
        if selected then return selected end
    end

    if entity then
        for _, option in pairs(entityOptions) do
            if canUseEntityOption(option, entity) then return { option = option, entity = entity } end
        end
    end

    local fallbackPlayer, fallbackPlayerPed, fallbackPlayerOption = getPlayerNearReticle()
    if fallbackPlayerOption then
        return playerTarget(fallbackPlayer, fallbackPlayerPed)
    end

    local fallbackEntity, fallbackOption = getEntityNearReticle()
    if fallbackOption then return { option = fallbackOption, entity = fallbackEntity } end

    for _, zone in pairs(zoneOptions) do
        for _, option in ipairs(zone.options) do
            if canUseZoneOption(option, zone) then return { option = option, zone = zone } end
        end
    end
end

local function addPlayerOption(id, option)
    if type(id) ~= 'string' or id == '' or type(option) ~= 'table' then
        return false, 'Identificador ou configuracao invalida.'
    end
    if type(option.label) ~= 'string' or option.label == '' or type(option.event) ~= 'string' or option.event == '' then
        return false, 'A opcao precisa de label e evento.'
    end

    option.id = id
    option.stateValue = option.stateValue == nil and true or option.stateValue
    playerOptions[id] = option
    return true
end

local function invalidateTargetOption(id)
    if not currentOption then return end
    for _, option in ipairs(currentOption.choices or {currentOption.option}) do
        if option.id == id then
            currentOption = nil
            targetActive = false
            hideTarget()
            setIndicator(false, false)
            setTargetFocus(false)
            return
        end
    end
end

local function removePlayerOption(id)
    playerOptions[id] = nil
    invalidateTargetOption(id)
end

local function addEntityOption(id, option)
    if type(id) ~= 'string' or id == '' or type(option) ~= 'table' then
        return false, 'Identificador ou configuracao invalida.'
    end
    if type(option.label) ~= 'string' or option.label == '' then
        return false, 'A opcao precisa de label.'
    end
    if type(option.event) ~= 'string' and not callable(option.action) then
        return false, 'A opcao precisa de evento ou acao.'
    end

    option.id = id
    entityOptions[id] = option
    return true
end

local function removeEntityOption(id)
    entityOptions[id] = nil
    invalidateTargetOption(id)
end

exports('AddPlayerOption', addPlayerOption)
exports('RemovePlayerOption', removePlayerOption)
exports('AddEntityOption', addEntityOption)
exports('RemoveEntityOption', removeEntityOption)

-- API propria da OB Framework para entidades e zonas.
local function registerEntity(id, entity, option)
    option = type(option) == 'table' and option or {}
    option.entity = entity
    return addEntityOption(id, option)
end

local function registerNetworkEntity(id, networkId, option)
    option = type(option) == 'table' and option or {}
    option.netId = tonumber(networkId)
    return addEntityOption(id, option)
end

local function registerZone(id, kind, data)
    if type(id) ~= 'string' or id == '' or type(data) ~= 'table' then
        return false, 'Identificador ou configuracao invalida.'
    end

    local option = data.option
    if type(option) ~= 'table' or type(option.label) ~= 'string' or option.label == '' then
        return false, 'A zona precisa de uma opcao com label.'
    end
    if type(option.event) ~= 'string' and not callable(option.action) then
        return false, 'A opcao da zona precisa de evento ou acao.'
    end

    option.id = id
    zoneOptions[id] = {
        id = id,
        kind = kind,
        coords = data.coords and vector3(data.coords.x, data.coords.y, data.coords.z) or nil,
        size = data.size and vector3(data.size.x, data.size.y, data.size.z) or nil,
        radius = tonumber(data.radius),
        rotation = tonumber(data.rotation) or 0.0,
        options = { option },
    }
    return true
end

local function unregisterZone(id)
    if type(id) ~= 'string' then return false end
    zoneOptions[id] = nil
    invalidateTargetOption(id)
    return true
end

exports('RegisterEntity', registerEntity)
exports('RegisterNetworkEntity', registerNetworkEntity)
exports('RegisterBoxZone', function(id, data) return registerZone(id, 'box', data) end)
exports('RegisterSphereZone', function(id, data) return registerZone(id, 'sphere', data) end)
exports('UnregisterZone', unregisterZone)

-- Diagnostico temporario: /obtargetdebug. Enquanto segura a tecla do target,
-- mostra uma esfera em cada entidade/zona registrada para localizar alvos
-- invisiveis ou registros em coordenadas erradas.
RegisterCommand('obtargetdebug', function()
    debugTargets = not debugTargets
    notify(debugTargets and 'Debug do target ativado. Segure a tecla do target para ver os pontos.' or 'Debug do target desativado.', 'inform')
end, false)

RegisterCommand('+ob_target', function()
    targetActive = true
    nextScanAt = 0
    suppressAttackUntil = GetGameTimer() + 350
end, false)

RegisterCommand('-ob_target', function()
    targetActive = false
    -- Na Legacy o comando de soltar Alt pode chegar logo depois de o cursor
    -- receber foco. Nessa situacao o cursor ja foi aberto de proposito e so
    -- deve fechar por Esc ou depois de escolher a opcao.
    if targetNuiFocused then return end
    if targetFocusPending and currentOption then
        setTargetFocus(true)
        return
    end
    targetFocusPending = false
    currentOption = nil
    hideTarget()
    setIndicator(false, false)
    setTargetFocus(false)
end, false)

RegisterKeyMapping('+ob_target', 'Usar target da OB Framework', 'keyboard', ORTargetConfig.ActivationKey)

RegisterNUICallback('select', function(data, callback)
    local option = currentOption
    if option and option.choices then
        local selected
        for _, entry in ipairs(option.choices) do
            if type(data) == 'table' and entry.id == data.id then selected = entry; break end
        end
        option = selected and {option = selected, entity = option.entity, targetSource = option.targetSource} or nil
    elseif option and type(data) == 'table' and data.id and data.id ~= option.option.id then
        option = nil
    end
    local valid = option ~= nil and LocalPlayer.state['or:loaded'] == true
        and LocalPlayer.state['or:downed'] ~= true and LocalPlayer.state['or:restrained'] ~= true
        and LocalPlayer.state['ob:restrained'] ~= true and LocalPlayer.state['ob:takedown'] ~= true
    if valid then
        local definition=option.option
        if option.zone then
            valid=zoneOptions[definition.id]==option.zone and canUseZoneOption(definition,option.zone)
        elseif option.targetSource then
            local playerIndex=getPlayerFromPed(option.entity)
            valid=playerOptions[definition.id]==definition and playerIndex~=nil
                and GetPlayerServerId(playerIndex)==option.targetSource and canUsePlayerOption(definition,playerIndex,option.entity)
        else
            valid=entityOptions[definition.id]==definition and DoesEntityExist(option.entity)
                and canUseEntityOption(definition,option.entity)
        end
    end
    callback({ ok = valid == true })
    -- Ao abrir o cursor o jogador normalmente solta Alt. A opcao continua
    -- valida enquanto a NUI estiver focada, portanto targetActive nao e uma
    -- condicao para o segundo clique.
    targetActive = false
    currentOption = nil
    suppressAttackUntil = GetGameTimer() + 350
    hideTarget()
    setIndicator(false, false)
    setTargetFocus(false)
    if not valid then return end
    if callable(option.option.action) then
        local ok, errorMessage = pcall(option.option.action, option.targetSource or option.entity)
        if not ok then
            print(('[ob_target] Acao de target falhou: %s'):format(tostring(errorMessage)))
        end
    else
        local args = type(option.option.args) == 'table' and option.option.args or nil
        if args then
            TriggerEvent(option.option.event, option.targetSource or option.entity, table.unpack(args))
        else
            TriggerEvent(option.option.event, option.targetSource or option.entity)
        end
    end
end)

RegisterNUICallback('close', function(_, callback)
    callback({ ok = true })
    targetActive = false
    suppressAttackUntil = GetGameTimer() + 350
    currentOption = nil
    hideTarget()
    setIndicator(false, false)
    setTargetFocus(false)
end)

RegisterNetEvent('ob_target:client:forceClose', function()
    targetActive = false
    suppressAttackUntil = GetGameTimer() + 350
    currentOption = nil
    hideTarget()
    setIndicator(false, false)
    setTargetFocus(false)
end)

-- O clique esquerdo seleciona a opcao da NUI, mas tambem e o controle de
-- ataque do GTA. Bloqueamos o disparo/soco durante todo o uso do target e por
-- alguns frames depois de fecha-lo, inclusive nos frames em que o raycast
-- assincrono ainda esta procurando uma entidade.
CreateThread(function()
    while true do
        if targetActive or targetNuiFocused or GetGameTimer() < suppressAttackUntil then
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 257, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            Wait(0)
        else
            Wait(100)
        end
    end
end)

CreateThread(function()
    while true do
        -- Enquanto o cursor esta aberto, preserve a opcao ate a pessoa clicar
        -- nela ou apertar Esc. Isso evita que a liberacao da tecla do target
        -- feche a NUI no mesmo frame na Legacy.
        if targetNuiFocused then
            Wait(0)
        else
        local canTarget = targetActive
            and not IsPauseMenuActive()
            and not IsNuiFocused()
            and LocalPlayer.state['or:loaded'] == true
            and LocalPlayer.state['or:downed'] ~= true
            and LocalPlayer.state['or:restrained'] ~= true
            and LocalPlayer.state['ob:restrained'] ~= true
            and LocalPlayer.state['ob:takedown'] ~= true

        if canTarget then
            if not targetFocusPending and GetGameTimer()>=nextScanAt then
                currentOption=getActiveOption()
                nextScanAt=GetGameTimer()+math.max(0,tonumber(ORTargetConfig.ScanIntervalMs) or 30)
            end
            local option = currentOption
            -- O indicador fica no centro enquanto Alt estiver pressionado e
            -- acende quando existe uma opcao valida sob a mira.
            setIndicator(true, option ~= nil)
            if option then
                currentOption = option
                showTarget(option)

                -- Mirar no alvo nao libera o cursor. O primeiro clique esquerdo
                -- apenas prepara o cursor; ele recebe foco somente quando o
                -- botao e solto. Assim o clique que abriu o cursor nunca e
                -- reutilizado pela NUI como um clique de selecao.
                DisableControlAction(0, ORTargetConfig.SelectControl, true)
                if not targetFocusPending and IsDisabledControlJustPressed(0, ORTargetConfig.SelectControl) then
                    targetFocusPending = true
                elseif targetFocusPending and not IsDisabledControlPressed(0, ORTargetConfig.SelectControl) then
                    targetFocusPending = false
                    setTargetFocus(true)
                end
                Wait(0)
            else
                currentOption = nil
                targetFocusPending = false
                hideTarget()
                setTargetFocus(false)
                Wait(0)
            end
        else
            currentOption = nil
            rays, lastRayEntity = nil, nil
            nextScanAt = 0
            hideTarget()
            setIndicator(false, false)
            setTargetFocus(false)
            Wait(50)
        end
        end
    end
end)

CreateThread(function()
    while true do
        if not debugTargets or not targetActive then
            Wait(250)
        else
            for _, option in pairs(entityOptions) do
                local entity = option.entity or (option.netId and NetworkGetEntityFromNetworkId(option.netId))
                if entity and entity > 0 and DoesEntityExist(entity) then
                    local coords = getEntityTargetPoint(entity)
                    DrawMarker(28, coords.x, coords.y, coords.z + 0.14,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        0.24, 0.24, 0.24, 255, 80, 40, 180,
                        false, true, 2, false, nil, nil, false)
                end
            end
            for _, zone in pairs(zoneOptions) do
                if zone.coords then
                    local inside = pointInsideZone(zone, GetEntityCoords(PlayerPedId()))
                    DrawMarker(28, zone.coords.x, zone.coords.y, zone.coords.z + 0.14,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        0.32, 0.32, 0.32, inside and 40 or 255, inside and 220 or 180, 70, 190,
                        false, true, 2, false, nil, nil, false)
                end
            end
            Wait(0)
        end
    end
end)

-- As opcoes vivem somente na memoria deste recurso. Quando o target volta de
-- um restart, os recursos que possuem peds/zonas existentes recebem este
-- aviso e registram apenas as suas opcoes novamente; nao e preciso reiniciar
-- o personagem, o core ou recriar as entidades.
CreateThread(function()
    Wait(350)
    TriggerEvent('ob_target:client:ready')
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        SendNUIMessage({ action = 'hide' })
        SendNUIMessage({ action = 'indicator', visible = false, active = false })
        setTargetFocus(false)
    end
end)
