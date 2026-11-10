local function notify(message, notificationType)
    if notificationType ~= 'error' then return end
    if OR and OR.Notify then OR.Notify(message, 'error') end
end

local function weaponByHash(hash)
    for itemName, definition in pairs(ORInventoryWeapons.Weapons) do
        if GetHashKey(definition.weaponHash) == hash then return itemName, definition end
    end
    return nil, nil
end

local ownedWeapons = {}
local weaponAmmo = {}
local lastAmmoSync = {}
local weaponSlotByHash = {}

local function readClipAmmo(ped, weaponHash)
    local first, second = GetAmmoInClip(ped, weaponHash)
    if type(second) == 'number' then return first == true and math.max(0, math.floor(second)) or 0 end
    return type(first) == 'number' and math.max(0, math.floor(first)) or 0
end

local function readMaximumAmmo(ped, weaponHash)
    local first, second = GetMaxAmmo(ped, weaponHash)
    if type(second) == 'number' then return first == true and math.max(0, math.floor(second)) or 0 end
    return type(first) == 'number' and math.max(0, math.floor(first)) or 0
end

local function readMaximumClip(ped, weaponHash)
    local first, second = GetMaxAmmoInClip(ped, weaponHash, true)
    if type(second) == 'number' then return math.max(0, math.floor(second)) end
    return type(first) == 'number' and math.max(0, math.floor(first)) or 0
end

local function restoreWeaponAmmo(ped, weaponHash, savedAmmo)
    if not savedAmmo or not HasPedGotWeapon(ped, weaponHash, false) then return end
    local total = math.max(0, math.floor(tonumber(savedAmmo.total) or 0))
    local maximumClip = readMaximumClip(ped, weaponHash)
    local clip = math.max(0, math.floor(tonumber(savedAmmo.clip) or 0))
    if maximumClip > 0 then clip = math.min(clip, maximumClip) end
    clip = math.min(clip, total)

    -- SetAmmoInClip pode alterar a contagem real ao reduzir um pente que o GTA
    -- completou durante a troca. Aplicar o total por ultimo devolve essa bala
    -- para a reserva e preserva exatamente total + estado parcial do pente.
    SetAmmoInClip(ped, weaponHash, clip)
    SetPedAmmo(ped, weaponHash, total)
end

local function equipVisualWeapon(ped, itemName)
    local definition = ORInventoryWeapons.Weapons[itemName]
    if not definition then return false end
    local weaponHash = GetHashKey(definition.weaponHash)
    local savedAmmo = weaponAmmo[weaponHash]

    -- Dar novamente uma arma que o ped ja possui pode redefinir o pente em
    -- alguns builds. So criamos a arma na primeira vez e restauramos o estado
    -- salvo antes de seleciona-la.
    if not HasPedGotWeapon(ped, weaponHash, false) then
        GiveWeaponToPed(ped, weaponHash, 0, false, false)
    end
    SetCurrentPedWeapon(ped, weaponHash, true)
    -- Restaurar depois de selecionar evita que a troca transforme o pente em
    -- reserva. Nao repetimos a escrita alguns frames depois: essa segunda
    -- escrita fazia o GTA iniciar uma recarga visual a cada saque.
    if savedAmmo then restoreWeaponAmmo(ped, weaponHash, savedAmmo) end
    return true
end

local function rememberWeaponAmmo(ped, weaponHash)
    if not weaponHash or weaponHash == GetHashKey('WEAPON_UNARMED') or not HasPedGotWeapon(ped, weaponHash, false) then return end
    weaponAmmo[weaponHash] = {
        total = math.max(0, GetAmmoInPedWeapon(ped, weaponHash) or 0),
        clip = readClipAmmo(ped, weaponHash),
    }
end

local function saveWeaponAmmo(itemName, ped, weaponHash, force, snapshot)
    if not itemName or not weaponHash or not HasPedGotWeapon(ped, weaponHash, false) then return end
    local state = snapshot or {
        total = math.max(0, GetAmmoInPedWeapon(ped, weaponHash) or 0),
        clip = readClipAmmo(ped, weaponHash),
    }
    local previous = lastAmmoSync[weaponHash]
    if not force and previous and previous.total == state.total and previous.clip == state.clip then return end
    lastAmmoSync[weaponHash] = state
    TriggerServerEvent('ob_inventory:server:saveWeaponAmmo', itemName, state.total, state.clip, weaponSlotByHash[weaponHash])
end

function ORInventoryWeaponsModuleGetSelectedItem()
    return weaponByHash(GetSelectedPedWeapon(PlayerPedId()))
end

