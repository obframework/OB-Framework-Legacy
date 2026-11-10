local currentVehicle, vehicleState, lastCoords, refueling = nil, nil, nil, false
local lastSaveAt = 0
local menuVehicle, fuelMenuOpen, maintenanceOpen = nil, false, false
local nozzleVehicle, nozzleLiters, nozzleFuelType, nozzleProp = nil, nil, nil, nil
local transientStates = {}
local diagnosticTargets = {}

local function typeFor(vehicle) return OBFuelConfig.DieselClasses[GetVehicleClass(vehicle)] and 'diesel' or 'gasoline' end
local function nearestPump()
    local coords = GetEntityCoords(PlayerPedId())
    for i = 1, #OBFuelConfig.PumpModels do
        local pump = GetClosestObjectOfType(coords.x, coords.y, coords.z, OBFuelConfig.PumpDistance, OBFuelConfig.PumpModels[i], false, false, false)
        if pump ~= 0 then return pump end
    end
    return nil
end

local function nearPump()
    return nearestPump() ~= nil
end

local function vehicleAtPump(vehicle, pump)
    if not vehicle or vehicle == 0 or not pump or pump == 0 then return false end
    return #(GetEntityCoords(vehicle) - GetEntityCoords(pump)) <= OBFuelConfig.VehiclePumpDistance
end

