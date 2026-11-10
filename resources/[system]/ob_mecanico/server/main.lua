local jackedVehicles = {}
local tyreActionLocks = {}
local validWheels = { [0]=true,[1]=true,[2]=true,[3]=true,[4]=true,[5]=true,[45]=true,[47]=true }

local function validSource(playerSource)
    playerSource = tonumber(playerSource)
    return playerSource and playerSource > 0 and GetPlayerName(playerSource) and playerSource or nil
end

local function vehicleFromNetId(netId)
    netId = math.floor(tonumber(netId) or 0)
    if netId <= 0 then return nil, nil end
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    return DoesEntityExist(vehicle) and vehicle or nil, netId
end

local function nearVehicle(playerSource, vehicle, distance)
    local ped = GetPlayerPed(tonumber(playerSource))
    if ped <= 0 or not DoesEntityExist(vehicle) then return false end
    return #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) <= (distance or 9.0)
end

local stationsById = {}
for _, station in ipairs(OBMechanicConfig.Stations or {}) do
    stationsById[tostring(station.id)] = station
end

local function stationAccess(playerSource, station)
    if not station then return false, 'Oficina invalida.' end
    if station.requirePermission ~= true then
        return true, tonumber((OBMechanicConfig.Payment or {}).PublicMarkupPercent) or 10
    end

    local permission = tostring(station.permission or station.id or ''):lower()
    if permission == '' then return false, 'A permissao desta oficina nao foi configurada.' end
    local allowed = false
    if GetResourceState('ob_org') == 'started' then
        allowed = exports.ob_org:HasPermission(playerSource, permission, station.requireDuty == true) == true
    end
    if not allowed and GetResourceState('ob_core') == 'started' then
        allowed = exports.ob_core:HasPermission(playerSource, permission) == true
    end
    return allowed, allowed and 0 or 'Voce nao tem permissao para usar esta oficina.'
end

local function nearStation(playerSource, station, distance)
    local ped = GetPlayerPed(tonumber(playerSource))
    if not ped or ped <= 0 or not station or not station.coords then return false end
    local coords = GetEntityCoords(ped)
    local point = vector3(station.coords.x, station.coords.y, station.coords.z)
    return #(coords - point) <= (distance or 10.0)
end

OR.Callback.register('stationAccess', function(playerSource, stationId)
    playerSource = validSource(playerSource)
    local station = stationsById[tostring(stationId or '')]
    if not playerSource or not station or not nearStation(playerSource, station, 8.0) then
        return false, 'Aproxime-se da oficina.'
    end
    local allowed, markupOrError = stationAccess(playerSource, station)
    if not allowed then return false, markupOrError end
    return true, { markupPercent = markupOrError, public = station.requirePermission ~= true }
end)

local function decodedProperties(raw)
    if type(raw) == 'table' then return raw end
    if type(raw) ~= 'string' or raw == '' then return {} end
    local ok, value = pcall(json.decode, raw)
    return ok and type(value) == 'table' and value or {}
end

local function indexed(container, key)
    if type(container) ~= 'table' then return nil end
    if container[key] ~= nil then return container[key] end
    return container[tostring(key)]
end

local function modValue(properties, index)
    local value = indexed(properties.mods, index)
    return type(value) == 'table' and tonumber(value.value) or tonumber(value)
end

local function toggleValue(properties, index)
    local value = indexed(properties.toggles, index)
    return type(value) == 'boolean' and value or nil
end

local function extraValue(properties, index)
    return indexed(properties.extras, index) == true
end

local function extrasChanged(oldProperties, newProperties)
    for extra = 0, 20 do
        if extraValue(oldProperties, extra) ~= extraValue(newProperties, extra) then return true end
    end
    return false
end

