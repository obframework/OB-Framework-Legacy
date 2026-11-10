local state = {
    shift = false,
    vehicle = nil,
    vehiclePlate = nil,
    vehicleModel = nil,
    selectedVehicleModel = nil,
    ride = nil,
    ridePeds = {},
    pickupBlip = nil,
    dropoffBlip = nil,
    bossPed = nil,
    bossBlip = nil,
    panelOpen = false,
    callsPanelOpen = false,
    panelData = nil,
    fallbackUiShown = false,
    appTaxiCaller = nil,
    meter = {
        active = false,
        pending = false,
        passenger = nil,
        fare = 0,
        distance = 0.0,
        startedAt = 0,
        lastPos = nil,
        lastTick = 0
    }
}

local closeCallsPanel
local sendPanelMessage
local pendingMeterConfirm = nil
local blockedPassengerHashes = {
    [joaat('u_m_y_abner')] = true
}

local function notify(desc, typ, duration)
    OR.Notify(desc, typ or 'info', duration)
end

local function vec3From4(v4)
    return vec3(v4.x, v4.y, v4.z)
end

local function getGroundZ(x, y, z)
    local found, ground = GetGroundZFor_3dCoord(x, y, z + 2.5, false)
    if found and ground then
        return ground
    end
    return z
end

