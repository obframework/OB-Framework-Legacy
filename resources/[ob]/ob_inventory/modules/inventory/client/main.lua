local isOpen = false
local currentInventory
local currentGround
local currentShop
local currentOther
local groundDrops = {}
local closestDrop
local closeInventory
local useCooldowns = {}
local itemProgressActive = false
local itemProp, itemPropModel
local itemPropGeneration = 0

local function nativeTrue(value)
    return value == true or value == 1
end

local function clearItemProp()
    if itemProp and nativeTrue(DoesEntityExist(itemProp)) and GetEntityModel(itemProp) == itemPropModel then
        exports.ob_core:DeleteNetworkedObject(itemProp)
    end
    itemProp, itemPropModel = nil, nil
end

local function createItemProp(config)
    if type(config) ~= 'table' then return true end
    local model = type(config.model) == 'string' and joaat(config.model) or config.model
    if not model or not nativeTrue(IsModelValid(model)) or not nativeTrue(IsModelInCdimage(model)) then
        return false, 'Prop da comida indisponivel. Verifique o recurso ob_foodprops.'
    end
    local generation = itemPropGeneration
    RequestModel(model)
    local deadline = GetGameTimer() + 5000
    while not nativeTrue(HasModelLoaded(model)) and GetGameTimer() < deadline and generation == itemPropGeneration do Wait(0) end
    if generation ~= itemPropGeneration or not nativeTrue(HasModelLoaded(model)) then
        SetModelAsNoLongerNeeded(model)
        return false, 'Nao foi possivel carregar o prop da comida.'
    end
    local ped = PlayerPedId()
    if nativeTrue(IsEntityDead(ped)) or LocalPlayer.state['or:downed'] == true then
        SetModelAsNoLongerNeeded(model)
        return false, 'Voce nao pode comer agora.'
    end
    local coords = GetEntityCoords(ped)
    itemProp = exports.ob_core:CreateNetworkedObject(model, coords, false)
    itemPropModel = model
    if not itemProp or itemProp == 0 then
        itemProp, itemPropModel = nil, nil
        SetModelAsNoLongerNeeded(model)
        return false, 'Nao foi possivel criar o prop da comida.'
    end
    -- O handle pode chegar antes de o objeto de rede estar pronto para anexar.
    deadline = GetGameTimer() + 2000
    while generation == itemPropGeneration and itemProp and not nativeTrue(DoesEntityExist(itemProp))
        and GetGameTimer() < deadline do Wait(0) end
    SetModelAsNoLongerNeeded(model)
    if generation ~= itemPropGeneration or not itemProp or not nativeTrue(DoesEntityExist(itemProp)) then
        return false, 'O objeto da comida nao ficou disponivel. Tente novamente.'
    end
    SetEntityAsMissionEntity(itemProp, true, true)
    SetEntityCollision(itemProp, false, false)
    SetEntityVisible(itemProp, true, false)
    ResetEntityAlpha(itemProp)
    local position, rotation = config.position or {}, config.rotation or {}
    AttachEntityToEntity(itemProp, ped, GetPedBoneIndex(ped, config.bone or 18905),
        position.x or 0.0, position.y or 0.0, position.z or 0.0,
        rotation.x or 0.0, rotation.y or 0.0, rotation.z or 0.0,
        false, false, false, true, 2, true)
    if not nativeTrue(IsEntityAttachedToEntity(itemProp, ped)) then
        return false, 'Nao foi possivel colocar a comida na mao.'
    end
    return true
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() and resource ~= 'ob_foodprops' then return end
    itemPropGeneration = itemPropGeneration + 1
    clearItemProp()
end)

local function isRestrained()
    return LocalPlayer.state['or:restrained'] == true
        or LocalPlayer.state['ob:restrained'] == true
        or LocalPlayer.state['ob:takedown'] == true
end

local function notify(message, kind)
    -- Operacoes normais ja possuem retorno visual na propria NUI. Mantemos
    -- notificacoes externas somente quando o jogador precisa corrigir algo.
    if kind ~= 'error' then return end
    if OR and OR.Notify then OR.Notify(message, 'error') end
end