local function changed(oldValue, newValue)
    -- Propriedades antigas podem nao possuir campos adicionados recentemente.
    -- Nao cobre uma alteracao baseada apenas na ausencia do campo legado.
    if oldValue == nil then return false end
    if type(oldValue) == 'table' or type(newValue) == 'table' then
        if type(oldValue) ~= 'table' or type(newValue) ~= 'table' then return true end
        for key, value in pairs(oldValue) do
            local nextValue = indexed(newValue, key)
            if changed(value, nextValue) then return true end
        end
        for key, value in pairs(newValue) do
            local previous = indexed(oldValue, key)
            if previous ~= nil and changed(previous, value) then return true end
        end
        return false
    end
    return oldValue ~= newValue
end

local function neonEnabled(properties)
    local neons = type(properties.neons) == 'table' and properties.neons or {}
    for side = 0, 3 do if indexed(neons, side) == true then return true end end
    return false
end

local function optionChanged(option, oldProperties, newProperties)
    if option.type == 'mod' then
        return changed(modValue(oldProperties, option.index), modValue(newProperties, option.index))
    elseif option.type == 'toggle' then
        -- Veiculos salvos por versoes antigas podem nao possuir os toggles.
        -- A ausencia equivale ao estado nativo desativado; assim instalar turbo
        -- ou xenon pela primeira vez tambem entra no calculo da cobranca.
        local oldEnabled = toggleValue(oldProperties, option.index) == true
        local newEnabled = toggleValue(newProperties, option.index) == true
        return oldEnabled ~= newEnabled
    elseif option.type == 'color' then
        return changed(oldProperties.primary, newProperties.primary)
            or changed(oldProperties.primaryCustom, newProperties.primaryCustom)
            or changed(oldProperties.primaryCustomColor, newProperties.primaryCustomColor)
    elseif option.type == 'color2' then
        return changed(oldProperties.secondary, newProperties.secondary)
            or changed(oldProperties.secondaryCustom, newProperties.secondaryCustom)
            or changed(oldProperties.secondaryCustomColor, newProperties.secondaryCustomColor)
    elseif option.type == 'paint_type1' then
        return changed(oldProperties.paintType1, newProperties.paintType1)
    elseif option.type == 'paint_type2' then
        return changed(oldProperties.paintType2, newProperties.paintType2)
    elseif option.type == 'pearl' then
        return changed(oldProperties.pearlescent, newProperties.pearlescent)
    elseif option.type == 'wheel_color' then
        return changed(oldProperties.wheel, newProperties.wheel)
    elseif option.type == 'tint' then
        return changed(oldProperties.windowTint, newProperties.windowTint)
    elseif option.type == 'neon_toggle' then
        return neonEnabled(oldProperties) ~= neonEnabled(newProperties)
    elseif option.type == 'neon' then
        return changed(oldProperties.neonColor, newProperties.neonColor)
    elseif option.type == 'headlight_color' then
        return changed(oldProperties.xenonColor, newProperties.xenonColor)
    elseif option.type == 'extra' then
        return extraValue(oldProperties, option.index) ~= extraValue(newProperties, option.index)
    elseif option.type == 'extras' then
        -- O grupo inteiro representa uma unica compra, mesmo que selecionar
        -- uma configuracao desligue um extra antigo e ligue outro.
        return extrasChanged(oldProperties, newProperties)
    end
    return false
end

local function configuredPrice(option, selectedValue, defaultPrice)
    local fallback = math.max(0, math.floor(tonumber(option.price) or defaultPrice))
    selectedValue = tonumber(selectedValue)
    if (option.type == 'mod' or option.type == 'wheel') and selectedValue then
        if selectedValue < 0 then
            return math.max(0, math.floor(tonumber(option.originalPrice) or fallback))
        end
        local levelPrice = indexed(option.levelPrices, selectedValue + 1)
        return math.max(0, math.floor(tonumber(levelPrice) or fallback))
    elseif option.type == 'toggle' or option.type == 'neon_toggle' or option.type == 'extra' then
        local value = selectedValue == 1 and option.enabledPrice or option.disabledPrice
        return math.max(0, math.floor(tonumber(value) or fallback))
    elseif selectedValue and type(option.choicePrices) == 'table' then
        return math.max(0, math.floor(tonumber(indexed(option.choicePrices, selectedValue)) or fallback))
    end
    return fallback