local function tankCanBeRefueled(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    local minimum = tonumber(OBFuelConfig.MinimumTankHealthToRefuel) or 650.0
    local health = tonumber(GetVehiclePetrolTankHealth(vehicle)) or 1000.0
    return health >= minimum and not IsEntityOnFire(vehicle), health
end

-- O tanque fica no lado esquerdo, proximo a traseira. Usamos as dimensoes do
-- modelo para impedir que o abastecimento comece no meio ou na frente do carro.
local function fuelPoint(vehicle)
    local minimum = GetModelDimensions(GetEntityModel(vehicle))
    return GetOffsetFromEntityInWorldCoords(vehicle, minimum.x - 0.18, minimum.y + 0.38, 0.05)
end

local function drawText3d(coords, text)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    SetTextScale(0.0, 0.32)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(215, 245, 255, 235)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function drawFuelProgress(liters, target, price)
    DrawRect(0.5, 0.90, 0.31, 0.075, 3, 17, 37, 210)
    SetTextFont(4); SetTextScale(0.0, 0.34); SetTextColour(220, 245, 255, 255); SetTextCentre(true); SetTextOutline()
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(('ABASTECENDO  %.1f / %.1f L'):format(liters, target)); EndTextCommandDisplayText(0.5, 0.875)
    SetTextScale(0.0, 0.28); SetTextColour(105, 214, 255, 255)
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(('%s  |  [BACKSPACE] Cancelar'):format(OR.FormatMoney(math.ceil(liters * price)))); EndTextCommandDisplayText(0.5, 0.908)
end

local function clearNozzle()
    nozzleVehicle, nozzleLiters, nozzleFuelType = nil, nil, nil
    if nozzleProp and DoesEntityExist(nozzleProp) then DeleteEntity(nozzleProp) end
    nozzleProp = nil
end

local function takeNozzle(vehicle, liters, fuelType)
    local model = joaat('prop_cs_fuel_nozle')
    RequestModel(model)
    local timeout = GetGameTimer() + 2500
    while not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(0) end
    if not HasModelLoaded(model) then return OR.Notify('Nao foi possivel pegar a mangueira.', 'error') end
    clearNozzle()
    local ped = PlayerPedId()
    nozzleProp = CreateObject(model, GetEntityCoords(ped), false, false, false)
    -- SKEL_L_Hand: o bico fica na mao esquerda durante o abastecimento.
    AttachEntityToEntity(nozzleProp, ped, GetPedBoneIndex(ped, 18905), 0.12, 0.02, -0.02, 95.0, 10.0, 0.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)
    nozzleVehicle, nozzleLiters, nozzleFuelType = vehicle, liters, fuelType
    OR.Notify('Leve a mangueira ao tanque traseiro esquerdo e aperte E.', 'info')
end
local function save(vehicle, state)
    vehicle, state = vehicle or currentVehicle, state or vehicleState
    if not vehicle or not state then return end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if not netId or netId == 0 then return end
    state.fuelType = typeFor(vehicle)
    if state.transient == true then transientStates[vehicle] = state end
    -- O servidor valida a proximidade, publica o estado para todos e somente
    -- grava no SQL quando o veiculo for persistente.
    TriggerServerEvent('ob_fuel:server:saveVehicleState', netId, state)
end
local function load(vehicle)
    local state = transientStates[vehicle] or OR.Callback.awaitResource('ob_fuel', 'getVehicleState', NetworkGetNetworkIdFromEntity(vehicle))
    vehicleState = state or { mileage = 0, oil_km = 0, brake_km = 0, spark_km = 0 }
    local sharedFuel = Entity(vehicle).state['ob:fuel']
    local sharedMisfuel = Entity(vehicle).state['ob:misfuel']
    if sharedFuel ~= nil then vehicleState.fuel = sharedFuel end
    if type(sharedMisfuel) == 'table' then
        vehicleState.misfuelLiters, vehicleState.misfuelType = sharedMisfuel.liters, sharedMisfuel.type
    end
    vehicleState.oilKm, vehicleState.brakeKm, vehicleState.sparkKm = vehicleState.oil_km or 0, vehicleState.brake_km or 0, vehicleState.spark_km or 0
    vehicleState.misfuelLiters = math.max(0.0, tonumber(vehicleState.misfuelLiters or vehicleState.misfuel_liters) or 0.0)
    vehicleState.misfuelType = vehicleState.misfuelType or vehicleState.misfuel_type
    vehicleState.fuelType = typeFor(vehicle)
    if vehicleState.fuel ~= nil then
        local loadedFuel = math.max(0.0, math.min(100.0, tonumber(vehicleState.fuel) or 100.0))
        if not tankCanBeRefueled(vehicle) then
            -- Nao devolve combustivel que vazou enquanto o motorista estava
            -- fora do veiculo.
            loadedFuel = math.min(loadedFuel,
                math.max(0.0, math.min(100.0, tonumber(GetVehicleFuelLevel(vehicle)) or loadedFuel)))
            vehicleState.fuel = loadedFuel
        end
        SetVehicleFuelLevel(vehicle, loadedFuel)
    end
end

RegisterNetEvent('ob_fuel:client:paidFuel', function(netId, liters, selectedType)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or vehicle == 0 then return end
    local vehicleType = typeFor(vehicle)
    local data = OBFuelConfig.Types[vehicleType]
    selectedType = OBFuelConfig.Types[selectedType] and selectedType or vehicleType
    SetVehicleFuelLevel(vehicle, math.min(100.0, GetVehicleFuelLevel(vehicle) + (liters / data.capacity * 100)))
    local state
    if vehicle == currentVehicle and vehicleState then
        state = vehicleState
    else
        -- Ao abastecer a pe o veiculo ainda nao e o veiculo monitorado pelo
        -- loop. Carrega/salva somente este estado para nao voltar a 100% ao
        -- entrar nele pela primeira vez.
        state = transientStates[vehicle] or OR.Callback.awaitResource('ob_fuel', 'getVehicleState', netId) or {}
        state.mileage = tonumber(state.mileage) or 0
        state.fuel = GetVehicleFuelLevel(vehicle)
        state.oilKm = tonumber(state.oilKm or state.oil_km) or 0
        state.brakeKm = tonumber(state.brakeKm or state.brake_km) or 0
        state.sparkKm = tonumber(state.sparkKm or state.spark_km) or 0
        state.misfuelLiters = math.max(0.0, tonumber(state.misfuelLiters or state.misfuel_liters) or 0.0)
        state.misfuelType = state.misfuelType or state.misfuel_type
        transientStates[vehicle] = state
    end
    state.fuel = GetVehicleFuelLevel(vehicle)
    state.fuelType = vehicleType
    if selectedType ~= vehicleType then
        state.misfuelLiters = math.max(0.0, tonumber(state.misfuelLiters) or 0.0) + liters
        state.misfuelType = selectedType
        OR.Notify(('Combustivel incorreto adicionado: %s em motor %s. O motor pode falhar.'):format(OBFuelConfig.Types[selectedType].label, OBFuelConfig.Types[vehicleType].label), 'error')
    end
    save(vehicle, state)
    OR.Notify(('Abastecido: %.1f L.'):format(liters), 'success')
end)

-- Recebido depois de o servidor validar a alteracao. Nao salva novamente,
-- evitando um loop de rede entre motorista e os jogadores proximos.
RegisterNetEvent('ob_fuel:client:syncVehicleState', function(netId, state)
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if vehicle == 0 or type(state) ~= 'table' then return end
    local fuel = math.max(0.0, math.min(100.0, tonumber(state.fuel) or 100.0))
    if not tankCanBeRefueled(vehicle) then
        fuel = math.min(fuel,
            math.max(0.0, math.min(100.0, tonumber(GetVehicleFuelLevel(vehicle)) or fuel)))
        state.fuel = fuel
    end
    SetVehicleFuelLevel(vehicle, fuel)
    if vehicle == currentVehicle and vehicleState then
        for key, value in pairs(state) do vehicleState[key] = value end
        vehicleState.oilKm = tonumber(state.oilKm or state.oil_km) or vehicleState.oilKm or 0
        vehicleState.brakeKm = tonumber(state.brakeKm or state.brake_km) or vehicleState.brakeKm or 0
        vehicleState.sparkKm = tonumber(state.sparkKm or state.spark_km) or vehicleState.sparkKm or 0
        vehicleState.misfuelLiters = math.max(0.0, tonumber(state.misfuelLiters or state.misfuel_liters) or 0.0)
        vehicleState.misfuelType = state.misfuelType or state.misfuel_type
    else
        transientStates[vehicle] = state
    end
end)

exports('GetMileage', function(vehicle)
    local cached = transientStates[vehicle]
    return vehicle == currentVehicle and vehicleState and vehicleState.mileage
        or cached and cached.mileage
        or tonumber(Entity(vehicle).state['ob:mileage']) or 0
end)
exports('GetFuelType', typeFor)
exports('SetFuel', function(vehicle, amount)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false, 'Veiculo invalido.' end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if not netId or netId == 0 then return false, 'Veiculo sem sincronizacao de rede.' end
    amount = math.max(0.0, math.min(100.0, tonumber(amount) or 100.0))
    local success, message = OR.Callback.awaitResource('ob_fuel', 'setFuelByAdmin', netId, amount)
    if success ~= true then return false, message end

    SetVehicleFuelLevel(vehicle, amount)
    if vehicle == currentVehicle and vehicleState then
        vehicleState.fuel = amount
        vehicleState.misfuelLiters = 0
        vehicleState.misfuelType = nil
    elseif transientStates[vehicle] then
        transientStates[vehicle].fuel = amount
        transientStates[vehicle].misfuelLiters = 0
        transientStates[vehicle].misfuelType = nil
    end
    return true
end)

local function nearestFuelVehicle()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then return vehicle end
    local coords = GetEntityCoords(ped)
    vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 5.5, 0, 71)
    return vehicle ~= 0 and vehicle or nil
