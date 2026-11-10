local locations, machinesById, activeByMachine, activeByUser, machineLocks = {}, {}, {}, {}, {}
local databaseReady = false

local schema = [[
CREATE TABLE IF NOT EXISTS ob_moneywash_locations (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    label VARCHAR(80) NOT NULL,
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    commission_percent TINYINT UNSIGNED NOT NULL DEFAULT 40,
    duration_seconds INT UNSIGNED NOT NULL DEFAULT 60,
    minimum_amount INT UNSIGNED NOT NULL DEFAULT 100,
    maximum_amount INT UNSIGNED NOT NULL DEFAULT 1000000,
    access_group VARCHAR(64) NULL,
    ped_model VARCHAR(64) NOT NULL,
    ped_scenario VARCHAR(96) NOT NULL,
    ped_x DOUBLE NOT NULL,
    ped_y DOUBLE NOT NULL,
    ped_z DOUBLE NOT NULL,
    ped_w DOUBLE NOT NULL,
    machine_model VARCHAR(64) NOT NULL,
    machine_open_model VARCHAR(64) NOT NULL,
    machine_spin_model VARCHAR(64) NOT NULL,
    machine_x DOUBLE NOT NULL,
    machine_y DOUBLE NOT NULL,
    machine_z DOUBLE NOT NULL,
    machine_w DOUBLE NOT NULL,
    action_x DOUBLE NOT NULL,
    action_y DOUBLE NOT NULL,
    action_z DOUBLE NOT NULL,
    action_w DOUBLE NOT NULL,
    created_by BIGINT UNSIGNED NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_ob_moneywash_enabled (enabled)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
]]

local machineSchema = [[
CREATE TABLE IF NOT EXISTS ob_moneywash_machines (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    location_id INT UNSIGNED NOT NULL,
    label VARCHAR(80) NOT NULL DEFAULT 'Maquina',
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    machine_model VARCHAR(64) NOT NULL,
    machine_open_model VARCHAR(64) NOT NULL,
    machine_spin_model VARCHAR(64) NOT NULL,
    machine_x DOUBLE NOT NULL,
    machine_y DOUBLE NOT NULL,
    machine_z DOUBLE NOT NULL,
    machine_w DOUBLE NOT NULL,
    action_x DOUBLE NOT NULL,
    action_y DOUBLE NOT NULL,
    action_z DOUBLE NOT NULL,
    action_w DOUBLE NOT NULL,
    sort_order INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    INDEX idx_ob_moneywash_machine_location (location_id, enabled, sort_order),
    CONSTRAINT fk_ob_moneywash_machine_location FOREIGN KEY (location_id)
        REFERENCES ob_moneywash_locations(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
]]

local transactionSchema = [[
CREATE TABLE IF NOT EXISTS ob_moneywash_transactions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    location_id INT UNSIGNED NOT NULL,
    machine_id INT UNSIGNED NULL,
    user_id BIGINT UNSIGNED NOT NULL,
    dirty_amount INT UNSIGNED NOT NULL,
    commission_percent TINYINT UNSIGNED NOT NULL,
    commission_amount INT UNSIGNED NOT NULL,
    clean_amount INT UNSIGNED NOT NULL,
    status ENUM('processing','ready','paying','completed','refunded','review') NOT NULL DEFAULT 'processing',
    receipt_code VARCHAR(32) NULL,
    dirty_balance_before BIGINT UNSIGNED NULL,
    dirty_balance_after BIGINT UNSIGNED NULL,
    clean_balance_before BIGINT UNSIGNED NULL,
    clean_balance_after BIGINT UNSIGNED NULL,
    payout_started_at DATETIME NULL,
    payout_confirmed_at DATETIME NULL,
    integrity_note VARCHAR(255) NULL,
    started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finish_at DATETIME NOT NULL,
    completed_at DATETIME NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_ob_moneywash_receipt (receipt_code),
    INDEX idx_ob_moneywash_active_location (location_id, status),
    INDEX idx_ob_moneywash_active_user (user_id, status),
    CONSTRAINT fk_ob_moneywash_location FOREIGN KEY (location_id)
        REFERENCES ob_moneywash_locations(id) ON DELETE RESTRICT,
    CONSTRAINT fk_ob_moneywash_character FOREIGN KEY (user_id)
        REFERENCES ob_characters(user_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
]]

local auditSchema = [[
CREATE TABLE IF NOT EXISTS ob_moneywash_audit (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    transaction_id BIGINT UNSIGNED NULL,
    location_id INT UNSIGNED NULL,
    user_id BIGINT UNSIGNED NULL,
    actor_user_id BIGINT UNSIGNED NULL,
    event_type VARCHAR(48) NOT NULL,
    dirty_balance BIGINT UNSIGNED NULL,
    clean_balance BIGINT UNSIGNED NULL,
    details LONGTEXT NULL,
    created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    INDEX idx_ob_moneywash_audit_transaction (transaction_id, id),
    INDEX idx_ob_moneywash_audit_user (user_id, created_at),
    INDEX idx_ob_moneywash_audit_event (event_type, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
]]

local function trim(value, maximum)
    value = tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if maximum and #value > maximum then value = value:sub(1, maximum) end
    return value
end

local function integer(value, minimum, maximum, fallback)
    value = math.floor(tonumber(value) or tonumber(fallback) or 0)
    return math.max(minimum, math.min(maximum, value))
end

local function number(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function validModel(value, fallback)
    value = trim(value, 64):lower()
    if value == '' then value = fallback end
    return value:match('^[%w_%-]+$') and value or nil
end

local function normalize(row)
    return {
        id = tonumber(row.id), label = row.label, enabled = tonumber(row.enabled) == 1,
        accessGroup = trim(row.access_group, 64), machines = {},
        commissionPercent = tonumber(row.commission_percent), durationSeconds = tonumber(row.duration_seconds),
        minimumAmount = tonumber(row.minimum_amount), maximumAmount = tonumber(row.maximum_amount),
        ped = { model = row.ped_model, scenario = row.ped_scenario,
            x = tonumber(row.ped_x), y = tonumber(row.ped_y), z = tonumber(row.ped_z), w = tonumber(row.ped_w) },
        machine = { model = row.machine_model, openModel = row.machine_open_model, spinModel = row.machine_spin_model,
            x = tonumber(row.machine_x), y = tonumber(row.machine_y), z = tonumber(row.machine_z), w = tonumber(row.machine_w) },
        action = { x = tonumber(row.action_x), y = tonumber(row.action_y), z = tonumber(row.action_z), w = tonumber(row.action_w) },
    }
end

local function normalizeMachine(row)
    return {
        id = tonumber(row.id), locationId = tonumber(row.location_id), label = row.label or 'Maquina',
        enabled = tonumber(row.enabled) == 1,
        model = row.machine_model, openModel = row.machine_open_model, spinModel = row.machine_spin_model,
        x = tonumber(row.machine_x), y = tonumber(row.machine_y), z = tonumber(row.machine_z), w = tonumber(row.machine_w),
        action = { x = tonumber(row.action_x), y = tonumber(row.action_y), z = tonumber(row.action_z), w = tonumber(row.action_w) },
    }
end

local function publicLocations(includeDisabled)
    local payload = {}
    for _, location in pairs(locations) do
        if includeDisabled or location.enabled then payload[#payload + 1] = location end
    end
    table.sort(payload, function(a, b) return a.id < b.id end)
    return payload
end

local function hasAdmin(source)
    if GetResourceState('ob_admin') == 'started' then
        local ok, allowed = pcall(function()
            return exports.ob_admin:HasPermission(source, OBMoneyWash.AdminPermission or 'world.shops')
        end)
        if ok then return allowed == true end
    end
    return exports.ob_core:IsAdmin(source) == true
end

local function audit(eventType, transactionId, userId, locationId, details, balances, actorUserId)
    details = type(details) == 'table' and details or { message = tostring(details or '') }
    balances = type(balances) == 'table' and balances or {}
    local inserted, insertError = OR.Database.insert.await([[INSERT INTO ob_moneywash_audit
        (transaction_id,location_id,user_id,actor_user_id,event_type,dirty_balance,clean_balance,details)
        VALUES (?,?,?,?,?,?,?,?)]], {
        tonumber(transactionId) or 0, tonumber(locationId) or 0, tonumber(userId) or 0, tonumber(actorUserId) or 0,
        trim(eventType, 48), tonumber(balances.dirty) or 0, tonumber(balances.clean) or 0, json.encode(details),
    })
    if not inserted then
        print(('[ob_moneywash] Falha ao gravar auditoria %s da transacao %s: %s'):format(
            tostring(eventType), tostring(transactionId or '-'), tostring(insertError or 'desconhecida')))
    end
    return inserted ~= nil
end

local function playerNear(source, point, tolerance)
    local ped = GetPlayerPed(source)
    if not ped or ped <= 0 or not point then return false end
    local coords = GetEntityCoords(ped)
    return #(coords - vector3(point.x, point.y, point.z)) <= (tolerance or OBMoneyWash.ServerDistanceTolerance or 4.5)
end

local function statePayload(machineId)
    machineId = tonumber(machineId)
    local transaction = activeByMachine[machineId]
    local machine = machinesById[machineId]
    if not transaction then return { machineId = machineId, locationId = machine and machine.locationId, status = 'idle' } end
    if transaction.status == 'processing' and os.time() >= transaction.endsAt then transaction.status = 'ready' end
    return {
        machineId = transaction.machineId, locationId = transaction.locationId, status = transaction.status,
        endsAt = transaction.endsAt, remainingSeconds = math.max(0, transaction.endsAt - os.time()),
        transactionId = transaction.id,
    }
end

local function broadcastState(machineId, target)
    TriggerClientEvent('ob_moneywash:client:state', target or -1, statePayload(machineId))
end

local function transactionPayload(transaction)
    if not transaction then return nil end
    return {
        id = transaction.id, locationId = transaction.locationId, machineId = transaction.machineId,
        reservationToken = transaction.reservationToken, dirtyAmount = transaction.dirtyAmount,
        cleanAmount = transaction.cleanAmount, commissionAmount = transaction.commissionAmount,
        commissionPercent = transaction.commissionPercent, endsAt = transaction.endsAt,
        remainingSeconds = math.max(0, (transaction.endsAt or os.time()) - os.time()),
        status = transaction.status, receipt = transaction.receipt,
    }
end

local function canUseLocation(source, location)
    local group = trim(location and location.accessGroup, 64):lower()
    if group == '' then return true end
    if GetResourceState('ob_org') ~= 'started' then return false, 'Sistema de organizacoes indisponivel.' end
    local ok, allowed = pcall(function() return exports.ob_org:HasPermission(source, group, false) end)
    return ok and allowed == true, ('Apenas membros do grupo %s podem usar esta lavagem.'):format(group)
end

local function loadData()
    local rows, loadError = OR.Database.query.await('SELECT * FROM ob_moneywash_locations ORDER BY id ASC')
    if not rows then
        print(('[ob_moneywash] Falha ao carregar locais: %s'):format(loadError or 'desconhecida'))
        return false
    end
    locations, machinesById = {}, {}
    for _, row in ipairs(rows) do
        local location = normalize(row)
        locations[location.id] = location
    end

    local machineRows, machineError = OR.Database.query.await('SELECT * FROM ob_moneywash_machines ORDER BY location_id,sort_order,id')
    if not machineRows then
        print(('[ob_moneywash] Falha ao carregar maquinas: %s'):format(machineError or 'desconhecida'))
        return false
    end
    for _, row in ipairs(machineRows) do
        local machine = normalizeMachine(row)
        machinesById[machine.id] = machine
        local location = locations[machine.locationId]
        if location then location.machines[#location.machines + 1] = machine end
    end

    local transactions = OR.Database.query.await([[SELECT id, location_id, machine_id, user_id, dirty_amount,
        commission_percent, commission_amount, clean_amount, status, receipt_code,
        UNIX_TIMESTAMP(finish_at) AS ends_at
        FROM ob_moneywash_transactions WHERE status IN ('processing','ready','paying') ORDER BY id ASC]]) or {}
    activeByMachine, activeByUser = {}, {}
    for _, row in ipairs(transactions) do
        if row.status == 'paying' then
            -- Nao repetir pagamento quando o servidor caiu entre AddMoney e a confirmacao final.
            OR.Database.update.await("UPDATE ob_moneywash_transactions SET status = 'review', integrity_note = 'Reinicio durante pagamento; revisao manual necessaria' WHERE id = ? AND status = 'paying'", { row.id })
            audit('restart_during_payout', row.id, row.user_id, row.location_id,
                { reason = 'Estado paying encontrado ao iniciar; pagamento automatico bloqueado.' })
            print(('[ob_moneywash] Transacao #%s enviada para revisao apos reinicio durante pagamento.'):format(row.id))
        else
            local transaction = {
                id = tonumber(row.id), locationId = tonumber(row.location_id), machineId = tonumber(row.machine_id), userId = tonumber(row.user_id),
                dirtyAmount = tonumber(row.dirty_amount), cleanAmount = tonumber(row.clean_amount),
                commissionAmount = tonumber(row.commission_amount), commissionPercent = tonumber(row.commission_percent),
                endsAt = tonumber(row.ends_at) or os.time(), status = row.status, receipt = row.receipt_code,
            }
            if transaction.status == 'processing' and os.time() >= transaction.endsAt then transaction.status = 'ready' end
            if transaction.machineId and machinesById[transaction.machineId] then
                activeByMachine[transaction.machineId] = transaction
                activeByUser[transaction.userId] = transaction
            else
                OR.Database.update.await("UPDATE ob_moneywash_transactions SET status='review',integrity_note='Maquina da transacao indisponivel' WHERE id=?", { transaction.id })
            end
        end
    end
    return true
end

local function userTransaction(source)
    local userId = tonumber(exports.ob_core:GetUserId(source))
    return userId, userId and activeByUser[userId] or nil
end

OR.Callback.register('locations', function(source)
    if not databaseReady then return nil, 'Sistema de lavagem ainda esta iniciando.' end
    local states = {}
    for machineId in pairs(machinesById) do states[#states + 1] = statePayload(machineId) end
    local _, transaction = userTransaction(source)
    return { locations = publicLocations(false), states = states, transaction = transactionPayload(transaction) }
end)

OR.Callback.register('interaction', function(source, rawLocationId)
    if not databaseReady then return nil, 'Sistema de lavagem indisponivel.' end
    local location = locations[tonumber(rawLocationId)]
    if not location or not location.enabled then return nil, 'Lavagem indisponivel.' end
    if not playerNear(source, location.ped) then return nil, 'Fale com o atendente.' end
    local allowed, accessError = canUseLocation(source, location)
    if not allowed then return nil, accessError end
    local userId, transaction = userTransaction(source)
    if not userId then return nil, 'Personagem indisponivel.' end
    if transaction and transaction.locationId ~= location.id then
        return nil, 'Sua lavagem em andamento esta em outro local.'
    end
    local hasFreeMachine = false
    for _, machine in ipairs(location.machines or {}) do
        if machine.enabled and not activeByMachine[machine.id] and not machineLocks[machine.id] then hasFreeMachine = true; break end
    end
    return {
        location = location,
        dirtyBalance = tonumber(exports.ob_inventory:GetMoney(source, OBMoneyWash.DirtyAccount)) or 0,
        transaction = transactionPayload(transaction),
        occupied = not transaction and not hasFreeMachine,
    }
end, { rateLimit = { limit = 8, window = 10000 } })

OR.Callback.register('start', function(source, rawLocationId, rawAmount)
    if not databaseReady then return nil, 'Sistema de lavagem indisponivel.' end
    local location = locations[tonumber(rawLocationId)]
    if not location or not location.enabled then return nil, 'Lavagem indisponivel.' end
    if not playerNear(source, location.ped) then return nil, 'Fale com o atendente para iniciar.' end
    local allowed, accessError = canUseLocation(source, location)
    if not allowed then return nil, accessError end

    local userId, existing = userTransaction(source)
    if not userId then return nil, 'Personagem indisponivel.' end
    if existing then return nil, 'Voce ja possui uma lavagem em andamento.' end
    local machine
    for _, candidate in ipairs(location.machines or {}) do
        if candidate.enabled and not activeByMachine[candidate.id] and not machineLocks[candidate.id] then machine = candidate; break end
    end
    if not machine then return nil, 'Todas as maquinas deste local estao ocupadas.' end

    local amount = math.floor(tonumber(rawAmount) or 0)
    if amount < location.minimumAmount or amount > location.maximumAmount then
        return nil, ('Informe um valor entre $%s e $%s.'):format(location.minimumAmount, location.maximumAmount)
    end
    local dirtyBefore = tonumber(exports.ob_inventory:GetMoney(source, OBMoneyWash.DirtyAccount)) or 0
    if dirtyBefore < amount then return nil, 'Dinheiro sujo insuficiente.' end

    local commissionAmount = math.floor(amount * location.commissionPercent / 100)
    local cleanAmount = amount - commissionAmount
    if cleanAmount < 1 then return nil, 'O valor liquido desta lavagem seria zero.' end

    local transaction = {
        id = 0, reservationToken = ('%s:%s:%s'):format(userId, machine.id, GetGameTimer()),
        locationId = location.id, machineId = machine.id, userId = userId,
        dirtyAmount = amount, commissionAmount = commissionAmount, cleanAmount = cleanAmount,
        commissionPercent = location.commissionPercent,
        endsAt = os.time() + (OBMoneyWash.ReservationSeconds or 120), status = 'reserved',
    }
    activeByMachine[machine.id], activeByUser[userId] = transaction, transaction
    broadcastState(machine.id)
    audit('machine_reserved', nil, userId, location.id, {
        machineId = machine.id, amount = amount, expiresAt = transaction.endsAt,
    }, { dirty = dirtyBefore })
    return transactionPayload(transaction)
end, { rateLimit = { limit = 2, window = 10000 } })

OR.Callback.register('deposit', function(source, rawMachineId)
    if not databaseReady then return nil, 'Sistema de lavagem indisponivel.' end
    local machine = machinesById[tonumber(rawMachineId)]
    local location = machine and locations[machine.locationId]
    if not machine or not location or not location.enabled or not machine.enabled then return nil, 'Maquina indisponivel.' end
    local allowed, accessError = canUseLocation(source, location)
    if not allowed then return nil, accessError end
    local userId, transaction = userTransaction(source)
    if not transaction or transaction.status ~= 'reserved' or transaction.machineId ~= machine.id then
        return nil, 'Esta maquina nao foi reservada para voce.'
    end
    if os.time() > transaction.endsAt then return nil, 'Sua reserva expirou. Fale novamente com o atendente.' end
    if not playerNear(source, machine.action, OBMoneyWash.MachineServerDistanceTolerance or 2.0) then return nil, 'Aproxime-se da maquina reservada.' end
    if machineLocks[machine.id] then return nil, 'Aguarde a operacao atual.' end
    machineLocks[machine.id] = true
    local function refuse(message)
        machineLocks[machine.id] = nil
        return nil, message
    end

    local dirtyBefore = tonumber(exports.ob_inventory:GetMoney(source, OBMoneyWash.DirtyAccount)) or 0
    if dirtyBefore < transaction.dirtyAmount then return refuse('Dinheiro sujo insuficiente.') end

    local removed, removeError = exports.ob_inventory:RemoveMoney(source, OBMoneyWash.DirtyAccount, transaction.dirtyAmount)
    if not removed then return refuse(removeError or 'Nao foi possivel retirar o dinheiro sujo.') end
    local dirtyAfter = tonumber(exports.ob_inventory:GetMoney(source, OBMoneyWash.DirtyAccount))
    local integrityNote
    if dirtyAfter == nil or dirtyAfter ~= dirtyBefore - transaction.dirtyAmount then
        integrityNote = ('Saldo sujo inesperado: antes=%s depois=%s esperado=%s'):format(
            dirtyBefore, tostring(dirtyAfter), dirtyBefore - transaction.dirtyAmount)
    end

    local endsAt = os.time() + location.durationSeconds
    local transactionId, insertError = OR.Database.insert.await([[INSERT INTO ob_moneywash_transactions
        (location_id,machine_id,user_id,dirty_amount,commission_percent,commission_amount,clean_amount,status,finish_at,
        dirty_balance_before,dirty_balance_after,integrity_note)
        VALUES (?,?,?,?,?,?,?,'processing',FROM_UNIXTIME(?),?,?,NULL)]], {
        location.id, machine.id, userId, transaction.dirtyAmount, transaction.commissionPercent,
        transaction.commissionAmount, transaction.cleanAmount, endsAt,
        dirtyBefore, dirtyAfter or 0,
    })
    if not transactionId then
        exports.ob_inventory:AddMoney(source, OBMoneyWash.DirtyAccount, transaction.dirtyAmount)
        audit('start_rolled_back', nil, userId, location.id, {
            machineId = machine.id, amount = transaction.dirtyAmount, reason = insertError or 'Falha ao inserir transacao',
        }, { dirty = exports.ob_inventory:GetMoney(source, OBMoneyWash.DirtyAccount) })
        return refuse(insertError or 'Nao foi possivel iniciar a lavagem. O valor foi devolvido.')
    end

    transactionId = tonumber(transactionId)
    local receipt = ('LW-%08d'):format(transactionId)
    OR.Database.update.await('UPDATE ob_moneywash_transactions SET receipt_code = ? WHERE id = ?', { receipt, transactionId })
    if integrityNote then
        OR.Database.update.await('UPDATE ob_moneywash_transactions SET integrity_note = ? WHERE id = ?', {
            integrityNote, transactionId,
        })
    end
    audit('wash_started', transactionId, userId, location.id, {
        receipt = receipt, machineId = machine.id, dirtyAmount = transaction.dirtyAmount,
        commissionPercent = transaction.commissionPercent,
        commissionAmount = transaction.commissionAmount, cleanAmount = transaction.cleanAmount, finishAt = endsAt,
        integrityNote = integrityNote,
    }, { dirty = dirtyAfter })

    transaction.id, transaction.receipt, transaction.endsAt, transaction.status = transactionId, receipt, endsAt, 'processing'
    transaction.reservationToken = nil
    machineLocks[machine.id] = nil
    broadcastState(machine.id)
    print(('[ob_moneywash] ID %s iniciou #%s em %s/maquina %s: sujo=%s taxa=%s liquido=%s.'):format(
        userId, transaction.id, location.id, machine.id, transaction.dirtyAmount,
        transaction.commissionAmount, transaction.cleanAmount))
    return transactionPayload(transaction)
end, { rateLimit = { limit = 2, window = 10000 } })

OR.Callback.register('collect', function(source, rawMachineId)
    if not databaseReady then return nil, 'Sistema de lavagem indisponivel.' end
    local machine = machinesById[tonumber(rawMachineId)]
    local location = machine and locations[machine.locationId]
    if not machine or not location or not location.enabled then return nil, 'Lavagem indisponivel.' end
    if not playerNear(source, machine.action, OBMoneyWash.MachineServerDistanceTolerance or 2.0) then
        return nil, 'Aproxime-se da maquina.'
    end
    local userId, transaction = userTransaction(source)
    if not transaction or transaction.machineId ~= machine.id then return nil, 'Este dinheiro nao pertence a voce.' end
    if os.time() < transaction.endsAt then return nil, 'A lavagem ainda nao terminou.' end

    local cleanBefore = tonumber(exports.ob_inventory:GetMoney(source, OBMoneyWash.CleanAccount))
    if cleanBefore == nil then return nil, 'Nao foi possivel confirmar o saldo limpo antes do pagamento.' end
    local changed, updateError = OR.Database.update.await([[UPDATE ob_moneywash_transactions
        SET status = 'paying', payout_started_at = NOW(), clean_balance_before = ?
        WHERE id = ? AND user_id = ? AND status IN ('processing','ready') AND finish_at <= NOW()]],
        { cleanBefore, transaction.id, userId })
    if not changed or changed < 1 then return nil, updateError or 'Pagamento ja processado ou indisponivel.' end
    transaction.status = 'paying'
    audit('payout_claimed', transaction.id, userId, location.id, {
        receipt = transaction.receipt, cleanAmount = transaction.cleanAmount,
    }, { clean = cleanBefore })

    local paid, payError = exports.ob_inventory:AddMoney(source, OBMoneyWash.CleanAccount, transaction.cleanAmount)
    if not paid then
        transaction.status = 'ready'
        OR.Database.update.await("UPDATE ob_moneywash_transactions SET status = 'ready' WHERE id = ? AND status = 'paying'", { transaction.id })
        audit('payout_failed', transaction.id, userId, location.id, {
            receipt = transaction.receipt, error = payError or 'AddMoney recusou o pagamento',
        }, { clean = cleanBefore })
        return nil, payError or 'Nao foi possivel guardar o dinheiro limpo.'
    end
    local cleanAfter = tonumber(exports.ob_inventory:GetMoney(source, OBMoneyWash.CleanAccount))
    local confirmed = cleanAfter ~= nil and cleanAfter == cleanBefore + transaction.cleanAmount
    local integrityNote = confirmed and nil or ('Pagamento retornou sucesso, mas saldo divergiu: antes=%s depois=%s esperado=%s'):format(
        tostring(cleanBefore), tostring(cleanAfter), tostring(cleanBefore + transaction.cleanAmount))
    if confirmed then
        OR.Database.update.await([[UPDATE ob_moneywash_transactions SET status = 'completed', clean_balance_after = ?,
            payout_confirmed_at = NOW(), completed_at = NOW() WHERE id = ?]], { cleanAfter, transaction.id })
    else
        OR.Database.update.await([[UPDATE ob_moneywash_transactions SET status = 'review', clean_balance_after = ?,
            completed_at = NOW(), integrity_note = ? WHERE id = ?]], { cleanAfter or 0, integrityNote, transaction.id })
    end
    audit(confirmed and 'payout_confirmed' or 'payout_needs_review', transaction.id, userId, location.id, {
        receipt = transaction.receipt, cleanAmount = transaction.cleanAmount,
        expectedBalance = cleanBefore + transaction.cleanAmount, confirmed = confirmed, note = integrityNote,
    }, { clean = cleanAfter })
    activeByMachine[machine.id], activeByUser[userId] = nil, nil
    broadcastState(machine.id)
    print(('[ob_moneywash] ID %s recebeu $%s da lavagem #%s (%s, confirmado=%s).'):format(
        userId, transaction.cleanAmount, transaction.id, transaction.receipt or '-', tostring(confirmed)))
    return {
        amount = transaction.cleanAmount, commission = transaction.commissionAmount,
        receipt = transaction.receipt, confirmed = confirmed,
    }
end, { rateLimit = { limit = 2, window = 10000 } })

OR.Callback.register('adminData', function(source)
    if not hasAdmin(source) then return nil, 'Sem permissao para editar lavagens.' end
    return { locations = publicLocations(true), defaults = OBMoneyWash.Default }
end)

local allowedLogStatuses = {
    processing = true, ready = true, paying = true, completed = true, refunded = true, review = true,
}

OR.Callback.register('adminLogs', function(source, rawFilters)
    if not hasAdmin(source) then return nil, 'Sem permissao para consultar auditoria.' end
    rawFilters = type(rawFilters) == 'table' and rawFilters or {}
    local clauses, parameters = {}, {}
    local search = trim(rawFilters.search, 48)
    local status = trim(rawFilters.status, 16):lower()
    local locationId = tonumber(rawFilters.locationId)
    if search ~= '' then
        local numeric = tonumber(search)
        if numeric and numeric > 0 and numeric == math.floor(numeric) then
            clauses[#clauses + 1] = '(t.id = ? OR t.user_id = ? OR t.location_id = ?)'
            parameters[#parameters + 1], parameters[#parameters + 1], parameters[#parameters + 1] = numeric, numeric, numeric
        else
            local like = ('%%%s%%'):format(search)
            clauses[#clauses + 1] = "(t.receipt_code LIKE ? OR CONCAT(COALESCE(c.firstname,''),' ',COALESCE(c.lastname,'')) LIKE ? OR l.label LIKE ?)"
            parameters[#parameters + 1], parameters[#parameters + 1], parameters[#parameters + 1] = like, like, like
        end
    end
    if allowedLogStatuses[status] then clauses[#clauses + 1] = 't.status = ?'; parameters[#parameters + 1] = status end
    if locationId and locations[locationId] then clauses[#clauses + 1] = 't.location_id = ?'; parameters[#parameters + 1] = locationId end
    local where = #clauses > 0 and ('WHERE ' .. table.concat(clauses, ' AND ')) or ''
    local rows, queryError = OR.Database.query.await(([[SELECT t.id,t.receipt_code,t.location_id,l.label AS location_label,
        t.user_id,CONCAT(COALESCE(c.firstname,''),' ',COALESCE(c.lastname,'')) AS character_name,
        t.dirty_amount,t.commission_percent,t.commission_amount,t.clean_amount,t.status,
        t.dirty_balance_before,t.dirty_balance_after,t.clean_balance_before,t.clean_balance_after,
        t.integrity_note,DATE_FORMAT(t.started_at,'%%d/%%m/%%Y %%H:%%i:%%s') AS started_at,
        DATE_FORMAT(t.finish_at,'%%d/%%m/%%Y %%H:%%i:%%s') AS finish_at,
        DATE_FORMAT(t.completed_at,'%%d/%%m/%%Y %%H:%%i:%%s') AS completed_at
        FROM ob_moneywash_transactions t
        LEFT JOIN ob_moneywash_locations l ON l.id=t.location_id
        LEFT JOIN ob_characters c ON c.user_id=t.user_id %s
        ORDER BY t.id DESC LIMIT 100]]):format(where), parameters)
    if not rows then return nil, queryError or 'Nao foi possivel consultar as transacoes.' end

    local reviewCount = tonumber(OR.Database.scalar.await("SELECT COUNT(*) FROM ob_moneywash_transactions WHERE status = 'review'")) or 0
    local duplicatePayouts = tonumber(OR.Database.scalar.await([[SELECT COUNT(*) FROM (
        SELECT transaction_id FROM ob_moneywash_audit WHERE event_type='payout_confirmed' AND transaction_id IS NOT NULL
        GROUP BY transaction_id HAVING COUNT(*) > 1) duplicated]])) or 0
    local totals = OR.Database.single.await([[SELECT COUNT(*) AS operations,
        COALESCE(SUM(dirty_amount),0) AS dirty_total,COALESCE(SUM(clean_amount),0) AS clean_total
        FROM ob_moneywash_transactions WHERE started_at >= CURDATE()]]) or {}
    return {
        rows = rows,
        summary = {
            reviewCount = reviewCount, duplicatePayouts = duplicatePayouts,
            operationsToday = tonumber(totals.operations) or 0,
            dirtyToday = tonumber(totals.dirty_total) or 0,
            cleanToday = tonumber(totals.clean_total) or 0,
        },
    }
end, { rateLimit = { limit = 8, window = 10000 } })

OR.Callback.register('adminLogDetails', function(source, rawTransactionId)
    if not hasAdmin(source) then return nil, 'Sem permissao para consultar auditoria.' end
    local transactionId = tonumber(rawTransactionId)
    if not transactionId then return nil, 'Transacao invalida.' end
    local events, queryError = OR.Database.query.await([[SELECT id,event_type,dirty_balance,clean_balance,details,
        DATE_FORMAT(created_at,'%d/%m/%Y %H:%i:%s.%f') AS created_at
        FROM ob_moneywash_audit WHERE transaction_id = ? ORDER BY id ASC]], { transactionId })
    if not events then return nil, queryError or 'Nao foi possivel consultar os eventos.' end
    for _, event in ipairs(events) do
        local ok, decoded = pcall(json.decode, event.details or '{}')
        event.details = ok and decoded or { raw = event.details }
    end
    return events
end, { rateLimit = { limit = 10, window = 10000 } })

local function coordinates(raw, name)
    raw = type(raw) == 'table' and raw or {}
    local x, y, z, w = number(raw.x), number(raw.y), number(raw.z), number(raw.w)
    if not x or not y or not z or not w or math.abs(x) > 10000 or math.abs(y) > 10000 or math.abs(z) > 2000 then
        return nil, ('Coordenadas de %s invalidas.'):format(name)
    end
    return { x = x, y = y, z = z, w = w % 360.0 }
end

OR.Callback.register('adminSave', function(source, raw)
    if not hasAdmin(source) then return nil, 'Sem permissao para editar lavagens.' end
    raw = type(raw) == 'table' and raw or {}
    local ped, pedError = coordinates(raw.ped, 'atendente')
    if not ped then return nil, pedError end

    local defaults = OBMoneyWash.Default
    local submittedMachines = type(raw.machines) == 'table' and raw.machines or {}
    if #submittedMachines < 1 or #submittedMachines > 20 then return nil, 'Cadastre entre 1 e 20 maquinas.' end
    local machineRows = {}
    for index, submitted in ipairs(submittedMachines) do
        local machine, machineError = coordinates(submitted, ('maquina %s'):format(index))
        if not machine then return nil, machineError end
        local action, actionError = coordinates(submitted.action, ('animacao da maquina %s'):format(index))
        if not action then return nil, actionError end
        if #(vector3(ped.x, ped.y, ped.z) - vector3(machine.x, machine.y, machine.z)) > 30.0 then
            return nil, ('A maquina %s deve ficar a no maximo 30 metros do atendente.'):format(index)
        end
        if #(vector3(action.x, action.y, action.z) - vector3(machine.x, machine.y, machine.z)) > 3.0 then
            return nil, ('A animacao da maquina %s deve ficar a no maximo 3 metros dela.'):format(index)
        end
        local machineModel = validModel(submitted.model, defaults.machineModel)
        local openModel = validModel(submitted.openModel, defaults.machineOpenModel)
        local spinModel = validModel(submitted.spinModel, defaults.machineSpinModel)
        if not machineModel or not openModel or not spinModel then return nil, ('Modelo invalido na maquina %s.'):format(index) end
        machineRows[#machineRows + 1] = {
            label = trim(submitted.label, 80) ~= '' and trim(submitted.label, 80) or ('Maquina %s'):format(index),
            enabled = submitted.enabled ~= false, model = machineModel, openModel = openModel, spinModel = spinModel,
            x = machine.x, y = machine.y, z = machine.z, w = machine.w, action = action,
        }
    end
    local firstMachine = machineRows[1]
    local row = {
        id = tonumber(raw.id), label = trim(raw.label, 80), enabled = raw.enabled ~= false,
        commission = integer(raw.commissionPercent, 0, 95, defaults.commissionPercent),
        duration = integer(raw.durationSeconds, 10, 3600, defaults.durationSeconds),
        minimum = integer(raw.minimumAmount, 1, 1000000000, defaults.minimumAmount),
        maximum = integer(raw.maximumAmount, 1, 1000000000, defaults.maximumAmount),
        accessGroup = trim(raw.accessGroup, 64):lower(),
        pedModel = validModel(raw.ped and raw.ped.model, defaults.pedModel),
        pedScenario = trim(raw.ped and raw.ped.scenario, 96),
    }
    if row.label == '' then row.label = defaults.label end
    if row.pedScenario == '' then row.pedScenario = defaults.pedScenario end
    if not row.pedModel then return nil, 'O modelo do atendente e invalido.' end
    if row.accessGroup ~= '' and not row.accessGroup:match('^[%w_%-%.]+$') then return nil, 'Grupo de acesso invalido.' end
    if row.maximum < row.minimum then return nil, 'O valor maximo deve ser maior ou igual ao minimo.' end
    if row.id then
        for _, transaction in pairs(activeByMachine) do
            if transaction.locationId == row.id then return nil, 'Aguarde as maquinas ficarem livres antes de editar este local.' end
        end
    end

    local parameters = {
        row.label, row.enabled and 1 or 0, row.commission, row.duration, row.minimum, row.maximum,
        row.accessGroup,
        row.pedModel, row.pedScenario, ped.x, ped.y, ped.z, ped.w,
        firstMachine.model, firstMachine.openModel, firstMachine.spinModel,
        firstMachine.x, firstMachine.y, firstMachine.z, firstMachine.w,
        firstMachine.action.x, firstMachine.action.y, firstMachine.action.z, firstMachine.action.w,
    }
    local id, saveError
    if row.id and locations[row.id] then
        parameters[#parameters + 1] = row.id
        local changed
        changed, saveError = OR.Database.update.await([[UPDATE ob_moneywash_locations SET
            label=?,enabled=?,commission_percent=?,duration_seconds=?,minimum_amount=?,maximum_amount=?,
            access_group=?,
            ped_model=?,ped_scenario=?,ped_x=?,ped_y=?,ped_z=?,ped_w=?,
            machine_model=?,machine_open_model=?,machine_spin_model=?,machine_x=?,machine_y=?,machine_z=?,machine_w=?,
            action_x=?,action_y=?,action_z=?,action_w=? WHERE id=?]], parameters)
        if changed == nil then return nil, saveError or 'Falha ao atualizar lavagem.' end
        id = row.id
    else
        parameters[#parameters + 1] = tonumber(exports.ob_core:GetUserId(source))
        id, saveError = OR.Database.insert.await([[INSERT INTO ob_moneywash_locations
            (label,enabled,commission_percent,duration_seconds,minimum_amount,maximum_amount,access_group,
            ped_model,ped_scenario,ped_x,ped_y,ped_z,ped_w,
            machine_model,machine_open_model,machine_spin_model,machine_x,machine_y,machine_z,machine_w,
            action_x,action_y,action_z,action_w,created_by) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)]], parameters)
        if not id then return nil, saveError or 'Falha ao criar lavagem.' end
    end

    local removed, removeError = OR.Database.update.await('DELETE FROM ob_moneywash_machines WHERE location_id=?', { id })
    if removed == nil then return nil, removeError or 'Falha ao atualizar as maquinas.' end
    for index, machine in ipairs(machineRows) do
        local machineId, machineInsertError = OR.Database.insert.await([[INSERT INTO ob_moneywash_machines
            (location_id,label,enabled,machine_model,machine_open_model,machine_spin_model,
            machine_x,machine_y,machine_z,machine_w,action_x,action_y,action_z,action_w,sort_order)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)]], {
            id, machine.label, machine.enabled and 1 or 0, machine.model, machine.openModel, machine.spinModel,
            machine.x, machine.y, machine.z, machine.w,
            machine.action.x, machine.action.y, machine.action.z, machine.action.w, index,
        })
        if not machineId then return nil, machineInsertError or ('Falha ao salvar maquina %s.'):format(index) end
    end

    local savedRow = OR.Database.single.await('SELECT * FROM ob_moneywash_locations WHERE id = ? LIMIT 1', { id })
    if not savedRow then return nil, 'Lavagem salva, mas nao foi possivel recarrega-la.' end
    local saved = normalize(savedRow)
    for machineId, machine in pairs(machinesById) do
        if machine.locationId == saved.id then machinesById[machineId] = nil end
    end
    local savedMachines = OR.Database.query.await('SELECT * FROM ob_moneywash_machines WHERE location_id=? ORDER BY sort_order,id', { id }) or {}
    for _, machineRow in ipairs(savedMachines) do
        local machine = normalizeMachine(machineRow)
        machinesById[machine.id] = machine
        saved.machines[#saved.machines + 1] = machine
    end
    locations[saved.id] = saved
    TriggerClientEvent('ob_moneywash:client:locationSaved', -1, saved)
    return saved, 'Lavagem salva.'
end, { rateLimit = { limit = 5, window = 10000 } })

OR.Callback.register('adminDelete', function(source, rawId)
    if not hasAdmin(source) then return nil, 'Sem permissao para excluir lavagens.' end
    local id = tonumber(rawId)
    if not id or not locations[id] then return nil, 'Lavagem nao encontrada.' end
    for _, transaction in pairs(activeByMachine) do
        if transaction.locationId == id then return nil, 'Aguarde as lavagens atuais serem retiradas antes de excluir.' end
    end
    local changed, deleteError = OR.Database.update.await('DELETE FROM ob_moneywash_locations WHERE id = ?', { id })
    if not changed or changed < 1 then return nil, deleteError or 'Nao foi possivel excluir a lavagem.' end
    for machineId, machine in pairs(machinesById) do
        if machine.locationId == id then machinesById[machineId] = nil end
    end
    locations[id] = nil
    TriggerClientEvent('ob_moneywash:client:locationDeleted', -1, id)
    return true, 'Lavagem excluida.'
end, { rateLimit = { limit = 3, window = 10000 } })

OR.Callback.register('adminTeleport', function(source, rawId)
    if not hasAdmin(source) then return nil, 'Sem permissao.' end
    local location = locations[tonumber(rawId)]
    return location and location.ped or nil, location and nil or 'Lavagem nao encontrada.'
end)

local function ensureTransactionColumn(column, definition)
    local exists = OR.Database.scalar.await([[SELECT 1 FROM information_schema.columns
        WHERE table_schema=DATABASE() AND table_name='ob_moneywash_transactions' AND column_name=? LIMIT 1]], { column })
    if exists then return true end
    local result, alterError = OR.Database.query.await(('ALTER TABLE ob_moneywash_transactions ADD COLUMN %s'):format(definition))
    if result == nil then print(('[ob_moneywash] Falha ao adicionar coluna %s: %s'):format(column, alterError or '?')); return false end
    return true
end

local function ensureLocationColumn(column, definition)
    local exists = OR.Database.scalar.await([[SELECT 1 FROM information_schema.columns
        WHERE table_schema=DATABASE() AND table_name='ob_moneywash_locations' AND column_name=? LIMIT 1]], { column })
    if exists then return true end
    local result, alterError = OR.Database.query.await(('ALTER TABLE ob_moneywash_locations ADD COLUMN %s'):format(definition))
    if result == nil then print(('[ob_moneywash] Falha ao adicionar coluna %s: %s'):format(column, alterError or '?')); return false end
    return true
end

CreateThread(function()
    local charactersReady = false
    for _ = 1, 30 do
        local exists = OR.Database.scalar.await([[SELECT 1 FROM information_schema.tables
            WHERE table_schema = DATABASE() AND table_name = 'ob_characters' LIMIT 1]])
        if exists then charactersReady = true; break end
        Wait(500)
    end
    if not charactersReady then
        print('[ob_moneywash] Tabela ob_characters indisponivel; as tabelas de lavagem nao foram criadas.')
        return
    end
    local firstOk, firstError = OR.Database.query.await(schema)
    local machineOk, machineError = OR.Database.query.await(machineSchema)
    local secondOk, secondError = OR.Database.query.await(transactionSchema)
    local thirdOk, thirdError = OR.Database.query.await(auditSchema)
    if firstOk == nil or machineOk == nil or secondOk == nil or thirdOk == nil then
        print(('[ob_moneywash] Falha ao preparar tabelas: %s / %s / %s / %s'):format(
            firstError or '?', machineError or '?', secondError or '?', thirdError or '?'))
        return
    end
    if not ensureLocationColumn('access_group', 'access_group VARCHAR(64) NULL') then return end
    local migrations = {
        { 'machine_id', 'machine_id INT UNSIGNED NULL AFTER location_id' },
        { 'receipt_code', 'receipt_code VARCHAR(32) NULL' },
        { 'dirty_balance_before', 'dirty_balance_before BIGINT UNSIGNED NULL' },
        { 'dirty_balance_after', 'dirty_balance_after BIGINT UNSIGNED NULL' },
        { 'clean_balance_before', 'clean_balance_before BIGINT UNSIGNED NULL' },
        { 'clean_balance_after', 'clean_balance_after BIGINT UNSIGNED NULL' },
        { 'payout_started_at', 'payout_started_at DATETIME NULL' },
        { 'payout_confirmed_at', 'payout_confirmed_at DATETIME NULL' },
        { 'integrity_note', 'integrity_note VARCHAR(255) NULL' },
    }
    for _, migration in ipairs(migrations) do
        if not ensureTransactionColumn(migration[1], migration[2]) then return end
    end
    local migratedMachines, migratedMachineError = OR.Database.update.await([[INSERT INTO ob_moneywash_machines
        (location_id,label,enabled,machine_model,machine_open_model,machine_spin_model,
        machine_x,machine_y,machine_z,machine_w,action_x,action_y,action_z,action_w,sort_order)
        SELECT l.id,'Maquina 1',1,l.machine_model,l.machine_open_model,l.machine_spin_model,
        l.machine_x,l.machine_y,l.machine_z,l.machine_w,l.action_x,l.action_y,l.action_z,l.action_w,1
        FROM ob_moneywash_locations l
        WHERE NOT EXISTS (SELECT 1 FROM ob_moneywash_machines m WHERE m.location_id=l.id)]])
    if migratedMachines == nil then
        print(('[ob_moneywash] Falha ao migrar maquinas antigas: %s'):format(migratedMachineError or '?'))
        return
    end
    OR.Database.update.await([[UPDATE ob_moneywash_transactions t
        JOIN (SELECT location_id,MIN(id) AS machine_id FROM ob_moneywash_machines GROUP BY location_id) m
          ON m.location_id=t.location_id
        SET t.machine_id=m.machine_id WHERE t.machine_id IS NULL AND t.status IN ('processing','ready','paying')]])
    local enumOk, enumError = OR.Database.query.await([[ALTER TABLE ob_moneywash_transactions MODIFY COLUMN
        status ENUM('processing','ready','paying','completed','refunded','review') NOT NULL DEFAULT 'processing']])
    if enumOk == nil then print(('[ob_moneywash] Falha ao atualizar estados: %s'):format(enumError or '?')); return end
    OR.Database.update.await([[UPDATE ob_moneywash_transactions
        SET receipt_code=CONCAT('LW-',LPAD(id,8,'0')) WHERE receipt_code IS NULL OR receipt_code='']])
    local receiptIndex = OR.Database.scalar.await([[SELECT 1 FROM information_schema.statistics
        WHERE table_schema=DATABASE() AND table_name='ob_moneywash_transactions' AND index_name='uq_ob_moneywash_receipt' LIMIT 1]])
    if not receiptIndex then
        local indexOk, indexError = OR.Database.query.await('ALTER TABLE ob_moneywash_transactions ADD UNIQUE KEY uq_ob_moneywash_receipt (receipt_code)')
        if indexOk == nil then print(('[ob_moneywash] Falha ao criar indice de comprovante: %s'):format(indexError or '?')); return end
    end
    databaseReady = loadData()
    if databaseReady then print(('[ob_moneywash] %d lavagem(ns) carregada(s).'):format(#publicLocations(true))) end
end)

CreateThread(function()
    while true do
        Wait(1000)
        if databaseReady then
            local now = os.time()
            for machineId, transaction in pairs(activeByMachine) do
                if transaction.status == 'reserved' and now >= transaction.endsAt then
                    activeByMachine[machineId], activeByUser[transaction.userId] = nil, nil
                    broadcastState(machineId)
                    local target = exports.ob_core:GetSourceByUserId(transaction.userId)
                    if target then TriggerClientEvent('ob_notification:client:notify', target, 'Sua reserva da maquina expirou.', 'warning', 6000) end
                elseif transaction.status == 'processing' and now >= transaction.endsAt then
                    transaction.status = 'ready'
                    OR.Database.update.await("UPDATE ob_moneywash_transactions SET status = 'ready' WHERE id = ? AND status = 'processing'", { transaction.id })
                    broadcastState(machineId)
                    local target = exports.ob_core:GetSourceByUserId(transaction.userId)
                    if target then TriggerClientEvent('ob_notification:client:notify', target, 'A lavagem terminou. Retire o dinheiro na maquina amarela.', 'success', 8000) end
                end
            end
        end
    end
end)

AddEventHandler('ob_core:server:playerLoaded', function(source)
    if not databaseReady then return end
    TriggerClientEvent('ob_moneywash:client:bootstrap', source, publicLocations(false))
end)