end

local function selectedOptionValue(option, properties)
    if option.type == 'mod' or option.type == 'wheel' then
        return modValue(properties, option.index)
    elseif option.type == 'toggle' then
        return toggleValue(properties, option.index) == true and 1 or 0
    elseif option.type == 'neon_toggle' then
        return neonEnabled(properties) and 1 or 0
    elseif option.type == 'paint_type1' then
        return tonumber(properties.paintType1)
    elseif option.type == 'paint_type2' then
        return tonumber(properties.paintType2)
    elseif option.type == 'pearl' then
        return tonumber(properties.pearlescent)
    elseif option.type == 'wheel_color' then
        return tonumber(properties.wheel)
    elseif option.type == 'tint' then
        return tonumber(properties.windowTint)
    elseif option.type == 'headlight_color' then
        return tonumber(properties.xenonColor)
    elseif option.type == 'extra' then
        return extraValue(properties, option.index) and 1 or 0
    elseif option.type == 'extras' then
        for extra = 0, 20 do
            if extraValue(properties, extra) then return extra end
        end
        return -1
    end
    return nil
end

local function tuningPrice(station, oldRaw, newRaw, markupPercent)
    if OBMechanicConfig.TuningFree == true then return 0 end
    local oldProperties, newProperties = decodedProperties(oldRaw), decodedProperties(newRaw)
    local defaultPrice = math.max(0, math.floor(tonumber((OBMechanicConfig.Payment or {}).DefaultPrice) or 100))
    local subtotal, wheelsProcessed = 0, false
    for _, section in ipairs(OBMechanicConfig.Sections or {}) do
        if not section.category or section.category == station.category then
            for _, option in ipairs(section.options or {}) do
                local wasChanged = false
                local selectedPrice = configuredPrice(option, selectedOptionValue(option, newProperties), defaultPrice)
                if option.type == 'wheel' then
                    if not wheelsProcessed then
                        wheelsProcessed = true
                        wasChanged = changed(oldProperties.wheelType, newProperties.wheelType)
                            or changed(modValue(oldProperties, option.index), modValue(newProperties, option.index))
                        local selectedWheelType = tonumber(newProperties.wheelType)
                        for _, wheelOption in ipairs(section.options or {}) do
                            if wheelOption.type == 'wheel' and tonumber(wheelOption.wheelType) == selectedWheelType then
                                selectedPrice = configuredPrice(
                                    wheelOption, modValue(newProperties, wheelOption.index), defaultPrice)
                                break
                            end
                        end
                    end
                else
                    wasChanged = optionChanged(option, oldProperties, newProperties)
                end
                if wasChanged then subtotal = subtotal + math.max(0, math.floor(selectedPrice)) end
            end
        end
    end
    return math.floor(subtotal * (1.0 + math.max(0, tonumber(markupPercent) or 0) / 100.0) + 0.5)
end

local paidTunings, paymentSequence = {}, 0