end

local function maintenanceStatus(used, interval)
    local remaining = math.max(0, interval - used)
    local percent = math.floor(math.min(100, (remaining / interval) * 100))
    return { percent = percent, remaining = math.floor(remaining), label = percent > 45 and 'Bom' or (percent > 15 and 'Atencao' or 'Trocar agora') }
end

local function openVehicleStatus(targetVehicle)
    if fuelMenuOpen then return end
    local vehicle = targetVehicle or nearestFuelVehicle()
    if not vehicle then return OR.Notify('Aproxime-se de um veiculo.', 'error') end
    local state = vehicle == currentVehicle and vehicleState or transientStates[vehicle]
    if not state then state = OR.Callback.awaitResource('ob_fuel', 'getVehicleState', NetworkGetNetworkIdFromEntity(vehicle)) end
    if type(state) ~= 'table' then return OR.Notify('Nao foi possivel ler este veiculo.', 'error') end
    local mileage, config = tonumber(state.mileage) or 0, OBFuelConfig.Maintenance
    menuVehicle, fuelMenuOpen, maintenanceOpen = vehicle, true, true
    SendNUIMessage({ action = 'status', data = {
        vehicle = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))) ~= 'NULL' and GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))) or GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)),
        mileage = math.floor(mileage * 10) / 10,
        fuel = math.floor(GetVehicleFuelLevel(vehicle) * 10) / 10,
        oil = maintenanceStatus(mileage - (tonumber(state.oilKm or state.oil_km) or 0), config.oilKm),
        brakes = maintenanceStatus(mileage - (tonumber(state.brakeKm or state.brake_km) or 0), config.brakesKm),
        spark = maintenanceStatus(mileage - (tonumber(state.sparkKm or state.spark_km) or 0), config.plugsKm),
    } })
    Wait(0)
    SetNuiFocus(true, true)
