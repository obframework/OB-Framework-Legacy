local attempts, worldVehicles, temporary, ownedBindings = {}, {}, {}, {}
local ready, ownedTableReady, sequence = false, false, 0
local epoch = ('%s:%s:%s'):format(os.time(), GetGameTimer(), math.random(100000, 999999))
local function uid(src)
    local value = exports.ob_core:GetUserId(tonumber(src))
    return tonumber(value)
end
local function sameModel(left, right) return (tonumber(left) or 0) % 4294967296 == (tonumber(right) or 0) % 4294967296 end
local function trim(value) return tostring(value or ''):gsub('^%s*(.-)%s*$', '%1') end
local function vehicleFromNet(netId)
    netId = tonumber(netId)
    if not netId or netId ~= netId or netId <= 0 or netId % 1 ~= 0 then return nil end
    local entity = NetworkGetEntityFromNetworkId(netId)
    return entity and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 2 and entity or nil
end
local function near(src, entity, distance)
    local ped = GetPlayerPed(src)
    return ped and ped ~= 0 and DoesEntityExist(entity)
        and GetPlayerRoutingBucket(src) == GetEntityRoutingBucket(entity)
        and #(GetEntityCoords(ped) - GetEntityCoords(entity)) <= (distance or 5.0)
end
local function validActor(src, character)
    return GetPlayerName(src) and uid(src) == character and character ~= nil
        and Player(src).state['or:downed'] ~= true
end
local function notify(src, text, kind) TriggerClientEvent('ob_notification:client:notify', src, text, kind or 'info') end
local function info(entity)
    local plate, model = trim(GetVehicleNumberPlateText(entity)), GetEntityModel(entity)
    local binding = ownedBindings[entity]
    if binding and sameModel(binding.model, model) then
        local row = OR.Database.single.await('SELECT id,owner_user_id,model,plate FROM ob_vehicles WHERE id=? LIMIT 1', { binding.id })
        if row and sameModel(joaat(row.model), model) then
            return { identity = ('owned:%s:%s'):format(row.id, row.owner_user_id), owner = tonumber(row.owner_user_id), plate = trim(row.plate), model = model }
        end
        return nil
    end
    -- A placa chega por RPC e pode mudar depois da entrega da chave. A
    -- identidade de uma entidade ja conhecida nao pode mudar junto com ela.
    local entry = worldVehicles[entity]
    if entry and sameModel(entry.model, model) then
        entry.plate = plate
        return entry
    end
    if ownedTableReady then
        local row, err = OR.Database.single.await('SELECT id,owner_user_id,model FROM ob_vehicles WHERE plate=? LIMIT 1', { plate })
        if err then
            print('[ob_vehiclekeys] Falha ao consultar cadastro do veiculo: ' .. tostring(err))
            return nil
        end
        if row and sameModel(joaat(row.model), model) then
            return { identity = ('owned:%s:%s'):format(row.id, row.owner_user_id), owner = tonumber(row.owner_user_id), plate = plate, model = model }
        end
    end
    if not entry or not sameModel(entry.model, model) then
        sequence = sequence + 1
        entry = { identity = 'world:' .. epoch .. ':' .. sequence, plate = plate, model = model }
        worldVehicles[entity] = entry
    end
    return entry
end
local function physicalKey(src, identity)
    local inventory = exports.ob_inventory:GetInventory(src)
    for _, item in pairs(inventory and inventory.items or {}) do
        local metadata = item.metadata or {}
        if item.name == VehicleKeysConfig.KeyItem and (tonumber(item.amount) or 0) > 0 and metadata.key_id then
            local key = OR.Database.single.await('SELECT id FROM ob_vehicle_keys WHERE id=? AND vehicle_identity=? LIMIT 1', { tostring(metadata.key_id), identity })
            if key then return true, item.slot, metadata end
        end
    end
    return false
