local records, ready = {}, false
local function textValue(value, limit)
    return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, limit or 80)
end
local function numberValue(value, low, high, fallback)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then n = fallback end
    if not n then return nil end
    return math.max(low, math.min(high, n))
end
local function point(raw, fallback)
    raw = raw or fallback
    if type(raw) ~= 'table' and type(raw) ~= 'vector3' and type(raw) ~= 'vector4' then return nil end
    local x = numberValue(raw.x, -10000, 10000)
    local y = numberValue(raw.y, -10000, 10000)
    local z = numberValue(raw.z, -1000, 3000)
    if not x or not y or not z then return nil end
    return { x = x, y = y, z = z, w = numberValue(raw.w or raw.heading, 0, 360, 0) }
end
local function baseRecord(raw)
    if type(raw) ~= 'table' then return nil, 'Dados invalidos.' end
    local id, label = textValue(raw.id, 64):lower(), textValue(raw.label, 80)
    if id == '' or not id:match('^[a-z0-9_%-]+$') then return nil, 'Informe um identificador com letras, numeros, _ ou -.' end
    if label == '' then return nil, 'Informe o nome do estabelecimento.' end
    local coords = point(raw.coords)
    if not coords then return nil, 'Capture a posicao do estabelecimento.' end
    local permission = textValue(raw.permission, 64):lower()
    if permission ~= '' and not permission:match('^[a-z0-9_%.:%-]+$') then return nil, 'Permissao invalida.' end
    local result = { id = id, label = label, coords = coords,
        permission = permission ~= '' and permission or nil, requireDuty = raw.requireDuty == true }
    if raw.blipEnabled ~= false and type(raw.blip) == 'table' then
        result.blip = { sprite = math.floor(numberValue(raw.blip.sprite, 0, 1000, 52)),
            color = math.floor(numberValue(raw.blip.color, 0, 100, 3)),
            scale = numberValue(raw.blip.scale, 0.2, 3, 0.72) }
    end
    return result
end

