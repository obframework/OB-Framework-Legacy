local schemaReady = false
local fuelAuthorizations = {}
local vehicleSaveStates = {}

CreateThread(function()
    if not OR.Database.waitForReady(30000) then
        print('[ob_fuel] Banco de dados indisponivel; manutencao sera tentada novamente no proximo restart.')
        return
    end
    local result, errorMessage = OR.Database.query.await([[CREATE TABLE IF NOT EXISTS ob_vehicle_maintenance (
        plate varchar(16) NOT NULL PRIMARY KEY,
        mileage decimal(12,2) NOT NULL DEFAULT 0,
        fuel decimal(6,2) NOT NULL DEFAULT 100,
        oil_km decimal(12,2) NOT NULL DEFAULT 0,
        brake_km decimal(12,2) NOT NULL DEFAULT 0,
        spark_km decimal(12,2) NOT NULL DEFAULT 0,
        misfuel_liters decimal(8,2) NOT NULL DEFAULT 0,
        misfuel_type varchar(16) NULL,
        updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    if not result then
        print(('[ob_fuel] Falha ao criar tabela de manutencao: %s'):format(tostring(errorMessage)))
        return
    end
    -- Instalacoes que chegaram a criar a primeira versao da tabela recebem a
    -- coluna de combustivel sem precisar importar outro SQL manualmente.
    local fuelColumn = OR.Database.single.await("SHOW COLUMNS FROM ob_vehicle_maintenance LIKE 'fuel'")
    if not fuelColumn then
        local altered, alterError = OR.Database.query.await('ALTER TABLE ob_vehicle_maintenance ADD COLUMN fuel decimal(6,2) NOT NULL DEFAULT 100 AFTER mileage')
        if not altered then
            print(('[ob_fuel] Falha ao atualizar tabela de manutencao: %s'):format(tostring(alterError)))
            return
        end
    end
    local misfuelColumn = OR.Database.single.await("SHOW COLUMNS FROM ob_vehicle_maintenance LIKE 'misfuel_liters'")
    if not misfuelColumn then
        local altered, alterError = OR.Database.query.await('ALTER TABLE ob_vehicle_maintenance ADD COLUMN misfuel_liters decimal(8,2) NOT NULL DEFAULT 0 AFTER spark_km')
        if not altered then
            print(('[ob_fuel] Falha ao adicionar estado de combustivel incorreto: %s'):format(tostring(alterError)))
            return
        end
    end
    local misfuelTypeColumn = OR.Database.single.await("SHOW COLUMNS FROM ob_vehicle_maintenance LIKE 'misfuel_type'")
    if not misfuelTypeColumn then
        local altered, alterError = OR.Database.query.await('ALTER TABLE ob_vehicle_maintenance ADD COLUMN misfuel_type varchar(16) NULL AFTER misfuel_liters')
        if not altered then
            print(('[ob_fuel] Falha ao adicionar tipo de combustivel incorreto: %s'):format(tostring(alterError)))
            return
        end
    end
    schemaReady = true
end)

local function plateOf(vehicle)
    return DoesEntityExist(vehicle) and GetVehicleNumberPlateText(vehicle):gsub('^%s*(.-)%s*$', '%1') or nil
end

local function fuelTypeFor(state)
    -- A classe do veiculo e uma native de cliente; o cliente ja a calcula ao
    -- montar o estado. Aqui aceitamos apenas os dois tipos configurados.
    local fuelType = state.fuelType
    return OBFuelConfig.Types[fuelType] and fuelType or 'gasoline'
end

local function numberInRange(value, default, minimum, maximum)
    value = tonumber(value)
    if not value then return default end
    return math.max(minimum, math.min(maximum, value))
end

local function normalizeState(vehicle, state)
    local misfuelType = OBFuelConfig.Types[state.misfuelType or state.misfuel_type] and (state.misfuelType or state.misfuel_type) or nil
    local misfuelLiters = numberInRange(state.misfuelLiters or state.misfuel_liters, 0, 0, 200)
    if misfuelLiters <= 0 then misfuelType = nil end
    return {
        mileage = numberInRange(state.mileage, 0, 0, 99999999),
        fuel = numberInRange(state.fuel, 100, 0, 100),
        oilKm = numberInRange(state.oilKm or state.oil_km, 0, 0, 99999999),
        brakeKm = numberInRange(state.brakeKm or state.brake_km, 0, 0, 99999999),
        sparkKm = numberInRange(state.sparkKm or state.spark_km, 0, 0, 99999999),
        misfuelLiters = misfuelLiters,
        misfuelType = misfuelType,
        fuelType = fuelTypeFor(state),
        transient = state.transient == true,
    }
end

local function publishState(vehicle, netId, state)
    local entity = Entity(vehicle)
    entity.state:set('ob:fuel', state.fuel, true)
    entity.state:set('ob:mileage', state.mileage, true)
    entity.state:set('ob:fuel_type', state.fuelType, true)
    entity.state:set('ob:misfuel', state.misfuelLiters > 0 and { type = state.misfuelType, liters = state.misfuelLiters } or nil, true)
    TriggerClientEvent('ob_fuel:client:syncVehicleState', -1, netId, state)
end

-- Somente veiculos registrados pela garagem/concessionaria recebem historico
-- permanente. NPCs e carros administrativos ainda consomem combustivel e
-- contam quilometragem localmente para a HUD, mas nao sujam a tabela SQL.
local function canPersistMaintenance(vehicle)
    if not schemaReady or not vehicle or vehicle == 0 then return false end
    if Entity(vehicle).state['ob:temporary_vehicle'] == true then return false end
    local plate = plateOf(vehicle)
    if not plate or plate == '' then return false end
    return OR.Database.scalar.await('SELECT id FROM ob_vehicles WHERE plate = ? LIMIT 1', { plate }) ~= nil
end

OR.Callback.register('getVehicleState', function(source, netId)
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not vehicle or vehicle == 0 then return nil, 'Veiculo invalido.' end
    if not schemaReady then return { mileage = 0, fuel = 100, oil_km = 0, brake_km = 0, spark_km = 0, misfuel_liters = 0, transient = true } end
    if not canPersistMaintenance(vehicle) then return { mileage = 0, fuel = 100, oil_km = 0, brake_km = 0, spark_km = 0, misfuel_liters = 0, transient = true } end
    local plate = plateOf(vehicle)
    local row = OR.Database.single.await('SELECT mileage, fuel, oil_km, brake_km, spark_km, misfuel_liters, misfuel_type FROM ob_vehicle_maintenance WHERE plate = ? LIMIT 1', { plate })
    return row or { mileage = 0, fuel = 100, oil_km = 0, brake_km = 0, spark_km = 0, misfuel_liters = 0 }
end)

OR.Callback.register('setFuelByAdmin', function(source, netId, requestedFuel)
    local allowed = false
    if GetResourceState('ob_admin') == 'started' then
        local ok, result = pcall(function()
            return exports.ob_admin:HasPermission(source, 'vehicle.fix')
        end)
        allowed = ok and result == true
    end
    if not allowed then return false, 'Sem permissao para restaurar o combustivel.' end
    if not OR.Security.rateLimit(source, 'fuel:admin_set', 3, 10000) then
        return false, 'Aguarde antes de restaurar outro veiculo.'
    end

    netId = tonumber(netId) or 0
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    local playerPed = GetPlayerPed(source)
    if not vehicle or vehicle == 0 or not playerPed or playerPed <= 0 then return false, 'Veiculo invalido.' end
    if GetPedInVehicleSeat(vehicle, -1) ~= playerPed and #(GetEntityCoords(playerPed) - GetEntityCoords(vehicle)) > 6.0 then
        return false, 'Aproxime-se do veiculo.'
    end

    local plate = plateOf(vehicle)
    local row = schemaReady and OR.Database.single.await([[SELECT mileage,fuel,oil_km,brake_km,spark_km,misfuel_liters,misfuel_type
        FROM ob_vehicle_maintenance WHERE plate = ? LIMIT 1]], { plate }) or {}
    local entityState = Entity(vehicle).state
    local state = normalizeState(vehicle, {
        mileage = row and row.mileage or entityState['ob:mileage'],
        fuel = numberInRange(requestedFuel, 100, 0, 100),
        oilKm = row and row.oil_km,
        brakeKm = row and row.brake_km,
        sparkKm = row and row.spark_km,
        misfuelLiters = 0,
        fuelType = entityState['ob:fuel_type'] or 'gasoline',
        transient = not canPersistMaintenance(vehicle),
    })
    publishState(vehicle, netId, state)

    if not state.transient and plate and plate ~= '' then
        local saved, saveError = OR.Database.transaction.await({
            { kind = 'update', statement = [[INSERT INTO ob_vehicle_maintenance
                (plate,mileage,fuel,oil_km,brake_km,spark_km,misfuel_liters,misfuel_type)
                VALUES (?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE fuel=VALUES(fuel), misfuel_liters=0, misfuel_type=NULL]],
                parameters = { plate, state.mileage, state.fuel, state.oilKm, state.brakeKm, state.sparkKm, 0, '' } },
            { kind = 'update', statement = 'UPDATE ob_vehicles SET fuel = ? WHERE plate = ?',
                parameters = { state.fuel, plate }, expectAffectedMin = 1 },
        })
        if not saved then return false, saveError or 'O combustivel nao foi salvo.' end
    end
    return true
end)

OR.Callback.register('servicePart', function(source, netId, part)
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    local playerPed = GetPlayerPed(source)
    local columns = { oil = 'oil_km', brakes = 'brake_km', spark = 'spark_km' }
    local column = columns[part]
    if not vehicle or vehicle == 0 or not playerPed or playerPed <= 0 or not column then return false, 'Veiculo ou peca invalida.' end
    local allowed, retry = OR.Security.rateLimit(source, 'fuel:service_part', 2, 10000)
    if not allowed then return false, ('Aguarde %d segundos.'):format(math.max(1, math.ceil((retry or 1000) / 1000))) end
    if #(GetEntityCoords(playerPed) - GetEntityCoords(vehicle)) > 6.0 then return false, 'Aproxime-se do veiculo.' end
    if not canPersistMaintenance(vehicle) then return false, 'Este veiculo nao possui historico de manutencao.' end
    local requiredItems = { oil = 'vehicle_oil', brakes = 'brake_pads', spark = 'spark_plugs' }
    local requiredItem = requiredItems[part]
    local removed, removeError = exports.ob_inventory:RemoveItem(source, requiredItem, 1)
    if not removed then return false, removeError or 'Voce nao possui a peca de manutencao.' end
    local plate = plateOf(vehicle)
    local row = OR.Database.single.await('SELECT mileage, fuel, oil_km, brake_km, spark_km FROM ob_vehicle_maintenance WHERE plate = ? LIMIT 1', { plate }) or {}
    local mileage = tonumber(row.mileage) or 0
    local saved = OR.Database.update.await(('INSERT INTO ob_vehicle_maintenance (plate, mileage, fuel, oil_km, brake_km, spark_km) VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE %s=VALUES(%s)'):format(column, column), {
        plate, mileage, tonumber(row.fuel) or 100, part == 'oil' and mileage or (tonumber(row.oil_km) or 0),
        part == 'brakes' and mileage or (tonumber(row.brake_km) or 0), part == 'spark' and mileage or (tonumber(row.spark_km) or 0)
    })
    if saved == nil then
        exports.ob_inventory:AddItem(source, requiredItem, 1)
        return false, 'Falha ao salvar manutencao; a peca foi devolvida.'
    end
    return true, 'Manutencao registrada.'
end)

RegisterNetEvent('ob_fuel:server:saveVehicleState', function(netId, state)
    local source = source
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not vehicle or vehicle == 0 or type(state) ~= 'table' then return end
    local playerPed = GetPlayerPed(source)
    if not playerPed or playerPed <= 0 then return end
    if not OR.Security.rateLimit(source, 'fuel:save_state', 5, 10000) then return end
    if GetPedInVehicleSeat(vehicle, -1) ~= playerPed and #(GetEntityCoords(playerPed) - GetEntityCoords(vehicle)) > 6.0 then return end
    netId = tonumber(netId)
    state = normalizeState(vehicle, state)

    local persistent = schemaReady and canPersistMaintenance(vehicle)
    local row
    if persistent then
        row = OR.Database.single.await([[SELECT mileage,fuel,oil_km,brake_km,spark_km,misfuel_liters,misfuel_type
            FROM ob_vehicle_maintenance WHERE plate=? LIMIT 1]], { plateOf(vehicle) }) or {}
    end

    local entityState = Entity(vehicle).state
    local authoritativeFuelType = OBFuelConfig.Types[entityState['ob:fuel_type']] and entityState['ob:fuel_type'] or state.fuelType
    state.fuelType = authoritativeFuelType
    local previousFuel = tonumber(entityState['ob:fuel'])
    if previousFuel == nil then previousFuel = persistent and (tonumber(row.fuel) or 100) or state.fuel end
    local authorization = fuelAuthorizations[source]
    local authorizationValid = authorization and authorization.netId == netId and authorization.expiresAt >= GetGameTimer()
    if state.fuel > previousFuel + 0.05 then
        if authorizationValid then
            state.fuel = math.min(state.fuel, authorization.maximumFuel)
            fuelAuthorizations[source] = nil
        else
            state.fuel = previousFuel
        end
    end

    -- Quilometragem pode subir apenas num ritmo fisicamente plausivel. Os
    -- marcos de manutencao sao exclusivamente alterados pelos callbacks que
    -- consomem a peca no servidor, nunca pelo payload do motorista.
    local previousMileage = tonumber(row and row.mileage) or 0
    local now = GetGameTimer()
    local cached = vehicleSaveStates[netId]
    if cached then previousMileage = math.max(previousMileage, cached.mileage) end
    local elapsed = cached and math.max(0, now - cached.at) / 1000 or 60
    local maximumDistance = math.max(0.25, math.min(15.0, elapsed * 0.20 + 0.25))
    state.mileage = math.max(previousMileage, math.min(state.mileage, previousMileage + maximumDistance))
    vehicleSaveStates[netId] = { mileage = state.mileage, at = now }
    state.oilKm = tonumber(row and row.oil_km) or 0
    state.brakeKm = tonumber(row and row.brake_km) or 0
    state.sparkKm = tonumber(row and row.spark_km) or 0

    local sharedMisfuel = entityState['ob:misfuel']
    local previousMisfuel = tonumber(type(sharedMisfuel) == 'table' and sharedMisfuel.liters)
        or tonumber(row and row.misfuel_liters) or 0
    local consumedLiters = math.max(0, previousFuel - state.fuel) * OBFuelConfig.Types[authoritativeFuelType].capacity / 100
    state.misfuelLiters = math.max(state.misfuelLiters, math.max(0, previousMisfuel - consumedLiters - 0.1))
    if state.misfuelLiters > previousMisfuel then
        if authorizationValid then
            state.misfuelLiters = math.min(state.misfuelLiters, previousMisfuel + authorization.liters)
            state.misfuelType = authorization.fuelType
        else
            state.misfuelLiters = previousMisfuel
            state.misfuelType = (type(sharedMisfuel) == 'table' and sharedMisfuel.type) or (row and row.misfuel_type) or nil
        end
    end
    publishState(vehicle, netId, state)
    if not persistent then return end
    local plate = plateOf(vehicle)
    OR.Database.update.await([[INSERT INTO ob_vehicle_maintenance (plate, mileage, fuel, oil_km, brake_km, spark_km, misfuel_liters, misfuel_type)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE mileage=VALUES(mileage), fuel=VALUES(fuel), oil_km=VALUES(oil_km), brake_km=VALUES(brake_km), spark_km=VALUES(spark_km), misfuel_liters=VALUES(misfuel_liters), misfuel_type=VALUES(misfuel_type)]], {
        -- Lua nao mantem um ultimo elemento nil no array. Sem este valor
        -- explicito o driver recebia somente 7 parametros para 8 "?" quando
        -- nao havia combustivel incorreto, gerando PARAMETER_COUNT a cada
        -- salvamento automatico.
        plate, state.mileage, state.fuel, state.oilKm, state.brakeKm, state.sparkKm, state.misfuelLiters, state.misfuelType or ''
    })
end)

RegisterNetEvent('ob_fuel:server:payFuel', function(netId, liters, fuelType)
    local source = source
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not vehicle or vehicle == 0 then return end
    local playerPed = GetPlayerPed(source)
    if not playerPed or playerPed <= 0 or #(GetEntityCoords(playerPed) - GetEntityCoords(vehicle)) > 6.0 then return end
    if not OR.Security.rateLimit(source, 'fuel:pay', 3, 15000) then return end
    local minimumTankHealth = tonumber(OBFuelConfig.MinimumTankHealthToRefuel) or 650.0
    if type(GetVehiclePetrolTankHealth) == 'function' then
        local readOk, tankHealth = pcall(GetVehiclePetrolTankHealth, vehicle)
        if readOk and tonumber(tankHealth) and tonumber(tankHealth) < minimumTankHealth then
            TriggerClientEvent('ob_notification:client:notify', source,
                'O tanque esta furado ou muito danificado. Repare-o antes de abastecer.', 'error')
            return
        end
    end
    liters = math.max(0, math.min(200, tonumber(liters) or 0))
    local typeData = OBFuelConfig.Types[fuelType]
    if not typeData or liters <= 0 then return end
    local entityState = Entity(vehicle).state
    local currentFuel = tonumber(entityState['ob:fuel'])
    if currentFuel == nil and schemaReady and canPersistMaintenance(vehicle) then
        currentFuel = tonumber(OR.Database.scalar.await('SELECT fuel FROM ob_vehicle_maintenance WHERE plate=? LIMIT 1', { plateOf(vehicle) })) or 100
    end
    currentFuel = numberInRange(currentFuel, 100, 0, 100)
    local engineFuelType = OBFuelConfig.Types[entityState['ob:fuel_type']] and entityState['ob:fuel_type'] or fuelType
    local capacity = OBFuelConfig.Types[engineFuelType].capacity
    local maximumLiters = math.max(0, (100 - currentFuel) * capacity / 100)
    liters = math.min(liters, maximumLiters)
    if liters < 0.1 then return end
    local price = math.ceil(liters * typeData.price)
    -- Quem possui cartao paga pelo saldo do banco. Sem cartao, o posto
    -- continua aceitando dinheiro fisico para nao bloquear jogadores novos.
    local paidByCard, paidByEconomy = false, false
    local economyResult = OR.Economy.ChargePlayer(source, price, 'fuel_purchase', 'Abastecimento', {
        liters = liters, fuelType = fuelType, netId = tonumber(netId),
    }, 'city_treasury')
    if economyResult.handled == true then
        if economyResult.success ~= true then
            TriggerClientEvent('ob_notification:client:notify', source,
                economyResult.error or 'Pagamento recusado.', 'error')
            return
        end
        paidByEconomy = true
    elseif GetResourceState('ob_bank') == 'started' then
        paidByCard = exports.ob_bank:PayWithCard(source, price, 'Abastecimento') == true
    end
    if not paidByCard and not paidByEconomy then
        local money = exports.ob_inventory:GetMoney(source, 'money') or 0
        if money < price then TriggerClientEvent('ob_notification:client:notify', source, 'Dinheiro e saldo insuficientes.', 'error') return end
        local removed = exports.ob_inventory:RemoveMoney(source, 'money', price)
        if not removed then return end
    end
    fuelAuthorizations[source] = {
        netId = tonumber(netId),
        liters = liters,
        fuelType = fuelType,
        maximumFuel = math.min(100, currentFuel + (liters / capacity * 100) + 0.25),
        expiresAt = GetGameTimer() + 15000,
    }
    TriggerClientEvent('ob_fuel:client:paidFuel', source, netId, liters, fuelType)
end)

-- Chamado pelo ob_mecanico depois de um reparo completo. A manutencao fica
-- vinculada a placa, por isso continua mesmo depois de o veiculo desstreamar.
AddEventHandler('ob_fuel:server:serviceVehicle', function(source, netId)
    source = tonumber(source)
    if not source or not GetPlayerName(source) then return end
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not vehicle or vehicle == 0 then return end
    local playerPed = GetPlayerPed(source)
    if not playerPed or playerPed <= 0 or #(GetEntityCoords(playerPed) - GetEntityCoords(vehicle)) > 6.0 then return end

    if not canPersistMaintenance(vehicle) then return end
    local plate = plateOf(vehicle)
    local row = OR.Database.single.await('SELECT mileage, fuel FROM ob_vehicle_maintenance WHERE plate = ? LIMIT 1', { plate }) or {}
    local mileage = tonumber(row.mileage) or 0
    OR.Database.update.await([[INSERT INTO ob_vehicle_maintenance (plate, mileage, fuel, oil_km, brake_km, spark_km)
        VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE mileage=VALUES(mileage), fuel=VALUES(fuel), oil_km=VALUES(oil_km), brake_km=VALUES(brake_km), spark_km=VALUES(spark_km)]], {
        plate, mileage, tonumber(row.fuel) or 100, mileage, mileage, mileage
    })
end)

AddEventHandler('playerDropped', function()
    fuelAuthorizations[tonumber(source)] = nil
end)
