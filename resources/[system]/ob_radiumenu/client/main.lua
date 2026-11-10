local open = false

local function locallyRestrained()
    return LocalPlayer.state['or:restrained'] == true or LocalPlayer.state['ob:restrained'] == true
end

local function restricted(serverId, ped)
    local state = Player(serverId).state
    return IsEntityDead(ped) or GetEntityHealth(ped) <= 0 or state['or:downed'] == true or state['or:restrained'] == true or state['ob:restrained'] == true
end

local function closestRestrictedPlayer()
    local me, coords, closest, distance = PlayerPedId(), GetEntityCoords(PlayerPedId()), nil, 3.0
    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        if ped ~= me and DoesEntityExist(ped) then
            local current = #(coords - GetEntityCoords(ped))
            local serverId = GetPlayerServerId(player)
            if current < distance and restricted(serverId, ped) then closest, distance = { serverId = serverId, ped = ped }, current end
        end
    end
    return closest
end

local function firstFreePassengerSeat(vehicle)
    local passengers = math.max(0, tonumber(GetVehicleMaxNumberOfPassengers(vehicle)) or 0)
    for seat = 0, passengers - 1 do
        if IsVehicleSeatFree(vehicle, seat) then return seat end
    end
end

local function close()
    if not open then return end
    open = false; SetNuiFocus(false, false); SendNUIMessage({ action = 'close' })
end

local function openMenu()
    if open or IsNuiFocused() or LocalPlayer.state['or:downed'] == true or locallyRestrained() then return end
    open = true; SetNuiFocus(true, true); SendNUIMessage({ action = 'open' })
end

RegisterCommand('ob_radiumenu', function() if open then close() else openMenu() end end, false)
RegisterKeyMapping('ob_radiumenu', 'Abrir menu radial', 'keyboard', 'F1')

RegisterNUICallback('close', function(_, cb) close(); cb({ ok = true }) end)
RegisterNUICallback('action', function(data, cb)
    local action = data and data.action
    if action == 'put' or action == 'remove' then
        local coords = GetEntityCoords(PlayerPedId())
        local target = closestRestrictedPlayer()
        local vehicle = 0
        if target then
            -- Para retirar, a fonte correta e o proprio ped: GetClosestVehicle
            -- pode ignorar veiculos ocupados e retornar zero.
            vehicle = action == 'remove' and GetVehiclePedIsIn(target.ped, false)
                or GetClosestVehicle(coords.x, coords.y, coords.z, 6.0, 0, 71)
        end
        if not target then OR.Notify('Aproxime-se de uma pessoa morta ou algemada.', 'error')
        elseif vehicle == 0 then
            OR.Notify(action == 'remove' and 'Essa pessoa nao esta em um veiculo.' or 'Nenhum veiculo proximo.', 'error')
        elseif action == 'put' then
            local seat = firstFreePassengerSeat(vehicle)
            if seat == nil then
                OR.Notify('Nao ha banco de passageiro livre nesse veiculo.', 'error')
            else
                TriggerServerEvent('ob_radiumenu:server:putInVehicle', target.serverId, NetworkGetNetworkIdFromEntity(vehicle), seat)
            end
        else
            TriggerServerEvent('ob_radiumenu:server:removeFromVehicle', target.serverId)
        end
        close()
    elseif action == 'outfits' then
        local outfits = OR.Callback.awaitResource('ob_radiumenu', 'outfits') or {}
        SendNUIMessage({ action = 'outfits', data = outfits })
    elseif action == 'saveOutfit' then
        local slot = math.max(1, math.min(5, tonumber(data.slot) or 1))
        local appearance = exports.ob_creator:getPedAppearance(PlayerPedId())
        local ok = appearance and OR.Callback.awaitResource('ob_radiumenu', 'saveOutfit', slot, data.label, appearance)
        OR.Notify(ok and 'Roupa salva.' or 'Nao foi possivel salvar a roupa.', ok and 'success' or 'error')
        if ok then
            local outfits = OR.Callback.awaitResource('ob_radiumenu', 'outfits') or {}
            SendNUIMessage({ action = 'outfits', data = outfits })
        end
    elseif action == 'loadOutfit' then
        local appearance = OR.Callback.awaitResource('ob_radiumenu', 'loadOutfit', data.slot)
        if appearance and exports.ob_creator:setPlayerAppearance(appearance) then OR.Notify('Roupa vestida.', 'success') else OR.Notify('Roupa nao encontrada.', 'error') end
        close()
    end
    cb({ ok = true })
end)

RegisterNetEvent('ob_radiumenu:client:forceClose', close)

RegisterNetEvent('ob_radiumenu:client:enterVehicle', function(netId, seat)
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    seat = math.floor(tonumber(seat) or -1)
    if vehicle == 0 or not DoesEntityExist(vehicle) or seat < 0 then return end
    if seat >= GetVehicleMaxNumberOfPassengers(vehicle) or not IsVehicleSeatFree(vehicle, seat) then return end
    local ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    ClearPedSecondaryTask(ped)
    DetachEntity(ped, true, false)
    SetEntityVisible(ped, true, false)
    ResetEntityAlpha(ped)
    SetPedCanRagdoll(ped, false)
    SetPedIntoVehicle(ped, vehicle, seat)
    SetPedConfigFlag(ped, 184, true)
    Wait(0)
    SetPedCanRagdoll(ped, true)
end)
RegisterNetEvent('ob_radiumenu:client:leaveVehicle', function(netId)
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    local ped = PlayerPedId()
    if vehicle ~= 0 and GetVehiclePedIsIn(ped, false) == vehicle then
        ClearPedTasksImmediately(ped)
        TaskLeaveVehicle(ped, vehicle, 16)

        local deadline = GetGameTimer() + 2500
        while GetVehiclePedIsIn(ped, false) == vehicle and GetGameTimer() < deadline do Wait(0) end

        -- A tarefa de sair termina com o ped em pe. Depois que o assento foi
        -- realmente liberado, o health devolve o ragdoll e a pose de morte.
        if GetVehiclePedIsIn(ped, false) == 0
            and LocalPlayer.state['or:downed'] == true
            and GetResourceState('ob_health') == 'started' then
            Wait(100)
            exports.ob_health:RestoreDownedPose()
        end
    end
end)
AddEventHandler('onResourceStop', function(resource) if resource == GetCurrentResourceName() then close() end end)
