local pushingStretcher
local registeredStretchers = {}

local function config()
    return type(ORHealthConfig.Stretcher) == 'table' and ORHealthConfig.Stretcher or {}
end

local function loadAnim(dictionary)
    RequestAnimDict(dictionary)
    local deadline = GetGameTimer() + 4000
    while not HasAnimDictLoaded(dictionary) and GetGameTimer() < deadline do Wait(0) end
    return HasAnimDictLoaded(dictionary)
end

local function stretcherEntity(netId)
    local entity = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    return entity ~= 0 and DoesEntityExist(entity) and entity or nil
end

local function closestStretcher(radius)
    local cfg = config()
    local ped = PlayerPedId()
    local position = GetEntityCoords(ped)
    local object = GetClosestObjectOfType(position.x, position.y, position.z, radius or 4.0,
        GetHashKey(tostring(cfg.Model or 'v_med_bed2')), false, false, false)
    if object == 0 or not DoesEntityExist(object) then return nil end
    return object, NetworkGetNetworkIdFromEntity(object)
end

local function registerStretcher(netId)
    netId = tonumber(netId)
    if not netId or netId <= 0 or registeredStretchers[netId] or GetResourceState('ob_target') ~= 'started' then return end
    registeredStretchers[netId] = true
    exports.ob_target:RegisterNetworkEntity(('ob_health:stretcher:%s'):format(netId), netId, {
        label = 'Empurrar maca',
        icon = '+',
        event = 'ob_health:client:useStretcher',
        distance = tonumber(config().InteractionDistance) or 3.0,
    })
end

RegisterNetEvent('ob_health:client:registerStretcher', registerStretcher)

RegisterNetEvent('ob_health:client:removeStretcherTarget', function(netId)
    netId = tonumber(netId)
    registeredStretchers[netId] = nil
    if GetResourceState('ob_target') == 'started' then
        exports.ob_target:RemoveEntityOption(('ob_health:stretcher:%s'):format(netId))
    end
end)

RegisterNetEvent('ob_health:client:useStretcher', function(entity)
    if not entity or entity == 0 then return end
    CreateThread(function()
        local ok, message = OR.Callback.await('stretcherPush', NetworkGetNetworkIdFromEntity(entity))
        if not ok then OR.Notify(message or 'Nao foi possivel usar a maca.', 'error') end
    end)
end)

RegisterNetEvent('ob_health:client:pushStretcher', function(netId)
    local object = stretcherEntity(netId)
    if not object then
        local deadline = GetGameTimer() + 4000
        while not object and GetGameTimer() < deadline do Wait(50); object = stretcherEntity(netId) end
    end
    if not object then return OR.Notify('A maca nao carregou no cliente.', 'error') end
    pushingStretcher = tonumber(netId)
    local ped = PlayerPedId()
    local offset = type(config().CarryOffset) == 'table' and config().CarryOffset or {}
    FreezeEntityPosition(object, false)
    AttachEntityToEntity(object, ped, GetPedBoneIndex(ped, 28422),
        tonumber(offset.x) or 0.0, tonumber(offset.y) or -1.05, tonumber(offset.z) or -0.65,
        tonumber(offset.rx) or 0.0, tonumber(offset.ry) or 0.0, tonumber(offset.rz) or 0.0,
        true, true, false, true, 1, true)
    local animation = type(config().CarryAnimation) == 'table' and config().CarryAnimation or {}
    CreateThread(function()
        if not loadAnim(animation.dict or 'anim@heists@box_carry@') then return end
        while pushingStretcher == tonumber(netId) do
            ped = PlayerPedId()
            DisableControlAction(0, 47, true)
            if IsDisabledControlJustPressed(0, 47) or IsPedInAnyVehicle(ped, false)
                or LocalPlayer.state['or:downed'] == true then
                TriggerServerEvent('ob_health:server:dropStretcher', netId)
                break
            end
            if not IsEntityPlayingAnim(ped, animation.dict or 'anim@heists@box_carry@', animation.clip or 'idle', 3) then
                TaskPlayAnim(ped, animation.dict or 'anim@heists@box_carry@', animation.clip or 'idle',
                    8.0, -8.0, -1, animation.flag or 49, 0.0, false, false, false)
            end
            Wait(0)
        end
    end)
    OR.Notify('Empurrando maca. Pressione G para deixa-la no chao.', 'inform')
end)