end

RegisterNetEvent('ob_fuel:client:inspectVehicle', openVehicleStatus)
RegisterNetEvent('ob_fuel:client:useMaintenancePart', function(slot, itemName, itemType)
    local vehicle = nearestFuelVehicle()
    if not vehicle then return OR.Notify('Aproxime-se de um veiculo.', 'error') end
    local parts = {
        mechanic_oil = { key = 'oil', label = 'Trocando oleo...', duration = 5500 },
        mechanic_brakes = { key = 'brakes', label = 'Trocando pastilhas...', duration = 6500 },
        mechanic_spark = { key = 'spark', label = 'Trocando velas...', duration = 6000 },
    }
    local part = parts[itemType]
    if not part or GetResourceState('ob_minigame') ~= 'started' then return OR.Notify('Minigame indisponivel.', 'error') end
    if not exports.ob_minigame:Keypress({ title = part.label, key = 'E', steps = 3, speed = 1.0, tolerance = 0.14 }) then return OR.Notify('Voce errou o ponto de aperto.', 'error') end
    if not OR.Progress.Run({ label = part.label, duration = part.duration, animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 } }) then return end
    local serviced, message = OR.Callback.awaitResource('ob_fuel', 'servicePart', NetworkGetNetworkIdFromEntity(vehicle), part.key)
    if not serviced then return OR.Notify(message or 'Nao foi possivel aplicar esta peca.', 'error') end
    if vehicleState and vehicle == currentVehicle then
        if part.key == 'oil' then vehicleState.oilKm = vehicleState.mileage elseif part.key == 'brakes' then vehicleState.brakeKm = vehicleState.mileage else vehicleState.sparkKm = vehicleState.mileage end
    end
    OR.Notify(message or 'Manutencao concluida.', 'success')
end)

local function refreshDiagnosticTargets()
    if GetResourceState('ob_target') ~= 'started' then return end
    local active, playerCoords = {}, GetEntityCoords(PlayerPedId())
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) and #(GetEntityCoords(vehicle) - playerCoords) <= 12.0 then
            local id = ('ob_fuel:diagnostic:%s'):format(NetworkGetNetworkIdFromEntity(vehicle) > 0 and NetworkGetNetworkIdFromEntity(vehicle) or vehicle)
            active[id] = true
            if diagnosticTargets[id] ~= vehicle then
                if diagnosticTargets[id] then exports.ob_target:RemoveEntityOption(id) end
                diagnosticTargets[id] = vehicle
                exports.ob_target:RegisterEntity(id, vehicle, {
                    label = 'Ver diagnostico do veiculo', icon = 'fa-solid fa-gauge-high', distance = 2.8,
                    action = function(entity) openVehicleStatus(entity) end,
                    canInteract = function(entity)
                        return DoesEntityExist(entity)
                            and GetSelectedPedWeapon(PlayerPedId()) ~= joaat('WEAPON_WRENCH')
                            and #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(entity)) <= 2.8
                    end,
                })
            end
        end
    end
    for id in pairs(diagnosticTargets) do
        if not active[id] then
            exports.ob_target:RemoveEntityOption(id)
            diagnosticTargets[id] = nil
        end
    end
