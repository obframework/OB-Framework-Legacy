local state = {
    active = false,
    menuOpen = false,
    points = {},
    checkpoint = nil,
    checkpointHandle = 0,
    routeBlip = 0,
    actorBlip = 0,
    busy = false,
    event = nil,
    eventStage = nil,
    eventEngaged = false,
    hasRecoveredItems = false,
    carriedProp = 0,
    nextSpawnAttempt = 0,
    actors = {},
    limitedVehicle = 0,
    originalMaxSpeed = nil,
    limiterEnabled = true,
    routeId = nil,
    cycle = 0,
    ai = { lastDecision = 0, lastMoveCheck = 0, lastPosition = nil, mode = 'idle' },
}
local group = { members = {}, isLeader = true, maxMembers = 4 }
local npcPed = nil

local function notify(message, kind)
    OR.Notify(message, kind or 'info')
end

local function closeMenu()
    if not state.menuOpen then return end
    state.menuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function deleteNavigation()
    if state.checkpointHandle ~= 0 then DeleteCheckpoint(state.checkpointHandle) end
    state.checkpointHandle = 0
    if state.routeBlip ~= 0 and DoesBlipExist(state.routeBlip) then RemoveBlip(state.routeBlip) end
    state.routeBlip = 0
    if state.actorBlip ~= 0 and DoesBlipExist(state.actorBlip) then RemoveBlip(state.actorBlip) end
    state.actorBlip = 0
end

local function takeControl(entity)
    if entity == 0 or not DoesEntityExist(entity) then return end
    local deadline = GetGameTimer() + 500
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < deadline do
        NetworkRequestControlOfEntity(entity)
        Wait(0)
    end
end

local function deleteActors()
    for _, ped in pairs(state.actors) do
        if ped ~= 0 and DoesEntityExist(ped) then
            takeControl(ped)
            SetEntityAsMissionEntity(ped, true, true)
            DeleteEntity(ped)
        end
    end
    state.actors = {}
    if state.carriedProp ~= 0 and DoesEntityExist(state.carriedProp) then
        takeControl(state.carriedProp)
        DeleteEntity(state.carriedProp)
    end
    state.carriedProp = 0
    state.hasRecoveredItems = false
    state.nextSpawnAttempt = 0
    state.eventStage = nil
    state.eventEngaged = false
    state.ai = { lastDecision = 0, lastMoveCheck = 0, lastPosition = nil, mode = 'idle' }
    if state.actorBlip ~= 0 and DoesBlipExist(state.actorBlip) then RemoveBlip(state.actorBlip) end
    state.actorBlip = 0
end

local function restoreSpeed()
    local vehicle = state.limitedVehicle
    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        SetEntityMaxSpeed(vehicle, state.originalMaxSpeed and math.max(state.originalMaxSpeed, 20.0) or 999.0)
    end
    state.limitedVehicle, state.originalMaxSpeed = 0, nil
end

local function allowedVehicle(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    local model = GetEntityModel(vehicle)
    for name in pairs(Patrol.allowedVehicles or {}) do if joaat(name) == model then return true end end
    return false
end

local function currentSpeedLimit()
    return Patrol.speedLimitKmh or 60.0
end

local function applySpeedLimit()
    if not state.limiterEnabled then restoreSpeed(); return end
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped or not allowedVehicle(vehicle) then
        restoreSpeed()
        return
    end
    if state.limitedVehicle ~= vehicle then
        restoreSpeed()
        state.limitedVehicle = vehicle
        state.originalMaxSpeed = GetVehicleEstimatedMaxSpeed(vehicle)
    end
    SetEntityMaxSpeed(vehicle, currentSpeedLimit() / 3.6)
end

local function clearPatrol()
    closeMenu()
    deleteNavigation()
    deleteActors()
    restoreSpeed()
    state.active = false
    state.points = {}
    state.checkpoint = nil
    state.busy = false
    state.event = nil
    state.routeId = nil
    state.cycle = 0
    state.limiterEnabled = true
    OR.Help.Hide()
end

local function routeTo(coords, label)
    if state.routeBlip ~= 0 and DoesBlipExist(state.routeBlip) then RemoveBlip(state.routeBlip) end
    state.routeBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(state.routeBlip, 280)
    SetBlipColour(state.routeBlip, Patrol.checkpoint.iconColor or 3)
    SetBlipScale(state.routeBlip, 0.82)
    SetBlipRoute(state.routeBlip, true)
    SetBlipRouteColour(state.routeBlip, Patrol.checkpoint.iconColor or 3)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label)
    EndTextCommandSetBlipName(state.routeBlip)
