local stretchers = {}
local playerStretcher = {}

local function config()
    return type(ORHealthConfig.Stretcher) == 'table' and ORHealthConfig.Stretcher or {}
end

local function validSource(playerSource)
    playerSource = tonumber(playerSource)
    return playerSource and playerSource > 0 and GetPlayerName(playerSource) and playerSource or nil
end

local function coords(entity)
    return entity and entity > 0 and DoesEntityExist(entity) and GetEntityCoords(entity) or nil
end

local function closeEntities(first, second, maximum)
    local a, b = coords(first), coords(second)
    return a and b and #(a - b) <= maximum
end

local function allowedVehicle(vehicle)
    if not vehicle or vehicle <= 0 or not DoesEntityExist(vehicle) then return false end
    local model = GetEntityModel(vehicle)
    for modelName, enabled in pairs(type(config().AllowedVehicles) == 'table' and config().AllowedVehicles or {}) do
        if enabled == true and joaat(modelName) == model then return true end
    end
    return false
end

local function stretcherRecord(netId)
    netId = tonumber(netId)
    local record = netId and stretchers[netId]
    if not record or not DoesEntityExist(record.entity) then
        if netId then stretchers[netId] = nil end
        return nil
    end
    return record
end

local function releasePatient(targetSource)
    targetSource = tonumber(targetSource)
    local netId = targetSource and playerStretcher[targetSource]
    local record = netId and stretcherRecord(netId)
    playerStretcher[targetSource] = nil
    if record and record.patient == targetSource then record.patient = nil end
    local player = targetSource and Player(targetSource)
    if player then player.state:set('ob:onStretcher', nil, true) end
    if validSource(targetSource) then TriggerClientEvent('ob_health:client:setOnStretcher', targetSource, false) end
    return netId ~= nil
end

local function stopOwner(record, placeOnGround)
    if not record or not record.owner then return end
    local owner = record.owner
    record.owner = nil
    if validSource(owner) then TriggerClientEvent('ob_health:client:stopStretcher', owner, record.netId, placeOnGround == true) end
end

local function createStretcher(ownerSource, spawnCoords)
    local cfg = config()
    if cfg.Enabled ~= true then return nil, 'Sistema de maca desativado.' end
    local model = joaat(tostring(cfg.Model or 'v_med_bed2'))
    local object = CreateObject(model, spawnCoords.x, spawnCoords.y, spawnCoords.z, true, true, false)
    if object == 0 or not DoesEntityExist(object) then return nil, 'Nao foi possivel criar a maca.' end
    local netId = NetworkGetNetworkIdFromEntity(object)
    if not netId or netId <= 0 then DeleteEntity(object); return nil, 'A maca nao recebeu identificacao de rede.' end
    local record = { entity = object, netId = netId, owner = ownerSource, patient = nil }
    stretchers[netId] = record
    Entity(object).state:set('ob:stretcher', true, true)
    TriggerClientEvent('ob_health:client:registerStretcher', -1, netId)
    if ownerSource then TriggerClientEvent('ob_health:client:pushStretcher', ownerSource, netId) end
    return record
end

local function deployForPlayer(playerSource)
    playerSource = validSource(playerSource)
    if not playerSource or not exports.ob_health:HasEmsAccess(playerSource) then
        return false, 'Somente EMS em servico pode montar a maca.'
    end
    for _, record in pairs(stretchers) do
        if record.owner == playerSource then return false, 'Voce ja esta empurrando uma maca.' end
    end
    local ped = GetPlayerPed(playerSource)
    local position = coords(ped)
    if not position then return false, 'Posicao indisponivel.' end
    local record, errorMessage = createStretcher(playerSource, position)
    if not record then return false, errorMessage end
    return true, 'Maca montada. Pressione G para deixa-la no chao.'
end

exports('DeployStretcherItem', deployForPlayer)
exports('ReleaseStretcherPatient', releasePatient)