end

CreateThread(function()
    while LocalPlayer.state['or:loaded'] ~= true do Wait(500) end
    while true do refreshDiagnosticTargets(); Wait(1200) end
end)

AddEventHandler('ob_target:client:ready', function()
    diagnosticTargets = {}
    refreshDiagnosticTargets()
end)

local function closeFuelMenu()
    fuelMenuOpen, maintenanceOpen, menuVehicle = false, false, nil
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
end

local function beginFueling(vehicle, selectedLiters, selectedType)
    vehicle = vehicle or nearestFuelVehicle()
    local pump = nearestPump()
    if IsPedInAnyVehicle(PlayerPedId(), false) then return OR.Notify('Saia do veiculo para abastecer.', 'error') end
    if not vehicle or not vehicleAtPump(vehicle, pump) or refueling then return OR.Notify('Aproxime-se da bomba e deixe o veiculo ao seu lado.', 'error') end
    local safeTank = tankCanBeRefueled(vehicle)
    if not safeTank then return OR.Notify('O tanque esta furado ou muito danificado. Repare-o antes de abastecer.', 'error') end
    local missing = 100 - GetVehicleFuelLevel(vehicle)
    if missing <= 0.1 then return OR.Notify('Tanque cheio.', 'info') end
    local vehicleType = typeFor(vehicle)
    selectedType = OBFuelConfig.Types[selectedType] and selectedType or vehicleType
    local tank = OBFuelConfig.Types[vehicleType]
    local data = OBFuelConfig.Types[selectedType]
    local maximum = missing * tank.capacity / 100
    local liters = math.max(0.5, math.min(maximum, tonumber(selectedLiters) or maximum))
    refueling = true
    local ped, started, pumped, cancelled, damagedTank = PlayerPedId(), GetGameTimer(), 0.0, false, false
    RequestAnimDict('timetable@gardener@filling_can')
    while not HasAnimDictLoaded('timetable@gardener@filling_can') do Wait(0) end
    TaskPlayAnim(ped, 'timetable@gardener@filling_can', 'gar_ig_5_filling_can', 2.0, -2.0, -1, 49, 0.0, false, false, false)
    while pumped < liters do
        DisableControlAction(0, 30, true); DisableControlAction(0, 31, true); DisableControlAction(0, 21, true); DisableControlAction(0, 22, true)
        DisableControlAction(0, 23, true); DisableControlAction(0, 24, true); DisableControlAction(0, 25, true); DisableControlAction(0, 75, true)
        if IsControlJustPressed(0, 177) or #(GetEntityCoords(ped) - fuelPoint(vehicle)) > 1.55 then cancelled = true break end
        if not tankCanBeRefueled(vehicle) then damagedTank = true break end
        pumped = math.min(liters, ((GetGameTimer() - started) / 1000.0) * OBFuelConfig.RefillPerSecond)
        drawFuelProgress(pumped, liters, data.price)
        Wait(0)
    end
    ClearPedTasks(ped)
    refueling = false
    clearNozzle()
    pumped = math.floor(pumped * 10) / 10
    if not damagedTank and pumped >= 0.1 then
        TriggerServerEvent('ob_fuel:server:payFuel', NetworkGetNetworkIdFromEntity(vehicle), pumped, selectedType)
    end
    if damagedTank then
        OR.Notify('Abastecimento interrompido: o tanque esta furado ou muito danificado.', 'error')
    elseif cancelled then
        OR.Notify(('Abastecimento cancelado: %.1f L adicionados.'):format(pumped), 'info')
    end
end