exports('ChargeTuning', function(playerSource, stationId, vehicle, oldRaw, newRaw)
    playerSource = validSource(playerSource)
    local station = stationsById[tostring(stationId or '')]
    if not playerSource or not station or not DoesEntityExist(vehicle)
        or not nearStation(playerSource, station, 12.0) or not nearVehicle(playerSource, vehicle, 12.0) then
        return false, 'Oficina ou veiculo indisponivel.'
    end
    local allowed, markupOrError = stationAccess(playerSource, station)
    if not allowed then return false, markupOrError end
    local price = tuningPrice(station, oldRaw, newRaw, markupOrError)
    if price <= 0 then return true, nil, 0 end
    if GetResourceState('ob_inventory') ~= 'started' then return false, 'Inventario indisponivel.' end
    local account = tostring((OBMechanicConfig.Payment or {}).Account or 'money')
    local paid, paymentType, economyPayment = false, nil, nil
    local description = ('Tuning - %s'):format(station.label or station.id)
    local economyResult = OR.Economy.ChargePlayer(playerSource, price, 'mechanic_tuning', description,
        { stationId = station.id }, 'city_treasury')
    if economyResult.handled == true then
        paid = economyResult.success == true
        if paid then paymentType, economyPayment = 'economy', economyResult end
    else
        if GetResourceState('ob_bank') == 'started' then
            paid = exports.ob_bank:PayWithCard(playerSource, price, description)
            if paid then paymentType = 'bank' end
        end
    end
    if not paid and economyResult.handled ~= true then
        if (tonumber(exports.ob_inventory:GetMoney(playerSource, account)) or 0) >= price then
            paid = exports.ob_inventory:RemoveMoney(playerSource, account, price)
            if paid then paymentType = 'cash' end
        end
    end
    if not paid then
        return false, economyResult.error
            or ('Saldo do cartao e dinheiro em maos insuficientes para %s.'):format(OR.FormatMoney(price))
    end
    paymentSequence = paymentSequence + 1
    local receipt = ('%s:%s:%s'):format(playerSource, GetGameTimer(), paymentSequence)
    paidTunings[receipt] = {
        source = playerSource, account = account, amount = price, paymentType = paymentType,
        economyReceipt = economyPayment and economyPayment.receipt or nil,
        economyMethod = economyPayment and economyPayment.method or nil,
    }
    return true, receipt, price
end)

exports('FinishTuningPayment', function(playerSource, receipt, refund)
    local payment = type(receipt) == 'string' and paidTunings[receipt] or nil
    if not payment or payment.source ~= tonumber(playerSource) then return false end
    paidTunings[receipt] = nil
    if refund == true and payment.amount > 0 then
        if payment.paymentType == 'economy' and payment.economyReceipt then
            local result = OR.Economy.RefundCharge(payment.source, payment.economyReceipt, 'Estorno de tuning')
            if result.handled == true then return result.success == true end
            payment.paymentType = payment.economyMethod == 'card' and 'bank' or 'cash'
        end
        if payment.paymentType == 'bank' and GetResourceState('ob_bank') == 'started' then
            return exports.ob_bank:RefundToBank(payment.source, payment.amount, 'Estorno de tuning') == true
        end
        if GetResourceState('ob_inventory') == 'started' then
            return exports.ob_inventory:AddMoney(payment.source, payment.account, payment.amount) == true
        end
        return false
    end
    return true
end)

local function point(raw)
    if type(raw) ~= 'table' then return nil end
    local x, y, z = tonumber(raw.x), tonumber(raw.y), tonumber(raw.z)
    if not x or not y or not z then return nil end
    return { x = x, y = y, z = z }
end

local function rotation(raw)
    local value = point(raw)
    return value and { x = value.x, y = value.y, z = value.z } or nil
end

local function sanitizeJackState(netId, raw, playerSource)
    if type(raw) ~= 'table' then return nil end
    local coords, originalRotation = point(raw.coords), rotation(raw.rotation)
    local prop, liftedCoords, liftedRotation = point(raw.prop), point(raw.liftedCoords), rotation(raw.liftedRotation)
    if not coords or not originalRotation or not prop or not liftedCoords or not liftedRotation then return nil end
    local side = raw.side == 'right' and 'right' or raw.side == 'left' and 'left' or nil
    if not side then return nil end
    return {
        netId = netId,
        owner = playerSource,
        side = side,
        coords = coords,
        rotation = originalRotation,
        prop = prop,
        propHeading = tonumber(raw.propHeading) or 0.0,
        liftedCoords = liftedCoords,
        liftedRotation = liftedRotation,
        createdAt = os.time(),
    }