end
local function authorized(src, entity, data)
    local character = uid(src)
    if not character or not ready then return false end
    data = data or info(entity)
    if not data then return false end
    if VehicleKeysConfig.virtual == false then return physicalKey(src, data.identity) end
    if data.owner == character then return true end
    local grant = temporary[entity]
    if grant and grant.identity == data.identity and grant.userId == character then return true end
    local key = OR.Database.single.await('SELECT id FROM ob_vehicle_keys WHERE vehicle_identity=? AND user_id=? LIMIT 1', { data.identity, character })
    return type(key) == 'table'
end
local function grant(src, entity, kind)
    local character = uid(src)
    if not ready or not character then return false, 'Sistema de chaves ainda iniciando.' end
    local data = info(entity)
    if not data then return false, 'Nao foi possivel identificar o veiculo.' end
    local _, err = OR.Database.query.await('INSERT IGNORE INTO ob_vehicle_keys (vehicle_identity,user_id,key_kind) VALUES (?,?,?)', { data.identity, character, kind })
    if err then return false, 'Nao foi possivel salvar a chave.' end
    local row = OR.Database.single.await('SELECT id FROM ob_vehicle_keys WHERE vehicle_identity=? AND user_id=? LIMIT 1', { data.identity, character })
    if not row or not validActor(src, character) or not DoesEntityExist(entity) then return false, 'Entrega de chave cancelada.' end
    if VehicleKeysConfig.virtual == false and not physicalKey(src, data.identity)
        and not (VehicleKeysIgnition and VehicleKeysIgnition.HasInserted(data.identity)) then
        local added, message = exports.ob_inventory:AddItem(src, VehicleKeysConfig.KeyItem, 1,
            { key_id = tostring(row.id), plate = data.plate, label = 'Chave - ' .. data.plate, kind = kind })
        if not added then return false, message or 'Sem espaco para receber a chave.' end
    end
    TriggerClientEvent('ob_vehiclekeys:client:refresh', src)
    return true
end
local function grantTemporary(src, netId, isAdmin)
    src = tonumber(src)
    local character = src and uid(src)
    if not src or not validActor(src, character) then return false, 'Personagem indisponivel.' end
    -- ServerSetter pode devolver o NetID antes de o tipo/modelo ser legivel
    -- em outro recurso. Nao tratar essa janela como veiculo inexistente.
    local deadline = GetGameTimer() + 8000
    local entity = vehicleFromNet(netId)
    while (not entity or GetEntityModel(entity) == 0) and GetGameTimer() < deadline do
        Wait(50)
        if not validActor(src, character) then return false, 'Entrega de chave cancelada.' end
        entity = vehicleFromNet(netId)
    end
    if not entity or GetEntityModel(entity) == 0 then
        print(('[ob_vehiclekeys] Chave temporaria: entidade nao sincronizada sessao=%s netId=%s'):format(src, tostring(netId)))
        return false, 'O veiculo do trabalho ainda nao sincronizou. Tente novamente.'
    end
    local data = info(entity)
    if not data or not validActor(src, character) or not DoesEntityExist(entity) then
        print(('[ob_vehiclekeys] Chave temporaria: identificacao falhou sessao=%s netId=%s entidade=%s'):format(src, tostring(netId), entity))
        return false, 'Nao foi possivel identificar o veiculo do trabalho.'
    end
    if VehicleKeysConfig.virtual == false then
        local ok, message = grant(src, entity, 'temporary')
        if not ok then
            print(('[ob_vehiclekeys] Falha ao entregar chave temporaria sessao=%s netId=%s motivo=%s'):format(src, tostring(netId), tostring(message)))
            return false, message
        end
    end
    if not validActor(src, character) then return false, 'Entrega de chave cancelada.' end
    temporary[entity] = { identity = data.identity, userId = character, source = src }
    -- O responsavel original tambem pode trancar com a chave na ignicao.
    if not data.owner then data.owner = character end
    local state = Entity(entity).state
    state:set(isAdmin and 'ob:temporary_vehicle' or 'ob:job_vehicle', true, true)
    state:set('ob:temporary_key_owner', src, true)
    state:set('ob:temporary_key_user', uid(src), true)
    state:set('ob:lockpick_required', true, true)
    state:set('ob:locked', false, true)
    TriggerClientEvent('ob_vehiclekeys:client:refresh', src)
    return true
