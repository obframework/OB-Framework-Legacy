local function finiteNumber(value, fallback)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        return fallback or 0
    end
    return value
end

local function rounded(value, decimals)
    local multiplier = 10 ^ (decimals or 0)
    return math.floor(finiteNumber(value, 0) * multiplier + 0.5) / multiplier
end

local function pedSnapshot(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) or not IsEntityAPed(ped) then return nil end

    local coords = GetEntityCoords(ped)
    local vehicle = GetVehiclePedIsIn(ped, false)
    local vehicleNetId = 0
    local vehicleModel = 0
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        vehicleModel = GetEntityModel(vehicle)
        if NetworkGetEntityIsNetworked(vehicle) then
            vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
        end
    end

    return {
        model = GetEntityModel(ped),
        coords = {
            x = rounded(coords.x, 2),
            y = rounded(coords.y, 2),
            z = rounded(coords.z, 2),
        },
        health = GetEntityHealth(ped),
        armour = GetPedArmour(ped),
        visible = IsEntityVisible(ped),
        dead = IsEntityDead(ped),
        speed = rounded(GetEntitySpeed(ped), 2),
        head = GetPedDrawableVariation(ped, 0),
        mask = GetPedDrawableVariation(ped, 1),
        maskTexture = GetPedTextureVariation(ped, 1),
        hair = GetPedDrawableVariation(ped, 2),
        hairTexture = GetPedTextureVariation(ped, 2),
        hairColor = GetPedHairColor(ped),
        hairHighlight = GetPedHairHighlightColor(ped),
        vehicleNetId = vehicleNetId,
        vehicleModel = vehicleModel,
    }
end

local function collectSnapshot()
    local localPlayer = PlayerId()
    local localPed = PlayerPedId()
    local localState = pedSnapshot(localPed)
    if not localState then return nil end

    local radius = math.max(10.0, finiteNumber(OBDiagnosticsConfig.NearbyRadius, 150.0))
    local maximum = math.max(1, math.min(16, math.floor(finiteNumber(OBDiagnosticsConfig.MaxNearbyPlayers, 8))))
    local localCoords = GetEntityCoords(localPed)
    local nearby = {}

    for _, player in ipairs(GetActivePlayers()) do
        if player ~= localPlayer then
            local ped = GetPlayerPed(player)
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                local distance = #(localCoords - GetEntityCoords(ped))
                if distance <= radius then
                    local state = pedSnapshot(ped)
                    if state then
                        state.serverId = GetPlayerServerId(player)
                        state.distance = rounded(distance, 2)
                        nearby[#nearby + 1] = state
                    end
                end
            end
        end
    end

    table.sort(nearby, function(first, second)
        return (first.distance or radius) < (second.distance or radius)
    end)
    while #nearby > maximum do table.remove(nearby) end

    return {
        clientTimer = GetGameTimer(),
        networkSession = NetworkIsSessionStarted(),
        paused = IsPauseMenuActive(),
        localPed = localState,
        nearby = nearby,
    }
end

local function markAction(action, data)
    if not OBDiagnosticsConfig.Enabled or type(action) ~= 'string' or action == '' then return false end
    TriggerServerEvent('ob_diagnostics:server:action', action:sub(1, 64), type(data) == 'table' and data or {})
    return true
end

exports('markAction', markAction)

RegisterNetEvent('ob_diagnostics:client:markAction', function(action, data)
    markAction(action, data)
end)

CreateThread(function()
    if not OBDiagnosticsConfig.Enabled then return end

    local interval = math.max(1000, math.floor(finiteNumber(OBDiagnosticsConfig.HeartbeatMs, 2000)))
    local lastErrorAt = -30000
    Wait(500)
    TriggerServerEvent('ob_diagnostics:server:clientStarted', GetGameTimer())
    Wait(500)
    while true do
        if NetworkIsSessionStarted() then
            local ok, snapshot = pcall(collectSnapshot)
            if ok and snapshot then
                TriggerServerEvent('ob_diagnostics:server:heartbeat', snapshot)
            elseif not ok and GetGameTimer() - lastErrorAt >= 30000 then
                lastErrorAt = GetGameTimer()
                TriggerServerEvent('ob_diagnostics:server:clientError', tostring(snapshot))
            end
        end
        Wait(interval)
    end
end)
