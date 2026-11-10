local function findLocation(id)
    for _, location in ipairs(OBStoresConfig.Locations or {}) do
        if location.id == id then return location end
    end
end

local function economySettings()
    local config = type(OBStoresConfig.Economy) == 'table' and OBStoresConfig.Economy or {}
    return {
        enabled = config.Enabled == true,
        tryCardFirst = config.TryCardFirst ~= false,
        allowCash = config.AllowCash ~= false,
        itemPrices = type(config.ItemPrices) == 'table' and config.ItemPrices or {},
    }
end

local function unitPriceFor(location)
    local economy = economySettings()
    if not economy.enabled then return 0 end
    return math.max(0, math.floor(tonumber(location.price) or tonumber(economy.itemPrices[location.kind]) or 0))
end

local function copied(value)
    local ok, encoded = pcall(json.encode, value)
    if not ok then return nil end
    local decodedOk, decoded = pcall(json.decode, encoded)
    return decodedOk and decoded or nil
end

local function indexed(list, idField, id)
    for _, entry in ipairs(type(list) == 'table' and list or {}) do
        if tonumber(entry[idField]) == tonumber(id) then return entry end
    end
end

local function sameFields(first, second, fields)
    first, second = type(first) == 'table' and first or {}, type(second) == 'table' and second or {}
    for _, field in ipairs(fields) do
        if first[field] ~= second[field] then return false end
    end
    return true
end

local function sameTattoos(first, second)
    first, second = type(first) == 'table' and first or {}, type(second) == 'table' and second or {}
    if #first ~= #second then return false end
    local fields = { 'name', 'collection', 'hashMale', 'hashFemale', 'opacity' }
    for index = 1, #first do
        if not sameFields(first[index], second[index], fields) then return false end
    end
    return true
end

