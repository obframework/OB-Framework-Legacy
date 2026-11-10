local function validSource(playerSource)
    playerSource = tonumber(playerSource)
    return playerSource and playerSource > 0 and GetPlayerName(playerSource) and playerSource or nil
end

local function getShop(shopId)
    if type(shopId) ~= 'string' then return nil end
    for _, shop in ipairs(ORInventoryShops.Shops or {}) do
        if shop.id == shopId then return shop end
    end
end

local function getGroup(shop)
    return shop and ORInventoryShops.Groups and ORInventoryShops.Groups[shop.group] or nil
end

local function weaponPurchaseMetadata(playerSource,shop,group,itemName)
    local definition=ORInventoryItems[itemName]
    if not definition or definition.type~='weapon' then return nil end
    local uid=exports.ob_core:GetUserId(playerSource)
    local name=exports.ob_core:GetFullName(playerSource) or GetPlayerName(playerSource) or 'Desconhecido'
    local ballisticSignature=('OBB-%s-%s-%08d'):format(os.time(),tostring(uid or 0),math.random(0,99999999))
    local policeOrigin=group.id=='police' or tostring(group.permission or ''):lower()=='police'
    if not policeOrigin then
        return {serialRemoved=true,serialStatus='removed',origin='unregistered_shop',acquiredAt=os.time(),
            ballisticSignature=ballisticSignature}
    end
    local serial=('OBP-%s-%s-%06d'):format(os.date('%y%m%d'),tostring(uid or 0),math.random(0,999999))
    return {serial=serial,serialStatus='registered',origin='police_shop',registeredToUserId=uid,
        registeredToName=name,purchasedAt=os.time(),purchasedShopId=shop.id,ballisticSignature=ballisticSignature}
end