RegisterNetEvent('ob_fuel:client:openPump', function()
    if fuelMenuOpen then return end
    if IsPedInAnyVehicle(PlayerPedId(), false) then return OR.Notify('Saia do veiculo para abastecer.', 'error') end
    local vehicle = nearestFuelVehicle()
    local pump = nearestPump()
    if not vehicle or not vehicleAtPump(vehicle, pump) then return OR.Notify('Estacione o veiculo ao lado da bomba.', 'error') end
    local safeTank = tankCanBeRefueled(vehicle)
    if not safeTank then return OR.Notify('O tanque esta furado ou muito danificado. Repare-o antes de abastecer.', 'error') end
    local fuelType = typeFor(vehicle)
    local data = OBFuelConfig.Types[fuelType]
    local level = math.max(0.0, math.min(100.0, GetVehicleFuelLevel(vehicle)))
    local maximum = math.max(0.0, (100.0 - level) * data.capacity / 100.0)
    if maximum < 0.5 then return OR.Notify('Tanque cheio.', 'info') end
    menuVehicle, fuelMenuOpen = vehicle, true
    SendNUIMessage({ action = 'open', data = {
        type = fuelType, selectedType = fuelType, level = level, capacity = data.capacity, price = data.price,
        prices = { gasoline = OBFuelConfig.Types.gasoline.price, diesel = OBFuelConfig.Types.diesel.price },
        maximum = math.floor(maximum * 2) / 2,
        vehicle = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))) ~= 'NULL'
            and GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)))
            or GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)),
    } })
    Wait(0)
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
end)

RegisterNUICallback('confirm', function(data, cb)
    cb({ ok = true })
    local vehicle = menuVehicle
    closeFuelMenu()
    if not vehicle or not DoesEntityExist(vehicle) then return OR.Notify('Veiculo indisponivel.', 'error') end
    takeNozzle(vehicle, data and data.liters, data and data.fuelType)
end)

RegisterNUICallback('close', function(_, cb)
    cb({ ok = true })
    closeFuelMenu()
end)

CreateThread(function()
    while LocalPlayer.state['or:loaded'] ~= true do Wait(250) end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    closeFuelMenu()
    clearNozzle()
    if GetResourceState('ob_target') == 'started' then
        for id in pairs(diagnosticTargets) do exports.ob_target:RemoveEntityOption(id) end
    end
end)

CreateThread(function()
    while true do
        if not fuelMenuOpen and not nozzleVehicle then
            local pump = nearestPump()
            local vehicle = nearestFuelVehicle()
            if pump and vehicle and vehicleAtPump(vehicle, pump) then
                local coords = GetEntityCoords(pump)
                DrawMarker(1, coords.x, coords.y, coords.z + 0.12, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    0.34, 0.34, 0.18, 26, 168, 255, 150, false, true, 2, false, nil, nil, false)
                drawText3d(coords + vector3(0.0, 0.0, 0.45), '[E] Abastecer veiculo')
                if IsControlJustReleased(0, 38) then
                    TriggerEvent('ob_fuel:client:openPump')
                    Wait(350)
                else
                    Wait(0)
                end
            else
                Wait(300)
            end
        else
            Wait(250)
        end
    end
end)

