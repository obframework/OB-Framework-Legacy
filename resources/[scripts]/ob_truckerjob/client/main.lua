local assignment = false
local group = { members = {}, isLeader = true, maxMembers = 4 }
local npc, npcBlip, routeBlip, deliveryCheckpoint = 0, 0, 0, 0
local panelOpen, currentRouteKey, destructionReported = false, nil, false
local truckEntity, trailerEntity = 0, 0
local trackedTruckNetId, trackedTrailerNetId = nil, nil
local truckLocated, trailerLocated = false, false
local autoSpawnBusy, nextAutoSpawnAt = false, 0

local MarkerTypeUpsideDownCone = 0
local MarkerTypeHorizontalSplitArrowCircle = 27

local function notify(message, kind) OR.Notify(message, kind or 'info') end

local function cargoIntegrity(bodyHealth)
    bodyHealth = tonumber(bodyHealth) or 0.0
    if bodyHealth <= Trucker.payment.destroyedBodyHealth then return 0.0 end
    local rawIntegrity = math.max(0.0, math.min(100.0, bodyHealth / 10.0))
    local damage = (100.0 - rawIntegrity) * (Trucker.payment.damageToIntegrity or 0.20)
    return math.max(0.0, math.min(100.0, 100.0 - damage))
end

local function loadModel(name)
    local model = joaat(name)
    if not IsModelInCdimage(model) or not IsModelValid(model) then return nil end
    RequestModel(model)
    local deadline = GetGameTimer() + 6000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(20) end
    return HasModelLoaded(model) and model or nil
end

local function resolveNetEntity(netId)
    netId = tonumber(netId)
    if not netId then return 0 end
    local entity = NetworkGetEntityFromNetworkId(netId)
    return entity ~= 0 and DoesEntityExist(entity) and entity or 0
end

local function removeRoute()
    if routeBlip ~= 0 and DoesBlipExist(routeBlip) then RemoveBlip(routeBlip) end
    routeBlip = 0
end

local function setRoute(coords, label)
    removeRoute()
    routeBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(routeBlip, 478)
    SetBlipColour(routeBlip, 5)
    SetBlipScale(routeBlip, 0.82)
    SetBlipRoute(routeBlip, true)
    SetBlipRouteColour(routeBlip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label)
    EndTextCommandSetBlipName(routeBlip)
end

local function clearCheckpoint()
    if deliveryCheckpoint ~= 0 then DeleteCheckpoint(deliveryCheckpoint) end
    deliveryCheckpoint = 0
end

local function createDeliveryCheckpoint(coords)
    clearCheckpoint()
    local groundZ = coords.z + (Trucker.delivery.groundOffset or -0.30)
    deliveryCheckpoint = CreateCheckpoint(Trucker.delivery.checkpointType or 47,
        coords.x, coords.y, groundZ, coords.x, coords.y, groundZ,
        Trucker.delivery.radius * 2.0, 30, 170, 255, 170, 0)
    SetCheckpointCylinderHeight(deliveryCheckpoint, 0.5, 0.5, Trucker.delivery.radius * 2.0)
end

local function instructionForState()
    if not assignment or not assignment.active then return nil end
    if assignment.state == 'waiting_truck' then return 'Seu caminhao esta sendo preparado no patio.' end
    if assignment.state == 'pickup_cargo' then return 'Leve o caminhao ao patio; sua carga sera liberada automaticamente.' end
    if assignment.state == 'need_cargo' then return 'Sua carga foi perdida. Volte ao patio para receber outra carreta.' end
    if assignment.state == 'delivering' then
        if truckEntity ~= 0 and trailerEntity ~= 0 and IsVehicleAttachedToTrailer(truckEntity) then
            return ('Entregue %s em %s.'):format(assignment.cargoLabel, assignment.destinationLabel)
        end
        return 'Engate sua carreta marcada em azul e siga para o destino.'
    end
    if assignment.state == 'return_truck' then return 'Carga guardada. Devolva o caminhao na area azul da transportadora.' end
    return nil
