local resource = GetCurrentResourceName()
local databaseReady = false
local actionLocks = {}

local function userId(src) return tonumber(exports.ob_core:GetUserId(src)) end
local function itemCount(src, item) return tonumber(exports.ob_inventory:GetItemCount(src, item)) or 0 end
local function clamp(value, minimum, maximum) return math.max(minimum, math.min(maximum, value)) end
local function now() return os.time() end
local function copyMetadata(metadata)
    local ok, encoded = pcall(json.encode, type(metadata) == 'table' and metadata or {})
    if not ok then return {} end
    local decodedOk, decoded = pcall(json.decode, encoded)
    return decodedOk and type(decoded) == 'table' and decoded or {}
end

local function itemUses(metadata, maximum)
    return math.max(0, math.min(maximum, math.floor(tonumber(metadata and metadata.usesRemaining) or maximum)))
end

local function potMetadata(plant)
    local remaining = itemUses({ usesRemaining = plant.pot_uses_remaining }, DrugPlants.uses.pot)
    return remaining > 0 and { usesRemaining = remaining } or nil, remaining
end

local function consumeUseAtSlot(src, slot, itemName, maximum)
    slot = math.floor(tonumber(slot) or 0)
    local item, itemError = exports.ob_inventory:GetItemAtSlot(src, slot)
    if not item or item.name ~= itemName or (tonumber(item.amount) or 0) < 1 then
        return false, itemError or 'O item foi movido ou não está mais nesse slot.'
    end
    local previousMetadata = copyMetadata(item.metadata)
    local remaining = itemUses(previousMetadata, maximum) - 1
    local changed, changeError
    if remaining <= 0 then
        changed, changeError = exports.ob_inventory:ConsumeItemAtSlot(src, slot, itemName, 1)
    else
        local metadata = copyMetadata(previousMetadata)
        metadata.usesRemaining = remaining
        changed, changeError = exports.ob_inventory:UpdateItemMetadataAtSlot(src, slot, itemName, metadata)
    end
    if not changed then return false, changeError end
    return true, remaining, previousMetadata, slot
end

local function restoreConsumedUse(src, slot, itemName, remaining, previousMetadata)
    if remaining <= 0 then
        exports.ob_inventory:AddItem(src, itemName, 1, previousMetadata, slot)
    else
        exports.ob_inventory:UpdateItemMetadataAtSlot(src, slot, itemName, previousMetadata)
    end
end

local function growthMinutes(plant, settings)
    if (tonumber(plant.nutrients) or 0) >= DrugPlants.care.fertilizedNutrientsMin then
        return tonumber(settings.fertilizedGrowMinutes) or tonumber(settings.growMinutes) or 5
    end
    return tonumber(settings.growMinutes) or 5
end

local function remainingText(plant, settings)
    local care = DrugPlants.care
    local water, nutrients, health = tonumber(plant.water) or 0, tonumber(plant.nutrients) or 0, tonumber(plant.health) or 0
    if health <= 0 then return 'planta morta' end
    if water < care.healthyWaterMin then return 'pausado: precisa de água' end
    if water > care.healthyWaterMax then return 'pausado: excesso de água' end
    if nutrients < care.healthyNutrientsMin then return 'pausado: precisa de nutrientes' end
    local healthFactor = 0.45 + (health / 100) * 0.55
    local seconds = math.max(0, math.ceil(((100 - (tonumber(plant.growth) or 0)) / 100) * growthMinutes(plant, settings) * 60 / healthFactor))
    if seconds <= 0 then return 'pronta para colher' end
    local minutes = math.floor(seconds / 60)
    local remainder = seconds % 60
    if minutes > 0 then return ('%dm %02ds'):format(minutes, remainder) end
    return ('%ds'):format(remainder)
end

local function playerCanAct(src)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and GetPlayerRoutingBucket(src) == 0 and GetEntityHealth(ped) > 100
        and Player(src).state['or:downed'] ~= true
