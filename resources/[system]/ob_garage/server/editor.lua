OBGarageDefinitions = {}

local records = {}
local ready = false

local function editorConfig()
    return type(GarageConfig.Editor) == 'table' and GarageConfig.Editor or {}
end

local function defaults()
    local config = editorConfig()
    return type(config.Defaults) == 'table' and config.Defaults or {}
end

local function trim(value, maximum)
    value = tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if maximum and #value > maximum then value = value:sub(1, maximum) end
    return value
end

local function finite(value, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    if minimum and value < minimum then return nil end
    if maximum and value > maximum then return nil end
    return value
end

local function clamp(value, minimum, maximum, fallback)
    value = finite(value) or tonumber(fallback) or minimum
    return math.max(minimum, math.min(maximum, value))
end

local function cleanPoint(raw, heading)
    if type(raw) ~= 'table' then return nil end
    local x, y = finite(raw.x, -10000.0, 10000.0), finite(raw.y, -10000.0, 10000.0)
    local z = finite(raw.z, -1000.0, 3000.0)
    if not x or not y or not z then return nil end
    local point = { x = x, y = y, z = z }
    if heading then point.w = clamp(raw.w or raw.heading, 0.0, 360.0, 0.0) end
    return point
end

local function cleanSize(raw, fallback)
    raw, fallback = type(raw) == 'table' and raw or {}, type(fallback) == 'table' and fallback or {}
    return {
        x = clamp(raw.x, 0.5, 50.0, fallback.x or 4.0),
        y = clamp(raw.y, 0.5, 50.0, fallback.y or 4.0),
        z = clamp(raw.z, 0.5, 20.0, fallback.z or 3.0),
    }
end

local function normalize(raw)
    raw = type(raw) == 'table' and raw or {}
    local id = trim(raw.id or raw.garageId, 48):lower()
    if id == '' or not id:match('^[a-z0-9_%-]+$') then return nil, 'Use uma chave com letras, numeros, _ ou -.' end
    local label = trim(raw.label, 80)
    if label == '' then return nil, 'Informe o nome exibido da garagem.' end
    local openPoint = cleanPoint(raw.coords or raw.openPoint, false)
    local storePoint = cleanPoint(raw.storeCoords or raw.storePoint, false)
    if not openPoint then return nil, 'Capture o ponto onde a garagem sera aberta.' end
    if not storePoint then return nil, 'Capture o ponto onde o veiculo sera guardado.' end

    local config, editorDefaults = editorConfig(), defaults()
    local maxSpawns = math.max(1, math.floor(tonumber(config.MaxSpawnPoints) or 20))
    local maxSpawnDistance = clamp(config.MaxSpawnDistance, 10.0, 5000.0, 150.0)
    local spawns = {}
    for _, point in ipairs(type(raw.spawns) == 'table' and raw.spawns or {}) do
        if #spawns >= maxSpawns then break end
        point = cleanPoint(point, true)
        if point then
            local dx, dy, dz = point.x - openPoint.x, point.y - openPoint.y, point.z - openPoint.z
            if math.sqrt(dx * dx + dy * dy + dz * dz) > maxSpawnDistance then
                return nil, ('Uma vaga esta a mais de %.0f metros do ponto de abertura.'):format(maxSpawnDistance)
            end
            spawns[#spawns + 1] = point
        end
    end
    if #spawns == 0 then return nil, 'Adicione pelo menos uma vaga de nascimento.' end

    local permission = trim(type(raw.access) == 'table' and raw.access.permission or raw.permission, 64):lower()
    if permission ~= '' and not permission:match('^[a-z0-9_%.:%-]+$') then
        return nil, 'A permissao possui caracteres invalidos.'
    end
    local vehicleType = trim(raw.vehicleType, 16):lower()
    if vehicleType ~= 'service' and vehicleType ~= 'free' then vehicleType = 'personal' end
    local sharedGroup = trim(raw.sharedGroup, 48):lower()
    if sharedGroup ~= '' and not sharedGroup:match('^[a-z0-9_%-]+$') then
        return nil, 'O grupo compartilhado deve usar apenas letras, numeros, _ ou -.'
    end
    local economyAccount = trim(raw.economyAccount, 64):lower()
    if economyAccount ~= '' and not economyAccount:match('^[a-z0-9_%.:%-]+$') then
        return nil, 'A conta economica possui caracteres invalidos.'
    end

    local maxVehicles = math.max(0, math.floor(tonumber(config.MaxCatalogVehicles) or 100))
    local vehicles, seenModels = {}, {}
    for _, entry in ipairs(type(raw.vehicles) == 'table' and raw.vehicles or {}) do
        if #vehicles >= maxVehicles then break end
        local model = trim(entry.model, 64):lower()
        if model ~= '' and model:match('^[a-z0-9_%-]+$') and not seenModels[model] then
            seenModels[model] = true
            local vehicleLabel = trim(entry.label, 96)
            vehicles[#vehicles + 1] = {
                model = model,
                label = vehicleLabel ~= '' and vehicleLabel or model:upper(),
                price = math.max(0, math.floor(tonumber(entry.price) or 0)),
                departmentPrice = math.max(0, math.floor(tonumber(entry.departmentPrice) or tonumber(entry.price) or 0)),
                taxExempt = entry.taxExempt == true,
                taxRatePercent = finite(entry.taxRatePercent, 0.0, 100.0),
            }
        end
    end

    local rawBlip = type(raw.blip) == 'table' and raw.blip or {}
    local defaultBlip = type(editorDefaults.Blip) == 'table' and editorDefaults.Blip or {}
    local blip
    if raw.blipEnabled == true or type(raw.blip) == 'table' then
        blip = {
            sprite = math.floor(clamp(rawBlip.sprite, 0, 1000, defaultBlip.sprite or 357)),
            color = math.floor(clamp(rawBlip.color, 0, 100, defaultBlip.color or 3)),
            scale = clamp(rawBlip.scale, 0.2, 3.0, defaultBlip.scale or 0.82),
            label = trim(rawBlip.label, 80) ~= '' and trim(rawBlip.label, 80) or 'Garagem',
        }
    end

    local taxRate = finite(raw.taxRatePercent, 0.0, 100.0)
    return {
        id = id,
        label = label,
        coords = openPoint,
        size = cleanSize(raw.size or raw.openSize, editorDefaults.OpenSize),
        storeCoords = storePoint,
        storeSize = cleanSize(raw.storeSize, editorDefaults.StoreSize),
        storeDistance = clamp(raw.storeDistance, 2.0, 80.0, editorDefaults.StoreDistance or 16.0),
        spawnClearRadius = clamp(raw.spawnClearRadius, 0.75, 10.0, editorDefaults.SpawnClearRadius or 1.75),
        spawns = spawns,
        access = permission ~= '' and { permission = permission, requireDuty = raw.requireDuty == true or type(raw.access) == 'table' and raw.access.requireDuty == true } or nil,
        vehicleType = vehicleType,
        sharedGroup = sharedGroup ~= '' and sharedGroup or nil,
        economyAccount = economyAccount ~= '' and economyAccount or nil,
        taxRatePercent = taxRate,
        taxExempt = raw.taxExempt == true or vehicleType == 'free',
        vehicles = vehicles,
        blipEnabled = blip ~= nil,
        blip = blip,
    }
end

local function hydrate(record)
    local place = {
        id = record.id,
        label = record.label,
        coords = vector3(record.coords.x, record.coords.y, record.coords.z),
        size = vector3(record.size.x, record.size.y, record.size.z),
        storeCoords = vector3(record.storeCoords.x, record.storeCoords.y, record.storeCoords.z),
        storeSize = vector3(record.storeSize.x, record.storeSize.y, record.storeSize.z),
        storeDistance = record.storeDistance,
        spawnClearRadius = record.spawnClearRadius,
        access = record.access,
        vehicleType = record.vehicleType,
        sharedGroup = record.sharedGroup,
        economyAccount = record.economyAccount,
        taxRatePercent = record.taxRatePercent,
        taxExempt = record.taxExempt,
        vehicles = record.vehicles,
        blip = record.blip,
        spawns = {},
    }
    for _, point in ipairs(record.spawns) do
        place.spawns[#place.spawns + 1] = vector4(point.x, point.y, point.z, point.w)
    end
    place.spawn = place.spawns[1]
    return place
end

local function publicDefinitions()
    local result = {}
    for id, record in pairs(records) do result[id] = record end
    return result
end

local function sortedDefinitions()
    local result = {}
    for _, record in pairs(records) do result[#result + 1] = record end
    table.sort(result, function(a, b) return a.label:lower() < b.label:lower() end)
    return result
end

local function reloadDefinitions()
    local rows = OR.Database.query.await('SELECT garage_id, data FROM ob_garage_definitions ORDER BY label, garage_id') or {}
    local nextRecords, nextRuntime = {}, {}
    for _, row in ipairs(rows) do
        local ok, decoded = pcall(json.decode, row.data or '')
        if ok and type(decoded) == 'table' then
            decoded.id = trim(row.garage_id, 48):lower()
            local normalized, normalizationError = normalize(decoded)
            if normalized then
                nextRecords[normalized.id] = normalized
                nextRuntime[normalized.id] = hydrate(normalized)
            else
                print(('[ob_garage] Garagem %s ignorada: %s'):format(tostring(row.garage_id), tostring(normalizationError)))
            end
        end
    end
    records, OBGarageDefinitions = nextRecords, nextRuntime
    GarageConfig.garages = OBGarageDefinitions
    return next(records) ~= nil
end

local function seedDefinitions()
    local count = tonumber(OR.Database.scalar.await('SELECT COUNT(*) FROM ob_garage_definitions')) or 0
    if count > 0 then return end
    local seeds = {
        {
            id = 'central', label = 'Garagem Central',
            coords = { x = 215.82, y = -810.12, z = 30.73 },
            storeCoords = { x = 228.72, y = -800.13, z = 30.57 },
            spawns = { { x = 219.4893, y = -808.7898, z = 30.6885, w = 250.1290 } },
            blipEnabled = true, blip = { sprite = 357, color = 3, scale = 0.82, label = 'Garagem Central' },
        },
        {
            id = 'lixeiro', label = 'Garagem do Lixeiro',
            coords = { x = -317.4060, y = -1513.8527, z = 27.5908 },
            storeCoords = { x = -317.4060, y = -1513.8527, z = 27.5908 },
            spawns = { { x = -319.0338, y = -1516.0194, z = 27.5655, w = 179.7358 } },
            blipEnabled = true, blip = { sprite = 357, color = 3, scale = 0.82, label = 'Garagem do Lixeiro' },
        },
        {
            id = 'police_service', label = 'Garagem da Policia', permission = 'police', requireDuty = true,
            coords = { x = 454.64, y = -1017.42, z = 28.43 },
            storeCoords = { x = 445.67, y = -1024.25, z = 28.64 },
            spawns = { { x = 438.42, y = -1018.30, z = 27.76, w = 90.0 } },
            vehicleType = 'service', economyAccount = 'police', taxRatePercent = 5.0,
            vehicles = {
                { model = 'police3', label = 'Police Interceptor', price = 100, departmentPrice = 25000 },
                { model = 'policeb2', label = 'Police Motorcycle', price = 100, departmentPrice = 25000 },
                { model = 'polgauntlet', label = 'Police Gauntlet', price = 100, departmentPrice = 25000 },
                { model = 'polignus', label = 'Police Ignus', price = 100, departmentPrice = 25000 },
                { model = 'polterminus', label = 'Police Terminus', price = 100, departmentPrice = 25000 },
            },
        },
        {
            id = 'free_faggio', label = 'Veiculos Gratuitos',
            coords = { x = -1031.4021, y = -2734.4150, z = 20.1693 },
            storeCoords = { x = -1031.4021, y = -2734.4150, z = 20.1693 },
            spawns = { { x = -1031.2535, y = -2730.4858, z = 20.1270, w = 237.4752 } },
            vehicleType = 'free', taxExempt = true,
            vehicles = { { model = 'faggio', label = 'Pegassi Faggio', price = 0, taxExempt = true } },
            blipEnabled = true, blip = { sprite = 357, color = 2, scale = 0.82, label = 'Veiculos Gratuitos' },
        },
    }
    for _, seed in ipairs(seeds) do
        local normalized = normalize(seed)
        if normalized then
            OR.Database.query.await([[INSERT IGNORE INTO ob_garage_definitions
                (garage_id, label, data, created_by) VALUES (?, ?, ?, 0)]], {
                normalized.id, normalized.label, json.encode(normalized)
            })
        end
    end
end

local function hasEditorPermission(source)
    local config = editorConfig()
    if config.Enabled ~= true or GetResourceState('ob_admin') ~= 'started' then return false end
    local ok, allowed = pcall(function()
        return exports.ob_admin:HasPermission(source, tostring(config.AdminPermission or 'world.garages'))
    end)
    return ok and allowed == true
end

local function syncDefinitions(target)
    TriggerClientEvent('ob_garage:client:syncGarages', target or -1, publicDefinitions())
end

CreateThread(function()
    if not OR.Database.waitForReady(30000) then return print('[ob_garage] Banco indisponivel para carregar as garagens.') end
    local created, createError = OR.Database.query.await([[CREATE TABLE IF NOT EXISTS ob_garage_definitions (
        garage_id varchar(48) NOT NULL, label varchar(80) NOT NULL, data longtext NOT NULL,
        created_by bigint unsigned NOT NULL DEFAULT 0,
        created_at timestamp NOT NULL DEFAULT current_timestamp(),
        updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
        PRIMARY KEY (garage_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    if created == nil then return print(('[ob_garage] Falha ao criar ob_garage_definitions: %s'):format(tostring(createError))) end
    seedDefinitions()
    reloadDefinitions()
    ready = true
    syncDefinitions()
    print(('[ob_garage] %d garagem(ns) carregada(s) do banco.'):format(#sortedDefinitions()))
end)

OR.Callback.register('ob_garage:server:definitions', function()
    if not ready then return false, 'As garagens ainda estao carregando.' end
    return true, publicDefinitions()
end)

OR.Callback.register('adminData', function(source)
    if not hasEditorPermission(source) then return nil, 'Sem permissao para editar garagens.' end
    if not ready then return nil, 'As garagens ainda estao carregando.' end
    return {
        garages = sortedDefinitions(),
        limits = {
            maxSpawns = math.max(1, math.floor(tonumber(editorConfig().MaxSpawnPoints) or 20)),
            maxVehicles = math.max(0, math.floor(tonumber(editorConfig().MaxCatalogVehicles) or 100)),
            protectedGarage = tostring(editorConfig().ProtectedGarage or 'central'),
        },
        defaults = defaults(),
    }
end)

OR.Callback.register('adminTeleport', function(source, id, kind, index)
    if not hasEditorPermission(source) then return nil, 'Sem permissao.' end
    local row = ready and type(id) == 'string' and records[id]
    if not row then return nil, 'Salve a garagem antes de teleportar.' end
    local point
    if kind == 'open' then point = row.coords
    elseif kind == 'store' then point = row.storeCoords
    elseif kind == 'spawn' then point = row.spawns[math.floor(tonumber(index) or 0)] end
    if not point then return nil, 'Ponto cadastrado nao encontrado.' end
    return { x = point.x, y = point.y, z = point.z, heading = point.w or 0.0 }
end, { rateLimit = { limit = 3, window = 10000 } })

OR.Callback.register('adminSaveGarage', function(source, payload)
    if not hasEditorPermission(source) then return nil, 'Sem permissao para editar garagens.' end
    if not ready then return nil, 'As garagens ainda estao carregando.' end
    if not OR.Security.rateLimit(source, 'garage:admin_save', 5, 10000) then return nil, 'Aguarde antes de salvar novamente.' end
    local normalized, normalizationError = normalize(payload)
    if not normalized then return nil, normalizationError end
    if not records[normalized.id] then
        local total = #sortedDefinitions()
        if total >= math.max(1, math.floor(tonumber(editorConfig().MaxGarages) or 100)) then
            return nil, 'O limite de garagens configurado foi atingido.'
        end
    end
    local actorUserId = tonumber(exports.ob_core:GetUserId(source)) or 0
    local changed, databaseError = OR.Database.query.await([[INSERT INTO ob_garage_definitions
        (garage_id, label, data, created_by) VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE label=VALUES(label), data=VALUES(data), updated_at=current_timestamp()]], {
        normalized.id, normalized.label, json.encode(normalized), actorUserId
    })
    if changed == nil then return nil, databaseError or 'Nao foi possivel salvar a garagem.' end
    reloadDefinitions()
    syncDefinitions()
    return records[normalized.id], ('Garagem %s salva e sincronizada.'):format(normalized.label)
end)

OR.Callback.register('adminDeleteGarage', function(source, garageId)
    if not hasEditorPermission(source) then return nil, 'Sem permissao para remover garagens.' end
    if not ready then return nil, 'As garagens ainda estao carregando.' end
    if not OR.Security.rateLimit(source, 'garage:admin_delete', 3, 15000) then return nil, 'Aguarde antes de remover novamente.' end
    garageId = trim(garageId, 48):lower()
    if garageId == tostring(editorConfig().ProtectedGarage or 'central'):lower() then
        return nil, 'A garagem principal esta protegida pela configuracao.'
    end
    if not records[garageId] then return nil, 'Garagem nao encontrada.' end
    local assigned = tonumber(OR.Database.scalar.await('SELECT COUNT(*) FROM ob_vehicles WHERE garage = ?', { garageId })) or 0
    if assigned > 0 then return nil, ('Existem %d veiculo(s) vinculados a essa garagem. Transfira-os antes de remover.'):format(assigned) end
    local changed, databaseError = OR.Database.update.await('DELETE FROM ob_garage_definitions WHERE garage_id = ?', { garageId })
    if not changed or tonumber(changed) < 1 then return nil, databaseError or 'Nao foi possivel remover a garagem.' end
    reloadDefinitions()
    syncDefinitions()
    return true, 'Garagem removida e sincronizada.'
end)

exports('GetDefinitions', publicDefinitions)
exports('GetDefinition', function(garageId) return OBGarageDefinitions[tostring(garageId or ''):lower()] end)