end

local function sendHud()
    if not assignment or not assignment.active then
        SendNUIMessage({ action = 'jobHud', payload = false })
        return
    end
    local integrity
    if assignment.state == 'delivering' and trailerEntity ~= 0 and DoesEntityExist(trailerEntity) then
        integrity = cargoIntegrity(GetVehicleBodyHealth(trailerEntity))
    end
    SendNUIMessage({ action = 'jobHud', payload = {
        state = assignment.state,
        cargo = assignment.cargoLabel,
        destination = assignment.destinationLabel,
        distance = assignment.distanceKm,
        integrity = integrity,
        instruction = instructionForState(),
    } })
end

local function applyAssignment(payload)
    local newTruckNetId = payload and payload.truckNetId or nil
    local newTrailerNetId = payload and payload.trailerNetId or nil
    if newTruckNetId ~= trackedTruckNetId then
        trackedTruckNetId, truckLocated = newTruckNetId, false
    end
    if newTrailerNetId ~= trackedTrailerNetId then
        trackedTrailerNetId, trailerLocated = newTrailerNetId, false
    end
    assignment = payload or false
    truckEntity = assignment and resolveNetEntity(assignment.truckNetId) or 0
    trailerEntity = assignment and resolveNetEntity(assignment.trailerNetId) or 0
    destructionReported = false

    local routeKey = assignment and table.concat({ assignment.state or '', assignment.truckNetId or '',
        assignment.trailerNetId or '', assignment.destinationLabel or '' }, ':') or 'none'
    if routeKey ~= currentRouteKey then
        currentRouteKey = routeKey
        clearCheckpoint()
        if not assignment or not assignment.active then
            removeRoute()
        elseif assignment.state == 'waiting_truck' then
            setRoute(Trucker.depot.truckSpawns[1].xyz, 'Retirada do caminhão')
        elseif assignment.state == 'pickup_cargo' or assignment.state == 'need_cargo' then
            setRoute(Trucker.depot.cargoCenter, 'Pátio de cargas')
        elseif assignment.state == 'delivering' and assignment.destination then
            local destination = vec3(assignment.destination.x, assignment.destination.y, assignment.destination.z)
            if truckEntity ~= 0 and trailerEntity ~= 0 and IsVehicleAttachedToTrailer(truckEntity) then
                setRoute(destination, assignment.destinationLabel)
                createDeliveryCheckpoint(destination)
            else
                setRoute(Trucker.depot.cargoCenter, 'Patio de cargas')
            end
        elseif assignment.state == 'return_truck' then
            setRoute(Trucker.depot.returnArea.coords, 'Devolução do caminhão')
        end
    end
    sendHud()
end

RegisterNetEvent('orbis-truckerjob:client:assignment', applyAssignment)

local function getNearbyPlayers()
    local result, coords = {}, GetEntityCoords(PlayerPedId())
    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() then
            local ped = GetPlayerPed(player)
            if ped ~= 0 and #(coords - GetEntityCoords(ped)) <= Trucker.group.inviteDistance then
                result[#result + 1] = { id = GetPlayerServerId(player), name = GetPlayerName(player) or ('ID %s'):format(GetPlayerServerId(player)) }
            end
        end
    end
    return result
end

local function refreshPanel(open)
    local data, message = OR.Callback.await('orbis-truckerjob:server:getPanelData')
    if not data then return notify(message or 'Painel indisponivel.', 'error') end
    group = data.group or group
    data.nearby = getNearbyPlayers()
    if open then
        panelOpen = true
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'open', payload = data })
    else
        SendNUIMessage({ action = 'update', payload = data })
    end
end

local function closePanel()
    panelOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterNetEvent('orbis-truckerjob:client:openPanel', function() refreshPanel(true) end)
