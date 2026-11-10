local ready = false
local activeTestDrives = {}

local function sourceValid(source)
    source = tonumber(source)
    return source and source > 0 and GetPlayerName(source) and source or nil
end

local function userId(source)
    return sourceValid(source) and exports.ob_core:GetUserId(source) or nil
end

local function isAdmin(source)
    return sourceValid(source) and exports.ob_admin:HasPermission(source, 'panel.open') == true
end

local function cleanText(value, maximum)
    value = tostring(value or ''):gsub('^%s*(.-)%s*$', '%1')
    return value:sub(1, maximum or 80)
end

local function cleanModel(value)
    value = cleanText(value, 64):lower():gsub('[^%w_]', '')
    return value ~= '' and value or nil
end

local function decodePoint(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return nil end
    local ok, point = pcall(json.decode, value)
    return ok and type(point) == 'table' and point or nil
end

local function pointFromPed(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    return { x = coords.x, y = coords.y, z = coords.z, w = GetEntityHeading(ped) }
end

local function playerNear(source, point, distance)
    local here = pointFromPed(source)
    if not here or not point then return false end
    return #(vector3(here.x, here.y, here.z) - vector3(point.x, point.y, point.z)) <= (distance or OBCarshopConfig.InteractionDistance)
end

local function publicShop(row)
    return {
        id = tonumber(row.id), label = row.label, shopType = row.shop_type,
        ownerUserId = tonumber(row.owner_user_id), active = tonumber(row.active) ~= 0,
        access = decodePoint(row.access_json), delivery = decodePoint(row.delivery_json), test = decodePoint(row.test_json),
        blip = { sprite = tonumber(row.blip_sprite) or 225, color = tonumber(row.blip_color) or 3, scale = tonumber(row.blip_scale) or .82, shortRange = tonumber(row.blip_short_range) ~= 0 },
        npcModel = OBCarshopConfig.DefaultNpcModel,
    }
end

local function fetchShops(includeInactive)
    if not ready then return {} end
    local clause = includeInactive and '' or ' WHERE active = 1'
    local rows = OR.Database.query.await('SELECT id,label,shop_type,owner_user_id,access_json,delivery_json,test_json,blip_sprite,blip_color,blip_scale,blip_short_range,active FROM ob_carshops' .. clause .. ' ORDER BY id ASC') or {}
    local shops = {}
    for _, row in ipairs(rows) do shops[#shops + 1] = publicShop(row) end
    return shops
end

local function getShop(id, includeInactive)
    id = tonumber(id)
    if not ready or not id then return nil end
    local clause = includeInactive and '' or ' AND active = 1'
    local row = OR.Database.single.await('SELECT id,label,shop_type,owner_user_id,access_json,delivery_json,test_json,blip_sprite,blip_color,blip_scale,blip_short_range,active FROM ob_carshops WHERE id = ?' .. clause .. ' LIMIT 1', { id })
    return row and publicShop(row) or nil
end

local function fetchVehicles(shopId, includeDisabled)
    local clause = includeDisabled and '' or ' AND enabled = 1'
    local rows = OR.Database.query.await('SELECT id,model,label,category,price,stock,enabled FROM ob_carshop_vehicles WHERE shop_id = ?' .. clause .. ' ORDER BY category,label', { tonumber(shopId) }) or {}
    local result = {}
    for _, row in ipairs(rows) do result[#result + 1] = { id = tonumber(row.id), model = row.model, label = row.label, category = row.category, price = tonumber(row.price) or 0, stock = tonumber(row.stock) or 0, enabled = tonumber(row.enabled) ~= 0 } end
    return result
end

local function notify(source, message, kind)
    TriggerClientEvent('ob_carshop:client:notify', source, message, kind or 'inform')
end

local function syncShops(target)
    TriggerClientEvent('ob_carshop:client:syncShops', target or -1, fetchShops(false))
end

local function uniquePlate()
    for _ = 1, 40 do
        local plate = ('OB%02d%03d'):format(math.random(10, 99), math.random(0, 999))
        if not OR.Database.scalar.await('SELECT id FROM ob_player_vehicles WHERE plate = ? LIMIT 1', { plate }) then return plate end
    end
    return ('OB%06d'):format(math.random(0, 999999))
end

CreateThread(function()
    if not OR.Database.waitForReady(30000) then print('[ob_carshop] Banco indisponivel.'); return end
    local statements = {
        [[CREATE TABLE IF NOT EXISTS ob_carshops (
            id int unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY, label varchar(80) NOT NULL,
            shop_type enum('public','player') NOT NULL DEFAULT 'public', owner_user_id bigint unsigned DEFAULT NULL,
            access_json text NOT NULL, delivery_json text DEFAULT NULL, test_json text DEFAULT NULL,
            blip_sprite smallint unsigned NOT NULL DEFAULT 225, blip_color smallint unsigned NOT NULL DEFAULT 3,
            blip_scale decimal(4,2) NOT NULL DEFAULT 0.82, blip_short_range tinyint(1) NOT NULL DEFAULT 1,
            active tinyint(1) NOT NULL DEFAULT 1, created_at timestamp NOT NULL DEFAULT current_timestamp(),
            updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(), INDEX idx_ob_carshops_owner (owner_user_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS ob_carshop_vehicles (
            id int unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY, shop_id int unsigned NOT NULL, model varchar(64) NOT NULL,
            label varchar(80) NOT NULL, category varchar(48) NOT NULL DEFAULT 'Outros', price int unsigned NOT NULL,
            stock int unsigned NOT NULL DEFAULT 0, enabled tinyint(1) NOT NULL DEFAULT 1,
            created_at timestamp NOT NULL DEFAULT current_timestamp(), updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
            UNIQUE KEY uq_ob_carshop_vehicle_model (shop_id, model),
            CONSTRAINT fk_ob_carshop_vehicles_shop FOREIGN KEY (shop_id) REFERENCES ob_carshops(id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS ob_player_vehicles (
            id bigint unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY, user_id bigint unsigned NOT NULL, shop_id int unsigned DEFAULT NULL,
            plate varchar(12) NOT NULL, model varchar(64) NOT NULL, label varchar(80) NOT NULL, properties longtext DEFAULT NULL,
            state varchar(32) NOT NULL DEFAULT 'stored', purchased_at timestamp NOT NULL DEFAULT current_timestamp(),
            UNIQUE KEY uq_ob_player_vehicles_plate (plate), INDEX idx_ob_player_vehicles_user (user_id),
            CONSTRAINT fk_ob_player_vehicles_user FOREIGN KEY (user_id) REFERENCES ob_characters(user_id) ON DELETE CASCADE,
            CONSTRAINT fk_ob_player_vehicles_shop FOREIGN KEY (shop_id) REFERENCES ob_carshops(id) ON DELETE SET NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    }
    for _, statement in ipairs(statements) do
        local result, err = OR.Database.query.await(statement)
        if result == nil then print(('[ob_carshop] Falha ao criar tabela: %s'):format(tostring(err))); return end
    end
    ready = true; syncShops(); print('[ob_carshop] Banco e concessionarias prontos.')

    -- Migra apenas o ponto antigo da loja demonstrativa para a pista de teste.
    -- Nao altera lojas criadas/ajustadas manualmente pelo administrador.
    OR.Database.update.await([[UPDATE ob_carshops SET test_json = ?
        WHERE label = ? AND test_json = ?]], {
        '{"x":-888.5062,"y":-3207.2808,"z":13.9464,"w":55.2832}',
        'Premium Motors',
        '{"x":-47.8838,"y":-1097.4756,"z":26.4223,"w":70.0000}'
    })
end)

OR.Callback.register('shops', function() return ready and fetchShops(false) or nil, 'Concessionarias ainda estao iniciando.' end)

OR.Callback.register('imageModels', function()
    if not ready then return {} end
    local rows = OR.Database.query.await('SELECT DISTINCT model FROM ob_carshop_vehicles WHERE enabled = 1') or {}
    local models = {}
    for _, row in ipairs(rows) do models[#models + 1] = row.model end
    return models
end)

OR.Callback.register('openShop', function(source, shopId)
    source = sourceValid(source); local shop = getShop(shopId)
    if not source or not shop then return nil, 'Concessionaria indisponivel.' end
    if not playerNear(source, shop.access, 4.0) then return nil, 'Aproxime-se da concessionaria.' end
    return { shop = shop, vehicles = fetchVehicles(shop.id, false), cash = exports.ob_inventory:GetMoney(source, 'money') or 0 }
end)

OR.Callback.register('buyVehicle', function(source, shopId, vehicleId)
    source = sourceValid(source); local shop, character = getShop(shopId), userId(source)
    if not source or not shop or not character then return false, 'Concessionaria ou personagem indisponivel.' end
    if GetResourceState('ob_garage') ~= 'started' then return false, 'Garagem indisponivel. Tente novamente em instantes.' end
    if not playerNear(source, shop.access, 4.0) then return false, 'Aproxime-se da concessionaria.' end
    if not shop.delivery then return false, 'Esta loja ainda nao possui ponto de entrega.' end
    local vehicle = OR.Database.single.await('SELECT id,model,label,price,stock FROM ob_carshop_vehicles WHERE id=? AND shop_id=? AND enabled=1 LIMIT 1', { tonumber(vehicleId), shop.id })
    if not vehicle or tonumber(vehicle.stock) < 1 then return false, 'Veiculo indisponivel no estoque.' end
    local price = math.max(0, math.floor(tonumber(vehicle.price) or 0))
    if OR.Database.update.await('UPDATE ob_carshop_vehicles SET stock=stock-1 WHERE id=? AND stock>0', { vehicle.id }) ~= 1 then return false, 'Estoque acabou de ser atualizado.' end
    local paid, paymentError, paidByCard, economyPayment = false, nil, false, nil
    local economyResult = OR.Economy.ChargePlayer(source, price, 'vehicle_purchase',
        ('Compra de veiculo: %s'):format(vehicle.label),
        { shopId = tonumber(shop.id), vehicleId = tonumber(vehicle.id), model = vehicle.model }, 'city_treasury')
    if economyResult.handled == true then
        paid = economyResult.success == true
        paymentError = economyResult.error
        economyPayment = paid and economyResult or nil
    else
        if GetResourceState('ob_bank') == 'started' then
            paid, paymentError = exports.ob_bank:PayWithCard(source, price, 'Compra de veiculo')
            paidByCard = paid == true
        end
    end
    if not paid and economyResult.handled ~= true then
        if (exports.ob_inventory:GetMoney(source, 'money') or 0) < price then
            OR.Database.update.await('UPDATE ob_carshop_vehicles SET stock=stock+1 WHERE id=?', { vehicle.id })
            return false, paymentError or 'Dinheiro fisico e saldo insuficientes.'
        end
        paid, paymentError = exports.ob_inventory:RemoveMoney(source, 'money', price)
    end
    if not paid then OR.Database.update.await('UPDATE ob_carshop_vehicles SET stock=stock+1 WHERE id=?', { vehicle.id }); return false, paymentError or 'Pagamento recusado.' end
    local plate = uniquePlate()
    local inserted, errorMessage = exports.ob_garage:RegisterVehicleForUser(character, {
        plate = plate,
        model = vehicle.model,
        label = vehicle.label,
        garage = OBCarshopConfig.DefaultGarage or 'central',
        fuel = 100.0,
        purchasePrice = price,
        vehicleType = 'personal',
        properties = { model = vehicle.model, fuel = 100.0, engine = 1000.0, body = 1000.0 }
    })
    if not inserted then
        if economyPayment then
            local refund = OR.Economy.RefundCharge(source, economyPayment.receipt, 'Estorno de veiculo')
            if refund.handled ~= true then
                if economyPayment.method == 'card' and GetResourceState('ob_bank') == 'started' then
                    exports.ob_bank:RefundToBank(source, price, 'Estorno de veiculo')
                else
                    exports.ob_inventory:AddMoney(source, 'money', price)
                end
            end
        elseif paidByCard and GetResourceState('ob_bank') == 'started' then
            exports.ob_bank:RefundToBank(source, price, 'Estorno de veiculo')
        else
            exports.ob_inventory:AddMoney(source, 'money', price)
        end
        OR.Database.update.await('UPDATE ob_carshop_vehicles SET stock=stock+1 WHERE id=?', { vehicle.id })
        return false, errorMessage or 'Falha ao registrar veiculo.'
    end
    local spawned, result = exports.ob_garage:SpawnOwnedVehicle(source, inserted, shop.delivery, {
        garageId = OBCarshopConfig.DefaultGarage or 'central',
        clearRadius = OBCarshopConfig.DeliveryClearRadius or 3.0,
        maxDistance = 100.0,
    })
    if not spawned then
        return true, {
            id = tonumber(inserted), plate = plate, model = vehicle.model, label = vehicle.label,
            cash = exports.ob_inventory:GetMoney(source, 'money') or 0,
        }, ('%s comprado com placa %s. A entrega esta ocupada; retire-o na garagem.'):format(vehicle.label, plate)
    end
    result.cash = exports.ob_inventory:GetMoney(source, 'money') or 0
    result.label = vehicle.label
    return true, result, ('%s entregue com placa %s.'):format(vehicle.label, plate)
end)

OR.Callback.register('testVehicle', function(source, shopId, vehicleId)
    source = sourceValid(source); local shop = getShop(shopId)
    if not source or not shop then return nil, 'Concessionaria indisponivel.' end
    if not playerNear(source, shop.access, 4.0) then return nil, 'Aproxime-se da concessionaria.' end
    if not shop.test then return nil, 'Esta loja ainda nao possui ponto de teste.' end
    local vehicle = OR.Database.single.await('SELECT model,label,stock FROM ob_carshop_vehicles WHERE id=? AND shop_id=? AND enabled=1 LIMIT 1', { tonumber(vehicleId), shop.id })
    if not vehicle or tonumber(vehicle.stock) < 1 then return nil, 'Veiculo indisponivel para teste.' end
    if activeTestDrives[source] then
        exports.ob_core:DeleteTemporaryVehicle(source, activeTestDrives[source])
        activeTestDrives[source] = nil
    end
    local spawned, result = exports.ob_core:SpawnTemporaryVehicle(source, vehicle.model, shop.test, {
        plate = 'TESTE OB',
        fuel = 100.0,
        clearRadius = OBCarshopConfig.DeliveryClearRadius or 3.0,
        maxDistance = 5000.0,
        serverSetterType = 'automobile',
    })
    if not spawned then return nil, result or 'Nao foi possivel criar o veiculo de teste.' end
    activeTestDrives[source] = result.netId
    return {
        netId = result.netId, plate = result.plate, model = vehicle.model, label = vehicle.label,
        point = shop.test, returnPoint = shop.access, duration = 90,
    }
end)

RegisterNetEvent('ob_carshop:server:finishTestDrive', function(netId)
    local playerSource = sourceValid(source)
    netId = tonumber(netId) or 0
    if not playerSource or activeTestDrives[playerSource] ~= netId then return end
    exports.ob_core:DeleteTemporaryVehicle(playerSource, netId)
    activeTestDrives[playerSource] = nil
end)

AddEventHandler('playerDropped', function()
    local playerSource = tonumber(source)
    if activeTestDrives[playerSource] then
        exports.ob_core:DeleteTemporaryVehicle(playerSource, activeTestDrives[playerSource])
        activeTestDrives[playerSource] = nil
    end
end)

OR.Callback.register('adminData', function(source)
    if not isAdmin(source) then return nil, 'Sem permissao administrativa.' end
    local shops = fetchShops(true); for _, shop in ipairs(shops) do shop.vehicles = fetchVehicles(shop.id, true) end
    return { shops = shops, suggested = OBCarshopConfig.SuggestedVehicles }
end)

RegisterCommand('obcarshopadmin', function(source)
    if source == 0 then return print('[ob_carshop] Este comando deve ser aberto dentro do jogo.') end
    if not isAdmin(source) then return notify(source, 'Sem permissao administrativa.', 'error') end
    TriggerClientEvent('ob_carshop:client:openAdmin', source)
end, false)

RegisterNetEvent('ob_carshop:server:createShop', function(data)
    local source = source
    if not isAdmin(source) or not ready then return end
    local label = cleanText(data and data.label, 80); if label == '' then return notify(source, 'Informe o nome da concessionaria.', 'error') end
    local shopType = data and data.shopType == 'player' and 'player' or 'public'; local owner = math.floor(tonumber(data and data.ownerUserId) or 0)
    if shopType == 'public' or owner < 1 then owner = nil end
    local access = pointFromPed(source); if not access then return end
    local result, err = OR.Database.insert.await('INSERT INTO ob_carshops (label,shop_type,owner_user_id,access_json) VALUES (?,?,?,?)', { label, shopType, owner, json.encode(access) })
    if not result then return notify(source, err or 'Falha ao criar concessionaria.', 'error') end
    syncShops(); notify(source, 'Concessionaria criada na sua posicao.', 'success'); TriggerClientEvent('ob_carshop:client:refreshAdmin', source)
end)

RegisterNetEvent('ob_carshop:server:setPoint', function(data)
    local source = source
    if not isAdmin(source) or not ready or type(data) ~= 'table' then return end
    local shopId, column = tonumber(data.shopId), ({ access='access_json',delivery='delivery_json',test='test_json' })[data.point]
    if not shopId or not column or not getShop(shopId, true) then return notify(source, 'Concessionaria ou ponto invalido.', 'error') end
    OR.Database.update.await(('UPDATE ob_carshops SET %s=? WHERE id=?'):format(column), { json.encode(pointFromPed(source)), shopId })
    syncShops(); notify(source, 'Ponto salvo na sua posicao.', 'success'); TriggerClientEvent('ob_carshop:client:refreshAdmin', source)
end)

RegisterNetEvent('ob_carshop:server:saveVehicle', function(data)
    local source = source
    if not isAdmin(source) or not ready or type(data) ~= 'table' then return end
    local shopId, model = tonumber(data.shopId), cleanModel(data.model); local label, category = cleanText(data.label,80), cleanText(data.category,48)
    local price, stock = math.floor(tonumber(data.price) or -1), math.floor(tonumber(data.stock) or -1)
    if not getShop(shopId, true) or not model or label == '' or price < 0 or stock < 0 then return notify(source, 'Dados do veiculo invalidos.', 'error') end
    if category == '' then category = 'Outros' end
    local result, err = OR.Database.insert.await([[INSERT INTO ob_carshop_vehicles (shop_id,model,label,category,price,stock,enabled) VALUES (?,?,?,?,?,?,1)
        ON DUPLICATE KEY UPDATE label=VALUES(label),category=VALUES(category),price=VALUES(price),stock=VALUES(stock),enabled=1]], { shopId, model, label, category, price, stock })
    if not result then return notify(source, err or 'Falha ao salvar veiculo.', 'error') end
    notify(source, 'Veiculo salvo no catalogo.', 'success'); TriggerClientEvent('ob_carshop:client:refreshAdmin', source)
end)

RegisterNetEvent('ob_carshop:server:deleteVehicle', function(data)
    local source = source; if not isAdmin(source) or type(data) ~= 'table' then return end
    OR.Database.update.await('DELETE FROM ob_carshop_vehicles WHERE id=? AND shop_id=?', { tonumber(data.id), tonumber(data.shopId) })
    notify(source, 'Veiculo removido.', 'success'); TriggerClientEvent('ob_carshop:client:refreshAdmin', source)
end)

RegisterNetEvent('ob_carshop:server:deleteShop', function(shopId)
    local source = source; if not isAdmin(source) or not tonumber(shopId) then return end
    OR.Database.update.await('DELETE FROM ob_carshops WHERE id=?', { tonumber(shopId) })
    syncShops(); notify(source, 'Concessionaria removida.', 'success'); TriggerClientEvent('ob_carshop:client:refreshAdmin', source)
end)

exports('GetPlayerVehicles', function(playerSource)
    local character = userId(playerSource)
    return character and OR.Database.query.await("SELECT id,plate,model,label,properties,stored FROM ob_vehicles WHERE owner_user_id=? AND vehicle_type<>'free' ORDER BY id DESC", { character }) or {}
end)
exports('SetVehicleState', function(plate, state)
    local stored = state == true or state == 'stored' or state == 'garage'
    return OR.Database.update.await('UPDATE ob_vehicles SET stored=? WHERE plate=?', { stored and 1 or 0, cleanText(plate,12) })
end)
