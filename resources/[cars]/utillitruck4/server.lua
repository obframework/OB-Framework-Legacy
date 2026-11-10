local MODEL = GetHashKey('utillitruck4')
local ACTIVE_KEY = 'ob:utillitruckActive'
local ANIM_KEY = 'ob:utillitruckAnim'
local activeVehicles = {}
local lastToggle = {}

local function isStowed(vehicle)
    local snapshot = Entity(vehicle).state[ANIM_KEY]
    if type(snapshot) ~= 'table' then return true end
    local vertical = tonumber(snapshot.vertical) or 0.0
    local horizontal = tonumber(snapshot.horizontal) or 0.0
    return vertical <= 0.004 and math.min(horizontal, 1.0 - horizontal) <= 0.004
end

local function driverVehicle(playerSource, netId)
    netId = tonumber(netId)
    if not netId or netId < 1 or netId > 65535 or netId ~= math.floor(netId) then return nil end
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityModel(vehicle) ~= MODEL then return nil end
    local ped = GetPlayerPed(playerSource)
    if not ped or ped == 0 or not DoesEntityExist(ped) or GetPedInVehicleSeat(vehicle, -1) ~= ped then return nil end
    return vehicle
end

local function deactivate(vehicle)
    activeVehicles[vehicle] = nil
    if DoesEntityExist(vehicle) then
        Entity(vehicle).state:set(ACTIVE_KEY, false, true)
        Entity(vehicle).state:set(ANIM_KEY, nil, true)
    end
end

RegisterNetEvent('ob_utillitruck:server:setActive', function(netId, enabled)
    local playerSource = source
    if type(enabled) ~= 'boolean' then return end
    local vehicle = driverVehicle(playerSource, netId)
    if not vehicle then return end
    local now = GetGameTimer()
    if lastToggle[playerSource] and now - lastToggle[playerSource] < 500 then return end
    lastToggle[playerSource] = now

    local record = activeVehicles[vehicle]
    if enabled then
        if record then
            record.owner = playerSource
            return
        end
        activeVehicles[vehicle] = { owner = playerSource, lastAnim = 0 }
        Entity(vehicle).state:set(ANIM_KEY, { mode = 1, vertical = 0.0, horizontal = 0.0 }, true)
        Entity(vehicle).state:set(ACTIVE_KEY, true, true)
    elseif record and isStowed(vehicle) then
        deactivate(vehicle)
    end
end)

RegisterNetEvent('ob_utillitruck:server:setAnim', function(netId, mode, vertical, horizontal)
    local playerSource = source
    local vehicle = driverVehicle(playerSource, netId)
    if not vehicle then return end
    local record = activeVehicles[vehicle]
    if not record then return end
    record.owner = playerSource
    mode, vertical, horizontal = tonumber(mode), tonumber(vertical), tonumber(horizontal)
    if (mode ~= 1 and mode ~= 2) or not vertical or not horizontal
        or vertical ~= vertical or horizontal ~= horizontal
        or vertical < 0.0 or vertical > 1.0 or horizontal < 0.0 or horizontal > 1.0 then return end
    local now = GetGameTimer()
    if now - record.lastAnim < 80 then return end
    record.lastAnim = now
    Entity(vehicle).state:set(ANIM_KEY,
        { mode = mode, vertical = vertical, horizontal = horizontal }, true)
end)

CreateThread(function()
    while true do
        for vehicle, record in pairs(activeVehicles) do
            if not DoesEntityExist(vehicle) or GetEntityModel(vehicle) ~= MODEL then
                activeVehicles[vehicle] = nil
            elseif record.owner then
                local ped = GetPlayerPed(record.owner)
                if not ped or ped == 0 or not DoesEntityExist(ped)
                    or GetPedInVehicleSeat(vehicle, -1) ~= ped then
                    if isStowed(vehicle) then deactivate(vehicle) else record.owner = nil end
                end
            end
        end
        Wait(1000)
    end
end)

AddEventHandler('playerDropped', function()
    local playerSource = source
    lastToggle[playerSource] = nil
    for vehicle, record in pairs(activeVehicles) do
        if record.owner == playerSource then
            if DoesEntityExist(vehicle) and not isStowed(vehicle) then
                record.owner = nil
            else
                deactivate(vehicle)
            end
        end
    end
end)

AddEventHandler('entityRemoved', function(entity)
    activeVehicles[entity] = nil
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    for vehicle in pairs(activeVehicles) do deactivate(vehicle) end
end)