local function request(name, ...)
    local success, payload, message = OR.Callback.awaitResource('ob_inventory', name, ...)
    if success ~= true then return nil, payload or message or 'Falha ao comunicar com o inventario.' end
    return payload, message
end

local function sendInventory()
    SendNUIMessage({
        action = 'setData',
        inventory = currentInventory,
        ground = currentGround,
        shop = currentShop,
        other = currentOther,
        imageConfig = ORInventoryConfig.ItemImages,
    })
end

local function activeWeaponItem()
    if not ORInventoryWeaponsModuleGetSelectedItem then return nil end
    local itemName = ORInventoryWeaponsModuleGetSelectedItem()
    return itemName
end

local function runItemProgress(item)
    if type(item) ~= 'table' then return true end
    -- O visual vem do cadastro local, mesmo se o cache recebido do servidor
    -- ainda nao contiver use.prop apos uma atualizacao do catalogo.
    local definition = ORInventoryItems and ORInventoryItems[item.name]
    local use = definition and definition.use or item.use
    if type(use) ~= 'table' then return true end
    if itemProgressActive then return false end
    if GetResourceState('ob_core') ~= 'started' then return false end
    itemProgressActive = true
    local ok, completed, errorMessage = pcall(function()
        local spawned, propError = createItemProp(use.prop)
        if not spawned then
            print(('[ob_inventory] Visual de %s (modelo %s): %s'):format(
                tostring(item.name), tostring(use.prop and use.prop.model), tostring(propError)))
            return false, propError
        end
        return exports.ob_core:Progress(use)
    end)
    clearItemProp()
    itemProgressActive = false
    if not ok then
        print('[ob_inventory] Falha no uso visual do item: ' .. tostring(completed))
        notify('Nao foi possivel usar o item.', 'error')
        return false
    end
    if completed ~= true then
        notify(errorMessage or 'Acao cancelada.', 'error')
        return false
    end
    return true
end

local function closestPlayerSource()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local closestSource, closestDistance
    for _, playerIndex in ipairs(GetActivePlayers()) do
        if playerIndex ~= PlayerId() then
            local targetPed = GetPlayerPed(playerIndex)
            if targetPed and targetPed > 0 then
                local distance = #(GetEntityCoords(targetPed) - playerCoords)
                if distance <= ORInventoryConfig.Transfer.Distance and (not closestDistance or distance < closestDistance) then
                    closestSource, closestDistance = GetPlayerServerId(playerIndex), distance
                end
            end
        end
    end
    return closestSource
end

local function useInventorySlot(slot, amount, loadMaximum)
    slot = tonumber(slot)
    if not slot then return end
    local now = GetGameTimer()
    if (useCooldowns[slot] or 0) > now then return end
    -- Key mappings do FiveM podem repetir enquanto a tecla esta pressionada.
    -- Evita varios callbacks/equipamentos para o mesmo slot em sequencia.
    useCooldowns[slot] = now + 550
    CreateThread(function()
        local item = currentInventory and currentInventory.items and (currentInventory.items[tostring(slot)] or currentInventory.items[slot])
        if item and item.type == 'armor' and GetPedArmour(PlayerPedId()) >= 100 then
            return notify('Seu colete ja esta com 100% de protecao.', 'error')
        end
        if item and (item.type == 'mechanic_repair' or item.type == 'mechanic_tyre') then
            if GetResourceState('ob_mecanico') ~= 'started' or not exports.ob_mecanico:CanUseRepairKit() then
                return notify('Aproxime-se de um veiculo para usar este kit.', 'error')
            end
        end
        -- Esses itens ja tem sua propria sequencia no ob_mecanico. A barra
        -- generica daqui causava 6-8 segundos de espera antes de o minigame/
        -- target mecanico sequer receber o evento.
        local mechanicAction = item and (item.type == 'mechanic_repair' or item.type == 'mechanic_tyre' or item.type == 'mechanic_jack')
        local restraintAction = item and (item.type == 'police_restraint' or item.type == 'police_restraint_key')
        local blackoutAction = item and item.type == 'blackout_control'
        local medicalAction = item and (item.type == 'medical_supply' or item.type == 'medical_stretcher' or item.name == 'emstablet')
        local documentAction = item and item.type == 'document'
        local forensicAction = item and (item.type == 'forensic_kit' or item.type == 'forensic_field_kit' or item.type == 'forensic_magnifier')
        local armorAction = item and item.type == 'armor'
        if item and (item.type == 'lockpick' or mechanicAction or restraintAction or blackoutAction or medicalAction or documentAction or forensicAction or armorAction or item.type == 'consumable' or item.type == 'drug') and isOpen then
            closeInventory()
        end
        if not mechanicAction and not blackoutAction and not runItemProgress(item) then return end
        local response, message = request('use', slot, activeWeaponItem(), amount, loadMaximum == true)
        if not response then return notify(message, 'error') end
        currentInventory = response.inventory
        if isOpen then sendInventory() end
        notify(message or 'Item utilizado.', 'success')
    end)