RegisterNetEvent('orbis-truckerjob:client:groupUpdated', function(payload)
    group = payload or group
    if panelOpen then refreshPanel(false) end
end)
RegisterNetEvent('orbis-truckerjob:client:offersUpdated', function()
    if panelOpen then refreshPanel(false) end
end)
RegisterNetEvent('orbis-truckerjob:client:invite', function(name)
    CreateThread(function()
        local accepted = OR.Dialog.Confirm({
            header = 'Equipe de caminhoneiros',
            content = ('%s convidou voce para uma equipe.'):format(name),
            centered = true, cancel = true,
            labels = { confirm = 'Entrar', cancel = 'Recusar' },
        })
        local ok, message = OR.Callback.await('orbis-truckerjob:server:answerInvite', accepted)
        if message then notify(message, ok and 'success' or 'error') end
    end)
end)
RegisterNetEvent('orbis-truckerjob:client:paid', function(money, xp, integrity)
    notify(('Entrega paga: %s | +%s XP | carga %.1f%%'):format(OR.FormatMoney(money), xp, integrity), 'success')
end)

RegisterNUICallback('close', function(_, cb) closePanel(); cb('ok') end)
RegisterNUICallback('allocateSkill', function(data, cb)
    local ok, payload = OR.Callback.await('orbis-truckerjob:server:allocateSkill', data and data.skill)
    if not ok then notify(payload or 'Nao foi possivel distribuir o ponto.', 'error')
    elseif payload then
        payload.nearby = getNearbyPlayers()
        SendNUIMessage({ action = 'update', payload = payload })
    end
    cb(ok and 'ok' or 'fail')
end)
RegisterNUICallback('acceptOffer', function(data, cb)
    local ok, message = OR.Callback.await('orbis-truckerjob:server:acceptOffer', data and data.id)
    if message then notify(message, ok and 'success' or 'error') end
    if ok then closePanel() else refreshPanel(false) end
    cb(ok and 'ok' or 'fail')
end)
RegisterNUICallback('invite', function(data, cb)
    local ok, message = OR.Callback.await('orbis-truckerjob:server:invite', data and data.id)
    if message then notify(message, ok and 'success' or 'error') end
    refreshPanel(false); cb(ok and 'ok' or 'fail')
end)
RegisterNUICallback('leaveGroup', function(_, cb)
    local ok, message = OR.Callback.await('orbis-truckerjob:server:leaveGroup')
    if message then notify(message, ok and 'success' or 'error') end
    refreshPanel(false); cb(ok and 'ok' or 'fail')
end)
RegisterNUICallback('cancelAssignment', function(_, cb)
    local ok, message = OR.Callback.await('orbis-truckerjob:server:cancelAssignment')
    if message then notify(message, ok and 'success' or 'error') end
    if ok then closePanel() else refreshPanel(false) end
    cb(ok and 'ok' or 'fail')
end)

local function spawnTruck(quiet)
    local ok, data = OR.Callback.await('orbis-truckerjob:server:spawnTruck')
    if not ok then
        if not quiet then notify(data or 'Nao foi possivel retirar o caminhao.', 'error') end
        return false
    end
    truckEntity = OR.Entity.AwaitNetwork(data.netId, 10000) or 0
    trailerEntity = OR.Entity.AwaitNetwork(data.trailerNetId, 10000) or 0
    if truckEntity ~= 0 then
        SetVehicleOnGroundProperly(truckEntity)
        SetVehicleFuelLevel(truckEntity, 100.0)
    end
    notify('Seu caminhao e sua carga estao prontos. Destranque o caminhao e va ao patio.', 'success')
    return true
end

local function spawnTrailer(quiet)
    local ok, result = OR.Callback.await('orbis-truckerjob:server:spawnTrailer')
    if not ok then
        if not quiet then notify(result or 'Nao foi possivel retirar a carga.', 'error') end
        return false
    end
    trailerEntity = OR.Entity.AwaitNetwork(result, 10000) or 0
    notify('Carga liberada. Engate a carreta marcada em azul.', 'success')
    return true
end

