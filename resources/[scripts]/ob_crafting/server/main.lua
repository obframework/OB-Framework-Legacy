local resource = GetCurrentResourceName()
local databaseReady = false
local sessions = {}

local function userId(src) return tonumber(exports.ob_core:GetUserId(src)) end
local function notify(src, message, kind) exports.ob_notification:Notify(src, message, kind or 'info') end
local function inventoryCount(src, item) return tonumber(exports.ob_inventory:GetItemCount(src, item)) or 0 end
local function levelFromXp(xp) return math.min(Crafting.maxLevel, math.floor((tonumber(xp) or 0) / Crafting.levelStep) + 1) end
local function stationNear(src, id, extra)
    local station, ped = Crafting.stations[id], GetPlayerPed(src)
    return station and station.enabled ~= false and ped ~= 0 and GetPlayerRoutingBucket(src) == 0
        and GetEntityHealth(ped) > 100 and Player(src).state['or:downed'] ~= true
        and #(GetEntityCoords(ped) - station.coords) <= (Crafting.interactDistance + (extra or 1.0))
end
local function stationAccess(src, id)
    local station = Crafting.stations[id]
    if not station or station.enabled == false then return nil, 'Bancada indisponivel.' end
    if station.mode ~= 'private' then return station end
    if GetResourceState('ob_org') ~= 'started' then return nil, 'Sistema de grupos indisponivel.' end
    local groups = type(station.groups) == 'table' and station.groups or { station.group }
    for _, group in ipairs(groups) do
        if type(group) == 'string' and group ~= '' then
            local ok, allowed = pcall(function()
                return exports.ob_org:HasPermission(src, group, station.requireDuty == true)
            end)
            if ok and allowed == true then return station end
        end
    end
    return nil, 'Esta bancada e exclusiva para o grupo autorizado.'
end
local function token() return ('%s:%s:%s'):format(os.time(), math.random(100000, 999999), math.random(100000, 999999)) end

local function profile(src)
    local uid = userId(src)
    if not databaseReady or not uid then return { xp = 0, crafts = 0, successes = 0, failures = 0 }, {} end
    OR.Database.update.await('INSERT IGNORE INTO ob_crafting_profiles (user_id) VALUES (?)', { uid })
    local row = OR.Database.single.await('SELECT xp,crafts,successes,failures FROM ob_crafting_profiles WHERE user_id=?', { uid })
        or { xp = 0, crafts = 0, successes = 0, failures = 0 }
    local blueprintRows = OR.Database.query.await('SELECT recipe_id FROM ob_crafting_blueprints WHERE user_id=?', { uid }) or {}
    local blueprints = {}
    for _, blueprint in ipairs(blueprintRows) do blueprints[blueprint.recipe_id] = true end
    return row, blueprints
end

local function refund(src, ingredients, fraction)
    for item, amount in pairs(ingredients or {}) do
        local value = math.floor(amount * fraction)
        if value > 0 then exports.ob_inventory:AddItem(src, item, value) end
    end
end

local function removeIngredients(src, ingredients)
    for item, amount in pairs(ingredients) do
        if inventoryCount(src, item) < amount then return false, ('Falta %sx %s.'):format(amount, item) end
    end
    local removed = {}
    for item, amount in pairs(ingredients) do
        local ok, err = exports.ob_inventory:RemoveItem(src, item, amount)
        if not ok then refund(src, removed, 1.0); return false, err or 'O inventario mudou durante a fabricacao.' end
        removed[item] = amount
    end
    return true
end

