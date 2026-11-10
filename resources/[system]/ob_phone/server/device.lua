-- Identidade fisica, seguranca e cobertura do aparelho.
-- Os dados continuam ligados ao personagem que ativou o telefone; o item leva
-- apenas deviceId, portanto uma transferencia preserva mensagens e galeria.
OBPhoneDevice = OBPhoneDevice or {}

local sessions, attempts, towers, jammers, devices = {}, {}, {}, {}, {}
local schemaReady = false

local function holderId(source)
    return exports.ob_core:GetUserId(source)
end

local function now()
    return os.time()
end

local function cleanExpired(collection)
    local timestamp = now()
    for id, entry in pairs(collection) do
        if entry.expiresAt <= timestamp then collection[id] = nil end
    end
end

local function inventoryPhone(source, requestedSlot)
    local slot = math.floor(tonumber(requestedSlot) or 0)
    if slot > 0 then
        local exportOk, item = pcall(function() return exports.ob_inventory:GetItemAtSlot(source, slot) end)
        if exportOk and item and item.name == 'phone' then return item, slot end
    end
    local inventory = exports.ob_inventory:GetInventory(source)
    for key, item in pairs(inventory and inventory.items or {}) do
        if item.name == 'phone' then return item, tonumber(item.slot) or tonumber(key) end
    end
end

local function updatePhoneMetadata(source, slot, metadata)
    local exportOk, updated, updateError = pcall(function()
        return exports.ob_inventory:UpdateItemMetadataAtSlot(source, slot, 'phone', metadata)
    end)
    if exportOk and updated then return true end
    -- Compatibilidade durante rolling restart: a export antiga encontra o
    -- unico telefone do jogador e ainda preserva o deviceId corretamente.
    local fallbackOk, fallbackResult, fallbackError = pcall(function()
        return exports.ob_inventory:UpdateItemMetadata(source, 'phone', metadata, {})
    end)
    if fallbackOk and fallbackResult then return true end
    return false, fallbackError or updateError or 'Nao foi possivel identificar o aparelho.'
end

local function createDeviceId(owner)
    return ('ob-%s-%x-%06x'):format(owner, now(), math.random(0, 0xffffff))
end

local function deviceRow(deviceId)
    if not schemaReady or not deviceId then return nil end
    if devices[deviceId] then return devices[deviceId] end
    local row = OR.Database.single.await([[SELECT device_id,owner_user_id,active,pin_hash,face_enabled
        FROM ob_phone_devices WHERE device_id=? LIMIT 1]], { deviceId })
    if row then devices[deviceId] = row end
    return row
end

local function sessionHasItem(source, session)
    if not session then return false end
    local item = inventoryPhone(source, session.slot)
    return item and type(item.metadata) == 'table' and tostring(item.metadata.deviceId or '') == session.deviceId
end

local function distanceToSegment(px, py, ax, ay, bx, by)
    local vx, vy, wx, wy = bx - ax, by - ay, px - ax, py - ay
    local length = vx * vx + vy * vy
    local t = length > 0 and math.max(0, math.min(1, (wx * vx + wy * vy) / length)) or 0
    local dx, dy = px - (ax + t * vx), py - (ay + t * vy)
    return math.sqrt(dx * dx + dy * dy)
end

local function insidePolygon(x, y, points)
    local inside, previous = false, #points
    for current = 1, #points do
        local a, b = points[current], points[previous]
        if ((a.y > y) ~= (b.y > y)) and x < (b.x - a.x) * (y - a.y) / ((b.y - a.y) + 0.0) + a.x then
            inside = not inside
        end
        previous = current
    end
    return inside
end