local function deliverCargo()
    if truckEntity == 0 or trailerEntity == 0 then return notify('Seu conjunto ainda nao sincronizou.', 'error') end
    if IsVehicleAttachedToTrailer(truckEntity) then return notify('Desengate a carreta dentro da area antes de guardar a carga.', 'error') end
    local integrity = cargoIntegrity(GetVehicleBodyHealth(trailerEntity))
    local ok, message = OR.Callback.await('orbis-truckerjob:server:deliverCargo', integrity)
    if message then notify(message, ok and 'success' or 'error') end
end

local function returnTruck()
    local ok, message = OR.Callback.await('orbis-truckerjob:server:returnTruck')
    if message then notify(message, ok and 'success' or 'error') end
end

local function drawWorldText(coords, text)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    SetTextFont(4); SetTextScale(0.0, 0.31); SetTextColour(255, 255, 255, 235)
    SetTextCentre(true); SetTextOutline()
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(text); EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function drawGroundMarker(markerType, coords, scale, color)
    DrawMarker(markerType, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        scale.x, scale.y, scale.z, color[1], color[2], color[3], color[4], false, false, 2, false, nil, nil, false)
end

local function markerAbove(entity, label)
    if entity == 0 or not DoesEntityExist(entity) then return end
    local _, maximum = GetModelDimensions(GetEntityModel(entity))
    local coords = GetOffsetFromEntityInWorldCoords(entity, 0.0, 0.0, (maximum and maximum.z or 2.0) + 0.75)
    DrawMarker(MarkerTypeUpsideDownCone, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        0.48, 0.48, 0.42, 20, 155, 255, 225, true, true, 2, true, nil, nil, false)
    local playerDistance = #(GetEntityCoords(PlayerPedId()) - coords)
    if playerDistance < 18.0 then drawWorldText(coords + vec3(0, 0, 0.4), label) end
end

CreateThread(function()
    while true do
        if not assignment or not assignment.active then
            OR.Help.Hide(); Wait(600)
        else
            local ped, coords = PlayerPedId(), GetEntityCoords(PlayerPedId())
            local interaction, help
            truckEntity = resolveNetEntity(assignment.truckNetId)
            trailerEntity = resolveNetEntity(assignment.trailerNetId)

            if truckEntity ~= 0 and IsPedInVehicle(ped, truckEntity, false) then truckLocated = true end
            if truckEntity ~= 0 and trailerEntity ~= 0 and IsVehicleAttachedToTrailer(truckEntity) and not trailerLocated then
                trailerLocated = true
                if assignment.state == 'delivering' and assignment.destination then
                    local destination = vec3(assignment.destination.x, assignment.destination.y, assignment.destination.z)
                    setRoute(destination, assignment.destinationLabel)
                    createDeliveryCheckpoint(destination)
                end
            end
            if truckEntity ~= 0 and not truckLocated then markerAbove(truckEntity, 'Seu caminhão') end
            if trailerEntity ~= 0 and not trailerLocated then markerAbove(trailerEntity, 'Sua carga') end

            if assignment.state == 'waiting_truck' then
                if not autoSpawnBusy and GetGameTimer() >= nextAutoSpawnAt then
                    autoSpawnBusy, nextAutoSpawnAt = true, GetGameTimer() + 3000
                    CreateThread(function()
                        spawnTruck(true)
                        autoSpawnBusy = false
                    end)
                end
            elseif assignment.state == 'pickup_cargo' or assignment.state == 'need_cargo' then
                if #(coords - Trucker.depot.cargoCenter) <= 45.0
                    and not autoSpawnBusy and GetGameTimer() >= nextAutoSpawnAt then
                    autoSpawnBusy, nextAutoSpawnAt = true, GetGameTimer() + 3000
                    CreateThread(function()
                        spawnTrailer(true)
                        autoSpawnBusy = false
                    end)
                end
            elseif assignment.state == 'delivering' and assignment.destination then
                local destination = vec3(assignment.destination.x, assignment.destination.y, assignment.destination.z)
                local distance = #(coords - destination)
                if distance <= Trucker.delivery.radius + 6.0 and trailerEntity ~= 0
                    and #(GetEntityCoords(trailerEntity) - destination) <= Trucker.delivery.radius then
                    help, interaction = '[E] Guardar carga desacoplada', deliverCargo
                end
            elseif assignment.state == 'return_truck' then
                local area = Trucker.depot.returnArea
                local distance = #(coords - area.coords)
                if distance < Trucker.depot.drawDistance then
                    drawGroundMarker(MarkerTypeHorizontalSplitArrowCircle,
                        area.coords + vec3(0.0, 0.0, area.groundOffset or -0.30),
                        vec3(area.radius * 2.0, area.radius * 2.0, 1.0), { 20, 155, 255, 125 })
                end
                if truckEntity ~= 0 and #(GetEntityCoords(truckEntity) - area.coords) <= area.radius then
                    help, interaction = '[E] Devolver caminhao e receber', returnTruck
                end
            end

            if help and interaction then
                OR.Help.Show(help)
                if IsControlJustReleased(0, 38) then OR.Help.Hide(); interaction() end
            else OR.Help.Hide() end
            Wait(0)
        end
    end
end)