end

local function showCheckpoint(index)
    deleteNavigation()
    local current = state.points[index]
    if not current then return end
    local following = state.points[index + 1] or current
    local cfg = Patrol.checkpoint
    state.checkpoint = index
    state.checkpointHandle = CreateCheckpoint(cfg.type or 47,
        current.x, current.y, current.z - 1.0,
        following.x, following.y, following.z - 1.0,
        cfg.radius or 7.0, cfg.color.r, cfg.color.g, cfg.color.b, cfg.color.a, 0)
    SetCheckpointCylinderHeight(state.checkpointHandle, 1.0, 1.0, cfg.radius or 7.0)
    routeTo(current, ('Patrulha %s/%s'):format(index, #state.points))
end

local function requestModel(modelName)
    local model = joaat(modelName or '')
    if not IsModelInCdimage(model) or not IsModelValid(model) then return nil end
    RequestModel(model)
    local deadline = GetGameTimer() + 7000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(10) end
    if not HasModelLoaded(model) then return nil end
    return model
end

local function separatedFrom(coords, avoid)
    return not avoid or #(vector3(coords.x, coords.y, coords.z) - avoid) >= 2.0
end

local function safeActorCoords(coords, avoid)
    local candidates = {
        vector3(coords.x, coords.y, coords.z),
        vector3(coords.x + 2.0, coords.y, coords.z),
        vector3(coords.x - 2.0, coords.y, coords.z),
        vector3(coords.x, coords.y + 2.0, coords.z),
        vector3(coords.x, coords.y - 2.0, coords.z),
        vector3(coords.x + 3.5, coords.y + 3.5, coords.z),
    }
    for _, candidate in ipairs(candidates) do
        local found, safe = GetSafeCoordForPed(candidate.x, candidate.y, candidate.z + 1.0, true, 16)
        if found and safe and separatedFrom(safe, avoid) then return safe end
        local groundFound, groundZ = GetGroundZFor_3dCoord(candidate.x, candidate.y, candidate.z + 8.0, false)
        local ground = groundFound and vector3(candidate.x, candidate.y, groundZ) or nil
        if ground and separatedFrom(ground, avoid) then return ground end
    end
    local fallback = vector3(coords.x, coords.y, coords.z)
    if separatedFrom(fallback, avoid) then return fallback end
    return vector3(coords.x + 2.5, coords.y, coords.z)
end

local function spawnActor(modelName, coords, heading, avoid)
    local model = requestModel(modelName)
    if not model then return 0 end
    local safe = safeActorCoords(coords, avoid)
    -- Somente o policial designado controla estes atores. Entidades de rede
    -- criadas pelo cliente podiam migrar e ser removidas pelo OneSync, piscando.
    local ped = CreatePed(4, model, safe.x, safe.y, safe.z, heading or 0.0, false, false)
    SetModelAsNoLongerNeeded(model)
    if ped == 0 then return 0 end
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)
    SetPedPathCanUseClimbovers(ped, true)
    SetPedPathCanUseLadders(ped, true)
    SetPedPathCanDropFromHeight(ped, true)
    return ped
end

local function offsetCoords(coords, forward, side)
    local heading = math.rad(coords.w or 0.0)
    return vector3(
        coords.x + math.sin(heading) * forward + math.cos(heading) * side,
        coords.y + math.cos(heading) * forward - math.sin(heading) * side,
        coords.z
    )
end

local function configureSuspect(ped, weapon)
    if ped == 0 then return end
    SetPedAsEnemy(ped, true)
    SetPedCombatAbility(ped, 2)
    SetPedCombatMovement(ped, 2)
    SetPedCombatRange(ped, 1)
    SetPedCombatAttributes(ped, 5, true)
    SetPedCombatAttributes(ped, 46, true)
    SetPedSeeingRange(ped, 90.0)
    SetPedHearingRange(ped, 90.0)
    SetPedAccuracy(ped, 24)
    SetPedDropsWeaponsWhenDead(ped, true)
    if weapon then GiveWeaponToPed(ped, joaat(weapon), 80, false, true) end
end

local function nearbyOfficerCount(suspect)
    if suspect == 0 or not DoesEntityExist(suspect) then return 1 end
    local suspectCoords, count = GetEntityCoords(suspect), 0
    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        if ped ~= 0 and not IsEntityDead(ped) and #(GetEntityCoords(ped) - suspectCoords) <= 38.0 then count = count + 1 end
    end
    return math.max(1, count)
end

local function tacticalOffset(suspectCoords, officerCoords, distance, side)
    local dx, dy = suspectCoords.x - officerCoords.x, suspectCoords.y - officerCoords.y
    local length = math.max(0.01, math.sqrt(dx * dx + dy * dy))
    local nx, ny = dx / length, dy / length
    return vector3(suspectCoords.x + nx * distance - ny * side, suspectCoords.y + ny * distance + nx * side, suspectCoords.z)
end

local function surrenderSuspect(suspect, officer)
    takeControl(suspect)
    ClearPedTasks(suspect)
    RemoveAllPedWeapons(suspect, true)
    TaskHandsUp(suspect, -1, officer, -1, true)
    SetPedKeepTask(suspect, true)
    state.ai.mode = 'surrender'
end

local function updateTacticalAI(event, suspect, officer)
    if suspect == 0 or not DoesEntityExist(suspect) or IsPedDeadOrDying(suspect, true) or state.ai.mode == 'surrender' then return end
    local cfg, now = Patrol.tacticalAI or {}, GetGameTimer()
    local suspectCoords, officerCoords = GetEntityCoords(suspect), GetEntityCoords(officer)
    local distance = #(suspectCoords - officerCoords)
    local eventType = event.type or 'assist'

    if now - (state.ai.lastMoveCheck or 0) >= (cfg.stuckCheckMs or 3500) then
        local previous = state.ai.lastPosition
        state.ai.lastMoveCheck, state.ai.lastPosition = now, suspectCoords
        if previous and #(suspectCoords - previous) < (cfg.stuckDistance or 1.25)
            and (state.ai.mode == 'flee' or state.ai.mode == 'flank' or state.ai.mode == 'cover') then
            local escape = tacticalOffset(suspectCoords, officerCoords, 18.0, (event.token:byte(1) % 2 == 0) and 10.0 or -10.0)
            ClearPedTasks(suspect)
            TaskFollowNavMeshToCoord(suspect, escape.x, escape.y, escape.z, 2.0, 6000, 1.5, false, 0.0)
            state.ai.mode = 'reposition'
            state.ai.lastDecision = now
            return
        end
    end

    if now - (state.ai.lastDecision or 0) < (cfg.decisionIntervalMs or 4500) then return end
    state.ai.lastDecision = now
    local officers = nearbyOfficerCount(suspect)
    local health = GetEntityHealth(suspect)
    local seesOfficer = HasEntityClearLosToEntity(suspect, officer, 17)
    local pressure = officers * 18 + (distance < 12.0 and 24 or 0) + (health <= (cfg.surrenderHealth or 135) and 45 or 0)
    local roll = (now + (event.token:byte(#event.token) or 1) * 17) % 100

    if eventType ~= 'purse_theft' and pressure >= roll + 45 then
        surrenderSuspect(suspect, officer)
        notify('O suspeito avaliou a situacao e decidiu se render.', 'info')
        return
    end

    if eventType == 'purse_theft' then
        if distance < 24.0 or state.ai.mode ~= 'flee' then
            ClearPedTasks(suspect)
            TaskSmartFleePed(suspect, officer, cfg.fleeDistance or 190.0, -1, false, false)
            SetPedMoveRateOverride(suspect, officers > 1 and 1.15 or 1.0)
            state.ai.mode = 'flee'
        end
        return
    end

    if officers >= 2 and distance < 30.0 and health > (cfg.surrenderHealth or 135) + 20 then
        local side = ((event.token:byte(2) or 2) % 2 == 0) and (cfg.flankDistance or 14.0) or -(cfg.flankDistance or 14.0)
        local flank = tacticalOffset(suspectCoords, officerCoords, 8.0, side)
        ClearPedTasks(suspect)
        TaskFollowNavMeshToCoord(suspect, flank.x, flank.y, flank.z, 1.6, 5000, 2.0, false, 0.0)
        state.ai.mode = 'flank'
    elseif distance > (cfg.coverDistance or 38.0) or not seesOfficer then
        ClearPedTasks(suspect)
        TaskSeekCoverFromPed(suspect, officer, 5000, false)
        state.ai.mode = 'cover'
    elseif eventType == 'shop_robbery' and health < 165 and distance < 18.0 then
        ClearPedTasks(suspect)
        TaskSmartFleePed(suspect, officer, cfg.fleeDistance or 190.0, -1, false, false)
        state.ai.mode = 'flee'
    else
        ClearPedTasks(suspect)
        TaskCombatPed(suspect, officer, 0, 16)
        state.ai.mode = 'combat'
    end
end

local function markActor(ped, label)
    if ped == 0 or not DoesEntityExist(ped) then return end
    if state.actorBlip ~= 0 and DoesBlipExist(state.actorBlip) then RemoveBlip(state.actorBlip) end
    state.actorBlip = AddBlipForEntity(ped)
    SetBlipSprite(state.actorBlip, 280)
    SetBlipColour(state.actorBlip, 1)
    SetBlipScale(state.actorBlip, 0.82)
    SetBlipAsShortRange(state.actorBlip, false)
    SetBlipFlashes(state.actorBlip, true)
    SetBlipRoute(state.actorBlip, true)
    SetBlipRouteColour(state.actorBlip, 1)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label or 'Suspeito')
    EndTextCommandSetBlipName(state.actorBlip)
end

local function spawnEventActors()
    local event = state.event
    if not event or next(state.actors) or event.handler ~= GetPlayerServerId(PlayerId())
        or GetGameTimer() < (state.nextSpawnAttempt or 0) then return end
    state.nextSpawnAttempt = GetGameTimer() + 2500
    local coords = event.coords
    local eventType = event.type or 'assist'
    if eventType == 'assist' then
        local victim = spawnActor(event.model, vector3(coords.x, coords.y, coords.z), coords.w)
        if victim == 0 then return end
        state.actors.victim = victim
        if victim ~= 0 and event.scenario then TaskStartScenarioInPlace(victim, event.scenario, 0, true) end
        state.eventStage = 'assist'
        return
    end

    local victimPos = offsetCoords(coords, -1.2, -0.9)
    local suspectPos = offsetCoords(coords, 1.4, 0.9)
    local victim = spawnActor(event.victimModel or 'a_f_y_business_02', victimPos, (coords.w or 0.0) + 180.0)
    local suspect = spawnActor(event.model or 'g_m_y_lost_01', suspectPos, coords.w,
        victim ~= 0 and GetEntityCoords(victim) or nil)
    if victim == 0 or suspect == 0 then
        if victim ~= 0 and DoesEntityExist(victim) then DeleteEntity(victim) end
        if suspect ~= 0 and DoesEntityExist(suspect) then DeleteEntity(suspect) end
        return
    end
    state.actors.victim, state.actors.suspect = victim, suspect
    state.ai = { lastDecision = 0, lastMoveCheck = GetGameTimer(), lastPosition = suspect ~= 0 and GetEntityCoords(suspect) or nil, mode = 'idle' }
    if victim ~= 0 then
        SetEntityInvincible(victim, true)
        TaskHandsUp(victim, -1, suspect, -1, true)
    end
    configureSuspect(suspect, event.weapon)
    if state.routeBlip ~= 0 and DoesBlipExist(state.routeBlip) then RemoveBlip(state.routeBlip) end
    state.routeBlip = 0
    markActor(suspect, eventType == 'purse_theft' and 'Autor do furto' or 'Suspeito armado')

    if eventType == 'purse_theft' then
        if suspect ~= 0 then TaskSmartFleePed(suspect, PlayerPedId(), 190.0, -1, false, false) end
        state.eventStage = 'chase'
    else
        if suspect ~= 0 and victim ~= 0 then TaskAimGunAtEntity(suspect, victim, -1, false) end
        state.eventStage = 'resolve'
    end
end

local function showEvent(event)
    deleteNavigation()
    deleteActors()
    state.event = event
    state.checkpoint = nil
    routeTo(event.coords, event.label or 'Ocorrencia da patrulha')
    local assigned = event.handler == GetPlayerServerId(PlayerId())
    notify(assigned and ('Ocorrencia designada para voce: %s'):format(event.label)
        or ('Ocorrencia do grupo: %s'):format(event.label), 'info')
end

local function applyJob(data)
    data = data or {}
    if data.active ~= true then clearPatrol(); return end
    local wasActive = state.active
    local oldCheckpoint, oldRoute = state.checkpoint, state.routeId
    local oldToken = state.event and state.event.token
    local oldHandler = state.event and state.event.handler
    state.active = true
    state.points = data.points or state.points
    state.routeLabel = data.routeLabel
    state.routeId = data.routeId
    state.cycle = data.cycle or state.cycle
    if not wasActive then state.limiterEnabled = true end
    if data.event then
        if not state.limiterEnabled then
            state.event = data.event
            state.checkpoint = nil
            deleteNavigation()
            deleteActors()
        elseif oldToken ~= data.event.token or oldHandler ~= data.event.handler then
            showEvent(data.event)
        end
    else
        if state.event then deleteActors(); state.event = nil end
        state.checkpoint = data.checkpoint
        if state.limiterEnabled and (oldCheckpoint ~= data.checkpoint or oldRoute ~= data.routeId or not wasActive) then
            showCheckpoint(data.checkpoint)
        elseif not state.limiterEnabled then
            deleteNavigation()
        end
    end
    if not wasActive then
        closeMenu()
        notify(('Patrulha continua iniciada: %s. Entre em uma viatura autorizada.'):format(data.routeLabel or 'rota selecionada'), 'success')
    elseif oldRoute and oldRoute ~= data.routeId then
        notify(('Nova rota: %s.'):format(data.routeLabel or 'rota selecionada'), 'info')
    end
end

local function nearbyPlayers()
    local result, coords = {}, GetEntityCoords(PlayerPedId())
    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() then
            local ped = GetPlayerPed(player)
            if ped ~= 0 and #(coords - GetEntityCoords(ped)) <= (Patrol.group.inviteDistance or 18.0) then
                result[#result + 1] = {
                    id = GetPlayerServerId(player),
                    name = GetPlayerName(player) or ('ID %s'):format(GetPlayerServerId(player)),
                }
            end
        end
    end
    return result
end

local function refreshPanel(open)
    local ok, data = OR.Callback.await('ob_patrol:server:panel')
    if not ok then if open then notify(data or 'Patrulhamento indisponivel.', 'error') end; return end
    data.nearby = nearbyPlayers()
    data.limiterEnabled = state.limiterEnabled
    group = data.group or group
    if open then
        state.menuOpen = true
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'open', payload = data })
    elseif state.menuOpen then
        SendNUIMessage({ action = 'update', payload = data })
    end
end

RegisterNetEvent('ob_patrol:client:refreshPanel', function() refreshPanel(false) end)
RegisterNetEvent('ob_patrol:client:groupUpdated', function(payload) group = payload or group; refreshPanel(false) end)
RegisterNetEvent('ob_patrol:client:jobSync', applyJob)
RegisterNetEvent('ob_patrol:client:stopped', function(reason, completed)
    clearPatrol()
    if reason then notify(reason, completed and 'success' or 'info') end
end)
RegisterNetEvent('ob_patrol:client:groupInvite', function(invite)
    CreateThread(function()
        local accepted = OR.Dialog.Confirm({
            header = 'Grupo de Patrulha',
            content = ('%s convidou voce para patrulhar em grupo.'):format(invite.name),
            centered = true,
            cancel = true,
            labels = { confirm = 'Entrar', cancel = 'Recusar' },
        })
        local ok, message = OR.Callback.await('ob_patrol:server:answerInvite', accepted)
        if message then notify(message, ok and 'success' or 'error') end
        refreshPanel(false)
    end)
end)

local function registerNpcTarget()
    if GetResourceState('ob_target') ~= 'started' or not npcPed or not DoesEntityExist(npcPed) then return end
    exports.ob_target:RegisterEntity('ob_patrol_npc', npcPed, {
        label = 'Organizar patrulha',
        icon = 'fa-solid fa-shield-halved',
        event = 'ob_patrol:client:openPanel',
        distance = Patrol.npc.targetDistance or 3.0,
        canInteract = function(entity) return entity == npcPed end,
    })
end

RegisterNetEvent('ob_patrol:client:openPanel', function() refreshPanel(true) end)

CreateThread(function()
    while LocalPlayer.state['or:loaded'] ~= true do Wait(250) end
    local cfg, model = Patrol.npc, requestModel(Patrol.npc.model)
    if not model then return print('[ob_patrol] Nao foi possivel carregar o NPC.') end
    npcPed = CreatePed(4, model, cfg.coords.x, cfg.coords.y, cfg.coords.z - 1.0, cfg.coords.w, false, true)
    SetModelAsNoLongerNeeded(model)
    if npcPed ~= 0 then
        SetEntityAsMissionEntity(npcPed, true, true)
        FreezeEntityPosition(npcPed, true)
        SetEntityInvincible(npcPed, true)
        SetBlockingOfNonTemporaryEvents(npcPed, true)
        registerNpcTarget()
    end
end)
AddEventHandler('ob_target:client:ready', registerNpcTarget)

RegisterCommand(Patrol.command or 'patrulha', function()
    if not state.active then return notify('Inicie a patrulha com o responsavel em Mission Row.', 'info') end
    local intended = not state.limiterEnabled
    local ok, message = OR.Callback.await('ob_patrol:server:setLimiter', intended)
    if not ok then return notify(message or 'Nao foi possivel alterar o limitador.', 'error') end
    state.limiterEnabled = intended
    if not state.limiterEnabled then
        restoreSpeed()
        deleteNavigation()
        deleteActors()
    elseif state.event then
        showEvent(state.event)
    elseif state.checkpoint then
        showCheckpoint(state.checkpoint)
    end
    notify(state.limiterEnabled
        and ('Limitador ativado em %s km/h.'):format(currentSpeedLimit())
        or 'Limitador da patrulha desativado. Os checkpoints ficaram suspensos apenas para voce.', 'info')
    if state.menuOpen then refreshPanel(false) end
end, false)

RegisterCommand(Patrol.leaveCommand or 'patrulhasair', function()
    if not state.active or state.busy then return end
    state.busy = true
    local ok, message = OR.Callback.await('ob_patrol:server:stop')
    state.busy = false
    if not ok then notify(message or 'Nao foi possivel encerrar.', 'error') end
end, false)

RegisterCommand((Patrol.creator and Patrol.creator.panelCommand) or 'patrulharotas', function()
    if state.menuOpen then return end
    local ok, data = OR.Callback.await('ob_patrol:server:adminPanel')
    if not ok then return notify(data or 'Gerenciador de rotas indisponivel.', 'error') end
    state.menuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', payload = data })
end, false)

RegisterNUICallback('close', function(_, cb) closeMenu(); cb('ok') end)
RegisterNUICallback('selectRegion', function(data, cb)
    if state.busy then cb('busy'); return end
    state.busy = true
    local ok, message = OR.Callback.await('ob_patrol:server:start', data and data.region)
    state.busy = false
    if not ok then notify(message or 'Nao foi possivel iniciar.', 'error') end
    cb(ok and 'ok' or 'fail')
end)
RegisterNUICallback('invite', function(data, cb)
    local ok, message = OR.Callback.await('ob_patrol:server:invite', data and data.id)
    if message then notify(message, ok and 'success' or 'error') end
    refreshPanel(false)
    cb(ok and 'ok' or 'fail')
end)
RegisterNUICallback('leaveGroup', function(_, cb)
    local ok, message = OR.Callback.await('ob_patrol:server:leaveGroup')
    if message then notify(message, ok and 'success' or 'error') end
    refreshPanel(false)
    cb(ok and 'ok' or 'fail')
end)
RegisterNUICallback('stopPatrol', function(_, cb)
    local ok, message = OR.Callback.await('ob_patrol:server:stop')
    if not ok then notify(message or 'Nao foi possivel encerrar.', 'error') end
    if ok then closeMenu() end
    cb(ok and 'ok' or 'fail')
end)
RegisterNUICallback('adminStartRecording', function(data, cb)
    local ok, message = OR.Callback.await('ob_patrol:server:adminStartRecording', data)
    if message then notify(message, ok and 'success' or 'error') end
    if ok then closeMenu() end
    cb(ok and 'ok' or 'fail')
end)
RegisterNUICallback('adminUpdateRoute', function(data, cb)
    local ok, result = OR.Callback.await('ob_patrol:server:adminUpdateRoute', data)
    if ok then SendNUIMessage({ action = 'update', payload = result })
    else notify(result or 'Nao foi possivel alterar a rota.', 'error') end
    cb(ok and 'ok' or 'fail')
end)
RegisterNUICallback('adminDeleteRoute', function(data, cb)
    local ok, result = OR.Callback.await('ob_patrol:server:adminDeleteRoute', data and data.id)
    if ok then SendNUIMessage({ action = 'update', payload = result })
    else notify(result or 'Nao foi possivel excluir a rota.', 'error') end
    cb(ok and 'ok' or 'fail')
end)

CreateThread(function()
    while true do
        if state.active then applySpeedLimit(); Wait(500) else Wait(900) end
    end
end)

CreateThread(function()
    while true do
        if not state.active or state.event or not state.checkpoint or state.busy or not state.limiterEnabled then
            Wait(300)
        else
            local current = state.points[state.checkpoint]
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            if current and vehicle ~= 0 and allowedVehicle(vehicle) and GetPedInVehicleSeat(vehicle, -1) == ped
                and #(GetEntityCoords(vehicle) - vector3(current.x, current.y, current.z)) <= (Patrol.checkpoint.radius or 7.0) then
                state.busy = true
                local ok, message = OR.Callback.await('ob_patrol:server:checkpoint', state.checkpoint, NetworkGetNetworkIdFromEntity(vehicle))
                state.busy = false
                if not ok and message then notify(message, 'error') end
                Wait(1200)
            else
                Wait(100)
            end
        end
    end
end)

local function detainSuspect(suspect)
    if suspect == 0 or not DoesEntityExist(suspect) then return end
    takeControl(suspect)
    ClearPedTasksImmediately(suspect)
    RemoveAllPedWeapons(suspect, true)
    TaskHandsUp(suspect, -1, PlayerPedId(), -1, true)
    SetEntityInvincible(suspect, true)
    FreezeEntityPosition(suspect, true)
end

local function moveToVictimStage()
    state.eventStage = 'return'
    if state.actorBlip ~= 0 and DoesBlipExist(state.actorBlip) then RemoveBlip(state.actorBlip) end
    state.actorBlip = 0
    local victim = state.actors.victim
    if victim and DoesEntityExist(victim) then
        state.actorBlip = AddBlipForEntity(victim)
        SetBlipSprite(state.actorBlip, 280)
        SetBlipColour(state.actorBlip, 3)
        SetBlipRoute(state.actorBlip, true)
        SetBlipRouteColour(state.actorBlip, 3)
    end
    notify(state.event and state.event.type == 'purse_theft'
        and 'Pertences recuperados. Volte ate a vitima para devolver.'
        or 'Suspeito controlado. Volte ate a vitima para concluir.', 'success')
end

local function restoreMissingVictim(event)
    if GetGameTimer() < (state.nextSpawnAttempt or 0) then return 0 end
    state.nextSpawnAttempt = GetGameTimer() + 2500
    local coords = event.coords
    local victimPos = offsetCoords(coords, -1.2, -0.9)
    local victim = spawnActor(event.victimModel or 'a_f_y_business_02', victimPos, (coords.w or 0.0) + 180.0)
    if victim ~= 0 then
        SetEntityInvincible(victim, true)
        TaskHandsUp(victim, -1, 0, -1, true)
        state.actors.victim = victim
        if state.actorBlip ~= 0 and DoesBlipExist(state.actorBlip) then RemoveBlip(state.actorBlip) end
        state.actorBlip = AddBlipForEntity(victim)
        SetBlipSprite(state.actorBlip, 280)
        SetBlipColour(state.actorBlip, 3)
        SetBlipRoute(state.actorBlip, true)
        SetBlipRouteColour(state.actorBlip, 3)
    end
    return victim
end

local function recoverBelongings(suspect)
    if state.busy or suspect == 0 or not DoesEntityExist(suspect) then return end
    state.busy = true
    OR.Help.Hide()
    local done = OR.Progress.Run({
        duration = 3500,
        label = 'Recuperando os pertences...',
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'amb@medic@standing@kneel@base', clip = 'base', flag = 49 },
    })
    if done then
        state.hasRecoveredItems = true
        local model = requestModel('prop_ld_wallet_01')
        if model then
            local coords = GetEntityCoords(PlayerPedId())
            state.carriedProp = CreateObject(model, coords.x, coords.y, coords.z, true, true, false)
            SetModelAsNoLongerNeeded(model)
            if state.carriedProp ~= 0 then
                AttachEntityToEntity(state.carriedProp, PlayerPedId(), GetPedBoneIndex(PlayerPedId(), 57005),
                    0.12, 0.02, -0.02, 10.0, 90.0, 10.0, true, true, false, true, 1, true)
            end
        end
        moveToVictimStage()
    end
    state.busy = false