end

local function nearPlant(src, plant)
    return playerCanAct(src) and #(GetEntityCoords(GetPlayerPed(src)) - vector3(tonumber(plant.x), tonumber(plant.y), tonumber(plant.z)))
        <= (DrugPlants.interactDistance + 1.0)
end

local function advancePlant(plant, timestamp)
    if not plant.kind then plant.last_update = timestamp return plant end
    local settings = DrugPlants.types[plant.kind]
    if not settings then return plant end
    local elapsedHours = math.max(0, timestamp - (tonumber(plant.last_update) or timestamp)) / 3600.0
    if elapsedHours <= 0 then return plant end
    local care = DrugPlants.care
    local oldWater, oldNutrients = tonumber(plant.water) or 0, tonumber(plant.nutrients) or 0
    local health, growth = tonumber(plant.health) or 0, tonumber(plant.growth) or 0
    if oldWater <= 5 then health = health - care.dryDamagePerHour * elapsedHours end
    if oldWater >= 96 then health = health - care.floodedDamagePerHour * elapsedHours end
    if oldNutrients <= 3 then health = health - care.starvedDamagePerHour * elapsedHours end
    local water = clamp(oldWater - care.waterDecayPerHour * elapsedHours, 0, 100)
    local nutrients = clamp(oldNutrients - care.nutrientDecayPerHour * elapsedHours, 0, 100)
    health = clamp(health, 0, 100)
    if health > 0 and water >= care.healthyWaterMin and water <= care.healthyWaterMax and nutrients >= care.healthyNutrientsMin then
        local healthFactor = 0.45 + (health / 100) * 0.55
        growth = clamp(growth + (elapsedHours * 60 / growthMinutes(plant, settings)) * 100 * healthFactor, 0, 100)
    end
    plant.water, plant.nutrients, plant.health, plant.growth, plant.last_update = water, nutrients, health, growth, timestamp
    return plant
end

local function fetchPlants(updateDatabase)
    if not databaseReady then return {} end
    local rows = OR.Database.query.await([[SELECT id,owner_user_id,plant_type AS kind,x,y,z,heading,growth,water,nutrients,health,last_update,pot_uses_remaining
        FROM ob_drug_plants ORDER BY id ASC]]) or {}
    local timestamp = now()
    for _, plant in ipairs(rows) do
        advancePlant(plant, timestamp)
        if updateDatabase and plant.kind then
            OR.Database.update.await([[UPDATE ob_drug_plants SET growth=?,water=?,nutrients=?,health=?,last_update=? WHERE id=?]],
                { plant.growth, plant.water, plant.nutrients, plant.health, plant.last_update, plant.id })
        end
    end
    return rows
end

local function syncAll(updateDatabase)
    TriggerClientEvent(resource .. ':client:sync', -1, fetchPlants(updateDatabase == true))
end

local function getPlant(id)
    if not databaseReady then return nil end
    local plant = OR.Database.single.await([[SELECT id,owner_user_id,plant_type AS kind,x,y,z,heading,growth,water,nutrients,health,last_update,pot_uses_remaining
        FROM ob_drug_plants WHERE id=?]], { math.floor(tonumber(id) or 0) })
    if plant then advancePlant(plant, now()) end
    return plant
end

local function ownsPlant(src, plant)
    return not DrugPlants.ownerOnly or tonumber(plant.owner_user_id) == userId(src)
end

local function removeInventoryItem(src, item, amount)
    if itemCount(src, item) < amount then return false, 'O item necessário não está mais no inventário.' end
    return exports.ob_inventory:RemoveItem(src, item, amount)
end

OR.Callback.register('list', function()
    return fetchPlants(false)
end, { rateLimit = { limit = 4, window = 10000 } })

