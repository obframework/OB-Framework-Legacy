local sessions = {}
local debugUnlock = {}
local pendingMeterPayments = {}
local fleetStates = {}
local fleetStateFile = 'fleet_states.json'
local databaseReady = false

local function characterIdColumnType()
    local deadline = GetGameTimer() + 30000
    repeat
        local columnType = exports.ob_core:GetCharacterIdColumnType()
        if columnType then return columnType end
        Wait(100)
    until GetGameTimer() >= deadline
end

local function debugPrint(...)
    if Config.Debug then
        print('[orbis-busjobs]', ...)
    end
end

local function clamp(v, mn, mx)
    if v < mn then return mn end
    if v > mx then return mx end
    return v
end

local function sanitizePlate(plate)
    if type(plate) ~= 'string' then return '' end
    return plate:gsub('%W', ''):upper()
end

local function deepCopy(tbl)
    if type(tbl) ~= 'table' then return tbl end
    local result = {}
    for k, v in pairs(tbl) do
        if type(v) == 'table' then
            result[k] = deepCopy(v)
        else
            result[k] = v
        end
    end
    return result
end

local function safeNative(fn, ...)
    local ok, value = pcall(fn, ...)
    if ok then
        return value
    end
    return nil
end

local function saveFleetStates()
    local payload = json.encode(fleetStates or {})
    SaveResourceFile(GetCurrentResourceName(), fleetStateFile, payload or '{}', -1)
end

local function loadFleetStates()
    local raw = LoadResourceFile(GetCurrentResourceName(), fleetStateFile)
    if not raw or raw == '' then
        fleetStates = {}
        return
    end

    local ok, parsed = pcall(json.decode, raw)
    if ok and type(parsed) == 'table' then
        fleetStates = parsed
    else
        fleetStates = {}
    end
end

