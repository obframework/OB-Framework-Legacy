local function notify(text, kind) OR.Notify(text, kind or 'info') end
local function applyLock(vehicle, locked)
    if not DoesEntityExist(vehicle) then return end
    SetVehicleDoorsLocked(vehicle, locked and 2 or 1)
end

local function lockFeedback(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    CreateThread(function()
        for _ = 1, 2 do
            SetVehicleLights(vehicle, 2)
            SetVehicleIndicatorLights(vehicle, 0, true)
            SetVehicleIndicatorLights(vehicle, 1, true)
            PlaySoundFromEntity(-1, 'Remote_Control_Fob', vehicle, 'PI_Menu_Sounds', false, 0)
            Wait(160)
            SetVehicleIndicatorLights(vehicle, 0, false)
            SetVehicleIndicatorLights(vehicle, 1, false)
            SetVehicleLights(vehicle, 0)
            Wait(120)
        end
    end)
end

local function closestVehicle(range)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return GetVehiclePedIsIn(ped, false) end
    local coords = GetEntityCoords(ped)
    local vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, range or 5.0, 0, 71)
    return vehicle ~= 0 and vehicle or nil
end

AddStateBagChangeHandler('ob:locked', nil, function(bagName, _, value)
    local vehicle = GetEntityFromStateBagName(bagName)
    if vehicle and vehicle ~= 0 then applyLock(vehicle, value ~= false) end
end)


RegisterCommand('+ob_vehicle_lock', function()
    if LocalPlayer.state['or:loaded'] ~= true or LocalPlayer.state['or:downed'] == true then return end
    if IsNuiFocused() or IsPauseMenuActive() then return end
    local vehicle = closestVehicle(9.0)
    if not vehicle then return notify('Nenhum veiculo proximo.', 'error') end
    CreateThread(function()
        local ok, locked = OR.Callback.await('toggleLock', NetworkGetNetworkIdFromEntity(vehicle))
        if not ok then return notify(locked or 'Nao foi possivel usar a chave.', 'error') end
        applyLock(vehicle, locked == true)
        lockFeedback(vehicle)
        notify(locked and 'Veiculo trancado.' or 'Veiculo destrancado.', 'success')
    end)
end, false)
RegisterCommand('-ob_vehicle_lock', function() end, false)
RegisterKeyMapping('+ob_vehicle_lock', 'Trancar ou destrancar seu veiculo', 'keyboard', VehicleKeysConfig.LockKey)

RegisterNetEvent('ob_vehiclekeys:client:useLockpick', function(itemName, token)
    CreateThread(function()
        local vehicle = closestVehicle(4.0)
        if not vehicle then
            TriggerServerEvent('ob_vehiclekeys:server:lockpickResult', 0, false, token)
            return notify('Aproxime-se de um veiculo trancado.', 'error')
        end
        if GetResourceState('ob_minigame') ~= 'started' then
            TriggerServerEvent('ob_vehiclekeys:server:lockpickResult', 0, false, token)
            return notify('Minigame indisponivel.', 'error')
        end
        local prepared = OR.Callback.await('prepareLockpick', NetworkGetNetworkIdFromEntity(vehicle), token)
        if not prepared then
            TriggerServerEvent('ob_vehiclekeys:server:lockpickResult', 0, false, token)
            return notify('Nao foi possivel iniciar o arrombamento. Confira a ferramenta e a distancia.', 'error')
        end
        local advanced = itemName == 'advanced_lockpick'
        local ok, success, reason = pcall(function() return exports.ob_minigame:Keypress({
            title = advanced and 'LOCKPICK AVANCADA' or 'LOCKPICK',
            key = 'E',
            steps = advanced and 3 or 4,
            speed = advanced and 0.95 or 1.75,
            tolerance = advanced and 0.18 or 0.10,
            timeoutMs = 25000,
        }) end)
        local started = ok and reason ~= 'Ja existe um minigame em andamento.'
        TriggerServerEvent('ob_vehiclekeys:server:lockpickResult', started and NetworkGetNetworkIdFromEntity(vehicle) or 0, ok and success == true, token)
        if not ok then notify('Falha ao abrir o minigame. Tente novamente.', 'error') end
    end)
end)
RegisterNetEvent('ob_vehiclekeys:client:lockFeedback', function(netId)
    lockFeedback(NetworkGetEntityFromNetworkId(tonumber(netId) or 0))
end)
RegisterNetEvent('ob_vehiclekeys:client:alarmTriggered', function(netId)
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        StartVehicleAlarm(vehicle)
        SetVehicleAlarmTimeLeft(vehicle, 30000)
    end
end)

local accessVehicle, accessAllowed, blockedVehicle, helpVisible = 0, false, nil, false
local ignitionState, engineBusy = {}, false
RegisterNetEvent('ob_vehiclekeys:client:refresh', function()
    if not engineBusy and ignitionState.running ~= true then accessVehicle = 0 end
end)
RegisterCommand('chave', function()
    local entity = closestVehicle(5.0)
    if not entity then return notify('Aproxime-se do seu veiculo.', 'error') end
    CreateThread(function()
        local ok, message = OR.Callback.await('ownerKey', NetworkGetNetworkIdFromEntity(entity))
        notify(ok and 'Sua chave esta disponivel.' or (message or 'Nao foi possivel emitir a chave.'), ok and 'success' or 'error')
        accessVehicle = 0
    end)
end, false)