end
exports('GrantTemporaryKey', function(src, netId) return grantTemporary(src, netId, false) end)
exports('GrantTemporaryVehicleKey', function(src, netId) return grantTemporary(src, netId, true) end)
exports('RevokeTemporaryKey', function(netId)
    local entity = vehicleFromNet(netId)
    if not entity then return false end
    temporary[entity] = nil
    local data = info(entity)
    if data then
        OR.Database.query.await("DELETE FROM ob_vehicle_keys WHERE vehicle_identity=? AND key_kind='temporary'", { data.identity })
        if worldVehicles[entity] == data then data.owner = nil end
    end
    Entity(entity).state:set('ob:temporary_key_owner', nil, true)
    Entity(entity).state:set('ob:temporary_key_user', nil, true)
    return true
end)
exports('GrantOwnerKey', function(src, netId, vehicleId)
    local entity = vehicleFromNet(netId)
    if not entity then return false, 'NetID do veiculo indisponivel para entregar a chave.' end
    if tonumber(vehicleId) then
        local row = OR.Database.single.await('SELECT id,owner_user_id,model,plate FROM ob_vehicles WHERE id=? AND owner_user_id=? LIMIT 1', { tonumber(vehicleId), uid(src) or 0 })
        if not row or not sameModel(joaat(row.model), GetEntityModel(entity)) then return false, 'Cadastro do veiculo nao corresponde a chave.' end
        ownedBindings[entity] = { id = row.id, model = GetEntityModel(entity) }
    end
    local data = info(entity)
    if not data or data.owner ~= uid(src) then return false, 'Nao foi possivel confirmar a chave do proprietario.' end
    if VehicleKeysIgnition then
        local restored, restoreError = VehicleKeysIgnition.AttachStored(entity, data.identity)
        if not restored then return false, restoreError end
    end
    return grant(src, entity, 'original')
end)
exports('PrepareVehicleRemoval', function(src, netId, store)
    local entity = vehicleFromNet(netId)
    if not entity or not VehicleKeysIgnition then return false, 'Veiculo/chaves indisponiveis.' end
    return VehicleKeysIgnition.PrepareRemoval(tonumber(src), entity, store == true)
end)
OR.Callback.register('prepareAdminDelete', function(src, netId)
    local entity = vehicleFromNet(netId)
    if not entity or not near(src, entity, 150.0) or GetResourceState('ob_admin') ~= 'started'
        or not exports.ob_admin:HasPermission(src, 'vehicle.delete') then return false, 'Acao nao autorizada.' end
    return VehicleKeysIgnition.PrepareRemoval(src, entity, false)
end)
exports('GiveSpareKey', function(src, netId)
    local entity = vehicleFromNet(netId)
    if not entity then return false end
    return grant(src, entity, 'spare') -- export apenas servidor, nao existe evento publico para dar chaves.
end)
exports('HasKey', function(src, netId)
    local entity = vehicleFromNet(netId)
    return entity and authorized(src, entity) or false
end)
OR.Callback.register('access', function(src, netId)
    local character, entity = uid(src), vehicleFromNet(netId)
    if not entity or not near(src, entity, 12.0) then return false end
    local data = info(entity)
    local ok = authorized(src, entity, data)
    local ignition = VehicleKeysIgnition and VehicleKeysIgnition.Status(entity, data and data.identity) or {}
    ok = ok or ignition.inserted == true
    return ok and validActor(src, character) and near(src, entity, 12.0), ignition
end)
OR.Callback.register('toggleLock', function(src, netId)
    local character, entity = uid(src), vehicleFromNet(netId)
    if not entity or not near(src, entity, 9.0) then return false, 'Aproxime-se do veiculo.' end
    local data = info(entity)
    -- O dono controla a trava mesmo com sua chave na ignicao. Reserva exige item na mochila.
    if not data or (data.owner ~= character and not authorized(src, entity, data)) then return false, 'Voce nao possui a chave deste veiculo.' end
    if not validActor(src, character) or not near(src, entity, 9.0) then return false, 'Acao cancelada.' end
    local locked = Entity(entity).state['ob:locked'] == false
    Entity(entity).state:set('ob:locked', locked, true)
    return true, locked
end)
-- Permite ao dono emitir sua chave em modo item, inclusive para carros ja cadastrados.
OR.Callback.register('ownerKey', function(src, netId)
    local entity = vehicleFromNet(netId)
    if not entity or not near(src, entity, 5.0) then return false, 'Aproxime-se do seu veiculo.' end
    local data = info(entity)
    if not data then return false, 'Veiculo indisponivel.' end
    if data.owner == uid(src) then return grant(src, entity, 'original') end
    local key = OR.Database.single.await('SELECT id FROM ob_vehicle_keys WHERE vehicle_identity=? AND user_id=? LIMIT 1', { data.identity, uid(src) or 0 })
    if type(key) ~= 'table' then return false, 'Voce nao possui autorizacao para emitir esta chave.' end
    return grant(src, entity, 'spare')
end)
local function beginLockpick(src, itemName, slot)
    src = tonumber(src)
    if not src or not ready or not validActor(src, uid(src)) or not VehicleKeysConfig.Lockpick.Enabled then return false, 'Arrombamento indisponivel.' end
    if itemName ~= 'lockpick' and itemName ~= 'advanced_lockpick' then return false, 'Lockpick invalida.' end
    if attempts[src] then return false, 'Voce ja esta tentando arrombar um veiculo.' end
    sequence = sequence + 1
    local attempt = { token = epoch .. ':' .. sequence, userId = uid(src), itemName = itemName, slot = slot,
        expiresAt = GetGameTimer() + VehicleKeysConfig.Lockpick.DurationMs }
    attempts[src] = attempt
    SetTimeout(VehicleKeysConfig.Lockpick.DurationMs, function() if attempts[src] == attempt then attempts[src] = nil end end)
    TriggerClientEvent('ob_vehiclekeys:client:useLockpick', src, itemName, attempt.token)
    return true