local function signalAt(coords)
    local config = OBPhoneConfig.Signal or {}
    if config.Enabled ~= true then return 4 end
    cleanExpired(towers); cleanExpired(jammers)
    for _, jammer in pairs(jammers) do
        if #(coords - jammer.coords) <= (tonumber(config.JammerRadius) or 2000.0) then return 0 end
    end
    local points = type(config.Area) == 'table' and config.Area or {}
    if #points >= 3 and insidePolygon(coords.x, coords.y, points) then
        local edge = math.huge
        for index, point in ipairs(points) do
            local nextPoint = points[index % #points + 1]
            edge = math.min(edge, distanceToSegment(coords.x, coords.y, point.x, point.y, nextPoint.x, nextPoint.y))
        end
        local fade = math.max(1.0, tonumber(config.EdgeFadeDistance) or 500.0)
        return math.max(1, math.min(4, 1 + math.floor((edge / fade) * 3)))
    end
    for _, tower in pairs(towers) do
        local radius = tonumber(config.TowerRadius) or 200.0
        local distance = #(coords - tower.coords)
        if distance <= radius then return math.max(1, math.min(4, math.ceil((1 - distance / radius) * 4))) end
    end
    return 0
end

function OBPhoneDevice.Signal(source)
    local ped = GetPlayerPed(source)
    return ped and ped > 0 and signalAt(GetEntityCoords(ped)) or 0
end

function OBPhoneDevice.HasSignal(source)
    return OBPhoneDevice.Signal(source) > 0
end

local function publicState(source, session, row)
    local holder = holderId(source)
    local key = session and (session.deviceId .. ':' .. tostring(holder))
    local failed = key and attempts[key]
    local remaining = failed and math.max(0, failed.lockUntil - now()) or 0
    local hasPin = row and type(row.pin_hash) == 'string' and row.pin_hash ~= ''
    return {
        valid = row and tonumber(row.active) == 1 and sessionHasItem(source, session) or false,
        deviceId = session and session.deviceId or nil,
        owner = row and tonumber(row.owner_user_id) == tonumber(holder) or false,
        authorized = session and session.authorized == true or false,
        setupRequired = row and not hasPin or false,
        faceEnabled = row and tonumber(row.face_enabled) == 1 or false,
        lockedSeconds = remaining,
        signal = OBPhoneDevice.Signal(source),
    }
end

local function activateNewDevice(source, holder, item, phoneSlot)
    local metadata = type(item.metadata) == 'table' and item.metadata or {}
    local deviceId = createDeviceId(holder)
    local previousDevice = OR.Database.scalar.await('SELECT device_id FROM ob_phone_devices WHERE owner_user_id=? AND active=1 ORDER BY updated_at DESC LIMIT 1', { holder })
    OR.Database.update.await('UPDATE ob_phone_devices SET active=0 WHERE owner_user_id=? AND active=1', { holder })
    for _, cached in pairs(devices) do
        if tonumber(cached.owner_user_id) == tonumber(holder) then cached.active = 0 end
    end
    local inserted, insertError = OR.Database.update.await([[INSERT INTO ob_phone_devices
        (device_id,owner_user_id,active) VALUES (?,?,1)]], { deviceId, holder })
    if inserted == nil then
        if previousDevice then
            OR.Database.update.await('UPDATE ob_phone_devices SET active=1 WHERE device_id=?', { previousDevice })
            if devices[previousDevice] then devices[previousDevice].active = 1 end
        end
        return nil, insertError or 'Nao foi possivel ativar o aparelho.'
    end
    metadata.deviceId = deviceId
    local updated, updateError = updatePhoneMetadata(source, phoneSlot, metadata)
    if not updated then
        OR.Database.update.await('UPDATE ob_phone_devices SET active=0 WHERE device_id=?', { deviceId })
        if previousDevice then
            OR.Database.update.await('UPDATE ob_phone_devices SET active=1 WHERE device_id=?', { previousDevice })
            if devices[previousDevice] then devices[previousDevice].active = 1 end
        end
        return nil, updateError
    end
    devices[deviceId] = {device_id=deviceId,owner_user_id=holder,active=1,pin_hash=nil,face_enabled=0}
    return devices[deviceId], deviceId
end

function OBPhoneDevice.Bind(source, slot)
    local holder = holderId(source)
    if not holder or not schemaReady then return false, 'Celular ainda esta iniciando.' end
    local item, phoneSlot = inventoryPhone(source, slot)
    if not item then return false, 'Voce precisa de um celular na mochila.' end
    local metadata = type(item.metadata) == 'table' and item.metadata or {}
    local deviceId = tostring(metadata.deviceId or '')
    local row = deviceId ~= '' and deviceRow(deviceId) or nil
    if deviceId == '' or not row then
        local activationError
        row, deviceId = activateNewDevice(source, holder, item, phoneSlot)
        if not row then return false, deviceId or activationError end
    end
    local hasPin = row.pin_hash and row.pin_hash ~= ''
    local faceUnlock = hasPin and tonumber(row.face_enabled) == 1 and tonumber(row.owner_user_id) == tonumber(holder)
    sessions[source] = {
        deviceId = deviceId, dataUserId = tonumber(row.owner_user_id), slot = phoneSlot,
        authorized = faceUnlock == true,
    }
    return true, publicState(source, sessions[source], row)
end


exports('ActivateNewPhone', function(source, slot)
    local holder = holderId(source)
    if not holder or not schemaReady then return false, 'Sistema de aparelhos ainda esta iniciando.' end
    local item, phoneSlot = inventoryPhone(source, slot)
    if not item then return false, 'Celular nao encontrado.' end
    if type(item.metadata) == 'table' and tostring(item.metadata.deviceId or '') ~= '' then return true end
    local row, result = activateNewDevice(source, holder, item, phoneSlot)
    return row ~= nil, row and nil or result
end)

function OBPhoneDevice.UserId(source)
    local session = sessions[tonumber(source)]
    if not session or not session.authorized or not sessionHasItem(source, session) or not OBPhoneDevice.HasSignal(source) then return nil end
    local row = deviceRow(session.deviceId)
    if not row or tonumber(row.active) ~= 1 then return nil end
    return tonumber(row.owner_user_id)
end

function OBPhoneDevice.HolderId(source)
    return holderId(source)
end

function OBPhoneDevice.ResolveOwner(source)
    local item = inventoryPhone(source)
    local deviceId = item and type(item.metadata) == 'table' and item.metadata.deviceId
    local row = deviceRow(deviceId)
    if not row or tonumber(row.active) ~= 1 then return nil end
    return tonumber(row.owner_user_id)
end

function OBPhoneDevice.DeviceUserId(source)
    if not OBPhoneDevice.HasSignal(source) then return nil end
    return OBPhoneDevice.ResolveOwner(source)
end

function OBPhoneDevice.SourceForUser(userId)
    userId = tonumber(userId)
    for source, session in pairs(sessions) do
        if session.authorized and tonumber(session.dataUserId) == userId and GetPlayerName(source) and sessionHasItem(source, session) and OBPhoneDevice.HasSignal(source) then
            local row = deviceRow(session.deviceId)
            if row and tonumber(row.active) == 1 then return source end
        end
    end
    for _, value in ipairs(GetPlayers()) do
        local source = tonumber(value)
        if source and OBPhoneDevice.DeviceUserId(source) == userId then return source end
    end
end

function OBPhoneDevice.HolderSourceForUser(userId)
    userId = tonumber(userId)
    for _, value in ipairs(GetPlayers()) do
        local source = tonumber(value)
        if source and OBPhoneDevice.ResolveOwner(source) == userId then return source end
    end
end

local function validPin(value)
    value = tostring(value or '')
    return value:match('^%d%d%d%d%d?%d?$') and value or nil
end

OR.Callback.register('deviceOpen', function(source, slot)
    return OBPhoneDevice.Bind(source, slot)
end)

OR.Callback.register('deviceSignal', function(source)
    local session = sessions[source]
    local row = session and deviceRow(session.deviceId)
    return true, publicState(source, session, row)
end)

OR.Callback.register('deviceAuth', function(source, action, payload)
    payload = type(payload) == 'table' and payload or {}
    action = tostring(action or '')
    local session, holder = sessions[source], holderId(source)
    if not session or not holder or not sessionHasItem(source, session) then return false, 'Abra o celular novamente.' end
    local row = deviceRow(session.deviceId)
    if not row or tonumber(row.active) ~= 1 then return false, 'Este aparelho foi desativado.' end
    local key = session.deviceId .. ':' .. tostring(holder)
    local failure = attempts[key]
    if failure and failure.lockUntil > now() then
        return false, ('Aguarde %d segundos.'):format(failure.lockUntil - now()), publicState(source, session, row)
    end
    if action == 'setup' then
        local pin, confirmation = validPin(payload.pin), validPin(payload.confirmation)
        if tonumber(row.owner_user_id) ~= tonumber(holder) or row.pin_hash then return false, 'Configuracao inicial indisponivel.' end
        if not pin or pin ~= confirmation then return false, 'Confirme a mesma senha de 4 a 6 digitos.' end
        local saved = OR.Database.update.await('UPDATE ob_phone_devices SET pin_hash=SHA2(?,256) WHERE device_id=? AND pin_hash IS NULL', { pin, session.deviceId })
        if not saved or saved < 1 then return false, 'Nao foi possivel criar a senha.' end
        session.authorized = true; attempts[key] = nil
        row.pin_hash = 'set'
        return true, publicState(source, session, row)
    elseif action == 'unlock' then
        local pin = validPin(payload.pin)
        local valid = pin and OR.Database.scalar.await('SELECT 1 FROM ob_phone_devices WHERE device_id=? AND pin_hash=SHA2(?,256) AND active=1', { session.deviceId, pin })
        if valid then session.authorized = true; attempts[key] = nil return true, publicState(source, session, row) end
        failure = failure or { count = 0, lockUntil = 0 }; failure.count = failure.count + 1
        local maximumAttempts = tonumber((OBPhoneConfig.Security or {}).AttemptsBeforeLock) or 3
        if failure.count >= maximumAttempts then failure.count, failure.lockUntil = 0, now() + (tonumber((OBPhoneConfig.Security or {}).LockSeconds) or 60) end
        attempts[key] = failure
        local message = failure.lockUntil > now() and 'Muitas tentativas. Aguarde 1 minuto.' or 'Senha incorreta.'
        return false, message, publicState(source, session, row)
    elseif action == 'changePin' then
        if not session.authorized then return false, 'Desbloqueie o celular.' end
        local pin, confirmation = validPin(payload.pin), validPin(payload.confirmation)
        if not pin or pin ~= confirmation then return false, 'Confirme a mesma senha de 4 a 6 digitos.' end
        OR.Database.update.await('UPDATE ob_phone_devices SET pin_hash=SHA2(?,256) WHERE device_id=?', { pin, session.deviceId })
        row.pin_hash = 'set'
        return true, 'Senha alterada.'
    elseif action == 'face' then
        if not session.authorized or tonumber(row.owner_user_id) ~= tonumber(holder) then return false, 'Somente o dono pode configurar o reconhecimento facial.' end
        OR.Database.update.await('UPDATE ob_phone_devices SET face_enabled=? WHERE device_id=?', { payload.enabled == true and 1 or 0, session.deviceId })
        row.face_enabled = payload.enabled == true and 1 or 0
        return true, payload.enabled == true and 'Reconhecimento facial ativado.' or 'Reconhecimento facial desativado.'
    elseif action == 'changeNumber' then
        if not session.authorized then return false, 'Desbloqueie o celular.' end
        local number = tostring(payload.number or ''):gsub('%D', '')
        local simSlot = math.floor(tonumber(payload.slot) or 0)
        if #number < 5 or #number > 16 then return false, 'Digite um numero entre 5 e 16 digitos.' end
        local sim = exports.ob_inventory:GetItemAtSlot(source, simSlot)
        if not sim or sim.name ~= 'sim_chip' then return false, 'O chip foi movido ou nao esta mais na mochila.' end
        if OR.Database.scalar.await('SELECT 1 FROM ob_phone_numbers WHERE phone_number=? AND user_id<>? LIMIT 1', { number, row.owner_user_id }) then
            return false, 'Esse numero ja esta em uso. Escolha outro.'
        end
        local changed, changeError = OR.Database.update.await('UPDATE ob_phone_numbers SET phone_number=? WHERE user_id=?', { number, row.owner_user_id })
        if changed == nil then return false, changeError or 'Nao foi possivel trocar o numero.' end
        local consumed, consumeError = exports.ob_inventory:ConsumeItemAtSlot(source, simSlot, 'sim_chip', 1)
        if not consumed then return false, consumeError end
        return true, 'Numero alterado para ' .. number .. '.'
    end
    return false, 'Acao de seguranca invalida.'
end)

exports('UseSignalItem', function(source, itemName, slot)
    local item = exports.ob_inventory:GetItemAtSlot(source, slot)
    if not item or item.name ~= itemName then return false, 'O dispositivo foi movido.' end
    local ped = GetPlayerPed(source)
    if not ped or ped <= 0 then return false, 'Nao foi possivel obter sua localizacao.' end
    local collection, label
    if itemName == 'mini_cell_tower' then collection, label = towers, 'Mini torre ativada por 30 minutos.'
    elseif itemName == 'signal_jammer' then collection, label = jammers, 'Bloqueador ativado por 30 minutos.'
    else return false, 'Dispositivo de sinal invalido.' end
    local duration = tonumber((OBPhoneConfig.Signal or {}).DeviceDurationSeconds) or 1800
    collection[('%s:%s:%s'):format(source, now(), math.random(1000, 9999))] = { coords = GetEntityCoords(ped), expiresAt = now() + duration }
    return true, label
end)

local function activateLegacyPhone(source)
    source = tonumber(source)
    if not source or not GetPlayerName(source) or not schemaReady then return end
    local item, slot = inventoryPhone(source)
    if not item or type(item.metadata) == 'table' and tostring(item.metadata.deviceId or '') ~= '' then return end
    local holder = holderId(source)
    if holder then activateNewDevice(source, holder, item, slot) end
end

AddEventHandler('ob_core:server:playerLoaded', function(source)
    CreateThread(function()
        Wait(750)
        activateLegacyPhone(source)
    end)
end)

AddEventHandler('playerDropped', function() sessions[tonumber(source)] = nil end)
AddEventHandler('ob_core:server:characterSelected', function(source) sessions[tonumber(source)] = nil end)

CreateThread(function()
    if not OR.Database.waitForReady(30000) then return end
    local result = OR.Database.query.await([[CREATE TABLE IF NOT EXISTS ob_phone_devices (
        device_id varchar(48) NOT NULL PRIMARY KEY,
        owner_user_id int NOT NULL,
        active tinyint(1) NOT NULL DEFAULT 1,
        pin_hash char(64) DEFAULT NULL,
        face_enabled tinyint(1) NOT NULL DEFAULT 0,
        created_at timestamp NOT NULL DEFAULT current_timestamp(),
        updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
        INDEX idx_phone_device_owner (owner_user_id,active)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    schemaReady = result ~= nil
    if schemaReady then
        for _, value in ipairs(GetPlayers()) do
            local source = tonumber(value)
            CreateThread(function()
                Wait(750)
                activateLegacyPhone(source)
            end)
        end
    end
end)
