local config = GarbageClientConfig
local sharedConfig = GarbageSharedConfig

assert(config and sharedConfig, '[ob_garbagejob] Configuracoes nao foram carregadas pelo fxmanifest.')

local state = {
    vehicle = nil,
    hasBag = false,
    bagObject = nil,
    currentStop = 0,
    bags = 0,
    deliveryBlip = nil,
    returnBlip = nil,
    unloadZone = nil,
    binZone = nil,
    workZone = nil,
    truckTarget = false,
    route = nil,
    group = nil,
    panelOpen = false,
    pedsSpawned = false,
    unloading = false,
    depositingBag = false
}

local function notify(message, kind)
    OR.Notify(message, kind or 'info')
end

local function createSphereMonitor(data)
    local zone = { removed = false }
    function zone:remove() self.removed = true end

    CreateThread(function()
        local inside = false
        while not zone.removed do
            local isInside = #(GetEntityCoords(PlayerPedId()) - data.coords) <= (tonumber(data.radius) or 1.0)
            if isInside and not inside and type(data.onEnter) == 'function' then data.onEnter() end
            if isInside and type(data.inside) == 'function' then data.inside() end
            if not isInside and inside and type(data.onExit) == 'function' then data.onExit() end
            inside = isInside
            Wait(isInside and 0 or 250)
        end
        if inside and type(data.onExit) == 'function' then data.onExit() end
    end)

    return zone
end

local function removeBlipSafe(blip)
    if blip then RemoveBlip(blip) end
end

local function removeZoneSafe(zone)
    if zone then zone:remove() end
end

local function sendRouteProgress(route)
    SendNUIMessage({ action = 'routeProgress', payload = route })
end

local function removeBagObject()
    if state.bagObject and DoesEntityExist(state.bagObject) then
        exports.ob_core:DeleteNetworkedObject(state.bagObject)
    end
    state.bagObject = nil
    state.hasBag = false
    ClearPedTasks(PlayerPedId())
end

local function removeTruckTarget()
    exports.ob_target:RemoveEntityOption('orbis_garbage_deliver')
    exports.ob_target:UnregisterZone('orbis_garbage_deliver_zone')
    state.truckTarget = false
end

local function getTruckDisposalPoint(vehicle)
    -- O ponto e preso na placa/luz traseira do modelo, nao em um offset que
    -- pode apontar para a frente dependendo da configuracao do veiculo.
    for _, boneName in ipairs({ 'platelight', 'numberplate', 'bumper_r', 'boot' }) do
        local bone = GetEntityBoneIndexByName(vehicle, boneName)
        if bone and bone ~= -1 then
            local point = GetWorldPositionOfEntityBone(vehicle, bone)
            return vector3(point.x, point.y, point.z + 0.35)
        end
    end

    return GetOffsetFromEntityInWorldCoords(vehicle, 0.0, -4.5, 0.0)
end

local function clearRouteVisuals()
    removeBlipSafe(state.deliveryBlip)
    removeBlipSafe(state.returnBlip)
    state.deliveryBlip = nil
    state.returnBlip = nil
    if state.binZone then exports.ob_target:UnregisterZone(state.binZone) end
    state.binZone = nil
    removeZoneSafe(state.workZone)
    state.workZone = nil
    removeZoneSafe(state.unloadZone)
    state.unloadZone = nil
    removeTruckTarget()
    OR.Help.Hide()
end

local function resetLocalRoute(deleteVehicle)
    clearRouteVisuals()
    removeBagObject()
    state.currentStop = 0
    state.bags = 0
    state.route = nil
    sendRouteProgress(nil)
    if deleteVehicle and state.vehicle and DoesEntityExist(state.vehicle) then
        DeleteVehicle(state.vehicle)
    end
    if deleteVehicle then state.vehicle = nil end
end

local function isLeader()
    return not state.group or state.group.isLeader == true
end