end

closeInventory = function()
    if not isOpen then return end
    local closedShopId = currentShop and currentShop.id or nil
    isOpen = false
    currentGround = nil
    currentShop = nil
    currentOther = nil
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
    TriggerEvent('ob_inventory:client:inventoryClosed', closedShopId)
end

local function showInventory(inventory, ground, shop, other)
    currentInventory = inventory
    currentGround = ground
    currentShop = shop
    currentOther = other
    isOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({
        action = 'open',
        inventory = currentInventory,
        ground = currentGround,
        shop = currentShop,
        other = currentOther,
        imageConfig = ORInventoryConfig.ItemImages,
    })
end

local function openInventory(dropId)
    if isOpen or LocalPlayer.state['or:loaded'] ~= true or LocalPlayer.state['or:downed'] == true or isRestrained() then return end

    if not dropId then
        local drop, distance = closestDrop()
        if drop and distance and distance <= ORInventoryConfig.Ground.InteractDistance then dropId = drop.id end
    end

    CreateThread(function()
        local response, errorMessage = request('open', dropId)
        if not response then return notify(errorMessage, 'error') end
        groundDrops = type(response.drops) == 'table' and response.drops or groundDrops
        showInventory(response.inventory, response.ground, nil)
    end)
end

closestDrop = function()
    local playerCoords = GetEntityCoords(PlayerPedId())
    local closest, closestDistance
    for _, drop in pairs(groundDrops) do
        local coords = vector3(drop.coords.x, drop.coords.y, drop.coords.z)
        local distance = #(playerCoords - coords)
        if distance <= ORInventoryConfig.Ground.DisplayDistance and (not closestDistance or distance < closestDistance) then
            closest, closestDistance = drop, distance
        end
    end
    return closest, closestDistance
end

RegisterCommand('+ob_inventory_apostrophe', function()
    if not isOpen then openInventory() end
end, false)

RegisterCommand('-ob_inventory_apostrophe', function() end, false)
RegisterKeyMapping('+ob_inventory_apostrophe', 'Abrir inventario da OB Framework', 'keyboard', ORInventoryConfig.OpenControl)

-- 1 a 5 usam diretamente os slots 1 a 5 da mochila; nao existe uma segunda barra.
for index = 1, 5 do
    -- Mantem o mesmo nome tecnico do atalho anterior para respeitar qualquer
    -- remapeamento que o jogador ja tenha salvo nas configuracoes do FiveM.
    RegisterCommand(('+ob_inventory_quick_%s'):format(index), function()
        if isOpen or LocalPlayer.state['or:loaded'] ~= true or LocalPlayer.state['or:downed'] == true or isRestrained() then return end
        useInventorySlot(index, 1, IsControlPressed(0, 36))
    end, false)
    RegisterCommand(('-ob_inventory_quick_%s'):format(index), function() end, false)
    RegisterKeyMapping(('+ob_inventory_quick_%s'):format(index), ('Usar slot %s do inventario OB'):format(index), 'keyboard', tostring(index))
end

RegisterNetEvent('ob_inventory:client:openShopInventory', function(shop)
    if isOpen or type(shop) ~= 'table' or LocalPlayer.state['or:downed'] == true or isRestrained() then return end
    CreateThread(function()
        local response, errorMessage = request('open')
        if not response then return notify(errorMessage, 'error') end
        showInventory(response.inventory, nil, shop)
    end)
end)

