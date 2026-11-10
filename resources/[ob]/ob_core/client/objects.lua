-- Objetos temporarios de gameplay precisam ser entidades de rede para que
-- outros jogadores vejam o mesmo prop, especialmente quando ele esta preso
-- na mao de um personagem.
local createdObjects = {}

local function validEntity(entity)
    return entity and entity ~= 0 and DoesEntityExist(entity)
end

local function createNetworkedObject(model, coords, useModelOffset)
    model = tonumber(model) or 0
    if model == 0 or not HasModelLoaded(model) then return 0 end
    coords = coords or GetEntityCoords(PlayerPedId())

    local create = useModelOffset == true and CreateObject or CreateObjectNoOffset
    local object = create(model, coords.x, coords.y, coords.z, true, true, false)
    if not validEntity(object) then return 0 end

    SetEntityAsMissionEntity(object, true, true)
    local netId = NetworkGetNetworkIdFromEntity(object)
    if netId and netId ~= 0 then SetNetworkIdCanMigrate(netId, true) end
    createdObjects[object] = true
    return object, netId
end

local function deleteNetworkedObject(object)
    if not validEntity(object) then return true end
    DetachEntity(object, true, false)
    local removed = OR.Entity.SafeDelete(object, 750)
    if removed then createdObjects[object] = nil end
    return removed == true
end

exports('CreateNetworkedObject', createNetworkedObject)
exports('DeleteNetworkedObject', deleteNetworkedObject)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for object in pairs(createdObjects) do deleteNetworkedObject(object) end
    createdObjects = {}
end)