end

RegisterNetEvent('ob_mecanico:server:setJackState', function(netId, rawState)
    local playerSource = validSource(source)
    local vehicle, normalizedNetId = vehicleFromNetId(netId)
    if not playerSource or not vehicle or not nearVehicle(playerSource, vehicle, 9.0) then return end
    if not OR.Security.rateLimit(playerSource, 'mechanic:set_jack', 2, 10000) then return end
    if GetResourceState('ob_inventory') ~= 'started' or (exports.ob_inventory:GetItemCount(playerSource, 'hydraulic_jack') or 0) < 1 then return end
    if jackedVehicles[normalizedNetId] or type(Entity(vehicle).state['ob:jack_state']) == 'table' then return end

    local state = sanitizeJackState(normalizedNetId, rawState, playerSource)
    if not state then return end
    jackedVehicles[normalizedNetId] = state
    Entity(vehicle).state:set('ob:jack_state', state, true)
    TriggerClientEvent('ob_mecanico:client:syncJack', -1, normalizedNetId, state)
end)

RegisterNetEvent('ob_mecanico:server:removeJackState', function(netId)
    local playerSource = validSource(source)
    local vehicle, normalizedNetId = vehicleFromNetId(netId)
    local state = normalizedNetId and (jackedVehicles[normalizedNetId] or (vehicle and Entity(vehicle).state['ob:jack_state'])) or nil
    if not playerSource or not vehicle or type(state) ~= 'table' or not nearVehicle(playerSource, vehicle, 10.0) then return end
    if not OR.Security.rateLimit(playerSource, 'mechanic:remove_jack', 3, 10000) then return end

    jackedVehicles[normalizedNetId] = nil
    Entity(vehicle).state:set('ob:jack_state', nil, true)
    TriggerClientEvent('ob_mecanico:client:removeJack', -1, normalizedNetId, state)
end)

local function updateTyreState(playerSource, netId, stateKey, wheel, value)
    local vehicle, normalizedNetId = vehicleFromNetId(netId)
    wheel = math.floor(tonumber(wheel) or -1)
    if not vehicle or not validWheels[wheel] or not nearVehicle(playerSource, vehicle, 10.0) then return end
    local current = Entity(vehicle).state[stateKey]
    local snapshot = {}
    for index, state in pairs(type(current) == 'table' and current or {}) do snapshot[index] = state end
    snapshot[tostring(wheel)] = value
    if value == nil then snapshot[tostring(wheel)] = nil end
    Entity(vehicle).state:set(stateKey, next(snapshot) and snapshot or nil, true)
    return vehicle, normalizedNetId, snapshot
end

