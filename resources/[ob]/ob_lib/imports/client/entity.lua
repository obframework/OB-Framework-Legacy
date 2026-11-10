local EntityApi = OR.Entity

function EntityApi.RequestControl(entity, timeout)
    entity = math.floor(tonumber(entity) or 0)
    if entity == 0 or not DoesEntityExist(entity) then return false end
    if not NetworkGetEntityIsNetworked(entity) or NetworkHasControlOfEntity(entity) then return true end
    local deadline = GetGameTimer() + math.max(250, math.floor(tonumber(timeout) or 2500))
    repeat
        NetworkRequestControlOfEntity(entity)
        if NetworkHasControlOfEntity(entity) then return true end
        Wait(0)
    until GetGameTimer() >= deadline
    return NetworkHasControlOfEntity(entity)
end

function EntityApi.FromNetId(netId)
    netId = math.floor(tonumber(netId) or 0)
    if netId <= 0 or not NetworkDoesEntityExistWithNetworkId(netId) then return nil end
    local entity = NetworkGetEntityFromNetworkId(netId)
    return entity ~= 0 and DoesEntityExist(entity) and entity or nil
end

function EntityApi.AwaitNetwork(netId, timeout)
    netId = math.floor(tonumber(netId) or 0)
    if netId <= 0 then return nil end
    local deadline = GetGameTimer() + math.max(250, math.floor(tonumber(timeout) or 8000))
    repeat
        local entity = EntityApi.FromNetId(netId)
        if entity then return entity end
        Wait(50)
    until GetGameTimer() >= deadline
    return nil
end

function EntityApi.ToNetId(entity)
    entity = math.floor(tonumber(entity) or 0)
    if entity == 0 or not DoesEntityExist(entity) or not NetworkGetEntityIsNetworked(entity) then return nil end
    local netId = NetworkGetNetworkIdFromEntity(entity)
    return netId > 0 and netId or nil
end

function EntityApi.SafeDelete(entity, timeout)
    entity = math.floor(tonumber(entity) or 0)
    if entity == 0 or not DoesEntityExist(entity) then return true end
    if not EntityApi.RequestControl(entity, timeout) then return false end
    SetEntityAsMissionEntity(entity, true, true)
    DeleteEntity(entity)
    return not DoesEntityExist(entity)
end

local function originCoords(coords)
    return OR.Validate.Coords(coords) or GetEntityCoords(PlayerPedId())
end

local function closestFromPool(poolName, coords, maximumDistance, filter)
    coords = originCoords(coords)
    maximumDistance = tonumber(maximumDistance) or 5.0
    local closest, closestDistance
    for _, entity in ipairs(GetGamePool(poolName)) do
        if DoesEntityExist(entity) and (not filter or filter(entity)) then
            local distance = #(coords - GetEntityCoords(entity))
            if distance <= maximumDistance and (not closestDistance or distance < closestDistance) then
                closest, closestDistance = entity, distance
            end
        end
    end
    return closest, closestDistance
end

function EntityApi.ClosestVehicle(coords, maximumDistance, filter)
    return closestFromPool('CVehicle', coords, maximumDistance, filter)
end

function EntityApi.ClosestObject(coords, maximumDistance, filter)
    return closestFromPool('CObject', coords, maximumDistance, filter)
end

function EntityApi.ClosestPed(coords, maximumDistance, filter)
    return closestFromPool('CPed', coords, maximumDistance, function(ped)
        return ped ~= PlayerPedId() and (not filter or filter(ped))
    end)
end

function EntityApi.ClosestPlayer(coords, maximumDistance)
    coords = originCoords(coords)
    maximumDistance = tonumber(maximumDistance) or 5.0
    local closestPlayer, closestPed, closestDistance
    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() then
            local ped = GetPlayerPed(player)
            if ped ~= 0 and DoesEntityExist(ped) then
                local distance = #(coords - GetEntityCoords(ped))
                if distance <= maximumDistance and (not closestDistance or distance < closestDistance) then
                    closestPlayer, closestPed, closestDistance = player, ped, distance
                end
            end
        end
    end
    return closestPlayer, closestPed, closestDistance, closestPlayer and GetPlayerServerId(closestPlayer) or nil
end