OR.Callback.register('place', function(src, data)
    if actionLocks[src] then return false, 'Aguarde a ação anterior terminar.' end
    actionLocks[src] = true
    local function finish(ok, message) actionLocks[src] = nil return ok, message end
    if not databaseReady then return finish(false, 'Banco de cultivo indisponível.') end
    if not playerCanAct(src) or type(data) ~= 'table' then return finish(false, 'Posição inválida.') end
    local coords = vector3(tonumber(data.x) or 0, tonumber(data.y) or 0, tonumber(data.z) or 0)
    if #(GetEntityCoords(GetPlayerPed(src)) - coords) > 4.0 then return finish(false, 'Posicione o vaso mais perto de você.') end
    local uid = userId(src)
    if not uid then return finish(false, 'Personagem indisponível.') end
    local total = OR.Database.single.await('SELECT COUNT(*) AS total FROM ob_drug_plants') or {}
    local owned = OR.Database.single.await('SELECT COUNT(*) AS total FROM ob_drug_plants WHERE owner_user_id=?', { uid }) or {}
    if (tonumber(total.total) or 0) >= DrugPlants.maxPlantsGlobal then return finish(false, 'O limite global de cultivos foi atingido.') end
    if (tonumber(owned.total) or 0) >= DrugPlants.maxPlantsPerPlayer then return finish(false, 'Você atingiu seu limite de vasos.') end
    local close = OR.Database.single.await([[SELECT id FROM ob_drug_plants
        WHERE SQRT(POW(x-?,2)+POW(y-?,2)+POW(z-?,2)) < ? LIMIT 1]], { coords.x, coords.y, coords.z, DrugPlants.minimumSpacing })
    if close then return finish(false, 'Já existe um vaso perto demais deste ponto.') end
    local slot = math.floor(tonumber(data.slot) or 0)
    local potItem, potError = exports.ob_inventory:GetItemAtSlot(src, slot)
    if not potItem or potItem.name ~= DrugPlants.items.pot or (tonumber(potItem.amount) or 0) < 1 then
        return finish(false, potError or 'O vaso foi movido ou não está mais nesse slot.')
    end
    local potItemMetadata = copyMetadata(potItem.metadata)
    local usesRemaining = itemUses(potItemMetadata, DrugPlants.uses.pot)
    local removed, removeError = exports.ob_inventory:ConsumeItemAtSlot(src, slot, DrugPlants.items.pot, 1)
    if not removed then return finish(false, removeError) end
    local id, insertError = OR.Database.insert.await([[INSERT INTO ob_drug_plants
        (owner_user_id,plant_type,x,y,z,heading,growth,water,nutrients,health,last_update,pot_uses_remaining)
        VALUES (?,NULL,?,?,?,?,0,0,0,100,?,?)]], { uid, coords.x, coords.y, coords.z, tonumber(data.heading) or 0, now(), usesRemaining })
    if not id then
        exports.ob_inventory:AddItem(src, DrugPlants.items.pot, 1, potItemMetadata, slot)
        return finish(false, insertError or 'Não foi possível salvar o vaso.')
    end
    actionLocks[src] = nil
    syncAll(false)
    return true, 'Vaso posicionado. Use uma semente perto dele para plantar.'
end, { rateLimit = { limit = 4, window = 10000 } })