-- Abre a mesma interface de duas mochilas usada pelo inventario normal. O
-- servidor do recurso solicitante continua sendo a autoridade sobre qualquer
-- transferencia; o modo readonly nao possui nenhuma acao de retirada.
RegisterNetEvent('ob_inventory:client:openOtherInventory', function(data)
    if isOpen or type(data) ~= 'table' or type(data.inventory) ~= 'table'
        or LocalPlayer.state['or:loaded'] ~= true
        or LocalPlayer.state['or:downed'] == true or isRestrained() then return end

    CreateThread(function()
        local response, errorMessage = request('open')
        if not response then return notify(errorMessage, 'error') end
        local mode = data.mode == 'police' and 'police' or 'readonly'
        local durationSeconds = math.max(15, tonumber(data.durationSeconds) or 120)
        showInventory(response.inventory, nil, nil, {
            mode = mode,
            targetSource = tonumber(data.targetSource),
            label = tostring(data.label or 'Outra pessoa'),
            userId = tonumber(data.userId),
            distance = math.max(1.0, tonumber(data.distance) or 3.0),
            requiresHandsUp = data.requiresHandsUp == true,
            expiresAt = mode == 'readonly' and (GetGameTimer() + (durationSeconds * 1000)) or nil,
            inventory = data.inventory,
        })
    end)
end)

RegisterNetEvent('ob_inventory:client:openContainer', function(data)
    if isOpen or type(data) ~= 'table' or type(data.inventory) ~= 'table'
        or LocalPlayer.state['or:loaded'] ~= true
        or LocalPlayer.state['or:downed'] == true or isRestrained() then return end
    CreateThread(function()
        local response, errorMessage = request('open')
        if not response then return notify(errorMessage, 'error') end
        if isOpen then return end
        local mode = data.mode == 'discard' and 'discard' or 'container'
        showInventory(response.inventory, nil, nil, {
            mode = mode,
            id = tonumber(data.id),
            label = tostring(data.label or (mode == 'discard' and 'Descarte' or 'Bau')),
            coords = type(data.coords) == 'table' and data.coords or nil,
            distance = math.max(1.0, tonumber(data.distance) or 2.0),
            inventory = data.inventory,
        })
    end)
end)

RegisterNetEvent('ob_inventory:client:sync', function(inventory)
    currentInventory = inventory
    if isOpen then sendInventory() end
end)

RegisterNetEvent('ob_inventory:client:applyArmour', function(value)
    local ped = PlayerPedId()
    if not ped or ped == 0 or IsEntityDead(ped) then return end
    SetPedArmour(ped, math.max(0, math.min(100, math.floor(tonumber(value) or 0))))
end)

RegisterNetEvent('ob_inventory:client:updateShopInventory', function(shop)
    if type(shop) ~= 'table' or not isOpen or not currentShop then return end
    currentShop = shop
    sendInventory()
end)

RegisterNetEvent('ob_inventory:client:itemChanges', function(changes)
    if type(changes) ~= 'table' then return end
    SendNUIMessage({ action = 'itemChanges', changes = changes, imageConfig = ORInventoryConfig.ItemImages })
end)

RegisterNetEvent('ob_inventory:client:forceClose', closeInventory)

RegisterNetEvent('ob_inventory:client:groundDrops', function(drops)
    groundDrops = type(drops) == 'table' and drops or {}
    if isOpen and not currentShop and not currentOther then
        local nearest, distance = closestDrop()
        currentGround = nearest and distance and distance <= ORInventoryConfig.Ground.InteractDistance and nearest or nil
        sendInventory()
    end
end)

-- Nao abre a NUI apos um restart. Apenas recompõe o cache do cliente para que
-- o proximo apostrofo e os marcadores de itens funcionem normalmente.
local function hydrateClientInventory()
    if LocalPlayer.state['or:loaded'] ~= true then return end

    for _ = 1, 5 do
        local response = request('open')
        if response and response.inventory then
            currentInventory = response.inventory
            groundDrops = type(response.drops) == 'table' and response.drops or groundDrops
            return
        end
        Wait(750)
    end