local function replaceIndexed(list, idField, id, value)
    list = type(list) == 'table' and list or {}
    for index, entry in ipairs(list) do
        if tonumber(entry[idField]) == tonumber(id) then list[index] = copied(value); return list end
    end
    if value then list[#list + 1] = copied(value) end
    return list
end

-- O cliente mostra o carrinho, mas o servidor monta novamente somente os
-- campos permitidos naquela loja e calcula o valor comparando com o banco.
local function checkoutFor(source, location, submitted)
    local okOld, oldAppearance = pcall(function()
        return exports.ob_creator:GetAppearanceForSource(source)
    end)
    local okNew, newAppearance = pcall(function()
        return exports.ob_creator:NormalizeAppearance(submitted)
    end)
    if not okOld or type(oldAppearance) ~= 'table' or not okNew or type(newAppearance) ~= 'table' then
        return nil, nil, nil, 'Nao foi possivel comparar sua aparencia atual.'
    end
    local merged = copied(oldAppearance)
    if type(merged) ~= 'table' then return nil, nil, nil, 'Aparencia atual invalida.' end
    local changed, breakdown = 0, {}
    local componentFields = { 'drawable', 'texture', 'palette', 'collection', 'local_drawable' }
    local propFields = { 'drawable', 'texture', 'collection', 'local_drawable' }
    local hairFields = { 'style', 'texture', 'palette', 'collection', 'local_drawable', 'color', 'highlight' }
    local overlayFields = { 'style', 'opacity', 'color', 'secondColor' }

    for _, section in ipairs(OBStoresUiFor(location).sections) do
        for _, category in ipairs(type(section.categories) == 'table' and section.categories or {}) do
            local wasChanged = false
            if category.kind == 'component' then
                local oldValue = indexed(oldAppearance.components, 'component_id', category.component)
                local newValue = indexed(newAppearance.components, 'component_id', category.component)
                if newValue then
                    wasChanged = not sameFields(oldValue, newValue, componentFields)
                    merged.components = replaceIndexed(merged.components, 'component_id', category.component, newValue)
                end
            elseif category.kind == 'prop' then
                local oldValue = indexed(oldAppearance.props, 'prop_id', category.prop)
                local newValue = indexed(newAppearance.props, 'prop_id', category.prop)
                if newValue then
                    wasChanged = not sameFields(oldValue, newValue, propFields)
                    merged.props = replaceIndexed(merged.props, 'prop_id', category.prop, newValue)
                end
            elseif category.kind == 'hair' then
                wasChanged = not sameFields(oldAppearance.hair, newAppearance.hair, hairFields)
                merged.hair = copied(newAppearance.hair)
            elseif category.kind == 'eyeColor' then
                wasChanged = tonumber(oldAppearance.eyeColor) ~= tonumber(newAppearance.eyeColor)
                merged.eyeColor = newAppearance.eyeColor
            elseif category.kind == 'overlay' then
                local oldValue = type(oldAppearance.headOverlays) == 'table' and oldAppearance.headOverlays[category.overlay] or nil
                local newValue = type(newAppearance.headOverlays) == 'table' and newAppearance.headOverlays[category.overlay] or nil
                if newValue then
                    wasChanged = not sameFields(oldValue, newValue, overlayFields)
                    merged.headOverlays = type(merged.headOverlays) == 'table' and merged.headOverlays or {}
                    merged.headOverlays[category.overlay] = copied(newValue)
                end
            elseif category.kind == 'tattoo' then
                local oldValue = type(oldAppearance.tattoos) == 'table' and oldAppearance.tattoos[category.zone] or nil
                local newValue = type(newAppearance.tattoos) == 'table' and newAppearance.tattoos[category.zone] or nil
                wasChanged = not sameTattoos(oldValue, newValue)
                merged.tattoos = type(merged.tattoos) == 'table' and merged.tattoos or {}
                merged.tattoos[category.zone] = copied(newValue or {})
            end
            if wasChanged then
                changed = changed + 1
                breakdown[#breakdown + 1] = tostring(category.id or category.label or category.kind):sub(1, 48)
            end
        end
    end
    return merged, unitPriceFor(location) * changed, changed, breakdown
end

local function playerNearLocation(source, location)
    source = tonumber(source)
    local ped = source and GetPlayerPed(source) or 0
    if ped <= 0 then return false end
    local maximum = math.max(3.0, (tonumber(location.radius) or 1.65) + 2.0)
    return #(GetEntityCoords(ped) - location.coords) <= maximum
end

local function takePayment(source, amount, description, metadata)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount == 0 then return true, 'free' end
    local economyResult = OR.Economy.ChargePlayer(
        source, amount, 'store_purchase', description, metadata, 'city_treasury')
    if economyResult.handled == true then
        if economyResult.success == true then return true, economyResult end
        return false, economyResult.error or 'Pagamento recusado pela economia.'
    end
    local economy = economySettings()
    local cardError
    if economy.tryCardFirst and GetResourceState('ob_bank') == 'started' then
        local paid, err = exports.ob_bank:PayWithCard(source, amount, description)
        if paid == true then return true, 'card' end
        cardError = err
    end
    if economy.allowCash and GetResourceState('ob_inventory') == 'started' then
        if (exports.ob_inventory:GetMoney(source, 'money') or 0) >= amount then
            local paid, err = exports.ob_inventory:RemoveMoney(source, 'money', amount)
            if paid == true then return true, 'cash' end
            return false, err or cardError or 'Pagamento recusado.'
        end
    end
    return false, cardError or 'Saldo no cartao e dinheiro em maos insuficientes.'
end

local function refundPayment(source, amount, method)
    if amount <= 0 or method == 'free' then return true end
    if type(method) == 'table' and method.receipt then
        local result = OR.Economy.RefundCharge(source, method.receipt, 'Estorno de personalizacao')
        if result.handled == true then return result.success == true end
        method = method.method == 'card' and 'card' or 'cash'
    end
    if method == 'card' and GetResourceState('ob_bank') == 'started' then
        return exports.ob_bank:RefundToBank(source, amount, 'Estorno de personalizacao') == true
    end
    return GetResourceState('ob_inventory') == 'started'
        and exports.ob_inventory:AddMoney(source, 'money', amount) == true
end

OR.Callback.register('purchase', function(source, locationId, appearance)
    source = tonumber(source)
    local location = type(locationId) == 'string' and findLocation(locationId) or nil
    if not source or not location or type(appearance) ~= 'table' then return false, 'Dados da loja invalidos.' end
    if not OR.Security.rateLimit(source, 'stores:purchase', 2, 10000) then
        return false, 'Aguarde antes de tentar salvar novamente.'
    end
    if not exports.ob_core:GetUserId(source) then return false, 'Personagem indisponivel.' end
    if not OBStoresAccess(source, location) then return false, 'Sem permissao ou fora de servico.' end
    if not playerNearLocation(source, location) then return false, 'Aproxime-se novamente do balcao da loja.' end
    if GetResourceState('ob_creator') ~= 'started' then return false, 'Sistema de aparencia indisponivel.' end

    local checkedAppearance, price, itemCount, breakdownOrError = checkoutFor(source, location, appearance)
    if not checkedAppearance then return false, breakdownOrError end
    if economySettings().enabled and itemCount < 1 then return false, 'Nenhuma alteracao foi selecionada.' end
    local paid, methodOrError = takePayment(source, price, ('Personalizacao: %s'):format(location.label or location.kind), {
        locationId = location.id,
        storeType = location.kind,
        itemCount = itemCount,
        items = breakdownOrError,
    })
    if not paid then return false, methodOrError end
    local exportOk, saved = pcall(function()
        return exports.ob_creator:SaveAppearanceForSource(source, checkedAppearance)
    end)
    if not exportOk or saved ~= true then
        local refunded = refundPayment(source, price, methodOrError)
        if not refunded then
            print(('[ob_stores] ATENCAO: falha ao estornar %s do source %s apos erro ao salvar aparencia.'):format(
                OR.FormatMoney(price), source))
            return false, 'Falha ao salvar e estornar o pagamento. Procure a administracao.'
        end
        return false, 'Nao foi possivel salvar a aparencia. O pagamento foi estornado.'
    end
    if price <= 0 then return true, 'Aparencia salva.' end
    return true, ('Compra concluida por %s.'):format(OR.FormatMoney(price))
end)
