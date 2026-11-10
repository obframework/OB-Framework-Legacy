ORInventoryShopBusiness = ORInventoryShopBusiness or {}

local Business = ORInventoryShopBusiness
local config = ORInventoryShops.Business or {}
local ready = false
local deliveryEntities = {}

local function clean(value, limit)
    return (tostring(value or ''):gsub('[\r\n%z]', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''):sub(1, limit or 80)
end

local function whole(value, maximum)
    value = math.floor(tonumber(value) or 0)
    return math.max(0, math.min(value, maximum or 1000000000))
end

local function userId(source)
    return tonumber(source) and GetPlayerName(source) and tonumber(exports.ob_core:GetUserId(source)) or nil
end

local function fullName(source)
    local ok, name = pcall(function() return exports.ob_core:GetFullName(source) end)
    return ok and clean(name, 100) ~= '' and clean(name, 100) or clean(GetPlayerName(source), 100)
end

local function getShop(id)
    for _, shop in ipairs(ORInventoryShops.Shops or {}) do if shop.id == id then return shop end end
end

local function getGroup(shop)
    return shop and ORInventoryShops.Groups and ORInventoryShops.Groups[shop.group] or nil
end

local function point(raw)
    return type(raw) == 'table' and tonumber(raw.x) and { x=tonumber(raw.x), y=tonumber(raw.y), z=tonumber(raw.z), w=tonumber(raw.w) or 0.0 } or nil
end

local function isPurchasable(shop, group)
    if not shop or not group or shop.purchasable == false or group.purchasable == false then return false end
    return group.category == 'convenience' and group.purchasable == true
end
local function purchasePrice(shop,group)
    local specific=whole(shop and shop.purchasePrice,1000000000)
    if specific>0 then return specific end
    local inherited=whole(group and group.purchasePrice,1000000000)
    return inherited>0 and inherited or whole(config.DefaultPurchasePrice,1000000000)
end

local function near(source, raw, distance)
    local p = point(raw)
    local ped = GetPlayerPed(source)
    if not p or not ped or ped <= 0 then return false end
    return #(GetEntityCoords(ped) - vector3(p.x,p.y,p.z)) <= (distance or 6.0)
end

local function deleteDeliveryEntities(orderId)
    local entities=deliveryEntities[tonumber(orderId)]
    if not entities then return end
    if entities.method=='pickup' and entities.vehicleNetId and GetResourceState('ob_vehiclekeys')=='started' then
        pcall(function() exports.ob_vehiclekeys:PrepareVehicleRemoval(entities.source,entities.vehicleNetId,false) end)
    end
    if entities.driver and DoesEntityExist(entities.driver) then DeleteEntity(entities.driver) end
    if entities.vehicle and DoesEntityExist(entities.vehicle) then DeleteEntity(entities.vehicle) end
    deliveryEntities[tonumber(orderId)]=nil
end

local function spawnIsClear(coords,radius)
    for _,vehicle in ipairs(GetAllVehicles()) do
        if DoesEntityExist(vehicle) and #(GetEntityCoords(vehicle)-vector3(coords.x,coords.y,coords.z))<=(radius or 7.0) then return false end
    end
    return true
end

local function productDefaults(group, entry)
    local initial = whole(entry.initialStock or group.initialStock or config.DefaultInitialStock, 1000000)
    local maximum = whole(entry.maxStock or group.maxStock or config.DefaultMaximumStock, 1000000)
    maximum = math.max(initial, maximum)
    local price = whole(entry.price, 100000000)
    local wholesale = whole(entry.wholesalePrice, 100000000)
    if wholesale < 1 then wholesale = math.max(1, math.floor(price * (tonumber(config.WholesaleRate) or 0.45))) end
    return initial, maximum, price, wholesale
end

local function ensureStock(shopId, group)
    for slot, entry in ipairs(group.items or {}) do
        local initial, maximum, price, wholesale = productDefaults(group, entry)
        OR.Database.query.await([[INSERT INTO ob_inventory_shop_stock
            (shop_id,slot,item_name,quantity,sale_price,wholesale_price,max_stock) VALUES (?,?,?,?,?,?,?)
            ON DUPLICATE KEY UPDATE slot=VALUES(slot),wholesale_price=VALUES(wholesale_price),max_stock=VALUES(max_stock),quantity=LEAST(quantity,VALUES(max_stock))]],
            { shopId, slot, entry.name, initial, price, wholesale, maximum })
    end
end

local function accountPayment(source, amount, category, description, metadata)
    if GetResourceState('ob_economy') == 'started' then
        local result = exports.ob_economy:ChargePlayer(source, amount, category, description, metadata,
            config.EconomyAccount or 'city_treasury')
        if result and result.handled == true then return result.success == true, result.error, { kind='economy', receipt=result.receipt } end
    end
    if GetResourceState('ob_bank') == 'started' then
        local paid, err = exports.ob_bank:PayWithCard(source, amount, description)
        if paid == true then return true, nil, { kind='bank' } end
    end
    local paid, err = exports.ob_inventory:RemoveMoney(source, 'money', amount)
    return paid == true, err, paid and { kind='cash' } or nil
end

local function refundPayment(source, amount, payment, description)
    if not payment then return end
    if payment.kind == 'economy' and GetResourceState('ob_economy') == 'started' then
        exports.ob_economy:RefundCharge(source, payment.receipt, description)
    elseif payment.kind == 'bank' and GetResourceState('ob_bank') == 'started' then
        exports.ob_bank:RefundToBank(source, amount, description)
    else
        exports.ob_inventory:AddMoney(source, 'money', amount)
    end
end

local function ownerRow(shopId)
    if not ready then return nil end
    return OR.Database.single.await([[SELECT shop_id,owner_user_id,owner_name,custom_name,balance,total_sales,total_tax,purchase_price,purchased_at
        FROM ob_inventory_shop_businesses WHERE shop_id=? AND owner_user_id IS NOT NULL LIMIT 1]], { shopId })
end

local function fiscalCallerAllowed()
    return GetInvokingResource() == 'ob_fiscal'
end

local function fiscalShop(shopId)
    local shop = getShop(clean(shopId, 64))
    local group = getGroup(shop)
    if not shop or not group or group.category ~= 'convenience' or group.purchasable ~= true then return nil end
    return shop, group
end

function Business.IsReady() return ready and config.Enabled == true end

local function fiscalBusinessData(rawShopId)
    local shop, group = fiscalShop(rawShopId)
    if not shop then return nil, 'Loja de conveniencia invalida.' end
    local owner = ownerRow(shop.id)
    if not owner then return nil, 'A loja ainda nao possui proprietario.' end
    local metrics = OR.Database.single.await([[SELECT
        COALESCE(SUM(CASE WHEN created_at >= DATE_SUB(NOW(),INTERVAL 24 HOUR) THEN gross_amount ELSE 0 END),0) AS sales_24h,
        COALESCE(SUM(CASE WHEN created_at >= DATE_SUB(NOW(),INTERVAL 7 DAY) THEN gross_amount ELSE 0 END),0) AS sales_7d,
        COALESCE(SUM(CASE WHEN created_at >= DATE_SUB(NOW(),INTERVAL 30 DAY) THEN gross_amount ELSE 0 END),0) AS sales_30d
        FROM ob_inventory_shop_sales WHERE shop_id=?]], { shop.id }) or {}
    return {
        shopId = shop.id, label = owner.custom_name or shop.label or group.label,
        ownerUserId = tonumber(owner.owner_user_id), ownerName = owner.owner_name,
        balance = tonumber(owner.balance) or 0, totalSales = tonumber(owner.total_sales) or 0,
        totalTax = tonumber(owner.total_tax) or 0,
        sales24h = tonumber(metrics.sales_24h) or 0, sales7d = tonumber(metrics.sales_7d) or 0,
        sales30d = tonumber(metrics.sales_30d) or 0,
        manager = point(shop.manager or shop.coords),
    }
end

exports('GetFiscalBusiness', function(rawShopId)
    if not fiscalCallerAllowed() or not Business.IsReady() then return nil, 'Integracao fiscal indisponivel.' end
    return fiscalBusinessData(rawShopId)
end)

exports('GetFiscalBusinesses', function(rawOwnerUserId)
    if not fiscalCallerAllowed() or not Business.IsReady() then return nil, 'Integracao fiscal indisponivel.' end
    local ownerUserId = tonumber(rawOwnerUserId)
    if not ownerUserId then return nil, 'Proprietario invalido.' end
    local rows = OR.Database.query.await([[SELECT shop_id FROM ob_inventory_shop_businesses
        WHERE owner_user_id=? ORDER BY shop_id]], { ownerUserId }) or {}
    local result = {}
    for _, row in ipairs(rows) do
        local shop = fiscalShop(row.shop_id)
        if shop then
            local data = fiscalBusinessData(row.shop_id)
            if data then result[#result + 1] = data end
        end
    end
    return result
end)

exports('ApplyFiscalBusinessBalance', function(rawShopId, rawOwnerUserId, rawDirection, rawAmount, rawToken, rawMetadata)
    if not fiscalCallerAllowed() or not Business.IsReady() then return nil, 'Integracao fiscal indisponivel.' end
    local shop = fiscalShop(rawShopId)
    local ownerUserId, amount = tonumber(rawOwnerUserId), whole(rawAmount)
    local direction, token = clean(rawDirection, 12):lower(), clean(rawToken, 96)
    if not shop or not ownerUserId or amount < 1 or (direction ~= 'credit' and direction ~= 'debit') or token == '' then
        return nil, 'Movimentacao fiscal invalida.'
    end
    local owner = ownerRow(shop.id)
    if not owner or tonumber(owner.owner_user_id) ~= ownerUserId then return nil, 'A loja nao pertence mais ao proprietario informado.' end
    local existing = OR.Database.single.await([[SELECT shop_id,owner_user_id,direction,amount
        FROM ob_inventory_shop_fiscal_entries WHERE token=? LIMIT 1]], { token })
    if existing then
        if existing.shop_id == shop.id and tonumber(existing.owner_user_id) == ownerUserId
            and existing.direction == direction and tonumber(existing.amount) == amount then
            return { alreadyApplied = true, balance = tonumber(owner.balance) or 0 }
        end
        return nil, 'Token fiscal ja utilizado em outra movimentacao.'
    end
    local metadata = '{}'
    pcall(function() metadata = json.encode(type(rawMetadata) == 'table' and rawMetadata or {}) end)
    local update = direction == 'credit'
        and 'UPDATE ob_inventory_shop_businesses SET balance=balance+? WHERE shop_id=? AND owner_user_id=?'
        or 'UPDATE ob_inventory_shop_businesses SET balance=balance-? WHERE shop_id=? AND owner_user_id=? AND balance>=?'
    local updateParameters = direction == 'credit' and { amount, shop.id, ownerUserId }
        or { amount, shop.id, ownerUserId, amount }
    local result, transactionError = OR.Database.transaction.await({
        { kind='insert', statement=[[INSERT INTO ob_inventory_shop_fiscal_entries
            (token,shop_id,owner_user_id,direction,amount,metadata) VALUES (?,?,?,?,?,?)]],
          parameters={token,shop.id,ownerUserId,direction,amount,metadata}, expectAffectedMin=1 },
        { kind='update', statement=update, parameters=updateParameters, expectAffectedMin=1 },
    })
    if not result then return nil, transactionError or 'Saldo empresarial insuficiente ou indisponivel.' end
    local balance = tonumber(OR.Database.scalar.await([[SELECT balance FROM ob_inventory_shop_businesses
        WHERE shop_id=? AND owner_user_id=?]], { shop.id, ownerUserId })) or 0
    return { alreadyApplied = false, balance = balance }
end)

function Business.GetPublicCatalog(shop, group)
    if not Business.IsReady() then return nil end
    local owner = ownerRow(shop.id)
    if not owner then return { owned=false, label=group.label } end
    ensureStock(shop.id, group)
    local rows = OR.Database.query.await('SELECT item_name,quantity,sale_price FROM ob_inventory_shop_stock WHERE shop_id=?', { shop.id }) or {}
    local indexed = {}
    for _, row in ipairs(rows) do indexed[row.item_name] = row end
    return { owned=true, label=owner.custom_name or group.label, stock=indexed }
end

function Business.ReserveSale(shop, group, itemName, amount)
    if not Business.IsReady() then return true, nil end
    local owner = ownerRow(shop.id)
    if not owner then return true, nil end
    ensureStock(shop.id, group)
    local changed, err = OR.Database.update.await([[UPDATE ob_inventory_shop_stock SET quantity=quantity-?
        WHERE shop_id=? AND item_name=? AND quantity>=?]], { amount, shop.id, itemName, amount })
    if not changed or changed < 1 then return false, err or 'Estoque insuficiente nesta loja.' end
    local row = OR.Database.single.await('SELECT sale_price FROM ob_inventory_shop_stock WHERE shop_id=? AND item_name=? LIMIT 1', { shop.id,itemName })
    return true, { shopId=shop.id, item=itemName, amount=amount, price=whole(row and row.sale_price), ownerUserId=tonumber(owner.owner_user_id) }
end

function Business.RollbackSale(reservation)
    if type(reservation) ~= 'table' then return end
    OR.Database.update.await('UPDATE ob_inventory_shop_stock SET quantity=LEAST(max_stock,quantity+?) WHERE shop_id=? AND item_name=?',
        { reservation.amount, reservation.shopId, reservation.item })
end

function Business.CommitSale(source, reservation, gross)
    if type(reservation) ~= 'table' then return end
    gross = whole(gross)
    local tax = math.floor(gross * math.max(0, math.min(1, tonumber(config.TaxRate) or 0.15)))
    local net = gross - tax
    if tax > 0 and GetResourceState('ob_economy') == 'started' then
        local movement = exports.ob_economy:Deposit(config.EconomyAccount or 'city_treasury', tax, 'shop_sales_tax',
            ('Imposto de venda da loja %s'):format(reservation.shopId), { shopId=reservation.shopId, gross=gross })
        if not movement then
            -- O imposto continua retido mesmo com o Tesouro em monitor/desativado.
            -- Isso preserva a economia da loja sem transformar uma indisponibilidade
            -- opcional do ob_economy em isencao fiscal.
            print(('[ob_inventory] Imposto de $%s da loja %s retido localmente; Tesouro indisponivel.'):format(tax,reservation.shopId))
        end
    end
    OR.Database.transaction.await({
        { kind='update', statement='UPDATE ob_inventory_shop_businesses SET balance=balance+?,total_sales=total_sales+?,total_tax=total_tax+? WHERE shop_id=? AND owner_user_id=?', parameters={net,gross,tax,reservation.shopId,reservation.ownerUserId}, expectAffectedMin=1 },
        { kind='insert', statement=[[INSERT INTO ob_inventory_shop_sales
            (shop_id,buyer_user_id,buyer_name,item_name,quantity,gross_amount,tax_amount,net_amount) VALUES (?,?,?,?,?,?,?,?)]],
          parameters={reservation.shopId,userId(source),fullName(source),reservation.item,reservation.amount,gross,tax,net}, expectAffectedMin=1 },
    })
end

local function ownedStoreData(source)
    local uid = userId(source)
    if not uid then return {} end
    local rows = OR.Database.query.await([[SELECT shop_id,custom_name,balance,total_sales,total_tax,purchase_price,purchased_at
        FROM ob_inventory_shop_businesses WHERE owner_user_id=? ORDER BY custom_name]], { uid }) or {}
    for _, row in ipairs(rows) do
        local shop=getShop(row.shop_id); local group=getGroup(shop); if shop and group then ensureStock(shop.id,group) end
        local stock = OR.Database.query.await([[SELECT item_name,quantity,sale_price,wholesale_price,max_stock
            FROM ob_inventory_shop_stock WHERE shop_id=? ORDER BY slot]], { row.shop_id }) or {}
        if group then local allowed={};for _,item in ipairs(group.items or {})do allowed[item.name]=true end;for index=#stock,1,-1 do if not allowed[stock[index].item_name]then table.remove(stock,index)end end end
        row.location, row.stock = shop, stock
        local active = OR.Database.single.await([[SELECT id,status,method,total_cost,created_at FROM ob_inventory_shop_orders
            WHERE shop_id=? AND status IN ('pending','in_transit') ORDER BY id DESC LIMIT 1]], { row.shop_id })
        row.activeOrder = active
    end
    return rows
end

local function nearbyOffer(source, shopId)
    local shop, group = getShop(shopId), nil
    group = getGroup(shop)
    if not isPurchasable(shop, group) or ownerRow(shopId)
        or (not near(source, shop.manager, 5.0) and not near(source, shop.coords, 5.0)) then return nil end
    return { id=shop.id, label=shop.label or group.label, price=purchasePrice(shop,group) }
end

OR.Callback.register('commercePanel', function(source, shopId)
    if not Business.IsReady() then return false, 'O gerenciamento comercial esta indisponivel; as lojas publicas continuam funcionando.' end
    if not userId(source) then return false, 'Personagem indisponivel.' end
    shopId=clean(shopId,64)
    local stores=ownedStoreData(source)
    if shopId~='' then
        local scoped={};for _,store in ipairs(stores)do if store.shop_id==shopId then scoped[#scoped+1]=store end end;stores=scoped
    end
    local offer=nearbyOffer(source,shopId)
    if shopId~='' and #stores==0 and not offer then return false,'Esta loja ja possui proprietario. Somente o dono pode administra-la.' end
    return true, { stores=stores, offer=offer, scopedShopId=shopId~='' and shopId or nil,
        scoped=shopId~='', taxRate=tonumber(config.TaxRate) or 0.15,
        fiscalAvailable=GetResourceState('ob_fiscal')=='started' }
end)
OR.Callback.register('commerceNames', function()
    if not ready then return true,{} end
    local rows=OR.Database.query.await('SELECT shop_id,custom_name FROM ob_inventory_shop_businesses WHERE owner_user_id IS NOT NULL') or {}
    local result={};for _,row in ipairs(rows)do result[row.shop_id]=row.custom_name end;return true,result
end)
OR.Callback.register('commerceResumeDeliveries', function(source)
    if not ready then return true,{} end
    local rows=OR.Database.query.await([[SELECT id,shop_id,method FROM ob_inventory_shop_orders
        WHERE owner_user_id=? AND status IN ('pending','in_transit') ORDER BY id]],{userId(source)}) or {}
    local result={};for _,row in ipairs(rows)do local shop=getShop(row.shop_id);if shop then result[#result+1]={id=tonumber(row.id),shopId=row.shop_id,method=row.method,shop=shop}end end
    return true,result
end)

OR.Callback.register('commerceTrackDelivery',function(source,orderId)
    local uid=userId(source);orderId=tonumber(orderId)
    if not uid or not orderId then return false,'Pedido invalido.' end
    local row=OR.Database.single.await([[SELECT id,shop_id,method,status FROM ob_inventory_shop_orders
        WHERE id=? AND owner_user_id=? AND status IN ('pending','in_transit') LIMIT 1]],{orderId,uid})
    if not row then return false,'Esse pedido nao esta mais em andamento.' end
    local shop=getShop(row.shop_id)
    if not shop then return false,'A loja deste pedido nao foi encontrada.' end
    return true,{id=tonumber(row.id),shopId=row.shop_id,method=row.method,shop=shop}
end)

OR.Callback.register('commerceSpawnDeliveryEntities',function(source,orderId)
    local uid=userId(source);orderId=tonumber(orderId)
    if not uid or not orderId then return false,'Pedido invalido.' end
    local order=OR.Database.single.await([[SELECT id,shop_id,method FROM ob_inventory_shop_orders
        WHERE id=? AND owner_user_id=? AND status IN ('pending','in_transit') LIMIT 1]],{orderId,uid})
    if not order then return false,'Pedido nao encontrado.' end
    local existing=deliveryEntities[orderId]
    if existing and existing.vehicle and DoesEntityExist(existing.vehicle) then
        return true,{vehicleNetId=NetworkGetNetworkIdFromEntity(existing.vehicle),
            driverNetId=existing.driver and DoesEntityExist(existing.driver) and NetworkGetNetworkIdFromEntity(existing.driver) or nil}
    end

    local shop=getShop(order.shop_id)
    local delivery=config.Delivery or {}
    local spawn=order.method=='npc' and shop and point(shop.npcSpawn)
        or shop and point(shop.truckStop or shop.npcTruckStop or shop.coords)
    if not spawn then return false,'Ponto de nascimento do caminhao nao configurado.' end
    if not spawnIsClear(spawn,tonumber(delivery.SpawnClearRadius) or 7.0) then return false,'O ponto de nascimento do caminhao esta ocupado.' end

    local vehicle=CreateVehicleServerSetter(joaat(delivery.Vehicle or 'mule3'),'automobile',spawn.x,spawn.y,spawn.z,spawn.w or 0.0)
    if not vehicle or vehicle==0 or not DoesEntityExist(vehicle) then return false,'O servidor nao conseguiu criar o caminhao.' end
    SetEntityOrphanMode(vehicle,2)
    SetEntityRoutingBucket(vehicle,GetPlayerRoutingBucket(source))
    pcall(function() SetEntityDistanceCullingRadius(vehicle,10000.0) end)
    local vehicleNetId=NetworkGetNetworkIdFromEntity(vehicle)
    if not vehicleNetId or vehicleNetId==0 then DeleteEntity(vehicle);return false,'O caminhao foi criado sem identificacao de rede.' end
    pcall(function() SetVehicleNumberPlateText(vehicle,('OB%05d'):format(orderId%100000)) end)

    local driver,driverNetId
    if order.method=='npc' then
        driver=CreatePed(26,joaat(delivery.Driver or 's_m_m_trucker_01'),spawn.x,spawn.y,spawn.z+0.5,spawn.w or 0.0,true,true)
        if not driver or driver==0 or not DoesEntityExist(driver) then
            DeleteEntity(vehicle);return false,'O servidor nao conseguiu criar o motorista.'
        end
        SetEntityOrphanMode(driver,2)
        SetEntityRoutingBucket(driver,GetPlayerRoutingBucket(source))
        pcall(function() SetEntityDistanceCullingRadius(driver,10000.0) end)
        driverNetId=NetworkGetNetworkIdFromEntity(driver)
        if not driverNetId or driverNetId==0 then
            DeleteEntity(driver);DeleteEntity(vehicle);return false,'O motorista foi criado sem identificacao de rede.'
        end
        pcall(function() SetPedIntoVehicle(driver,vehicle,-1) end)
    end
    if order.method=='pickup' then
        if GetResourceState('ob_vehiclekeys')~='started' then DeleteEntity(vehicle);return false,'Sistema de chaves indisponivel.' end
        local granted,keyError=exports.ob_vehiclekeys:GrantTemporaryKey(source,vehicleNetId)
        if not granted then DeleteEntity(vehicle);return false,keyError or 'Nao foi possivel entregar a chave do caminhao.' end
    end
    deliveryEntities[orderId]={owner=uid,source=source,method=order.method,vehicle=vehicle,vehicleNetId=vehicleNetId,driver=driver}
    return true,{vehicleNetId=vehicleNetId,driverNetId=driverNetId}
end,{rateLimit={limit=4,window=10000}})

RegisterNetEvent('ob_inventory:server:releaseDeliveryEntities',function(orderId)
    local src=source;orderId=tonumber(orderId);local entities=orderId and deliveryEntities[orderId]
    if entities and entities.owner==userId(src) then deleteDeliveryEntities(orderId) end
end)

AddEventHandler('playerDropped',function()
    local src=source
    for orderId,entities in pairs(deliveryEntities) do
        if tonumber(entities.source)==tonumber(src) then deleteDeliveryEntities(orderId) end
    end
end)

AddEventHandler('onResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    for orderId in pairs(deliveryEntities) do deleteDeliveryEntities(orderId) end
end)

OR.Callback.register('commercePurchase', function(source, data)
    local shop = getShop(clean(data and data.shopId,64)); local group = getGroup(shop)
    if not Business.IsReady() or not isPurchasable(shop, group) then return false, 'Esta loja nao esta disponivel para compra.' end
    if not near(source, shop.manager, 5.0) and not near(source, shop.coords, 5.0) then return false, 'Aproxime-se do atendente.' end
    local uid = userId(source); if not uid then return false, 'Personagem indisponivel.' end
    if ownerRow(shop.id) then return false, 'Esta loja ja possui proprietario.' end
    local count = tonumber(OR.Database.scalar.await('SELECT COUNT(*) FROM ob_inventory_shop_businesses WHERE owner_user_id=?', { uid })) or 0
    if count >= whole(config.MaxStoresPerOwner,50) then return false, 'Voce atingiu o limite de lojas.' end
    local name = clean(data and data.name,80); if #name < 3 then name = shop.label or group.label end
    local price = purchasePrice(shop,group)
    local paid, payError, payment = accountPayment(source,price,'shop_purchase',('Compra de %s'):format(name),{shopId=shop.id})
    if not paid then return false, payError or 'Pagamento recusado.' end
    local changed, dbError = OR.Database.update.await([[INSERT INTO ob_inventory_shop_businesses
        (shop_id,owner_user_id,owner_name,custom_name,purchase_price,purchased_at) VALUES (?,?,?,?,?,NOW())
        ON DUPLICATE KEY UPDATE owner_user_id=IF(owner_user_id IS NULL,VALUES(owner_user_id),owner_user_id),
        owner_name=IF(owner_user_id=VALUES(owner_user_id),VALUES(owner_name),owner_name),
        custom_name=IF(owner_user_id=VALUES(owner_user_id),VALUES(custom_name),custom_name),
        purchase_price=IF(owner_user_id=VALUES(owner_user_id),VALUES(purchase_price),purchase_price),
        purchased_at=IF(owner_user_id=VALUES(owner_user_id),NOW(),purchased_at)]], {shop.id,uid,fullName(source),name,price})
    local owner = ownerRow(shop.id)
    if changed == nil or not owner or tonumber(owner.owner_user_id) ~= uid then
        refundPayment(source,price,payment,'Estorno de compra de loja'); return false, dbError or 'A loja foi adquirida por outra pessoa.'
    end
    ensureStock(shop.id,group)
    TriggerClientEvent('ob_inventory:client:commerceRefresh',source)
    TriggerClientEvent('ob_inventory:client:commerceStoreName',-1,shop.id,name)
    return true, ('Voce comprou %s.'):format(name)
end, { rateLimit={limit=2,window=10000} })

OR.Callback.register('commerceRename', function(source, data)
    local name = clean(data and data.name,80); if #name < 3 then return false,'Informe um nome com pelo menos 3 caracteres.' end
    local changed = OR.Database.update.await('UPDATE ob_inventory_shop_businesses SET custom_name=? WHERE shop_id=? AND owner_user_id=?',
        {name,clean(data and data.shopId,64),userId(source)})
    if changed and changed>0 then TriggerClientEvent('ob_inventory:client:commerceStoreName',-1,clean(data and data.shopId,64),name) end
    return changed and changed > 0, changed and changed > 0 and 'Nome atualizado.' or 'Loja nao encontrada.'
end)

OR.Callback.register('commerceSetPrice', function(source, data)
    local shopId,item = clean(data and data.shopId,64),clean(data and data.item,64)
    local price=whole(data and data.price,100000000); if price < 1 then return false,'Preco invalido.' end
    local changed = OR.Database.update.await([[UPDATE ob_inventory_shop_stock s JOIN ob_inventory_shop_businesses b ON b.shop_id=s.shop_id
        SET s.sale_price=? WHERE s.shop_id=? AND s.item_name=? AND b.owner_user_id=?]], {price,shopId,item,userId(source)})
    return changed and changed > 0, changed and changed > 0 and 'Preco atualizado.' or 'Produto ou loja invalida.'
end)

OR.Callback.register('commerceWithdraw', function(source, data)
    local amount=whole(data and data.amount); if amount<1 then return false,'Valor invalido.' end
    local shopId,uid=clean(data and data.shopId,64),userId(source)
    local changed=OR.Database.update.await('UPDATE ob_inventory_shop_businesses SET balance=balance-? WHERE shop_id=? AND owner_user_id=? AND balance>=?',{amount,shopId,uid,amount})
    if not changed or changed<1 then return false,'Saldo insuficiente no caixa da loja.' end
    local paid,err=exports.ob_inventory:AddMoney(source,'money',amount)
    if not paid then OR.Database.update.await('UPDATE ob_inventory_shop_businesses SET balance=balance+? WHERE shop_id=?',{amount,shopId}); return false,err or 'Falha ao entregar o dinheiro.' end
    return true,'Saque realizado.'
end)

OR.Callback.register('commerceDeposit', function(source, data)
    local amount=whole(data and data.amount); if amount<1 then return false,'Valor invalido.' end
    local shopId,uid=clean(data and data.shopId,64),userId(source)
    local owns=OR.Database.scalar.await('SELECT shop_id FROM ob_inventory_shop_businesses WHERE shop_id=? AND owner_user_id=?',{shopId,uid})
    if not owns then return false,'Loja nao encontrada.' end
    local removed,err=exports.ob_inventory:RemoveMoney(source,'money',amount);if not removed then return false,err or 'Dinheiro insuficiente.' end
    local changed,dbErr=OR.Database.update.await('UPDATE ob_inventory_shop_businesses SET balance=balance+? WHERE shop_id=? AND owner_user_id=?',{amount,shopId,uid})
    if not changed or changed<1 then exports.ob_inventory:AddMoney(source,'money',amount);return false,dbErr or 'Falha ao depositar no caixa.' end
    return true,'Deposito realizado.'
end)

OR.Callback.register('commerceOrder', function(source, data)
    if not Business.IsReady() then return false,'Sistema de pedidos indisponivel.' end
    local uid=userId(source); local shopIds=type(data and data.shopIds)=='table' and data.shopIds or {}
    local wanted=type(data and data.items)=='table' and data.items or {}; local method=data and data.method=='pickup' and 'pickup' or 'npc'
    if #shopIds<1 or #shopIds>20 then return false,'Selecione de 1 a 20 lojas.' end
    local created,failures={},{}
    local function failed(shopId,message)
        failures[#failures+1]=('%s: %s'):format(shopId~='' and shopId or 'loja',message)
    end
    for _,rawId in ipairs(shopIds) do
        local shopId=clean(rawId,64); local shop=getShop(shopId); local group=getGroup(shop); local owner=ownerRow(shopId)
        local delivery=config.Delivery or {}
        local routeReady=shop and (method~='npc' or (point(shop.npcSpawn) and point(shop.truckStop or shop.npcTruckStop)
            and point(shop.npcWalkPoint) and point(shop.dropoff or shop.manager)))
        local pickupReady=method~='pickup' or point(shop and (shop.truckStop or shop.npcTruckStop or shop.coords))
        if not shop or not group then
            failed(shopId,'cadastro da loja ou grupo nao foi encontrado.')
        elseif not owner or tonumber(owner.owner_user_id)~=uid then
            failed(shopId,'voce nao e o proprietario desta loja.')
        elseif not routeReady then
            failed(shopId,'configure o nascimento, a parada, a porta/caminho do entregador e o ponto de entrega no editor.')
        elseif not pickupReady then
            failed(shopId,'configure a parada do caminhao ao lado da loja.')
        else
            ensureStock(shopId,group)
            local active=OR.Database.scalar.await("SELECT id FROM ob_inventory_shop_orders WHERE shop_id=? AND status IN ('pending','in_transit') LIMIT 1",{shopId})
            if active then
                failed(shopId,'ja existe um pedido em andamento.')
            else
                local cargo,total={},0
                local requested=false
                for itemName,rawAmount in pairs(wanted) do
                    local amount=whole(rawAmount,1000)
                    if amount>0 then
                        requested=true
                        local stock=OR.Database.single.await('SELECT quantity,wholesale_price,max_stock FROM ob_inventory_shop_stock WHERE shop_id=? AND item_name=?',{shopId,clean(itemName,64)})
                        if stock then
                            amount=math.min(amount,math.max(0,tonumber(stock.max_stock)-tonumber(stock.quantity)))
                            if amount>0 then cargo[#cargo+1]={item=clean(itemName,64),amount=amount}; total=total+amount*tonumber(stock.wholesale_price) end
                        end
                    end
                end
                local base=total
                if method=='npc' then total=math.ceil(total*(1+(tonumber(config.Delivery.NpcFeeRate) or 0.08)))
                else total=math.floor(total*(1-(tonumber(config.Delivery.PickupDiscountRate) or 0.10))) end
                if #cargo>0 and total>0 then
                    if (tonumber(owner.balance) or 0) < total then
                        failed(shopId,('o caixa possui %s, mas o pedido custa %s.'):format(OR.FormatMoney(owner.balance),OR.FormatMoney(total)))
                    else
                        local tx=OR.Database.transaction.await({
                            {kind='update',statement='UPDATE ob_inventory_shop_businesses SET balance=balance-? WHERE shop_id=? AND owner_user_id=? AND balance>=?',parameters={total,shopId,uid,total},expectAffectedMin=1},
                            {kind='insert',statement=[[INSERT INTO ob_inventory_shop_orders (shop_id,owner_user_id,method,status,cargo_json,subtotal,total_cost)
                                VALUES (?,?,?,'pending',?,?,?)]],parameters={shopId,uid,method,json.encode(cargo),base,total},expectAffectedMin=1},
                        })
                        if tx then created[#created+1]={id=tonumber(tx[2]),shopId=shopId,method=method,shop=shop}
                        else failed(shopId,'nao foi possivel registrar o pedido no banco de dados.') end
                    end
                elseif requested then
                    failed(shopId,'os produtos pedidos ja atingiram o estoque maximo.')
                else
                    failed(shopId,'informe pelo menos uma quantidade maior que zero.')
                end
            end
        end
    end
    if #created<1 then return false,failures[1] or 'Nenhum pedido foi criado.' end
    for _,order in ipairs(created) do TriggerClientEvent('ob_inventory:client:startShopDelivery',source,order) end
    local message=('%s pedido(s) criado(s).'):format(#created)
    if #failures>0 then message=message..(' %s loja(s) ignorada(s): %s'):format(#failures,failures[1]) end
    return true,message
end, {rateLimit={limit=2,window=10000},payload={maxNodes=1000,maxDepth=6}})

OR.Callback.register('commerceCompleteDelivery', function(source, orderId)
    orderId=tonumber(orderId); local uid=userId(source)
    local order=orderId and OR.Database.single.await([[SELECT id,shop_id,method,cargo_json,status FROM ob_inventory_shop_orders
        WHERE id=? AND owner_user_id=? AND status IN ('pending','in_transit') LIMIT 1]],{orderId,uid})
    if not order then return false,'Entrega invalida ou ja concluida.' end
    local shop=getShop(order.shop_id)
    local target=shop and (shop.dropoff or shop.manager or shop.coords)
    if order.method=='pickup' then
        if not near(source,target,8.0) then return false,'Leve a mercadoria ate o ponto de entrega.' end
    else
        local targetPoint=point(target)
        local entities=deliveryEntities[orderId]
        local driver=entities and entities.driver
        if not targetPoint or not driver or not DoesEntityExist(driver)
            or #(GetEntityCoords(driver)-vector3(targetPoint.x,targetPoint.y,targetPoint.z))>5.0 then
            return false,'O entregador ainda nao chegou ao ponto de entrega.'
        end
    end
    local cargo={}; pcall(function() cargo=json.decode(order.cargo_json) or {} end)
    local statements={{kind='update',statement="UPDATE ob_inventory_shop_orders SET status='delivered',completed_at=NOW() WHERE id=? AND status IN ('pending','in_transit')",parameters={orderId},expectAffectedMin=1}}
    for _,entry in ipairs(cargo) do statements[#statements+1]={kind='update',statement='UPDATE ob_inventory_shop_stock SET quantity=LEAST(max_stock,quantity+?) WHERE shop_id=? AND item_name=?',parameters={whole(entry.amount),order.shop_id,clean(entry.item,64)},expectAffectedMin=1} end
    local done,err=OR.Database.transaction.await(statements); if not done then return false,err or 'Falha ao concluir a entrega.' end
    TriggerClientEvent('ob_inventory:client:commerceRefresh',source)
    return true,'Estoque recebido com sucesso.'
end)

OR.Callback.register('commerceCancelDelivery', function(source, orderId)
    orderId=tonumber(orderId);local uid=userId(source)
    local order=orderId and OR.Database.single.await([[SELECT id,shop_id,total_cost FROM ob_inventory_shop_orders
        WHERE id=? AND owner_user_id=? AND status IN ('pending','in_transit') LIMIT 1]],{orderId,uid})
    if not order then return false,'Pedido nao encontrado.' end
    local done,err=OR.Database.transaction.await({
        {kind='update',statement="UPDATE ob_inventory_shop_orders SET status='failed',completed_at=NOW() WHERE id=? AND status IN ('pending','in_transit')",parameters={orderId},expectAffectedMin=1},
        {kind='update',statement='UPDATE ob_inventory_shop_businesses SET balance=balance+? WHERE shop_id=? AND owner_user_id=?',parameters={order.total_cost,order.shop_id,uid},expectAffectedMin=1},
    })
    local cancelled=done~=nil and done~=false
    if cancelled then TriggerClientEvent('ob_inventory:client:finishShopDelivery',source,orderId) end
    return cancelled,cancelled and 'Pedido cancelado e valor devolvido ao caixa.' or err or 'Falha ao cancelar pedido.'
end)

CreateThread(function()
    if config.Enabled ~= true or not OR.Database.waitForReady(30000) then return end
    local idType='BIGINT UNSIGNED'; pcall(function() idType=exports.ob_core:GetCharacterIdColumnType() or idType end)
    local schema={
        ([[CREATE TABLE IF NOT EXISTS ob_inventory_shop_businesses (shop_id varchar(64) NOT NULL PRIMARY KEY,owner_user_id %s NULL,owner_name varchar(100) NULL,custom_name varchar(80) NOT NULL,balance bigint unsigned NOT NULL DEFAULT 0,total_sales bigint unsigned NOT NULL DEFAULT 0,total_tax bigint unsigned NOT NULL DEFAULT 0,purchase_price bigint unsigned NOT NULL DEFAULT 0,purchased_at datetime NULL,updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),KEY idx_ob_shop_owner(owner_user_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]):format(idType),
        [[CREATE TABLE IF NOT EXISTS ob_inventory_shop_stock (shop_id varchar(64) NOT NULL,slot smallint unsigned NOT NULL,item_name varchar(64) NOT NULL,quantity int unsigned NOT NULL DEFAULT 0,sale_price int unsigned NOT NULL DEFAULT 0,wholesale_price int unsigned NOT NULL DEFAULT 0,max_stock int unsigned NOT NULL DEFAULT 0,updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),PRIMARY KEY(shop_id,item_name),KEY idx_ob_shop_stock_slot(shop_id,slot)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        ([[CREATE TABLE IF NOT EXISTS ob_inventory_shop_orders (id bigint unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,shop_id varchar(64) NOT NULL,owner_user_id %s NOT NULL,method enum('npc','pickup') NOT NULL,status enum('pending','in_transit','delivered','cancelled','failed') NOT NULL DEFAULT 'pending',cargo_json longtext NOT NULL,subtotal bigint unsigned NOT NULL,total_cost bigint unsigned NOT NULL,created_at timestamp NOT NULL DEFAULT current_timestamp(),completed_at datetime NULL,KEY idx_ob_shop_order_active(shop_id,status)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]):format(idType),
        ([[CREATE TABLE IF NOT EXISTS ob_inventory_shop_sales (id bigint unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,shop_id varchar(64) NOT NULL,buyer_user_id %s NULL,buyer_name varchar(100) NULL,item_name varchar(64) NOT NULL,quantity int unsigned NOT NULL,gross_amount bigint unsigned NOT NULL,tax_amount bigint unsigned NOT NULL,net_amount bigint unsigned NOT NULL,created_at timestamp NOT NULL DEFAULT current_timestamp(),KEY idx_ob_shop_sales(shop_id,created_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]):format(idType),
        ([[CREATE TABLE IF NOT EXISTS ob_inventory_shop_fiscal_entries (token varchar(96) NOT NULL PRIMARY KEY,shop_id varchar(64) NOT NULL,owner_user_id %s NOT NULL,direction enum('credit','debit') NOT NULL,amount bigint unsigned NOT NULL,metadata longtext NULL,created_at timestamp NOT NULL DEFAULT current_timestamp(),KEY idx_ob_shop_fiscal_shop(shop_id,created_at),KEY idx_ob_shop_fiscal_owner(owner_user_id,created_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]):format(idType),
    }
    for _,sql in ipairs(schema) do local result,err=OR.Database.query.await(sql); if result==nil then print('[ob_inventory] Falha ao preparar comercio: '..tostring(err)); return end end
    ready=true
    for _,row in ipairs(OR.Database.query.await('SELECT shop_id,custom_name FROM ob_inventory_shop_businesses WHERE owner_user_id IS NOT NULL') or {}) do
        TriggerClientEvent('ob_inventory:client:commerceStoreName',-1,row.shop_id,row.custom_name)
    end
end)

CreateThread(function()
    while true do
        Wait(60000)
        if ready then
            local minutes=math.max(5,whole(config.DeliveryTimeoutMinutes,1440))
            local expired=OR.Database.query.await(("SELECT id,shop_id,total_cost FROM ob_inventory_shop_orders WHERE status IN ('pending','in_transit') AND created_at < DATE_SUB(NOW(),INTERVAL %s MINUTE)"):format(minutes)) or {}
            for _,row in ipairs(expired) do
                OR.Database.transaction.await({
                    {kind='update',statement="UPDATE ob_inventory_shop_orders SET status='failed',completed_at=NOW() WHERE id=? AND status IN ('pending','in_transit')",parameters={row.id},expectAffectedMin=1},
                    {kind='update',statement='UPDATE ob_inventory_shop_businesses SET balance=balance+? WHERE shop_id=?',parameters={row.total_cost,row.shop_id},expectAffectedMin=1},
                })
            end
        end
    end
end)
