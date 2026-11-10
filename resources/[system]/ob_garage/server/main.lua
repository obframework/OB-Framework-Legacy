local activeVehicles = {}
local spawnReservations = {}
local schemaReady = false
local removeVehiclesWithExpiredTax
local findFreeVehicleInUse
local validTyreWheels = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [45] = true, [47] = true }

local function userId(source) return exports.ob_core:GetUserId(source) end
local function trim(value) return tostring(value or ''):gsub('^%s*(.-)%s*$', '%1') end
local function garage(id)
    id = tostring(id or ''):lower()
    return type(OBGarageDefinitions) == 'table' and OBGarageDefinitions[id]
        or type(GarageConfig.garages) == 'table' and GarageConfig.garages[id]
end

local function sharedPersonalGarage(place)
    return GarageConfig.SharedPersonalGarages == true and place
        and (place.vehicleType == nil or place.vehicleType == 'personal')
end

local function garageVehicleType(place)
    local vehicleType = place and tostring(place.vehicleType or 'personal'):lower() or 'personal'
    if vehicleType == 'service' or vehicleType == 'free' then return vehicleType end
    return 'personal'
end

local function garageGroupKey(garageId, place)
    local group = trim(place and place.sharedGroup):lower()
    return group ~= '' and group or tostring(garageId or ''):lower()
end

local function vehicleBelongsToGarageScope(garageId, place, vehicleGarage, vehicleType)
    vehicleType = tostring(vehicleType or 'personal'):lower()
    if sharedPersonalGarage(place) and vehicleType == 'personal' then return true end
    if vehicleType ~= garageVehicleType(place) then return false end
    local origin = garage(vehicleGarage)
    return origin ~= nil
        and garageVehicleType(origin) == garageVehicleType(place)
        and garageGroupKey(vehicleGarage, origin) == garageGroupKey(garageId, place)
end

local function garageSpawn(place, requestedIndex)
    local spawns = type(place and place.spawns) == 'table' and place.spawns or {}
    if #spawns == 0 and place and place.spawn then spawns = { place.spawn } end
    local index = math.floor(tonumber(requestedIndex) or 0)
    if index < 1 or index > #spawns then return nil end
    return spawns[index]
end

local function positiveInteger(value, fallback, maximum)
    value = math.floor(tonumber(value) or tonumber(fallback) or 1)
    return math.max(1, math.min(maximum or 3650, value))
end

local function taxSettings()
    local config = type(GarageConfig.Tax) == 'table' and GarageConfig.Tax or {}
    return {
        enabled = config.Enabled ~= false,
        intervalDays = positiveInteger(config.BillingIntervalDays, 7, 365),
        deleteAfterDays = positiveInteger(config.DeleteAfterOverdueDays, 14, 3650),
        personalRate = math.max(0.0, math.min(100.0, tonumber(config.PersonalRatePercent) or 15.0)),
        serviceRate = math.max(0.0, math.min(100.0, tonumber(config.ServiceRatePercent) or 5.0)),
        cleanupMinutes = positiveInteger(config.CleanupIntervalMinutes, 30, 1440),
        minimumCharge = math.max(0, math.floor(tonumber(config.MinimumCharge) or 1)),
    }
end

local function hasGarageAccess(source, place)
    local access = place and place.access
    if type(access) ~= 'table' or type(access.permission) ~= 'string' or access.permission == '' then
        return true
    end
    if GetResourceState('ob_org') ~= 'started' then
        return false, 'Sistema de organizacoes indisponivel.'
    end
    local ok, allowed = pcall(function()
        return exports.ob_org:HasPermission(source, access.permission, access.requireDuty == true)
    end)
    if ok and allowed == true then return true end
    if access.requireDuty == true then
        return false, 'Voce precisa da permissao exigida e estar em servico.'
    end
    return false, 'Voce nao possui permissao para esta garagem.'
end

local function playerNearGarage(source, place, distance)
    source = tonumber(source)
    local ped = source and GetPlayerPed(source) or 0
    return ped > 0 and place and #(GetEntityCoords(ped) - place.coords) <= (tonumber(distance) or 6.0)
end

local function vehicleTaxAmount(row)
    if tonumber(row.tax_exempt) == 1 or (tonumber(row.purchase_price) or 0) <= 0 then return 0 end
    local settings = taxSettings()
    if not settings.enabled then return 0 end
    local amount = math.ceil((tonumber(row.purchase_price) or 0) * (tonumber(row.tax_rate) or settings.personalRate) / 100.0)
    return math.max(settings.minimumCharge, amount)
end

local function taxStatus(row)
    local amount, dueAt = vehicleTaxAmount(row), tonumber(row.tax_due_unix)
    local now = tonumber(row.tax_now_unix) or os.time()
    local deadline = dueAt and dueAt + taxSettings().deleteAfterDays * 86400
    local overdue = amount > 0 and dueAt ~= nil and dueAt <= now
    return overdue, overdue and now >= deadline, deadline, now
end