end

local function finishOccurrence(event)
    if state.busy then return end
    state.busy = true
    OR.Help.Hide()
    local done = OR.Progress.Run({
        duration = (Patrol.events and Patrol.events.durationMs) or 5500,
        label = event.action or 'Finalizando ocorrencia...',
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'missheistdockssetup1clipboard@base', clip = 'base', flag = 49 },
    })
    if done then
        local ok, message = OR.Callback.await('ob_patrol:server:completeEvent', event.token)
        if not ok then notify(message or 'Nao foi possivel concluir.', 'error') end
    end
    state.busy = false
end

CreateThread(function()
    while true do
        local event = state.active and state.event
        if not event or not state.limiterEnabled then
            OR.Help.Hide()
            Wait(500)
        else
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            local target = vector3(event.coords.x, event.coords.y, event.coords.z)
            local distance = #(playerCoords - target)
            local assigned = event.handler == GetPlayerServerId(PlayerId())
            if assigned and distance <= ((Patrol.events and Patrol.events.spawnDistance) or 170.0) then spawnEventActors() end
            if not assigned then
                OR.Help.Hide()
                Wait(250)
            elseif not next(state.actors) then
                Wait(100)
            else
                local eventType = event.type or 'assist'
                local victim, suspect = state.actors.victim, state.actors.suspect
                if (eventType == 'shop_robbery' or eventType == 'armed_robbery') and not state.eventEngaged and distance <= 28.0 then
                    state.eventEngaged = true
                    if suspect ~= 0 and DoesEntityExist(suspect) then
                        if eventType == 'shop_robbery' and (event.token:byte(#event.token) or 0) % 2 == 0 then
                            TaskSmartFleePed(suspect, playerPed, 190.0, -1, false, false)
                        else
                            TaskCombatPed(suspect, playerPed, 0, 16)
                        end
                    end
                end

                if suspect ~= 0 and DoesEntityExist(suspect) and (state.eventEngaged or eventType == 'purse_theft') then
                    updateTacticalAI(event, suspect, playerPed)
                end

                if state.eventStage == 'assist' then
                    local actorDistance = victim ~= 0 and #(playerCoords - GetEntityCoords(victim)) or distance
                    if actorDistance <= (Patrol.events.interactionDistance or 2.2) and not IsPedInAnyVehicle(playerPed, false) then
                        OR.Help.Show(('[E] %s'):format(event.label))
                        if IsControlJustReleased(0, 38) then finishOccurrence(event) end
                    else OR.Help.Hide() end
                elseif state.eventStage == 'chase' or state.eventStage == 'resolve' then
                    local suspectExists = suspect ~= 0 and DoesEntityExist(suspect)
                    local neutralized = suspectExists and (IsPedDeadOrDying(suspect, true) or GetEntityHealth(suspect) <= 110)
                    local suspectDistance = suspectExists and #(playerCoords - GetEntityCoords(suspect)) or 999.0
                    if not suspectExists then
                        OR.Help.Show('A central esta atualizando a posicao do suspeito...')
                        deleteActors()
                        state.nextSpawnAttempt = GetGameTimer() + 1500
                    elseif neutralized and eventType == 'purse_theft' then
                        state.eventStage = 'recover'
                        if state.actorBlip ~= 0 and DoesBlipExist(state.actorBlip) then SetBlipFlashes(state.actorBlip, false) end
                    elseif neutralized then
                        moveToVictimStage()
                    elseif suspectDistance <= (Patrol.events.interactionDistance or 2.2) and not IsPedInAnyVehicle(playerPed, false) then
                        OR.Help.Show('[E] Render e deter o suspeito')
                        if IsControlJustReleased(0, 38) then
                            detainSuspect(suspect)
                            if eventType == 'purse_theft' then state.eventStage = 'recover' else moveToVictimStage() end
                        end
                    else
                        OR.Help.Show(state.eventStage == 'chase' and 'Persiga e alcance o suspeito.' or 'Controle o suspeito armado.')
                    end
                elseif state.eventStage == 'recover' then
                    local suspectExists = suspect ~= 0 and DoesEntityExist(suspect)
                    local suspectDistance = suspectExists and #(playerCoords - GetEntityCoords(suspect)) or 999.0
                    if suspectExists and suspectDistance <= (Patrol.events.interactionDistance or 2.2)
                        and not IsPedInAnyVehicle(playerPed, false) then
                        OR.Help.Show('[E] Revistar e recuperar os pertences')
                        if IsControlJustReleased(0, 38) then recoverBelongings(suspect) end
                    else
                        OR.Help.Show('Aproxime-se do suspeito para recuperar os pertences.')
                    end
                elseif state.eventStage == 'return' then
                    local victimExists = victim ~= 0 and DoesEntityExist(victim)
                    if not victimExists then
                        victim = restoreMissingVictim(event)
                        victimExists = victim ~= 0 and DoesEntityExist(victim)
                    end
                    local victimDistance = victimExists and #(playerCoords - GetEntityCoords(victim)) or 999.0
                    if victimExists and victimDistance <= (Patrol.events.interactionDistance or 2.2)
                        and not IsPedInAnyVehicle(playerPed, false) then
                        OR.Help.Show(eventType == 'purse_theft' and '[E] Devolver os pertences' or '[E] Atender a vitima')
                        if IsControlJustReleased(0, 38) and (eventType ~= 'purse_theft' or state.hasRecoveredItems) then
                            finishOccurrence(event)
                        end
                    else OR.Help.Hide() end
                end
                Wait(0)
            end
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearPatrol()
    if GetResourceState('ob_target') == 'started' then exports.ob_target:RemoveEntityOption('ob_patrol_npc') end
    if npcPed and DoesEntityExist(npcPed) then DeleteEntity(npcPed) end
end)