local function requestIgnition(entity, turnOn)
    if engineBusy then return end
    if turnOn and GetVehicleEngineHealth(entity) <= 0.0 then
        SetVehicleUndriveable(entity, true)
        SetVehicleEngineOn(entity, false, true, true)
        return notify('O motor esta destruido e precisa de reparo.', 'error')
    end
    engineBusy = true
    CreateThread(function()
        local ok, value = OR.Callback.await('ignition', NetworkGetNetworkIdFromEntity(entity), turnOn)
        if DoesEntityExist(entity) and entity == GetVehiclePedIsIn(PlayerPedId(), false) then
            if ok then
                ignitionState = { running = value == true, inserted = VehicleKeysConfig.virtual == false and value == true, manual = true }
                accessVehicle, accessAllowed = entity, true
                SetVehicleUndriveable(entity, value ~= true)
                SetVehicleEngineOn(entity, value == true, true, true)
                notify(value == true and 'Motor ligado.' or 'Motor desligado.', 'success')
            else
                notify(value or 'Nao foi possivel usar a ignicao.', 'error')
            end
        end
        engineBusy = false
    end)
end
RegisterCommand('ob_vehicle_engine', function()
    if IsNuiFocused() or IsPauseMenuActive() or LocalPlayer.state['or:downed'] == true then return end
    local entity = GetVehiclePedIsIn(PlayerPedId(), false)
    if entity == 0 or GetPedInVehicleSeat(entity, -1) ~= PlayerPedId() then return end
    local running = GetIsVehicleEngineRunning(entity)
    requestIgnition(entity, not (running == true or running == 1))
end, false)
RegisterKeyMapping('ob_vehicle_engine', 'Veiculo: ligar/desligar motor e usar a chave', 'keyboard', VehicleKeysConfig.EngineKey or 'Z')

-- Consulta permissao fora do loop por frame; nao confia em chaves enviadas pelo cliente.
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local entity = GetVehiclePedIsIn(ped, false)
        if entity ~= 0 and GetPedInVehicleSeat(entity, -1) == ped and GetVehicleClass(entity) ~= 13 then
            local ok, state = OR.Callback.await('access', NetworkGetNetworkIdFromEntity(entity))
            if not engineBusy and entity == GetVehiclePedIsIn(PlayerPedId(), false) then
                accessVehicle, accessAllowed = entity, ok == true
                ignitionState = type(state) == 'table' and state or {}
            end
        else accessVehicle, accessAllowed = 0, false end
        Wait(1500)
    end
end)
CreateThread(function()
    while true do
        local wait = 250
        local ped = PlayerPedId()
        local entity = GetVehiclePedIsIn(ped, false)
        local blocked = LocalPlayer.state['or:loaded'] == true and entity ~= 0
            and GetPedInVehicleSeat(entity, -1) == ped and GetVehicleClass(entity) ~= 13
            and (accessVehicle ~= entity or not accessAllowed
                or (VehicleKeysConfig.virtual == false and ignitionState.running ~= true)
                or (VehicleKeysConfig.virtual ~= false and ignitionState.manual == true and ignitionState.running ~= true))
        if blockedVehicle and (not blocked or blockedVehicle ~= entity) then
            if DoesEntityExist(blockedVehicle) and GetVehicleEngineHealth(blockedVehicle) > 0.0 then
                SetVehicleUndriveable(blockedVehicle, false)
            end
            blockedVehicle = nil
        end
        if blocked then
            wait, blockedVehicle = 0, entity
            SetVehicleUndriveable(entity, true)
            SetVehicleEngineOn(entity, false, true, true)
            DisableControlAction(0, 71, true); DisableControlAction(0, 72, true)
            if VehicleKeysConfig.ShowIgnitionHints == true then
                OR.Help.Show(accessAllowed and ('[' .. (VehicleKeysConfig.EngineKey or 'Z') .. '] Ligar motor')
                    or 'Voce precisa da chave deste veiculo. Use uma lockpick para obter uma reserva.')
                helpVisible = true
            elseif helpVisible then
                OR.Help.Hide()
                helpVisible = false
            end
        elseif helpVisible then OR.Help.Hide(); helpVisible = false end
        Wait(wait)
    end
end)
-- Reaplica trancas quando entidades entram no alcance, sem forcar carros de trabalho abertos.
CreateThread(function()
    while true do
        if LocalPlayer.state['or:loaded'] == true then
            local coords = GetEntityCoords(PlayerPedId())
            for _, entity in ipairs(GetGamePool('CVehicle')) do
                if #(GetEntityCoords(entity) - coords) < 90.0 then
                    local state = Entity(entity).state
                    if state['ob:locked'] ~= nil then applyLock(entity, state['ob:locked'] == true)
                    elseif state['ob:registered_vehicle'] ~= true then applyLock(entity, false) end
                end
            end
        end
        Wait(2000)
    end
end)
AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if blockedVehicle and DoesEntityExist(blockedVehicle) and GetVehicleEngineHealth(blockedVehicle) > 0.0 then
        SetVehicleUndriveable(blockedVehicle, false)
    end
    if helpVisible then OR.Help.Hide() end
end)