end
exports('BeginLockpick', beginLockpick)
OR.Callback.register('prepareLockpick', function(src, netId, token)
    local attempt, entity = attempts[src], vehicleFromNet(netId)
    if not attempt or attempt.token ~= token or attempt.entity or not validActor(src, attempt.userId) then return false end
    if not entity or not near(src, entity, 5.0) then attempts[src] = nil; return false end
    local inventory = exports.ob_inventory:GetInventory(src)
    local item = inventory and inventory.items and (inventory.items[tonumber(attempt.slot)] or inventory.items[tostring(attempt.slot)])
    if not item or item.name ~= attempt.itemName or (tonumber(item.amount) or 0) < 1 then attempts[src] = nil; return false end
    local data = info(entity)
    if attempts[src] ~= attempt or not data or not validActor(src, attempt.userId) or not near(src, entity, 5.0) then return false end
    if VehicleKeysIgnition and VehicleKeysIgnition.Status(entity).running == true then
        attempts[src] = nil
        return false
    end
    attempt.entity, attempt.identity, attempt.startedAt = entity, data.identity, GetGameTimer()
    if GetResourceState('ob_dispatch') == 'started' then
        local coords = GetEntityCoords(entity)
        local ok, dispatchError = pcall(function()
            exports.ob_dispatch:CreateAlert('lockpick_vehicle', {
                actorSource = src,
                coords = coords,
                message = ('Possivel arrombamento de veiculo, placa %s.'):format(data.plate ~= '' and data.plate or 'nao identificada'),
                metadata = { origin = 'ob_vehiclekeys', plate = data.plate, netId = tonumber(netId) },
            })
        end)
        if not ok then print('[ob_vehiclekeys] Falha ao enviar chamado de lockpick: ' .. tostring(dispatchError)) end
    end
    return true
end)
-- Interface interna para a ignicao; nao e um evento de rede nem aceita chaves do cliente.
VehicleKeysService = { uid = uid, info = info, physicalKey = physicalKey, authorized = authorized,
    vehicle = vehicleFromNet, near = near, validActor = validActor, notify = notify }