CreateThread(function()
    while true do
        if nozzleVehicle and DoesEntityExist(nozzleVehicle) then
            local side = fuelPoint(nozzleVehicle)
            local distance = #(GetEntityCoords(PlayerPedId()) - side)
            DrawMarker(1, side.x, side.y, side.z - 0.92, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                0.28, 0.28, 0.16, 26, 168, 255, 155, false, true, 2, false, nil, nil, false)
            if distance <= 1.4 then
                drawText3d(side + vector3(0.0, 0.0, 0.28), '[E] Abastecer no tanque')
                if IsControlJustReleased(0, 38) then beginFueling(nozzleVehicle, nozzleLiters, nozzleFuelType) end
            end
            Wait(0)
        elseif nozzleVehicle then
            clearNozzle()
            Wait(250)
        else
            Wait(300)
        end
    end
end)

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
            if vehicle ~= currentVehicle then
                save()
                currentVehicle, lastCoords = vehicle, GetEntityCoords(vehicle)
                load(vehicle)
                lastSaveAt = GetGameTimer()
            end
            local coords = GetEntityCoords(vehicle)
            local distance = #(coords - lastCoords) / 1000.0
            lastCoords = coords
            vehicleState.mileage = (vehicleState.mileage or 0) + distance
            local vehicleType = typeFor(vehicle)
            local capacity = OBFuelConfig.Types[vehicleType].capacity
            local engineHealth = GetVehicleEngineHealth(vehicle)
            local runningValue = GetIsVehicleEngineRunning(vehicle)
            local engineRunning = runningValue == true or runningValue == 1
            local canConsume = engineHealth > 0.0 and engineRunning
            local usedLiters = canConsume and distance * ((OBFuelConfig.ConsumptionPer100Km[vehicleType] or 10.0) / 100.0) or 0.0
            -- O cache continua controlando o consumo normal, mas nunca pode
            -- sobrescrever uma reducao real aplicada pelo GTA.
            local nativeFuel = math.max(0.0, math.min(100.0, tonumber(GetVehicleFuelLevel(vehicle)) or 0.0))
            local cachedFuel = math.max(0.0, math.min(100.0, tonumber(vehicleState.fuel) or nativeFuel))
            -- Aceita reducoes reais feitas pelo GTA, inclusive vazamento de um
            -- tanque perfurado. O recurso nunca deve restaurar esse combustivel.
            local previousFuel = math.min(cachedFuel, nativeFuel)
            local fuel = math.max(0.0, previousFuel - ((usedLiters / capacity) * 100.0))
            SetVehicleFuelLevel(vehicle, fuel)
            vehicleState.fuel = fuel
            local contaminated = math.max(0.0, tonumber(vehicleState.misfuelLiters or vehicleState.misfuel_liters) or 0.0)
            if contaminated > 0.0 and usedLiters > 0.0 then
                local tankLiters = math.max(0.01, (GetVehicleFuelLevel(vehicle) / 100.0) * capacity + usedLiters)
                local ratio = math.min(1.0, contaminated / tankLiters)
                vehicleState.misfuelLiters = math.max(0.0, contaminated - (usedLiters * ratio))
                SetVehicleEngineHealth(vehicle, GetVehicleEngineHealth(vehicle) - (distance * OBFuelConfig.Misfuel.damagePerKm * ratio))
                if math.random() < math.min(0.5, distance * OBFuelConfig.Misfuel.stallChancePerKm * ratio) then
                    SetVehicleEngineOn(vehicle, false, true, true)
                end
            end
            if fuel <= 0.05 then SetVehicleEngineOn(vehicle, false, true, true) end
            if vehicleState.mileage - vehicleState.oilKm >= OBFuelConfig.Maintenance.oilKm then SetVehicleEngineHealth(vehicle, GetVehicleEngineHealth(vehicle) - OBFuelConfig.Maintenance.damagePerTick) end
            if vehicleState.mileage - vehicleState.brakeKm >= OBFuelConfig.Maintenance.brakesKm then
                -- A perda de freio e representada por desgaste de motor ate o
                -- modulo de mecanica aplicar a manutencao especifica.
                SetVehicleEngineHealth(vehicle, GetVehicleEngineHealth(vehicle) - (OBFuelConfig.Maintenance.damagePerTick * 0.25))
            end
            if vehicleState.mileage - vehicleState.sparkKm >= OBFuelConfig.Maintenance.plugsKm and math.random(1, 100) <= 5 then SetVehicleEngineOn(vehicle, false, true, true) end
            if GetGameTimer() - lastSaveAt >= (OBFuelConfig.SaveInterval or 60000) then
                save()
                lastSaveAt = GetGameTimer()
            end
            Wait(OBFuelConfig.Tick)
        else
            save(); currentVehicle, vehicleState, lastCoords, lastSaveAt = nil, nil, nil, 0
            Wait(750)
        end
    end
end)