CreateThread(function()
    while true do
        if assignment and assignment.active and assignment.state == 'delivering' then
            trailerEntity = resolveNetEntity(assignment.trailerNetId)
            if trailerEntity ~= 0 then
                local health = GetVehicleBodyHealth(trailerEntity)
                if health <= Trucker.payment.destroyedBodyHealth and not destructionReported then
                    destructionReported = true
                    OR.Callback.await('orbis-truckerjob:server:reportDestroyedCargo')
                end
            end
            sendHud()
            Wait(800)
        else Wait(1500) end
    end
end)

local function registerNpcTarget()
    if npc == 0 or not DoesEntityExist(npc) or GetResourceState('ob_target') ~= 'started' then return end
    exports.ob_target:RegisterEntity('orbis_truckerjob_npc', npc, {
        icon = 'fas fa-truck', label = 'Falar com transportadora',
        event = 'orbis-truckerjob:client:openPanel', distance = 3.0,
        canInteract = function(entity) return entity == npc end,
    })
end

AddEventHandler('ob_target:client:ready', registerNpcTarget)

CreateThread(function()
    while LocalPlayer.state['or:loaded'] ~= true do Wait(250) end
    local status, payloadGroup = OR.Callback.await('orbis-truckerjob:server:getStatus')
    group = payloadGroup or group
    applyAssignment(status)

    local cfg, model = Trucker.npc, loadModel(Trucker.npc.model)
    if model then
        npc = CreatePed(4, model, cfg.coords.x, cfg.coords.y, cfg.coords.z - 1.0, cfg.coords.w, false, true)
        FreezeEntityPosition(npc, true); SetEntityInvincible(npc, true); SetBlockingOfNonTemporaryEvents(npc, true)
        if cfg.scenario then TaskStartScenarioInPlace(npc, cfg.scenario, 0, true) end
        SetModelAsNoLongerNeeded(model)
        registerNpcTarget()
    end
    npcBlip = AddBlipForCoord(cfg.coords.x, cfg.coords.y, cfg.coords.z)
    SetBlipSprite(npcBlip, cfg.blip.sprite); SetBlipColour(npcBlip, cfg.blip.color)
    SetBlipScale(npcBlip, cfg.blip.scale); SetBlipAsShortRange(npcBlip, true)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString(cfg.blip.name); EndTextCommandSetBlipName(npcBlip)
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    closePanel(); clearCheckpoint(); removeRoute(); OR.Help.Hide()
    if GetResourceState('ob_target') == 'started' then exports.ob_target:RemoveEntityOption('orbis_truckerjob_npc') end
    if npc ~= 0 and DoesEntityExist(npc) then DeleteEntity(npc) end
    if npcBlip ~= 0 and DoesBlipExist(npcBlip) then RemoveBlip(npcBlip) end
    TriggerServerEvent('orbis-truckerjob:server:forceStop')
end)