local function getPedSpawnCoord(base, index)
    local heading = math.rad(base.w or 0.0)
    local rightX = math.cos(heading)
    local rightY = -math.sin(heading)
    local fwdX = -math.sin(heading)
    local fwdY = math.cos(heading)

    local sideOffsets = { 4.8, -4.8, 6.2, -6.2, 3.2, -3.2, 0.0 }
    local fwdOffsets = { 1.2, 2.4, -1.2, 3.6, -2.0, 0.0 }

    local rot = ((index or 1) - 1) % #sideOffsets
    local start = rot + 1

    for i = 0, #sideOffsets - 1 do
        local idx = ((start + i - 1) % #sideOffsets) + 1
        local side = sideOffsets[idx]
        local fwd = fwdOffsets[idx] or 0.0

        local x = base.x + (rightX * side) + (fwdX * fwd)
        local y = base.y + (rightY * side) + (fwdY * fwd)
        local z = getGroundZ(x, y, base.z)

        if not IsPointOnRoad(x, y, z, 0) then
            return vector4(x, y, z, base.w or 0.0)
        end
    end

    local fallbackX = base.x + (rightX * 5.0)
    local fallbackY = base.y + (rightY * 5.0)
    local fallbackZ = getGroundZ(fallbackX, fallbackY, base.z)
    return vector4(fallbackX, fallbackY, fallbackZ, base.w or 0.0)
end

local function getRandomPassengerModel()
    local fallback = 'a_m_y_business_01'
    local list = Config.PedModels or {}

    if type(Config.PedBlacklistModels) == 'table' then
        for _, model in ipairs(Config.PedBlacklistModels) do
            if type(model) == 'string' and model ~= '' then
                blockedPassengerHashes[joaat(model)] = true
            end
        end
    end

    if #list == 0 then
        return fallback
    end

    for _ = 1, 20 do
        local model = list[math.random(1, #list)]
        if type(model) == 'string' and model ~= '' and not blockedPassengerHashes[joaat(model)] then
            return model
        end
    end

    return fallback
end

local function sanitizePlate(plate)
    if type(plate) ~= 'string' then return '' end
    return plate:gsub('%W', ''):upper()
end

local function setMeterVisible(visible)
    sendPanelMessage('meterVisibility', { show = visible == true })
end

local function updateMeterHud()
    local meter = state.meter
    sendPanelMessage('meterUpdate', {
        fare = meter.fare or 0,
        distance = meter.distance or 0,
        elapsed = meter.startedAt > 0 and math.max(0, GetGameTimer() - meter.startedAt) or 0
    })
end

local function resetMeter()
    state.meter.active = false
    state.meter.pending = false
    state.meter.passenger = nil
    state.meter.fare = 0
    state.meter.distance = 0.0
    state.meter.startedAt = 0
    state.meter.lastPos = nil
    state.meter.lastTick = 0
    updateMeterHud()
    setMeterVisible(false)
end

local function respondMeterConfirmation(accept)
    if not pendingMeterConfirm then return end
    local reqId = pendingMeterConfirm.id
    pendingMeterConfirm = nil
    TriggerServerEvent('orbis-busjobs:server:meterResponse', reqId, accept == true)
end

local function getPassengerServerIdInVehicle(vehicle)
    local myPlayer = PlayerId()
    local players = GetActivePlayers()
    for i = 1, #players do
        local player = players[i]
        if player ~= myPlayer then
            local ped = GetPlayerPed(player)
            if ped and ped ~= 0 and IsPedInVehicle(ped, vehicle, false) then
                return GetPlayerServerId(player)
            end
        end
    end
    return nil
end

local function isPassengerStillInVehicle(serverId, vehicle)
    if not serverId then return false end
    local ply = GetPlayerFromServerId(serverId)
    if ply == -1 then return false end
    local ped = GetPlayerPed(ply)
    return ped and ped ~= 0 and IsPedInVehicle(ped, vehicle, false)
end

local function startMeterForPassenger(serverId)
    state.meter.active = true
    state.meter.pending = false
    state.meter.passenger = serverId
    state.meter.fare = tonumber(Config.Meter and Config.Meter.baseFare or 25) or 25
    state.meter.distance = 0.0
    state.meter.startedAt = GetGameTimer()
    state.meter.lastPos = GetEntityCoords(state.vehicle)
    state.meter.lastTick = GetGameTimer()
    updateMeterHud()
    setMeterVisible(true)
    notify('Taximetro iniciado.', 'inform')
end

local function getVehicleCfg(model)
    if type(model) ~= 'string' then return nil end
    local lower = model:lower()
    for _, cfg in ipairs(Config.Vehicles) do
        if cfg.model:lower() == lower then
            return cfg
        end
    end
    return nil
end

local function removeBlipSafe(blip)
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
end

local function clearRideBlips()
    removeBlipSafe(state.pickupBlip)
    removeBlipSafe(state.dropoffBlip)
    state.pickupBlip = nil
    state.dropoffBlip = nil
end

local function setVehicleFuel(vehicle, amount)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return
    end
    -- ob_fuel le e acompanha o native do veiculo; nao existe ponte para
    -- recursos de combustivel externos.
    SetVehicleFuelLevel(vehicle, math.max(0.0, math.min(100.0, tonumber(amount) or 100.0)))
end

-- Chamado vindo do aplicativo local do NPWD. Ele nao abre nenhuma NUI e nao
-- cria entidade: somente marca o passageiro para o taxista em servico.
RegisterNetEvent('orbis-busjobs:client:phoneDispatch', function(data)
    if type(data) ~= 'table' or type(data.coords) ~= 'table' then return end
    local x, y = tonumber(data.coords.x), tonumber(data.coords.y)
    if not x or not y then return end
    SetNewWaypoint(x, y)
    local name = tostring(data.name or 'Passageiro')
    OR.Notify(('Chamado de %s marcado no GPS.'):format(name), 'info')
end)

local function collectVehicleCondition(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil
    end

    local condition = {
        engineHealth = GetVehicleEngineHealth(vehicle),
        bodyHealth = GetVehicleBodyHealth(vehicle),
        tankHealth = GetVehiclePetrolTankHealth(vehicle),
        fuel = GetVehicleFuelLevel(vehicle),
        burstTires = {}
    }

    for tire = 0, 7 do
        if IsVehicleTyreBurst(vehicle, tire, false) then
            condition.burstTires[#condition.burstTires + 1] = tire
        end
    end

    return condition
end

local function applyFleetCondition(vehicle, condition, preserveFuel)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or type(condition) ~= 'table' then
        return
    end

    if condition.engineHealth then
        SetVehicleEngineHealth(vehicle, tonumber(condition.engineHealth) or 1000.0)
    end
    if condition.bodyHealth then
        SetVehicleBodyHealth(vehicle, tonumber(condition.bodyHealth) or 1000.0)
    end
    if condition.tankHealth then
        SetVehiclePetrolTankHealth(vehicle, tonumber(condition.tankHealth) or 1000.0)
    end
    if condition.fuel and not preserveFuel then
        setVehicleFuel(vehicle, tonumber(condition.fuel) or 0.0)
    end

    if type(condition.burstTires) == 'table' then
        for _, tire in ipairs(condition.burstTires) do
            local idx = tonumber(tire)
            if idx and idx >= 0 and idx <= 7 then
                SetVehicleTyreBurst(vehicle, idx, true, 1000.0)
            end
        end
    end
end

local function applyBusStyle(vehicle)
    local style = Config.BusStyle or {}
    SetVehicleColours(vehicle, style.primaryColor or 88, style.secondaryColor or 0)
    SetVehicleExtraColours(vehicle, style.pearlColor or 88, style.wheelColor or 0)
    SetVehicleDirtLevel(vehicle, style.dirtLevel or 0.0)

    local liveryCount = GetVehicleLiveryCount(vehicle)
    if liveryCount and liveryCount > 0 then
        SetVehicleLivery(vehicle, 0)
    end
end

-- Rotas de onibus usam passageiros NPC e nao entram no despacho de taxi do celular.
local function setSmartphoneTaxiService(_) end

local function requestModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    RequestModel(hash)
    local timeout = GetGameTimer() + 7000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
        Wait(10)
    end
    return HasModelLoaded(hash), hash
end

sendPanelMessage = function(action, payload)
    SendNUIMessage({ action = action, payload = payload })
end

local function mergeSelection(panel)
    if not panel or not panel.meta or not panel.meta.vehicles then
        return panel
    end

    local selected = state.selectedVehicleModel or panel.shift and panel.shift.selectedVehicleModel
    for _, v in ipairs(panel.meta.vehicles) do
        v.selected = selected and v.model:lower() == selected:lower() or false
    end

    return panel
end

local function refreshPanelData()
    local panel = OR.Callback.await('orbis-busjobs:server:getPanelData')
    if panel and panel.shift and panel.shift.selectedVehicleModel then
        state.selectedVehicleModel = panel.shift.selectedVehicleModel
    end

    panel = mergeSelection(panel)
    state.panelData = panel

    if state.callsPanelOpen and panel and panel.shift and not panel.shift.working then
        closeCallsPanel()
    end

    if state.panelOpen then
        sendPanelMessage('update', panel)
    end

    if state.callsPanelOpen then
        sendPanelMessage('updateCalls', panel)
    end
end

local function openPanel()
    if state.callsPanelOpen then
        state.callsPanelOpen = false
        sendPanelMessage('closeCalls', {})
    end

    refreshPanelData()
    state.panelOpen = true
    SetNuiFocus(true, true)
    state.panelData = state.panelData or {}
    state.panelData.tutorial = Config.Tutorial
    sendPanelMessage('open', state.panelData)
end

RegisterNetEvent('orbis-busjobs:client:openPanel', openPanel)

local function closePanel()
    state.panelOpen = false
    if not state.callsPanelOpen then
        SetNuiFocus(false, false)
    end
    sendPanelMessage('close', {})
end

local function openCallsPanel(silent)
    if not state.shift then
        if not silent then
            notify('Inicie o turno para abrir as rotas de onibus.', 'error')
        end
        return
    end

    if state.panelOpen then
        state.panelOpen = false
        sendPanelMessage('close', {})
    end

    refreshPanelData()
    state.callsPanelOpen = true
    SetNuiFocus(true, true)
    sendPanelMessage('openCalls', state.panelData)
end

closeCallsPanel = function()
    state.callsPanelOpen = false
    if not state.panelOpen then
        SetNuiFocus(false, false)
    end
    sendPanelMessage('closeCalls', {})
end

CreateThread(function()
    Wait(500)
    resetMeter()
end)

local function isUsingShiftVehicle()
    if not state.shift or not state.vehicle or not DoesEntityExist(state.vehicle) then return false end
    return IsPedInVehicle(PlayerPedId(), state.vehicle, false)
end

local function findFreePassengerSeats(vehicle, neededSeats)
    local seats = {}
    local max = GetVehicleMaxNumberOfPassengers(vehicle)
    for i = max - 1, 0, -1 do
        if IsVehicleSeatFree(vehicle, i) then
            seats[#seats + 1] = i
            if #seats >= neededSeats then break end
        end
    end
    return seats
end

local function cleanupRide(aborted)
    OR.Help.Hide()

    if state.ridePeds then
        for _, ped in ipairs(state.ridePeds) do
            if ped and DoesEntityExist(ped) then
                if not aborted then
                    TaskLeaveVehicle(ped, state.vehicle or 0, 0)
                    SetEntityAsNoLongerNeeded(ped)
                else
                    DeleteEntity(ped)
                end
            end
        end
    end

    state.ridePeds = {}
    state.ride = nil
    clearRideBlips()

    if state.panelOpen or state.callsPanelOpen then
        refreshPanelData()
    end
end

local function createRouteBlip(coords, name, color)
    if type(coords) ~= 'table' then
        notify('A parada recebida esta invalida. Selecione a linha novamente.', 'error')
        return nil
    end

    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z then
        notify('A parada recebida esta sem coordenadas. Selecione a linha novamente.', 'error')
        return nil
    end

    local blip = AddBlipForCoord(x, y, z)
    SetBlipSprite(blip, 1)
    SetBlipDisplay(blip, 4)
    SetBlipColour(blip, color)
    SetBlipScale(blip, 0.9)
    SetBlipAsShortRange(blip, false)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, color)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(name)
    EndTextCommandSetBlipName(blip)
    return blip
end

local function finalizeMeterRide()
    if not state.meter.active or state.meter.pending then
        return
    end

    local meter = state.meter
    meter.pending = true

    local minDistance = tonumber(Config.Meter and Config.Meter.minChargeDistance or 200.0) or 200.0
    if (meter.distance or 0.0) < minDistance then
        notify('Corrida curta demais para cobranca.', 'inform')
        resetMeter()
        return
    end

    local ok, msg = OR.Callback.await('orbis-busjobs:server:meterFinish', meter.passenger, math.floor(meter.fare or 0), meter.distance or 0.0)
    if not ok then
        notify(msg or 'Falha ao enviar cobranca.', 'error')
    else
        notify(msg or 'Solicitacao de pagamento enviada.', 'inform')
    end

    resetMeter()
end

local function spawnRidePeds(ride)
    state.ridePeds = {}
    local count = ride.passengerCount or 1
    local c = ride.pickup

    for i = 1, count do
        local modelName = getRandomPassengerModel()
        local ok, hash = requestModel(modelName)
        if ok then
            local spawnPos = getPedSpawnCoord(c, i)
            local ped = CreatePed(4, hash, spawnPos.x, spawnPos.y, spawnPos.z, spawnPos.w, false, false)
            SetEntityAsMissionEntity(ped, true, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            SetPedFleeAttributes(ped, 0, false)
            SetPedCanRagdoll(ped, false)
            SetEntityInvincible(ped, true)
            FreezeEntityPosition(ped, true)
            TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_MOBILE', 0, true)
            SetModelAsNoLongerNeeded(hash)
            state.ridePeds[#state.ridePeds + 1] = ped
        end
    end

    return #state.ridePeds > 0
end

-- Marca exatamente a mesma area em que o E pode ser usado.
local function drawStopArea(coords, isDropoff)
    if type(coords) ~= 'table' then return end
    local diameter = tonumber(Config.Ride.markerDiameter) or 20.0
    local height = tonumber(Config.Ride.markerHeight) or 0.95
    DrawMarker(1, coords.x, coords.y, coords.z - 0.94,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        diameter, diameter, height,
        isDropoff and 55 or 35, isDropoff and 180 or 215, 255, 125,
        false, false, 2, false, nil, nil, false)
end

local startRouteLeg

local function rideFlowThread(ride)
    CreateThread(function()
        local pickupPos = vec3(ride.pickup.x, ride.pickup.y, ride.pickup.z)
        local dropPos = vec3(ride.dropoff.x, ride.dropoff.y, ride.dropoff.z)
        local shownStopPrompt = nil
        while state.shift and state.ride and state.ride.id == ride.id do
            Wait(0)

            if not state.vehicle or not DoesEntityExist(state.vehicle) then
                notify('Onibus de turno perdido.', 'error')
                cleanupRide(true)
                break
            end

            local bodyHealth = GetVehicleBodyHealth(state.vehicle)
            local engineHealth = GetVehicleEngineHealth(state.vehicle)
            if bodyHealth and engineHealth then
                ride.minBodyHealth = math.min(ride.minBodyHealth or bodyHealth, bodyHealth)
                ride.minEngineHealth = math.min(ride.minEngineHealth or engineHealth, engineHealth)
                if HasEntityCollidedWithAnything(state.vehicle) then
                    ride.hadImpact = true
                end

            end

            local playerPos = GetEntityCoords(PlayerPedId())

            if not ride.pickupDone then
                local dist = #(playerPos - pickupPos)

                if dist <= (tonumber(Config.Ride.markerDrawDistance) or 85.0) then
                    drawStopArea(ride.pickup, false)
                end

                if dist <= Config.Ride.pickupDistance then
                    if not state.ridePeds or #state.ridePeds == 0 then
                        spawnRidePeds(ride)
                    end
                end

                local canStop = dist <= Config.Ride.pickupStopDistance
                    and isUsingShiftVehicle()
                    and GetEntitySpeed(state.vehicle) * 3.6 <= (tonumber(Config.Ride.interactionMaxSpeedKmh) or 8.0)

                if canStop then
                    OR.Help.Show(Config.Text.pickupHint)
                    if shownStopPrompt ~= 'pickup' then
                        shownStopPrompt = 'pickup'
                        notify(Config.Text.pickupHint, 'inform', Config.Ride.instructionDuration)
                    end

                    if IsControlJustPressed(0, 38) then
                        OR.Help.Hide()

                        local needed = ride.passengerCount or 1
                        local freeSeats = findFreePassengerSeats(state.vehicle, needed)
                        if #freeSeats < needed then
                            notify(Config.Text.noSeat, 'error')
                            Wait(1200)
                        else
                            for i, ridePed in ipairs(state.ridePeds) do
                                if ridePed and DoesEntityExist(ridePed) then
                                    FreezeEntityPosition(ridePed, false)
                                    ClearPedTasksImmediately(ridePed)
                                    -- A margem de parada e maior para o onibus, mas um ped
                                    -- nao deve ficar tentando caminhar 20+ metros ate a porta.
                                    -- Nessa situacao ele entra de imediato; perto do veiculo,
                                    -- ainda usa a animacao normal de embarque.
                                    if #(GetEntityCoords(ridePed) - GetEntityCoords(state.vehicle)) > (tonumber(Config.Ride.passengerWarpDistance) or 12.0) then
                                        TaskWarpPedIntoVehicle(ridePed, state.vehicle, freeSeats[i])
                                    else
                                        TaskEnterVehicle(ridePed, state.vehicle, 3500, freeSeats[i], 1.0, 1, 0)
                                    end
                                end
                            end

                            -- Se o caminho do NPC para a porta do onibus falhar,
                            -- nao deixa o motorista aguardando quase meio minuto.
                            local timeout = GetGameTimer() + (tonumber(Config.Ride.passengerBoardTimeoutMs) or 1800)
                            while GetGameTimer() < timeout do
                                local boarded = 0
                                for _, ridePed in ipairs(state.ridePeds) do
                                    if ridePed and DoesEntityExist(ridePed) and IsPedInVehicle(ridePed, state.vehicle, false) then
                                        boarded = boarded + 1
                                    end
                                end
                                if boarded >= needed then break end
                                Wait(250)
                            end

                            -- Nem todos os onibus calculam caminho ate os bancos traseiros.
                            -- Primeiro o ped tenta entrar normalmente; no timeout ele ocupa
                            -- o mesmo assento sem deixar a rota travada.
                            for i, ridePed in ipairs(state.ridePeds) do
                                if ridePed and DoesEntityExist(ridePed) and not IsPedInVehicle(ridePed, state.vehicle, false) then
                                    TaskWarpPedIntoVehicle(ridePed, state.vehicle, freeSeats[i])
                                end
                            end
                            Wait(150)

                            local boarded = 0
                            for _, ridePed in ipairs(state.ridePeds) do
                                if ridePed and DoesEntityExist(ridePed) and IsPedInVehicle(ridePed, state.vehicle, false) then
                                    boarded = boarded + 1
                                end
                            end

                            if boarded >= needed then
                                local ok = OR.Callback.await('orbis-busjobs:server:confirmPickup', ride.id)
                                if ok then
                                    ride.pickupDone = true
                                    removeBlipSafe(state.pickupBlip)
                                    state.pickupBlip = nil
                                    state.dropoffBlip = createRouteBlip(ride.dropoff, 'Destino do cliente', 2)
                                    notify(Config.Text.dropHint, 'inform', Config.Ride.instructionDuration)
                                    if state.panelOpen or state.callsPanelOpen then refreshPanelData() end
                                end
                            end
                        end
                    end
                else
                    OR.Help.Hide()
                    shownStopPrompt = nil
                end
            else
                local dist = #(playerPos - dropPos)
                if dist <= (tonumber(Config.Ride.markerDrawDistance) or 85.0) then
                    drawStopArea(ride.dropoff, true)
                end
                local canStop = dist <= Config.Ride.dropoffStopDistance
                    and isUsingShiftVehicle()
                    and GetEntitySpeed(state.vehicle) * 3.6 <= (tonumber(Config.Ride.interactionMaxSpeedKmh) or 8.0)

                if canStop then
                    OR.Help.Show(Config.Text.dropHint)
                    if shownStopPrompt ~= 'dropoff' then
                        shownStopPrompt = 'dropoff'
                        notify(Config.Text.dropHint, 'inform', Config.Ride.instructionDuration)
                    end

                    if IsControlJustPressed(0, 38) then
                        OR.Help.Hide()

                        for _, ridePed in ipairs(state.ridePeds) do
                            if ridePed and DoesEntityExist(ridePed) and IsPedInVehicle(ridePed, state.vehicle, false) then
                                TaskLeaveVehicle(ridePed, state.vehicle, 0)
                                Wait(250)
                                if DoesEntityExist(ridePed) then
                                    TaskWanderStandard(ridePed, 10.0, 10)
                                end
                            end
                        end

                        local ok, result = OR.Callback.await('orbis-busjobs:server:completeRide', ride.id, {
                            hadImpact = ride.hadImpact == true,
                            startBodyHealth = ride.startBodyHealth or GetVehicleBodyHealth(state.vehicle),
                            startEngineHealth = ride.startEngineHealth or GetVehicleEngineHealth(state.vehicle),
                            bodyHealth = ride.minBodyHealth or GetVehicleBodyHealth(state.vehicle),
                            engineHealth = ride.minEngineHealth or GetVehicleEngineHealth(state.vehicle)
                        })
                        if ok and result then
                            notify(('%s +%s | +%s XP'):format(Config.Text.rideDone, OR.FormatMoney(result.fare), result.xp), 'success')
                            state.panelData = result.panel
                            cleanupRide(false)

                            if result.nextRide then
                                startRouteLeg(result.nextRide, false)
                                break
                            end
                        else
                            notify(result or 'Falha ao finalizar corrida.', 'error')
                        end

                        cleanupRide(false)
                        break
                    end
                else
                    OR.Help.Hide()
                    shownStopPrompt = nil
                end
            end
        end

        OR.Help.Hide()
    end)
end

startRouteLeg = function(ride, notifyStart)
    if not ride or type(ride.pickup) ~= 'table' or type(ride.dropoff) ~= 'table' then
        notify('Nao foi possivel carregar as coordenadas da rota.', 'error')
        return false
    end

    ride.hadImpact = false
    ride.startBodyHealth = state.vehicle and DoesEntityExist(state.vehicle) and GetVehicleBodyHealth(state.vehicle) or 1000.0
    ride.startEngineHealth = state.vehicle and DoesEntityExist(state.vehicle) and GetVehicleEngineHealth(state.vehicle) or 1000.0
    ride.minBodyHealth = ride.startBodyHealth
    ride.minEngineHealth = ride.startEngineHealth
    state.ride = ride

    if notifyStart then
        notify(('%s Quando chegar ao circulo, pare o onibus e pressione E.'):format(Config.Text.rideAccepted), 'success', Config.Ride.instructionDuration)
    end

    clearRideBlips()
    state.pickupBlip = createRouteBlip(ride.pickup, 'Proxima parada: embarque', 5)
    spawnRidePeds(ride)
    rideFlowThread(ride)
    return true
end

local function selectRoute(routeId)
    if not routeId then return false end

    if state.ride then
        cleanupRide(true)
    end

    local ok, rideOrMsg = OR.Callback.await('orbis-busjobs:server:selectRoute', routeId)
    if ok and rideOrMsg then
        startRouteLeg(rideOrMsg, true)

        if state.panelOpen or state.callsPanelOpen then refreshPanelData() end
        return true
    end

    notify(rideOrMsg or 'Nao foi possivel selecionar linha.', 'error')
    if state.panelOpen or state.callsPanelOpen then refreshPanelData() end
    return false
end

local function declineCall(callId)
    if not callId then return false end

    local ok = OR.Callback.await('orbis-busjobs:server:declineCall', callId)
    if ok then
        notify(Config.Text.rideDeclined, 'error')
        if state.panelOpen or state.callsPanelOpen then refreshPanelData() end
        return true
    end

    if state.panelOpen or state.callsPanelOpen then refreshPanelData() end
    return false
end

local function startShift(model)
    if state.shift then
        notify(Config.Text.vehicleAlready, 'error')
        return
    end

    local selectedModel = model or state.selectedVehicleModel
    if not selectedModel then
        notify('Selecione um veiculo na aba Vehicles.', 'error')
        return
    end

    local ok, response = OR.Callback.await('orbis-busjobs:server:startShift', selectedModel)
    if not ok then
        notify(response or 'Nao foi possivel iniciar turno.', 'error')
        return
    end
    local spawned = response and response.spawnedVehicle
    local vehicle = spawned and OR.Entity.AwaitNetwork(spawned.netId, 10000) or nil
    if not vehicle then
        OR.Callback.await('orbis-busjobs:server:stopShift')
        notify('O onibus criado nao sincronizou.', 'error')
        return
    end
    local plate = sanitizePlate(spawned.plate)
    SetVehicleNumberPlateText(vehicle, spawned.plate)
    SetVehicleOnGroundProperly(vehicle)
    applyBusStyle(vehicle)

    state.shift = true
    state.vehicle = vehicle
    state.vehiclePlate = plate
    state.vehicleModel = selectedModel

    if state.panelOpen then
        closePanel()
    end

    setVehicleFuel(vehicle, Config.Vehicle.fuel)
    -- A chave temporaria do turno tambem deixa as portas abertas de imediato;
    -- nao depende do proximo ciclo de sincronizacao do state bag.
    SetVehicleDoorsLocked(vehicle, 1)
    if Config.Vehicle.warpIntoVehicle and DoesEntityExist(vehicle) then
        TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)
    end

    local fleetCondition = response and response.shift and response.shift.fleetCondition
    if fleetCondition then
        -- Mantem manutencao entre turnos, mas tanque sempre inicia cheio.
        applyFleetCondition(vehicle, fleetCondition, true)
        CreateThread(function()
            Wait(1500)
            if state.shift and state.vehicle == vehicle and DoesEntityExist(vehicle) then
                applyFleetCondition(vehicle, fleetCondition, true)
            end
        end)
    end

    setSmartphoneTaxiService(true)
    notify(Config.Text.shiftStarted, 'success')
    notify('Pressione [O] para abrir Rotas de Onibus.', 'inform')

    if response then
        state.panelData = mergeSelection(response)
        if state.panelOpen then sendPanelMessage('update', state.panelData) end
        if state.callsPanelOpen then sendPanelMessage('updateCalls', state.panelData) end
    end
end

local function stopShift(showNotify)
    if not state.shift then return end

    cleanupRide(true)

    setSmartphoneTaxiService(false)
    local condition = collectVehicleCondition(state.vehicle)

    OR.Callback.await('orbis-busjobs:server:stopShift', condition)

    state.shift = false
    state.vehicle = nil
    state.vehiclePlate = nil
    state.vehicleModel = nil
    state.appTaxiCaller = nil
    resetMeter()

    if showNotify then
        notify(Config.Text.shiftStopped, 'inform')
    end

    if state.callsPanelOpen then
        closeCallsPanel()
    end

    if state.panelOpen then refreshPanelData() end
end

local function createBossBlip()
    if not Config.Boss.blip.enabled then return end
    if state.bossBlip and DoesBlipExist(state.bossBlip) then return end

    local c = Config.Boss.coords
    local blip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(blip, Config.Boss.blip.sprite)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, Config.Boss.blip.scale)
    SetBlipColour(blip, Config.Boss.blip.color)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(Config.Boss.blip.name)
    EndTextCommandSetBlipName(blip)
    state.bossBlip = blip
end

local function registerBossTarget()
    if not Config.UseTarget or GetResourceState('ob_target') ~= 'started' then return end
    if not state.bossPed or not DoesEntityExist(state.bossPed) then return end

    exports.ob_target:RegisterEntity('orbis_bus_panel', state.bossPed, {
        icon = 'fa-solid fa-bus',
        label = 'Abrir painel de Onibus',
        event = 'orbis-busjobs:client:openPanel',
        distance = Config.Boss.interactionDistance,
        canInteract = function(entity)
            return entity == state.bossPed
        end,
    })
end

local function spawnBossPed()
    if state.bossPed and DoesEntityExist(state.bossPed) then return end

    local ok, hash = requestModel(Config.Boss.pedModel)
    if not ok then
        print('[orbis-busjobs] failed to load boss ped model')
        return
    end

    local c = Config.Boss.coords
    local ped = CreatePed(4, hash, c.x, c.y, c.z - 1.0, c.w, false, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)

    if Config.Boss.scenario and Config.Boss.scenario ~= '' then
        TaskStartScenarioInPlace(ped, Config.Boss.scenario, 0, true)
    end

    state.bossPed = ped
    SetModelAsNoLongerNeeded(hash)

    registerBossTarget()
end

CreateThread(function()
    -- Mesmo ciclo do modulo de lojas: so cria ped e target apos o personagem.
    while LocalPlayer.state['or:loaded'] ~= true do Wait(250) end
    spawnBossPed()
    createBossBlip()
    print(('[ob_busjobs] Ponto criado: ped=%s blip=%s.'):format(tostring(state.bossPed), tostring(state.bossBlip)))

    if Config.UseTarget and GetResourceState('ob_target') == 'started' then
        return
    end

    while true do
        Wait(0)
        if not state.bossPed or not DoesEntityExist(state.bossPed) then
            spawnBossPed()
            Wait(1000)
        end

        local pos = GetEntityCoords(PlayerPedId())
        local boss = vec3From4(Config.Boss.coords)
        local dist = #(pos - boss)

        if dist <= Config.Boss.interactionDistance + 0.5 then
            if not state.fallbackUiShown then
                OR.Help.Show(Config.Text.interaction)
                state.fallbackUiShown = true
            end

            if IsControlJustReleased(0, 38) then
                openPanel()
            end
        else
            if state.fallbackUiShown then
                state.fallbackUiShown = false
                OR.Help.Hide()
            end
            Wait(350)
        end
    end
end)

AddEventHandler('ob_target:client:ready', function()
    registerBossTarget()
end)

-- Mesmo padrao das lojas: registre a opcao depois do personagem estar pronto.
CreateThread(function()
    while LocalPlayer.state['or:loaded'] ~= true or not state.bossPed or not DoesEntityExist(state.bossPed) do Wait(250) end
    registerBossTarget()
    print('[ob_busjobs] Target do NPC registrado apos o carregamento.')
end)

CreateThread(function()
    while true do
        Wait(500)

        if not (Config.Meter and Config.Meter.enabled) then
            goto continue
        end

        if not state.shift or not state.vehicle or not DoesEntityExist(state.vehicle) then
            if state.meter.active then
                resetMeter()
            end
            goto continue
        end

        if state.ride then
            if state.meter.active then
                resetMeter()
            end
            goto continue
        end

        if not IsPedInVehicle(PlayerPedId(), state.vehicle, false) then
            if state.meter.active then
                resetMeter()
            end
            goto continue
        end

        if not state.meter.active then
            local passenger = nil
            if Config.Meter.requireAppCall then
                if state.appTaxiCaller and isPassengerStillInVehicle(state.appTaxiCaller, state.vehicle) then
                    passenger = state.appTaxiCaller
                end
            else
                passenger = getPassengerServerIdInVehicle(state.vehicle)
            end

            if passenger then
                startMeterForPassenger(passenger)
            end
            goto continue
        end

        if not isPassengerStillInVehicle(state.meter.passenger, state.vehicle) then
            finalizeMeterRide()
            goto continue
        end

        local now = GetGameTimer()
        local currentPos = GetEntityCoords(state.vehicle)
        if state.meter.lastPos then
            local delta = #(currentPos - state.meter.lastPos)
            if delta > 0.1 and delta < 120.0 then
                state.meter.distance = (state.meter.distance or 0.0) + delta
            end
        end
        state.meter.lastPos = currentPos

        if now - (state.meter.lastTick or 0) >= 1000 then
            local baseFare = tonumber(Config.Meter.baseFare or 25) or 25
            local perKm = tonumber(Config.Meter.perKm or 35) or 35
            local perMinute = tonumber(Config.Meter.perMinute or 6) or 6
            local maxFare = tonumber(Config.Meter.maxFare or 5000) or 5000

            local elapsedMinutes = math.max(0.0, (now - (state.meter.startedAt or now)) / 60000.0)
            local distanceKm = math.max(0.0, (state.meter.distance or 0.0) / 1000.0)
            local fare = baseFare + (distanceKm * perKm) + (elapsedMinutes * perMinute)
            state.meter.fare = math.floor(math.min(maxFare, math.max(baseFare, fare)))
            state.meter.lastTick = now
            updateMeterHud()
        end

        ::continue::
    end
end)

-- Painel principal somente via NPC/target (sem comando/keybind global).

RegisterCommand(Config.UI.callsCommand, function()
    openCallsPanel(true)
end, false)

RegisterKeyMapping(Config.UI.callsCommand, 'Abrir rotas de onibus', 'keyboard', Config.UI.callsKeybind)

RegisterNetEvent('orbis-busjobs:client:notify', function(desc, typ)
    notify(desc, typ or 'inform')
end)

RegisterNetEvent('orbis:bus:assigned', function(data)
    if not data then return end
    if data.role == 'driver' then
        state.appTaxiCaller = tonumber(data.callerId) or nil
    end
end)

RegisterNetEvent('orbis:bus:ended', function()
    state.appTaxiCaller = nil
    if Config.Meter.requireAppCall and state.meter.active then
        resetMeter()
    end
end)

RegisterNetEvent('orbis-busjobs:client:meterConfirmRequest', function(data)
    local reqId = data and data.id
    local fare = math.floor(tonumber(data and data.fare or 0) or 0)
    if not reqId or fare <= 0 then
        return
    end

    if pendingMeterConfirm then
        respondMeterConfirmation(false)
    end

    local timeoutMs = (tonumber(Config.Meter and Config.Meter.confirmTimeout or 25) or 25) * 1000
    pendingMeterConfirm = {
        id = reqId,
        expiresAt = GetGameTimer() + timeoutMs
    }

    notify(('Ônibus: %s | Use Y para aceitar ou N para recusar.'):format(OR.FormatMoney(fare)), 'inform')

    CreateThread(function()
        local localReq = reqId
        while pendingMeterConfirm and pendingMeterConfirm.id == localReq do
            Wait(0)
            if GetGameTimer() > (pendingMeterConfirm.expiresAt or 0) then
                respondMeterConfirmation(false)
                break
            end

            if IsControlJustReleased(0, 246) then -- Y
                respondMeterConfirmation(true)
                break
            end

            if IsControlJustReleased(0, 249) or IsControlJustReleased(0, 305) or IsControlJustReleased(0, 306) then -- N variants
                respondMeterConfirmation(false)
                break
            end
        end
    end)

    CreateThread(function()
        local localReq = reqId
        local result = OR.Dialog.Confirm({
            header = 'Taxi',
            content = ('Voce chegou ao destino?\nValor da corrida: %s\n\nConfirmar pagamento?\n(Y = Sim | N = Nao)'):format(OR.FormatMoney(fare)),
            centered = true,
            cancel = true,
            labels = { confirm = 'Sim', cancel = 'Nao' }
        })

        if pendingMeterConfirm and pendingMeterConfirm.id == localReq then
            respondMeterConfirmation(result)
        end
    end)
end)

RegisterNUICallback('close', function(_, cb)
    closePanel()
    cb('ok')
end)

RegisterNUICallback('closeCalls', function(_, cb)
    closeCallsPanel()
    cb('ok')
end)

RegisterNUICallback('refresh', function(_, cb)
    local ok, panel = OR.Callback.await('orbis-busjobs:server:refreshCalls')
    if ok and panel then
        state.panelData = mergeSelection(panel)
        if state.panelOpen then
            sendPanelMessage('update', state.panelData)
        end
        if state.callsPanelOpen then
            sendPanelMessage('updateCalls', state.panelData)
        end
    else
        refreshPanelData()
    end
    cb('ok')
end)

RegisterNUICallback('selectVehicle', function(data, cb)
    local model = data and data.model
    if type(model) == 'string' and getVehicleCfg(model) then
        state.selectedVehicleModel = model
        refreshPanelData()
        cb('ok')
        return
    end
    cb('fail')
end)

RegisterNUICallback('startShift', function(data, cb)
    startShift(data and data.model)
    cb('ok')
end)

RegisterNUICallback('stopShift', function(_, cb)
    stopShift(true)
    cb('ok')
end)

RegisterNUICallback('selectRoute', function(data, cb)
    local ok = selectRoute(data and data.id)
    if state.callsPanelOpen then
        refreshPanelData()
    end
    cb(ok and 'ok' or 'fail')
end)

RegisterNUICallback('declineCall', function(data, cb)
    local ok = declineCall(data and data.id)
    if state.callsPanelOpen then
        refreshPanelData()
    end
    cb(ok and 'ok' or 'fail')
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    closePanel()
    closeCallsPanel()
    cleanupRide(true)
    resetMeter()

    setSmartphoneTaxiService(false)

    if state.vehicle and DoesEntityExist(state.vehicle) then
        DeleteVehicle(state.vehicle)
    end

    if state.bossPed and DoesEntityExist(state.bossPed) then
        exports.ob_target:RemoveEntityOption('orbis_bus_panel')
        DeleteEntity(state.bossPed)
    end

    TriggerServerEvent('orbis-busjobs:server:forceStop')
end)
