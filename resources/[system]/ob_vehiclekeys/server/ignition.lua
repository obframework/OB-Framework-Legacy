-- A chave e transferida para um inventario persistente de ignicao, nunca destruida/recriada.
local S = VehicleKeysService
local entries, virtualEngines, busy, ready = {}, {}, {}, false
local ownerType = 'vehicle_ignition'
VehicleKeysIgnition = {}
local function driver(src, entity)
    local ped = GetPlayerPed(src)
    return S.validActor(src, S.uid(src)) and ped ~= 0 and S.near(src, entity, 5.0)
        and GetPedInVehicleSeat(entity, -1) == ped
end
local function findEntry(entity)
    for identity, entry in pairs(entries) do if entry.entity == entity then return entry, identity end end
end
local function publish(entity, running, inserted)
    if entity and DoesEntityExist(entity) then
        Entity(entity).state:set('ob:ignition', { running = running, inserted = inserted }, true)
    end
end
function VehicleKeysIgnition.Status(entity, identity)
    local entry = findEntry(entity)
    if not entry and identity and entries[identity] and entries[identity].disposition == 'inserted' then
        entry = entries[identity]
        if not entry.entity then entry.entity = entity end
        if entry.entity ~= entity then entry = nil end
    end
    if entry then return { running = entry.running == true, inserted = entry.disposition ~= 'discard', manual = true } end
    return { running = VehicleKeysConfig.virtual ~= false and virtualEngines[entity] or false,
        inserted = false, manual = virtualEngines[entity] ~= nil }
end
function VehicleKeysIgnition.HeldBy(src, identity)
    local entry = entries[identity]
    return entry ~= nil and entry.userId == S.uid(src)
end
function VehicleKeysIgnition.HasInserted(identity)
    local entry = entries[identity]
    return entry ~= nil and entry.disposition ~= 'discard'
end
function VehicleKeysIgnition.AttachStored(entity, identity)
    local entry = entries[identity]
    if entry and entry.disposition == 'parked' then
        local _, err = OR.Database.query.await("UPDATE ob_vehicle_ignitions SET disposition='inserted' WHERE vehicle_identity=?", { identity })
        if err then return false, 'Nao foi possivel recuperar a chave guardada no veiculo.' end
        entry.entity, entry.running, entry.disposition = entity, false, 'inserted'
        publish(entity, false, true)
    end
    return true
end
local function clearEntry(identity, entry)
    local _, err = OR.Database.query.await('DELETE FROM ob_vehicle_ignitions WHERE vehicle_identity=?', { identity })
    if err then return false end
    if entries[identity] == entry then entries[identity] = nil end
    return true
end
local function returnKey(src, identity, entry)
    if entry.disposition == 'parked' or entry.disposition == 'discard' then return false end
    local character = S.uid(src)
    if not character then return false, 'Personagem indisponivel.' end
    entry.running = false
    publish(entry.entity, false, false)
    local inventory = exports.ob_inventory:GetOwnedInventory(ownerType, identity, 1, 10000)
    if not inventory then return false, 'A chave esta protegida na ignicao; tente novamente.' end
    local item = inventory.items and (inventory.items['1'] or inventory.items[1])
    if not item then clearEntry(identity, entry); return true, false end
    local _, errorMessage = OR.Database.query.await("UPDATE ob_vehicle_ignitions SET user_id=?, disposition='active' WHERE vehicle_identity=?", { character, identity })
    if errorMessage then return false, 'Nao foi possivel preparar a devolucao da chave.' end
    entry.userId, entry.disposition = character, 'active'
    local moved, message = exports.ob_inventory:TransferFromOwned(src, ownerType, identity, 1, 10000, 1, 1)
    if not moved then return false, 'Motor desligado. Libere espaco na mochila para recuperar a chave: ' .. tostring(message or '') end
    clearEntry(identity, entry)
    TriggerClientEvent('ob_vehiclekeys:client:refresh', src)
    return true, false
