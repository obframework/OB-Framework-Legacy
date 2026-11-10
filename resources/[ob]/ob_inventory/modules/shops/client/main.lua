local shopPeds = {}
local shopBlips = {}
local shopDefinitions = {}
local isShopOpen = false
local currentShopId

local function streamingSettings()
    local config = type(ORInventoryShops.Streaming) == 'table' and ORInventoryShops.Streaming or {}
    local spawnDistance = math.max(20.0, tonumber(config.SpawnDistance) or 90.0)
    local despawnDistance = math.max(spawnDistance + 10.0, tonumber(config.DespawnDistance) or 120.0)
    return spawnDistance, despawnDistance, math.max(500, math.floor(tonumber(config.UpdateInterval) or 1000))
end

-- Permite que sistemas que interagem com pedestres ignorem os vendedores
-- fixos. Sem isso, uma venda de drogas pode descongelar o NPC e fazê-lo sumir.
exports('IsServicePed', function(ped)
    if not ped or ped == 0 then return false end
    if ORInventoryShopBusinessClient and ORInventoryShopBusinessClient.IsManagerPed
        and ORInventoryShopBusinessClient.IsManagerPed(ped) then return true end
    for _, entity in pairs(shopPeds) do
        if entity == ped and DoesEntityExist(entity) then return true end
    end
    return false
end)

local function notify(message, kind)
    if kind ~= 'error' then return end
    if OR and OR.Notify then OR.Notify(message, 'error') end
end

local function request(name, ...)
    local success, payload, message = OR.Callback.awaitResource('ob_inventory', name, ...)
    if success ~= true then return nil, payload or message or 'Falha ao comunicar com a loja.' end
    return payload, message
end

local function closeShop()
    if not isShopOpen then return end
    isShopOpen = false
    currentShopId = nil
end

local function openShop(shopId)
    if isShopOpen or LocalPlayer.state['or:loaded'] ~= true or LocalPlayer.state['or:downed'] == true then return end
    CreateThread(function()
        local shop, errorMessage = request('shopOpen', shopId)
        if not shop then return notify(errorMessage, 'error') end
        currentShopId = shopId
        isShopOpen = true
        -- A loja usa exatamente a NUI do inventario: catalogo a direita,
        -- mochila a esquerda. Assim itens podem ser arrastados entre elas.
        TriggerEvent('ob_inventory:client:openShopInventory', shop)
    end)
end

local function requestModel(model)
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 8000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function createBlip(shop, group)
    if type(group) ~= 'table' or type(group.blip) ~= 'table' then return end
    local coords = shop.coords
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, group.blip.sprite or 52)
    SetBlipColour(blip, group.blip.color or 0)
    SetBlipScale(blip, group.blip.scale or 0.72)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(shop.businessName or group.label or 'Loja')
    EndTextCommandSetBlipName(blip)
    shopBlips[shop.id] = blip
end

RegisterNetEvent('ob_inventory:client:commerceStoreName', function(shopId, name)
    local blip=shopBlips[shopId];if not blip or not DoesBlipExist(blip) then return end
    BeginTextCommandSetBlipName('STRING');AddTextComponentSubstringPlayerName(tostring(name or 'Loja'));EndTextCommandSetBlipName(blip)
end)

local function registerShopTarget(shop)
    local ped = shopPeds[shop.id]
    local group = (ORInventoryShops.Groups or {})[shop.group] or {}
    if not ped or not DoesEntityExist(ped) or GetResourceState('ob_target') ~= 'started' then return end

    exports.ob_target:RegisterEntity(('ob_inventory:shop:%s'):format(shop.id), ped, {
        label = ('Abrir %s'):format(group.label or 'loja'),
        event = 'ob_inventory:client:openShop',
        distance = 2.0,
        canInteract = function(entity)
            return entity == shopPeds[shop.id]
        end,
    })
end

