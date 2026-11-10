-- Servico compartilhado de veiculos: nao depende de garagem nem de inventario.
local function trim(value) return tostring(value or ''):gsub('^%s*(.-)%s*$', '%1') end
local function getVehicle(netId)
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    return vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and vehicle or nil
end

-- Um veiculo criado pelo cliente pode levar alguns frames para existir no
-- servidor. Sem esta espera a retirada ocasionalmente ficava sem a chave.
local function waitForVehicle(netId, timeout)
    -- Em OneSync/Enhanced a criacao no cliente pode levar alguns segundos ate
    -- a entidade aparecer no servidor. Aguardar mais aqui evita falha de
    -- chave temporaria sem gravar state bag pelo cliente.
    local deadline = GetGameTimer() + (tonumber(timeout) or 8000)
    local vehicle = getVehicle(netId)
    while not vehicle and GetGameTimer() < deadline do
        Wait(50)
        vehicle = getVehicle(netId)
    end
    return vehicle
end

local function spawnPoint(raw)
    if not raw then return nil end
    local x, y, z = tonumber(raw.x), tonumber(raw.y), tonumber(raw.z)
    if not x or not y or not z or math.abs(x) > 10000 or math.abs(y) > 10000 or z < -2000 or z > 5000 then return nil end
    return { x = x, y = y, z = z, w = tonumber(raw.w or raw.heading) or 0.0 }
end

local function spawnIsClear(coords, radius)
    radius = math.max(1.0, math.min(15.0, tonumber(radius) or 3.0))
    for _, vehicle in ipairs(GetAllVehicles()) do
        if DoesEntityExist(vehicle) and #(GetEntityCoords(vehicle) - vector3(coords.x, coords.y, coords.z)) <= radius then
            return false
        end
    end
    return true
end

-- Unico ponto de criacao de veiculos de gameplay. O pedido nasce em outro
-- recurso servidor depois da regra daquele trabalho/loja ser validada; o
-- cliente recebe apenas o NetID da entidade que o servidor ja criou.
local function createServerVehicle(source, model, rawCoords, options)
    source = tonumber(source)
    options = type(options) == 'table' and options or {}
    local coords = spawnPoint(rawCoords)
    local modelHash = type(model) == 'number' and model or type(model) == 'string' and joaat(model) or 0
    local ped = source and GetPlayerPed(source) or 0
    if not source or not GetPlayerName(source) or ped <= 0 or not coords or modelHash == 0 then
        return nil, 'Dados de criacao do veiculo invalidos.'
    end
    local maximumDistance = math.max(10.0, math.min(5000.0, tonumber(options.maxDistance) or 45.0))
    if #(GetEntityCoords(ped) - vector3(coords.x, coords.y, coords.z)) > maximumDistance then
        return nil, 'A vaga de criacao esta longe demais.'
    end
    if options.clearRadius ~= false and not spawnIsClear(coords, options.clearRadius) then
        return nil, 'A vaga de veiculo esta ocupada.'
    end

    local vehicle
    if type(options.serverSetterType) == 'string' and options.serverSetterType ~= '' then
        vehicle = CreateVehicleServerSetter(modelHash, options.serverSetterType, coords.x, coords.y, coords.z, coords.w)
    else
        vehicle = CreateVehicle(modelHash, coords.x, coords.y, coords.z, coords.w, true, true)
    end
    local deadline = GetGameTimer() + 8000
    while (not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)) and GetGameTimer() < deadline do Wait(50) end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil, 'O servidor nao conseguiu criar o veiculo.' end
    SetEntityOrphanMode(vehicle, 2)
    SetEntityRoutingBucket(vehicle, GetPlayerRoutingBucket(source))
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if not netId or netId == 0 then
        DeleteEntity(vehicle)
        return nil, 'O veiculo foi criado sem identificacao de rede.'
    end
    return vehicle, nil, netId
end


local function grantTemporaryKey(source, netId)
    if GetResourceState('ob_vehiclekeys') ~= 'started' then return false, 'Sistema de chaves indisponivel.' end
    return exports.ob_vehiclekeys:GrantTemporaryKey(source, netId)
