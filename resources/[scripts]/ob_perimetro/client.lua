local areas, blips, inside, nearby = {}, {}, {}, {}
local opened, busy, uiVersion = false, false, 0

local function close()
    uiVersion = uiVersion + 1
    if not opened then return end
    opened = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function clearBlips()
    for _, pair in pairs(blips) do
        for _, blip in ipairs(pair) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
    end
    blips = {}
end

local function update(data)
    clearBlips()
    areas, nearby = type(data) == 'table' and data or {}, {}
    local keep = {}
    for _, area in ipairs(areas) do
        keep[area.id] = true
        local c = area.center
        local radius = AddBlipForRadius(c.x, c.y, c.z, area.radius + 0.0)
        SetBlipColour(radius, OBPerimetro.BlipColor)
        SetBlipAlpha(radius, OBPerimetro.BlipAlpha)
        local center = AddBlipForCoord(c.x, c.y, c.z)
        SetBlipSprite(center, OBPerimetro.BlipSprite)
        SetBlipColour(center, OBPerimetro.BlipColor)
        SetBlipScale(center, 0.7)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName('Perimetro: ' .. area.name)
        EndTextCommandSetBlipName(center)
        blips[area.id] = { radius, center }
    end
    for id in pairs(inside) do if not keep[id] then inside[id] = nil end end
    if opened then SendNUIMessage({ action = 'update', areas = areas }) end
end

RegisterNetEvent('ob_perimetro:client:sync', function(data)
    if source == 65535 then update(data) end
end)

RegisterCommand('perimetro', function()
    if opened then return close() end
    if busy or IsNuiFocused() then return end
    busy = true
    local version = uiVersion
    CreateThread(function()
        local ok, data, err = pcall(OR.Callback.await, 'menu')
        busy = false
        if not ok or not data then
            return TriggerEvent('ob_notification:client:notify', ok and err or 'Falha ao abrir perimetros.', 'error')
        end
        if version ~= uiVersion or IsNuiFocused() then return end
        update(data.areas)
        opened = true
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'open', areas = areas, config = OBPerimetro })
    end)
end, false)

RegisterNUICallback('close', function(_, cb) close(); cb({ ok = true }) end)
for _, action in ipairs({ 'create', 'remove' }) do
    RegisterNUICallback(action, function(data, cb)
        if not opened or busy then return cb({ ok = false, error = 'Aguarde a operacao atual.' }) end
        busy = true
        CreateThread(function()
            local ok, result, err = pcall(OR.Callback.await, action, action == 'remove' and data.id or data)
            busy = false
            if ok and result then update(result.areas) end
            cb({ ok = ok and result ~= nil, error = ok and err or 'Falha ao contatar o servidor.' })
        end)
    end)
end

CreateThread(function()
    while LocalPlayer.state['or:loaded'] ~= true do Wait(500) end
    TriggerServerEvent('ob_perimetro:server:requestSync')
end)

CreateThread(function()
    while true do
        nearby = {}
        if #areas > 0 and LocalPlayer.state['or:loaded'] == true then
            local coords = GetEntityCoords(PlayerPedId())
            for _, area in ipairs(areas) do
                local c = area.center
                local dx, dy = coords.x - c.x, coords.y - c.y
                local distance = math.sqrt(dx * dx + dy * dy)
                if distance <= area.radius and not inside[area.id] then
                    inside[area.id] = true
                    TriggerEvent('ob_notification:client:notify', 'Area interditada pela policia: ' .. area.name .. '. Evite permanecer no local.', 'warning', 8000)
                elseif distance > area.radius + 5 then inside[area.id] = nil end
                if OBPerimetro.Marker.enabled and distance <= area.radius + OBPerimetro.Marker.distance then
                    nearby[#nearby + 1] = area
                end
            end
        end
        if opened and (LocalPlayer.state['or:loaded'] ~= true or LocalPlayer.state['or:downed'] == true) then close() end
        Wait(math.max(250, OBPerimetro.CheckIntervalMs))
    end
end)

CreateThread(function()
    while true do
        if #nearby == 0 then Wait(500)
        else
            local m = OBPerimetro.Marker
            for _, area in ipairs(nearby) do
                local c = area.center
                DrawMarker(1, c.x, c.y, c.z - 15.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    area.radius * 2.0, area.radius * 2.0, m.height + 0.0, m.r, m.g, m.b, m.alpha,
                    false, false, 2, false, nil, nil, false)
            end
            Wait(0)
        end
    end
end)

AddEventHandler('onClientResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    close()
    clearBlips()
end)