local function ensureVehicle(netId)
    if not netId or netId <= 0 then return end
    if state.vehicle and DoesEntityExist(state.vehicle) and NetworkGetNetworkIdFromEntity(state.vehicle) == netId then return end

    CreateThread(function()
        local vehicle = OR.WaitUntil(function()
            if NetworkDoesEntityExistWithNetworkId(netId) then return NetToVeh(netId) end
        end, 5000)
        if vehicle and vehicle ~= 0 then
            state.vehicle = vehicle
            if state.route then TriggerEvent('orbis-garbagejob:client:applyRoute', state.route) end
        end
    end)
end

local function getJobVehicle()
    if state.vehicle and DoesEntityExist(state.vehicle) then return state.vehicle end

    local routeNet = state.route and tonumber(state.route.vehicleNet)
    if routeNet and routeNet > 0 and NetworkDoesEntityExistWithNetworkId(routeNet) then
        local vehicle = NetToVeh(routeNet)
        if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
            state.vehicle = vehicle
            SetVehicleDoorsLocked(vehicle, 1)
            return vehicle
        end
    end

    -- Reserva para quando o netId ainda nao sincronizou: encontra o trash2 da
    -- rota proximo ao jogador e passa a acompanha-lo normalmente.
    local playerCoords, closest, closestDistance = GetEntityCoords(PlayerPedId()), nil, 80.0
    local model = joaat('trash2')
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if GetEntityModel(vehicle) == model and GetVehicleNumberPlateText(vehicle):sub(1, 4) == 'GBGE' then
            local distance = #(playerCoords - GetEntityCoords(vehicle))
            if distance < closestDistance then
                closest, closestDistance = vehicle, distance
            end
        end
    end

    if closest then
        state.vehicle = closest
        SetVehicleDoorsLocked(closest, 1)
    end
    return closest
end

local function setReturnRoute()
    if not state.vehicle or not DoesEntityExist(state.vehicle) then return end
    local unload = sharedConfig.locations.unload or sharedConfig.locations.main
    local depot = unload.coords
    removeBlipSafe(state.returnBlip)
    state.returnBlip = AddBlipForCoord(depot.x, depot.y, depot.z)
    SetBlipSprite(state.returnBlip, 1)
    SetBlipColour(state.returnBlip, 2)
    SetBlipRoute(state.returnBlip, true)
    SetBlipRouteColour(state.returnBlip, 2)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(unload.label or 'Ponto de descarga')
    EndTextCommandSetBlipName(state.returnBlip)

    removeZoneSafe(state.unloadZone)
    state.unloadZone = createSphereMonitor({
        coords = depot.xyz,
        radius = unload.radius or 8.0,
        debug = config.debugPoly,
        inside = function()
            local vehicle = state.vehicle
            local driving = vehicle and DoesEntityExist(vehicle)
                and GetPedInVehicleSeat(vehicle, -1) == PlayerPedId()
                and IsVehicleStopped(vehicle)
            if state.route and state.route.finished and isLeader() and driving and not state.unloading then
                OR.Help.Show('[E] Descarregar caminhao')
                if IsControlJustPressed(0, 38) then TriggerEvent('orbis-garbagejob:client:unloadVehicle') end
            end
        end,
        onExit = function() OR.Help.Hide() end
    })
end

