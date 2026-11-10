local menuOpen = false
local profile = nil
local lastMapRequest = 0

local function isLoaded()
    return LocalPlayer and LocalPlayer.state and LocalPlayer.state['or:loaded'] == true
end

local function locationData()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = streetHash ~= 0 and GetStreetNameFromHashKey(streetHash) or 'Local desconhecido'
    local crossing = crossingHash ~= 0 and GetStreetNameFromHashKey(crossingHash) or nil
    local zoneCode = GetNameOfZone(coords.x, coords.y, coords.z)
    local zone = zoneCode and GetLabelText(zoneCode) or ''

    if zone == 'NULL' then zone = zoneCode or '' end
    if crossing and crossing ~= '' then street = ('%s / %s'):format(street, crossing) end

    return {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        street = street,
        zone = zone,
        hour = GetClockHours(),
        minute = GetClockMinutes(),
        health = math.max(0, GetEntityHealth(ped) - 100),
        armour = GetPedArmour(ped),
    }
end

local function pushInterface(action)
    if not menuOpen then return end
    SendNUIMessage({
        action = action or 'update',
        profile = profile or {},
        location = locationData(),
        config = {
            cityName = OBPauseMenuConfig.CityName,
            citySubtitle = OBPauseMenuConfig.CitySubtitle,
        }
    })
end

local function closeMenu()
    if not menuOpen then return end
    menuOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
end

local function openMenu()
    if menuOpen or not isLoaded() or IsPauseMenuActive() or IsNuiFocused() then return end
    menuOpen = true
    profile = nil
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    pushInterface('open')
    TriggerServerEvent('ob_pausemenu:server:requestProfile')
end

RegisterNetEvent('ob_pausemenu:client:profile', function(data)
    profile = type(data) == 'table' and data or {}
    pushInterface('update')
end)

RegisterCommand(OBPauseMenuConfig.Command or 'obmenu', function()
    if menuOpen then closeMenu() else openMenu() end
end, false)

local function suppressNativePause()
    -- A tecla tambem pertence ao frontend do GTA. Bloqueia somente os poucos
    -- frames da abertura, em vez de manter um thread ativo durante todo o jogo.
    CreateThread(function()
        for _ = 1, 4 do
            DisableControlAction(0, 200, true)
            SetPauseMenuActive(false)
            Wait(0)
        end
    end)
end

RegisterCommand('+ob_pausemenu_escape', function()
    if OBPauseMenuConfig.InterceptEscape ~= true or OBPauseMenuConfig.UseEscapeKeyMapping ~= true then return end
    if menuOpen or not isLoaded() or IsNuiFocused() then return end
    DisableControlAction(0, 200, true)
    SetPauseMenuActive(false)
    suppressNativePause()
    openMenu()
end, false)

RegisterCommand('-ob_pausemenu_escape', function() end, false)
RegisterKeyMapping('+ob_pausemenu_escape', 'Abrir menu de pausa OB', 'keyboard', 'ESCAPE')

RegisterNUICallback('close', function(_, callback)
    closeMenu()
    callback({ ok = true })
end)

RegisterNUICallback('refresh', function(_, callback)
    if menuOpen then
        TriggerServerEvent('ob_pausemenu:server:requestProfile')
        SendNUIMessage({ action = 'location', location = locationData() })
    end
    callback({ ok = true })
end)

RegisterNUICallback('openNativeMap', function(_, callback)
    closeMenu()
    Wait(100)
    -- O frontend nativo e o unico que possui o mapa real, blips, zoom e criacao de rota.
    ActivateFrontendMenu(GetHashKey('FE_MENU_VERSION_MP_PAUSE'), true, -1)
    callback({ ok = true })
end)

RegisterNUICallback('openNativeSettings', function(_, callback)
    closeMenu()
    Wait(100)
    -- Os componentes nao seguem a ordem visual das abas. O componente 6
    -- abre diretamente Configuracoes no frontend multiplayer.
    ActivateFrontendMenu(GetHashKey('FE_MENU_VERSION_MP_PAUSE'), false, 6)
    callback({ ok = true })
end)

local blipTypeLabels = {
    [1] = 'Destino ou rota', [51] = 'Alerta de drogas', [52] = 'Loja',
    [59] = 'Conveniência', [60] = 'Polícia', [61] = 'Hospital',
    [67] = 'Veículo de serviço', [71] = 'Barbearia', [72] = 'Oficina',
    [73] = 'Loja de roupas', [75] = 'Estúdio de tatuagem', [108] = 'Banco',
    [110] = 'Loja de armas', [137] = 'Polícia', [141] = 'Trabalho rural',
    [153] = 'Emergência médica', [161] = 'Alerta', [198] = 'Táxi',
    [225] = 'Veículo', [237] = 'Madeireira', [280] = 'Destino de serviço',
    [313] = 'Disparos', [318] = 'Coleta de lixo', [354] = 'Eletricista',
    [355] = 'Loja de eletrônicos', [357] = 'Garagem', [375] = 'Hospital',
    [380] = 'Acidente de trânsito', [407] = 'Central de empregos',
    [431] = 'Loja', [455] = 'Ilha', [477] = 'Transportadora',
    [478] = 'Entrega', [498] = 'Centro de licenças', [500] = 'Alerta fiscal',
    [513] = 'Terminal de ônibus', [544] = 'Produtos de mecânica', [566] = 'Serraria',
}