local settings = OBStoresConfig.Editor
local tableName, syncEvent = 'ob_store_locations', 'ob_stores:client:definitions'
local function normalize(raw)
    local row, err = baseRecord(raw)
    if not row then return nil, err end
    row.kind = textValue(raw.kind, 32)
    local ui = OBStoresConfig.Ui[row.kind]
    if not ui then return nil, 'Selecione um tipo de estabelecimento valido.' end
    row.title = textValue(raw.title, 80)
    if row.title == '' then row.title = row.label end
    row.heading = numberValue(raw.heading or row.coords.w, 0, 360, 0)
    row.radius = numberValue(raw.radius, 0.5, 10, 1.65)
    row.price = numberValue(raw.price, 0, 100000000)
    row.markerEnabled = raw.markerEnabled ~= false
    row.camOffset = point(raw.camOffset, { x=0,y=2.6,z=0.55 })
    row.lookAtOffset = point(raw.lookAtOffset, { x=0,y=0,z=0.5 })
    if not row.camOffset or not row.lookAtOffset then return nil, 'Deslocamento de camera invalido.' end
    row.categories, row.allowedSections = {}, {}
    local selected = {}
    for _, id in ipairs(type(raw.categories) == 'table' and raw.categories or {}) do selected[id] = true end
    local sections = {}
    for _, id in ipairs(type(raw.allowedSections) == 'table' and raw.allowedSections or {}) do sections[id] = true end
    for _, section in ipairs(ui.sections or {}) do
        local count = 0
        for _, category in ipairs(section.categories or {}) do
            if (raw.categories == nil or selected[category.id]) and (raw.allowedSections == nil or sections[section.id]) then
                row.categories[#row.categories+1] = category.id
                count = count + 1
            end
        end
        if count > 0 then row.allowedSections[#row.allowedSections+1] = section.id end
    end
    if #row.categories == 0 then return nil, 'Selecione pelo menos uma categoria de atendimento.' end
    row.defaultSection = row.allowedSections[1]
    for _, id in ipairs(row.allowedSections) do if id == raw.defaultSection then row.defaultSection = id end end
    return row
end
function OBStoresUiFor(location)
    local selected, allowed, result = {}, {}, { sections = {} }
    for _, id in ipairs(location.categories or {}) do selected[id] = true end
    for _, id in ipairs(location.allowedSections or {}) do allowed[id] = true end
    for _, section in ipairs((OBStoresConfig.Ui[location.kind] or {}).sections or {}) do
        if allowed[section.id] then
            local copy = { id = section.id, label = section.label, categories = {} }
            for _, category in ipairs(section.categories or {}) do
                if selected[category.id] then copy.categories[#copy.categories+1] = category end
            end
            if #copy.categories > 0 then result.sections[#result.sections+1] = copy end
        end
    end
    return result
end
function OBStoresAccess(source, location)
    if not location.permission or location.permission == '' then return true end
    if GetResourceState('ob_org') ~= 'started' then return false end
    return exports.ob_org:HasPermission(source, location.permission, location.requireDuty == true) == true
end
local function seedRecords() return OBStoreSeeds end
local function applyRecords(rows)
    OBStoresConfig.Locations = {}
    for _, original in ipairs(rows) do
        local row = json.decode(json.encode(original))
        row.coords = vector3(row.coords.x,row.coords.y,row.coords.z)
        row.camOffset = vector3(row.camOffset.x,row.camOffset.y,row.camOffset.z)
        row.lookAtOffset = vector3(row.lookAtOffset.x,row.lookAtOffset.y,row.lookAtOffset.z)
        OBStoresConfig.Locations[#OBStoresConfig.Locations+1] = row
    end
end
local function editorMeta()
    return { mode = 'stores', types = OBStoresConfig.Ui, prices = OBStoresConfig.Economy.ItemPrices }
end

local function listRecords()
    local result = {}
    for _, row in pairs(records) do result[#result + 1] = row end
    table.sort(result, function(a,b) return a.label == b.label and a.id < b.id or a.label < b.label end)
    return result
end
local function publish()
    local rows = listRecords()
    applyRecords(rows)
    TriggerLatentClientEvent(syncEvent, -1, 100000, rows)
end
local function allowed(source)
    if settings.Enabled ~= true or GetResourceState('ob_admin') ~= 'started' then return false end
    return exports.ob_admin:HasPermission(source, settings.Permission) == true
end
CreateThread(function()
    if not OR.Database.waitForReady(30000) then return print('[' .. GetCurrentResourceName() .. '] Banco indisponivel para carregar lojas.') end
    local created, err = OR.Database.query.await(('CREATE TABLE IF NOT EXISTS %s (id varchar(64) NOT NULL PRIMARY KEY, data longtext NOT NULL, deleted tinyint NOT NULL DEFAULT 0, updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'):format(tableName))
    if created == nil then return print(tostring(err)) end
    local seeded, seedError = OR.Database.scalar.await(('SELECT id FROM %s WHERE id=?'):format(tableName), { '__seed_v1' })
    if seedError then return print(tostring(seedError)) end
    if not seeded then
        for _, raw in ipairs(seedRecords()) do
            local row, normalizeError = normalize(raw)
            if not row then return print('Importacao de loja recusada: ' .. tostring(normalizeError)) end
            local inserted, insertError = OR.Database.query.await(('INSERT IGNORE INTO %s (id,data) VALUES (?,?)'):format(tableName), { row.id, json.encode(row) })
            if inserted == nil then return print(tostring(insertError)) end
        end
        local marked, markError = OR.Database.query.await(('INSERT IGNORE INTO %s (id,data,deleted) VALUES (?, ?, 1)'):format(tableName), { '__seed_v1', '{}' })
        if marked == nil then return print(tostring(markError)) end
    end
    local rows, readError = OR.Database.query.await(('SELECT id,data FROM %s WHERE deleted=0'):format(tableName))
    if not rows then return print(tostring(readError)) end
    for _, entry in ipairs(rows) do
        local ok, raw = pcall(json.decode, entry.data)
        local row, errorMessage
        if ok then row, errorMessage = normalize(raw) end
        if row then records[row.id] = row else print('Loja ignorada ' .. entry.id .. ': ' .. tostring(errorMessage)) end
    end
    ready = true
    publish()
end)
OR.Callback.register('worldShopDefinitions', function()
    if not ready then return nil, 'Os estabelecimentos ainda estao carregando.' end
    return listRecords()
end)
OR.Callback.register('worldShopEditorData', function(source)
    if not allowed(source) then return nil, 'Sem permissao para editar estes estabelecimentos.' end
    if not ready then return nil, 'Os estabelecimentos ainda estao carregando.' end
    return { records = listRecords(), meta = editorMeta() }
end)
OR.Callback.register('worldShopEditorTeleport', function(source, id)
    if not allowed(source) then return nil, 'Sem permissao.' end
    local row = ready and type(id) == 'string' and records[id]
    if not row then return nil, 'Salve o estabelecimento antes de teleportar.' end
    return { x = row.coords.x, y = row.coords.y, z = row.coords.z,
        heading = row.heading or row.coords.w or 0.0 }
end, { rateLimit = { limit = 3, window = 10000 } })

OR.Callback.register('worldShopEditorSave', function(source, raw)
    if not allowed(source) then return nil, 'Sem permissao.' end
    if not ready then return nil, 'Aguarde o carregamento.' end
    local row, err = normalize(raw)
    if not row then return nil, err end
    if not records[row.id] and #listRecords() >= (settings.MaxLocations or 200) then return nil, 'Limite de estabelecimentos atingido.' end
    local result, dbError = OR.Database.query.await(('INSERT INTO %s (id,data,deleted) VALUES (?,?,0) ON DUPLICATE KEY UPDATE data=VALUES(data),deleted=0'):format(tableName), { row.id, json.encode(row) })
    if result == nil then return nil, dbError or 'Falha ao salvar.' end
    records[row.id] = row
    publish()
    return row, 'Estabelecimento salvo e publicado.'
end, { rateLimit = { limit = 5, window = 10000 }, payload = { maxNodes = 5000, maxDepth = 10 } })
OR.Callback.register('worldShopEditorDelete', function(source, id)
    if not allowed(source) then return nil, 'Sem permissao.' end
    if not ready or type(id) ~= 'string' or not records[id] then return nil, 'Estabelecimento nao encontrado.' end
    local result, err = OR.Database.update.await(('UPDATE %s SET deleted=1 WHERE id=?'):format(tableName), { id })
    if not result or result < 1 then return nil, err or 'Falha ao remover.' end
    records[id] = nil
    publish()
    return true, 'Estabelecimento removido.'
end, { rateLimit = { limit = 3, window = 10000 } })

OR.Callback.register('storeAccess', function(source, id)
    for _, location in ipairs(OBStoresConfig.Locations) do
        if location.id == id then
            local ped = GetPlayerPed(source)
            if ped <= 0 or #(GetEntityCoords(ped)-location.coords) > location.radius + 2 then return false, 'Aproxime-se do estabelecimento.' end
            if not OBStoresAccess(source, location) then return false, 'Sem permissao ou fora de servico.' end
            return true
        end
    end
    return false, 'Estabelecimento indisponivel.'
end)