local function payPlayer(source, amount, description, category, metadata, paymentAccount, fallbackAmount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount == 0 then return true, 'free' end
    local economyResult
    if type(paymentAccount) == 'string' and paymentAccount ~= '' then
        economyResult = OR.Economy.ChargeAccount(
            source, paymentAccount, amount, category or 'department_vehicle', description, metadata)
    else
        economyResult = OR.Economy.ChargePlayer(
            source, amount, category or 'garage_payment', description, metadata, 'city_treasury')
    end
    if economyResult.handled == true then
        if economyResult.success == true then return true, economyResult end
        return false, economyResult.error or 'Pagamento recusado pela economia.'
    end
    amount = math.max(0, math.floor(tonumber(fallbackAmount) or amount))
    if amount == 0 then return true, 'free' end
    local paid, paymentError
    if GetResourceState('ob_bank') == 'started' then
        paid, paymentError = exports.ob_bank:PayWithCard(source, amount, description)
        if paid == true then return true, 'card' end
    end
    if GetResourceState('ob_inventory') ~= 'started' then return false, paymentError or 'Sistema de pagamento indisponivel.' end
    if (exports.ob_inventory:GetMoney(source, 'money') or 0) < amount then
        return false, paymentError or 'Saldo no cartao e dinheiro em maos insuficientes.'
    end
    local removed, removeError = exports.ob_inventory:RemoveMoney(source, 'money', amount)
    return removed == true, removed == true and 'cash' or (removeError or paymentError or 'Pagamento recusado.')
end

local function refundPlayer(source, amount, method, description)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount == 0 then return true end
    if type(method) == 'table' and method.receipt then
        local result
        if method.method == 'account' then
            result = OR.Economy.RefundAccountCharge(source, method.receipt, description or 'Estorno de garagem')
        else
            result = OR.Economy.RefundCharge(source, method.receipt, description or 'Estorno de garagem')
        end
        if result.handled == true then return result.success == true end
        method = method.method == 'card' and 'card' or 'cash'
    end
    if method == 'card' and GetResourceState('ob_bank') == 'started' then
        return exports.ob_bank:RefundToBank(source, amount, description) == true
    end
    return GetResourceState('ob_inventory') == 'started' and exports.ob_inventory:AddMoney(source, 'money', amount) == true
end

local function cleanRemovedTyres(raw)
    local cleaned = {}
    for key, value in pairs(type(raw) == 'table' and raw or {}) do
        local wheel = math.floor(tonumber(key) or -1)
        if validTyreWheels[wheel] and value == true then cleaned[tostring(wheel)] = true end
    end
    return next(cleaned) and cleaned or nil
end

-- No Enhanced, o servidor pode devolver 1000 mesmo quando o dono da entidade
-- ve a carroceria ou o motor danificados. O evento ja valida dono, proximidade
-- e entidade; por isso a leitura do cliente dono e a fonte correta ao guardar.
local function reliableVehicleHealth(serverValue, clientValue)
    serverValue, clientValue = tonumber(serverValue), tonumber(clientValue)
    local selected = clientValue
    if selected == nil or selected < 0 or selected > 1000 then selected = serverValue end
    if not selected then selected = serverValue or 1000.0 end
    return math.max(0.0, math.min(1000.0, selected))
end

local function cleanTyreTypes(raw)
    local cleaned = {}
    for key, value in pairs(type(raw) == 'table' and raw or {}) do
        local wheel = math.floor(tonumber(key) or -1)
        if validTyreWheels[wheel] and value == 'tyre_armored' then cleaned[tostring(wheel)] = value end
    end
    return next(cleaned) and cleaned or nil
end

local function decodedProperties(raw)
    if type(raw) == 'table' then return raw end
    if type(raw) ~= 'string' or raw == '' then return {} end
    local ok, value = pcall(json.decode, raw)
    return ok and type(value) == 'table' and value or {}
end

local visualFlagKeys = { 'primaryCustom', 'secondaryCustom', 'neonEnabled', 'xenonEnabled', 'turboEnabled' }

local function visualFlagsFromProperties(raw)
    local properties = decodedProperties(raw)
    local neons = type(properties.neons) == 'table' and properties.neons or {}
    local toggles = type(properties.toggles) == 'table' and properties.toggles or {}
    return {
        primaryCustom = properties.primaryCustom == true,
        secondaryCustom = properties.secondaryCustom == true,
        neonEnabled = neons[0] == true or neons[1] == true or neons[2] == true or neons[3] == true
            or neons['0'] == true or neons['1'] == true or neons['2'] == true or neons['3'] == true,
        xenonEnabled = toggles[22] == true or toggles['22'] == true,
        turboEnabled = toggles[18] == true or toggles['18'] == true,
    }
end

local function mergeVisualFlags(base, raw)
    local flags = type(base) == 'table' and base or {}
    if type(raw) ~= 'table' then return flags end
    for _, key in ipairs(visualFlagKeys) do
        if type(raw[key]) == 'boolean' then flags[key] = raw[key] end
    end
    return flags
end

local function applyVisualFlags(properties, flags)
    if type(properties) ~= 'table' or type(flags) ~= 'table' then return properties end
    if type(flags.primaryCustom) == 'boolean' then properties.primaryCustom = flags.primaryCustom end
    if type(flags.secondaryCustom) == 'boolean' then properties.secondaryCustom = flags.secondaryCustom end
    if type(flags.neonEnabled) == 'boolean' then
        properties.neons = type(properties.neons) == 'table' and properties.neons or {}
        for side = 0, 3 do properties.neons[tostring(side)] = flags.neonEnabled end
    end
    if type(flags.xenonEnabled) == 'boolean' then
        properties.toggles = type(properties.toggles) == 'table' and properties.toggles or {}
        properties.toggles['22'] = flags.xenonEnabled
    end
    if type(flags.turboEnabled) == 'boolean' then
        properties.toggles = type(properties.toggles) == 'table' and properties.toggles or {}
        properties.toggles['18'] = flags.turboEnabled
    end
    return properties
end

-- Pneus removidos e blindados alteram inventario. Por isso esses dois campos
-- nunca sao aceitos do payload do cliente ao guardar o veiculo.
local function authoritativeTyreProperties(vehicle, raw)
    local properties = decodedProperties(raw)
    local entityState = Entity(vehicle).state
    properties.removedTyres = cleanRemovedTyres(entityState['ob:removed_tyres'])
    properties.tyreTypes = cleanTyreTypes(entityState['ob:tyre_types'])
    applyVisualFlags(properties, entityState['ob:visual_flags'])
    properties.hsw = nil
    return properties
end

local function restoreTyreState(vehicle, raw)
    local properties = decodedProperties(raw)
    local entityState = Entity(vehicle).state
    entityState:set('ob:removed_tyres', cleanRemovedTyres(properties.removedTyres), true)
    entityState:set('ob:tyre_types', cleanTyreTypes(properties.tyreTypes), true)
end

local function restoreVisualState(vehicle, raw)
    Entity(vehicle).state:set('ob:visual_flags', visualFlagsFromProperties(raw), true)
end

local function getVehicle(netId)
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    return vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and vehicle or nil
end

-- Um veiculo criado pelo cliente pode levar alguns frames para existir no
-- servidor. Sem esta espera a retirada ocasionalmente ficava sem a chave.
local function waitForVehicle(netId, timeout)
    -- Em OneSync/Enhanced a criacao no cliente pode levar alguns segundos ate
    -- a entidade aparecer no servidor. Aguardar mais aqui evita falha de
    -- chave temporaria sem gravar state bag pelo cliente.
    local deadline = GetGameTimer() + (tonumber(timeout) or 8000)
    local vehicle = getVehicle(netId)
    while not vehicle and GetGameTimer() < deadline do
        Wait(50)
        vehicle = getVehicle(netId)
    end
    return vehicle
end

local function createServerVehicle(source, model, coords, options)
    local result = exports.ob_core:CreateServerVehicle(source, model, coords, options)
    if type(result) ~= 'table' or result.ok ~= true or not tonumber(result.netId) then
        return nil, type(result) == 'table' and result.error or 'Reinicie o core para carregar o novo servico de veiculos.'
    end
    local entity = waitForVehicle(result.netId)
    if not entity then return nil, 'O veiculo criado nao foi sincronizado no servidor.' end
    return entity, nil, tonumber(result.netId)
end
local function spawnIsClear(coords, radius)
    return exports.ob_core:IsVehicleSpawnClear(coords, radius)
end

local function reserveGarageSpawn(garageId, place, requestedIndex)
    local requested = math.floor(tonumber(requestedIndex) or 0)
    if not garageSpawn(place, requested) then return nil, nil, 'Vaga de nascimento invalida.' end

    local slots = type(place.spawns) == 'table' and #place.spawns or 1
    local reserved = spawnReservations[garageId] or {}
    spawnReservations[garageId] = reserved
    for offset = 0, slots - 1 do
        local index = ((requested - 1 + offset) % slots) + 1
        local point = garageSpawn(place, index)
        if point and not reserved[index] and spawnIsClear(point, place.spawnClearRadius) then
            reserved[index] = true
            return index, point
        end
    end
    return nil, nil, 'Todas as vagas de saida estao ocupadas. Aguarde um veiculo sair.'
end

local function releaseGarageSpawn(garageId, index)
    local reserved = spawnReservations[garageId]
    if reserved and index then reserved[index] = nil end
end

local function playerNearVehicle(source, vehicle, range)
    -- Em eventos do FiveM o source pode chegar como texto ("1"). Os natives
    -- do servidor aceitam somente client id numerico.
    local clientId = tonumber(source)
    if not clientId then return false end
    local ped = GetPlayerPed(clientId)
    return ped and ped ~= 0 and #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) <= (range or 5.0)
end

local function setVehicleLocked(vehicle, locked)
    Entity(vehicle).state:set('ob:locked', locked == true, true)
end

local function setRegisteredVehicle(vehicle, locked)
    local state = Entity(vehicle).state
    state:set('ob:registered_vehicle', true, true)
    -- Veiculo proprio pode ser dirigido pelo dono mesmo quando as portas estao
    -- trancadas. Lockpick e exigida apenas em veiculos nao registrados.
    state:set('ob:lockpick_required', false, true)
    setVehicleLocked(vehicle, locked)
end

-- Compatibilidade: implementacoes compartilhadas estao fora da garagem.
exports('SpawnTemporaryVehicle', function(...) return exports.ob_core:SpawnTemporaryVehicle(...) end)
exports('DeleteTemporaryVehicle', function(...) return exports.ob_core:DeleteTemporaryVehicle(...) end)
exports('GrantTemporaryKey', function(...) return exports.ob_vehiclekeys:GrantTemporaryKey(...) end)
exports('GrantTemporaryVehicleKey', function(...) return exports.ob_vehiclekeys:GrantTemporaryVehicleKey(...) end)
exports('RevokeTemporaryKey', function(...) return exports.ob_vehiclekeys:RevokeTemporaryKey(...) end)
exports('BeginLockpick', function(...) return exports.ob_vehiclekeys:BeginLockpick(...) end)

local function ensureVehicleColumn(name, definition)
    local exists = OR.Database.scalar.await([[SELECT 1 FROM information_schema.columns
        WHERE table_schema = DATABASE() AND table_name = 'ob_vehicles' AND column_name = ? LIMIT 1]], { name })
    if exists then return true end
    local result, err = OR.Database.query.await(('ALTER TABLE ob_vehicles ADD COLUMN %s'):format(definition))
    if result == nil then
        print(('[ob_garage] Falha ao criar coluna %s: %s'):format(name, tostring(err)))
        return false
    end
    return true
end

CreateThread(function()
    if not OR.Database.waitForReady(30000) then return print('[ob_garage] Banco indisponivel.') end
    local created, createError = OR.Database.query.await([[CREATE TABLE IF NOT EXISTS ob_vehicles (
        id int unsigned NOT NULL AUTO_INCREMENT, owner_user_id bigint unsigned NOT NULL,
        plate varchar(16) NOT NULL, model varchar(64) NOT NULL, label varchar(96) NOT NULL,
        garage varchar(48) NOT NULL DEFAULT 'central', stored tinyint(1) NOT NULL DEFAULT 1,
        fuel decimal(6,2) NOT NULL DEFAULT 100, body decimal(7,2) NOT NULL DEFAULT 1000,
        engine decimal(7,2) NOT NULL DEFAULT 1000, properties longtext NULL,
        purchase_price bigint unsigned NOT NULL DEFAULT 0, vehicle_type varchar(16) NOT NULL DEFAULT 'personal',
        tax_rate decimal(6,3) DEFAULT NULL, tax_exempt tinyint(1) NOT NULL DEFAULT 0,
        acquired_at timestamp NOT NULL DEFAULT current_timestamp(), tax_due_at datetime DEFAULT NULL,
        updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
        PRIMARY KEY (id), UNIQUE KEY uq_ob_vehicles_plate (plate), KEY idx_ob_vehicles_owner (owner_user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    if created == nil then return print(('[ob_garage] Falha ao criar ob_vehicles: %s'):format(tostring(createError))) end

    local columnsReady = ensureVehicleColumn('purchase_price', '`purchase_price` bigint unsigned NOT NULL DEFAULT 0 AFTER `properties`')
        and ensureVehicleColumn('vehicle_type', "`vehicle_type` varchar(16) NOT NULL DEFAULT 'personal' AFTER `purchase_price`")
        and ensureVehicleColumn('tax_rate', '`tax_rate` decimal(6,3) DEFAULT NULL AFTER `vehicle_type`')
        and ensureVehicleColumn('tax_exempt', '`tax_exempt` tinyint(1) NOT NULL DEFAULT 0 AFTER `tax_rate`')
        and ensureVehicleColumn('acquired_at', '`acquired_at` timestamp NOT NULL DEFAULT current_timestamp() AFTER `tax_exempt`')
        and ensureVehicleColumn('tax_due_at', '`tax_due_at` datetime DEFAULT NULL AFTER `acquired_at`')
    if not columnsReady then return end

    -- Mantem um registro recuperavel da perda por IPVA, sem permitir que a
    -- importacao de ob_player_vehicles recrie o mesmo carro no proximo restart.
    local archive = OR.Database.query.await([[CREATE TABLE IF NOT EXISTS ob_vehicle_tax_repossessions (
        vehicle_id int unsigned NOT NULL PRIMARY KEY, owner_user_id bigint unsigned NOT NULL,
        plate varchar(16) NOT NULL, snapshot longtext NOT NULL,
        removed_at timestamp NOT NULL DEFAULT current_timestamp(),
        KEY idx_tax_repossessed_plate (plate, owner_user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    if archive == nil then return print('[ob_garage] Falha ao preparar historico de remocao por IPVA.') end

    OR.Database.query.await([[CREATE TABLE IF NOT EXISTS ob_vehicle_tax_payments (
        id bigint unsigned NOT NULL AUTO_INCREMENT, vehicle_id int unsigned NOT NULL,
        owner_user_id bigint unsigned NOT NULL, plate varchar(16) NOT NULL, amount int unsigned NOT NULL,
        previous_due_at datetime DEFAULT NULL, next_due_at datetime NOT NULL,
        paid_at timestamp NOT NULL DEFAULT current_timestamp(),
        PRIMARY KEY (id), KEY idx_ob_vehicle_tax_owner (owner_user_id), KEY idx_ob_vehicle_tax_vehicle (vehicle_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    -- Compras de uma versao anterior da concessionaria foram registradas em
    -- ob_player_vehicles. Esta migracao preserva esses veiculos na garagem e
    -- ignora placas que ja tenham sido trazidas antes.
    local legacy = OR.Database.scalar.await([[SELECT 1 FROM information_schema.tables
        WHERE table_schema = DATABASE() AND table_name = 'ob_player_vehicles' LIMIT 1]])
    if legacy then
        OR.Database.query.await([[INSERT IGNORE INTO ob_vehicles
            (owner_user_id, plate, model, label, garage, stored, fuel, body, engine, properties)
            SELECT user_id, plate, model, label, 'central', 1,
                100, 1000, 1000, properties
            FROM ob_player_vehicles legacy_vehicle
            WHERE NOT EXISTS (SELECT 1 FROM ob_vehicle_tax_repossessions removed
                WHERE removed.plate = legacy_vehicle.plate AND removed.owner_user_id = legacy_vehicle.user_id)]])
        OR.Database.query.await([[UPDATE ob_vehicles v
            INNER JOIN ob_player_vehicles legacy_vehicle ON legacy_vehicle.plate = v.plate
            SET v.acquired_at = legacy_vehicle.purchased_at
            WHERE v.vehicle_type = 'personal' AND v.purchase_price = 0]])
    end


    local catalogExists = OR.Database.scalar.await([[SELECT 1 FROM information_schema.tables
        WHERE table_schema = DATABASE() AND table_name = 'ob_carshop_vehicles' LIMIT 1]])
    if catalogExists then
        OR.Database.query.await([[UPDATE ob_vehicles v
            INNER JOIN (SELECT model, MAX(price) AS price FROM ob_carshop_vehicles GROUP BY model) catalog
                ON LOWER(catalog.model) = LOWER(v.model)
            SET v.purchase_price = catalog.price
            WHERE v.vehicle_type = 'personal' AND v.purchase_price = 0]])
    end

    local settings = taxSettings()
    if settings.enabled then
        OR.Database.update.await(([[UPDATE ob_vehicles SET tax_rate = ?, tax_due_at = DATE_ADD(acquired_at, INTERVAL %d DAY)
            WHERE tax_exempt = 0 AND purchase_price > 0 AND tax_due_at IS NULL]]):format(settings.intervalDays), {
            settings.personalRate
        })
    end
    -- Reassocia entidades existentes depois de restart, sem duplicar carros na retirada.
    local outside = OR.Database.query.await('SELECT id,plate,model FROM ob_vehicles WHERE stored=0') or {}
    local byPlate = {}
    for _, row in ipairs(outside) do byPlate[trim(row.plate)] = row end
    for _, entity in ipairs(GetAllVehicles()) do
        if DoesEntityExist(entity) then
            local row = byPlate[trim(GetVehicleNumberPlateText(entity))]
            if row and GetEntityModel(entity) == joaat(row.model) then
                activeVehicles[tonumber(row.id)] = { netId = NetworkGetNetworkIdFromEntity(entity) }
            end
        end
    end
    schemaReady = true
end)

local function listVehicles(source, garageId)
    local owner, place = userId(source), garage(garageId)
    if not schemaReady then return false, 'Garagem ainda esta iniciando.' end
    if not owner or not place then return false, 'Garagem invalida.' end
    local allowed, accessError = hasGarageAccess(source, place)
    if not allowed then return false, accessError end
    removeVehiclesWithExpiredTax(owner)
    local settings = taxSettings()
    local queriedRows = OR.Database.query.await([[SELECT id, plate, model, label, garage, stored, fuel, body, engine,
            purchase_price, vehicle_type, tax_rate, tax_exempt, UNIX_TIMESTAMP(acquired_at) AS acquired_unix,
            UNIX_TIMESTAMP(tax_due_at) AS tax_due_unix, UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) AS tax_now_unix
        FROM ob_vehicles WHERE owner_user_id = ? AND vehicle_type <> 'free'
        ORDER BY stored DESC, label ASC]], { owner }) or {}
    local rows = {}
    for _, row in ipairs(queriedRows) do
        if vehicleBelongsToGarageScope(garageId, place, row.garage, row.vehicle_type) then rows[#rows + 1] = row end
    end

    -- activeVehicles e uma tabela em memoria. Depois de restart ela zera; sem
    -- esta recuperacao o banco mantinha carros que ja nao existem como "fora"
    -- e o botao de retirar ficava bloqueado para sempre.
    for _, row in ipairs(rows) do
        if tonumber(row.stored) == 0 then
            local active = activeVehicles[tonumber(row.id)]
            local entity = active and getVehicle(active.netId)
            if not entity then
                OR.Database.update.await('UPDATE ob_vehicles SET stored = 1 WHERE id = ? AND owner_user_id = ? AND stored = 0', { row.id, owner })
                row.stored = 1
            end
        end
        row.taxAmount = vehicleTaxAmount(row)
        row.taxDueUnix = tonumber(row.tax_due_unix)
        row.acquiredUnix = tonumber(row.acquired_unix)
        local overdue, expired, deadline, now = taxStatus(row)
        row.taxDue = overdue
        row.taxExpired = expired
        row.taxRemovalUnix = deadline
        row.taxOverdueDays = overdue and math.floor((now - row.taxDueUnix) / 86400) or 0
        row.taxExempt = tonumber(row.tax_exempt) == 1 or row.taxAmount <= 0
        row.vehicleType = row.vehicle_type or 'personal'
        row.purchasePrice = tonumber(row.purchase_price) or 0
        row.taxRate = tonumber(row.tax_rate) or 0
        row.taxIntervalDays = settings.intervalDays
        row.deleteAfterOverdueDays = settings.deleteAfterDays
    end


    local economyStatus = OR.Economy.GetStatus()
    local departmentEconomyActive = place.vehicleType == 'service'
        and type(place.economyAccount) == 'string' and place.economyAccount ~= ''
        and economyStatus.handled == true and economyStatus.mode == 'active'
    local ownedModels = {}
    for _, row in ipairs(rows) do ownedModels[trim(row.model):lower()] = true end
    for _, entry in ipairs(type(place.vehicles) == 'table' and place.vehicles or {}) do
        local model = trim(entry.model):lower()
        if model ~= '' and (place.vehicleType == 'free' or not ownedModels[model]) then
            local fallbackPrice = math.max(0, math.floor(tonumber(entry.price) or 0))
            local price = departmentEconomyActive
                and math.max(0, math.floor(tonumber(entry.departmentPrice) or fallbackPrice)) or fallbackPrice
            local vehicleType = place.vehicleType or 'personal'
            local taxExempt = entry.taxExempt == true or place.taxExempt == true or price <= 0 or not settings.enabled
            local taxRate = tonumber(entry.taxRatePercent) or tonumber(place.taxRatePercent)
                or (vehicleType == 'service' and settings.serviceRate or settings.personalRate)
            local catalogRow = {
                id = ('catalog:%s'):format(model), catalog = true, catalogKey = model,
                model = model, label = trim(entry.label) ~= '' and trim(entry.label) or model:upper(),
                price = price, purchase_price = price, tax_rate = taxRate, tax_exempt = taxExempt and 1 or 0,
                vehicleType = vehicleType, taxExempt = taxExempt, taxRate = taxRate,
                taxIntervalDays = settings.intervalDays, deleteAfterOverdueDays = settings.deleteAfterDays,
                stored = 1, fuel = 100, body = 1000, engine = 1000,
            }
            if vehicleType == 'free' and findFreeVehicleInUse
                and findFreeVehicleInUse(owner, garageGroupKey(garageId, place), model) then
                catalogRow.inUse = true
            end
            catalogRow.taxAmount = vehicleTaxAmount(catalogRow)
            rows[#rows + 1] = catalogRow
        end
    end
    return true, rows
end

local function spawnOwnedVehicle(source, id, rawCoords, options)
    options = type(options) == 'table' and options or {}
    local owner = userId(source)
    if not owner then return false, 'Personagem indisponivel.' end
    if not schemaReady then return false, 'Garagem ainda esta iniciando.' end
    local row = OR.Database.single.await([[SELECT *, UNIX_TIMESTAMP(tax_due_at) AS tax_due_unix,
        UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) AS tax_now_unix
        FROM ob_vehicles WHERE id=? AND owner_user_id=? LIMIT 1]], { tonumber(id), owner })
    if not row then return false, 'Veiculo indisponivel.' end
    local overdue, expired = taxStatus(row)
    if expired then
        removeVehiclesWithExpiredTax(owner)
        return false, 'O prazo para pagar o IPVA terminou. Retirada bloqueada por recolhimento.'
    end
    if overdue then return false, 'IPVA vencido. Pague o imposto na garagem antes de retirar o veiculo.' end
    local requestedPlace = options.garageId and garage(options.garageId)
    if options.garageId and (not requestedPlace
        or not vehicleBelongsToGarageScope(options.garageId, requestedPlace, row.garage, row.vehicle_type)) then
        return false, 'O veiculo pertence a outra garagem.'
    end

    if tonumber(row.stored) == 0 then
        local active = activeVehicles[tonumber(row.id)]
        if active and getVehicle(active.netId) then return false, 'Esse veiculo ja esta fora da garagem.' end
        OR.Database.update.await('UPDATE ob_vehicles SET stored=1 WHERE id=? AND owner_user_id=?', { row.id, owner })
    end
    local changed = OR.Database.update.await([[UPDATE ob_vehicles SET stored=0
        WHERE id=? AND owner_user_id=? AND stored=1
        AND (? = 0 OR tax_exempt = 1 OR purchase_price <= 0 OR tax_due_at IS NULL OR tax_due_at > CURRENT_TIMESTAMP())]],
        { row.id, owner, taxSettings().enabled and 1 or 0 })
    if not changed or changed < 1 then return false, 'Esse veiculo acabou de ser retirado.' end

    local vehicle, spawnError, netId = createServerVehicle(source, row.model, rawCoords, options)
    if not vehicle then
        OR.Database.update.await('UPDATE ob_vehicles SET stored=1 WHERE id=? AND owner_user_id=?', { row.id, owner })
        return false, spawnError
    end
    SetVehicleNumberPlateText(vehicle, trim(row.plate))
    row.properties = decodedProperties(row.properties)
    local fuel = math.max(0, math.min(100, tonumber(row.fuel) or 100))
    local state = Entity(vehicle).state
    state:set('ob:fuel', fuel, true)
    state:set('ob:init_vehicle', { plate = trim(row.plate), fuel = fuel }, true)
    restoreTyreState(vehicle, row.properties)
    restoreVisualState(vehicle, row.properties)
    setRegisteredVehicle(vehicle, true)
    Entity(vehicle).state:set('ob:owned_vehicle_id', tonumber(row.id), true)
    if GetResourceState('ob_vehiclekeys') == 'started' then
        local given, message = exports.ob_vehiclekeys:GrantOwnerKey(source, netId, row.id)
        if not given then TriggerClientEvent('ob_notification:client:notify', source, message or 'Use /chave perto do carro para emitir sua chave.', 'error') end
    end
    activeVehicles[tonumber(row.id)] = { source = tonumber(source), netId = netId }
    row.netId = netId
    print(('[ob_garage] retirada id=%s netId=%s bucket=%s'):format(row.id, netId, GetPlayerRoutingBucket(tonumber(source))))
    return true, row
end

exports('SpawnOwnedVehicle', spawnOwnedVehicle)

OR.Callback.register('ob_garage:server:list', listVehicles)

OR.Callback.register('ob_garage:server:take', function(source, id, garageId, spawnIndex)
    local place = garage(garageId)
    if not place then return false, 'Garagem invalida.' end
    local allowed, accessError = hasGarageAccess(source, place)
    if not allowed then return false, accessError end
    local selected, spawnPoint, reserveError = reserveGarageSpawn(garageId, place, spawnIndex)
    if not selected then return false, reserveError end
    local ran, ok, result = pcall(spawnOwnedVehicle, source, id, spawnPoint, {
        garageId = garageId,
        clearRadius = tonumber(place.spawnClearRadius) or 1.75,
        maxDistance = tonumber(type(GarageConfig.Editor) == 'table' and GarageConfig.Editor.MaxSpawnDistance) or 150.0,
    })
    releaseGarageSpawn(garageId, selected)
    if not ran then
        print(('[ob_garage] Falha na retirada: %s'):format(tostring(ok)))
        return false, 'Nao foi possivel retirar o veiculo.'
    end
    return ok, result
end)

-- A oficina confirma o tuning enquanto o veiculo ainda esta fora da garagem.
-- Persistir aqui evita depender de guardar o carro para que cores, neon e
-- outras modificacoes cheguem a ob_vehicles.properties.
OR.Callback.register('ob_garage:server:saveTuning', function(source, netId, rawProperties, rawVisualFlags, stationId)
    local clientId, owner = tonumber(source), userId(source)
    if not clientId or not owner then return false, 'Personagem indisponivel.' end
    if not OR.Security.rateLimit(clientId, 'garage:save_tuning', 6, 30000) then
        return false, 'Aguarde antes de salvar novamente.'
    end

    local vehicle = waitForVehicle(netId, 1800)
    if not vehicle or not playerNearVehicle(clientId, vehicle, 12.0) then
        return false, 'O veiculo nao esta sincronizado perto de voce.'
    end
    local playerPed = GetPlayerPed(clientId)
    if not playerPed or playerPed == 0 or GetPedInVehicleSeat(vehicle, -1) ~= playerPed then
        return false, 'Permaneça como motorista para aplicar o tuning.'
    end

    local plate = trim(GetVehicleNumberPlateText(vehicle))
    local row, queryError = OR.Database.single.await([[SELECT id, properties FROM ob_vehicles
        WHERE plate = ? AND owner_user_id = ? AND stored = 0 LIMIT 1]], { plate, owner })
    if not row then
        return false, queryError or 'Esse veiculo nao esta registrado fora da sua garagem.'
    end

    local properties = decodedProperties(rawProperties)
    -- ToggleVehicleMod(18) pode ser aplicado corretamente, mas o getter do
    -- turbo ainda devolver false naquele frame. A oficina envia a escolha
    -- confirmada separadamente; ela precisa entrar antes do calculo do preco.
    properties.toggles = type(properties.toggles) == 'table' and properties.toggles or {}
    if type(rawVisualFlags) == 'table' then
        if type(rawVisualFlags.turboEnabled) == 'boolean' then
            properties.toggles['18'] = rawVisualFlags.turboEnabled
        end
        if type(rawVisualFlags.xenonEnabled) == 'boolean' then
            properties.toggles['22'] = rawVisualFlags.xenonEnabled
        end
        local selectedExtra = tonumber(rawVisualFlags.selectedExtra)
        if selectedExtra then
            selectedExtra = math.floor(selectedExtra)
            if selectedExtra < -1 or selectedExtra > 20 then
                return false, 'O extra selecionado e invalido.'
            end
            properties.extras = type(properties.extras) == 'table' and properties.extras or {}
            local selectedExists = selectedExtra == -1
            for key in pairs(properties.extras) do
                local extra = tonumber(key)
                if extra and extra >= 0 and extra <= 20 then
                    properties.extras[tostring(extra)] = extra == selectedExtra
                    if extra == selectedExtra then selectedExists = true end
                end
            end
            if not selectedExists then return false, 'Esse veiculo nao possui o extra selecionado.' end
        end
    end
    if GetResourceState('ob_mecanico') ~= 'started' then
        return false, 'A mecanica esta indisponivel para calcular o servico.'
    end
    local charged, receiptOrError, chargedAmount = exports.ob_mecanico:ChargeTuning(
        clientId, stationId, vehicle, row.properties, properties)
    if charged ~= true then return false, receiptOrError or 'Nao foi possivel cobrar o servico.' end
    local receipt = receiptOrError
    local entityState = Entity(vehicle).state
    properties.hsw = nil
    local visualFlags = visualFlagsFromProperties(properties)
    visualFlags = mergeVisualFlags(visualFlags, entityState['ob:visual_flags'])
    visualFlags = mergeVisualFlags(visualFlags, rawVisualFlags)
    entityState:set('ob:visual_flags', visualFlags, true)
    applyVisualFlags(properties, visualFlags)
    properties = authoritativeTyreProperties(vehicle, properties)
    local encoded = json.encode(properties)
    if type(encoded) ~= 'string' or #encoded > 150000 then
        if receipt then exports.ob_mecanico:FinishTuningPayment(clientId, receipt, true) end
        return false, 'As propriedades do veiculo sao invalidas.'
    end
    local changed, databaseError = OR.Database.update.await([[UPDATE ob_vehicles
        SET properties = ? WHERE id = ? AND owner_user_id = ? AND stored = 0]], {
        encoded, row.id, owner
    })
    if changed == nil then
        if receipt then exports.ob_mecanico:FinishTuningPayment(clientId, receipt, true) end
        print(('[ob_garage] Falha ao salvar tuning de %s (registro %s): %s'):format(
            plate, tostring(row.id), tostring(databaseError or 'erro desconhecido')))
        return false, 'O banco recusou o salvamento do tuning.'
    end
    if receipt then exports.ob_mecanico:FinishTuningPayment(clientId, receipt, false) end
    return true, tonumber(chargedAmount) or 0
end)

RegisterNetEvent('ob_garage:server:return', function(id)
    local source, owner = source, userId(source)
    if not owner then return end
    if not OR.Security.rateLimit(source, 'garage:return', 3, 10000) then return end
    local active = activeVehicles[tonumber(id)]
    local vehicle = active and active.source == tonumber(source) and getVehicle(active.netId) or nil
    if vehicle then DeleteEntity(vehicle) end
    OR.Database.update.await('UPDATE ob_vehicles SET stored = 1 WHERE id = ? AND owner_user_id = ?', { tonumber(id), owner })
    activeVehicles[tonumber(id)] = nil
end)

RegisterNetEvent('ob_garage:server:store', function(garageId, netId, stats, properties)
    local source, owner, place = source, userId(source), garage(garageId)
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not owner or not place or not vehicle or vehicle == 0 then return end
    if not OR.Security.rateLimit(source, 'garage:store', 3, 10000) then return end
    local allowed, accessError = hasGarageAccess(source, place)
    if not allowed then return TriggerClientEvent('ob_notification:client:notify', source, accessError, 'error') end
    local driver = GetPedInVehicleSeat(vehicle, -1)
    if driver ~= 0 and driver ~= GetPlayerPed(tonumber(source)) then
        return TriggerClientEvent('ob_notification:client:notify', source, 'O veiculo esta sendo dirigido por outra pessoa.', 'error')
    end
    if not playerNearVehicle(source, vehicle, place.storeDistance) then return end
    local storePoint = place.storeCoords or place.coords
    if not storePoint or #(GetEntityCoords(vehicle) - storePoint) > (tonumber(place.storeDistance) or 16.0) then
        return TriggerClientEvent('ob_notification:client:notify', source, 'Leve o veiculo ate o ponto de armazenamento.', 'error')
    end
    local entityState = Entity(vehicle).state
    local freeGroup = tostring(entityState['ob:free_garage_group'] or '')
    local currentPlate = trim(GetVehicleNumberPlateText(vehicle)):upper()
    local legacyFree = freeGroup == '' and currentPlate:match('^FREE') ~= nil
        and tonumber(entityState['ob:temporary_key_user']) == tonumber(owner)
        and entityState['ob:job_vehicle'] == true
    if legacyFree and garageVehicleType(place) == 'free' then freeGroup = garageGroupKey(garageId, place) end
    if freeGroup ~= '' then
        if tonumber(entityState['ob:free_vehicle_owner']) ~= tonumber(owner) then
            return TriggerClientEvent('ob_notification:client:notify', source, 'Esse veiculo gratuito foi retirado por outra pessoa.', 'error')
        end
        if garageVehicleType(place) ~= 'free' or garageGroupKey(garageId, place) ~= freeGroup then
            return TriggerClientEvent('ob_notification:client:notify', source, 'Devolva o veiculo em uma garagem gratuita do mesmo grupo.', 'error')
        end
        local removed = exports.ob_core:DeleteTemporaryVehicle(source, netId)
        if not removed then
            return TriggerClientEvent('ob_notification:client:notify', source, 'Nao foi possivel devolver o veiculo gratuito.', 'error')
        end
        return TriggerClientEvent('ob_garage:client:stored', source, netId, true)
    end
    local plate = trim(GetVehicleNumberPlateText(vehicle))
    local row = OR.Database.single.await('SELECT id, garage, vehicle_type FROM ob_vehicles WHERE plate = ? AND owner_user_id = ? LIMIT 1', { plate, owner })
    if not row then return TriggerClientEvent('ob_notification:client:notify', source, 'Esse veiculo nao pertence a voce.', 'error') end
    if not vehicleBelongsToGarageScope(garageId, place, row.garage, row.vehicle_type) then
        return TriggerClientEvent('ob_notification:client:notify', source, 'Esse veiculo pertence a outra garagem ou grupo.', 'error')
    end
    stats = type(stats) == 'table' and stats or {}
    properties = authoritativeTyreProperties(vehicle, properties)
    local serverBody = reliableVehicleHealth(GetVehicleBodyHealth(vehicle), stats.body)
    local serverEngine = reliableVehicleHealth(GetVehicleEngineHealth(vehicle), stats.engine)
    local changed, databaseError = OR.Database.update.await([[UPDATE ob_vehicles SET stored = 1, fuel = ?, body = ?, engine = ?, properties = ? WHERE id = ?]], {
        math.max(0, math.min(100, tonumber(Entity(vehicle).state['ob:fuel']) or tonumber(stats.fuel) or 100)),
        serverBody, serverEngine, json.encode(properties), row.id
    })
    if not changed or tonumber(changed) < 1 then
        print(('[ob_garage] Falha ao guardar o veiculo %s (registro %s): %s'):format(
            plate, tostring(row.id), tostring(databaseError or 'nenhuma linha atualizada')))
        TriggerClientEvent('ob_notification:client:notify', source,
            'Nao foi possivel salvar o veiculo. Ele permaneceu na vaga.', 'error')
        return
    end
    local keysStored, keyError = exports.ob_vehiclekeys:PrepareVehicleRemoval(source, netId, true)
    if not keysStored then
        OR.Database.update.await('UPDATE ob_vehicles SET stored=0 WHERE id=?', { row.id })
        TriggerClientEvent('ob_notification:client:notify', source, keyError or 'Nao foi possivel guardar a chave.', 'error')
        return
    end
    activeVehicles[row.id] = nil
    TriggerClientEvent('ob_garage:client:stored', source, netId)
end)

-- O /dv administrativo tambem pode atingir um veiculo proprio que esta fora
-- da garagem. Nesse caso ele deve ser guardado antes de a entidade sumir; do
-- contrario o registro ficava como "fora" para sempre e nao podia ser puxado.
OR.Callback.register('ob_garage:server:adminStoreBeforeDelete', function(source, netId, stats, properties)
    local canDelete = false
    if GetResourceState('ob_admin') == 'started' then
        local ok, allowed = pcall(function()
            return exports.ob_admin:HasPermission(source, 'vehicle.delete')
        end)
        canDelete = ok and allowed == true
    end
    if not canDelete then return false end

    local vehicle = waitForVehicle(netId, 1200)
    if not vehicle then return false end

    local plate = trim(GetVehicleNumberPlateText(vehicle))
    local row = OR.Database.single.await('SELECT id FROM ob_vehicles WHERE plate = ? AND stored = 0 LIMIT 1', { plate })
    if not row then return false end

    stats = type(stats) == 'table' and stats or {}
    properties = authoritativeTyreProperties(vehicle, properties)
    local serverBody = reliableVehicleHealth(GetVehicleBodyHealth(vehicle), stats.body)
    local serverEngine = reliableVehicleHealth(GetVehicleEngineHealth(vehicle), stats.engine)
    local changed, databaseError = OR.Database.update.await([[UPDATE ob_vehicles
        SET stored = 1, fuel = ?, body = ?, engine = ?, properties = ?
        WHERE id = ?]], {
        math.max(0, math.min(100, tonumber(stats.fuel) or 100)),
        serverBody,
        serverEngine,
        json.encode(properties), row.id
    })
    if not changed or tonumber(changed) < 1 then
        print(('[ob_garage] Falha ao salvar o veiculo %s antes do /dv (registro %s): %s'):format(
            plate, tostring(row.id), tostring(databaseError or 'nenhuma linha atualizada')))
        return false
    end
    local keysStored = exports.ob_vehiclekeys:PrepareVehicleRemoval(source, netId, true)
    if not keysStored then
        OR.Database.update.await('UPDATE ob_vehicles SET stored=0 WHERE id=?', { row.id })
        return false
    end
    activeVehicles[row.id] = nil
    return true
end)


OR.Callback.register('ob_garage:server:track', function(source, vehicleId)
    local owner = userId(source)
    local row = owner and OR.Database.single.await('SELECT id,stored FROM ob_vehicles WHERE id=? AND owner_user_id=? LIMIT 1', { tonumber(vehicleId), owner })
    if not row then return false, 'Veiculo nao encontrado.' end
    if tonumber(row.stored) == 1 then return false, 'Esse veiculo esta guardado na garagem.' end
    local active = activeVehicles[row.id]
    local vehicle = active and getVehicle(active.netId)
    if not vehicle then return false, 'O veiculo nao esta sincronizado para rastreamento.' end
    local coords = GetEntityCoords(vehicle)
    return true, { x = coords.x, y = coords.y, z = coords.z }
end)


local function registerVehicle(owner, data)
    owner = tonumber(owner)
    if not schemaReady or not owner or type(data) ~= 'table' then return nil, 'Proprietario ou garagem indisponivel.' end
    local plate, model = trim(data.plate), trim(data.model):lower()
    if plate == '' or model == '' then return nil, 'Placa e modelo sao obrigatorios.' end
    local label = trim(data.label); if label == '' then label = model:upper() end
    local settings = taxSettings()
    local vehicleType = trim(data.vehicleType):lower()
    if vehicleType ~= 'service' and vehicleType ~= 'free' then vehicleType = 'personal' end
    local price = math.max(0, math.floor(tonumber(data.purchasePrice) or 0))
    local defaultRate = vehicleType == 'service' and settings.serviceRate or settings.personalRate
    local taxRate = math.max(0.0, math.min(100.0, tonumber(data.taxRatePercent) or defaultRate))
    local taxExempt = data.taxExempt == true or price <= 0 or settings.enabled ~= true
    local dueExpression = taxExempt and 'NULL' or ('DATE_ADD(CURRENT_TIMESTAMP(), INTERVAL %d DAY)'):format(settings.intervalDays)
    local id, err = OR.Database.insert.await(([[INSERT INTO ob_vehicles
        (owner_user_id, plate, model, label, garage, fuel, body, engine, properties,
            purchase_price, vehicle_type, tax_rate, tax_exempt, tax_due_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, %s)]]):format(dueExpression), {
        owner, plate, model, label, data.garage or 'central', tonumber(data.fuel) or 100,
        1000, 1000, json.encode(data.properties or {}), price, vehicleType, taxRate, taxExempt and 1 or 0
    })
    return id, err
end

exports('RegisterVehicleForUser', registerVehicle)
exports('RegisterVehicle', function(source, data) return registerVehicle(userId(source), data) end)

local function findCatalogVehicle(place, requestedModel)
    requestedModel = trim(requestedModel):lower()
    if requestedModel == '' then return nil end
    for _, entry in ipairs(type(place and place.vehicles) == 'table' and place.vehicles or {}) do
        if trim(entry.model):lower() == requestedModel then return entry end
    end
end

local function uniqueOwnedPlate(prefix)
    prefix = trim(prefix):upper():gsub('[^A-Z0-9]', ''):sub(1, 2)
    if prefix == '' then prefix = 'OB' end
    for _ = 1, 60 do
        local plate = ('%s%02d%04d'):format(prefix, math.random(10, 99), math.random(0, 9999)):sub(1, 12)
        if not OR.Database.scalar.await('SELECT id FROM ob_vehicles WHERE plate = ? LIMIT 1', { plate }) then return plate end
    end
end

findFreeVehicleInUse = function(owner, group, model)
    owner, group, model = tonumber(owner), tostring(group or ''), tostring(model or ''):lower()
    for _, vehicle in ipairs(GetAllVehicles()) do
        if DoesEntityExist(vehicle) then
            local state = Entity(vehicle).state
            local savedGroup = tostring(state['ob:free_garage_group'] or '')
            local savedModel = tostring(state['ob:free_vehicle_model'] or ''):lower()
            local legacyFree = savedGroup == '' and trim(GetVehicleNumberPlateText(vehicle)):upper():match('^FREE') ~= nil
                and state['ob:job_vehicle'] == true
            local sameOwner = tonumber(state['ob:free_vehicle_owner']) == owner
                or (legacyFree and tonumber(state['ob:temporary_key_user']) == owner)
            local sameGroup = savedGroup == group or legacyFree
            local sameModel = savedModel == model or (legacyFree and GetEntityModel(vehicle) == joaat(model))
            if sameOwner and sameGroup and sameModel then
                return vehicle
            end
        end
    end
end

OR.Callback.register('ob_garage:server:acquire', function(source, garageId, requestedModel, spawnIndex)
    local owner, place = userId(source), garage(garageId)
    if not schemaReady or not owner or not place then return false, 'Garagem indisponivel.' end
    if not OR.Security.rateLimit(source, 'garage:acquire', 3, 15000) then return false, 'Aguarde antes de tentar novamente.' end
    local allowed, accessError = hasGarageAccess(source, place)
    if not allowed then return false, accessError end
    if not playerNearGarage(source, place, 7.0) then return false, 'Aproxime-se do ponto da garagem.' end

    local entry = findCatalogVehicle(place, requestedModel)
    if not entry then return false, 'Veiculo nao pertence ao catalogo desta garagem.' end
    local model = trim(entry.model):lower()
    if not model:match('^[a-z0-9_]+$') or #model > 64 then return false, 'Modelo de veiculo invalido.' end
    local vehicleType = place.vehicleType == 'service' and 'service' or (place.vehicleType == 'free' and 'free' or 'personal')
    if vehicleType == 'free' then
        local sharedGroup = garageGroupKey(garageId, place)
        if findFreeVehicleInUse(owner, sharedGroup, model) then
            return false, 'Voce ja retirou esse veiculo em uma garagem deste grupo.'
        end
        local selected, spawnPoint, reserveError = reserveGarageSpawn(garageId, place, spawnIndex)
        if not selected then return false, reserveError end
        local ran, spawned, vehicleData = pcall(function()
            return exports.ob_core:SpawnTemporaryVehicle(source, model, spawnPoint, {
                platePrefix = 'FREE', fuel = 100.0,
                clearRadius = tonumber(place.spawnClearRadius) or 1.75,
                maxDistance = tonumber(type(GarageConfig.Editor) == 'table' and GarageConfig.Editor.MaxSpawnDistance) or 150.0,
            })
        end)
        releaseGarageSpawn(garageId, selected)
        if not ran then
            print(('[ob_garage] Falha na retirada gratuita: %s'):format(tostring(spawned)))
            return false, 'Nao foi possivel retirar o veiculo gratuito.'
        end
        if not spawned then return false, vehicleData or 'Nao foi possivel retirar o veiculo gratuito.' end
        vehicleData.temporary = true
        vehicleData.model = model
        vehicleData.label = trim(entry.label) ~= '' and trim(entry.label) or model:upper()
        vehicleData.fuel = 100.0
        vehicleData.body = 1000.0
        vehicleData.engine = 1000.0
        vehicleData.properties = { model = model, fuel = 100.0, engine = 1000.0, body = 1000.0 }
        local entity = NetworkGetEntityFromNetworkId(tonumber(vehicleData.netId) or 0)
        if entity and entity ~= 0 and DoesEntityExist(entity) then
            local state = Entity(entity).state
            state:set('ob:free_vehicle_owner', owner, true)
            state:set('ob:free_garage_group', sharedGroup, true)
            state:set('ob:free_vehicle_model', model, true)
        end
        return true, vehicleData
    end
    local ownedRows = OR.Database.query.await([[SELECT id, garage, vehicle_type FROM ob_vehicles
        WHERE owner_user_id = ? AND LOWER(model) = ? AND vehicle_type <> 'free']], { owner, model }) or {}
    local alreadyOwned
    for _, ownedRow in ipairs(ownedRows) do
        if vehicleBelongsToGarageScope(garageId, place, ownedRow.garage, ownedRow.vehicle_type) then
            alreadyOwned = ownedRow.id
            break
        end
    end
    if alreadyOwned then return false, 'Voce ja adquiriu este veiculo nesta garagem ou grupo.' end

    local price = math.max(0, math.floor(tonumber(entry.price) or 0))
    local departmentPrice = vehicleType == 'service'
        and math.max(0, math.floor(tonumber(entry.departmentPrice) or price)) or price
    local paymentAccount = vehicleType == 'service' and place.economyAccount or nil
    local paid, methodOrError = payPlayer(source, departmentPrice,
        ('Aquisicao de %s'):format(trim(entry.label) ~= '' and trim(entry.label) or model),
        vehicleType == 'service' and 'vehicle_rental' or 'garage_vehicle_purchase',
        { garageId = garageId, model = model, vehicleType = vehicleType }, paymentAccount, price)
    if not paid then return false, methodOrError end
    local chargedPrice = type(methodOrError) == 'table' and tonumber(methodOrError.amount) or price
    chargedPrice = math.max(0, math.floor(chargedPrice or price))
    local plate = uniqueOwnedPlate(vehicleType == 'service' and 'SV' or (vehicleType == 'free' and 'FR' or 'OB'))
    if not plate then
        refundPlayer(source, price, methodOrError, 'Estorno de veiculo')
        return false, 'Nao foi possivel gerar uma placa unica.'
    end
    local id, registerError = registerVehicle(owner, {
        plate = plate, model = model,
        label = trim(entry.label) ~= '' and trim(entry.label) or model:upper(),
        garage = garageId, fuel = 100.0, purchasePrice = chargedPrice, vehicleType = vehicleType,
        taxRatePercent = tonumber(entry.taxRatePercent) or tonumber(place.taxRatePercent),
        taxExempt = entry.taxExempt == true or place.taxExempt == true,
        properties = { model = model, fuel = 100.0, engine = 1000.0, body = 1000.0 },
    })
    if not id then
        refundPlayer(source, price, methodOrError, 'Estorno de veiculo')
        return false, registerError or 'Nao foi possivel registrar o veiculo.'
    end
    return true, ('%s adquirido e guardado com a placa %s.'):format(trim(entry.label) ~= '' and trim(entry.label) or model:upper(), plate)
end)

RegisterNetEvent('ob_garage:server:releaseTemporary', function(netId)
    exports.ob_core:DeleteTemporaryVehicle(source, tonumber(netId))
end)

OR.Callback.register('ob_garage:server:payTax', function(source, vehicleId, garageId)
    local owner, place = userId(source), garage(garageId)
    if not schemaReady or not owner or not place then return false, 'Garagem indisponivel.' end
    if not OR.Security.rateLimit(source, 'garage:pay_tax', 3, 15000) then return false, 'Aguarde antes de tentar novamente.' end
    local allowed, accessError = hasGarageAccess(source, place)
    if not allowed then return false, accessError end
    if not playerNearGarage(source, place, 7.0) then return false, 'Aproxime-se do ponto da garagem.' end
    local row = OR.Database.single.await([[SELECT id, plate, garage, purchase_price, vehicle_type, tax_rate, tax_exempt,
            UNIX_TIMESTAMP(tax_due_at) AS tax_due_unix, UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) AS tax_now_unix
        FROM ob_vehicles WHERE id = ? AND owner_user_id = ? LIMIT 1]], { tonumber(vehicleId), owner })
    if not row or not vehicleBelongsToGarageScope(garageId, place, row.garage, row.vehicle_type) then
        return false, 'Veiculo nao encontrado nesta garagem.'
    end
    local amount, dueAt = vehicleTaxAmount(row), tonumber(row.tax_due_unix)
    if amount <= 0 or not dueAt then return false, 'Este veiculo nao possui IPVA.' end
    local overdue, expired, _, now = taxStatus(row)
    if not overdue then return false, 'O IPVA deste veiculo ainda nao venceu.' end
    if expired then
        removeVehiclesWithExpiredTax(owner)
        return false, 'O prazo para pagar o IPVA terminou. Veiculo sujeito a recolhimento.'
    end

    local paymentAccount = row.vehicle_type == 'service' and place.economyAccount or nil
    local paid, methodOrError = payPlayer(source, amount, ('IPVA da placa %s'):format(row.plate),
        'vehicle_tax', { vehicleId = tonumber(row.id), plate = trim(row.plate), vehicleType = row.vehicle_type },
        paymentAccount, amount)
    if not paid then return false, methodOrError end
    local settings = taxSettings()
    local nextDueUnix = math.max(now, dueAt) + settings.intervalDays * 86400
    local changed, updateError = OR.Database.update.await(([[UPDATE ob_vehicles SET tax_due_at = FROM_UNIXTIME(?)
        WHERE id = ? AND owner_user_id = ? AND UNIX_TIMESTAMP(tax_due_at) = ?
        AND tax_due_at > DATE_SUB(CURRENT_TIMESTAMP(), INTERVAL %d DAY)]]):format(settings.deleteAfterDays),
        { nextDueUnix, row.id, owner, dueAt })
    if not changed or tonumber(changed) < 1 then
        refundPlayer(source, amount, methodOrError, 'Estorno de IPVA')
        return false, updateError or 'Nao foi possivel registrar o pagamento.'
    end
    OR.Database.insert.await([[INSERT INTO ob_vehicle_tax_payments
        (vehicle_id, owner_user_id, plate, amount, previous_due_at, next_due_at)
        VALUES (?, ?, ?, ?, FROM_UNIXTIME(?), FROM_UNIXTIME(?))]], { row.id, owner, row.plate, amount, dueAt, nextDueUnix })
    return true, ('IPVA de %s pago. Proximo vencimento em %s.'):format(OR.FormatMoney(amount), os.date('%d/%m/%Y', nextDueUnix))
end)

removeVehiclesWithExpiredTax = function(owner)
    local settings = taxSettings()
    if not schemaReady or not settings.enabled then return 0 end
    local cutoff = ('DATE_SUB(CURRENT_TIMESTAMP(), INTERVAL %d DAY)'):format(settings.deleteAfterDays)
    local rows, queryError = OR.Database.query.await(([[SELECT * FROM ob_vehicles
        WHERE tax_exempt = 0 AND purchase_price > 0 AND tax_due_at IS NOT NULL AND tax_due_at <= %s
        AND (? = 0 OR owner_user_id = ?)]]):format(cutoff), { tonumber(owner) or 0, tonumber(owner) or 0 })
    if not rows then
        print('[ob_garage] Falha ao consultar IPVA vencido: ' .. tostring(queryError))
        return 0
    end
    local removed = 0
    for _, row in ipairs(rows) do
        local id = tonumber(row.id)
        -- Arquivar e remover na mesma transacao. Pagamento concorrente impede
        -- o DELETE e desfaz tambem o arquivo; falha SQL nunca perde o cadastro.
        local result, removalError = OR.Database.transaction.await({
            { kind = 'insert', statement = [[INSERT INTO ob_vehicle_tax_repossessions
                (vehicle_id, owner_user_id, plate, snapshot) VALUES (?, ?, ?, ?)]],
                parameters = { id, row.owner_user_id, row.plate, json.encode(row) }, expectAffectedMin = 1 },
            { kind = 'update', statement = ([[DELETE FROM ob_vehicles WHERE id = ? AND owner_user_id = ?
                AND tax_exempt = 0 AND purchase_price > 0 AND tax_due_at IS NOT NULL AND tax_due_at <= %s]]):format(cutoff),
                parameters = { id, row.owner_user_id }, expectAffectedMin = 1 },
        })
        if result then
            local active = activeVehicles[id]
            local entity = active and getVehicle(active.netId) or nil
            if entity then DeleteEntity(entity) end
            activeVehicles[id] = nil
            removed = removed + 1
            print(('[ob_garage] Veiculo %s do user_id %s removido apos %d dias de IPVA atrasado.'):format(
                tostring(row.plate), tostring(row.owner_user_id), settings.deleteAfterDays))
        elseif removalError then
            print(('[ob_garage] Remocao por IPVA nao aplicada id=%s: %s'):format(id, tostring(removalError)))
        end
    end
    return removed
end

CreateThread(function()
    while not schemaReady do Wait(500) end
    removeVehiclesWithExpiredTax()
    while true do
        Wait(taxSettings().cleanupMinutes * 60000)
        removeVehiclesWithExpiredTax()
    end
end)

RegisterCommand('givevehicle', function(source, args)
    if source ~= 0 and not exports.ob_core:IsAdmin(source) then return end
    local targetUserId, model = math.floor(tonumber(args[1]) or 0), trim(args[2])
    local targetSource = targetUserId > 0 and exports.ob_core:GetSourceByUserId(targetUserId) or nil
    if not targetSource or model == '' or not GetPlayerName(targetSource) then
        if source == 0 then
            print('[ob_garage] Uso: givevehicle [ID fixo] [modelo]. O personagem precisa estar na cidade.')
        else
            TriggerClientEvent('ob_notification:client:notify', source, 'Uso: /givevehicle [ID fixo] [modelo]. O personagem precisa estar na cidade.', 'error')
        end
        return
    end
    local plate = ('OB%04d'):format(math.random(0, 9999))
    local id, err = registerVehicle(targetUserId, { model = model, label = model:upper(), plate = plate })
    if id then
        TriggerClientEvent('ob_notification:client:notify', targetSource, ('Veiculo %s adicionado a garagem.'):format(model), 'success')
        if source ~= 0 and source ~= targetSource then
            TriggerClientEvent('ob_notification:client:notify', source, ('Veiculo entregue ao ID fixo %s.'):format(targetUserId), 'success')
        end
    elseif source == 0 then
        print(('[ob_garage] Falha ao entregar veiculo ao ID fixo %s: %s'):format(targetUserId, err or 'erro desconhecido'))
    else
        TriggerClientEvent('ob_notification:client:notify', source, err or 'Nao foi possivel entregar o veiculo.', 'error')
    end
end, false)