end
local function grantTemporaryVehicleKey(source, netId)
    if GetResourceState('ob_vehiclekeys') ~= 'started' then return false, 'Sistema de chaves indisponivel.' end
    return exports.ob_vehiclekeys:GrantTemporaryVehicleKey(source, netId)
end
local function deleteTemporaryVehicle(source, netId)
    source = tonumber(source)
    local vehicle = getVehicle(netId)
    if not source or not vehicle then return false end
    local state = Entity(vehicle).state
    if tonumber(state['ob:temporary_key_owner']) ~= source then return false end
    if tonumber(state['ob:temporary_key_user']) ~= tonumber(exports.ob_core:GetUserId(source)) then return false end
    if state['ob:job_vehicle'] ~= true and state['ob:temporary_vehicle'] ~= true then return false end
    if GetResourceState('ob_vehiclekeys') == 'started' then
        local prepared = exports.ob_vehiclekeys:PrepareVehicleRemoval(source, netId, false)
        if not prepared then return false end
    end
    DeleteEntity(vehicle)
    return true
end

-- Limpeza sem retorno para o recurso solicitante. Deve ser usada durante
-- onResourceStop: a remocao das chaves consulta o banco e pode terminar depois
-- que o runtime Lua de quem pediu ja foi destruido pelo restart.
local function deleteTemporaryVehicleDetached(source, netId)
    source, netId = tonumber(source), tonumber(netId)
    if not source or not netId then return false end
    CreateThread(function()
        local vehicle = getVehicle(netId)
        if not vehicle then return end
        if not deleteTemporaryVehicle(source, netId) and DoesEntityExist(vehicle) then
            DeleteEntity(vehicle)
        end
    end)
    return true
end

AddEventHandler('ob_core:server:deleteTemporaryVehicleDetached', deleteTemporaryVehicleDetached)

local function spawnTemporaryVehicle(source, model, coords, options)
    if GetResourceState('ob_vehiclekeys') ~= 'started' then return false, 'Sistema de chaves indisponivel.' end
    options = type(options) == 'table' and options or {}
    local vehicle, errorMessage, netId = createServerVehicle(source, model, coords, options)
    if not vehicle then return false, errorMessage end
    local prefix = tostring(options.platePrefix or 'JOB'):upper():gsub('[^A-Z0-9]', ''):sub(1, 6)
    if prefix == '' then prefix = 'JOB' end
    local plate = trim(options.plate)
    if plate == '' then plate = ('%s%03d'):format(prefix, math.random(100, 999)) end
    plate = plate:sub(1, 12)
    SetVehicleNumberPlateText(vehicle, plate)
    local fuel = math.max(0, math.min(100, tonumber(options.fuel) or 100))
    local state = Entity(vehicle).state
    state:set('ob:fuel', fuel, true)
    state:set('ob:init_vehicle', { plate = plate, fuel = fuel }, true)
    local grant = options.temporaryKind == 'admin' and grantTemporaryVehicleKey or grantTemporaryKey
    local granted, keyError = grant(source, netId)
    if not granted then
        DeleteEntity(vehicle)
        return false, keyError or 'Nao foi possivel entregar a chave temporaria.'
    end
    return true, { netId = netId, plate = plate }
end


-- Nao atravessar a fronteira entre recursos com um nil entre entidade e NetID.
-- O consumidor resolve a entidade no proprio contexto a partir do NetID.
exports('CreateServerVehicle', function(...)
    local entity, message, netId = createServerVehicle(...)
    if not entity then return { ok = false, error = message } end
    return { ok = true, netId = netId }
end)
exports('IsVehicleSpawnClear', spawnIsClear)
exports('SpawnTemporaryVehicle', spawnTemporaryVehicle)
exports('DeleteTemporaryVehicle', deleteTemporaryVehicle)
exports('DeleteTemporaryVehicleDetached', deleteTemporaryVehicleDetached)