end

local function preloadCatalogIcons()
    local names = {}
    for itemName in pairs(ORInventoryItems or {}) do names[#names + 1] = itemName end
    table.sort(names)
    SendNUIMessage({ action = 'preloadIcons', imageConfig = ORInventoryConfig.ItemImages, items = names })
end

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
    CreateThread(function()
        Wait(600)
        preloadCatalogIcons()
        hydrateClientInventory()
    end)
end)

RegisterNUICallback('close', function(_, callback)
    closeInventory()
    callback({ ok = true })
end)

RegisterNUICallback('use', function(data, callback)
    callback({ ok = true })
    useInventorySlot(data and data.slot, data and data.amount, data and data.loadMaximum == true)
end)

RegisterNUICallback('drop', function(data, callback)
    callback({ ok = true })
    CreateThread(function()
        local response, message = request('drop', data and data.slot, data and data.amount, activeWeaponItem())
        if not response then return notify(message, 'error') end
        currentInventory, currentGround = response.inventory, response.ground
        if isOpen then sendInventory() end
        notify(message or 'Item jogado no chao.', 'success')
    end)
end)

RegisterNUICallback('move', function(data, callback)
    callback({ ok = true })
    CreateThread(function()
        local response, message = request('move', data and data.fromSlot, data and data.toSlot)
        if not response then return notify(message, 'error') end
        currentInventory = response.inventory
        if isOpen then sendInventory() end
    end)
end)

RegisterNUICallback('transfer', function(data, callback)
    callback({ ok = true })
    CreateThread(function()
        local targetSource = closestPlayerSource()
        if not targetSource then return notify('Nenhum jogador proximo para receber o item.', 'error') end
        local response, message = request('transfer', targetSource, data and data.slot, data and data.amount, activeWeaponItem())
        if not response then return notify(message, 'error') end
        currentInventory = response.inventory
        if isOpen then sendInventory() end
        notify(message or 'Item enviado.', 'success')
    end)
end)

RegisterNUICallback('pickup', function(data, callback)
    callback({ ok = true })
    CreateThread(function()
        local response, message = request('pickup', currentGround and currentGround.id or nil, data and data.index, data and data.amount, data and data.targetSlot)
        if not response then return notify(message, 'error') end
        currentInventory, currentGround = response.inventory, response.ground
        if isOpen then sendInventory() end
        notify(message or 'Item recolhido.', 'success')
    end)
end)

RegisterNUICallback('otherTake', function(data, callback)
    callback({ ok = true })
    if not isOpen or not currentOther or currentOther.mode ~= 'police'
        or not currentOther.targetSource then return end

    local targetAtRequest = currentOther.targetSource
    CreateThread(function()
        local payload, message = OR.Callback.awaitResource(
            'ob_police', 'seize', targetAtRequest,
            data and data.slot, data and data.amount, data and data.targetSlot
        )
        if not payload then return notify(message or 'Nao foi possivel apreender.', 'error') end
        if not isOpen or not currentOther or currentOther.targetSource ~= targetAtRequest then return end
        currentInventory = payload.officerInventory or currentInventory
        currentOther.inventory = payload.inventory or currentOther.inventory
        sendInventory()
        notify(message or 'Item apreendido.', 'success')
    end)
end)

RegisterNUICallback('containerPut', function(data, callback)
    callback({ ok = true })
    if not isOpen or not currentOther or (currentOther.mode ~= 'container' and currentOther.mode ~= 'discard')
        or not currentOther.id then return end
    local chestId = currentOther.id
    CreateThread(function()
        local ok, payload, message = OR.Callback.awaitResource(
            'ob_org','chestPut',chestId,data and data.slot,data and data.amount,
            data and data.targetSlot,activeWeaponItem()
        )
        if ok ~= true then return notify(payload or message or 'Nao foi possivel guardar o item.','error') end
        if not isOpen or not currentOther or currentOther.id ~= chestId then return end
        currentInventory = payload.inventory or currentInventory
        currentOther.inventory = payload.owned or currentOther.inventory
        sendInventory()
        notify(message or (currentOther.mode == 'discard' and 'Item descartado.' or 'Item guardado.'),'success')
    end)
end)