end
local function change(src, entity, turnOn)
    if not ready then return false, 'Sistema de ignicao iniciando.' end
    local character, data = S.uid(src), S.info(entity)
    if not data or not driver(src, entity) then return false, 'Sente no banco do motorista.' end
    if VehicleKeysConfig.virtual ~= false then
        if not S.authorized(src, entity, data) then return false, 'Voce nao possui acesso a este veiculo.' end
        if not S.validActor(src, character) or not driver(src, entity) then return false, 'Acao cancelada.' end
        virtualEngines[entity] = turnOn
        publish(entity, turnOn, false)
        return true, turnOn
    end
    local identity, entry = data.identity, entries[data.identity]
    if entry then
        if entry.entity and entry.entity ~= entity then return false, 'Chave em uso em outro veiculo.' end
        entry.entity = entity
        if entry.disposition == 'discard' or entry.disposition == 'parked' then return false, 'Veiculo sendo removido ou guardado.' end
        if not turnOn then return returnKey(src, identity, entry) end
        local _, err = OR.Database.query.await("UPDATE ob_vehicle_ignitions SET disposition='active' WHERE vehicle_identity=?", { identity })
        if err then return false, 'Nao foi possivel confirmar a chave na ignicao.' end
        entry.disposition = 'active'
        entry.running = true
        publish(entity, true, true)
        return true, true
    end
    if not turnOn then return true, false end
    local hasKey, slot, metadata = S.physicalKey(src, identity)
    if not hasKey then return false, 'Voce precisa da chave na mochila para ligar o motor.' end
    if not S.validActor(src, character) or not driver(src, entity) then return false, 'Acao cancelada.' end
    entry = { entity = entity, userId = character, running = false, keyId = tostring(metadata.key_id) }
    local _, err = OR.Database.query.await('INSERT INTO ob_vehicle_ignitions (vehicle_identity,user_id,key_id) VALUES (?,?,?)', { identity, character, entry.keyId })
    if err then return false, 'Ja existe uma chave aguardando devolucao ou o banco esta indisponivel.' end
    entries[identity] = entry
    local moved, result = exports.ob_inventory:TransferToOwned(src, ownerType, identity, 1, 10000, slot, 1, 1, false,
        { name = VehicleKeysConfig.KeyItem, keyId = entry.keyId })
    if not moved then return false, tostring(result or 'Nao foi possivel inserir a chave.') end
    local received = result and result.item
    if not received or received.name ~= VehicleKeysConfig.KeyItem or tostring((received.metadata or {}).key_id) ~= entry.keyId
        or not S.validActor(src, character) or not driver(src, entity) then
        returnKey(src, identity, entry)
        return false, 'A chave foi movida ou o motorista mudou; partida cancelada.'
    end
    entry.running = true
    publish(entity, true, true)
    TriggerClientEvent('ob_vehiclekeys:client:refresh', src)
    return true, true
end
OR.Callback.register('ignition', function(src, netId, turnOn)
    local entity = S.vehicle(netId)
    if not entity or type(turnOn) ~= 'boolean' or not driver(src, entity) then return false, 'Sente no banco do motorista.' end
    if busy[entity] then return false, 'Aguarde a operacao da chave.' end
    busy[entity] = true
    local ok, result, message = pcall(change, src, entity, turnOn)
    busy[entity] = nil
    if not ok then
        print('[ob_vehiclekeys] Falha na ignicao: ' .. tostring(result))
        return false, 'Nao foi possivel alterar a ignicao. A chave continua protegida.'
    end
    return result, message
end)