RegisterNetEvent('ob_health:client:stopStretcher', function(netId, placeOnGround)
    if pushingStretcher == tonumber(netId) then pushingStretcher = nil end
    local object = stretcherEntity(netId)
    ClearPedTasks(PlayerPedId())
    if not object then return end
    DetachEntity(object, true, true)
    if placeOnGround == true then
        PlaceObjectOnGroundProperly(object)
        FreezeEntityPosition(object, true)
    end
end)

RegisterNetEvent('ob_health:client:setOnStretcher', function(enabled, netId, offset, animation)
    local ped = PlayerPedId()
    if enabled ~= true then
        if not IsPedInAnyVehicle(ped, false) then DetachEntity(ped, true, false) end
        TriggerEvent('ob_health:client:medicalPose', false)
        return
    end
    local object = stretcherEntity(netId)
    if not object then return end
    offset = type(offset) == 'table' and offset or {}
    TriggerEvent('ob_health:client:medicalPose', true, animation)
    AttachEntityToEntity(ped, object, 0,
        tonumber(offset.x) or 0.0, tonumber(offset.y) or 0.0, tonumber(offset.z) or 1.15,
        tonumber(offset.rx) or 0.0, tonumber(offset.ry) or 0.0, tonumber(offset.rz) or 180.0,
        false, false, false, false, 2, false)
end)

RegisterNetEvent('ob_health:client:patientStretcher', function(targetSource)
    CreateThread(function()
        local _, netId = closestStretcher(tonumber(config().InteractionDistance) or 3.0)
        local ok, message = OR.Callback.await('stretcherPatient', targetSource, netId)
        OR.Notify(message or (ok and 'Maca atualizada.' or 'Nenhuma maca proxima.'), ok and 'success' or 'error')
    end)
end)

RegisterNetEvent('ob_health:client:stretcherVehicle', function(vehicle)
    if not vehicle or vehicle == 0 then return end
    CreateThread(function()
        local ok, message = OR.Callback.await('stretcherVehicleAction', NetworkGetNetworkIdFromEntity(vehicle), pushingStretcher)
        OR.Notify(message or (ok and 'Equipamento atualizado.' or 'Nao foi possivel acessar a maca.'), ok and 'success' or 'error')
    end)
end)

local function registerVehicleTargets()
    if GetResourceState('ob_target') ~= 'started' then return end
    for modelName, enabled in pairs(type(config().AllowedVehicles) == 'table' and config().AllowedVehicles or {}) do
        if enabled == true then
            exports.ob_target:AddEntityOption(('ob_health:stretcher_vehicle:%s'):format(modelName), {
                label = 'Equipamentos EMS', icon = '+', event = 'ob_health:client:stretcherVehicle',
                model = GetHashKey(modelName), entityType = 2,
                distance = tonumber(config().VehicleDistance) or 7.0,
            })
        end
    end
end

CreateThread(function()
    Wait(800)
    registerVehicleTargets()
    local list = OR.Callback.await('stretcherList') or {}
    for _, netId in ipairs(list) do registerStretcher(netId) end
end)

AddEventHandler('ob_target:client:ready', function()
    registerVehicleTargets()
    CreateThread(function()
        local list = OR.Callback.await('stretcherList') or {}
        for _, netId in ipairs(list) do registerStretcher(netId) end
    end)
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    local object = pushingStretcher and stretcherEntity(pushingStretcher)
    if object then DetachEntity(object, true, true) end
    DetachEntity(PlayerPedId(), true, false)
    ClearPedTasks(PlayerPedId())
end)
