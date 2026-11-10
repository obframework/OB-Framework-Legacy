local blips, blipCoords = {}, {}
local storeOpen = false
local activeLocationId

local function economyFor(location)
    local economy = type(OBStoresConfig.Economy) == 'table' and OBStoresConfig.Economy or {}
    local prices = type(economy.ItemPrices) == 'table' and economy.ItemPrices or {}
    local unitPrice = math.max(0, math.floor(tonumber(location.price) or tonumber(prices[location.kind]) or 0))
    return {
        enabled = economy.Enabled == true,
        currency = type(economy.Currency) == 'string' and economy.Currency or 'USD',
        unitPrice = unitPrice,
        itemPrices = prices,
    }
end

local function closeStoreUi()
    storeOpen = false
    activeLocationId = nil
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
end

local function openStore(locationId)
    local location = OBStoresConfig.Locations[locationId]
    if not location then return end
    if LocalPlayer.state['or:loaded'] ~= true or LocalPlayer.state['or:downed'] == true then return end

    local allowed, accessError = OR.Callback.awaitResource('ob_stores', 'storeAccess', location.id)
    if not allowed then return OR.Notify(accessError or 'Estabelecimento indisponivel.', 'error') end
    local ui = { sections = {} }
    local selected, allowedSections = {}, {}
    for _, id in ipairs(location.categories or {}) do selected[id] = true end
    for _, id in ipairs(location.allowedSections or {}) do allowedSections[id] = true end
    for _, section in ipairs((OBStoresConfig.Ui[location.kind] or {}).sections or {}) do
        if allowedSections[section.id] then
            local copy = { id = section.id, label = section.label, categories = {} }
            for _, category in ipairs(section.categories or {}) do
                if selected[category.id] then copy.categories[#copy.categories+1] = category end
            end
            if #copy.categories > 0 then ui.sections[#ui.sections+1] = copy end
        end
    end
    local payload = {
        id = location.id, label = location.label, title = location.title, coords = location.coords,
        heading = location.heading, camOffset = location.camOffset, lookAtOffset = location.lookAtOffset,
        defaultSection = location.defaultSection, allowedSections = location.allowedSections, ui = ui,
        economy = economyFor(location),
    }
    payload.externalUi = true
    if not exports.ob_creator:openStore(payload) then
        OR.Notify('A loja ja esta em uso.', 'error')
    end
end

RegisterNetEvent('ob_creator:client:externalStoreReady', function(payload)
    storeOpen = true
    activeLocationId = payload and payload.id or nil
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'open', data = payload or {} })
end)

RegisterNetEvent('ob_creator:client:externalStoreClosed', closeStoreUi)

RegisterNUICallback('getItems', function(data, cb)
    cb(exports.ob_creator:storeGetItems(data.sectionId, data.categoryId, data.page, 24))
end)

RegisterNUICallback('selectItem', function(data, cb)
    cb(exports.ob_creator:storeSelectItem(data.sectionId, data.categoryId, data.item))
end)

RegisterNUICallback('changeTexture', function(data, cb)
    cb(exports.ob_creator:storeChangeTexture(data and data.direction))
end)

RegisterNUICallback('changeColor', function(data, cb)
    cb(exports.ob_creator:storeChangeColor(data and data.direction))
end)

RegisterNUICallback('focus', function(data, cb)
    exports.ob_creator:storeFocus(data.focus)
    cb({ ok = true })
end)

RegisterNUICallback('save', function(_, cb)
    cb({ ok = exports.ob_creator:storeSave({
        callbackResource = 'ob_stores',
        locationId = activeLocationId,
    }) })
end)

RegisterNUICallback('cancel', function(_, cb)
    cb({ ok = exports.ob_creator:storeCancel() })
end)

local function createLocationBlip(index, location)
    local alreadyMarked = false
    for _, coords in pairs(blipCoords) do
        if #(coords - location.coords) < 12.0 then alreadyMarked = true break end
    end
    if OBStoresConfig.Blips and location.blip and not blips[index] and not alreadyMarked then
        local blip = AddBlipForCoord(location.coords.x, location.coords.y, location.coords.z)
        SetBlipSprite(blip, location.blip.sprite or 73)
        SetBlipColour(blip, location.blip.color or 3)
        SetBlipScale(blip, location.blip.scale or 0.72)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(location.label)
        EndTextCommandSetBlipName(blip)
        blips[index] = blip
        blipCoords[index] = location.coords
    end
end

local function setup()
    for index, location in ipairs(OBStoresConfig.Locations) do
        createLocationBlip(index, location)
    end
end

local function applyDefinitions(rows)
    if storeOpen then
        exports.ob_creator:storeCancel()
        OR.Notify('Os estabelecimentos foram atualizados. Abra novamente para continuar.', 'info')
    end
    for _, blip in pairs(blips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
    blips, blipCoords = {}, {}
    local locations = {}
    for _, row in ipairs(rows or {}) do
        row.coords = vector3(row.coords.x, row.coords.y, row.coords.z)
        row.camOffset = vector3(row.camOffset.x, row.camOffset.y, row.camOffset.z)
        row.lookAtOffset = vector3(row.lookAtOffset.x, row.lookAtOffset.y, row.lookAtOffset.z)
        locations[#locations+1] = row
    end
    OBStoresConfig.Locations = locations
    setup()
end
RegisterNetEvent('ob_stores:client:definitions', applyDefinitions)
CreateThread(function()
    while LocalPlayer.state['or:loaded'] ~= true do Wait(500) end
    while true do
        local rows = OR.Callback.awaitResource('ob_stores', 'worldShopDefinitions')
        if rows then applyDefinitions(rows); break end
        Wait(1500)
    end
end)

-- A zona continua sendo aberta pelo ob_target, mas o marcador deixa claro
-- onde esta o balcao mesmo antes de o jogador pressionar o Alt.
CreateThread(function()
    while true do
        local sleep = 1000
        local playerCoords = GetEntityCoords(PlayerPedId())
        local marker = OBStoresConfig.Marker
        for index, location in ipairs(OBStoresConfig.Locations) do
            local distance = #(playerCoords - location.coords)
            if distance <= (marker.distance or 30.0) then
                sleep = 0
                if location.markerEnabled ~= false then DrawMarker(
                    marker.type or 1,
                    location.coords.x, location.coords.y, location.coords.z - 0.96,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    marker.scale.x, marker.scale.y, marker.scale.z,
                    marker.color[1], marker.color[2], marker.color[3], marker.color[4],
                    false, true, 2, false, nil, nil, false
                ) end
                if distance <= (location.radius or 1.5) then
                    local onScreen, x, y = World3dToScreen2d(location.coords.x, location.coords.y, location.coords.z + 1.05)
                    if onScreen then
                        SetTextScale(0.34, 0.34)
                        SetTextFont(4)
                        SetTextProportional(1)
                        SetTextColour(230, 248, 255, 230)
                        SetTextCentre(true)
                        SetTextEntry('STRING')
                        AddTextComponentString(('~b~[E]~s~ Abrir %s'):format(location.label))
                        DrawText(x, y)
                    end
                    if not storeOpen and not IsNuiFocused() and IsControlJustPressed(0, 38) then
                        openStore(index)
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if storeOpen then exports.ob_creator:storeCancel() end
    for _, blip in pairs(blips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
end)
