ORInventoryWeaponsModule = ORInventoryWeaponsModule or {}

local pendingComponents = {}
local pendingAmmo = {}

local function validSource(playerSource)
    playerSource = tonumber(playerSource)
    return playerSource and playerSource > 0 and GetPlayerName(playerSource) and playerSource or nil
end

function ORInventoryWeaponsModule.UseWeapon(playerSource, itemName, activeWeaponItem, slot)
    local weapon = ORInventoryWeapons.Weapons[itemName]
    if not weapon then return false, 'Arma invalida.' end
    if activeWeaponItem and activeWeaponItem ~= itemName then
        return false, 'Guarde a arma atual antes de equipar outra.'
    end

    TriggerClientEvent('ob_inventory:client:equipWeapon', playerSource, itemName, math.floor(tonumber(slot) or 0))
    return true, ('%s equipada.'):format(weapon.label), false
end

function ORInventoryWeaponsModule.BeginComponentInstall(playerSource, inventory, slot, itemName, weaponItemName)
    local component = ORInventoryWeapons.Components[itemName]
    local weapon = ORInventoryWeapons.Weapons[weaponItemName]
    if not component then return false, 'Acessorio invalido.' end
    if not weapon or not inventory.items[slot] then
        return false, 'Equipe uma arma compativel antes de usar esse acessorio.'
    end

    local componentHash = weapon.components[component.key]
    if type(componentHash) ~= 'string' or componentHash == '' then
        return false, ('%s nao e compativel com %s.'):format(component.label, weapon.label)
    end

    local activeWeaponInInventory = false
    for _, item in pairs(inventory.items) do
        if item.name == weaponItemName and item.amount > 0 then
            activeWeaponInInventory = true
            break
        end
    end
    if not activeWeaponInInventory then return false, 'Essa arma nao esta no seu inventario.' end

    pendingComponents[playerSource] = {
        slot = slot,
        itemName = itemName,
        weaponItemName = weaponItemName,
        componentHash = componentHash,
        expiresAt = GetGameTimer() + 8000,
    }
    TriggerClientEvent('ob_inventory:client:installWeaponComponent', playerSource, slot, itemName, weaponItemName, componentHash)
    return true, ('Instalando %s em %s.'):format(component.label, weapon.label), false
end

function ORInventoryWeaponsModule.TakePendingComponent(playerSource, slot, itemName, weaponItemName, installed)
    playerSource = validSource(playerSource)
    local pending = playerSource and pendingComponents[playerSource] or nil
    if not pending then return nil, 'Nenhuma instalacao pendente.' end
    pendingComponents[playerSource] = nil

    if pending.expiresAt < GetGameTimer() then return nil, 'A instalacao expirou.' end
    if pending.slot ~= math.floor(tonumber(slot) or 0) or pending.itemName ~= itemName or pending.weaponItemName ~= weaponItemName then
        return nil, 'Instalacao invalida.'
    end
    if installed ~= true then return nil, 'O acessorio nao pode ser instalado nessa arma.' end
    return pending
end

function ORInventoryWeaponsModule.BeginAmmoLoad(playerSource, inventory, slot, itemName, weaponItemName, requestedAmount, loadMaximum)
    local ammo = ORInventoryWeapons.Ammo[itemName]
    local weapon = ORInventoryWeapons.Weapons[weaponItemName]
    if not ammo then return false, 'Municao invalida.' end
    if not weapon then return false, 'Equipe uma arma antes de usar a municao.' end
    if weapon.ammoType == 'melee' or weapon.ammoType ~= ammo.ammoType then
        return false, ('%s nao e compativel com %s.'):format(ammo.label, weapon.label)
    end

    slot = math.floor(tonumber(slot) or 0)
    local inventoryAmmo = inventory.items[slot]
    if not inventoryAmmo or inventoryAmmo.name ~= itemName or inventoryAmmo.amount < 1 then
        return false, 'Essa municao nao esta mais no seu inventario.'
    end

    requestedAmount = math.floor(tonumber(requestedAmount) or 1)
    requestedAmount = math.max(1, math.min(requestedAmount, inventoryAmmo.amount))
    loadMaximum = loadMaximum == true
    if loadMaximum then requestedAmount = inventoryAmmo.amount end

    local activeWeaponInInventory = false
    for _, item in pairs(inventory.items) do
        if item.name == weaponItemName and item.amount > 0 then
            activeWeaponInInventory = true
            break
        end
    end
    if not activeWeaponInInventory then return false, 'Essa arma nao esta no seu inventario.' end

    pendingAmmo[playerSource] = {
        slot = slot,
        itemName = itemName,
        weaponItemName = weaponItemName,
        requestedAmount = requestedAmount,
        availableAmount = inventoryAmmo.amount,
        loadMaximum = loadMaximum,
        expiresAt = GetGameTimer() + 8000,
    }
    TriggerClientEvent('ob_inventory:client:loadWeaponAmmo', playerSource, slot, itemName, weaponItemName, requestedAmount, loadMaximum)
    return true, loadMaximum and ('Carregando o maximo de %s.'):format(ammo.label) or ('Carregando %s bala(s).'):format(requestedAmount), false
end

function ORInventoryWeaponsModule.TakePendingAmmo(playerSource, slot, itemName, weaponItemName, loadedAmount)
    playerSource = validSource(playerSource)
    local pending = playerSource and pendingAmmo[playerSource] or nil
    if not pending then return nil, nil, 'Nenhum carregamento pendente.' end
    pendingAmmo[playerSource] = nil

    if pending.expiresAt < GetGameTimer() then return nil, nil, 'O carregamento expirou.' end
    if pending.slot ~= math.floor(tonumber(slot) or 0) or pending.itemName ~= itemName or pending.weaponItemName ~= weaponItemName then
        return nil, nil, 'Carregamento invalido.'
    end
    loadedAmount = math.floor(tonumber(loadedAmount) or 0)
    local allowedAmount = pending.loadMaximum and pending.availableAmount or pending.requestedAmount
    if loadedAmount < 1 then return nil, nil, 'A arma ja esta cheia ou nao pode receber essa municao.' end
    if loadedAmount > allowedAmount then return nil, nil, 'Quantidade de municao invalida.' end
    return pending, loadedAmount
end

CreateThread(function()
    while true do
        Wait(10000)
        local now = GetGameTimer()
        for playerSource, pending in pairs(pendingComponents) do
            if pending.expiresAt <= now or not GetPlayerName(playerSource) then pendingComponents[playerSource] = nil end
        end
        for playerSource, pending in pairs(pendingAmmo) do
            if pending.expiresAt <= now or not GetPlayerName(playerSource) then pendingAmmo[playerSource] = nil end
        end
    end
end)