local function throwUnloadBags()
    if not state.vehicle or not DoesEntityExist(state.vehicle) then return end
    local model = `prop_cs_rub_binbag_01`
    OR.Model.Load(model, 5000)
    if not HasModelLoaded(model) then return end

    for index = 1, 10 do
        if not state.vehicle or not DoesEntityExist(state.vehicle) then break end
        local offsetX = ((index % 3) - 1) * 0.7
        local spawn = GetOffsetFromEntityInWorldCoords(state.vehicle, offsetX, -4.8, 0.15)
        local bag = exports.ob_core:CreateNetworkedObject(model, spawn, true)
        if not bag or bag == 0 then break end
        SetEntityCollision(bag, true, true)
        ApplyForceToEntity(bag, 1, offsetX * 1.7, -2.5, 1.4, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
        SetTimeout(5500, function()
            if DoesEntityExist(bag) then exports.ob_core:DeleteNetworkedObject(bag) end
        end)
        Wait(500)
    end
    SetModelAsNoLongerNeeded(model)
end

AddEventHandler('orbis-garbagejob:client:unloadVehicle', function()
    if state.unloading or not state.route or not state.route.finished or not isLeader() then return end
    local vehicle = getJobVehicle()
    if not vehicle or not DoesEntityExist(vehicle) or GetPedInVehicleSeat(vehicle, -1) ~= PlayerPedId() then
        return notify('O lider precisa estacionar o caminhao para descarregar.', 'error')
    end

    state.unloading = true
    CreateThread(throwUnloadBags)
    local done = OR.Progress.Run({
        duration = 5500,
        label = 'Descarregando o caminhao...',
        useWhileDead = false,
        canCancel = false,
        disable = { car = true, move = true, combat = true }
    })
    if not done then state.unloading = false return end

    local ok, message = OR.Callback.await('garbagejob:server:unloadRoute', NetworkGetNetworkIdFromEntity(vehicle))
    state.unloading = false
    if not ok then return notify(message or 'Nao foi possivel descarregar.', 'error') end
    if DoesEntityExist(vehicle) then DeleteVehicle(vehicle) end
    notify('Carga descarregada. O pagamento foi enviado.', 'success')
end)

local function deliverBag()
    local vehicle = getJobVehicle()
    if state.depositingBag or not state.hasBag or not vehicle then return end
    state.depositingBag = true

    -- A compactadora abre na hora de jogar o saco e fecha ao concluir.
    SetVehicleDoorOpen(vehicle, 5, false, false)
    Wait(350)
    local done = OR.Progress.Run({
        duration = 1800,
        label = 'Colocando saco no caminhao...',
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, move = true, combat = true },
        anim = { dict = 'missfbi4prepp1', clip = '_bag_throw_garbage_man', flag = 48 }
    })
    if not done then
        SetVehicleDoorShut(vehicle, 5, false)
        state.depositingBag = false
        return
    end

    removeBagObject()
    removeTruckTarget()
    local success, routeOrError = OR.Callback.await('garbagejob:server:depositBag')
    if DoesEntityExist(vehicle) then SetVehicleDoorShut(vehicle, 5, false) end
    state.depositingBag = false
    if not success then notify(routeOrError or 'Nao foi possivel registrar o saco.', 'error') end
end

local function registerTruckDeliveryTarget()
    state.vehicle = getJobVehicle() or state.vehicle
    if not state.vehicle or not DoesEntityExist(state.vehicle) then return end

    -- O trash2 usa este mesmo offset na logica normal de descarte abaixo.
    -- Assim a area fica exatamente na boca traseira, nao na cabine/lateral.
    local rear = getTruckDisposalPoint(state.vehicle)

    removeTruckTarget()
    exports.ob_target:RegisterEntity('orbis_garbage_deliver', state.vehicle, {
        label = 'Jogar saco no caminhao',
        icon = 'fa-solid fa-trash-arrow-up',
        event = 'orbis-garbagejob:client:deliverGarbageTarget',
        canInteract = function(entity)
            if entity ~= state.vehicle or not state.hasBag then return false end
            return #(GetEntityCoords(PlayerPedId()) - rear) <= 3.5
        end,
    })
    exports.ob_target:RegisterSphereZone('orbis_garbage_deliver_zone', {
        coords = rear,
        radius = 4.0,
        option = {
            label = 'Jogar saco no caminhao',
            icon = 'fa-solid fa-trash-arrow-up',
            event = 'orbis-garbagejob:client:deliverGarbageTarget',
            canInteract = function()
                return state.hasBag and state.vehicle and DoesEntityExist(state.vehicle)
            end,
        },
    })
    state.truckTarget = true
end