local function createShopPed(shop, group)
    if shopPeds[shop.id] and DoesEntityExist(shopPeds[shop.id]) then return end
    if type(group) ~= 'table' or not group.ped or type(shop.coords) ~= 'table' then return end
    local coords = shop.coords
    local model = requestModel(group.ped)
    if not model then
        print(('[ob_inventory] Modelo invalido da loja %s: %s'):format(shop.id, tostring(group.ped)))
        return
    end

    local ped = CreatePed(4, model, coords.x, coords.y, coords.z - 1.0, coords.w or 0.0, false, true)
    if ped and ped > 0 and shopDefinitions[shop.id] == shop then
        SetEntityAsMissionEntity(ped, true, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        FreezeEntityPosition(ped, true)
        SetPedCanRagdoll(ped, false)
        SetPedCanEvasiveDive(ped, false)
        shopPeds[shop.id] = ped
        registerShopTarget(shop)
    elseif ped and ped > 0 and DoesEntityExist(ped) then DeleteEntity(ped) end
    SetModelAsNoLongerNeeded(model)
end

local function removeShopPed(id)
    local ped = shopPeds[id]
    if not ped then return end
    if GetResourceState('ob_target') == 'started' then
        exports.ob_target:RemoveEntityOption(('ob_inventory:shop:%s'):format(id))
    end
    if DoesEntityExist(ped) then DeleteEntity(ped) end
    shopPeds[id] = nil
end

local function streamShopPeds()
    local origin = GetEntityCoords(PlayerPedId())
    local spawnDistance, despawnDistance = streamingSettings()

    for id, shop in pairs(shopDefinitions) do
        local coords = shop.coords
        local distance = coords and #(origin - vector3(coords.x, coords.y, coords.z)) or math.huge
        local ped = shopPeds[id]
        if ped and (not DoesEntityExist(ped) or distance > despawnDistance) then
            removeShopPed(id)
        elseif not ped and distance <= spawnDistance then
            createShopPed(shop, (ORInventoryShops.Groups or {})[shop.group])
        end
    end
end

RegisterNetEvent('ob_inventory:client:openShop', function(entity)
    for shopId, ped in pairs(shopPeds) do
        if ped == entity then
            openShop(shopId)
            return
        end
    end
end)

RegisterNUICallback('shopBuy', function(data, callback)
    callback({ ok = true })
    if not currentShopId then return end
    CreateThread(function()
        local received, message = request('shopBuy', currentShopId, data and data.item, data and data.amount, data and data.targetSlot)
        if not received then return notify(message, 'error') end
        if received.inventory then TriggerEvent('ob_inventory:client:sync', received.inventory) end
        if received.shop then TriggerEvent('ob_inventory:client:updateShopInventory', received.shop) end
        notify(message or 'Item adicionado ao inventario.', 'success')
    end)
end)

RegisterNetEvent('ob_inventory:client:inventoryClosed', function(shopId)
    if not shopId or shopId == currentShopId then closeShop() end
end)

local function clearShops()
    local ids = {}
    for id in pairs(shopPeds) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do removeShopPed(id) end
    for _, blip in pairs(shopBlips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
    shopPeds, shopBlips, shopDefinitions = {}, {}, {}
end
local pendingDefinitions
local function queueShopDefinitions(rows)
    if type(rows) ~= 'table' or type(rows.groups) ~= 'table' or type(rows.shops) ~= 'table' then
        print('[ob_inventory] Sincronizacao de lojas ignorada: definicoes incompletas.')
        return false
    end
    pendingDefinitions = rows
    return true
end
RegisterNetEvent('ob_inventory:client:shopDefinitions', queueShopDefinitions)
CreateThread(function()
    while LocalPlayer.state['or:loaded'] ~= true do Wait(500) end
    while not pendingDefinitions do
        -- worldShopDefinitions devolve o payload diretamente. O booleano de
        -- transporte do ob_lib nao faz parte dos valores retornados ao caller.
        local rows = OR.Callback.awaitResource('ob_inventory', 'worldShopDefinitions')
        if not queueShopDefinitions(rows) then Wait(1500) end
    end
    while true do
        if pendingDefinitions then
            local rows = pendingDefinitions
            pendingDefinitions = nil
            if isShopOpen then TriggerEvent('ob_inventory:client:forceClose'); closeShop() end
            clearShops()
            local groups, shops = rows.groups, rows.shops
            ORInventoryShops.Groups, ORInventoryShops.Shops = groups, shops
            for _, shop in ipairs(shops) do shopDefinitions[shop.id] = shop end
            for _, shop in ipairs(shops) do
                if pendingDefinitions then break end
                createBlip(shop, groups[shop.group])
            end
            streamShopPeds()
            CreateThread(function()
                local ok,names=OR.Callback.awaitResource('ob_inventory','commerceNames')
                if ok==true and type(names)=='table' then for id,name in pairs(names)do TriggerEvent('ob_inventory:client:commerceStoreName',id,name) end end
            end)
        end
        local _, _, interval = streamingSettings()
        streamShopPeds()
        Wait(interval)
    end
end)

-- O ped e o blip continuam existindo se apenas o ob_target for reiniciado.
-- Recriar o ped aqui causaria NPC duplicado; basta registrar a opcao de novo.
AddEventHandler('ob_target:client:ready', function()
    for _, shop in ipairs(ORInventoryShops.Shops or {}) do
        registerShopTarget(shop)
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    closeShop()
    clearShops()
end)
