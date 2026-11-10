local belted = false
local kmh = 3.6

local function notify(text, kind)
    if OR and OR.Notify then OR.Notify(text, kind or 'info') end
end

local function supportedVehicle(vehicle)
    return vehicle ~= 0 and DoesEntityExist(vehicle) and not OBSeatbeltConfig.ExcludedVehicleClasses[GetVehicleClass(vehicle)]
end

local function setBelt(value, silent)
    belted = value == true
    TriggerEvent('ob_hud:client:setSeatbelt', belted)
    if not silent then
        notify(belted and 'Cinto colocado.' or 'Cinto removido.', belted and 'success' or 'inform')
    end
end

exports('IsBuckled', function() return belted end)

RegisterCommand('+ob_seatbelt', function()
    if LocalPlayer.state['or:loaded'] ~= true or LocalPlayer.state['or:downed'] == true then return end
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not supportedVehicle(vehicle) then return end
    setBelt(not belted)
end, false)
RegisterCommand('-ob_seatbelt', function() end, false)
RegisterKeyMapping('+ob_seatbelt', 'Colocar ou remover cinto de seguranca', 'keyboard', OBSeatbeltConfig.Key)

CreateThread(function()
    local lastSpeed, lastVelocity = 0.0, vector3(0.0, 0.0, 0.0)
    while true do
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        if supportedVehicle(vehicle) then
            local speed = GetEntitySpeed(vehicle) * kmh
            if not belted and lastSpeed >= OBSeatbeltConfig.EjectSpeedKmh and speed <= (lastSpeed * OBSeatbeltConfig.ImpactSpeedDrop) and HasEntityCollidedWithAnything(vehicle) then
                -- Sai para a frente usando a velocidade anterior ao impacto.
                local coords = GetEntityCoords(ped)
                TaskLeaveVehicle(ped, vehicle, 4160)
                Wait(0)
                SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z + 0.45, false, false, false)
                SetEntityVelocity(ped, lastVelocity.x * 1.25, lastVelocity.y * 1.25, math.max(lastVelocity.z * 1.25, 1.5))
                SetPedToRagdoll(ped, 1500, 2000, 0, false, false, false)
                notify('Voce foi arremessado: estava sem cinto.', 'error')
                lastSpeed = 0.0
            else
                lastSpeed = speed
                lastVelocity = GetEntityVelocity(vehicle)
            end
            Wait(0)
        else
            if belted then setBelt(false, true) end
            lastSpeed, lastVelocity = 0.0, vector3(0.0, 0.0, 0.0)
            Wait(200)
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then setBelt(false, true) end
end)
