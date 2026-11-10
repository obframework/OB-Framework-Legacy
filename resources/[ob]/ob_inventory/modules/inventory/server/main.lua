local inventories = {}
local ownedInventories = {}
local groundDrops = {}
local databaseReady = false
local weaponUseSync = {}

ORInventory = ORInventory or {}

local schema = [[
CREATE TABLE IF NOT EXISTS ob_inventories (
    owner_type VARCHAR(32) NOT NULL,
    owner_id VARCHAR(96) NOT NULL,
    items MEDIUMTEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (owner_type, owner_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

local function validSource(playerSource)
    playerSource = tonumber(playerSource)
    return playerSource and playerSource > 0 and GetPlayerName(playerSource) and playerSource or nil
end

function ORInventory.IsPlayerActionRestricted(playerSource)
    playerSource = validSource(playerSource)
    if not playerSource then return true end
    local state = Player(playerSource).state
    local policeRestrained = false
    if GetResourceState('ob_police') == 'started' then
        local ok, value = pcall(function() return exports.ob_police:IsRestrained(playerSource) end)
        policeRestrained = ok and value == true
    end
    return state['or:downed'] == true
        or state['or:restrained'] == true
        or state['ob:restrained'] == true
        or state['ob:takedown'] == true
        or policeRestrained
end

local function inventoryActionAllowed(playerSource)
    if ORInventory.IsPlayerActionRestricted(playerSource) then
        return false, 'Voce nao pode usar o inventario nesse estado.'
    end
    return true
end

local function itemDefinition(itemName)
    if type(itemName) ~= 'string' then return nil end
    return ORInventoryItems[itemName:lower()]
end

local function getUserId(playerSource)
    return validSource(playerSource) and exports.ob_core:GetUserId(playerSource) or nil
end

local function baseMaxWeight()
    return math.max(1, math.floor(tonumber(ORInventoryConfig.MaxWeight) or 20000))
end

local function maximumBackpackWeight()
    return math.max(baseMaxWeight(), math.floor(tonumber(ORInventoryConfig.MaxBackpackWeight) or 50000))
end

local function normalizeMaxWeight(value)
    local parsed = math.floor(tonumber(value) or baseMaxWeight())
    return math.max(baseMaxWeight(), math.min(maximumBackpackWeight(), parsed))
end

local function maximumBackpackCount()
    return math.max(0, math.min(20, math.floor(tonumber(ORInventoryConfig.MaxBackpacks) or 3)))
end

local function backpackSlotUpgrade()
    return math.max(1, math.floor(tonumber(ORInventoryConfig.BackpackSlotUpgrade) or 10))
end

local function playerBackpackCount(inventory)
    local explicit = inventory and tonumber(inventory.backpacks) or nil
    if explicit then return math.max(0, math.min(maximumBackpackCount(), math.floor(explicit))) end
    local weightUpgrade = math.max(1, math.floor(tonumber(ORInventoryConfig.BackpackUpgrade) or 10000))
    local inferred = math.floor(math.max(0, normalizeMaxWeight(inventory and inventory.maxWeight) - baseMaxWeight()) / weightUpgrade)
    return math.max(0, math.min(maximumBackpackCount(), inferred))
end

local function inventorySlotCount(inventory)
    if inventory and inventory.ownerType ~= 'player' then
        return math.max(1, math.min(500, math.floor(tonumber(inventory.slots) or 1)))
    end
    local baseSlots = math.max(1, math.floor(tonumber(ORInventoryConfig.Slots) or 30))
    return math.min(500, baseSlots + (playerBackpackCount(inventory) * backpackSlotUpgrade()))
end

local function inventoryVisibleSlotCount(inventory)
    local visible = inventorySlotCount(inventory)
    for slot in pairs(inventory and inventory.items or {}) do
        slot = math.floor(tonumber(slot) or 0)
        if slot > visible and slot <= 500 then visible = slot end
    end
    return visible
end

local function inventoryMaximumWeight(inventory)
    if inventory and inventory.ownerType ~= 'player' then
        return math.max(1, math.min(1000000000, math.floor(tonumber(inventory.maxWeight) or 1)))
    end
    return normalizeMaxWeight(inventory and inventory.maxWeight)
end

local function decodeMetadata(raw)
    if type(raw) == 'table' then return raw end
    if type(raw) ~= 'string' or raw == '' then return {} end
    local ok, decoded = pcall(json.decode, raw)
    return ok and type(decoded) == 'table' and decoded or {}
end

local function decodeInventoryPayload(raw)
    if type(raw) ~= 'string' or raw == '' then return {}, baseMaxWeight(), 0 end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return {}, baseMaxWeight(), 0 end

    -- Formato novo: { items = { [slot] = item }, maxWeight = 20000 }.
    -- Formato antigo: { [slot] = item }, que continua valido com 20 kg.
    if type(decoded.items) == 'table' then
        return decoded.items, normalizeMaxWeight(decoded.maxWeight), tonumber(decoded.backpacks)
    end
    return decoded, baseMaxWeight(), 0
end

local function inventoryWeight(inventory)
    local total = 0
    for _, item in pairs(inventory.items or {}) do
        local definition = itemDefinition(item.name)
        total = total + ((definition and definition.weight or 0) * item.amount)
    end
    return total
end

local function durabilityDays(itemName, definition)
    local config = ORInventoryConfig.Durability or {}
    if (config.NonDurableItems or {})[itemName] or ((config.NonDurableTypes or {})[definition.type]) then return 0 end
    if definition.durability ~= nil then return math.max(0, tonumber(definition.durability) or 0) end
    if definition.type == 'weapon' then
        local override = (config.WeaponOverrides or {})[itemName]
        return math.max(0, tonumber(override ~= nil and override or config.WeaponDays) or 7)
    end
    return math.max(0, tonumber(config.DefaultDays) or 7)
end

local function ensureDurability(item, definition)
    item.metadata = type(item.metadata) == 'table' and item.metadata or {}
    local days = durabilityDays(item.name, definition)
    if days <= 0 then
        if item.metadata.durabilityExpiresAt or item.metadata.durabilityCreatedAt then
            item.metadata.durabilityExpiresAt, item.metadata.durabilityCreatedAt = nil, nil
            return true
        end
        return false
    end
    if tonumber(item.metadata.durabilityExpiresAt) and tonumber(item.metadata.durabilityCreatedAt) then return false end
    local created = os.time()
    item.metadata.durabilityCreatedAt = created
    item.metadata.durabilityExpiresAt = created + (days * 86400)
    return true
end

local function itemExpired(item)
    local expiresAt = tonumber(item and item.metadata and item.metadata.durabilityExpiresAt)
    return expiresAt and expiresAt > 0 and os.time() >= expiresAt or false
end

local function sameMetadata(left, right)
    local okLeft, encodedLeft = pcall(json.encode, left or {})
    local okRight, encodedRight = pcall(json.encode, right or {})
    return okLeft and okRight and encodedLeft == encodedRight
end

local function publicItem(item)
    local definition = itemDefinition(item.name)
    if not definition then return nil end
    local expiresAt, createdAt = tonumber(item.metadata and item.metadata.durabilityExpiresAt), tonumber(item.metadata and item.metadata.durabilityCreatedAt)
    local description = type(item.metadata) == 'table' and item.metadata.description or definition.description or definition.label
    if definition.type == 'weapon' then
        local serial = item.metadata and item.metadata.serial
        local serialText = item.metadata and item.metadata.serialRemoved == true and 'Numeracao raspada'
            or (serial and tostring(serial) or 'Sem registro')
        description = ('%s\nSerial: %s'):format(description or definition.label,serialText)
    end
    if definition.type == 'document' and item.metadata and item.metadata.documentType == 'driver_license' then
        local documentExpiry = tonumber(item.metadata.expiresAt) or 0
        local validity = documentExpiry > os.time()
            and (('%s dia(s), ate %s'):format(math.max(0, math.ceil((documentExpiry - os.time()) / 86400)), os.date('%d/%m/%Y', documentExpiry)))
            or (documentExpiry > 0 and ('VENCIDA em ' .. os.date('%d/%m/%Y', documentExpiry)) or 'Nao emitida')
        description = ('Titular: %s\nRegistro: %s\nCategorias: %s\nValidade: %s'):format(
            tostring(item.metadata.fullName or 'Nao informado'), tostring(item.metadata.userId or '?'),
            tostring(item.metadata.categoryText or 'Nenhuma'), validity)
    end
    return {
        slot = item.slot,
        name = item.name,
        label = definition.type == 'vehicle_key' and ('Chave - ' .. tostring(item.metadata and item.metadata.plate or '?')) or definition.label,
        icon = definition.icon or '?',
        amount = item.amount,
        weight = definition.weight,
        type = definition.type,
        description = description,
        durability = expiresAt and { createdAt = createdAt, expiresAt = expiresAt, expired = itemExpired(item) } or nil,
        use = definition.use,
        maxUses = definition.maxUses,
        maxCarry = tonumber(definition.maxCarry),
        -- Somente um caminho declarado no catalogo e enviado como imagem
        -- explicita. Sem isso, a NUI tenta primeiro o CDN configurado.
        image = definition.image,
        metadata = item.metadata or {},
    }
end

local function snapshot(inventory)
    local items = {}
    for slot, item in pairs(inventory.items or {}) do
        -- Chaves numericas esparsas podem ser serializadas pelo NUI como uma
        -- lista vazia. Slots sao um mapa, portanto saem como chaves texto.
        items[tostring(slot)] = publicItem(item)
    end

    return {
        slots = inventoryVisibleSlotCount(inventory),
        activeSlots = inventorySlotCount(inventory),
        maxWeight = inventoryMaximumWeight(inventory),
        weight = inventoryWeight(inventory),
        items = items,
    }
end

local itemChangeBaseline = {}
local function syncInventory(playerSource)
    local inventory = inventories[playerSource]
    if not inventory then return end
    local current, totals = snapshot(inventory), {}
    for _, item in pairs(current.items) do
        local entry = totals[item.name]
        if not entry then entry = { amount = 0, item = item }; totals[item.name] = entry end
        entry.amount = entry.amount + item.amount
    end
    local previous = itemChangeBaseline[playerSource]
    itemChangeBaseline[playerSource] = totals
    -- A primeira carga/reconexao nao representa recebimento de itens.
    if previous then
        local changes, names = {}, {}
        for name in pairs(previous) do names[name] = true end
        for name in pairs(totals) do names[name] = true end
        for name in pairs(names) do
            local before, after = previous[name], totals[name]
            local delta = (after and after.amount or 0) - (before and before.amount or 0)
            if delta ~= 0 then
                local item = (after or before).item
                changes[#changes + 1] = { name = name, label = item.label, icon = item.icon,
                    image = item.image, amount = math.abs(delta), added = delta > 0 }
            end
        end
        if #changes > 0 then TriggerClientEvent('ob_inventory:client:itemChanges', playerSource, changes) end
    end
    TriggerClientEvent('ob_inventory:client:sync', playerSource, current)
end

-- Um inventario ocupa apenas uma linha: items e um JSON com slot, item,
-- quantidade e metadata. owner_type/owner_id permitem reutilizar a mesma
-- tabela para personagens, baus, porta-malas e outros donos no futuro.
local function inventoryPayload(inventory)
    local items = {}
    for slot, item in pairs(inventory.items or {}) do
        items[tostring(slot)] = {
            name = item.name,
            amount = item.amount,
            metadata = item.metadata or {},
        }
    end
    return json.encode({
        items = items,
        maxWeight = inventoryMaximumWeight(inventory),
        backpacks = inventory.ownerType == 'player' and playerBackpackCount(inventory) or nil,
    })
end

local function persistInventory(inventory)
    local result, errorMessage = OR.Database.update.await([[
        INSERT INTO ob_inventories (owner_type, owner_id, items)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE items = VALUES(items), updated_at = CURRENT_TIMESTAMP
    ]], {
        inventory.ownerType or 'player',
        tostring(inventory.ownerId or inventory.userId),
        inventoryPayload(inventory),
    })
    if result == nil then return false, errorMessage or 'Falha ao salvar o inventario.' end
    return true
end

local function migrateLegacyInventories()
    -- A tabela antiga e mantida como backup. A migracao somente cria o JSON
    -- para quem ainda nao possui uma linha na nova tabela.
    local legacyTable = OR.Database.scalar.await([[
        SELECT COUNT(*) FROM information_schema.tables
        WHERE table_schema = DATABASE() AND table_name = ?
    ]], { 'ob_inventory_items' })
    if tonumber(legacyTable) ~= 1 then return end

    local legacyRows = OR.Database.query.await(
        'SELECT user_id, slot, item_name, amount, metadata FROM ob_inventory_items ORDER BY user_id ASC, slot ASC'
    )
    if not legacyRows then return end

    local existingRows = OR.Database.query.await(
        'SELECT owner_id FROM ob_inventories WHERE owner_type = ?', { 'player' }
    ) or {}
    local existing = {}
    for _, row in ipairs(existingRows) do existing[tostring(row.owner_id)] = true end

    local grouped = {}
    for _, row in ipairs(legacyRows) do
        local userId = tonumber(row.user_id)
        local slot = tonumber(row.slot)
        local amount = tonumber(row.amount)
        if userId and slot and slot >= 1 and slot <= ORInventoryConfig.Slots and amount and amount > 0 and itemDefinition(row.item_name) then
            grouped[userId] = grouped[userId] or {}
            grouped[userId][tostring(slot)] = {
                name = row.item_name,
                amount = math.floor(amount),
                metadata = decodeMetadata(row.metadata),
            }
        end
    end

    for userId, items in pairs(grouped) do
        local ownerId = tostring(userId)
        if not existing[ownerId] then
            local result, errorMessage = OR.Database.insert.await(
                'INSERT INTO ob_inventories (owner_type, owner_id, items) VALUES (?, ?, ?)',
                { 'player', ownerId, json.encode(items) }
            )
            if result == nil then
                print(('[ob_inventory] Falha ao migrar inventario do usuario %s: %s'):format(ownerId, tostring(errorMessage)))
            end
        end
    end
end

local function loadInventory(playerSource)
    playerSource = validSource(playerSource)
    if not databaseReady or not playerSource then return nil, 'Inventario indisponivel.' end

    local userId = getUserId(playerSource)
    if not userId then return nil, 'Personagem ainda nao foi carregado.' end

    local current = inventories[playerSource]
    if current and current.userId == userId then return current end

    local row, errorMessage = OR.Database.single.await(
        'SELECT items FROM ob_inventories WHERE owner_type = ? AND owner_id = ?',
        { 'player', tostring(userId) }
    )
    if row == nil and errorMessage then return nil, errorMessage or 'Nao foi possivel carregar o inventario.' end

    local storedItems, storedMaxWeight, storedBackpacks = decodeInventoryPayload(row and row.items)
    local inventory, changed = {
        ownerType = 'player', ownerId = tostring(userId), userId = userId,
        slots = ORInventoryConfig.Slots, items = {}, maxWeight = storedMaxWeight,
        backpacks = storedBackpacks,
    }, false
    inventory.backpacks = playerBackpackCount(inventory)
    changed = storedBackpacks == nil
    for index, storedItem in pairs(storedItems) do
        local slot = tonumber(index)
        local definition = type(storedItem) == 'table' and itemDefinition(storedItem.name) or nil
        local amount = type(storedItem) == 'table' and tonumber(storedItem.amount) or nil
        if slot and slot >= 1 and slot <= 500 and definition and amount and amount > 0 then
            local item = {
                slot = slot,
                name = storedItem.name,
                amount = math.floor(amount),
                metadata = decodeMetadata(storedItem.metadata),
            }
            changed = ensureDurability(item, definition) or changed
            inventory.items[slot] = item
        end
    end

    if changed then persistInventory(inventory) end
    inventories[playerSource] = inventory
    syncInventory(playerSource)
    return inventory
end

local function loadOwnedInventory(ownerType, ownerId, slots, maxWeight)
    ownerType = type(ownerType) == 'string' and ownerType:lower() or ''
    ownerId = tostring(ownerId or '')
    slots = math.max(1, math.min(500, math.floor(tonumber(slots) or 0)))
    maxWeight = math.max(1, math.min(1000000000, math.floor(tonumber(maxWeight) or 0)))
    if not databaseReady then return nil, 'Inventario indisponivel.' end
    if ownerType == '' or ownerType == 'player' or not ownerType:match('^[a-z0-9_:%-]+$') or ownerId == '' then
        return nil, 'Proprietario de inventario invalido.'
    end

    local cacheKey = ('%s:%s'):format(ownerType, ownerId)
    local current = ownedInventories[cacheKey]
    if current then
        current.slots, current.maxWeight = slots, maxWeight
        return current
    end

    local row, errorMessage = OR.Database.single.await(
        'SELECT items FROM ob_inventories WHERE owner_type = ? AND owner_id = ?',
        { ownerType, ownerId }
    )
    if row == nil and errorMessage then return nil, errorMessage or 'Nao foi possivel carregar o bau.' end

    local storedItems = decodeInventoryPayload(row and row.items)
    local inventory, changed = {
        ownerType = ownerType, ownerId = ownerId, slots = slots,
        items = {}, maxWeight = maxWeight,
    }, false
    for index, storedItem in pairs(storedItems) do
        local slot = tonumber(index)
        local definition = type(storedItem) == 'table' and itemDefinition(storedItem.name) or nil
        local amount = type(storedItem) == 'table' and tonumber(storedItem.amount) or nil
        -- Uma reducao administrativa nunca apaga o excedente. Os itens acima
        -- da capacidade ativa continuam carregados como slots de recuperacao.
        if slot and slot >= 1 and slot <= 500 and definition and amount and amount > 0 then
            local item = {
                slot = slot, name = storedItem.name, amount = math.floor(amount),
                metadata = decodeMetadata(storedItem.metadata),
            }
            changed = ensureDurability(item, definition) or changed
            inventory.items[slot] = item
        end
    end
    ownedInventories[cacheKey] = inventory
    if changed then persistInventory(inventory) end
    return inventory
end

local function persistItem(inventory)
    return persistInventory(inventory)
end

local function canCarry(inventory, itemName, amount)
    local definition = itemDefinition(itemName)
    if not definition then return false, 'Item invalido.' end
    if inventoryWeight(inventory) + (definition.weight * amount) > inventoryMaximumWeight(inventory) then
        return false, 'Peso maximo do inventario atingido.'
    end
    return true
end

local function itemAtSlot(inventory, slot)
    slot = math.floor(tonumber(slot) or 0)
    if slot < 1 then return nil end
    return inventory.items[slot] or inventory.items[tostring(slot)]
end

local function firstFreeSlot(inventory)
    for slot = 1, inventorySlotCount(inventory) do
        if not itemAtSlot(inventory, slot) then return slot end
    end
end

local function canAddItemToInventory(inventory, itemName, amount, metadata, preferredSlot)
    local carry, carryError = canCarry(inventory, itemName, amount)
    if not carry then return false, carryError end

    -- maxCarry limita a quantidade total do item na mochila do personagem,
    -- independentemente de slots ou metadata. Ausente/0 significa ilimitado.
    local definition = itemDefinition(itemName)
    local maxCarry = math.floor(tonumber(definition and definition.maxCarry) or 0)
    if inventory.ownerType == 'player' and maxCarry > 0 then
        local current = 0
        for _, existing in pairs(inventory.items) do
            if existing.name == itemName then current = current + math.max(0, math.floor(tonumber(existing.amount) or 0)) end
        end
        if current + amount > maxCarry then
            return false, ('Voce pode carregar no maximo %sx %s.'):format(maxCarry, definition.label or itemName)
        end
    end

    -- O telefone e um aparelho fisico unico. Esta verificacao central cobre
    -- loja, coleta, bau e transferencia entre jogadores.
    if itemName == 'phone' and inventory.ownerType == 'player' then
        for _, existing in pairs(inventory.items) do
            if existing.name == 'phone' then
                return false, 'Voce so pode carregar um celular por vez.'
            end
        end
    end

    local maxStack = tonumber(definition and definition.maxStack) or 1
    preferredSlot = math.floor(tonumber(preferredSlot) or 0)
    if preferredSlot > 0 then
        if preferredSlot > inventorySlotCount(inventory) then return false, 'Slot invalido.' end
        local targetItem = itemAtSlot(inventory, preferredSlot)
        if targetItem and (targetItem.name ~= itemName or not sameMetadata(targetItem.metadata, metadata)) then
            return false, 'Esse slot esta ocupado por outro item.'
        end
        local targetAmount = targetItem and targetItem.amount or 0
        if targetAmount + amount > maxStack then
            return false, 'Essa quantidade nao cabe nesse slot.'
        end
        return true
    end

    local capacity = 0
    for _, item in pairs(inventory.items) do
        if (tonumber(item.slot) or 0) <= inventorySlotCount(inventory)
            and item.name == itemName and sameMetadata(item.metadata, metadata) then
            capacity = capacity + math.max(0, maxStack - item.amount)
        end
    end
    for slot = 1, inventorySlotCount(inventory) do
        if not itemAtSlot(inventory, slot) then capacity = capacity + maxStack end
    end
    if capacity < amount then return false, 'Sem espaco em slots no inventario.' end
    return true
end

local function addItemToInventory(inventory, itemName, amount, metadata, preferredSlot, emptySlotsFirst)
    local definition = itemDefinition(itemName)
    amount = math.floor(tonumber(amount) or 0)
    if not definition or amount < 1 then return false, 'Item ou quantidade invalida.' end
    local received = { name = itemName, metadata = decodeMetadata(metadata) }
    ensureDurability(received, definition)
    metadata = received.metadata

    preferredSlot = math.floor(tonumber(preferredSlot) or 0)
    local canAdd, addError = canAddItemToInventory(inventory, itemName, amount, metadata, preferredSlot)
    if not canAdd then return false, addError end

    if preferredSlot > 0 then
        local targetItem = itemAtSlot(inventory, preferredSlot)
        local previousAmount = targetItem and targetItem.amount or nil
        if targetItem then
            targetItem.amount = targetItem.amount + amount
        else
            inventory.items[preferredSlot] = { slot = preferredSlot, name = itemName, amount = amount, metadata = metadata or {} }
        end
        local saved, saveError = persistItem(inventory)
        if not saved then
            if targetItem then
                targetItem.amount = previousAmount
            else
                inventory.items[preferredSlot] = nil
            end
            return false, saveError
        end
        return true
    end

    local remaining = amount
    local maxStack = tonumber(definition.maxStack) or 1

    local function addToEmptySlot()
        local emptySlot = firstFreeSlot(inventory)
        if not emptySlot then return false end

        local adding = math.min(maxStack, remaining)
        local item = { slot = emptySlot, name = itemName, amount = adding, metadata = metadata or {} }
        inventory.items[emptySlot] = item
        local saved, saveError = persistItem(inventory, item)
        if not saved then
            inventory.items[emptySlot] = nil
            return nil, saveError
        end
        remaining = remaining - adding
        return true
    end

    -- Transferencias entre jogadores ocupam primeiro o menor slot realmente
    -- vazio. Isso preserva a organizacao da mochila de quem recebe e evita que
    -- uma arma recebida tente reutilizar os primeiros slots ocupados.
    if emptySlotsFirst then
        while remaining > 0 do
            local addedToEmpty, emptyError = addToEmptySlot()
            if addedToEmpty == nil then return false, emptyError end
            if not addedToEmpty then break end
        end
        if remaining == 0 then return true end
    end

    for _, item in pairs(inventory.items) do
        if (tonumber(item.slot) or 0) <= inventorySlotCount(inventory)
            and item.name == itemName and sameMetadata(item.metadata, metadata) and item.amount < maxStack then
            local adding = math.min(maxStack - item.amount, remaining)
            item.amount = item.amount + adding
            local saved, saveError = persistItem(inventory, item)
            if not saved then
                item.amount = item.amount - adding
                return false, saveError
            end
            remaining = remaining - adding
            if remaining == 0 then return true end
        end
    end

    while remaining > 0 do
        local addedToEmpty, emptyError = addToEmptySlot()
        if addedToEmpty == nil then return false, emptyError end
        if not addedToEmpty then return false, 'Sem espaco em slots no inventario.' end
    end

    return true
end

-- Coletas e compras pela NUI nunca escolhem um slot automatico: o cliente
-- informa exatamente onde o jogador soltou o item.
local function addItemAtSlot(inventory, itemName, amount, metadata, targetSlot)
    targetSlot = math.floor(tonumber(targetSlot) or 0)
    if targetSlot < 1 or targetSlot > inventorySlotCount(inventory) then
        return false, 'Arraste o item para um slot valido.'
    end
    return addItemToInventory(inventory, itemName, amount, metadata, targetSlot)
end

local function removeItemFromInventory(inventory, slot, amount)
    slot = math.floor(tonumber(slot) or 0)
    amount = math.floor(tonumber(amount) or 0)
    local item = inventory.items[slot]
    if not item or amount < 1 or amount > item.amount then return false, 'Quantidade indisponivel.' end

    local previousAmount = item.amount
    item.amount = item.amount - amount
    local saved, errorMessage
    if item.amount <= 0 then
        inventory.items[slot] = nil
        saved, errorMessage = persistInventory(inventory)
    else
        saved, errorMessage = persistInventory(inventory)
    end

    if not saved then
        item.amount = previousAmount
        inventory.items[slot] = item
        return false, errorMessage
    end
    return true, item
end

local function countItemInInventory(inventory, itemName)
    local total = 0
    for _, item in pairs(inventory.items) do
        if item.name == itemName then total = total + item.amount end
    end
    return total
end

local function removeItemByName(playerSource, itemName, amount)
    playerSource = validSource(playerSource)
    itemName = type(itemName) == 'string' and itemName:lower() or ''
    amount = math.floor(tonumber(amount) or 0)
    if not playerSource or not itemDefinition(itemName) or amount < 1 then return false, 'Item ou quantidade invalida.' end

    local inventory, errorMessage = loadInventory(playerSource)
    if not inventory then return false, errorMessage end
    if countItemInInventory(inventory, itemName) < amount then
        local definition=itemDefinition(itemName)
        return false, ('Voce nao possui %sx %s.'):format(amount,definition and definition.label or itemName)
    end

    local slots = {}
    for slot, item in pairs(inventory.items) do
        if item.name == itemName then slots[#slots + 1] = slot end
    end
    table.sort(slots)

    local changes = {}
    local remaining = amount
    for _, slot in ipairs(slots) do
        if remaining <= 0 then break end
        local item = inventory.items[slot]
        local removed = math.min(item.amount, remaining)
        changes[#changes + 1] = { slot = slot, item = item, amount = item.amount }
        item.amount = item.amount - removed
        if item.amount <= 0 then inventory.items[slot] = nil end
        remaining = remaining - removed
    end

    local saved, saveError = persistInventory(inventory)
    if not saved then
        for _, change in ipairs(changes) do
            change.item.amount = change.amount
            inventory.items[change.slot] = change.item
        end
        return false, saveError or 'Nao foi possivel remover o item.'
    end

    syncInventory(playerSource)
    return true
end

local function moveItemSlot(inventory, fromSlot, toSlot)
    fromSlot = math.floor(tonumber(fromSlot) or 0)
    toSlot = math.floor(tonumber(toSlot) or 0)
    local activeSlots = inventorySlotCount(inventory)
    local visibleSlots = inventoryVisibleSlotCount(inventory)
    if fromSlot < 1 or toSlot < 1 or fromSlot > visibleSlots or toSlot > activeSlots then
        return false, 'Slot invalido.'
    end
    if fromSlot == toSlot then return true end

    local sourceItem = inventory.items[fromSlot]
    if not sourceItem then return false, 'Nao ha item nesse slot.' end
    local targetItem = inventory.items[toSlot]
    if fromSlot > activeSlots and targetItem then
        return false, 'Mova o item bloqueado para um slot ativo vazio.'
    end
    inventory.items[fromSlot], inventory.items[toSlot] = targetItem, sourceItem
    sourceItem.slot = toSlot
    if targetItem then targetItem.slot = fromSlot end
    local saved, errorMessage = persistInventory(inventory)
    if saved then return true end

    inventory.items[fromSlot], inventory.items[toSlot] = sourceItem, targetItem
    sourceItem.slot = fromSlot
    if targetItem then targetItem.slot = toSlot end
    return false, errorMessage or 'Nao foi possivel mover o item.'
end

local function publicGroundDrop(drop)
    local items = {}
    for index, item in ipairs(drop.items) do
        local public = publicItem(item)
        -- Evita que a NUI converta uma lista Lua em array vazio/sparse.
        if public then items[tostring(index)] = public end
    end
    local label = #drop.items > 1 and 'Itens no chao' or (items['1'] and items['1'].label) or drop.label
    return {
        id = drop.id,
        coords = drop.coords,
        label = label,
        expiresAt = drop.expiresAt,
        items = items,
    }
end

local function groundDropSnapshot()
    local drops = {}
    for id, drop in pairs(groundDrops) do drops[id] = publicGroundDrop(drop) end
    return drops
end

local function sendGroundDrops(playerSource)
    TriggerClientEvent('ob_inventory:client:groundDrops', playerSource, groundDropSnapshot())
end

local function broadcastGroundDrops()
    TriggerClientEvent('ob_inventory:client:groundDrops', -1, groundDropSnapshot())
end

local function createGroundDrop(coords, items)
    for _, existingDrop in pairs(groundDrops) do
        local existingCoords = vector3(existingDrop.coords.x, existingDrop.coords.y, existingDrop.coords.z)
        if existingDrop.expiresAt > GetGameTimer() and #(existingCoords - coords) <= 1.5 then
            for _, item in ipairs(items) do table.insert(existingDrop.items, item) end
            existingDrop.label = #existingDrop.items > 1 and 'Itens no chao' or existingDrop.label
            existingDrop.expiresAt = GetGameTimer() + ORInventoryConfig.Ground.ExpireMs
            broadcastGroundDrops()
            return existingDrop
        end
    end

    local firstItem = items[1]
    local definition = firstItem and itemDefinition(firstItem.name)
    local id = ('drop:%s:%s'):format(GetGameTimer(), math.random(100000, 999999))
    groundDrops[id] = {
        id = id,
        coords = { x = coords.x, y = coords.y, z = coords.z },
        items = items,
        label = definition and definition.label or 'Itens',
        expiresAt = GetGameTimer() + ORInventoryConfig.Ground.ExpireMs,
    }
    broadcastGroundDrops()
    return groundDrops[id]
end

local function playerNearDrop(playerSource, drop)
    local ped = GetPlayerPed(playerSource)
    if not ped or ped <= 0 then return false end
    local coords = GetEntityCoords(ped)
    local dropCoords = vector3(drop.coords.x, drop.coords.y, drop.coords.z)
    return #(coords - dropCoords) <= (ORInventoryConfig.Ground.InteractDistance + 0.6)
end

local function inventoryResponse(playerSource, dropId)
    local inventory, errorMessage = loadInventory(playerSource)
    if not inventory then return false, errorMessage end

    -- A lista completa e usada pelo cliente para restaurar os marcadores se
    -- ele tambem tiver reiniciado depois do broadcast inicial.
    local result = { inventory = snapshot(inventory), ground = nil, drops = groundDropSnapshot() }
    if dropId then
        local drop = groundDrops[dropId]
        if not drop or drop.expiresAt <= GetGameTimer() then return false, 'Esse item no chao nao esta mais disponivel.' end
        if not playerNearDrop(playerSource, drop) then return false, 'Aproxime-se do item no chao.' end
        result.ground = publicGroundDrop(drop)
    end
    return true, result
end

OR.Callback.register('open', function(playerSource, dropId)
    return inventoryResponse(playerSource, type(dropId) == 'string' and dropId or nil)
end)

local function equippedWeaponMatches(item, activeWeaponItem)
    local definition = item and itemDefinition(item.name)
    return definition and definition.type == 'weapon'
        and tostring(activeWeaponItem or ''):lower() == item.name
end

OR.Callback.register('drop', function(playerSource, slot, amount, activeWeaponItem)
    local allowed, restrictionError = inventoryActionAllowed(playerSource)
    if not allowed then return false, restrictionError end
    local inventory, errorMessage = loadInventory(playerSource)
    if not inventory then return false, errorMessage end

    slot = math.floor(tonumber(slot) or 0)
    local item = inventory.items[slot]
    amount = math.floor(tonumber(amount) or 0)
    if not item or amount < 1 or amount > item.amount then return false, 'Quantidade invalida para jogar no chao.' end
    if equippedWeaponMatches(item, activeWeaponItem) then
        return false, 'Guarde a arma antes de joga-la no chao.'
    end

    local removed, removeError = removeItemFromInventory(inventory, slot, amount)
    if not removed then return false, removeError end

    local ped = GetPlayerPed(playerSource)
    local coords = GetEntityCoords(ped)
    local createdDrop = createGroundDrop(coords, {{ slot = 1, name = item.name, amount = amount, metadata = item.metadata or {} }})
    syncInventory(playerSource)
    local success, response = inventoryResponse(playerSource, createdDrop.id)
    if not success then return false, response end
    return true, response, 'Item jogado no chao.'
end)

OR.Callback.register('move', function(playerSource, fromSlot, toSlot)
    local allowed, restrictionError = inventoryActionAllowed(playerSource)
    if not allowed then return false, restrictionError end
    local inventory, errorMessage = loadInventory(playerSource)
    if not inventory then return false, errorMessage end

    local moved, moveError = moveItemSlot(inventory, fromSlot, toSlot)
    if not moved then return false, moveError end
    syncInventory(playerSource)
    return true, { inventory = snapshot(inventory) }, 'Item movido.'
end)

local function transferItemBySlot(playerSource, targetSource, slot, amount, activeWeaponItem, forceEquipped, targetSlot)
    playerSource = validSource(playerSource)
    targetSource = validSource(targetSource)
    if not playerSource or not targetSource then return false, 'Jogador de destino invalido.' end
    if playerSource == targetSource then return false, 'Voce nao pode enviar itens para si mesmo.' end

    local senderPed = GetPlayerPed(playerSource)
    local targetPed = GetPlayerPed(targetSource)
    if not senderPed or senderPed <= 0 or not targetPed or targetPed <= 0 then
        return false, 'Jogador de destino indisponivel.'
    end
    if #(GetEntityCoords(senderPed) - GetEntityCoords(targetPed)) > (ORInventoryConfig.Transfer.Distance + 0.25) then
        return false, ('Aproxime-se do jogador (maximo %.1f m).'):format(ORInventoryConfig.Transfer.Distance)
    end

    local senderInventory, senderError = loadInventory(playerSource)
    if not senderInventory then return false, senderError end
    local targetInventory, targetError = loadInventory(targetSource)
    if not targetInventory then return false, targetError end

    slot = math.floor(tonumber(slot) or 0)
    amount = math.floor(tonumber(amount) or 0)
    local item = senderInventory.items[slot]
    if not item or amount < 1 or amount > item.amount then return false, 'Quantidade indisponivel para enviar.' end
    if forceEquipped ~= true and equippedWeaponMatches(item, activeWeaponItem) then
        return false, 'Guarde a arma antes de envia-la para outro jogador.'
    end

    targetSlot = math.floor(tonumber(targetSlot) or 0)
    local preferredSlot = targetSlot > 0 and targetSlot or nil
    local canReceive, receiveError = canAddItemToInventory(
        targetInventory, item.name, amount, item.metadata or {}, preferredSlot
    )
    if not canReceive then return false, ('O jogador nao pode receber: %s'):format(receiveError) end

    local itemName = item.name
    local metadata = item.metadata or {}
    local removed, removeError = removeItemFromInventory(senderInventory, slot, amount)
    if not removed then return false, removeError end

    local added, addError = addItemToInventory(
        targetInventory, itemName, amount, metadata, preferredSlot, preferredSlot == nil
    )
    if not added then
        local restored, restoreError = addItemToInventory(senderInventory, itemName, amount, metadata, slot)
        if not restored then
            print(('[ob_inventory] CRITICO: falha ao restaurar %sx %s apos transferencia recusada: %s'):format(amount, itemName, tostring(restoreError)))
        end
        return false, addError or 'Nao foi possivel concluir a transferencia.'
    end

    syncInventory(playerSource)
    syncInventory(targetSource)
    return true, { inventory = snapshot(senderInventory) }, ('%sx %s enviado para %s.'):format(amount, itemDefinition(itemName).label, GetPlayerName(targetSource) or ('ID %s'):format(targetSource))
end

OR.Callback.register('transfer', function(playerSource, targetSource, slot, amount, activeWeaponItem)
    local allowed, restrictionError = inventoryActionAllowed(playerSource)
    if not allowed then return false, restrictionError end
    return transferItemBySlot(playerSource, targetSource, slot, amount, activeWeaponItem, false)
end)

OR.Callback.register('pickup', function(playerSource, dropId, itemIndex, amount, targetSlot)
    local allowed, restrictionError = inventoryActionAllowed(playerSource)
    if not allowed then return false, restrictionError end
    local inventory, errorMessage = loadInventory(playerSource)
    if not inventory then return false, errorMessage end

    local drop = groundDrops[type(dropId) == 'string' and dropId or '']
    if not drop or drop.expiresAt <= GetGameTimer() then return false, 'Esse item no chao nao esta mais disponivel.' end
    if not playerNearDrop(playerSource, drop) then return false, 'Aproxime-se do item no chao.' end

    itemIndex = math.floor(tonumber(itemIndex) or 0)
    local item = drop.items[itemIndex]
    amount = math.floor(tonumber(amount) or 0)
    if not item or amount < 1 or amount > item.amount then return false, 'Quantidade invalida.' end

    local added, addError = addItemAtSlot(inventory, item.name, amount, item.metadata, targetSlot)
    if not added then return false, addError end

    item.amount = item.amount - amount
    if item.amount <= 0 then table.remove(drop.items, itemIndex) end
    if #drop.items == 0 then groundDrops[drop.id] = nil end
    broadcastGroundDrops()
    syncInventory(playerSource)
    local response, responseData = inventoryResponse(playerSource, groundDrops[drop.id] and drop.id or nil)
    if not response then return false, responseData end
    return true, responseData, 'Item recolhido.'
end)

OR.Callback.register('use', function(playerSource, slot, activeWeaponItem, amount, loadMaximum)
    local allowed, restrictionError = inventoryActionAllowed(playerSource)
    if not allowed then return false, restrictionError end
    local inventory, errorMessage = loadInventory(playerSource)
    if not inventory then return false, errorMessage end

    slot = math.floor(tonumber(slot) or 0)
    local item = inventory.items[slot]
    if not item then return false, 'Selecione um item valido.' end
    local definition = itemDefinition(item.name)
    if not definition then return false, 'Esse item ainda nao possui uso.' end
    if itemExpired(item) then return false, 'Esse item venceu e nao pode mais ser usado.' end
    if GetResourceState('ob_health') == 'started' then
        local exportOk, canUse, healthError = pcall(function()
            return exports.ob_health:CanUseItem(playerSource, item.name, definition.type)
        end)
        if exportOk and canUse == false then return false, healthError or 'Seus ferimentos impedem o uso desse item.' end
    end

    local quickUse = type(ORInventoryConfig.QuickUse) == 'table' and ORInventoryConfig.QuickUse or {}
    local maximumItems = type(quickUse.CtrlMaximumItems) == 'table' and quickUse.CtrlMaximumItems or {}
    local maximumTypes = type(quickUse.CtrlMaximumTypes) == 'table' and quickUse.CtrlMaximumTypes or {}
    local useMaximum = loadMaximum == true and (maximumItems[item.name] == true or maximumTypes[definition.type] == true)
    local consumeAmount = 1
    if useMaximum and definition.type == 'consumable' then
        consumeAmount = math.min(item.amount, math.max(1, math.floor(tonumber(amount) or item.amount)))
    end

    local used, useError, consumeItem
    local applyArmour = false
    if definition.type == 'medical' then
        if item.name == 'adrenaline' then return false, 'Use a adrenalina olhando para alguem incapacitado.' end
        if GetResourceState('ob_health') ~= 'started' then return false, 'Sistema medico indisponivel.' end
        used, useError = exports.ob_health:UseMedicalItem(playerSource, item.name, playerSource)
    elseif definition.type == 'medical_supply' or item.name == 'emstablet' then
        if GetResourceState('ob_health') ~= 'started' then return false, 'Sistema medico indisponivel.' end
        used, useError = exports.ob_health:BeginMedicalEquipmentUse(playerSource, item.name)
        -- Abrir o exame nao consome material; o tratamento validado pelo health consome.
        consumeItem = false
    elseif definition.type == 'consumable' then
        local effects = {}
        for effectName, effectValue in pairs(type(definition.effects) == 'table' and definition.effects or {}) do
            effects[effectName] = type(effectValue) == 'number' and effectValue * consumeAmount or effectValue
        end
        used, useError = ORInventoryNeeds.ApplyEffects(playerSource, effects)
    elseif definition.type == 'weapon' then
        used, useError, consumeItem = ORInventoryWeaponsModule.UseWeapon(playerSource, item.name, activeWeaponItem, slot)
    elseif definition.type == 'weapon_component' then
        used, useError, consumeItem = ORInventoryWeaponsModule.BeginComponentInstall(playerSource, inventory, slot, item.name, activeWeaponItem)
    elseif definition.type == 'weapon_ammo' then
        used, useError, consumeItem = ORInventoryWeaponsModule.BeginAmmoLoad(playerSource, inventory, slot, item.name, activeWeaponItem, amount, useMaximum)
    elseif definition.type == 'armor' then
        if item.name == 'police_vest' then
            if GetResourceState('ob_org') ~= 'started' then
                return false, 'Sistema de organizacoes indisponivel.'
            end
            local permissionOk, hasPolicePermission = pcall(function()
                return exports.ob_org:HasPermission(playerSource, 'police', false)
            end)
            if not permissionOk or hasPolicePermission ~= true then
                return false, 'Este colete e exclusivo para integrantes da policia.'
            end
        end
        used, useError, consumeItem = true, 'Colete equipado com 100% de protecao.', true
        applyArmour = true
    elseif definition.type == 'backpack' then
        local previousMaxWeight = normalizeMaxWeight(inventory.maxWeight)
        local previousBackpacks = playerBackpackCount(inventory)
        if previousBackpacks >= maximumBackpackCount() then
            return false, ('Voce ja equipou o limite de %s mochilas.'):format(maximumBackpackCount())
        end
        local upgrade = math.max(1, math.floor(tonumber(ORInventoryConfig.BackpackUpgrade) or 10000))
        local nextBackpacks = previousBackpacks + 1
        local nextMaxWeight = math.min(maximumBackpackWeight(), baseMaxWeight() + (nextBackpacks * upgrade))

        local previousAmount = item.amount
        item.amount = item.amount - 1
        if item.amount <= 0 then inventory.items[slot] = nil end
        inventory.maxWeight = nextMaxWeight
        inventory.backpacks = nextBackpacks
        local saved, saveError = persistInventory(inventory)
        if not saved then
            inventory.maxWeight = previousMaxWeight
            inventory.backpacks = previousBackpacks
            item.amount = previousAmount
            inventory.items[slot] = item
            return false, saveError or 'Nao foi possivel equipar a mochila.'
        end
        used, useError, consumeItem = true, ('Mochila equipada: %s slots e %.0f kg.'):format(inventorySlotCount(inventory), nextMaxWeight / 1000), false
    elseif definition.type == 'mechanic_repair' then
        if GetResourceState('ob_mecanico') ~= 'started' then return false, 'Sistema mecanico indisponivel.' end
        TriggerClientEvent('ob_mecanico:client:useRepairKit', playerSource, slot, item.name)
        used, consumeItem = true, false
    elseif definition.type == 'mechanic_tyre' then
        if GetResourceState('ob_mecanico') ~= 'started' then return false, 'Sistema mecanico indisponivel.' end
        TriggerClientEvent('ob_mecanico:client:useTyreKit', playerSource, slot, item.name)
        used, consumeItem = true, false
    elseif definition.type == 'vehicle_tyre' then
        return false, 'Nao use o pneu pelo inventario. Com o macaco e a chave, aperte E na seta azul da roda furada.'
    elseif definition.type == 'mechanic_jack' then
        if GetResourceState('ob_mecanico') ~= 'started' then return false, 'Sistema mecanico indisponivel.' end
        TriggerClientEvent('ob_mecanico:client:useJack', playerSource)
        used, useError, consumeItem = true, 'Use o macaco perto de um veiculo.', false
    elseif definition.type == 'mechanic_oil' or definition.type == 'mechanic_brakes' or definition.type == 'mechanic_spark' then
        if GetResourceState('ob_fuel') ~= 'started' then return false, 'Sistema de manutencao indisponivel.' end
        TriggerClientEvent('ob_fuel:client:useMaintenancePart', playerSource, slot, item.name, definition.type)
        used, consumeItem = true, false
    elseif definition.type == 'vehicle_diagnostics' then
        if GetResourceState('ob_fuel') ~= 'started' then return false, 'Sistema de manutencao indisponivel.' end
        TriggerClientEvent('ob_fuel:client:inspectVehicle', playerSource)
        used, useError, consumeItem = true, 'Leitor de odometro aberto.', false
    elseif definition.type == 'police_restraint' or definition.type == 'police_restraint_key' then
        if GetResourceState('ob_police') ~= 'started' then return false, 'Sistema de algemas indisponivel.' end
        local started, restraintError = exports.ob_police:BeginItemUse(playerSource, item.name)
        if not started then return false, restraintError or 'Nao foi possivel usar esse item.' end
        used, useError, consumeItem = true, restraintError or 'Uso da algema iniciado.', false
    elseif definition.type == 'lockpick' then
        if GetResourceState('ob_minigame') ~= 'started' then return false, 'Minigame indisponivel.' end
        if GetResourceState('ob_police') == 'started' then
            local started, restraintError, handled = exports.ob_police:BeginItemUse(playerSource, item.name, slot)
            if handled == true then
                if not started then return false, restraintError or 'Nao foi possivel usar a lockpick.' end
                used, useError, consumeItem = true, restraintError or 'Arrombamento da algema iniciado.', false
            end
        end
        if used ~= true and (GetResourceState('ob_vehiclekeys') ~= 'started' or GetResourceState('ob_minigame') ~= 'started') then
            return false, 'Sistema de arrombamento indisponivel.'
        end
        if used ~= true then
            local started, lockpickError = exports.ob_vehiclekeys:BeginLockpick(playerSource, item.name, slot)
            if not started then return false, lockpickError or 'Nao foi possivel iniciar o arrombamento.' end
            -- O item e removido somente quando o minigame for concluido no servidor.
            used, useError, consumeItem = true, 'Aproxime-se de um veiculo trancado.', false
        end
    elseif definition.type == 'vehicle_key' then
        if GetResourceState('ob_vehiclekeys') ~= 'started' then return false, 'Sistema de chaves indisponivel.' end
        used, useError, consumeItem = true, 'Use L perto do veiculo correspondente a esta chave.', false
    elseif definition.type == 'document' then
        if item.name ~= 'driver_license' or GetResourceState('ob_licenca') ~= 'started' then
            return false, 'Este documento ainda nao possui visualizacao.'
        end
        used, useError = exports.ob_licenca:UseInventoryDocument(playerSource, item.name, item.metadata or {})
        consumeItem = false
    elseif definition.type == 'forensic_kit' then
        if GetResourceState('ob_evidence') ~= 'started' then return false, 'Sistema de pericia indisponivel.' end
        local started, forensicError = exports.ob_evidence:UseForensicKit(playerSource, slot)
        if not started then return false, forensicError or 'Nao foi possivel iniciar a pericia.' end
        used, useError, consumeItem = true, forensicError or 'Selecione uma arma equipada para examinar.', false
    elseif definition.type == 'forensic_field_kit' then
        if GetResourceState('ob_evidence') ~= 'started' then return false, 'Sistema de pericia indisponivel.' end
        local started, forensicError = exports.ob_evidence:UseFieldKit(playerSource, item.name, slot)
        if not started then return false, forensicError or 'Nao foi possivel iniciar o teste.' end
        used, useError, consumeItem = true, forensicError or 'Selecione uma pessoa proxima.', false
    elseif definition.type == 'forensic_magnifier' then
        if GetResourceState('ob_evidence') ~= 'started' then return false, 'Sistema de pericia indisponivel.' end
        local toggled, magnifierError = exports.ob_evidence:ToggleMagnifier(playerSource)
        if not toggled then return false, magnifierError or 'Nao foi possivel usar a lupa.' end
        used, useError, consumeItem = true, magnifierError, false
    elseif definition.type == 'drug' then
        if GetResourceState('ob_evidence') == 'started' then
            exports.ob_evidence:MarkDrugUse(playerSource, item.name, 'inventory_use')
        end
        used, useError, consumeItem = true, ('Voce consumiu %s.'):format(definition.label or item.name), true
    elseif definition.type == 'phone' then
        if GetResourceState('ob_phone') ~= 'started' then return false, 'Sistema de celular indisponivel.' end
        TriggerClientEvent('ob_phone:client:open', playerSource, slot)
        used, useError, consumeItem = true, 'Celular aberto.', false
    elseif definition.type == 'powerbank' then
        if GetResourceState('ob_phone') ~= 'started' then return false, 'Sistema de celular indisponivel.' end
        TriggerClientEvent('ob_phone:client:charge', playerSource, slot)
        used, useError, consumeItem = true, 'Powerbank conectado ao celular.', false
    elseif definition.type == 'phone_sim' then
        if GetResourceState('ob_phone') ~= 'started' then return false, 'Sistema de celular indisponivel.' end
        TriggerClientEvent('ob_phone:client:useSimChip', playerSource, slot)
        used, useError, consumeItem = true, 'Digite o novo numero no celular.', false
    elseif definition.type == 'phone_signal' then
        if GetResourceState('ob_phone') ~= 'started' then return false, 'Sistema de celular indisponivel.' end
        used, useError = exports.ob_phone:UseSignalItem(playerSource, item.name, slot)
    elseif definition.type == 'drug_planting' then
        if GetResourceState('ob_drugplants') ~= 'started' then return false, 'Sistema de cultivo indisponivel.' end
        used, useError, consumeItem = exports.ob_drugplants:UseItem(playerSource, item.name, slot)
    elseif definition.type == 'blackout_control' then
        if GetResourceState('ob_blackout') ~= 'started' then return false, 'Sistema de energia indisponivel.' end
        used, useError, consumeItem = exports.ob_blackout:UseItem(playerSource, item.name)
    elseif definition.type == 'parachute' then
        TriggerClientEvent('ob_inventory:client:equipParachute', playerSource)
        -- Paraquedas e de uso unico: o item vira o gadget do GTA e e
        -- consumido assim que for equipado.
        used, useError, consumeItem = true, 'Paraquedas equipado nas costas.'
    elseif definition.type == 'medical_stretcher' then
        if GetResourceState('ob_health') ~= 'started' then return false, 'Sistema medico indisponivel.' end
        used, useError = exports.ob_health:DeployStretcherItem(playerSource)
    else
        return false, 'Esse item ainda nao possui uso.'
    end
    if not used then return false, useError end

    if consumeItem ~= false then
        local removed, removeError = removeItemFromInventory(inventory, slot, consumeAmount)
        if not removed then return false, removeError end
    end
    syncInventory(playerSource)
    if applyArmour then
        TriggerClientEvent('ob_inventory:client:applyArmour', playerSource, 100)
    end
    local successMessage = consumeAmount > 1
        and ('%sx %s utilizado.'):format(consumeAmount, definition.label)
        or ('%s utilizado.'):format(definition.label)
    return true, { inventory = snapshot(inventory) }, useError or successMessage
end)

OR.Callback.register('hasPhone', function(playerSource)
    return (ORInventory.GetItemCount(playerSource, 'phone') or 0) > 0
end)

OR.Callback.register('phoneItem', function(playerSource)
    local inventory = loadInventory(playerSource)
    for slot, item in pairs(inventory and inventory.items or {}) do
        if item.name == 'phone' then
            return true, { slot = tonumber(item.slot) or tonumber(slot), metadata = item.metadata or {} }
        end
    end
    return false, 'Voce precisa de um celular na mochila.'
end)

-- Kits mecanicos so saem da mochila depois que o cliente conclui o minigame
-- e a animacao. Assim falhar/cancelar nunca consome a peca.
RegisterNetEvent('ob_inventory:server:mechanicUseResult', function(slot, itemName, completed)
    local playerSource = validSource(source)
    if not playerSource or completed ~= true then return end
    if not OR.Security.rateLimit(playerSource, 'inventory:mechanic_result', 3, 10000) then return end
    local inventory = loadInventory(playerSource)
    slot = math.floor(tonumber(slot) or 0)
    local item = inventory and inventory.items[slot]
    local definition = item and itemDefinition(item.name)
    if not item or item.name ~= tostring(itemName or ''):lower() then return end
    if not definition or (definition.type ~= 'mechanic_repair' and definition.type ~= 'mechanic_tyre'
        and definition.type ~= 'mechanic_oil' and definition.type ~= 'mechanic_brakes' and definition.type ~= 'mechanic_spark') then return end
    local removed, errorMessage = removeItemFromInventory(inventory, slot, 1)
    if not removed then return end
    syncInventory(playerSource)
end)

OR.Callback.register('hasTargetTyre', function(playerSource, itemName)
    itemName = tostring(itemName or ''):lower()
    return (itemName == 'tyre_normal' or itemName == 'tyre_armored') and (ORInventory.GetItemCount(playerSource, itemName) or 0) > 0
end)

RegisterNetEvent('ob_inventory:server:componentInstallResult', function(slot, itemName, weaponItemName, installed)
    local playerSource = validSource(source)
    if not playerSource then return end
    if not OR.Security.rateLimit(playerSource, 'inventory:component_result', 4, 10000) then return end

    local pending, pendingError = ORInventoryWeaponsModule.TakePendingComponent(playerSource, slot, itemName, weaponItemName, installed)
    if not pending then
        TriggerClientEvent('ob_notification:client:notify', playerSource, pendingError or 'A instalacao nao foi concluida.', 'error')
        return
    end
    if installed ~= true then
        TriggerClientEvent('ob_notification:client:notify', playerSource, 'O acessorio nao pode ser instalado nessa arma.', 'error')
        return
    end

    local inventory, inventoryError = loadInventory(playerSource)
    if not inventory then
        TriggerClientEvent('ob_notification:client:notify', playerSource, inventoryError or 'Inventario indisponivel.', 'error')
        return
    end
    local item = inventory.items[pending.slot]
    if not item or item.name ~= pending.itemName or item.amount < 1 then
        TriggerClientEvent('ob_notification:client:notify', playerSource, 'Esse acessorio nao esta mais no inventario.', 'error')
        return
    end

    local removed, removeError = removeItemFromInventory(inventory, pending.slot, 1)
    if not removed then
        TriggerClientEvent('ob_notification:client:notify', playerSource, removeError or 'Nao foi possivel consumir o acessorio.', 'error')
        return
    end
    syncInventory(playerSource)
end)

RegisterNetEvent('ob_inventory:server:ammoLoadResult', function(slot, itemName, weaponItemName, loadedAmount, finalTotal, finalClip)
    local playerSource = validSource(source)
    if not playerSource then return end
    if not OR.Security.rateLimit(playerSource, 'inventory:ammo_result', 6, 10000) then return end

    local pending, usedAmount, pendingError = ORInventoryWeaponsModule.TakePendingAmmo(playerSource, slot, itemName, weaponItemName, loadedAmount)
    if not pending then
        TriggerClientEvent('ob_notification:client:notify', playerSource, usedAmount or pendingError or 'O carregamento nao foi concluido.', 'error')
        return
    end

    local inventory, inventoryError = loadInventory(playerSource)
    if not inventory then
        TriggerClientEvent('ob_notification:client:notify', playerSource, inventoryError or 'Inventario indisponivel.', 'error')
        return
    end
    local item = inventory.items[pending.slot]
    if not item or item.name ~= pending.itemName or item.amount < usedAmount then
        TriggerClientEvent('ob_notification:client:notify', playerSource, 'Essa municao nao esta mais no inventario.', 'error')
        return
    end

    local removed, removeError = removeItemFromInventory(inventory, pending.slot, usedAmount)
    if not removed then
        TriggerClientEvent('ob_notification:client:notify', playerSource, removeError or 'Nao foi possivel consumir a municao.', 'error')
        return
    end
    -- O carregamento foi validado pelo servidor; ele e a unica operacao que
    -- pode aumentar a municao persistida da arma.
    for _, weaponItem in pairs(inventory.items) do
        if weaponItem.name == pending.weaponItemName then
            weaponItem.metadata = type(weaponItem.metadata) == 'table' and weaponItem.metadata or {}
            local savedAmmo = type(weaponItem.metadata.weaponAmmo) == 'table' and weaponItem.metadata.weaponAmmo or {}
            local savedTotal = math.max(0, math.floor(tonumber(savedAmmo.total) or 0))
            local savedClip = math.min(savedTotal, math.max(0, math.floor(tonumber(savedAmmo.clip) or 0)))
            local maximumAuthorizedTotal = savedTotal + usedAmount
            finalTotal = math.max(0, math.floor(tonumber(finalTotal) or maximumAuthorizedTotal))
            finalClip = math.max(0, math.floor(tonumber(finalClip) or (savedClip + usedAmount)))
            weaponItem.metadata.weaponAmmo = {
                total = math.min(finalTotal, maximumAuthorizedTotal),
                clip = math.min(finalClip, finalTotal, savedClip + usedAmount, maximumAuthorizedTotal),
            }
            break
        end
    end
    persistInventory(inventory)
    syncInventory(playerSource)
end)

-- O cliente so pode reduzir a municao ja registrada pelo servidor. Assim os
-- disparos persistem, mas esse evento nunca pode ser usado para criar balas.
RegisterNetEvent('ob_inventory:server:saveWeaponAmmo', function(weaponItemName, total, clip, slot)
    local playerSource = validSource(source)
    weaponItemName = tostring(weaponItemName or ''):lower()
    total, clip = math.max(0, math.floor(tonumber(total) or 0)), math.max(0, math.floor(tonumber(clip) or 0))
    if not playerSource or clip > total or not ORInventoryWeapons.Weapons[weaponItemName] then return end
    if not OR.Security.rateLimit(playerSource, 'inventory:save_ammo', 12, 10000) then return end

    local inventory = loadInventory(playerSource)
    if not inventory then return end
    slot = math.floor(tonumber(slot) or 0)
    local slots = slot > 0 and { slot } or {}
    if #slots == 0 then for inventorySlot in pairs(inventory.items) do slots[#slots + 1] = inventorySlot end end
    for _, inventorySlot in ipairs(slots) do
        local weaponItem = inventory.items[inventorySlot]
        if weaponItem and weaponItem.name == weaponItemName and itemDefinition(weaponItem.name) and itemDefinition(weaponItem.name).type == 'weapon' then
            weaponItem.metadata = type(weaponItem.metadata) == 'table' and weaponItem.metadata or {}
            local hasSavedAmmo = type(weaponItem.metadata.weaponAmmo) == 'table'
            local saved = hasSavedAmmo and weaponItem.metadata.weaponAmmo or {}
            local allowed = math.max(0, math.floor(tonumber(saved.total) or 0))
            -- Armas criadas antes desta atualizacao ainda nao possuem estado
            -- salvo. Aceitamos somente essa primeira sincronizacao para migrar
            -- a municao existente; depois disso o cliente so pode reduzi-la.
            if hasSavedAmmo and total > allowed then return end
            weaponItem.metadata.weaponAmmo = { total = total, clip = clip }
            persistInventory(inventory)
            return
        end
    end
end)

local function useMedicalItem(playerSource, itemName, targetSource)
    local inventory, errorMessage = loadInventory(playerSource)
    if not inventory then return false, errorMessage end

    local selectedSlot
    for slot, item in pairs(inventory.items) do
        if item.name == itemName and item.amount > 0 then selectedSlot = slot break end
    end
    if not selectedSlot then return false, 'Voce nao possui esse item.' end
    if GetResourceState('ob_health') ~= 'started' then return false, 'Sistema medico indisponivel.' end

    local used, useError = exports.ob_health:UseMedicalItem(playerSource, itemName, targetSource)
    if not used then return false, useError end

    local removed, removeError = removeItemFromInventory(inventory, selectedSlot, 1)
    if not removed then return false, removeError end
    syncInventory(playerSource)
    return true, 'Adrenalina utilizada; jogador reanimado.'
end

exports('UseMedicalItem', useMedicalItem)
exports('ResetAfterDeath', function(playerSource)
    local inventory, errorMessage = loadInventory(playerSource)
    if not inventory then return false, errorMessage end

    local previousItems = inventory.items
    local previousMaxWeight = inventory.maxWeight
    local previousBackpacks = playerBackpackCount(inventory)
    inventory.items = {}
    inventory.maxWeight = baseMaxWeight()
    inventory.backpacks = 0
    local saved, saveError = persistInventory(inventory)
    if not saved then
        inventory.items = previousItems
        inventory.maxWeight = previousMaxWeight
        inventory.backpacks = previousBackpacks
        return false, saveError or 'Nao foi possivel limpar o inventario apos a morte.'
    end

    syncInventory(playerSource)
    TriggerClientEvent('ob_inventory:client:clearWeapons', playerSource)
    return true
end)
function ORInventory.AddItem(playerSource, itemName, amount, metadata, preferredSlot)
    local inventory, errorMessage = loadInventory(playerSource)
    if not inventory then return false, errorMessage end
    local added, addError = addItemToInventory(inventory, itemName, math.floor(tonumber(amount) or 1), metadata, preferredSlot)
    if added then
        syncInventory(playerSource)
        if itemName == 'phone' and (type(metadata) ~= 'table' or not metadata.deviceId) and GetResourceState('ob_phone') == 'started' then
            exports.ob_phone:ActivateNewPhone(playerSource, preferredSlot)
        end
    end
    return added, addError
end

function ORInventory.AddItemAtSlot(playerSource, itemName, amount, metadata, targetSlot)
    local inventory, errorMessage = loadInventory(playerSource)
    if not inventory then return false, errorMessage end
    local added, addError = addItemAtSlot(inventory, itemName, math.floor(tonumber(amount) or 1), metadata, targetSlot)
    if added then
        syncInventory(playerSource)
        if itemName == 'phone' and (type(metadata) ~= 'table' or not metadata.deviceId) and GetResourceState('ob_phone') == 'started' then
            exports.ob_phone:ActivateNewPhone(playerSource, targetSlot)
        end
    end
    return added, addError
end

function ORInventory.GetItemCount(playerSource, itemName)
    local inventory, errorMessage = loadInventory(playerSource)
    if not inventory then return nil, errorMessage end
    itemName = type(itemName) == 'string' and itemName:lower() or ''
    if not itemDefinition(itemName) then return nil, 'Item invalido.' end
    return countItemInInventory(inventory, itemName)
end

function ORInventory.CanCarryItem(playerSource, itemName, amount, metadata, preferredSlot)
    local inventory, errorMessage = loadInventory(playerSource)
    if not inventory then return false, errorMessage end
    itemName = type(itemName) == 'string' and itemName:lower() or ''
    amount = math.floor(tonumber(amount) or 0)
    if type(metadata) == 'number' and preferredSlot == nil then preferredSlot, metadata = metadata, nil end
    if amount < 1 then return false, 'Quantidade invalida.' end
    local definition = itemDefinition(itemName)
    if not definition then return false, 'Item invalido.' end
    local received = { name = itemName, metadata = decodeMetadata(metadata) }
    ensureDurability(received, definition)
    return canAddItemToInventory(inventory, itemName, amount, received.metadata, preferredSlot)
end

function ORInventory.RemoveItem(playerSource, itemName, amount)
    return removeItemByName(playerSource, itemName, amount)
end

-- Atualiza um item unico sem remove-lo/recria-lo. O filtro impede que um
-- documento pertencente a outro personagem seja alterado depois de transferido.
function ORInventory.UpdateItemMetadata(playerSource, itemName, metadata, matchMetadata)
    local inventory, errorMessage = loadInventory(playerSource)
    if not inventory then return false, errorMessage end
    itemName = type(itemName) == 'string' and itemName:lower() or ''
    local definition = itemDefinition(itemName)
    if not definition or type(metadata) ~= 'table' then return false, 'Item ou metadata invalida.' end
    matchMetadata = type(matchMetadata) == 'table' and matchMetadata or {}
    local slots = {}
    for slot in pairs(inventory.items) do slots[#slots + 1] = slot end
    table.sort(slots)
    for _, slot in ipairs(slots) do
        local item = inventory.items[slot]
        if item and item.name == itemName then
            local matches = true
            for key, value in pairs(matchMetadata) do
                if tostring((item.metadata or {})[key]) ~= tostring(value) then matches = false break end
            end
            if matches then
                local previous = item.metadata
                item.metadata = decodeMetadata(metadata)
                ensureDurability(item, definition)
                local saved, saveError = persistInventory(inventory)
                if not saved then item.metadata = previous return false, saveError end
                syncInventory(playerSource)
                return true, slot
            end
        end
    end
    return false, 'Item nao encontrado.'
end

exports('AddItem', ORInventory.AddItem)
exports('AddItemAtSlot', ORInventory.AddItemAtSlot)
exports('GetItemCount', ORInventory.GetItemCount)
-- Desgaste no proprio inventario. Nunca devolve/adiciona ferramentas por falha.
local lockpickUseBusy = {}
exports('ConsumeLockpickUse', function(playerSource, itemName, slot)
    playerSource = validSource(playerSource)
    local definition = itemDefinition(itemName)
    if not playerSource or not definition or definition.type ~= 'lockpick' then return false, 'Lockpick invalida.' end
    if lockpickUseBusy[playerSource] then return false, 'Aguarde o uso anterior da ferramenta.' end
    lockpickUseBusy[playerSource] = true
    local ok, used, result = pcall(function()
        local inventory, errorMessage = loadInventory(playerSource)
        if not inventory then return false, errorMessage end
        slot = math.floor(tonumber(slot) or 0)
        local item = inventory.items[slot]
        if not item or item.name ~= itemName or item.amount < 1 then return false, 'A lockpick foi movida ou nao esta mais na mochila.' end
        local maximum = math.max(1, math.floor(tonumber(definition.maxUses) or 3))
        local previousMetadata = item.metadata
        local metadata = decodeMetadata(json.encode(previousMetadata or {}))
        local remaining = math.max(0, math.min(maximum, math.floor(tonumber(metadata.usesRemaining) or maximum))) - 1
        local previousAmount, splitSlot = item.amount, nil
        if remaining > 0 and item.amount > 1 then
            splitSlot = firstFreeSlot(inventory)
            if not splitSlot then return false, 'Libere um slot para separar a lockpick usada da pilha antiga.' end
        end
        if remaining <= 0 then
            item.amount = item.amount - 1
            if item.amount == 0 then inventory.items[slot] = nil
            else item.metadata = decodeMetadata(json.encode(previousMetadata or {})); item.metadata.usesRemaining = nil end
        elseif splitSlot then
            item.amount = item.amount - 1
            metadata.usesRemaining = remaining
            inventory.items[splitSlot] = { slot = splitSlot, name = itemName, amount = 1, metadata = metadata }
        else
            metadata.usesRemaining = remaining
            item.metadata = metadata
        end
        local saveOk, saved, saveError = pcall(persistInventory, inventory)
        if not saveOk or not saved then
            item.amount, item.metadata = previousAmount, previousMetadata
            inventory.items[slot] = item
            if splitSlot then inventory.items[splitSlot] = nil end
            return false, saveOk and saveError or 'Falha ao salvar o desgaste da lockpick.'
        end
        syncInventory(playerSource)
        return true, math.max(0, remaining)
    end)
    lockpickUseBusy[playerSource] = nil
    if not ok then return false, 'Nao foi possivel registrar o desgaste da lockpick.' end
    return used, result
end)
exports('RemoveItem', ORInventory.RemoveItem)
exports('UpdateItemMetadata', ORInventory.UpdateItemMetadata)
exports('CanCarryItem', ORInventory.CanCarryItem)
exports('GetInventory', function(playerSource)
    local inventory, errorMessage = loadInventory(playerSource)
    return inventory and snapshot(inventory) or nil, errorMessage
end)

-- Integracao por slot para itens unicos. Evita que recursos consumidores
-- removam acidentalmente a primeira unidade de outro slot.
exports('GetItemAtSlot', function(playerSource, slot)
    local inventory, errorMessage = loadInventory(playerSource)
    if not inventory then return nil, errorMessage end
    local item = itemAtSlot(inventory, slot)
    if not item then return nil, 'Item nao encontrado.' end
    return decodeMetadata(json.encode(item))
end)

exports('UpdateItemMetadataAtSlot', function(playerSource, slot, expectedName, metadata)
    local inventory, errorMessage = loadInventory(playerSource)
    if not inventory then return false, errorMessage end
    local item = itemAtSlot(inventory, slot)
    expectedName = tostring(expectedName or ''):lower()
    if not item or item.name ~= expectedName or type(metadata) ~= 'table' then
        return false, 'O item foi movido ou nao esta mais nesse slot.'
    end
    local previous = item.metadata
    item.metadata = decodeMetadata(metadata)
    ensureDurability(item, itemDefinition(item.name))
    local saved, saveError = persistInventory(inventory)
    if not saved then item.metadata = previous return false, saveError end
    syncInventory(playerSource)
    return true
end)

exports('MarkWeaponUsed', function(playerSource, slot, expectedName)
    playerSource,slot=validSource(playerSource),math.floor(tonumber(slot) or 0)
    local inventory=playerSource and loadInventory(playerSource)
    local item=inventory and itemAtSlot(inventory,slot)
    local definition=item and itemDefinition(item.name)
    expectedName=tostring(expectedName or ''):lower()
    if not item or item.name~=expectedName or not definition or definition.type~='weapon' then
        return nil,'Arma equipada nao corresponde ao inventario.'
    end
    local uid=getUserId(playerSource)
    if not uid then return nil,'Personagem indisponivel.' end
    local now=os.time()
    item.metadata=type(item.metadata)=='table' and item.metadata or {}
    local fingerprintHash=joaat(('ob:%s'):format(uid))
    if fingerprintHash<0 then fingerprintHash=fingerprintHash+4294967296 end
    local fingerprint=('FP-%08X'):format(fingerprintHash)
    local last=item.metadata.lastFingerprint
    local key=('%s:%s'):format(uid,slot)
    local metadataChanged=false
    if type(item.metadata.ballisticSignature)~='string' or item.metadata.ballisticSignature=='' then
        item.metadata.ballisticSignature=('OBB-%s-%s-%08d'):format(now,tostring(uid),math.random(0,99999999))
        metadataChanged=true
    end
    if not weaponUseSync[key] or weaponUseSync[key]+30<=now or type(last)~='table' or tonumber(last.userId)~=tonumber(uid) then
        item.metadata.lastFingerprint={userId=uid,name=exports.ob_core:GetFullName(playerSource) or GetPlayerName(playerSource) or 'Desconhecido',
            code=fingerprint,at=now}
        metadataChanged=true
        weaponUseSync[key]=now
    end
    if metadataChanged then
        local saved,saveError=persistInventory(inventory)
        if not saved then return nil,saveError end
    end
    local weapon=ORInventoryWeapons and ORInventoryWeapons.Weapons and ORInventoryWeapons.Weapons[item.name]
    return {itemName=item.name,label=definition.label,ammoType=weapon and weapon.ammoType or 'desconhecida',
        metadata=decodeMetadata(json.encode(item.metadata)),fingerprint=fingerprint}
end)

exports('InspectWeaponAtSlot', function(playerSource, slot, expectedName)
    playerSource,slot=validSource(playerSource),math.floor(tonumber(slot) or 0)
    local inventory=playerSource and loadInventory(playerSource)
    local item=inventory and itemAtSlot(inventory,slot)
    local definition=item and itemDefinition(item.name)
    expectedName=tostring(expectedName or ''):lower()
    if not item or (expectedName~='' and item.name~=expectedName) or not definition or definition.type~='weapon' then
        return nil,'Arma nao encontrada nesse slot.'
    end
    local weapon=ORInventoryWeapons and ORInventoryWeapons.Weapons and ORInventoryWeapons.Weapons[item.name]
    return {itemName=item.name,label=definition.label,ammoType=weapon and weapon.ammoType or 'desconhecida',
        metadata=decodeMetadata(json.encode(item.metadata or {}))}
end)

exports('LookupWeaponSerial', function(serial)
    serial=tostring(serial or ''):sub(1,64)
    if serial=='' then return nil end
    return OR.Database.single.await([[SELECT serial,item_name,purchaser_user_id,purchaser_name,shop_id,
        UNIX_TIMESTAMP(purchased_at) AS purchased_at FROM ob_weapon_registry WHERE serial=? LIMIT 1]],{serial})
end)

exports('ConsumeItemAtSlot', function(playerSource, slot, expectedName, amount)
    local inventory, errorMessage = loadInventory(playerSource)
    if not inventory then return false, errorMessage end
    local item = itemAtSlot(inventory, slot)
    expectedName = tostring(expectedName or ''):lower()
    if not item or item.name ~= expectedName then
        return false, 'O item foi movido ou nao esta mais nesse slot.'
    end
    local removed, removeError = removeItemFromInventory(inventory, slot, math.max(1, math.floor(tonumber(amount) or 1)))
    if not removed then return false, removeError end
    syncInventory(playerSource)
    return true
end)

-- Inventarios pertencentes a recursos (baus, porta-malas etc.) usam a mesma
-- persistencia dos personagens. O recurso chamador continua responsavel por
-- validar permissao e distancia antes de chamar estas exports.
exports('GetOwnedInventory', function(ownerType, ownerId, slots, maxWeight)
    local inventory, errorMessage = loadOwnedInventory(ownerType, ownerId, slots, maxWeight)
    return inventory and snapshot(inventory) or nil, errorMessage
end)

exports('TransferToOwned', function(playerSource, ownerType, ownerId, slots, maxWeight, playerSlot, amount, targetSlot, activeWeaponItem, expectedItem)
    local allowed, restrictionError = inventoryActionAllowed(playerSource)
    if not allowed then return false, restrictionError end
    local playerInventory, playerError = loadInventory(playerSource)
    if not playerInventory then return false, playerError end
    local ownedInventory, ownedError = loadOwnedInventory(ownerType, ownerId, slots, maxWeight)
    if not ownedInventory then return false, ownedError end

    playerSlot = math.floor(tonumber(playerSlot) or 0)
    targetSlot = math.floor(tonumber(targetSlot) or 0)
    amount = math.floor(tonumber(amount) or 0)
    local item = playerInventory.items[playerSlot]
    if not item or amount < 1 or amount > item.amount then return false, 'Quantidade indisponivel.' end
    if type(expectedItem) == 'table' and (item.name ~= expectedItem.name
        or tostring((item.metadata or {}).key_id) ~= tostring(expectedItem.keyId)) then
        return false, 'A chave mudou de slot; tente novamente.'
    end
    if equippedWeaponMatches(item, activeWeaponItem) then return false, 'Guarde a arma antes de coloca-la no bau.' end
    local preferredSlot = targetSlot > 0 and targetSlot or nil
    local canReceive, receiveError = canAddItemToInventory(ownedInventory, item.name, amount, item.metadata or {}, preferredSlot)
    if not canReceive then return false, receiveError end

    local itemName, metadata = item.name, item.metadata or {}
    local audit = { name = itemName, label = itemDefinition(itemName).label, amount = amount, metadata = metadata }
    local removed, removeError = removeItemFromInventory(playerInventory, playerSlot, amount)
    if not removed then return false, removeError end
    local added, addError = addItemToInventory(ownedInventory, itemName, amount, metadata, preferredSlot)
    if not added then
        local restored, restoreError = addItemToInventory(playerInventory, itemName, amount, metadata, playerSlot)
        if not restored then
            print(('[ob_inventory] CRITICO: falha ao restaurar %sx %s apos deposito recusado: %s'):format(amount, itemName, tostring(restoreError)))
        end
        return false, addError or 'Nao foi possivel concluir o deposito.'
    end
    syncInventory(tonumber(playerSource))
    return true, { inventory = snapshot(playerInventory), owned = snapshot(ownedInventory), item = audit }
end)

exports('TransferFromOwned', function(playerSource, ownerType, ownerId, slots, maxWeight, ownedSlot, amount, targetSlot)
    local allowed, restrictionError = inventoryActionAllowed(playerSource)
    if not allowed then return false, restrictionError end
    local playerInventory, playerError = loadInventory(playerSource)
    if not playerInventory then return false, playerError end
    local ownedInventory, ownedError = loadOwnedInventory(ownerType, ownerId, slots, maxWeight)
    if not ownedInventory then return false, ownedError end

    ownedSlot = math.floor(tonumber(ownedSlot) or 0)
    targetSlot = math.floor(tonumber(targetSlot) or 0)
    amount = math.floor(tonumber(amount) or 0)
    local item = ownedInventory.items[ownedSlot]
    if not item or amount < 1 or amount > item.amount then return false, 'Quantidade indisponivel.' end
    local preferredSlot = targetSlot > 0 and targetSlot or nil
    local canReceive, receiveError = canAddItemToInventory(playerInventory, item.name, amount, item.metadata or {}, preferredSlot)
    if not canReceive then return false, receiveError end

    local itemName, metadata = item.name, item.metadata or {}
    local audit = { name = itemName, label = itemDefinition(itemName).label, amount = amount, metadata = metadata }
    local removed, removeError = removeItemFromInventory(ownedInventory, ownedSlot, amount)
    if not removed then return false, removeError end
    local added, addError = addItemToInventory(playerInventory, itemName, amount, metadata, preferredSlot, preferredSlot == nil)
    if not added then
        local restored, restoreError = addItemToInventory(ownedInventory, itemName, amount, metadata, ownedSlot)
        if not restored then
            print(('[ob_inventory] CRITICO: falha ao restaurar %sx %s apos retirada recusada: %s'):format(amount, itemName, tostring(restoreError)))
        end
        return false, addError or 'Nao foi possivel concluir a retirada.'
    end
    syncInventory(tonumber(playerSource))
    return true, { inventory = snapshot(playerInventory), owned = snapshot(ownedInventory), item = audit }
end)

exports('MoveOwnedItem', function(ownerType, ownerId, slots, maxWeight, fromSlot, toSlot)
    local inventory, errorMessage = loadOwnedInventory(ownerType, ownerId, slots, maxWeight)
    if not inventory then return false, errorMessage end
    local moved, moveError = moveItemSlot(inventory, fromSlot, toSlot)
    return moved, moved and snapshot(inventory) or moveError
end)

-- Operacoes exclusivamente servidor para finalizar chaves sem devolve-las ao jogador.
exports('RemoveOwnedItem', function(ownerType, ownerId, slots, maxWeight, slot, itemName, keyId)
    local inventory, err = loadOwnedInventory(ownerType, ownerId, slots, maxWeight)
    if not inventory then return false, err end
    slot = tonumber(slot)
    local item = slot and inventory.items[slot]
    if not item then return true end
    if item.name ~= itemName or tostring((item.metadata or {}).key_id) ~= tostring(keyId) then
        return false, 'O item protegido nao corresponde a chave.'
    end
    return removeItemFromInventory(inventory, slot, item.amount)
end)

exports('RemoveVehicleKeyItems', function(playerSource, itemName, keyIds)
    local inventory, err = loadInventory(playerSource)
    if not inventory then return false, err end
    local allowed, removed = {}, 0
    for _, id in ipairs(type(keyIds) == 'table' and keyIds or {}) do allowed[tostring(id)] = true end
    -- Remove apenas chaves desta identidade; nunca limpa outras chaves da mochila.
    local selected = {}
    for slot, item in pairs(inventory.items) do
        if item.name == itemName and allowed[tostring((item.metadata or {}).key_id)] then selected[#selected + 1] = slot end
    end
    for _, slot in ipairs(selected) do
        local item = inventory.items[slot]
        if item and item.name == itemName and allowed[tostring((item.metadata or {}).key_id)] then
            local ok, message = removeItemFromInventory(inventory, slot, item.amount)
            if not ok then syncInventory(playerSource); return false, message end
            removed = removed + 1
        end
    end
    if removed > 0 then syncInventory(playerSource) end
    return true
end)

exports('DiscardPlayerItem', function(playerSource, playerSlot, amount, activeWeaponItem)
    local allowed, restrictionError = inventoryActionAllowed(playerSource)
    if not allowed then return false, restrictionError end
    local inventory, errorMessage = loadInventory(playerSource)
    if not inventory then return false, errorMessage end
    playerSlot = math.floor(tonumber(playerSlot) or 0)
    amount = math.floor(tonumber(amount) or 0)
    local item = inventory.items[playerSlot]
    if not item or amount < 1 or amount > item.amount then return false, 'Quantidade indisponivel.' end
    if equippedWeaponMatches(item, activeWeaponItem) then return false, 'Guarde a arma antes de descarta-la.' end
    local audit = { name = item.name, label = itemDefinition(item.name).label, amount = amount, metadata = item.metadata or {} }
    local removed, removeError = removeItemFromInventory(inventory, playerSlot, amount)
    if not removed then return false, removeError end
    syncInventory(tonumber(playerSource))
    return true, { inventory = snapshot(inventory), item = audit }
end)

exports('DeleteOwnedInventory', function(ownerType, ownerId)
    ownerType, ownerId = tostring(ownerType or ''):lower(), tostring(ownerId or '')
    if ownerType == '' or ownerType == 'player' or ownerId == '' then return false, 'Proprietario invalido.' end
    local changed, errorMessage = OR.Database.update.await(
        'DELETE FROM ob_inventories WHERE owner_type=? AND owner_id=?', { ownerType, ownerId }
    )
    if changed == nil then return false, errorMessage or 'Nao foi possivel excluir o inventario.' end
    ownedInventories[('%s:%s'):format(ownerType, ownerId)] = nil
    return true
end)
-- Integracao server-side para revista/apreensao. A permissao da acao pertence
-- ao recurso chamador; esta export preserva slot, metadata e sincronizacao.
exports('TransferItemBySlot', function(fromSource, toSource, slot, amount, forceEquipped, targetSlot)
    return transferItemBySlot(fromSource, toSource, slot, amount, nil, forceEquipped == true, targetSlot)
end)

AddEventHandler('ob_core:server:playerLoaded', function(playerSource, character)
    CreateThread(function()
        local inventory = loadInventory(playerSource)
        if inventory then
            syncInventory(playerSource)
            sendGroundDrops(playerSource)
        end
        ORInventoryNeeds.Load(playerSource, character or exports.ob_core:GetCharacter(playerSource))
    end)
end)

AddEventHandler('ob_core:server:playerUnloading', function(playerSource)
    playerSource = tonumber(playerSource)
    if not playerSource then return end
    ORInventoryNeeds.Unload(playerSource)
    inventories[playerSource] = nil
    itemChangeBaseline[playerSource] = nil
end)

AddEventHandler('playerDropped', function()
    -- Unload pode aguardar o banco. Capture o source antes desse ponto,
    -- pois a global do FiveM deixa de ser confiavel apos um yield.
    local playerSource = tonumber(source)
    if not playerSource then return end
    ORInventoryNeeds.Unload(playerSource)
    inventories[playerSource] = nil
    itemChangeBaseline[playerSource] = nil
end)

CreateThread(function()
    if not OR.Database.waitForReady(30000) then
        print('[ob_inventory] Banco de dados indisponivel; inventario nao foi iniciado.')
        return
    end
    local created, errorMessage = OR.Database.query.await(schema)
    if not created then
        print(('[ob_inventory] Falha ao criar tabela: %s'):format(errorMessage or 'desconhecida'))
        return
    end
    migrateLegacyInventories()
    databaseReady = true
    print('[ob_inventory] Tabela JSON de inventarios pronta.')
    for _, playerSource in ipairs(GetPlayers()) do
        CreateThread(function()
            playerSource = tonumber(playerSource)
            local inventory = loadInventory(playerSource)
            if inventory then
                -- Um restart do inventario descarta somente o cache local.
                -- O personagem continua carregado no ob_core, portanto
                -- devolvemos imediatamente mochila, necessidades e itens no
                -- chao para aquele cliente, sem novo login.
                syncInventory(playerSource)
                sendGroundDrops(playerSource)
                ORInventoryNeeds.Load(playerSource, exports.ob_core:GetCharacter(playerSource))
            end
        end)
    end
end)

CreateThread(function()
    while true do
        Wait(ORInventoryConfig.Ground.CleanupInterval)
        local changed = false
        local now = GetGameTimer()
        for id, drop in pairs(groundDrops) do
            if drop.expiresAt <= now then
                groundDrops[id] = nil
                changed = true
            end
        end
        if changed then broadcastGroundDrops() end
    end
end)
