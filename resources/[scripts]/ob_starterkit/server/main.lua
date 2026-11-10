local schemaReady = false
local delivering = {}

local function validCharacter(source, character)
    source = tonumber(source)
    local userId = type(character) == 'table' and tonumber(character.userId) or nil
    return source and source > 0 and userId and userId > 0
        and exports.ob_core:GetUserId(source) == userId and source, userId
end

local function waitForSchema()
    while not schemaReady do Wait(100) end
end

local function registerNewCharacter(source, character)
    local playerSource, userId = validCharacter(source, character)
    if not playerSource then return end
    CreateThread(function()
        waitForSchema()
        if exports.ob_core:GetUserId(playerSource) ~= userId then return end
        local changed, errorMessage = OR.Database.update.await(
            'INSERT IGNORE INTO ob_starterkit_claims (user_id) VALUES (?)', { userId }
        )
        if changed == nil then
            print(('[ob_starterkit] Falha ao registrar personagem user_id=%s: %s'):format(userId, tostring(errorMessage)))
        end
    end)
end

local function rollback(playerSource, granted)
    for index = #granted, 1, -1 do
        local reward = granted[index]
        local ok, removed
        if reward.money then
            ok, removed = pcall(function()
                return exports.ob_inventory:RemoveMoney(playerSource, reward.name, reward.amount)
            end)
        else
            ok, removed = pcall(function()
                return exports.ob_inventory:RemoveItem(playerSource, reward.name, reward.amount)
            end)
        end
        if not ok or removed ~= true then
            print(('[ob_starterkit] Rollback pendente source=%s item=%s amount=%s'):format(
                playerSource, reward.name, reward.amount))
        end
    end
end

local function deliver(playerSource, character)
    local sourceId, userId = validCharacter(playerSource, character)
    if not sourceId or delivering[userId] then return end
    delivering[userId] = true
    CreateThread(function()
        waitForSchema()
        local row = OR.Database.single.await(
            'SELECT user_id, delivered_at FROM ob_starterkit_claims WHERE user_id=? LIMIT 1', { userId }
        )
        if not row or row.delivered_at or exports.ob_core:GetUserId(sourceId) ~= userId then
            delivering[userId] = nil
            return
        end

        local granted, failure = {}, nil
        for _, reward in ipairs(OBStarterKit.Items or {}) do
            local name, amount = tostring(reward.name or ''):lower(), math.max(0, math.floor(tonumber(reward.amount) or 0))
            if name ~= '' and amount > 0 then
                local canCarry, carryError = exports.ob_inventory:CanCarryItem(sourceId, name, amount, reward.metadata)
                if canCarry ~= true then failure = carryError or ('Sem espaco para ' .. name);break end
                local added, addError = exports.ob_inventory:AddItem(sourceId, name, amount, reward.metadata)
                if added ~= true then failure = addError or ('Falha ao entregar ' .. name);break end
                granted[#granted + 1] = { name = name, amount = amount }
            end
        end

        local money = type(OBStarterKit.Money) == 'table' and OBStarterKit.Money or {}
        local account, amount = tostring(money.account or 'money'):lower(), math.max(0, math.floor(tonumber(money.amount) or 0))
        if not failure and amount > 0 then
            local added, addError = exports.ob_inventory:AddMoney(sourceId, account, amount)
            if added ~= true then failure = addError or 'Falha ao entregar dinheiro.'
            else granted[#granted + 1] = { name = account, amount = amount, money = true } end
        end

        if failure then
            rollback(sourceId, granted)
            print(('[ob_starterkit] Entrega adiada user_id=%s: %s'):format(userId, tostring(failure)))
            TriggerClientEvent('ob_notification:client:notify', sourceId,
                'Nao foi possivel receber o kit inicial agora. Libere espaco e reconecte.', 'error', 8000)
            delivering[userId] = nil
            return
        end

        local saved, saveError = OR.Database.update.await(
            'UPDATE ob_starterkit_claims SET delivered_at=current_timestamp() WHERE user_id=? AND delivered_at IS NULL',
            { userId }
        )
        if saved == nil then
            rollback(sourceId, granted)
            print(('[ob_starterkit] Falha ao finalizar user_id=%s: %s'):format(userId, tostring(saveError)))
        else
            TriggerClientEvent('ob_notification:client:notify', sourceId,
                OBStarterKit.Notification or 'Kit inicial recebido.', 'success', 9000)
            print(('[ob_starterkit] DELIVERED user_id=%s'):format(userId))
        end
        delivering[userId] = nil
    end)
end

AddEventHandler('ob_core:server:characterCreated', registerNewCharacter)
AddEventHandler('ob_core:server:playerLoaded', deliver)

AddEventHandler('playerDropped', function()
    local userId = exports.ob_core:GetUserId(source)
    if userId then delivering[tonumber(userId)] = nil end
end)

CreateThread(function()
    while not OR.Database.waitForReady(10000) do Wait(1000) end
    local ok, result, errorMessage = pcall(function()
        return OR.Database.query.await([[CREATE TABLE IF NOT EXISTS ob_starterkit_claims (
            user_id BIGINT UNSIGNED NOT NULL PRIMARY KEY,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            delivered_at TIMESTAMP NULL DEFAULT NULL,
            CONSTRAINT fk_ob_starterkit_character FOREIGN KEY (user_id) REFERENCES ob_characters(user_id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    end)
    if not ok or result == nil then
        print('[ob_starterkit] Falha ao preparar banco: ' .. tostring(ok and errorMessage or result))
        return
    end
    schemaReady = true
    print('[ob_starterkit] Pronto.')
end)