-- A alteracao de pneu e inventario acontece em uma unica operacao no servidor.
-- O cliente nao pode mais chamar um evento separado para criar/devolver itens.
OR.Callback.register('completeTyreAction', function(playerSource, netId, wheel, action, requestedItem)
    playerSource = validSource(playerSource)
    local vehicle, normalizedNetId = vehicleFromNetId(netId)
    wheel = math.floor(tonumber(wheel) or -1)
    action = type(action) == 'string' and action:lower() or ''
    if not playerSource or not vehicle or not validWheels[wheel] or not nearVehicle(playerSource, vehicle, 7.0) then
        return false, 'Veiculo ou roda indisponivel.'
    end
    if not OR.Security.rateLimit(playerSource, 'mechanic:tyre_action', 1, 3500) then
        return false, 'Aguarde antes de mexer em outro pneu.'
    end
    local jackState = jackedVehicles[normalizedNetId] or Entity(vehicle).state['ob:jack_state']
    if type(jackState) ~= 'table' then return false, 'Instale o macaco antes de trabalhar no pneu.' end
    if GetResourceState('ob_inventory') ~= 'started' then return false, 'Inventario indisponivel.' end
    if (exports.ob_inventory:GetItemCount(playerSource, 'weapon_wrench') or 0) < 1 then
        return false, 'Voce precisa da chave inglesa.'
    end

    -- Dois jogadores nao podem concluir a mesma roda ao mesmo tempo. Sem o
    -- bloqueio ambos poderiam ler "instalada" antes do primeiro gravar e
    -- receber dois itens pelo mesmo pneu.
    local lockKey = ('%s:%s'):format(normalizedNetId, wheel)
    local now = GetGameTimer()
    if (tyreActionLocks[lockKey] or 0) > now then return false, 'Essa roda ja esta sendo alterada.' end
    tyreActionLocks[lockKey] = now + 10000
    local function finish(...)
        tyreActionLocks[lockKey] = nil
        return ...
    end

    local removed = Entity(vehicle).state['ob:removed_tyres']
    local types = Entity(vehicle).state['ob:tyre_types']
    local isRemoved = type(removed) == 'table' and removed[tostring(wheel)] == true

    if action == 'remove' then
        if isRemoved then return finish(false, 'Esse pneu ja foi removido.') end
        local itemName = type(types) == 'table' and types[tostring(wheel)] == 'tyre_armored' and 'tyre_armored' or 'tyre_normal'
        local added, addError = exports.ob_inventory:AddItem(playerSource, itemName, 1)
        if not added then return finish(false, addError or 'Sem espaco para guardar o pneu.') end
        local updatedVehicle, _, removedSnapshot = updateTyreState(playerSource, normalizedNetId, 'ob:removed_tyres', wheel, true)
        if not updatedVehicle then
            exports.ob_inventory:RemoveItem(playerSource, itemName, 1)
            return finish(false, 'A roda deixou de estar disponivel; o item foi revertido.')
        end
        updateTyreState(playerSource, normalizedNetId, 'ob:tyre_types', wheel, nil)
        TriggerClientEvent('ob_mecanico:client:syncRemovedTyres', -1, normalizedNetId, removedSnapshot or {})
        return finish(true, 'Pneu removido e guardado na mochila.', itemName)
    end

    if action == 'install' then
        local itemName = requestedItem == 'tyre_armored' and 'tyre_armored' or requestedItem == 'tyre_normal' and 'tyre_normal' or nil
        if not itemName then return finish(false, 'Pneu invalido.') end
        local removedItem, removeError = exports.ob_inventory:RemoveItem(playerSource, itemName, 1)
        if not removedItem then return finish(false, removeError or 'Voce nao possui esse pneu.') end
        local updatedVehicle, _, removedSnapshot = updateTyreState(playerSource, normalizedNetId, 'ob:removed_tyres', wheel, nil)
        if not updatedVehicle then
            exports.ob_inventory:AddItem(playerSource, itemName, 1)
            return finish(false, 'A roda deixou de estar disponivel; o pneu foi devolvido.')
        end
        updateTyreState(playerSource, normalizedNetId, 'ob:tyre_types', wheel, itemName == 'tyre_armored' and itemName or nil)
        TriggerClientEvent('ob_mecanico:client:syncRemovedTyres', -1, normalizedNetId, removedSnapshot or {})
        return finish(true, 'Pneu trocado.', itemName)
    end

    return finish(false, 'Acao de pneu invalida.')
end)

AddEventHandler('playerDropped', function()
    local playerSource = tonumber(source)
    for netId, state in pairs(jackedVehicles) do
        if state.owner == playerSource then
            local vehicle = NetworkGetEntityFromNetworkId(netId)
            if DoesEntityExist(vehicle) then Entity(vehicle).state:set('ob:jack_state', nil, true) end
            TriggerClientEvent('ob_mecanico:client:removeJack', -1, netId, state)
            jackedVehicles[netId] = nil
        end
    end
end)