local function recipePayload(src, stationId)
    local station = Crafting.stations[stationId]
    local progression = station.mode ~= 'private'
    local row, blueprints = { xp = 0, crafts = 0, successes = 0, failures = 0 }, {}
    if progression then row, blueprints = profile(src) end
    local level = progression and levelFromXp(row.xp) or Crafting.maxLevel
    local recipes = {}
    for id, recipe in pairs(Crafting.recipes) do
        if recipe.enabled ~= false and recipe.station == stationId then
            local unlocked = not progression or not recipe.blueprint or blueprints[id] == true
            local ingredients, canCraft = {}, (not progression or level >= (recipe.level or 1)) and unlocked
            for item, amount in pairs(recipe.ingredients) do
                local count = inventoryCount(src, item)
                ingredients[#ingredients + 1] = { item = item, label = Crafting.itemLabels[item] or item, amount = amount, owned = count }
                if count < amount then canCraft = false end
            end
            table.sort(ingredients, function(a, b) return a.item < b.item end)
            recipes[#recipes + 1] = {
                id = id, label = recipe.label, category = recipe.category, level = recipe.level or 1,
                blueprint = progression and recipe.blueprint == true, unlocked = unlocked,
                chance = recipe.chance or 100, duration = recipe.duration, ingredients = ingredients,
                output = recipe.output, canCraft = canCraft,
            }
        end
    end
    table.sort(recipes, function(a, b) if a.level == b.level then return a.label < b.label end return a.level < b.level end)
    return {
        station = { id = stationId, label = station.label, category = Crafting.categoryLabels[station.category], mode = progression and 'public' or 'private' },
        progression = progression,
        profile = { level = level, xp = tonumber(row.xp) or 0, xpInLevel = (tonumber(row.xp) or 0) % Crafting.levelStep,
            xpRequired = Crafting.levelStep, crafts = tonumber(row.crafts) or 0, successes = tonumber(row.successes) or 0 },
        recipes = recipes, maxBatch = Crafting.maxBatch,
    }
end

OR.Callback.register('panel', function(src, stationId)
    local station, accessError = stationAccess(src, stationId)
    if not station then return nil, accessError end
    if station.mode ~= 'private' and not databaseReady then return nil, 'Banco de fabricacao indisponivel.' end
    if not stationNear(src, stationId) then return nil, 'Aproxime-se da bancada.' end
    return recipePayload(src, stationId)
end, { rateLimit = { limit = 8, window = 10000 } })

OR.Callback.register('begin', function(src, stationId, recipeId, rawAmount)
    if sessions[src] then return nil, 'Voce ja esta fabricando.' end
    local station, accessError = stationAccess(src, stationId)
    if not station then return nil, accessError end
    local recipe = Crafting.recipes[tostring(recipeId or '')]
    if not recipe or recipe.enabled == false or recipe.station ~= stationId or not stationNear(src, stationId) then return nil, 'Receita ou bancada invalida.' end
    local amount = math.max(1, math.min(Crafting.maxBatch, math.floor(tonumber(rawAmount) or 1)))
    local progression = station.mode ~= 'private'
    if progression then
        local row, blueprints = profile(src)
        if levelFromXp(row.xp) < (recipe.level or 1) then return nil, 'Seu nivel ainda e insuficiente.' end
        if recipe.blueprint and not blueprints[recipeId] then return nil, 'Voce nao possui o projeto desta receita.' end
    end
    local ingredients = {}
    for item, value in pairs(recipe.ingredients) do ingredients[item] = value * amount end
    local canCarry, carryError = exports.ob_inventory:CanCarryItem(src, recipe.output.item, recipe.output.amount * amount)
    if not canCarry then return nil, carryError or 'Sem espaco para o resultado.' end
    local removed, removeError = removeIngredients(src, ingredients)
    if not removed then return nil, removeError end
    local id = token()
    sessions[src] = { token = id, station = stationId, recipe = recipeId, amount = amount, ingredients = ingredients, progression = progression,
        started = os.time(), minimumEnd = GetGameTimer() + math.floor(recipe.duration * amount * 0.8), expires = os.time() + 300 }
    return { token = id, label = recipe.label, duration = recipe.duration * amount, steps = recipe.steps }
end, { rateLimit = { limit = 5, window = 10000 } })

OR.Callback.register('finish', function(src, suppliedToken, completed)
    local session = sessions[src]
    if not session or session.token ~= suppliedToken then return false, 'Fabricacao expirada.' end
    sessions[src] = nil
    local recipe = Crafting.recipes[session.recipe]
    local allowed = stationAccess(src, session.station) ~= nil
    if completed ~= true or not allowed or not stationNear(src, session.station, 2.0) then
        refund(src, session.ingredients, Crafting.cancelRefund)
        return false, 'Fabricacao cancelada; materiais devolvidos.'
    end
    if GetGameTimer() < session.minimumEnd then refund(src, session.ingredients, 1.0); return false, 'Tempo de fabricacao invalido.' end
    local row = session.progression and profile(src) or { xp = 0 }
    local level = session.progression and levelFromXp(row.xp) or (recipe.level or 1)
    local chance = math.min(100, (recipe.chance or 100) + math.floor((level - (recipe.level or 1)) * 0.75))
    local success = math.random(1, 100) <= chance
    local xp = session.progression and math.floor((recipe.xp or 25) * session.amount * (success and 1.0 or 0.35)) or 0
    local uid = userId(src)
    if success then
        local metadata
        if recipe.output.item:sub(1, 7) == 'weapon_' then
            metadata = { serialRemoved = true, serialStatus = 'removed', origin = 'crafted_illegal',
                quality = math.min(100, 65 + level * 2), craftedBy = uid, craftedAt = os.time() }
        end
        local added, addError = exports.ob_inventory:AddItem(src, recipe.output.item, recipe.output.amount * session.amount, metadata)
        if not added then refund(src, session.ingredients, 1.0); return false, addError or 'Sem espaco para o resultado; materiais devolvidos.' end
        if session.progression then
            OR.Database.update.await('UPDATE ob_crafting_profiles SET xp=xp+?,crafts=crafts+?,successes=successes+? WHERE user_id=?', { xp, session.amount, session.amount, uid })
            return true, ('%sx %s fabricado. +%s XP'):format(recipe.output.amount * session.amount, recipe.label, xp)
        end
        return true, ('%sx %s fabricado.'):format(recipe.output.amount * session.amount, recipe.label)
    end
    refund(src, session.ingredients, Crafting.failureRefund)
    if session.progression then
        OR.Database.update.await('UPDATE ob_crafting_profiles SET xp=xp+?,crafts=crafts+?,failures=failures+? WHERE user_id=?', { xp, session.amount, session.amount, uid })
        return false, ('O processo falhou. Parte dos materiais foi recuperada. +%s XP'):format(xp)
    end
    return false, 'O processo falhou. Parte dos materiais foi recuperada.'
end, { rateLimit = { limit = 6, window = 10000 } })

RegisterCommand('darprojeto', function(src, args)
    if src == 0 then return print('Uso: darprojeto [id] [receita]') end
    local allowed = false
    if GetResourceState('ob_admin') == 'started' then
        local ok, result = pcall(function() return exports.ob_admin:HasPermission(src, 'panel.open') end)
        allowed = ok and result == true
    end
    if not allowed then return notify(src, 'Sem permissao.', 'error') end
    local target, recipeId = tonumber(args[1]), tostring(args[2] or '')
    local recipe = Crafting.recipes[recipeId]
    if not target or not recipe or not recipe.blueprint then return notify(src, 'ID ou projeto invalido.', 'error') end
    local uid = userId(target)
    if not uid then return notify(src, 'Jogador indisponivel.', 'error') end
    OR.Database.update.await('INSERT IGNORE INTO ob_crafting_blueprints (user_id,recipe_id,granted_by) VALUES (?,?,?)', { uid, recipeId, userId(src) })
    TriggerClientEvent(resource .. ':client:blueprint', target, 'Projeto aprendido: ' .. recipe.label)
    notify(src, 'Projeto entregue.', 'success')
end, false)

CreateThread(function()
    if not OR.Database.waitForReady(30000) then return print('[ob_crafting] Banco indisponivel.') end
    local a, ae = OR.Database.query.await([[CREATE TABLE IF NOT EXISTS ob_crafting_profiles (
        user_id BIGINT UNSIGNED NOT NULL PRIMARY KEY, xp INT UNSIGNED NOT NULL DEFAULT 0,
        crafts INT UNSIGNED NOT NULL DEFAULT 0, successes INT UNSIGNED NOT NULL DEFAULT 0,
        failures INT UNSIGNED NOT NULL DEFAULT 0, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    if a == nil then return print(('[ob_crafting] Falha na tabela de perfis: %s'):format(ae or 'desconhecida')) end
    local b, be = OR.Database.query.await([[CREATE TABLE IF NOT EXISTS ob_crafting_blueprints (
        user_id BIGINT UNSIGNED NOT NULL, recipe_id VARCHAR(64) NOT NULL, granted_by BIGINT UNSIGNED NULL,
        granted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (user_id,recipe_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    databaseReady = b ~= nil
    if not databaseReady then print(('[ob_crafting] Falha na tabela de projetos: %s'):format(be or 'desconhecida')) end
end)

CreateThread(function()
    while true do
        Wait(10000)
        for src, session in pairs(sessions) do
            if os.time() > session.expires then
                if GetPlayerName(src) then refund(src, session.ingredients, 1.0) end
                sessions[src] = nil
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src, session = tonumber(source), sessions[tonumber(source)]
    if session then pcall(refund, src, session.ingredients, 1.0) end
    sessions[src] = nil
end)
AddEventHandler('onResourceStop', function(name)
    if name ~= resource then return end
    for src, session in pairs(sessions) do if GetPlayerName(src) then refund(src, session.ingredients, 1.0) end end
end)