local function normalizeFleetCondition(condition)
    if type(condition) ~= 'table' then
        return nil
    end

    local normalized = {
        engineHealth = clamp(tonumber(condition.engineHealth) or 1000.0, -4000.0, 1000.0),
        bodyHealth = clamp(tonumber(condition.bodyHealth) or 1000.0, 0.0, 1000.0),
        tankHealth = clamp(tonumber(condition.tankHealth) or 1000.0, 0.0, 1000.0),
        fuel = clamp(tonumber(condition.fuel) or 100.0, 0.0, 100.0),
        burstTires = {}
    }

    if type(condition.burstTires) == 'table' then
        for _, idx in ipairs(condition.burstTires) do
            local tireIndex = tonumber(idx)
            if tireIndex and tireIndex >= 0 and tireIndex <= 7 then
                normalized.burstTires[#normalized.burstTires + 1] = tireIndex
            end
        end
    end

    return normalized
end

local function getFleetConditionFromEntity(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil
    end

    local condition = {
        engineHealth = clamp(tonumber(safeNative(GetVehicleEngineHealth, vehicle)) or 1000.0, -4000.0, 1000.0),
        bodyHealth = clamp(tonumber(safeNative(GetVehicleBodyHealth, vehicle)) or 1000.0, 0.0, 1000.0),
        tankHealth = clamp(tonumber(safeNative(GetVehiclePetrolTankHealth, vehicle)) or 1000.0, 0.0, 1000.0),
        fuel = clamp(tonumber(safeNative(GetVehicleFuelLevel, vehicle)) or 100.0, 0.0, 100.0),
        burstTires = {}
    }

    for tire = 0, 7 do
        local burst = safeNative(IsVehicleTyreBurst, vehicle, tire, false)
        if burst == true then
            condition.burstTires[#condition.burstTires + 1] = tire
        end
    end

    return condition
end

local function getUserId(src)
    return exports.ob_core:GetUserId(src)
end

local function isAdmin(src)
    if src == 0 then return true end
    return exports.ob_core:IsAdmin(src)
end

local function isDebugUnlockEnabled(src)
    return debugUnlock[src] == true
end

local function hasBusJob(src)
    if not Config.Job.requireJob then return true end
    return exports.ob_core:HasJob(src, Config.Job.name)
end

local function addMoney(src, amount)
    return exports.ob_inventory:AddItem(src, 'money', math.max(0, math.floor(tonumber(amount) or 0)))
end

local function getMoney(src)
    return exports.ob_inventory:GetItemCount(src, 'money') or 0
end

local function removeMoney(src, amount)
    return exports.ob_inventory:RemoveItem(src, 'money', math.max(0, math.floor(tonumber(amount) or 0)))
end

local function getLevelFromXp(xp)
    local step = Config.XP.levelStep
    local level = math.floor(xp / step) + 1
    if level > Config.XP.maxLevel then
        level = Config.XP.maxLevel
    end
    return level
end

local function ensureTable()
    local userIdType = characterIdColumnType()
    if not userIdType then
        print('[ob_busjobs] Tipo de ob_characters.user_id indisponivel.')
        return
    end
    local created = OR.Database.query.await(([[
        CREATE TABLE IF NOT EXISTS ob_bus_progress (
            user_id %s NOT NULL PRIMARY KEY,
            xp INT NOT NULL DEFAULT 0,
            level INT NOT NULL DEFAULT 1,
            rides INT NOT NULL DEFAULT 0,
            total_earned INT NOT NULL DEFAULT 0,
            best_fare INT NOT NULL DEFAULT 0,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            CONSTRAINT fk_ob_bus_progress_character FOREIGN KEY (user_id) REFERENCES ob_characters(user_id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]]):format(userIdType))
    databaseReady = created ~= nil
end

local function ensureProgress(userId)
    userId = tonumber(userId)
    if not databaseReady or not userId then return nil end

    OR.Database.update.await(
        'INSERT IGNORE INTO ob_bus_progress (user_id, xp, level, rides, total_earned, best_fare) VALUES (?, 0, 1, 0, 0, 0)',
        { userId }
    )

    local row = OR.Database.single.await('SELECT * FROM ob_bus_progress WHERE user_id = ?', { userId })
    if not row then return nil end

    local expectedLevel = getLevelFromXp(row.xp or 0)
    if (row.level or 1) ~= expectedLevel then
        row.level = expectedLevel
        OR.Database.update.await('UPDATE ob_bus_progress SET level = ? WHERE user_id = ?', { expectedLevel, userId })
    end

    return row
end

local function getPlayerDisplayName(firstname, lastname, userId)
    local name = ((firstname or '') .. ' ' .. (lastname or '')):gsub('^%s*(.-)%s*$', '%1')
    return name ~= '' and name or ('ID %s'):format(userId or '?')
end

local function fetchLeaderboard(userId, progressRow)
    local topXpRows = OR.Database.query.await([[
        SELECT t.user_id, t.xp, t.rides, p.firstname, p.lastname
        FROM ob_bus_progress t
        LEFT JOIN ob_characters p ON p.user_id = t.user_id
        ORDER BY t.xp DESC, t.rides DESC, t.user_id ASC
        LIMIT 50
    ]])

    local topRidesRows = OR.Database.query.await([[
        SELECT t.user_id, t.xp, t.rides, p.firstname, p.lastname
        FROM ob_bus_progress t
        LEFT JOIN ob_characters p ON p.user_id = t.user_id
        ORDER BY t.rides DESC, t.xp DESC, t.user_id ASC
        LIMIT 50
    ]])

    local xpList = {}
    for i, row in ipairs(topXpRows or {}) do
        xpList[#xpList + 1] = {
            rank = i,
            userId = row.user_id,
            name = getPlayerDisplayName(row.firstname, row.lastname, row.user_id),
            xp = tonumber(row.xp) or 0,
            rides = tonumber(row.rides) or 0
        }
    end

    local ridesList = {}
    for i, row in ipairs(topRidesRows or {}) do
        ridesList[#ridesList + 1] = {
            rank = i,
            userId = row.user_id,
            name = getPlayerDisplayName(row.firstname, row.lastname, row.user_id),
            xp = tonumber(row.xp) or 0,
            rides = tonumber(row.rides) or 0
        }
    end

    local myXpRank = 0
    local myRidesRank = 0
    local myXp = tonumber(progressRow and progressRow.xp or 0) or 0
    local myRides = tonumber(progressRow and progressRow.rides or 0) or 0

    if userId then
        local xpCount = OR.Database.single.await([[
            SELECT COUNT(*) AS c
            FROM ob_bus_progress
            WHERE xp > ?
               OR (xp = ? AND rides > ?)
               OR (xp = ? AND rides = ? AND user_id < ?)
        ]], { myXp, myXp, myRides, myXp, myRides, userId })

        local ridesCount = OR.Database.single.await([[
            SELECT COUNT(*) AS c
            FROM ob_bus_progress
            WHERE rides > ?
               OR (rides = ? AND xp > ?)
               OR (rides = ? AND xp = ? AND user_id < ?)
        ]], { myRides, myRides, myXp, myRides, myXp, userId })

        myXpRank = (tonumber(xpCount and xpCount.c or 0) or 0) + 1
        myRidesRank = (tonumber(ridesCount and ridesCount.c or 0) or 0) + 1
    end

    return {
        xp = {
            list = xpList,
            myRank = myXpRank,
            myValue = myXp
        },
        rides = {
            list = ridesList,
            myRank = myRidesRank,
            myValue = myRides
        }
    }
end

local function getVehicleConfig(model)
    if type(model) ~= 'string' then return nil end
    local modelLower = model:lower()
    for _, vehicle in ipairs(Config.Vehicles) do
        if vehicle.model:lower() == modelLower then
            return vehicle
        end
    end
    return nil
end

local function getVehicleFareMultiplier(model)
    local cfg = getVehicleConfig(model or '')
    if not cfg then return 1.0 end
    local mult = tonumber(cfg.fareMultiplier) or 1.0
    if mult < 0.5 then mult = 0.5 end
    if mult > 3.0 then mult = 3.0 end
    return mult
end

local function getPoolsUnlocked(level, forceUnlock)
    local pools = {}
    for _, pool in ipairs(Config.CallPools) do
        if forceUnlock or level >= (pool.minLevel or 1) then
            pools[#pools + 1] = pool
        end
    end
    return pools
end

local function getCityTabs(level, forceUnlock, vehicleModel)
    local tabs = {}
    for _, city in ipairs(Config.CityTabs or {}) do
        local matchesVehicle = not city.vehicleModel
            or not vehicleModel
            or (type(vehicleModel) == 'string' and city.vehicleModel:lower() == vehicleModel:lower())

        if matchesVehicle then
            tabs[#tabs + 1] = {
                id = city.id,
                label = city.label,
                vehicleModel = city.vehicleModel,
                minLevel = city.minLevel or 1,
                unlocked = forceUnlock or level >= (city.minLevel or 1),
                fareMultiplier = city.fareMultiplier or 1.0,
                xpMultiplier = city.xpMultiplier or 1.0
            }
        end
    end
    return tabs
end

local function getSession(src)
    if not sessions[src] then
        sessions[src] = {
            working = false,
            vehicleNet = nil,
            vehiclePlate = nil,
            vehicleModel = nil,
            calls = {},
            activeRide = nil,
            routeId = nil,
            routeStopIndex = nil,
            recentPickups = {}
        }
    end
    if not sessions[src].recentPickups then
        sessions[src].recentPickups = {}
    end
    return sessions[src]
end

local function buildVehiclePanel(level, selectedModel)
    local list = {}
    for _, cfg in ipairs(Config.Vehicles) do
        list[#list + 1] = {
            model = cfg.model,
            label = cfg.label,
            image = cfg.image or ('vehicles/' .. cfg.model .. '.png'),
            seats = cfg.seats or 4,
            rent = cfg.rent,
            requiredLevel = cfg.requiredLevel,
            unlocked = level >= (cfg.requiredLevel or 1),
            selected = selectedModel and selectedModel:lower() == cfg.model:lower() or false
        }
    end
    return list
end

local function getCityRoutePool(cityId)
    if type(cityId) ~= 'string' then return nil end
    local pool = Config.Routes[cityId]
    if pool and pool.pickup and pool.dropoff and #pool.pickup > 0 and #pool.dropoff > 0 then
        return pool
    end
    return nil
end

local function coordKey(v)
    return ('%.2f:%.2f'):format(v.x or 0.0, v.y or 0.0)
end

local function randomPickupDrop(cityId, usedPickupKeys, recentPickups)
    local routePool = getCityRoutePool(cityId)
    if not routePool then
        return nil, nil
    end

    local availablePickups = {}
    for _, pickupPoint in ipairs(routePool.pickup) do
        local key = coordKey(pickupPoint)
        if not usedPickupKeys or not usedPickupKeys[key] then
            availablePickups[#availablePickups + 1] = pickupPoint
        end
    end

    if type(recentPickups) == 'table' and #recentPickups > 0 then
        local filtered = {}
        for _, pickupPoint in ipairs(availablePickups) do
            local keep = true
            for i = 1, #recentPickups do
                local recent = recentPickups[i]
                if recent and recent.x and recent.y then
                    local dx = (pickupPoint.x or 0.0) - recent.x
                    local dy = (pickupPoint.y or 0.0) - recent.y
                    if (dx * dx + dy * dy) <= (220.0 * 220.0) then
                        keep = false
                        break
                    end
                end
            end
            if keep then
                filtered[#filtered + 1] = pickupPoint
            end
        end
        if #filtered > 0 then
            availablePickups = filtered
        end
    end

    local pickupSource = (#availablePickups > 0) and availablePickups or routePool.pickup
    local pickup = pickupSource[math.random(1, #pickupSource)]
    if usedPickupKeys and pickup then
        usedPickupKeys[coordKey(pickup)] = true
    end

    local dropoff = routePool.dropoff[math.random(1, #routePool.dropoff)]

    local safetyCounter = 0
    while pickup and dropoff and #(vector3(pickup.x, pickup.y, pickup.z) - vector3(dropoff.x, dropoff.y, dropoff.z)) < 420.0 and safetyCounter < 20 do
        dropoff = routePool.dropoff[math.random(1, #routePool.dropoff)]
        safetyCounter = safetyCounter + 1
    end

    return pickup, dropoff
end

local function createCall(level, city, vehicleFareMultiplier, forceUnlock, usedPickupKeys, recentPickups)
    if not city or not city.id then return nil end

    local routePool = getCityRoutePool(city.id)
    if not routePool then return nil end

    local unlockedPools = getPoolsUnlocked(level, forceUnlock)
    if #unlockedPools == 0 then
        unlockedPools[1] = Config.CallPools[1]
    end

    local pool = unlockedPools[math.random(1, #unlockedPools)]
    local pickup, dropoff = randomPickupDrop(city.id, usedPickupKeys, recentPickups)
    if not pickup or not dropoff then return nil end

    local passengerCount = math.random((Config.Ride.passengers and Config.Ride.passengers.min) or 1, (Config.Ride.passengers and Config.Ride.passengers.max) or 1)
    local fareBase = math.random(pool.fareMin, pool.fareMax)
    local fare = math.floor(fareBase * (city.fareMultiplier or 1.0) * (vehicleFareMultiplier or 1.0))
    if fare < 1 then fare = 1 end
    local xp = math.floor(math.random(pool.xpMin, pool.xpMax) * (city.xpMultiplier or 1.0))

    return {
        id = ('call:%s:%s'):format(os.time(), math.random(10000, 99999)),
        customerName = Config.CustomerNames[math.random(1, #Config.CustomerNames)],
        category = pool.label,
        cityId = city.id,
        city = city.label,
        vehicleModel = city.vehicleModel,
        minLevel = math.max(pool.minLevel or 1, city.minLevel or 1),
        fare = fare,
        xp = xp,
        passengerCount = passengerCount,
        pickup = pickup,
        dropoff = dropoff,
        distance = math.floor(#(vector3(pickup.x, pickup.y, pickup.z) - vector3(dropoff.x, dropoff.y, dropoff.z)))
    }
end

local function refillCallsFor(source, row, forceUnlock)
    local session = getSession(source)
    session.calls = {}

    local level = row.level or 1
    local cityTabs = getCityTabs(level, forceUnlock, session.vehicleModel)

    for _, city in ipairs(cityTabs) do
        if city.unlocked then
            local route = Config.Routes and Config.Routes[city.id]
            local stops = route and route.stops or {}
            if #stops >= 2 then
                session.calls[#session.calls + 1] = {
                    id = 'route:' .. city.id,
                    cityId = city.id,
                    city = city.label,
                    customerName = city.label,
                    category = ('%d paradas em sequencia'):format(#stops),
                    vehicleModel = city.vehicleModel,
                    minLevel = city.minLevel or 1,
                    fare = math.floor((Config.Ride.payout and Config.Ride.payout.base or 160) * (city.fareMultiplier or 1.0)),
                    xp = math.floor((Config.XP.rideComplete or 0) * (city.xpMultiplier or 1.0)),
                    passengerCount = 1,
                    routeId = city.id,
                    stopCount = #stops
                }
            end
        end
    end
end

local function getRouteCity(routeId, level, forceUnlock, vehicleModel)
    for _, city in ipairs(getCityTabs(level, forceUnlock, vehicleModel)) do
        if city.id == routeId then
            return city
        end
    end
    return nil
end

local function createRouteLeg(city, stopIndex)
    local route = Config.Routes and Config.Routes[city and city.id]
    local stops = route and route.stops or {}
    if #stops < 2 then return nil end

    local pickupIndex = tonumber(stopIndex) or 1
    if pickupIndex < 1 or pickupIndex > #stops then pickupIndex = 1 end
    local dropoffIndex = pickupIndex >= #stops and 1 or pickupIndex + 1
    local pickup = stops[pickupIndex]
    local dropoff = stops[dropoffIndex]
    local distance = math.floor(#(vector3(pickup.x, pickup.y, pickup.z) - vector3(dropoff.x, dropoff.y, dropoff.z)))
    local payout = Config.Ride.payout or {}
    local fare = math.floor(((payout.base or 160) + (distance * (payout.distanceMultiplier or 0.5))) * (city.fareMultiplier or 1.0))
    fare = clamp(fare, payout.min or 1, payout.max or fare)

    return {
        id = ('ride:%d:%d'):format(os.time(), math.random(1000, 9999)),
        pickup = pickup,
        dropoff = dropoff,
        customerName = 'Passageiro aguardando',
        category = ('%s | parada %d de %d'):format(city.label, pickupIndex, #stops),
        routeId = city.id,
        routeLabel = city.label,
        pickupStopIndex = pickupIndex,
        dropoffStopIndex = dropoffIndex,
        fare = fare,
        xp = math.max(1, math.floor((Config.XP.rideComplete or 1) * (city.xpMultiplier or 1.0))),
        passengerCount = 1,
        distance = distance,
        acceptedAt = os.time(),
        pickupDone = false
    }
end

local function ridePayload(ride)
    if not ride then return nil end

    -- Vetores nativos nao sao serializados de forma consistente por callbacks
    -- entre recursos. Tabelas simples preservam a parada no cliente.
    local function coordsPayload(coords)
        if not coords then return nil end
        return {
            x = tonumber(coords.x),
            y = tonumber(coords.y),
            z = tonumber(coords.z),
            w = tonumber(coords.w) or 0.0
        }
    end

    return {
        id = ride.id,
        pickup = coordsPayload(ride.pickup),
        dropoff = coordsPayload(ride.dropoff),
        customerName = ride.customerName,
        fare = ride.fare,
        xp = ride.xp,
        category = ride.category,
        routeId = ride.routeId,
        routeLabel = ride.routeLabel,
        pickupStopIndex = ride.pickupStopIndex,
        dropoffStopIndex = ride.dropoffStopIndex,
        passengerCount = 1
    }
end

local function getLevelXpBonus(level)
    return math.min(math.floor(math.max(level - 1, 0) * 2), 30)
end

local function getLevelMoneyBonus(level)
    return math.min(math.floor(math.max(level - 1, 0) * 2), 30)
end

local function buildLevelPreview(currentLevel)
    local highestRequired = 1

    for _, city in ipairs(Config.CityTabs or {}) do
        highestRequired = math.max(highestRequired, city.minLevel or 1)
    end

    for _, vehicle in ipairs(Config.Vehicles or {}) do
        highestRequired = math.max(highestRequired, vehicle.requiredLevel or 1)
    end

    local maxPreviewLevel = math.max(highestRequired + 2, currentLevel + 3, 10)
    maxPreviewLevel = math.min(maxPreviewLevel, Config.XP.maxLevel or maxPreviewLevel)

    local preview = {}
    for level = 1, maxPreviewLevel do
        local unlocks = {}

        for _, city in ipairs(Config.CityTabs or {}) do
            if (city.minLevel or 1) == level then
                unlocks[#unlocks + 1] = ('Liberar linha: %s'):format(city.label or city.id)
            end
        end

        for _, vehicle in ipairs(Config.Vehicles or {}) do
            if (vehicle.requiredLevel or 1) == level then
                unlocks[#unlocks + 1] = ('Liberar onibus: %s'):format(vehicle.label or vehicle.model)
            end
        end

        local extraUnlocks = Config.LevelUnlocks and Config.LevelUnlocks[level]
        if type(extraUnlocks) == 'table' then
            for _, txt in ipairs(extraUnlocks) do
                if type(txt) == 'string' and txt ~= '' then
                    unlocks[#unlocks + 1] = txt
                end
            end
        end

        preview[#preview + 1] = {
            level = level,
            xpBonus = getLevelXpBonus(level),
            moneyBonus = getLevelMoneyBonus(level),
            unlocks = unlocks
        }
    end

    return preview
end

local function buildPanelData(source)
    local cid = getUserId(source)
    local row = ensureProgress(cid)
    local session = getSession(source)

    if not row then return nil end

    local forceUnlock = isDebugUnlockEnabled(source)
    local unlockLevel = forceUnlock and (Config.XP.maxLevel or (row.level or 1)) or (row.level or 1)

    if session.working and (#session.calls == 0) then
        refillCallsFor(source, row, forceUnlock)
    end

    local xp = row.xp or 0
    local level = row.level or 1
    local step = Config.XP.levelStep
    local xpMin = (level - 1) * step
    local xpInLevel = xp - xpMin

    local activeRide = nil
    if session.activeRide then
        activeRide = {
            id = session.activeRide.id,
            customerName = session.activeRide.customerName,
            fare = session.activeRide.fare,
            xp = session.activeRide.xp,
            category = session.activeRide.category,
            pickupDone = session.activeRide.pickupDone,
            passengerCount = 1,
            routeId = session.activeRide.routeId,
            routeLabel = session.activeRide.routeLabel,
            pickupStopIndex = session.activeRide.pickupStopIndex,
            dropoffStopIndex = session.activeRide.dropoffStopIndex
        }
    end

    local leaderboard = fetchLeaderboard(cid, row)
    local modelKey = session.vehicleModel and session.vehicleModel:lower() or nil
    local fleetCondition = modelKey and fleetStates[modelKey] and deepCopy(fleetStates[modelKey]) or nil

    return {
        stats = {
            level = level,
            xp = xp,
            xpInLevel = xpInLevel,
            xpRequired = step,
            rides = row.rides or 0,
            totalEarned = row.total_earned or 0,
            bestFare = row.best_fare or 0
        },
        shift = {
            working = session.working,
            vehiclePlate = session.vehiclePlate,
            vehicleModel = session.vehicleModel,
            selectedVehicleModel = session.vehicleModel,
            hasActiveRide = session.activeRide ~= nil,
            activeRide = activeRide,
            fleetCondition = fleetCondition
        },
        calls = session.calls,
        meta = {
            routesAvailable = #session.calls,
            vehicles = buildVehiclePanel(unlockLevel, session.vehicleModel),
            cityTabs = getCityTabs(unlockLevel, forceUnlock, session.vehicleModel),
            activeRouteId = session.routeId,
            levelPreview = buildLevelPreview(level),
            leaderboard = leaderboard,
            debugUnlock = forceUnlock
        }
    }
end

OR.Callback.register('orbis-busjobs:server:getPanelData', function(source)
    return buildPanelData(source)
end)

OR.Callback.register('orbis-busjobs:server:refreshCalls', function(source)
    local session = getSession(source)
    if not session.working then
        return false, 'Turno inativo.'
    end
    if session.activeRide then
        return false, 'Finalize a corrida ativa antes de atualizar chamadas.'
    end

    local cid = getUserId(source)
    local row = ensureProgress(cid)
    if not row then
        return false, 'Falha ao carregar progresso.'
    end

    refillCallsFor(source, row, isDebugUnlockEnabled(source))
    return true, buildPanelData(source)
end)

OR.Callback.register('orbis-busjobs:server:startShift', function(source, selectedModel)
    if not hasBusJob(source) then
        return false, 'Voce nao tem permissao para este trabalho.'
    end

    local session = getSession(source)
    if session.working then
        return false, Config.Text.vehicleAlready
    end

    if type(selectedModel) ~= 'string' then
        return false, 'Dados do veiculo invalidos.'
    end

    local cid = getUserId(source)
    local row = ensureProgress(cid)
    if not row then
        return false, 'Falha ao carregar progresso.'
    end

    local vehicleCfg = getVehicleConfig(selectedModel)
    if not vehicleCfg then
        return false, 'Veiculo invalido.'
    end

    local forceUnlock = isDebugUnlockEnabled(source)
    if not forceUnlock and (row.level or 1) < (vehicleCfg.requiredLevel or 1) then
        return false, ('Nivel %s necessario para este veiculo.'):format(vehicleCfg.requiredLevel or 1)
    end

    local spawned, vehicleData = exports.ob_core:SpawnTemporaryVehicle(source, vehicleCfg.model, Config.Vehicle.spawn, {
        platePrefix = Config.Vehicle.platePrefix or 'BUS', fuel = Config.Vehicle.fuel or 100.0,
        clearRadius = 2.8, maxDistance = 100.0,
        serverSetterType = 'automobile',
    })
    if not spawned then return false, vehicleData or Config.Text.noSpace end

    session.working = true
    session.vehicleNet = vehicleData.netId
    session.vehiclePlate = sanitizePlate(vehicleData.plate)
    session.vehicleModel = vehicleCfg.model
    session.activeRide = nil
    session.routeId = nil
    session.routeStopIndex = nil

    refillCallsFor(source, row, forceUnlock)

    debugPrint('Shift started for', source, session.vehiclePlate, session.vehicleModel)

    local response = buildPanelData(source)
    response.spawnedVehicle = vehicleData
    return true, response
end)

OR.Callback.register('orbis-busjobs:server:stopShift', function(source, vehicleCondition)
    local session = getSession(source)
    local modelKey = session.vehicleModel and session.vehicleModel:lower() or nil

    if modelKey then
        local normalized = normalizeFleetCondition(vehicleCondition)
        if not normalized and session.vehicleNet then
            local vehicle = NetworkGetEntityFromNetworkId(session.vehicleNet)
            normalized = normalizeFleetCondition(getFleetConditionFromEntity(vehicle))
        end
        if normalized then
            fleetStates[modelKey] = normalized
            saveFleetStates()
        end
    end

    if session.vehicleNet then
        exports.ob_core:DeleteTemporaryVehicle(source, session.vehicleNet)
    end

    session.working = false
    session.vehicleNet = nil
    session.vehiclePlate = nil
    session.vehicleModel = nil
    session.calls = {}
    session.activeRide = nil
    session.routeId = nil
    session.routeStopIndex = nil
    session.recentPickups = {}
    for id, payment in pairs(pendingMeterPayments) do
        if payment.driver == source then
            pendingMeterPayments[id] = nil
        end
    end

    return true, buildPanelData(source)
end)

OR.Callback.register('orbis-busjobs:server:meterFinish', function(source, passengerSrc, amount, distanceMeters)
    local session = getSession(source)
    if not session.working then
        return false, 'Turno inativo.'
    end

    local passenger = tonumber(passengerSrc)
    local fare = tonumber(amount) or 0
    local distance = tonumber(distanceMeters) or 0.0
    local maxFare = tonumber(Config.Meter and Config.Meter.maxFare or 5000) or 5000
    local minDistance = tonumber(Config.Meter and Config.Meter.minChargeDistance or 200.0) or 200.0

    if not passenger or passenger <= 0 or GetPlayerPed(passenger) == 0 then
        return false, 'Passageiro invalido.'
    end

    if fare <= 0 then
        return false, 'Valor invalido.'
    end

    if fare > maxFare then
        fare = maxFare
    end

    if distance < minDistance then
        return false, 'Corrida curta demais para cobranca.'
    end

    local driverPed = GetPlayerPed(source)
    local passengerPed = GetPlayerPed(passenger)
    if driverPed == 0 or passengerPed == 0 then
        return false, 'Jogador invalido.'
    end

    local dist = #(GetEntityCoords(driverPed) - GetEntityCoords(passengerPed))
    if dist > 35.0 then
        return false, 'Passageiro muito longe para confirmar corrida.'
    end

    local reqId = ('meter:%s:%s:%s'):format(source, passenger, os.time())
    pendingMeterPayments[reqId] = {
        driver = source,
        passenger = passenger,
        fare = math.floor(fare),
        expiresAt = os.time() + (tonumber(Config.Meter and Config.Meter.confirmTimeout or 25) or 25)
    }

    TriggerClientEvent('orbis-busjobs:client:meterConfirmRequest', passenger, {
        id = reqId,
        fare = math.floor(fare),
        driver = source
    })
    TriggerClientEvent('orbis-busjobs:client:notify', source, 'Aguardando confirmacao do passageiro...', 'inform')
    return true, 'Cobranca enviada para o passageiro.'
end)

local function selectRoute(source, routeId)
    local session = getSession(source)
    if not session.working then
        return false, 'Turno inativo.'
    end

    local cid = getUserId(source)
    local row = ensureProgress(cid)
    if not row then
        return false, 'Falha ao carregar progresso.'
    end

    if type(routeId) ~= 'string' or routeId == '' then
        return false, 'Linha invalida.'
    end

    local forceUnlock = isDebugUnlockEnabled(source)
    local city = getRouteCity(routeId, row.level or 1, forceUnlock, session.vehicleModel)
    if not city then
        return false, 'Essa linha nao pertence ao onibus atual.'
    end

    if not city.unlocked then
        return false, ('Nivel %s necessario para esta linha.'):format(city.minLevel or 1)
    end

    local leg = createRouteLeg(city, 1)
    if not leg then
        return false, 'Essa linha nao possui paradas suficientes.'
    end

    -- Trocar a linha pelo painel encerra somente o passageiro atual; o turno e o onibus continuam.
    session.routeId = city.id
    session.routeStopIndex = leg.pickupStopIndex
    session.activeRide = leg

    return true, ridePayload(leg)
end

OR.Callback.register('orbis-busjobs:server:selectRoute', function(source, routeId)
    return selectRoute(source, routeId)
end)

-- Mantido para clientes antigos que ainda chamarem o callback anterior.
OR.Callback.register('orbis-busjobs:server:acceptCall', function(source, callId)
    local routeId = type(callId) == 'string' and callId:gsub('^route:', '') or nil
    return selectRoute(source, routeId)
end)

OR.Callback.register('orbis-busjobs:server:declineCall', function(source, callId)
    local session = getSession(source)
    if not session.working then
        return false, 'Turno inativo.'
    end

    if type(callId) ~= 'string' then
        return false, 'Chamada invalida.'
    end

    local idx
    for i, entry in ipairs(session.calls) do
        if entry.id == callId then
            idx = i
            break
        end
    end

    if not idx then
        return false, 'Chamada indisponivel.'
    end

    local removedCall = session.calls[idx]
    table.remove(session.calls, idx)

    local cid = getUserId(source)
    local row = ensureProgress(cid)
    local forceUnlock = isDebugUnlockEnabled(source)
    if row then
        if removedCall and removedCall.cityId then
            local unlockLevel = forceUnlock and (Config.XP.maxLevel or (row.level or 1)) or (row.level or 1)
            local cityTabs = getCityTabs(unlockLevel, forceUnlock, session.vehicleModel)
            for _, city in ipairs(cityTabs) do
                if city.id == removedCall.cityId and city.unlocked then
                    local call = createCall(unlockLevel, city, getVehicleFareMultiplier(session.vehicleModel), forceUnlock, nil, session.recentPickups)
                    if call then
                        session.calls[#session.calls + 1] = call
                    end
                    break
                end
            end
        end
    end

    return true, buildPanelData(source)
end)

OR.Callback.register('orbis-busjobs:server:confirmPickup', function(source, rideId)
    local session = getSession(source)
    local ride = session.activeRide

    if not ride or ride.id ~= rideId then
        return false
    end

    ride.pickupDone = true
    return true
end)

OR.Callback.register('orbis-busjobs:server:completeRide', function(source, rideId, quality)
    local session = getSession(source)
    local ride = session.activeRide

    if not session.working or not ride or ride.id ~= rideId then
        return false, 'Corrida invalida.'
    end

    if not ride.pickupDone then
        return false, 'Pickup nao confirmado.'
    end

    if (os.time() - ride.acceptedAt) < Config.Ride.minRideSeconds then
        return false, 'Tempo de corrida invalido.'
    end

    local ped = GetPlayerPed(source)
    if ped == 0 or not DoesEntityExist(ped) then
        return false, 'Jogador invalido.'
    end

    local pos = GetEntityCoords(ped)
    local drop = vector3(ride.dropoff.x, ride.dropoff.y, ride.dropoff.z)
    local dist = #(pos - drop)

    if dist > Config.Ride.serverFinishMaxDistance then
        return false, 'Voce esta longe do destino.'
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        return false, 'Voce precisa estar no onibus do turno.'
    end

    local plate = sanitizePlate(GetVehicleNumberPlateText(vehicle))
    if session.vehiclePlate and session.vehiclePlate ~= '' and plate ~= session.vehiclePlate then
        return false, 'Onibus invalido para pagamento.'
    end

    -- Nao ha reputacao nem bonus/penalidade por direcao: cada parada paga o valor fixo da linha.
    local finalFare = math.max(1, math.floor(ride.fare or 0))
    local xpGain = math.max(1, math.floor(ride.xp or Config.XP.rideComplete))

    local paid = addMoney(source, finalFare, true)
    if not paid then
        return false, 'Nao foi possivel efetuar pagamento.'
    end

    local cid = getUserId(source)
    local row = ensureProgress(cid)
    if not row then
        return false, 'Falha ao atualizar progresso.'
    end

    local newXp = (row.xp or 0) + xpGain
    local newLevel = getLevelFromXp(newXp)

    OR.Database.update.await(
        'UPDATE ob_bus_progress SET xp = ?, level = ?, rides = rides + 1, total_earned = total_earned + ?, best_fare = GREATEST(best_fare, ?) WHERE user_id = ?',
        { newXp, newLevel, finalFare, finalFare, cid }
    )

    session.activeRide = nil

    local nextRide = nil
    local city = getRouteCity(session.routeId, newLevel, isDebugUnlockEnabled(source), session.vehicleModel)
    if city and city.unlocked then
        local stops = Config.Routes and Config.Routes[city.id] and Config.Routes[city.id].stops or {}
        -- A proxima pessoa espera duas paradas adiante: uma para desembarcar e a seguinte para embarcar.
        -- Assim 20 paradas formam uma linha completa com 10 passageiros, igual ao trabalho antigo.
        session.routeStopIndex = (ride.dropoffStopIndex or 0) >= #stops and 1 or (ride.dropoffStopIndex or 0) + 1
        nextRide = createRouteLeg(city, session.routeStopIndex)
        session.activeRide = nextRide
    end

    local result = {
        fare = finalFare,
        xp = xpGain,
        level = newLevel,
        nextRide = ridePayload(nextRide),
        panel = buildPanelData(source)
    }

    return true, result
end)

RegisterNetEvent('orbis-busjobs:server:meterResponse', function(reqId, accepted)
    local src = source
    local pending = pendingMeterPayments[reqId]
    if not pending then
        return
    end

    if pending.passenger ~= src then
        return
    end

    pendingMeterPayments[reqId] = nil

    if pending.expiresAt and os.time() > pending.expiresAt then
        TriggerClientEvent('orbis-busjobs:client:notify', pending.driver, 'Tempo da cobranca expirou.', 'error')
        return
    end

    if not accepted then
        TriggerClientEvent('orbis-busjobs:client:notify', pending.driver, 'Passageiro recusou o pagamento.', 'error')
        TriggerClientEvent('orbis-busjobs:client:notify', pending.passenger, 'Pagamento recusado.', 'inform')
        return
    end

    local fare = tonumber(pending.fare) or 0
    if fare < 1 then
        TriggerClientEvent('orbis-busjobs:client:notify', pending.driver, 'Valor invalido para cobranca.', 'error')
        return
    end

    local hasMoney = getMoney(pending.passenger) >= fare
    if not hasMoney then
        TriggerClientEvent('orbis-busjobs:client:notify', pending.driver, 'Passageiro sem dinheiro suficiente.', 'error')
        TriggerClientEvent('orbis-busjobs:client:notify', pending.passenger, 'Voce nao tem dinheiro suficiente para pagar o onibus.', 'error')
        return
    end

    if not removeMoney(pending.passenger, fare) then
        TriggerClientEvent('orbis-busjobs:client:notify', pending.driver, 'Falha ao debitar pagamento do passageiro.', 'error')
        return
    end

    if not addMoney(pending.driver, fare, false) then
        addMoney(pending.passenger, fare, false)
        TriggerClientEvent('orbis-busjobs:client:notify', pending.driver, 'Falha ao creditar pagamento do taxista.', 'error')
        return
    end

    TriggerClientEvent('orbis-busjobs:client:notify', pending.driver, ('Corrida paga: +%s'):format(OR.FormatMoney(fare)), 'success')
    TriggerClientEvent('orbis-busjobs:client:notify', pending.passenger, ('Pagamento de onibus realizado: %s'):format(OR.FormatMoney(-fare)), 'success')
    TriggerEvent('orbis:bus:force_end', pending.driver, pending.passenger, 'finalizado')
end)

RegisterNetEvent('orbis-busjobs:server:forceStop', function()
    local src = source
    local session = getSession(src)

    if session.vehicleNet then
        exports.ob_core:DeleteTemporaryVehicle(src, session.vehicleNet)
    end

    session.working = false
    session.vehicleNet = nil
    session.vehiclePlate = nil
    session.vehicleModel = nil
    session.calls = {}
    session.activeRide = nil
    session.routeId = nil
    session.routeStopIndex = nil
    session.recentPickups = {}

    for id, payment in pairs(pendingMeterPayments) do
        if payment.driver == src or payment.passenger == src then
            pendingMeterPayments[id] = nil
        end
    end
end)

RegisterCommand('busdebugunlock', function(source)
    if not isAdmin(source) then
        if source ~= 0 then
            TriggerClientEvent('orbis-busjobs:client:notify', source, 'Sem permissao para esse comando.', 'error')
        end
        return
    end

    if source == 0 then
        print('[orbis-busjobs] Use esse comando em jogo para habilitar no seu personagem.')
        return
    end

    debugUnlock[source] = not debugUnlock[source]

    if debugUnlock[source] then
        TriggerClientEvent('orbis-busjobs:client:notify', source, 'Onibus debug unlock ativado. Tudo liberado para teste.', 'success')
    else
        TriggerClientEvent('orbis-busjobs:client:notify', source, 'Onibus debug unlock desativado. Voltou ao normal.', 'inform')
    end
end, false)

AddEventHandler('playerDropped', function()
    local session = sessions[source]
    if session and session.vehicleNet then exports.ob_core:DeleteTemporaryVehicle(source, session.vehicleNet) end
    sessions[source] = nil
    debugUnlock[source] = nil
    for id, payment in pairs(pendingMeterPayments) do
        if payment.driver == source or payment.passenger == source then
            pendingMeterPayments[id] = nil
        end
    end
end)

CreateThread(function()
    while true do
        Wait(10000)
        local now = os.time()
        for id, payment in pairs(pendingMeterPayments) do
            if payment.expiresAt and now > payment.expiresAt then
                pendingMeterPayments[id] = nil
                if payment.driver then
                    TriggerClientEvent('orbis-busjobs:client:notify', payment.driver, 'Passageiro nao confirmou a cobranca a tempo.', 'error')
                end
            end
        end
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    CreateThread(function()
        if not OR.Database.waitForReady(30000) then
            print('[ob_busjobs] Banco indisponivel; emprego nao iniciado.')
            return
        end
        math.randomseed(os.time() + GetGameTimer())
        math.random(); math.random(); math.random()
        loadFleetStates()
        ensureTable()
        if databaseReady then
            debugPrint('Tabela de progresso pronta.')
        else
            print('[ob_busjobs] Falha ao criar tabela de progresso.')
        end
    end)
end)
