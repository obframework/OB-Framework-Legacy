AddStateBagChangeHandler('ob:init_vehicle', nil, function(bagName, _, value)
    if type(value) ~= 'table' then return end
    CreateThread(function()
        local deadline = GetGameTimer() + 8000
        repeat
            local vehicle = GetEntityFromStateBagName(bagName)
            if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                if type(value.plate) == 'string' and value.plate ~= '' then SetVehicleNumberPlateText(vehicle, value.plate) end
                if tonumber(value.fuel) then SetVehicleFuelLevel(vehicle, math.max(0.0, math.min(100.0, tonumber(value.fuel)))) end
                return
            end
            Wait(50)
        until GetGameTimer() >= deadline
    end)
end)