RegisterNetEvent('ob_vehiclekeys:server:lockpickResult', function(netId, success, token)
    local src = tonumber(source)
    local attempt = attempts[src]
    if not attempt or attempt.token ~= token or attempt.finishing then return end
    if tonumber(netId) == 0 then attempts[src] = nil; return end -- cancelamento antes de iniciar.
    attempt.finishing = true
    local ok, failure = pcall(function()
        local entity = vehicleFromNet(netId)
        if entity ~= attempt.entity or not entity or not validActor(src, attempt.userId)
            or not near(src, entity, 5.0) or GetGameTimer() > attempt.expiresAt
            or not attempt.startedAt or GetGameTimer() - attempt.startedAt < 1000 then return end
        local data = info(entity)
        if not data or data.identity ~= attempt.identity then return end
        local used, remaining = exports.ob_inventory:ConsumeLockpickUse(src, attempt.itemName, attempt.slot)
        if not used then return notify(src, remaining, 'error') end
        if not validActor(src, attempt.userId) or not near(src, entity, 5.0) then return end
        local wear = remaining > 0 and (' Restam %s usos.'):format(remaining) or ' A lockpick quebrou.'
        if success ~= true then
            if math.random(100) <= VehicleKeysConfig.Lockpick.AlarmChance then
                TriggerClientEvent('ob_vehiclekeys:client:alarmTriggered', -1, netId)
                local coords = GetEntityCoords(entity)
                TriggerEvent('ob_vehiclekeys:server:vehicleAlarm', src, netId, { x = coords.x, y = coords.y, z = coords.z })
            end
            return notify(src, 'Voce falhou ao arrombar o veiculo.' .. wear, 'error')
        end
        local given, message = grant(src, entity, 'spare')
        if not given then return notify(src, message, 'error') end
        -- Nao altera owner_user_id, chaves originais nem chaves de outros jogadores.
        Entity(entity).state:set('ob:locked', false, true)
        TriggerClientEvent('ob_vehiclekeys:client:lockFeedback', src, netId)
        notify(src, (VehicleKeysConfig.virtual ~= false and 'Veiculo aberto. Acesso virtual autorizado.' or 'Veiculo aberto. Voce recebeu uma chave reserva.') .. wear, 'success')
    end)
    if attempts[src] == attempt then attempts[src] = nil end
    if not ok then print('[ob_vehiclekeys] Falha ao concluir lockpick: ' .. tostring(failure)) end
end)
AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    attempts[src] = nil
    for entity, entry in pairs(temporary) do if entry.source == src then temporary[entity] = nil end end
end)
AddEventHandler('entityRemoved', function(entity) worldVehicles[entity] = nil; temporary[entity] = nil; ownedBindings[entity] = nil end)
CreateThread(function()
    if not OR.Database.waitForReady(30000) then return print('[ob_vehiclekeys] Banco indisponivel.') end
    local result, err = OR.Database.query.await([[CREATE TABLE IF NOT EXISTS ob_vehicle_keys (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, vehicle_identity VARCHAR(96) NOT NULL,
        user_id BIGINT UNSIGNED NOT NULL, key_kind VARCHAR(16) NOT NULL,
        PRIMARY KEY (id), UNIQUE KEY idx_ob_vehicle_key (vehicle_identity,user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    if result == nil or err then return print('[ob_vehiclekeys] Nao foi possivel preparar as chaves.') end
    ready = true
    while not ownedTableReady do
        ownedTableReady = OR.Database.scalar.await("SELECT 1 FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='ob_vehicles' LIMIT 1") ~= nil
        Wait(1000)
    end
end)
