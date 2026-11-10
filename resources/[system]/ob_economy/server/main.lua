local ready = false
local validModes = { active = true, monitor = true, disabled = true }

local function mode()
    local value = tostring(OBEconomyConfig.Mode or 'disabled'):lower()
    return validModes[value] and value or 'disabled'
end

local function whole(value, maximum)
    value = math.floor(tonumber(value) or 0)
    if value < 0 then return 0 end
    return math.min(value, maximum or 9007199254740991)
end

local function clean(value, maximum)
    value = tostring(value or ''):gsub('[\r\n%z]', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''
    return value:sub(1, maximum or 160)
end

local function accountKey(value)
    value = tostring(value or OBEconomyConfig.DefaultAccount or 'city_treasury'):lower()
    return value:match('^[a-z0-9_%-]+$') and value:sub(1, 64) or nil
end

local function userId(source)
    source = tonumber(source)
    if not source or source <= 0 or GetResourceState('ob_core') ~= 'started' then return nil end
    return tonumber(exports.ob_core:GetUserId(source))
end

local function metadataJson(value)
    if type(value) ~= 'table' then value = {} end
    local ok, encoded = pcall(json.encode, value)
    if not ok or type(encoded) ~= 'string' then return '{}' end
    return encoded:sub(1, 10000)
end

local function resultFallback(reason)
    return { handled = false, fallback = true, success = false, reason = reason }
end

local function isAdmin(source)
    if GetResourceState('ob_admin') == 'started' then
        local ok, allowed = pcall(function()
            return exports.ob_admin:HasPermission(source, OBEconomyConfig.AdminPermission or 'economy.manage')
        end)
        if ok and allowed == true then return true end
    end
    return GetResourceState('ob_core') == 'started' and exports.ob_core:IsAdmin(source) == true
end

local function insertMonitor(key, direction, amount, category, actorId, targetId, invokingResource, description, metadata)
    if not ready then return nil end
    return OR.Database.insert.await([[INSERT INTO ob_economy_ledger
        (account_key,direction,amount,balance_before,balance_after,category,status,actor_user_id,target_user_id,
         source_resource,description,metadata)
        SELECT account_key,?, ?,balance,balance,?,'monitor',?,?,?,?,?
        FROM ob_economy_accounts WHERE account_key=? AND active=1]], {
        direction, amount, category, tonumber(actorId) or 0, tonumber(targetId) or 0,
        invokingResource, description, metadataJson(metadata), key
    })
end

local function mutateAccount(key, direction, amount, category, actorId, targetId, invokingResource, description, metadata, parentId)
    key, amount = accountKey(key), whole(amount)
    if not ready then return nil, 'A economia ainda esta iniciando.' end
    if not key or amount <= 0 or (direction ~= 'credit' and direction ~= 'debit') then
        return nil, 'Movimentacao economica invalida.'
    end

    category = clean(category ~= '' and category or 'general', 64)
    description = clean(description, 255)
    invokingResource = clean(invokingResource ~= '' and invokingResource or 'unknown', 64)
    local updateSql, updateParameters, beforeExpression
    if direction == 'credit' then
        updateSql = 'UPDATE ob_economy_accounts SET balance=balance+? WHERE account_key=? AND active=1'
        updateParameters = { amount, key }
        beforeExpression = 'balance-?'
    else
        updateSql = [[UPDATE ob_economy_accounts SET balance=balance-?
            WHERE account_key=? AND active=1 AND (allow_negative=1 OR balance>=?)]]
        updateParameters = { amount, key, amount }
        beforeExpression = 'balance+?'
    end

    local insertSql = ([[INSERT INTO ob_economy_ledger
        (account_key,direction,amount,balance_before,balance_after,category,status,actor_user_id,target_user_id,
         source_resource,description,metadata,parent_ledger_id)
        SELECT account_key,?,?,%s,balance,?,'committed',?,?,?,?,?,?,?
        FROM ob_economy_accounts WHERE account_key=? AND active=1]]):format(beforeExpression)
    local statements = {
        { kind = 'update', statement = updateSql, parameters = updateParameters, expectAffectedMin = 1 },
        { kind = 'insert', statement = insertSql, parameters = {
            direction, amount, amount, category, tonumber(actorId) or 0, tonumber(targetId) or 0,
            invokingResource, description, metadataJson(metadata), tonumber(parentId) or 0, key,
        }, expectAffectedMin = 1 },
    }
    local results, transactionError = OR.Database.transaction.await(statements)
    if not results then
        if direction == 'debit' then return nil, 'Saldo insuficiente no cofre selecionado.' end
        return nil, transactionError or 'Falha ao movimentar o cofre.'
    end
    local balance = tonumber(OR.Database.scalar.await(
        'SELECT balance FROM ob_economy_accounts WHERE account_key=? LIMIT 1', { key })) or 0
    return { ledgerId = tonumber(results[2]), balance = balance, accountKey = key }
end

local function takePlayerMoney(source, amount, description)
    local payment = type(OBEconomyConfig.Payment) == 'table' and OBEconomyConfig.Payment or {}
    local cardError
    if payment.TryCardFirst ~= false and GetResourceState('ob_bank') == 'started' then
        local paid, err = exports.ob_bank:PayWithCard(source, amount, description)
        if paid == true then return true, 'card' end
        cardError = err
    end
    if payment.AllowCash ~= false and GetResourceState('ob_inventory') == 'started' then
        local cashAccount = tostring(payment.CashAccount or 'money')
        if (tonumber(exports.ob_inventory:GetMoney(source, cashAccount)) or 0) >= amount then
            local paid, err = exports.ob_inventory:RemoveMoney(source, cashAccount, amount)
            if paid == true then return true, 'cash' end
            return false, err or cardError or 'Pagamento recusado.'
        end
    end
    return false, cardError or 'Saldo no cartao e dinheiro em maos insuficientes.'
end

local function returnPlayerMoney(source, amount, method, description)
    if method == 'card' and GetResourceState('ob_bank') == 'started' then
        return exports.ob_bank:RefundToBank(source, amount, description) == true
    end
    if GetResourceState('ob_inventory') == 'started' then
        local payment = type(OBEconomyConfig.Payment) == 'table' and OBEconomyConfig.Payment or {}
        return exports.ob_inventory:AddMoney(source, tostring(payment.CashAccount or 'money'), amount) == true
    end
    return false
end

local function creditPlayer(source, amount, description)
    if GetResourceState('ob_bank') == 'started' then
        local ok, err = exports.ob_bank:CreditSalary(source, amount, description)
        if ok == true then return true, 'card' end
        if GetResourceState('ob_inventory') ~= 'started' then return false, err end
    end
    if GetResourceState('ob_inventory') == 'started' then
        local payment = type(OBEconomyConfig.Payment) == 'table' and OBEconomyConfig.Payment or {}
        local ok, err = exports.ob_inventory:AddMoney(source, tostring(payment.CashAccount or 'money'), amount)
        return ok == true, ok == true and 'cash' or err
    end
    return false, 'Sistema de pagamento indisponivel.'
end

local function chargePlayer(source, amount, category, description, metadata, key, invokingResource)
    source, amount = tonumber(source), whole(amount)
    key = accountKey(key)
    if not source or not GetPlayerName(source) or not userId(source) then
        return { handled = true, fallback = false, success = false, error = 'Personagem indisponivel.' }
    end
    if amount <= 0 then return { handled = true, fallback = false, success = true, free = true, amount = 0 } end
    if mode() == 'disabled' then return resultFallback('disabled') end
    if not ready then return resultFallback('not_ready') end
    category, description = clean(category ~= '' and category or 'general', 64), clean(description, 255)
    local actorId = userId(source)
    if mode() == 'monitor' then
        insertMonitor(key, 'credit', amount, category, actorId, actorId, invokingResource, description, metadata)
        return resultFallback('monitor')
    end

    local paid, methodOrError = takePlayerMoney(source, amount, description)
    if not paid then
        return { handled = true, fallback = false, success = false, error = methodOrError }
    end
    metadata = type(metadata) == 'table' and metadata or {}
    metadata.paymentMethod = methodOrError
    local movement, movementError = mutateAccount(
        key, 'credit', amount, category, actorId, actorId, invokingResource, description, metadata)
    if not movement then
        local refunded = returnPlayerMoney(source, amount, methodOrError, 'Estorno por falha no Tesouro')
        return {
            handled = true, fallback = false, success = false,
            error = refunded and (movementError or 'Falha ao registrar o pagamento.')
                or 'Falha no Tesouro e no estorno. Procure a administracao.',
        }
    end
    return {
        handled = true, fallback = false, success = true, amount = amount,
        method = methodOrError, receipt = movement.ledgerId, accountKey = movement.accountKey,
        accountBalance = movement.balance,
    }
end

local function refundCharge(source, receipt, description, invokingResource)
    source, receipt = tonumber(source), tonumber(receipt)
    if mode() ~= 'active' or not ready then return resultFallback(mode()) end
    if not source or not receipt or not userId(source) then
        return { handled = true, fallback = false, success = false, error = 'Estorno invalido.' }
    end
    local row = OR.Database.single.await([[SELECT l.id,l.account_key,l.amount,l.metadata
        FROM ob_economy_ledger l
        WHERE l.id=? AND l.direction='credit' AND l.status='committed' AND l.target_user_id=?
          AND NOT EXISTS (SELECT 1 FROM ob_economy_ledger r WHERE r.parent_ledger_id=l.id)
        LIMIT 1]], { receipt, userId(source) })
    if not row then
        return { handled = true, fallback = false, success = false, error = 'Esse pagamento ja foi estornado ou nao existe.' }
    end
    local decoded = {}
    pcall(function() decoded = json.decode(row.metadata or '{}') or {} end)
    local amount, method = whole(row.amount), decoded.paymentMethod == 'card' and 'card' or 'cash'
    local movement, movementError = mutateAccount(
        row.account_key, 'debit', amount, 'refund', userId(source), userId(source), invokingResource,
        clean(description ~= '' and description or 'Estorno', 255), { paymentMethod = method }, row.id)
    if not movement then
        return { handled = true, fallback = false, success = false, error = movementError }
    end
    if not returnPlayerMoney(source, amount, method, description ~= '' and description or 'Estorno') then
        mutateAccount(row.account_key, 'credit', amount, 'refund_rollback', userId(source), userId(source),
            invokingResource, 'Reversao de estorno que nao chegou ao jogador', { failedRefund = true }, movement.ledgerId)
        return { handled = true, fallback = false, success = false, error = 'Nao foi possivel devolver o dinheiro.' }
    end
    return { handled = true, fallback = false, success = true, amount = amount, receipt = movement.ledgerId }
end

local function payPlayer(source, amount, category, description, metadata, key, invokingResource)
    source, amount, key = tonumber(source), whole(amount), accountKey(key)
    if not source or not GetPlayerName(source) or not userId(source) then
        return { handled = true, fallback = false, success = false, error = 'Personagem indisponivel.' }
    end
    if amount <= 0 then return { handled = true, fallback = false, success = true, free = true, amount = 0 } end
    if mode() == 'disabled' then return resultFallback('disabled') end
    if not ready then return resultFallback('not_ready') end
    category, description = clean(category ~= '' and category or 'payout', 64), clean(description, 255)
    if mode() == 'monitor' then
        insertMonitor(key, 'debit', amount, category, userId(source), userId(source), invokingResource, description, metadata)
        return resultFallback('monitor')
    end
    local movement, movementError = mutateAccount(
        key, 'debit', amount, category, userId(source), userId(source), invokingResource, description, metadata)
    if not movement then
        return { handled = true, fallback = false, success = false, error = movementError }
    end
    local paid, methodOrError = creditPlayer(source, amount, description)
    if not paid then
        mutateAccount(key, 'credit', amount, 'payout_rollback', userId(source), userId(source), invokingResource,
            'Reversao de pagamento que nao chegou ao jogador', { failedPayout = true }, movement.ledgerId)
        return { handled = true, fallback = false, success = false, error = methodOrError }
    end
    return {
        handled = true, fallback = false, success = true, amount = amount, method = methodOrError,
        receipt = movement.ledgerId, accountKey = movement.accountKey, accountBalance = movement.balance,
    }
end

local function chargeAccount(source, key, amount, category, description, metadata, invokingResource)
    source, key, amount = tonumber(source), accountKey(key), whole(amount)
    local actorId = source and userId(source) or nil
    if amount <= 0 then return { handled = true, fallback = false, success = true, free = true, amount = 0 } end
    if mode() == 'disabled' then return resultFallback('disabled') end
    if not ready then return resultFallback('not_ready') end
    if not key then return { handled = true, fallback = false, success = false, error = 'Cofre invalido.' } end
    category, description = clean(category ~= '' and category or 'department_expense', 64), clean(description, 255)
    if mode() == 'monitor' then
        insertMonitor(key, 'debit', amount, category, actorId, actorId, invokingResource, description, metadata)
        return resultFallback('monitor')
    end
    local movement, movementError = mutateAccount(
        key, 'debit', amount, category, actorId, actorId, invokingResource, description, metadata)
    if not movement then
        return { handled = true, fallback = false, success = false, error = movementError }
    end
    return {
        handled = true, fallback = false, success = true, amount = amount, method = 'account',
        receipt = movement.ledgerId, accountKey = movement.accountKey, accountBalance = movement.balance,
    }
end

local function refundAccountCharge(source, receipt, description, invokingResource)
    source, receipt = tonumber(source), tonumber(receipt)
    if mode() ~= 'active' or not ready then return resultFallback(mode()) end
    if not receipt then
        return { handled = true, fallback = false, success = false, error = 'Estorno de cofre invalido.' }
    end
    local row = OR.Database.single.await([[SELECT l.id,l.account_key,l.amount
        FROM ob_economy_ledger l
        WHERE l.id=? AND l.direction='debit' AND l.status='committed'
          AND NOT EXISTS (SELECT 1 FROM ob_economy_ledger r WHERE r.parent_ledger_id=l.id)
        LIMIT 1]], { receipt })
    if not row then
        return { handled = true, fallback = false, success = false, error = 'Essa despesa ja foi estornada ou nao existe.' }
    end
    local movement, movementError = mutateAccount(row.account_key, 'credit', whole(row.amount),
        'department_refund', source and userId(source) or nil, nil, invokingResource,
        clean(description ~= '' and description or 'Estorno de despesa', 255), {}, row.id)
    if not movement then
        return { handled = true, fallback = false, success = false, error = movementError }
    end
    return { handled = true, fallback = false, success = true, amount = whole(row.amount), receipt = movement.ledgerId }
end

exports('GetStatus', function()
    return { handled = true, fallback = false, success = true, mode = mode(), ready = ready }
end)

exports('ChargePlayer', function(source, amount, category, description, metadata, key)
    return chargePlayer(source, amount, category, description, metadata, key, GetInvokingResource() or 'unknown')
end)

exports('RefundCharge', function(source, receipt, description)
    return refundCharge(source, receipt, clean(description, 255), GetInvokingResource() or 'unknown')
end)

exports('PayPlayer', function(source, amount, category, description, metadata, key)
    return payPlayer(source, amount, category, description, metadata, key, GetInvokingResource() or 'unknown')
end)

exports('ChargeAccount', function(source, key, amount, category, description, metadata)
    return chargeAccount(source, key, amount, category, description, metadata, GetInvokingResource() or 'unknown')
end)

exports('RefundAccountCharge', function(source, receipt, description)
    return refundAccountCharge(source, receipt, clean(description, 255), GetInvokingResource() or 'unknown')
end)

exports('GetBalance', function(key)
    if not ready then return nil, 'A economia ainda esta iniciando.' end
    key = accountKey(key)
    if not key then return nil, 'Conta economica invalida.' end
    return tonumber(OR.Database.scalar.await(
        'SELECT balance FROM ob_economy_accounts WHERE account_key=? AND active=1 LIMIT 1', { key }))
end)

exports('Deposit', function(key, amount, category, description, metadata)
    local caller = GetInvokingResource() or 'unknown'
    if mode() ~= 'active' then return nil, 'A economia nao esta ativa.' end
    return mutateAccount(key, 'credit', amount, category, nil, nil, caller, description, metadata)
end)

exports('Withdraw', function(key, amount, category, description, metadata)
    local caller = GetInvokingResource() or 'unknown'
    if mode() ~= 'active' then return nil, 'A economia nao esta ativa.' end
    return mutateAccount(key, 'debit', amount, category, nil, nil, caller, description, metadata)
end)

local function panelData(source, filters)
    if not isAdmin(source) then return nil, 'Sem permissao para administrar a economia.' end
    if not ready then return nil, 'A economia ainda esta iniciando.' end
    filters = type(filters) == 'table' and filters or {}
    local panel = type(OBEconomyConfig.Panel) == 'table' and OBEconomyConfig.Panel or {}
    local limit = whole(filters.limit, whole(panel.MaximumEntries, 200))
    if limit < 1 then limit = whole(panel.RecentEntries, 80) end
    local term = clean(filters.term, 80)
    local category = clean(filters.category, 64)
    local clauses, parameters = {}, {}
    if term ~= '' then
        clauses[#clauses + 1] = '(description LIKE ? OR source_resource LIKE ? OR CAST(target_user_id AS CHAR) LIKE ?)'
        local like = ('%%%s%%'):format(term)
        parameters[#parameters + 1] = like
        parameters[#parameters + 1] = like
        parameters[#parameters + 1] = like
    end
    if category ~= '' then clauses[#clauses + 1] = 'category=?'; parameters[#parameters + 1] = category end
    local where = #clauses > 0 and (' WHERE ' .. table.concat(clauses, ' AND ')) or ''
    local ledger = OR.Database.query.await(([[SELECT id,account_key,direction,amount,balance_before,balance_after,
        category,status,actor_user_id,target_user_id,source_resource,description,created_at
        FROM ob_economy_ledger%s ORDER BY id DESC LIMIT %d]]):format(where, limit), parameters) or {}
    return {
        mode = mode(), currency = OBEconomyConfig.Currency or 'USD',
        accounts = OR.Database.query.await([[SELECT account_key,label,kind,balance,allow_negative,active,updated_at
            FROM ob_economy_accounts WHERE active=1 ORDER BY kind,label]]) or {},
        ledger = ledger,
    }
end

OR.Callback.register('panel', panelData)
OR.Callback.register('adjust', function(source, data)
    if not isAdmin(source) then return false, 'Sem permissao.' end
    if mode() ~= 'active' then return false, 'Ative Mode = active para alterar saldos.' end
    if not OR.Security.rateLimit(source, 'economy:adjust', 6, 30000) then return false, 'Aguarde antes de ajustar novamente.' end
    data = type(data) == 'table' and data or {}
    local panel = type(OBEconomyConfig.Panel) == 'table' and OBEconomyConfig.Panel or {}
    local amount = whole(data.amount, whole(panel.MaximumAdjustment, 100000000))
    local direction = data.direction == 'debit' and 'debit'
        or data.direction == 'credit' and 'credit'
        or data.direction == 'transfer' and 'transfer' or nil
    local reason = clean(data.reason, 255)
    if not direction or amount <= 0 or reason == '' then return false, 'Informe operacao, valor e motivo.' end
    local movement, movementError
    if direction == 'transfer' then
        local treasuryKey = accountKey(OBEconomyConfig.DefaultAccount)
        local targetKey = accountKey(data.accountKey)
        if not targetKey or targetKey == treasuryKey then return false, 'Selecione um orgao para receber a verba.' end
        local treasuryMovement
        treasuryMovement, movementError = mutateAccount(treasuryKey, 'debit', amount, 'department_funding',
            userId(source), nil, 'ob_economy', reason, { adminSource = source, targetAccount = targetKey })
        if not treasuryMovement then return false, movementError end
        movement, movementError = mutateAccount(targetKey, 'credit', amount, 'department_funding',
            userId(source), nil, 'ob_economy', reason,
            { adminSource = source, sourceAccount = treasuryKey }, treasuryMovement.ledgerId)
        if not movement then
            mutateAccount(treasuryKey, 'credit', amount, 'funding_rollback', userId(source), nil,
                'ob_economy', 'Reversao de repasse que falhou', { targetAccount = targetKey }, treasuryMovement.ledgerId)
            return false, movementError
        end
    else
        movement, movementError = mutateAccount(data.accountKey, direction, amount, 'admin_adjustment',
            userId(source), nil, 'ob_economy', reason, { adminSource = source })
    end
    if not movement then return false, movementError end
    return true, ('Saldo atualizado para %s.'):format(OR.FormatMoney(movement.balance)), panelData(source)
end)

CreateThread(function()
    if not OR.Database.waitForReady(30000) then
        print(('[ob_economy] Banco indisponivel: %s'):format(OR.Database.getError() or 'erro desconhecido'))
        return
    end
    local statements = {
        [[CREATE TABLE IF NOT EXISTS ob_economy_accounts (
            account_key varchar(64) NOT NULL, label varchar(100) NOT NULL, kind varchar(32) NOT NULL DEFAULT 'treasury',
            balance bigint NOT NULL DEFAULT 0, initial_balance bigint NOT NULL DEFAULT 0,
            allow_negative tinyint(1) NOT NULL DEFAULT 0, active tinyint(1) NOT NULL DEFAULT 1,
            created_at timestamp NOT NULL DEFAULT current_timestamp(),
            updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
            PRIMARY KEY (account_key), KEY idx_ob_economy_accounts_kind (kind,active)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS ob_economy_ledger (
            id bigint unsigned NOT NULL AUTO_INCREMENT, account_key varchar(64) NOT NULL,
            direction varchar(16) NOT NULL, amount bigint NOT NULL, balance_before bigint NOT NULL,
            balance_after bigint NOT NULL, category varchar(64) NOT NULL, status varchar(24) NOT NULL,
            actor_user_id int DEFAULT NULL, target_user_id int DEFAULT NULL, source_resource varchar(64) NOT NULL,
            description varchar(255) NOT NULL DEFAULT '', metadata longtext DEFAULT NULL,
            parent_ledger_id bigint unsigned DEFAULT NULL, created_at timestamp NOT NULL DEFAULT current_timestamp(),
            PRIMARY KEY (id), KEY idx_ob_economy_ledger_account (account_key,id),
            KEY idx_ob_economy_ledger_category (category,id), KEY idx_ob_economy_ledger_target (target_user_id,id),
            KEY idx_ob_economy_ledger_parent (parent_ledger_id),
            CONSTRAINT fk_ob_economy_ledger_account FOREIGN KEY (account_key)
                REFERENCES ob_economy_accounts(account_key) ON DELETE RESTRICT
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    }
    for _, statement in ipairs(statements) do
        local result, schemaError = OR.Database.query.await(statement)
        if result == nil then
            print(('[ob_economy] Falha ao criar schema: %s'):format(schemaError or 'erro desconhecido'))
            return
        end
    end
    for key, definition in pairs(type(OBEconomyConfig.Accounts) == 'table' and OBEconomyConfig.Accounts or {}) do
        local normalized = accountKey(key)
        if normalized then
            local initial = whole(definition.initialBalance)
            OR.Database.insert.await([[INSERT INTO ob_economy_accounts
                (account_key,label,kind,balance,initial_balance,allow_negative,active) VALUES (?,?,?,?,?,?,1)
                ON DUPLICATE KEY UPDATE label=VALUES(label),kind=VALUES(kind),
                    allow_negative=VALUES(allow_negative),active=1]], {
                normalized, clean(definition.label ~= '' and definition.label or normalized, 100),
                clean(definition.kind ~= '' and definition.kind or 'treasury', 32), initial, initial,
                definition.allowNegative == true and 1 or 0,
            })
        end
    end
    ready = true
    print(('[ob_economy] Pronto em modo %s. Remover o recurso mantem os pagamentos antigos funcionando.'):format(mode()))
end)