local function blipLabel(blip, sprite)
    if type(GetBlipNameFromTextFile) == 'function' then
        local ok, key = pcall(GetBlipNameFromTextFile, blip)
        if ok and type(key) == 'string' and key ~= '' and key ~= 'NULL' then
            local translated = GetLabelText(key)
            if translated and translated ~= 'NULL' then return translated end
        end
    end
    return blipTypeLabels[sprite] or ('Blip %s'):format(sprite)
end

local function collectMapBlips()
    local result, seen = {}, {}
    -- Os sprites atuais do GTA/FiveM ficam dentro deste intervalo. A leitura so
    -- acontece quando a pagina do mapa e aberta, sem thread permanente.
    for sprite = 1, 1200 do
        local blip = GetFirstBlipInfoId(sprite)
        while blip and blip ~= 0 and DoesBlipExist(blip) do
            if not seen[blip] then
                seen[blip] = true
                local display = GetBlipInfoIdDisplay(blip)
                local alpha = GetBlipAlpha(blip)
                local coords = GetBlipInfoIdCoord(blip)
                local entity = GetBlipInfoIdEntityIndex(blip)
                local insideAtlas = coords
                    and coords.x >= -5660.0 and coords.x <= 6690.0
                    and coords.y >= -4060.0 and coords.y <= 8420.0
                    and (math.abs(coords.x) > 0.5 or math.abs(coords.y) > 0.5)

                -- Blips presos a ped/veículo mudam de posição e não pertencem ao
                -- atlas estático. Eles eram a principal origem dos pontos soltos.
                if sprite ~= 8 and display ~= 0 and alpha > 0 and insideAtlas and (not entity or entity == 0) then
                    result[#result + 1] = {
                        x = coords.x,
                        y = coords.y,
                        sprite = GetBlipSprite(blip),
                        color = GetBlipColour(blip),
                        label = blipLabel(blip, sprite),
                    }
                    if #result >= 1200 then return result end
                end
            end
            blip = GetNextBlipInfoId(sprite)
        end
    end
    return result
end

local function currentWaypoint()
    if not IsWaypointActive() then return false end
    local sprite = type(GetWaypointBlipEnumId) == 'function' and GetWaypointBlipEnumId() or 8
    local blip = GetFirstBlipInfoId(sprite)
    if not blip or blip == 0 or not DoesBlipExist(blip) then return false end
    local coords = GetBlipInfoIdCoord(blip)
    if not coords then return false end
    return { x = coords.x, y = coords.y }
end

RegisterNUICallback('requestMap', function(_, callback)
    local now = GetGameTimer()
    if now - lastMapRequest >= 750 then
        lastMapRequest = now
        SendNUIMessage({
            action = 'mapData',
            location = locationData(),
            blips = collectMapBlips(),
            waypoint = currentWaypoint(),
        })
    end
    callback({ ok = true })
end)

RegisterNUICallback('setWaypoint', function(data, callback)
    local x, y = tonumber(data and data.x), tonumber(data and data.y)
    if not x or not y or math.abs(x) > 10000.0 or math.abs(y) > 10000.0 then
        callback({ ok = false })
        return
    end
    SetNewWaypoint(x + 0.0, y + 0.0)
    callback({ ok = true })
end)

RegisterNUICallback('clearWaypoint', function(_, callback)
    -- Sao estados diferentes: um remove o marcador e o outro limpa o caminho
    -- calculado. Chamar os dois evita deixar a rota ou o pin presos.
    if type(ClearGpsPlayerWaypoint) == 'function' then
        pcall(ClearGpsPlayerWaypoint)
    else
        pcall(Citizen.InvokeNative, 0xFF4FB7C8CDFA3DA7)
    end
    if type(SetWaypointOff) == 'function' then
        pcall(SetWaypointOff)
    else
        pcall(Citizen.InvokeNative, 0xA7E4E2D361C2627F)
    end
    Wait(50)
    callback({ ok = not IsWaypointActive(), active = IsWaypointActive() })
end)

RegisterNUICallback('openHudSettings', function(_, callback)
    closeMenu()
    Wait(100)
    ExecuteCommand('ob_hud_settings')
    callback({ ok = true })
end)

RegisterNUICallback('disconnect', function(_, callback)
    callback({ ok = true })
    closeMenu()
    TriggerServerEvent('ob_pausemenu:server:disconnect')
end)

CreateThread(function()
    local interceptEscape = OBPauseMenuConfig.InterceptEscape == true
    local interceptPauseP = OBPauseMenuConfig.InterceptPauseP == true
    if OBPauseMenuConfig.UseEscapeKeyMapping == true then interceptEscape = false end
    if not interceptEscape and not interceptPauseP then return end
    local contextBlocked = false
    local nextContextCheck = 0

    while true do
        if not isLoaded() then
            nextContextCheck = 0
            Wait(500)
        elseif menuOpen then
            Wait(250)
        else
            local now = GetGameTimer()
            if now >= nextContextCheck then
                contextBlocked = IsNuiFocused() or IsPauseMenuActive()
                nextContextCheck = now + 100
            end

            if contextBlocked then
                Wait(50)
            else
                Wait(0)
                if interceptEscape then DisableControlAction(0, 200, true) end
                if interceptPauseP then DisableControlAction(0, 199, true) end
                local escapeReleased = interceptEscape and IsDisabledControlJustReleased(0, 200)
                local pausePReleased = interceptPauseP and IsDisabledControlJustReleased(0, 199)
                if escapeReleased or pausePReleased then
                    openMenu()
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end)
