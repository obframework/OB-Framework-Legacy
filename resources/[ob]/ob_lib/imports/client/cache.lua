local Cache = OR.Cache
local listeners, enabled, interval = {}, false, 500

local function seatForPed(ped, vehicle)
    if vehicle == 0 then return nil end
    if GetPedInVehicleSeat(vehicle, -1) == ped then return -1 end
    for seat = 0, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        if GetPedInVehicleSeat(vehicle, seat) == ped then return seat end
    end
    return nil
end

local function setValue(key, value)
    local previous = rawget(Cache, key)
    rawset(Cache, key, value)
    if previous ~= value and listeners[key] then
        for _, callback in pairs(listeners[key]) do pcall(callback, value, previous) end
    end
end

function Cache.Refresh()
    local ped = PlayerPedId()
    local playerId = PlayerId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    local _, weapon = GetCurrentPedWeapon(ped, true)
    setValue('ped', ped)
    setValue('playerId', playerId)
    setValue('serverId', GetPlayerServerId(playerId))
    setValue('vehicle', vehicle ~= 0 and vehicle or nil)
    setValue('seat', seatForPed(ped, vehicle))
    setValue('coords', GetEntityCoords(ped))
    setValue('weapon', weapon)
    return Cache
end

function Cache.Get(key, refresh)
    if refresh == true then Cache.Refresh() end
    return rawget(Cache, key)
end

function Cache.On(key, callback)
    assert(type(key) == 'string' and key ~= '', 'cache key must be a non-empty string')
    assert(type(callback) == 'function', 'cache listener must be a function')
    listeners[key] = listeners[key] or {}
    local id = #listeners[key] + 1
    listeners[key][id] = callback
    return function() listeners[key][id] = nil end
end

function Cache.Enable(updateInterval)
    interval = math.max(100, math.floor(tonumber(updateInterval) or interval))
    if enabled then return false end
    enabled = true
    CreateThread(function()
        while enabled do Cache.Refresh(); Wait(interval) end
    end)
    return true
end

function Cache.Disable()
    enabled = false
end

function Cache.IsEnabled()
    return enabled
end

Cache.Refresh()