exports('GetSelectedWeaponInfo', function()
    local ped=PlayerPedId()
    local hash=GetSelectedPedWeapon(ped)
    local itemName,definition=weaponByHash(hash)
    if not itemName or not definition then return nil end
    return {itemName=itemName,slot=weaponSlotByHash[hash],ammoType=definition.ammoType,label=definition.label}
end)

RegisterNetEvent('ob_inventory:client:equipWeapon', function(itemName, slot)
    local definition = ORInventoryWeapons.Weapons[itemName]
    if not definition then return end

    local ped = PlayerPedId()
    local weaponHash = GetHashKey(definition.weaponHash)
    if tonumber(slot) and tonumber(slot) > 0 then weaponSlotByHash[weaponHash] = math.floor(tonumber(slot)) end
    if GetSelectedPedWeapon(ped) == weaponHash then
        rememberWeaponAmmo(ped, weaponHash)
        -- Usa a leitura feita antes de trocar para desarmado. Em alguns
        -- builds GetAmmoInPedWeapon pode retornar 0 no frame da troca.
        saveWeaponAmmo(itemName, ped, weaponHash, true, weaponAmmo[weaponHash])
        SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
        return
    end

    equipVisualWeapon(ped, itemName)
end)

RegisterNetEvent('ob_inventory:client:sync', function(inventory)
    local ped = PlayerPedId()
    local nextOwnedWeapons = {}
    local nextWeaponSlots = {}
    local ownedHashes = {}
    for slot, item in pairs(type(inventory) == 'table' and inventory.items or {}) do
        if item and item.type == 'weapon' and ORInventoryWeapons.Weapons[item.name] then
            nextOwnedWeapons[#nextOwnedWeapons + 1] = { slot = tonumber(slot) or 9999, itemName = item.name, expiresAt = tonumber(item.durability and item.durability.expiresAt) or 0 }
            local definition = ORInventoryWeapons.Weapons[item.name]
            local weaponHash = definition and GetHashKey(definition.weaponHash)
            if weaponHash then
                ownedHashes[weaponHash] = true
                nextWeaponSlots[weaponHash] = tonumber(slot)
            end
            local saved = item.metadata and item.metadata.weaponAmmo
            if definition and type(saved) == 'table' then
                weaponAmmo[weaponHash] = {
                    total = math.max(0, math.floor(tonumber(saved.total) or 0)),
                    clip = math.max(0, math.floor(tonumber(saved.clip) or 0)),
                }
            end
        end
    end

    -- A mochila e a autoridade. Se uma arma foi transferida, descartada ou
    -- removida pelo servidor, ela tambem precisa sair imediatamente do ped.
    -- Isso funciona inclusive dentro de veiculos e impede duas pessoas de
    -- usarem a mesma instancia depois de uma transferencia.
    for _, definition in pairs(ORInventoryWeapons.Weapons) do
        local weaponHash = GetHashKey(definition.weaponHash)
        if not ownedHashes[weaponHash] and HasPedGotWeapon(ped, weaponHash, false) then
            if GetSelectedPedWeapon(ped) == weaponHash then
                SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
            end
            RemoveWeaponFromPed(ped, weaponHash)
            weaponAmmo[weaponHash] = nil
            lastAmmoSync[weaponHash] = nil
        end
    end

    ownedWeapons = nextOwnedWeapons
    weaponSlotByHash = nextWeaponSlots
    table.sort(ownedWeapons, function(left, right) return left.slot < right.slot end)
end)

RegisterNetEvent('ob_inventory:client:clearWeapons', function()
    local ped = PlayerPedId()
    for _, definition in pairs(ORInventoryWeapons.Weapons) do
        RemoveWeaponFromPed(ped, GetHashKey(definition.weaponHash))
    end
    RemoveWeaponFromPed(ped, GetHashKey('GADGET_PARACHUTE'))
    SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
    ownedWeapons = {}
    weaponAmmo = {}
    lastAmmoSync = {}
    weaponSlotByHash = {}
end)

RegisterNetEvent('ob_inventory:client:equipParachute', function()
    local ped = PlayerPedId()
    local parachute = GetHashKey('GADGET_PARACHUTE')
    if not HasPedGotWeapon(ped, parachute, false) then
        GiveWeaponToPed(ped, parachute, 1, false, false)
    end
    -- Gadget nativo: mostra a mochila e abre com a mecanica normal do GTA.
    SetPedGadget(ped, parachute, true)
end)

RegisterNetEvent('ob_inventory:client:installWeaponComponent', function(slot, itemName, weaponItemName, componentName)
    local weapon = ORInventoryWeapons.Weapons[weaponItemName]
    if not weapon then return end

    local ped = PlayerPedId()
    local weaponHash = GetHashKey(weapon.weaponHash)
    local installed = GetSelectedPedWeapon(ped) == weaponHash and HasPedGotWeapon(ped, weaponHash, false)
    if installed then
        local componentHash = GetHashKey(componentName)
        GiveWeaponComponentToPed(ped, weaponHash, componentHash)
        installed = HasPedGotWeaponComponent(ped, weaponHash, componentHash)
    end

    if not installed then notify('O acessorio nao pode ser instalado nessa arma.', 'error') end
    TriggerServerEvent('ob_inventory:server:componentInstallResult', slot, itemName, weaponItemName, installed)
end)

RegisterNetEvent('ob_inventory:client:loadWeaponAmmo', function(slot, itemName, weaponItemName, amount, loadMaximum)
    local weapon = ORInventoryWeapons.Weapons[weaponItemName]
    if not weapon then return end

    local ped = PlayerPedId()
    local weaponHash = GetHashKey(weapon.weaponHash)
    local loadedAmount = 0
    local finalTotal, finalClip = 0, 0
    if GetSelectedPedWeapon(ped) == weaponHash and HasPedGotWeapon(ped, weaponHash, false) then
        local beforeTotal = math.max(0, GetAmmoInPedWeapon(ped, weaponHash) or 0)
        local beforeClip = readClipAmmo(ped, weaponHash)
        local requested = math.max(1, math.floor(tonumber(amount) or 0))
        local maximum = readMaximumAmmo(ped, weaponHash)
        if maximum > 0 then requested = math.min(requested, math.max(0, maximum - beforeTotal)) end

        if requested > 0 then
            -- A munição total inclui o pente. Primeiro definimos o total e,
            -- em seguida, ajustamos o pente para evitar que o GTA recarregue
            -- cada bala como se todas fossem reserva.
            local maximumClip = readMaximumClip(ped, weaponHash)
            local newClip = maximumClip > 0 and math.min(maximumClip, beforeClip + requested) or beforeClip
            if maximumClip > 0 then SetAmmoInClip(ped, weaponHash, newClip) end
            SetPedAmmo(ped, weaponHash, beforeTotal + requested)

            local afterTotal = math.max(0, GetAmmoInPedWeapon(ped, weaponHash) or 0)
            loadedAmount = math.max(0, math.min(requested, afterTotal - beforeTotal))
        end
        finalTotal = math.max(0, GetAmmoInPedWeapon(ped, weaponHash) or 0)
        finalClip = math.min(finalTotal, readClipAmmo(ped, weaponHash))
        weaponAmmo[weaponHash] = { total = finalTotal, clip = finalClip }
    end

    if loadedAmount < 1 then notify('A arma ja esta cheia ou nao pode receber essa municao.', 'error') end
    TriggerServerEvent('ob_inventory:server:ammoLoadResult', slot, itemName, weaponItemName, loadedAmount, finalTotal, finalClip)
end)

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local currentHash = GetSelectedPedWeapon(ped)
        local currentItem = weaponByHash(currentHash)
        local currentEntry
        for _, weapon in ipairs(ownedWeapons) do
            if weapon.itemName == currentItem then currentEntry = weapon break end
        end

        local now = GetCloudTimeAsInt()
        if currentItem then
            rememberWeaponAmmo(ped, currentHash)
        end

        if currentItem and currentEntry and currentEntry.expiresAt > 0 and now >= currentEntry.expiresAt then
            RemoveWeaponFromPed(ped, currentHash)
            SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
            weaponAmmo[currentHash] = nil
            notify('Essa arma venceu e nao pode mais ser usada.', 'error')
            Wait(500)
        end
        Wait(150)
    end
end)

-- Salva a municao real de forma periodica. Isso cobre tiros, recargas e
-- reinicios da base sem depender da arma continuar equipada na proxima vez.
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local itemName, definition = weaponByHash(GetSelectedPedWeapon(ped))
        if itemName and definition then
            saveWeaponAmmo(itemName, ped, GetHashKey(definition.weaponHash), false)
            Wait(1000)
        else
            Wait(500)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    local ped = PlayerPedId()
    local itemName, definition = weaponByHash(GetSelectedPedWeapon(ped))
    if itemName and definition then saveWeaponAmmo(itemName, ped, GetHashKey(definition.weaponHash), true) end
end)

-- Roda, scroll e teclas numericas sao bloqueados uma unica vez pelo ob_core.
-- Este modulo conserva somente a selecao autorizada pelo inventario.