local weaponRegistryReady=false
local function ensureWeaponRegistry()
    if weaponRegistryReady then return true end
    if not OR.Database.waitForReady(30000) then return false,'Banco de dados indisponivel.' end
    local result,errorMessage=OR.Database.query.await([[CREATE TABLE IF NOT EXISTS ob_weapon_registry (
        serial varchar(64) NOT NULL PRIMARY KEY,item_name varchar(64) NOT NULL,
        purchaser_user_id varchar(64) NOT NULL,purchaser_name varchar(100) NOT NULL,
        shop_id varchar(64) NOT NULL,purchased_at datetime NOT NULL,
        KEY idx_ob_weapon_registry_owner (purchaser_user_id),KEY idx_ob_weapon_registry_item (item_name)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    weaponRegistryReady=result~=nil
    if not weaponRegistryReady then print('[ob_inventory] Falha ao preparar registro de armas: '..tostring(errorMessage)) end
    return weaponRegistryReady,errorMessage
end

CreateThread(function()
    ensureWeaponRegistry()
end)

local function playerNearShop(playerSource, shop)
    local ped = GetPlayerPed(playerSource)
    if not ped or ped <= 0 then return false end
    local shopCoords = shop.coords
    if type(shopCoords) ~= 'table' then return false end

    local playerCoords = GetEntityCoords(ped)
    return #(playerCoords - vector3(shopCoords.x, shopCoords.y, shopCoords.z)) <= 3.25
end

local function canAccessShop(playerSource, shop, group)
    if ORInventory.IsPlayerActionRestricted and ORInventory.IsPlayerActionRestricted(playerSource) then
        return false, 'Voce nao pode usar a loja nesse estado.'
    end
    if not playerNearShop(playerSource, shop) then
        return false, 'Aproxime-se do atendente para usar a loja.'
    end
    if group.permission then
        local allowed = false
        if GetResourceState('ob_org') == 'started' then
            allowed = exports.ob_org:HasPermission(playerSource, group.permission, group.requireDuty == true) == true
        end
        if not group.requireDuty and not allowed then
            allowed = exports.ob_core:HasPermission(playerSource, group.permission) == true
        end
        if not allowed then
            return false, group.requireDuty and 'Voce precisa ter permissao e estar em servico para acessar esta loja.' or 'Voce nao tem permissao para acessar esta loja.'
        end
    end
    return true
end

local function publicShop(shop, group)
    local items = {}
    local business = ORInventoryShopBusiness and ORInventoryShopBusiness.GetPublicCatalog
        and ORInventoryShopBusiness.GetPublicCatalog(shop, group) or nil
    local economyStatus = OR.Economy.GetStatus()
    local departmentActive = type(group.departmentAccount) == 'string'
        and economyStatus.handled == true and economyStatus.mode == 'active'
    for index, entry in ipairs(group.items or {}) do
        local item = ORInventoryItems[entry.name]
        if item then
            local ownedStock = business and business.owned and business.stock and business.stock[entry.name] or nil
            items[tostring(index)] = {
                name = entry.name,
                label = item.label,
                icon = item.icon or '?',
                image = item.image,
                weight = item.weight,
                price = math.max(0, math.floor(tonumber(departmentActive and entry.departmentPrice
                    or (ownedStock and ownedStock.sale_price) or entry.price) or 0)),
                stock = ownedStock and math.max(0, math.floor(tonumber(ownedStock.quantity) or 0)) or nil,
                maxPurchase = item.type == 'weapon' and 1 or math.max(1,
                    math.floor(tonumber(entry.maxPurchase) or 0) > 0 and math.floor(tonumber(entry.maxPurchase))
                    or (math.floor(tonumber(shop.purchaseLimit) or 0) > 0 and math.floor(tonumber(shop.purchaseLimit))
                    or math.floor(tonumber(group.purchaseLimit) or 10))),
            }
        end
    end

    return {
        id = shop.id,
        label = business and business.label or group.label or 'Loja',
        owned = business and business.owned == true or false,
        currency = group.currency or ORInventoryMoneyConfig.ShopAccount,
        developmentFree = ORInventoryShops.DevelopmentFree == true,
        departmentAccount = departmentActive and group.departmentAccount or nil,
        items = items,
    }
end

local function findShopItem(group, itemName)
    if type(itemName) ~= 'string' then return nil end
    for _, entry in ipairs(group.items or {}) do
        if entry.name == itemName then return entry end
    end
end

OR.Callback.register('shopOpen', function(playerSource, shopId)
    playerSource = validSource(playerSource)
    local shop = getShop(shopId)
    local group = getGroup(shop)
    if not playerSource or not shop or not group then return false, 'Loja invalida.' end

    local allowed, accessError = canAccessShop(playerSource, shop, group)
    if not allowed then return false, accessError end
    return true, publicShop(shop, group)
end)

OR.Callback.register('shopBuy', function(playerSource, shopId, itemName, amount, targetSlot)
    playerSource = validSource(playerSource)
    local shop = getShop(shopId)
    local group = getGroup(shop)
    if not playerSource or not shop or not group then return false, 'Loja invalida.' end

    local allowed, accessError = canAccessShop(playerSource, shop, group)
    if not allowed then return false, accessError end

    local entry = findShopItem(group, itemName)
    amount = math.floor(tonumber(amount) or 0)
    local purchaseLimit=entry and math.floor(tonumber(entry.maxPurchase) or 0) or 0
    if purchaseLimit<1 then purchaseLimit=math.floor(tonumber(shop.purchaseLimit) or 0) end
    if purchaseLimit<1 then purchaseLimit=math.max(1,math.floor(tonumber(group.purchaseLimit) or 10)) end
    if entry and ORInventoryItems[entry.name] and ORInventoryItems[entry.name].type=='weapon' then purchaseLimit=1 end
    if not entry or amount < 1 or amount > purchaseLimit then
        return false,('Esta loja permite comprar no maximo %s unidades por vez.'):format(purchaseLimit)
    end
    local itemMetadata=weaponPurchaseMetadata(playerSource,shop,group,entry.name)
    if itemMetadata and itemMetadata.serial then
        local registryOk,registryError=ensureWeaponRegistry()
        if not registryOk then return false,registryError or 'Registro de armas indisponivel.' end
    end
    local reservation
    if ORInventoryShopBusiness and ORInventoryShopBusiness.ReserveSale then
        local reserved, reservationOrError = ORInventoryShopBusiness.ReserveSale(shop, group, itemName, amount)
        if not reserved then return false, reservationOrError end
        reservation = reservationOrError
    end
    local currency = group.currency or ORInventoryMoneyConfig.ShopAccount
    local unitPrice = reservation and reservation.price or math.max(0, math.floor(tonumber(entry.price) or 0))
    local fallbackPrice = unitPrice * amount
    local departmentPrice = math.max(0, math.floor(tonumber(entry.departmentPrice) or 0)) * amount
    local totalPrice = fallbackPrice
    local paid, paymentType, economyPayment = false, nil, nil
    if ORInventoryShops.DevelopmentFree ~= true and type(group.departmentAccount) == 'string'
        and group.departmentAccount ~= '' and departmentPrice > 0 then
        local result = OR.Economy.ChargeAccount(playerSource, group.departmentAccount, departmentPrice,
            'police_supplies', ('Suprimentos policiais: %sx %s'):format(amount, entry.name), {
                shopId = shop.id, item = entry.name, amount = amount,
            })
        if result.handled == true then
            if result.success ~= true then
                if reservation then ORInventoryShopBusiness.RollbackSale(reservation) end
                return false, result.error or 'O cofre da Policia nao possui saldo.'
            end
            paid, paymentType, economyPayment, totalPrice = true, 'economy', result, departmentPrice
        end
    end
    if not paid and ORInventoryShops.DevelopmentFree ~= true and totalPrice > 0 then
        -- A loja prioriza o cartao quando o banco esta ativo; quem ainda nao
        -- tem cartao continua pagando normalmente com dinheiro da mochila.
        if currency == 'money' and GetResourceState('ob_bank') == 'started' then
            paid = exports.ob_bank:PayWithCard(playerSource, totalPrice, 'Compra em loja') == true
            if paid then paymentType = 'bank' end
        end
        if not paid then
            local removed, moneyError = exports.ob_inventory:RemoveMoney(playerSource, currency, totalPrice)
            if not removed then
                if reservation then ORInventoryShopBusiness.RollbackSale(reservation) end
                return false, moneyError or 'Dinheiro e saldo insuficientes.'
            end
            paid, paymentType = true, 'cash'
        end
    end

    local added, addError = exports.ob_inventory:AddItemAtSlot(playerSource, entry.name, amount, itemMetadata, targetSlot)
    if not added then
        if reservation then ORInventoryShopBusiness.RollbackSale(reservation) end
        if paid then
            local refunded, refundError
            if paymentType == 'bank' and GetResourceState('ob_bank') == 'started' then
                refunded, refundError = exports.ob_bank:RefundToBank(playerSource, totalPrice)
            elseif paymentType == 'economy' and economyPayment then
                local result = OR.Economy.RefundAccountCharge(
                    playerSource, economyPayment.receipt, 'Estorno de suprimento policial')
                refunded, refundError = result.handled == true and result.success == true, result.error
            else
                refunded, refundError = exports.ob_inventory:AddMoney(playerSource, currency, totalPrice)
            end
            if not refunded then
                print(('[ob_inventory] CRITICO: falha ao estornar %s para %s: %s'):format(OR.FormatMoney(totalPrice), playerSource, tostring(refundError)))
            end
        end
        return false, addError or 'Nao foi possivel adicionar o item.'
    end
    if itemMetadata and itemMetadata.serial then
        local registered,registryError=OR.Database.insert.await([[INSERT INTO ob_weapon_registry
            (serial,item_name,purchaser_user_id,purchaser_name,shop_id,purchased_at)
            VALUES (?,?,?,?,?,FROM_UNIXTIME(?))]],{itemMetadata.serial,entry.name,tostring(itemMetadata.registeredToUserId or ''),
            itemMetadata.registeredToName,shop.id,itemMetadata.purchasedAt})
        if registered==nil then
            print(('[ob_inventory] Arma %s entregue, mas o registro do serial %s falhou: %s'):format(entry.name,itemMetadata.serial,tostring(registryError)))
        end
    end
    if reservation then ORInventoryShopBusiness.CommitSale(playerSource, reservation, totalPrice) end
    local inventory, inventoryError = exports.ob_inventory:GetInventory(playerSource)
    if not inventory then return false, inventoryError or 'Item adicionado, mas a mochila nao foi atualizada.' end
    return true, {
        inventory = inventory,
        shop = publicShop(shop, group),
    }, ('Recebido: %sx %s.'):format(amount, ORInventoryItems[entry.name].label)
end)