RegisterNUICallback('containerTake', function(data, callback)
    callback({ ok = true })
    if not isOpen or not currentOther or currentOther.mode ~= 'container' or not currentOther.id then return end
    local chestId = currentOther.id
    CreateThread(function()
        local ok, payload, message = OR.Callback.awaitResource(
            'ob_org','chestTake',chestId,data and data.slot,data and data.amount,data and data.targetSlot
        )
        if ok ~= true then return notify(payload or message or 'Nao foi possivel retirar o item.','error') end
        if not isOpen or not currentOther or currentOther.id ~= chestId then return end
        currentInventory = payload.inventory or currentInventory
        currentOther.inventory = payload.owned or currentOther.inventory
        sendInventory()
        notify(message or 'Item retirado.','success')
    end)
end)

RegisterNUICallback('containerMove', function(data, callback)
    callback({ ok = true })
    if not isOpen or not currentOther or currentOther.mode ~= 'container' or not currentOther.id then return end
    local chestId = currentOther.id
    CreateThread(function()
        local ok, payload, message = OR.Callback.awaitResource(
            'ob_org','chestMove',chestId,data and data.fromSlot,data and data.toSlot
        )
        if ok ~= true then return notify(payload or message or 'Nao foi possivel mover o item.','error') end
        if not isOpen or not currentOther or currentOther.id ~= chestId then return end
        currentOther.inventory = payload.owned or currentOther.inventory
        sendInventory()
    end)
end)

CreateThread(function()
    while true do
        if not isOpen or not currentOther then
            Wait(500)
        elseif currentOther.mode == 'container' or currentOther.mode == 'discard' then
            local position = currentOther.coords
            local maximum = (tonumber(currentOther.distance) or 2.0) + 0.75
            if type(position) ~= 'table' or #(GetEntityCoords(PlayerPedId()) - vector3(position.x,position.y,position.z)) > maximum then
                closeInventory()
                notify('O bau foi fechado porque voce se afastou.','error')
            end
            Wait(350)
        elseif not currentOther.targetSource then
            Wait(500)
        else
            local targetPlayer = GetPlayerFromServerId(currentOther.targetSource)
            local targetPed = targetPlayer >= 0 and GetPlayerPed(targetPlayer) or 0
            local myPed = PlayerPedId()
            local maximum = (tonumber(currentOther.distance) or 3.0) + 0.75
            local expired = currentOther.expiresAt and GetGameTimer() >= currentOther.expiresAt
            local handsLowered = currentOther.requiresHandsUp
                and (targetPlayer < 0
                    or Player(currentOther.targetSource).state['ob:handsUp'] ~= true)
            if expired or handsLowered or targetPed == 0 or not DoesEntityExist(targetPed)
                or #(GetEntityCoords(myPed) - GetEntityCoords(targetPed)) > maximum then
                closeInventory()
                notify(
                    expired and 'O tempo de visualizacao da mochila terminou.'
                        or handsLowered and 'A revista terminou porque a pessoa abaixou as maos.'
                        or 'A revista foi encerrada porque a pessoa se afastou.',
                    expired and 'info' or 'error'
                )
            end
            Wait(350)
        end
    end
end)

CreateThread(function()
    while true do
        if isOpen or LocalPlayer.state['or:loaded'] ~= true then
            Wait(500)
        else
            local drop = closestDrop()
            if not drop then
                Wait(500)
            else
                local coords = vector3(drop.coords.x, drop.coords.y, drop.coords.z)
                DrawMarker(2, coords.x, coords.y, coords.z + 0.18, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0, 0.20, 0.20, 0.20, 25, 200, 255, 180, false, true, 2, false, nil, nil, false)
                Wait(0)
            end
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then closeInventory() end
end)
-- Aguarda o frame do NUI existir antes de ordenar inventario e avisos de itens.
CreateThread(function()
    for _ = 1, 3 do
        Wait(1000)
        if type(SetNuiZIndex) == 'function' then SetNuiZIndex(40) end
    end
end)