OR.Callback.register('applyItem', function(src, id, itemName, slot)
    if actionLocks[src] then return false, 'Aguarde a ação anterior terminar.' end
    actionLocks[src] = true
    local function finish(ok, message) actionLocks[src] = nil return ok, message end
    local plant = getPlant(id)
    if not plant or not nearPlant(src, plant) then return finish(false, 'A planta não está mais ao seu alcance.') end
    if not ownsPlant(src, plant) then return finish(false, 'Somente o dono pode cuidar desta planta.') end
    itemName = tostring(itemName or '')
    local seedKind
    for kind, settings in pairs(DrugPlants.types) do if settings.seedItem == itemName then seedKind = kind break end end
    local message, consumed = nil, false
    local usedToolRemaining, usedToolMetadata, usedToolSlot
    if seedKind then
        if plant.kind then return finish(false, 'Esse vaso já possui uma planta.') end
        local removed, err = removeInventoryItem(src, itemName, 1)
        if not removed then return finish(false, err) end
        consumed = true
        local remaining = itemUses({ usesRemaining = plant.pot_uses_remaining }, DrugPlants.uses.pot)
        if remaining <= 0 then
            exports.ob_inventory:AddItem(src, itemName, 1)
            return finish(false, 'Esse vaso chegou ao limite de usos.')
        end
        plant.pot_uses_remaining = remaining - 1
        plant.kind, plant.growth, plant.health = seedKind, 0, 100
        plant.water, plant.nutrients, plant.last_update = DrugPlants.care.initialWater, DrugPlants.care.initialNutrients, now()
        message = ('Semente de %s plantada.'):format(DrugPlants.types[seedKind].label)
    elseif itemName == DrugPlants.items.wateringCan then
        if not plant.kind or tonumber(plant.health) <= 0 then return finish(false, 'Essa planta não pode ser regada.') end
        local used, useError
        used, usedToolRemaining, usedToolMetadata, usedToolSlot = consumeUseAtSlot(src, slot, itemName, DrugPlants.uses.wateringCan)
        if not used then return finish(false, useError or 'Você não possui um regador válido.') end
        local before = tonumber(plant.water) or 0
        plant.water = clamp(before + DrugPlants.care.waterPerUse, 0, 100)
        if before >= 85 then plant.health = clamp((tonumber(plant.health) or 100) - 4, 0, 100) end
        message = (before >= 85 and 'A planta foi regada demais e perdeu um pouco de saúde.' or 'Planta regada.')
            .. (usedToolRemaining > 0 and (' Restam %s usos no regador.'):format(usedToolRemaining) or ' O regador se desgastou por completo.')
    elseif itemName == DrugPlants.items.fertilizer then
        if not plant.kind or tonumber(plant.health) <= 0 then return finish(false, 'Essa planta não pode ser fertilizada.') end
        local removed, err = removeInventoryItem(src, itemName, 1)
        if not removed then return finish(false, err) end
        consumed = true
        plant.nutrients = clamp((tonumber(plant.nutrients) or 0) + DrugPlants.care.nutrientsPerUse, 0, 100)
        message = 'Fertilizante aplicado.'
    else
        return finish(false, 'Item de cultivo inválido.')
    end
    local updated, updateError = OR.Database.update.await([[UPDATE ob_drug_plants SET plant_type=?,growth=?,water=?,nutrients=?,health=?,last_update=?,pot_uses_remaining=? WHERE id=?]],
        { plant.kind, plant.growth, plant.water, plant.nutrients, plant.health, plant.last_update, plant.pot_uses_remaining, plant.id })
    if updated == nil then
        if consumed then exports.ob_inventory:AddItem(src, itemName, 1) end
        if usedToolMetadata then restoreConsumedUse(src, usedToolSlot, itemName, usedToolRemaining, usedToolMetadata) end
        return finish(false, updateError or 'Não foi possível salvar o cuidado da planta.')
    end
    actionLocks[src] = nil
    syncAll(false)
    return true, message
end, { rateLimit = { limit = 5, window = 10000 } })