function TakeAnim()
    if state.hasBag or not state.route or not state.route.active then return end
    local done = OR.Progress.Run({
        duration = math.random(3000, 5000),
        label = 'Pegando saco de lixo...',
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, move = true, combat = true },
        anim = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' }
    })
    if not done then return end

    OR.Model.Load(`prop_cs_rub_binbag_01`, 10000)
    state.bagObject = exports.ob_core:CreateNetworkedObject(`prop_cs_rub_binbag_01`, GetEntityCoords(PlayerPedId()), true)
    if not state.bagObject or state.bagObject == 0 then
        SetModelAsNoLongerNeeded(`prop_cs_rub_binbag_01`)
        return notify('Nao foi possivel criar o saco de lixo.', 'error')
    end
    AttachEntityToEntity(state.bagObject, PlayerPedId(), GetPedBoneIndex(PlayerPedId(), 57005), 0.12, 0.0, -0.05, 220.0, 120.0, 0.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(`prop_cs_rub_binbag_01`)
    state.hasBag = true
    if state.binZone then exports.ob_target:UnregisterZone(state.binZone) end
    state.binZone = nil

    -- Mantem o E como fallback e tambem tenta o target agora que o veiculo e
    -- resolvido pelo netId/placa corretamente.
    if config.useTarget then registerTruckDeliveryTarget() end
end

RegisterNetEvent('orbis-garbagejob:client:takeGarbageTarget', function()
    TakeAnim()
end)

RegisterNetEvent('orbis-garbagejob:client:deliverGarbageTarget', function()
    deliverBag()
end)

local function runWorkLoop()
    if not state.route or not state.route.active or not state.currentStop then return end
    local stop = sharedConfig.locations.trashcan[state.currentStop]
    if not stop then return end
    local playerCoords = GetEntityCoords(PlayerPedId())
    local stopDistance = #(playerCoords - stop.coords.xyz)

    if not state.hasBag and stopDistance <= 1.5 then
        OR.Help.Show('[E] Pegar saco de lixo')
        if IsControlJustPressed(0, 51) then
            OR.Help.Hide()
            TakeAnim()
        end
    elseif state.hasBag and state.vehicle and DoesEntityExist(state.vehicle) then
        local rear = getTruckDisposalPoint(state.vehicle)
        if #(playerCoords - rear) <= 2.0 then
            OR.Help.Show('[E] Descartar saco de lixo')
            if IsControlJustPressed(0, 51) then
                OR.Help.Hide()
                deliverBag()
            end
        else
            OR.Help.Hide()
        end
    elseif stopDistance > 2.0 then
        OR.Help.Hide()
    end
end

function SetGarbageRoute()
    if not state.route or not state.route.active or not state.currentStop then return end
    local stop = sharedConfig.locations.trashcan[state.currentStop]
    if not stop then return end

    removeBlipSafe(state.deliveryBlip)
    if state.binZone then exports.ob_target:UnregisterZone(state.binZone) end
    removeZoneSafe(state.workZone)
    state.binZone, state.workZone = nil, nil

    state.deliveryBlip = AddBlipForCoord(stop.coords.x, stop.coords.y, stop.coords.z)
    SetBlipSprite(state.deliveryBlip, 1)
    SetBlipColour(state.deliveryBlip, 2)
    SetBlipRoute(state.deliveryBlip, true)
    SetBlipRouteColour(state.deliveryBlip, 2)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(stop.name)
    EndTextCommandSetBlipName(state.deliveryBlip)

    if config.useTarget and not state.hasBag then
        state.binZone = 'orbis_garbage_bin'
        exports.ob_target:RegisterSphereZone(state.binZone, {
            coords = stop.coords.xyz,
            radius = 3.0,
            option = {
                label = 'Pegar saco de lixo',
                icon = 'fa-solid fa-trash',
                event = 'orbis-garbagejob:client:takeGarbageTarget',
                canInteract = function() return not state.hasBag and state.route and state.route.active end,
            },
        })
    end

    state.workZone = createSphereMonitor({
        coords = stop.coords.xyz,
        radius = 15.0,
        debug = config.debugPoly,
        onEnter = function()
            if state.vehicle and DoesEntityExist(state.vehicle) then SetVehicleDoorOpen(state.vehicle, 5, false, false) end
        end,
        inside = function()
            if not config.useTarget then runWorkLoop() end
        end,
        onExit = function()
            OR.Help.Hide()
            if state.vehicle and DoesEntityExist(state.vehicle) then SetVehicleDoorShut(state.vehicle, 5, false) end
        end
    })
end

-- Marca somente a lixeira da parada atual, inclusive quando existem varias no mesmo quarteirao.
CreateThread(function()
    while true do
        local route = state.route
        local stop = route and route.active and state.currentStop and sharedConfig.locations.trashcan[state.currentStop]
        if stop and #(GetEntityCoords(PlayerPedId()) - stop.coords.xyz) <= 180.0 then
            local coords = stop.coords
            DrawMarker(2, coords.x, coords.y, coords.z + 1.15, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0,
                0.38, 0.38, 0.38, 105, 220, 125, 235, false, true, 2, false, nil, nil, false)
            DrawLightWithRange(coords.x, coords.y, coords.z + 1.0, 105, 220, 125, 2.2, 1.15)
            Wait(0)
        elseif route and route.finished then
            local unload = sharedConfig.locations.unload
            if unload and #(GetEntityCoords(PlayerPedId()) - unload.coords.xyz) <= 180.0 then
                local coords = unload.coords
                DrawMarker(1, coords.x, coords.y, coords.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    (unload.radius or 8.0) * 2.0, (unload.radius or 8.0) * 2.0, 0.35, 62, 190, 92, 105,
                    false, false, 2, false, nil, nil, false)
                Wait(0)
            else
                Wait(700)
            end
        else
            Wait(700)
        end
    end
end)

AddEventHandler('orbis-garbagejob:client:applyRoute', function(route)
    state.route = route
    sendRouteProgress(route)
    if not route then return end
    ensureVehicle(route.vehicleNet)
    if route.finished then
        removeBlipSafe(state.deliveryBlip)
        state.deliveryBlip = nil
        if state.binZone then exports.ob_target:UnregisterZone(state.binZone) end
        state.binZone = nil
        removeZoneSafe(state.workZone)
        state.workZone = nil
        setReturnRoute()
        notify('Rota concluida. Estacione no ponto de descarga para receber.', 'success')
        return
    end

    state.currentStop = route.nextStop
    state.bags = route.bags
    SetGarbageRoute()
end)

RegisterNetEvent('orbis-garbagejob:client:syncRoute', function(route)
    TriggerEvent('orbis-garbagejob:client:applyRoute', route)
end)

local function getNearbyPlayers()
    local nearby, myCoords = {}, GetEntityCoords(PlayerPedId())
    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() then
            local ped = GetPlayerPed(player)
            if ped ~= 0 and #(myCoords - GetEntityCoords(ped)) <= (config.groupInviteDistance or 18.0) then
                nearby[#nearby + 1] = { id = GetPlayerServerId(player), name = GetPlayerName(player) or ('ID %s'):format(GetPlayerServerId(player)) }
            end
        end
    end
    return nearby
end

local function sendPanel(action, payload)
    SendNUIMessage({ action = action, payload = payload })
end

local function refreshPanel(open)
    local data = OR.Callback.await('garbagejob:server:getPanelData')
    if not data then return end
    state.group = data.group
    data.nearby = getNearbyPlayers()
    data.tutorial = GarbageSharedConfig.Tutorial
    if open then
        state.panelOpen = true
        SetNuiFocus(true, true)
        sendPanel('open', data)
    else
        sendPanel('update', data)
    end
end

local function openPanel()
    refreshPanel(true)
end

RegisterNetEvent('orbis-garbagejob:client:openPanel', openPanel)

local function closePanel()
    state.panelOpen = false
    SetNuiFocus(false, false)
    sendPanel('close', {})
end

local function requestRoute()
    if not isLeader() then return notify('Somente o lider do grupo pode iniciar uma rota.', 'error') end
    if state.route and state.route.active then return notify('A rota atual ainda esta em andamento.', 'error') end
    if state.route and state.route.finished then return notify('Descarregue o caminhao antes de iniciar outra rota.', 'error') end

    local ok, routeOrError = OR.Callback.await('garbagejob:server:newShift')
    if not ok then return notify(routeOrError or 'Nao foi possivel iniciar a rota.', 'error') end

    if not state.vehicle or not DoesEntityExist(state.vehicle) then
        local spawn
        for _, coords in pairs(sharedConfig.locations.vehicle.coords) do
            if not IsAnyVehicleNearPoint(coords.x, coords.y, coords.z, 2.5) then spawn = coords break end
        end
        if not spawn then return notify('Todas as vagas estao ocupadas.', 'error') end

        local netId = OR.Callback.await('garbagejob:server:spawnVehicle', spawn)
        if not netId then return notify('Nao foi possivel liberar o caminhao. Verifique se ha uma vaga livre e tente novamente.', 'error') end
        ensureVehicle(netId)
        SetTimeout(700, function()
            if state.vehicle and DoesEntityExist(state.vehicle) then
                SetVehicleFuelLevel(state.vehicle, 100.0)
                SetVehicleFixed(state.vehicle)
            end
        end)
    end

    TriggerEvent('orbis-garbagejob:client:applyRoute', routeOrError)
    notify('Servico iniciado. O primeiro ponto foi marcado no GPS.', 'success')
    if state.panelOpen then refreshPanel(false) end
end

local function cancelRoute()
    if not isLeader() then return notify('Somente o lider pode cancelar a rota.','error') end
    if not state.route then return notify('Nao existe rota ativa para cancelar.','error') end
    local confirmed=OR.Dialog.Confirm({header='Cancelar rota',
        content='A rota sera encerrada para todo o grupo e a coleta atual nao sera paga.',centered=true,cancel=true,
        labels={confirm='Cancelar rota',cancel='Continuar trabalhando'}})
    if not confirmed then return end
    local ok,message=OR.Callback.await('garbagejob:server:cancelShift')
    if not ok then return notify(message or 'Nao foi possivel cancelar a rota.','error') end
    resetLocalRoute(false);state.vehicle=nil
    notify(message or 'Rota cancelada.','inform')
    if state.panelOpen then refreshPanel(false) end
end

RegisterNetEvent('orbis-garbagejob:client:groupUpdated', function(group)
    state.group = group
    if state.panelOpen then refreshPanel(false) end
end)

RegisterNetEvent('orbis-garbagejob:client:groupInvite', function(invite)
    CreateThread(function()
        local answer = OR.Dialog.Confirm({
            header = 'Grupo de Lixeiros',
            content = ('%s convidou voce para o grupo de coleta.'):format(invite.name),
            centered = true,
            cancel = true,
            labels = { confirm = 'Entrar', cancel = 'Recusar' }
        })
        local ok, message = OR.Callback.await('garbagejob:server:answerInvite', answer)
        if message then notify(message, ok and 'success' or 'error') end
    end)
end)

RegisterNetEvent('orbis-garbagejob:client:shiftPaid', function(data)
    notify(('Pagamento recebido na mochila: %s | +%s XP'):format(OR.FormatMoney(data.reward or 0), data.xp or 0), 'success')
    if state.panelOpen and data.panel then
        data.panel.nearby = getNearbyPlayers()
        sendPanel('update', data.panel)
    end
end)

RegisterNetEvent('orbis-garbagejob:client:shiftEnded', function()
    resetLocalRoute(false)
    state.vehicle = nil
    if state.panelOpen then refreshPanel(false) end
end)

RegisterNUICallback('close', function(_, cb) closePanel(); cb('ok') end)
RegisterNUICallback('refresh', function(_, cb) refreshPanel(false); cb('ok') end)
RegisterNUICallback('startRoute', function(_, cb) requestRoute(); cb('ok') end)
RegisterNUICallback('cancelRoute',function(_,cb) cancelRoute();cb('ok') end)
RegisterNUICallback('invite', function(data, cb)
    local ok, message = OR.Callback.await('garbagejob:server:inviteMember', data and data.id)
    if message then notify(message, ok and 'success' or 'error') end
    if state.panelOpen then refreshPanel(false) end
    cb(ok and 'ok' or 'fail')
end)
RegisterNUICallback('leaveGroup', function(_, cb)
    local ok, message = OR.Callback.await('garbagejob:server:leaveGroup')
    if message then notify(message, ok and 'success' or 'error') end
    if state.panelOpen then refreshPanel(false) end
    cb(ok and 'ok' or 'fail')
end)

local function registerBossTarget(index, entry)
    if not config.useTarget or GetResourceState('ob_target') ~= 'started' then return end
    if not entry.pedHandle or not DoesEntityExist(entry.pedHandle) then return end
    exports.ob_target:RegisterEntity(('orbis_garbage_boss_%s'):format(index), entry.pedHandle, {
        label = 'Central de Lixeiros',
        icon = 'fa-solid fa-recycle',
        event = 'orbis-garbagejob:client:openPanel',
        distance = 3.0,
        canInteract = function(entity)
            return entity == entry.pedHandle
        end,
    })
end

local function createBossBlip(entry)
    local cfg = entry.blip
    if not cfg or cfg.enabled == false then return end
    if entry.blipHandle and DoesBlipExist(entry.blipHandle) then return end

    local coords = entry.coords
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, cfg.sprite or 318)
    SetBlipDisplay(blip, 4)
    SetBlipColour(blip, cfg.color or 25)
    SetBlipScale(blip, cfg.scale or 0.75)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(cfg.name or 'Central de Lixeiros')
    EndTextCommandSetBlipName(blip)
    entry.blipHandle = blip
end

local function spawnPeds()
    if state.pedsSpawned then return end
    for index, entry in ipairs(config.peds or {}) do
        local model = type(entry.model) == 'string' and joaat(entry.model) or entry.model
        OR.Model.Load(model, 20000)
        local ped = CreatePed(0, model, entry.coords.x, entry.coords.y, entry.coords.z, entry.coords.w, false, false)
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetModelAsNoLongerNeeded(model)
        entry.pedHandle = ped
        createBossBlip(entry)
        registerBossTarget(index, entry)
    end
    state.pedsSpawned = true
    print(('[ob_garbagejob] %s ponto(s) criado(s).'):format(#(config.peds or {})))
end

AddEventHandler('ob_target:client:ready', function()
    for index, entry in ipairs(config.peds or {}) do
        registerBossTarget(index, entry)
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    closePanel()
    resetLocalRoute(false)
    for index, entry in ipairs(config.peds or {}) do
        if entry.pedHandle and DoesEntityExist(entry.pedHandle) then
            exports.ob_target:RemoveEntityOption(('orbis_garbage_boss_%s'):format(index))
            DeletePed(entry.pedHandle)
        end
        if entry.blipHandle and DoesBlipExist(entry.blipHandle) then
            RemoveBlip(entry.blipHandle)
            entry.blipHandle = nil
        end
    end
end)

CreateThread(function()
    while LocalPlayer.state['or:loaded'] ~= true do Wait(250) end
    spawnPeds()
end)

CreateThread(function()
    while LocalPlayer.state['or:loaded'] ~= true do Wait(250) end
    for index, entry in ipairs(config.peds or {}) do
        while not entry.pedHandle or not DoesEntityExist(entry.pedHandle) do Wait(250) end
        registerBossTarget(index, entry)
    end
    print('[ob_garbagejob] Target do NPC registrado apos o carregamento.')
end)