local function removeCarriedKeys(src, identity, allPlayers)
    local rows = OR.Database.query.await('SELECT id FROM ob_vehicle_keys WHERE vehicle_identity=?', { identity })
    if type(rows) ~= 'table' then return false, 'Nao foi possivel consultar as chaves do veiculo.' end
    local ids = {}
    for _, row in ipairs(rows) do ids[#ids + 1] = tostring(row.id) end
    if #ids == 0 then return true end
    local players = allPlayers and GetPlayers() or { src }
    for _, player in ipairs(players) do
        player = tonumber(player)
        if player and GetPlayerName(player) then
            local ok, err = exports.ob_inventory:RemoveVehicleKeyItems(player, VehicleKeysConfig.KeyItem, ids)
            if not ok then return false, err end
        end
    end
    return true
end

local function discard(identity, entry)
    local removed, err = exports.ob_inventory:RemoveOwnedItem(ownerType, identity, 1, 10000, 1, VehicleKeysConfig.KeyItem, entry.keyId)
    if not removed then return false, err end
    local isTemporary = identity:sub(1, 6) == 'world:'
    if isTemporary then
        local ok, message = removeCarriedKeys(nil, identity, true)
        if not ok then return false, message end
        local _, keyError = OR.Database.query.await('DELETE FROM ob_vehicle_keys WHERE vehicle_identity=?', { identity })
        if keyError then return false, keyError end
    end
    return clearEntry(identity, entry)
end

function VehicleKeysIgnition.PrepareRemoval(src, entity, store)
    if not ready then return false, 'Sistema de chaves iniciando.' end
    if busy[entity] then return false, 'Aguarde a operacao da chave antes de guardar/apagar.' end
    busy[entity] = true
    local ok, result, message = pcall(function()
        local data = S.info(entity)
        if not data then return false, 'Nao foi possivel identificar as chaves.' end
        local identity, entry = data.identity, entries[data.identity]
        if not entry then
            local has, slot, metadata = S.physicalKey(src, identity)
            local holder = src
            if store and not has and data.owner then
                for _, player in ipairs(GetPlayers()) do
                    player = tonumber(player)
                    if S.uid(player) == data.owner then
                        has, slot, metadata = S.physicalKey(player, identity)
                        if has then holder = player; break end
                    end
                end
            end
            entry = { entity = entity, userId = S.uid(holder) or 0, running = false,
                keyId = has and tostring(metadata.key_id) or '0', disposition = store and 'parked' or 'discard' }
            local _, err = OR.Database.query.await('INSERT INTO ob_vehicle_ignitions (vehicle_identity,user_id,key_id,disposition) VALUES (?,?,?,?)',
                { identity, entry.userId, entry.keyId, entry.disposition })
            if err then return false, 'Nao foi possivel proteger a chave ao remover o veiculo.' end
            entries[identity] = entry
            if store and has then
                local moved, moveError = exports.ob_inventory:TransferToOwned(holder, ownerType, identity, 1, 10000, slot, 1, 1, false,
                    { name = VehicleKeysConfig.KeyItem, keyId = entry.keyId })
                if not moved then clearEntry(identity, entry); return false, moveError end
            elseif store then
                clearEntry(identity, entry)
                return true -- Nenhuma chave na mochila nem na ignicao.
            end
        else
            local disposition = store and 'parked' or 'discard'
            local _, err = OR.Database.query.await('UPDATE ob_vehicle_ignitions SET disposition=? WHERE vehicle_identity=?', { disposition, identity })
            if err then return false, 'Nao foi possivel salvar o destino da chave.' end
            entry.disposition, entry.running = disposition, false
        end
        publish(entity, false, store)
        local cleaned, cleanError = removeCarriedKeys(src, identity, not store and identity:sub(1, 6) == 'world:')
        if not cleaned then return false, cleanError end
        if store and data.owner and S.uid(src) ~= data.owner then
            for _, player in ipairs(GetPlayers()) do
                player = tonumber(player)
                if S.uid(player) == data.owner then
                    local ownerCleaned, ownerError = removeCarriedKeys(player, identity, false)
                    if not ownerCleaned then return false, ownerError end
                end
            end
        end
        if not store then return discard(identity, entry) end
        return true
    end)
    busy[entity] = nil
    if not ok then print('[ob_vehiclekeys] Falha ao finalizar chaves: ' .. tostring(result)); return false, 'Falha ao finalizar as chaves.' end
    return result, message
end

AddEventHandler('entityRemoved', function(entity)
    local entry = findEntry(entity)
    if entry then
        entry.running = false; entry.entity = nil
        if entry.disposition ~= 'parked' then
            entry.disposition = 'discard'
            CreateThread(function()
                local identity
                for id, current in pairs(entries) do if current == entry then identity = id; break end end
                if identity then OR.Database.query.await("UPDATE ob_vehicle_ignitions SET disposition='discard' WHERE vehicle_identity=?", { identity }) end
            end)
        end
    end
    virtualEngines[entity] = nil
end)
CreateThread(function()
    if not OR.Database.waitForReady(30000) then return end
    local created, err = OR.Database.query.await([[CREATE TABLE IF NOT EXISTS ob_vehicle_ignitions (
        vehicle_identity VARCHAR(96) NOT NULL PRIMARY KEY, user_id BIGINT UNSIGNED NOT NULL,
        key_id BIGINT UNSIGNED NOT NULL, disposition VARCHAR(12) NOT NULL DEFAULT 'active'
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    if created == nil or err then return print('[ob_vehiclekeys] Falha ao preparar persistencia da ignicao.') end
    local column = OR.Database.single.await("SHOW COLUMNS FROM ob_vehicle_ignitions LIKE 'disposition'")
    if not column then
        local _, migrationError = OR.Database.query.await("ALTER TABLE ob_vehicle_ignitions ADD COLUMN disposition VARCHAR(12) NOT NULL DEFAULT 'active'")
        if migrationError then return print('[ob_vehiclekeys] Falha na migracao do destino das chaves.') end
    end
    local rows = OR.Database.query.await('SELECT vehicle_identity,user_id,key_id,disposition FROM ob_vehicle_ignitions')
    if type(rows) ~= 'table' then return end
    for _, row in ipairs(rows) do
        local disposition = row.disposition or 'active'
        -- Identidades temporarias pertencem ao ciclo anterior do recurso.
        -- Nao devolver itens sem utilidade depois de um /dv ou restart antigo.
        if row.vehicle_identity:sub(1, 6) == 'world:' then disposition = 'discard' end
        if disposition == 'active' then
            local vehicleId = row.vehicle_identity:match('^owned:(%d+):')
            if vehicleId then
                local vehicle, lookupError = OR.Database.single.await('SELECT stored FROM ob_vehicles WHERE id=? LIMIT 1', { tonumber(vehicleId) })
                if lookupError then return print('[ob_vehiclekeys] Nao foi possivel verificar as chaves guardadas; recuperacao suspensa.') end
                if vehicle and tonumber(vehicle.stored) == 1 then disposition = 'parked' end
            end
        end
        if disposition ~= (row.disposition or 'active') then
            local _, saveError = OR.Database.query.await('UPDATE ob_vehicle_ignitions SET disposition=? WHERE vehicle_identity=?', { disposition, row.vehicle_identity })
            if saveError then return print('[ob_vehiclekeys] Nao foi possivel migrar o destino de uma chave.') end
        end
        entries[row.vehicle_identity] = { userId = tonumber(row.user_id), keyId = tostring(row.key_id), running = false, disposition = disposition }
    end
    ready = true
    while true do
        Wait(3000)
        local online = {}
        for _, src in ipairs(GetPlayers()) do
            src = tonumber(src)
            local character = S.uid(src)
            if character then online[character] = src end
        end
        for identity, entry in pairs(entries) do
            if entry.entity and not DoesEntityExist(entry.entity) then
                entry.entity = nil; entry.running = false
                if entry.disposition ~= 'parked' then entry.disposition = 'discard' end
            end
            -- Guardada/inserida nao e devolucao pendente. Descarte nunca gera recebimento.
            if entry.disposition == 'discard' and not busy[entry.entity or identity] then
                local lock = entry.entity or identity
                busy[lock] = true
                OR.Database.query.await("UPDATE ob_vehicle_ignitions SET disposition='discard' WHERE vehicle_identity=?", { identity })
                pcall(discard, identity, entry)
                busy[lock] = nil
            elseif (entry.disposition == nil or entry.disposition == 'active') and not entry.running and not busy[entry.entity or identity] and online[entry.userId] then
                local lock = entry.entity or identity
                busy[lock] = true
                local ok, returned = pcall(returnKey, online[entry.userId], identity, entry)
                busy[lock] = nil
                if ok and returned then S.notify(online[entry.userId], 'Chave devolvida a mochila.', 'success') end
            end
        end
    end
end)