OR.Callback.register('interact', function(src, id, action)
    if actionLocks[src] then return false, 'Aguarde a ação anterior terminar.' end
    actionLocks[src] = true
    local function finish(ok, message) actionLocks[src] = nil return ok, message end
    local plant = getPlant(id)
    if not plant or not nearPlant(src, plant) then return finish(false, 'A planta não está mais ao seu alcance.') end
    if not ownsPlant(src, plant) then return finish(false, 'Somente o dono pode mexer nesta planta.') end
    if action == 'inspect' then
        if not plant.kind then return finish(true, 'Vaso vazio. Use uma semente perto dele.') end
        local settings = DrugPlants.types[plant.kind]
        local fertilized = (tonumber(plant.nutrients) or 0) >= DrugPlants.care.fertilizedNutrientsMin
        return finish(true, ('%s | Crescimento %.0f%% | Falta %s | Água %.0f%% | Nutrientes %.0f%% | Saúde %.0f%%%s | Vaso %s/%s usos'):format(
            settings.label, plant.growth, remainingText(plant, settings), plant.water, plant.nutrients, plant.health,
            fertilized and ' | Fertilizada' or '', itemUses({ usesRemaining = plant.pot_uses_remaining }, DrugPlants.uses.pot), DrugPlants.uses.pot))
    end
    if action == 'remove' then
        if plant.kind and tonumber(plant.health) > 0 then return finish(false, 'Uma planta viva não pode ser removida desta forma.') end
        local metadata, remaining = potMetadata(plant)
        if remaining > 0 then
            local canCarry, carryError = exports.ob_inventory:CanCarryItem(src, DrugPlants.items.pot, 1, metadata)
            if not canCarry then return finish(false, carryError or 'Sem espaço para recolher o vaso.') end
            local added, addError = exports.ob_inventory:AddItem(src, DrugPlants.items.pot, 1, metadata)
            if not added then return finish(false, addError or 'Não foi possível recolher o vaso.') end
        end
        local deleted = OR.Database.update.await('DELETE FROM ob_drug_plants WHERE id=?', { plant.id })
        if deleted == nil or tonumber(deleted) < 1 then
            if remaining > 0 then exports.ob_inventory:RemoveItem(src, DrugPlants.items.pot, 1) end
            return finish(false, 'Não foi possível remover o vaso.')
        end
        actionLocks[src] = nil
        syncAll(false)
        return true, remaining > 0 and ('Vaso recolhido com %s uso(s) restante(s).'):format(remaining) or 'A planta foi removida e o vaso chegou ao fim da vida útil.'
    end
    if action ~= 'harvest' or not plant.kind or tonumber(plant.health) <= 0 or tonumber(plant.growth) < 100 then
        return finish(false, 'A planta ainda não está pronta para colheita.')
    end
    local settings = DrugPlants.types[plant.kind]
    local quality = clamp(tonumber(plant.health) or 0, 0, 100) / 100
    local amount = math.max(1, math.floor(settings.yieldMin + (settings.yieldMax - settings.yieldMin) * quality + 0.5))
    local returnsSeed = math.random(100) <= settings.seedReturnChance
    local potItemMetadata, potUsesRemaining = potMetadata(plant)
    local checks = { { item = settings.harvestItem, amount = amount } }
    if potUsesRemaining > 0 then checks[#checks + 1] = { item = DrugPlants.items.pot, amount = 1, metadata = potItemMetadata } end
    if returnsSeed then checks[#checks + 1] = { item = settings.seedItem, amount = 1 } end
    for _, reward in ipairs(checks) do
        local canCarry, carryError = exports.ob_inventory:CanCarryItem(src, reward.item, reward.amount, reward.metadata)
        if not canCarry then return finish(false, carryError or 'Sem espaço para receber a colheita.') end
    end
    local addedRewards = {}
    for _, reward in ipairs(checks) do
        local added, addError = exports.ob_inventory:AddItem(src, reward.item, reward.amount, reward.metadata)
        if not added then
            for _, previous in ipairs(addedRewards) do exports.ob_inventory:RemoveItem(src, previous.item, previous.amount) end
            return finish(false, addError or 'Não foi possível guardar toda a colheita.')
        end
        addedRewards[#addedRewards + 1] = reward
    end
    local deleted = OR.Database.update.await('DELETE FROM ob_drug_plants WHERE id=?', { plant.id })
    if deleted == nil or tonumber(deleted) < 1 then
        for _, reward in ipairs(addedRewards) do exports.ob_inventory:RemoveItem(src, reward.item, reward.amount) end
        return finish(false, 'Não foi possível concluir a colheita.')
    end
    actionLocks[src] = nil
    syncAll(false)
    local potMessage = potUsesRemaining > 0 and (' Vaso devolvido com %s uso(s).'):format(potUsesRemaining)
        or ' O vaso chegou ao limite de 5 plantios e não foi devolvido.'
    return true, ('Colheita concluída: %sx %s%s.%s'):format(amount, settings.label, returnsSeed and ' e uma semente' or '', potMessage)
end, { rateLimit = { limit = 5, window = 10000 } })

exports('UseItem', function(src, itemName, slot)
    local valid = itemName == DrugPlants.items.pot or itemName == DrugPlants.items.wateringCan or itemName == DrugPlants.items.fertilizer
    if not valid then
        for _, settings in pairs(DrugPlants.types) do if settings.seedItem == itemName then valid = true break end end
    end
    if not valid then return false, 'Esse item não pertence ao sistema de cultivo.', false end
    if not databaseReady then return false, 'Banco de cultivo indisponível.', false end
    if not playerCanAct(src) then return false, 'Você não pode cultivar agora.', false end
    TriggerClientEvent(resource .. ':client:useItem', src, itemName, slot)
    return true, itemName == DrugPlants.items.pot and 'Escolha onde posicionar o vaso.' or 'Use o item perto de um vaso seu.', false
end)

CreateThread(function()
    if not OR.Database.waitForReady(30000) then return print('[ob_drugplants] Banco indisponível.') end
    local created, createError = OR.Database.query.await([[CREATE TABLE IF NOT EXISTS ob_drug_plants (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        owner_user_id BIGINT UNSIGNED NOT NULL,
        plant_type VARCHAR(24) NULL,
        x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL, heading FLOAT NOT NULL DEFAULT 0,
        growth FLOAT NOT NULL DEFAULT 0, water FLOAT NOT NULL DEFAULT 0, nutrients FLOAT NOT NULL DEFAULT 0,
        health FLOAT NOT NULL DEFAULT 100, last_update BIGINT UNSIGNED NOT NULL,
        pot_uses_remaining TINYINT UNSIGNED NOT NULL DEFAULT 5,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id), KEY idx_ob_drug_plants_owner (owner_user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    if not created then return print(('[ob_drugplants] Falha ao criar tabela: %s'):format(createError or 'desconhecida')) end
    local usesColumn = OR.Database.single.await("SHOW COLUMNS FROM ob_drug_plants LIKE 'pot_uses_remaining'")
    if not usesColumn then
        local altered, alterError = OR.Database.query.await('ALTER TABLE ob_drug_plants ADD COLUMN pot_uses_remaining TINYINT UNSIGNED NOT NULL DEFAULT 5 AFTER last_update')
        if not altered then return print(('[ob_drugplants] Falha ao adicionar usos do vaso: %s'):format(alterError or 'desconhecida')) end
    end
    local plantedMaximum = math.max(0, DrugPlants.uses.pot - 1)
    local migrated, migrationError = OR.Database.update.await([[UPDATE ob_drug_plants
        SET pot_uses_remaining=LEAST(pot_uses_remaining, ?) WHERE plant_type IS NOT NULL AND pot_uses_remaining>?]],
        { plantedMaximum, plantedMaximum })
    if migrated == nil then return print(('[ob_drugplants] Falha ao migrar usos dos vasos ativos: %s'):format(migrationError or 'desconhecida')) end
    databaseReady = true
    syncAll(true)
end)

CreateThread(function()
    while true do
        Wait(math.max(15, DrugPlants.databaseTickSeconds) * 1000)
        if databaseReady then syncAll(true) end
    end
end)

AddEventHandler('playerDropped', function() actionLocks[tonumber(source)] = nil end)