OR.Callback.register('stretcherList', function()
    local list = {}
    for netId, record in pairs(stretchers) do
        if DoesEntityExist(record.entity) then list[#list + 1] = netId end
    end
    return list
end)

OR.Callback.register('stretcherPush', function(source, netId)
    if not exports.ob_health:HasEmsAccess(source) then return false, 'Somente EMS em servico pode usar a maca.' end
    local record = stretcherRecord(netId)
    if not record then return false, 'Maca indisponivel.' end
    if record.owner and record.owner ~= source then return false, 'Outro profissional ja esta empurrando essa maca.' end
    if not closeEntities(GetPlayerPed(source), record.entity, tonumber(config().InteractionDistance) or 3.0) then
        return false, 'Aproxime-se da maca.'
    end
    record.owner = source
    TriggerClientEvent('ob_health:client:pushStretcher', source, record.netId)
    return true
end)

RegisterNetEvent('ob_health:server:dropStretcher', function(netId)
    local playerSource = validSource(source)
    local record = stretcherRecord(netId)
    if not playerSource or not record or record.owner ~= playerSource then return end
    stopOwner(record, true)
end)

OR.Callback.register('stretcherPatient', function(source, targetSource, netId)
    local target, validationError = exports.ob_health:ValidateEmsPatient(source, targetSource)
    if not target then return false, validationError end
    if playerStretcher[target] then
        releasePatient(target)
        return true, 'Paciente retirado da maca.', false
    end
    if Player(target).state['or:downed'] ~= true then return false, 'Somente pacientes incapacitados podem ser colocados na maca.' end
    local record = stretcherRecord(netId)
    if not record then return false, 'Aproxime uma maca do paciente.' end
    if record.patient then return false, 'Essa maca ja possui um paciente.' end
    if not closeEntities(GetPlayerPed(target), record.entity, tonumber(config().InteractionDistance) or 3.0) then
        return false, 'Aproxime a maca do paciente.'
    end
    record.patient = target
    playerStretcher[target] = record.netId
    Player(target).state:set('ob:onStretcher', record.netId, true)
    TriggerClientEvent('ob_health:client:setOnStretcher', target, true, record.netId, config().PatientOffset, config().PatientAnimation)
    return true, 'Paciente colocado na maca.', true
end)

OR.Callback.register('stretcherVehicleAction', function(source, vehicleNetId, currentStretcherNetId)
    if not exports.ob_health:HasEmsAccess(source) then return false, 'Somente EMS em servico pode acessar as macas.' end
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(vehicleNetId) or 0)
    if not allowedVehicle(vehicle) then return false, 'Esse veiculo nao esta configurado para macas.' end
    local maximumDistance = tonumber(config().VehicleDistance) or 7.0
    if not closeEntities(GetPlayerPed(source), vehicle, maximumDistance) then return false, 'Aproxime-se do veiculo.' end
    local capacity = math.max(0, math.floor(tonumber(config().VehicleCapacity) or 2))
    local state = Entity(vehicle).state
    local available = tonumber(state['ob:stretchers'])
    if available == nil then available = capacity end

    local record = stretcherRecord(currentStretcherNetId)
    if record and record.owner == source then
        if record.patient then return false, 'Retire o paciente antes de guardar a maca.' end
        if not closeEntities(record.entity, vehicle, maximumDistance) then return false, 'Aproxime a maca do veiculo.' end
        if available >= capacity then return false, 'O veiculo ja esta com todas as macas.' end
        stopOwner(record, false)
        stretchers[record.netId] = nil
        DeleteEntity(record.entity)
        state:set('ob:stretchers', available + 1, true)
        TriggerClientEvent('ob_health:client:removeStretcherTarget', -1, record.netId)
        return true, 'Maca guardada no veiculo.'
    end

    if available < 1 then return false, 'Nao ha macas disponiveis nesse veiculo.' end
    local position = coords(vehicle)
    local created, createError = createStretcher(source, position)
    if not created then return false, createError end
    state:set('ob:stretchers', available - 1, true)
    return true, ('Maca retirada. Restam %d no veiculo.'):format(available - 1)
end)

AddEventHandler('ob_health:server:beforePatientVehicle', releasePatient)
AddEventHandler('ob_health:server:patientRecovered', releasePatient)

AddEventHandler('playerDropped', function()
    local playerSource = tonumber(source)
    releasePatient(playerSource)
    for _, record in pairs(stretchers) do
        if record.owner == playerSource then stopOwner(record, true) end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, record in pairs(stretchers) do
        if DoesEntityExist(record.entity) then DeleteEntity(record.entity) end
    end
end)
