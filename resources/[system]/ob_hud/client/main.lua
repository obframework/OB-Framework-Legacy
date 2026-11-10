local speedMultiplier = ORHudConfig.SpeedUnit == 'mph' and 2.236936 or 3.6
local hudHidden = false
local deathHidden = false
local minimapLoaded = false
local radarRefreshed = false
local minimapScaleform = RequestScaleformMovie('minimap')
local minimapBarsConfigured = false
local pauseWasActive = false
local settingsOpen = false
local hudTheme = 'current'
local visualFilter = 'default'
local performancePreset = 'default'
local lodScale
local function nativeTrue(value) return value == true or value == 1 end
local enhancedGame = type(IsGameEnhancedVersion) == 'function' and nativeTrue(IsGameEnhancedVersion()) or false

local validThemes = { current = true, clean = true, racing = true }
local visualFilters = {
    default = false,
    -- Intensidades moderadas preservam leitura noturna, interiores e clima.
    -- O Realista combina cor suave com uma camada leve de luz ambiente/reflexos.
    realistic = {
        modifier = 'NG_filmic01',
        strength = 0.42,
        extra = 'reflection_correct_ambient',
        extraStrength = 0.24,
    },
    natural = { modifier = 'yell_tunnel_nodirect', strength = 0.24 },
    cinema = { modifier = 'cinema', strength = 0.58 },
    vibrant = { modifier = 'yell_tunnel_nodirect', strength = 0.42 },
    contrast = { modifier = 'MP_Powerplay_blend', strength = 0.40, extra = 'reflection_correct_ambient' },
}
local validPerformancePresets = { default = true, balanced = true, performance = true, ultra = true }

local function configuredDefaultTheme()
    local name = tostring(ORHudConfig.DefaultTheme or 'current'):lower()
    return validThemes[name] and name or 'current'
end

-- Somente elementos substituidos pela HUD propria. Ajuda, textos flutuantes,
-- legendas e mira continuam disponiveis para os demais recursos do servidor.
local hiddenHudComponents = { 1, 2, 3, 4, 6, 7, 8, 9, 13, 16, 17, 20 }

local function percent(value)
    value = math.floor(tonumber(value) or 0)
    return math.max(0, math.min(100, value))
end

local function vehicleEnginePercent(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return 0 end
    -- O mostrador M representa somente o motor. A lataria e persistida e
    -- reparada separadamente, mas nao deve mascarar um motor destruido.
    local engineHealth = tonumber(GetVehicleEngineHealth(vehicle)) or 0.0
    return percent(engineHealth / 10.0)
end

local function vehicleBodyPercent(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return 0 end
    return percent((tonumber(GetVehicleBodyHealth(vehicle)) or 0.0) / 10.0)
end

local function vehicleRoadSpeed(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return 0 end

    -- GetEntitySpeed mede deslocamento no mundo. Isso inclui um carro parado
    -- sobre trem/plataforma e tambem a velocidade vertical durante uma queda.
    -- O dashboard speed do FiveM vem das rodas motrizes e representa melhor o
    -- que o velocimetro deve exibir.
    local speed = math.abs(tonumber(GetVehicleDashboardSpeed(vehicle)) or 0.0)
    if speed < 0.5 then return 0 end
    return math.floor(speed * speedMultiplier)
end

local function normalizeSignedAngle(value)
    value = (tonumber(value) or 0.0) % 360.0
    if value > 180.0 then value = value - 360.0 end
    return value
end

local function aircraftTelemetry(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end

    local class = GetVehicleClass(vehicle)
    if class ~= 15 and class ~= 16 then return nil end -- helicoptero / aviao

    local velocity = GetEntityVelocity(vehicle)
    local coords = GetEntityCoords(vehicle)
    local rotation = GetEntityRotation(vehicle, 2)
    local horizontalSpeed = math.sqrt((velocity.x * velocity.x) + (velocity.y * velocity.y))
    local heading = math.floor(((GetEntityHeading(vehicle) or 0.0) % 360.0) + 0.5) % 360

    return {
        active = true,
        kind = class == 15 and 'HELI' or 'PLANE',
        -- O GTA nao simula pressao para IAS. Exibimos ground speed em nos.
        groundSpeed = math.floor((horizontalSpeed * 1.943844) + 0.5),
        altitude = math.floor(math.max(0.0, coords.z) * 3.28084 + 0.5),
        agl = math.floor(math.max(0.0, GetEntityHeightAboveGround(vehicle)) * 3.28084 + 0.5),
        verticalSpeed = velocity.z >= 0.0
            and math.floor((velocity.z * 196.850394) + 0.5)
            or math.ceil((velocity.z * 196.850394) - 0.5),
        heading = heading,
        pitch = math.max(-90.0, math.min(90.0, normalizeSignedAngle(rotation.x))),
        roll = normalizeSignedAngle(rotation.y),
        rpm = percent(GetVehicleCurrentRpm(vehicle) * 100),
    }
end

local function isLoaded()
    return LocalPlayer.state and LocalPlayer.state['or:loaded'] == true
end

local function isDowned()
    return LocalPlayer.state and LocalPlayer.state['or:downed'] == true
end

local function getNeeds()
    local needs = LocalPlayer.state and LocalPlayer.state['or:needs'] or nil
    return {
        hunger = percent(needs and needs.hunger or 100),
        thirst = percent(needs and needs.thirst or 100),
    }
end

local function setMinimapPosition(component, values)
    SetMinimapComponentPosition(component, values[1], values[2], values[3], values[4], values[5], values[6])
end

local minimapBounds
local radarMaskReady = false
local radarMaskRequestedAt
local radarMaskFailed = false
local radarMask1gReplaced = false
local function loadRadarMask()
    if ORHudConfig.RectangularMinimap == false or radarMaskFailed then return false end
    if radarMaskReady then return true end
    if not radarMaskRequestedAt then
        radarMaskRequestedAt = GetGameTimer()
        RequestStreamedTextureDict('ob_hud_radarmask', false)
    end
    if HasStreamedTextureDictLoaded('ob_hud_radarmask') then
        AddReplaceTexture('platform:/textures/graphics', 'radarmasksm', 'ob_hud_radarmask', 'radarmasksm')
        -- O Legacy possui radarmask1g; no Enhanced essa textura nao existe e
        -- tentar substitui-la gera warning no rage-graphics-five.
        if not enhancedGame then
            AddReplaceTexture('platform:/textures/graphics', 'radarmask1g', 'ob_hud_radarmask', 'radarmasksm')
            radarMask1gReplaced = true
        end
        radarMaskReady = true
        minimapLoaded = false
        radarRefreshed = false
    elseif GetGameTimer() - radarMaskRequestedAt > 10000 then
        radarMaskFailed = true
        print('[ob_hud] Mascara retangular nao carregou em 10s; usando radar nativo. Confira stream/stream_enhanced.')
    end
    return radarMaskReady
end

local function configureMinimap(force)
    local rectangular = loadRadarMask()
    if minimapLoaded and not force then return end

    -- Converte o espaco frontend do GTA para NUI, incluindo aspect ratio e safezone.
    -- https://docs.fivem.net/docs/cookbook/2019/08/12/useful-snippet-getting-the-top-left-of-the-minimap-in-screen-coordinates/
    SetScriptGfxAlign(string.byte('L'), string.byte('B'))
    local originX, originY = GetScriptGfxPosition(0.0, 0.0)
    local unitX, unitY = GetScriptGfxPosition(1.0, 1.0)
    ResetScriptGfxAlign()
    local scaleX, scaleY = unitX - originX, unitY - originY
    if scaleX <= 0 or scaleY <= 0 then return end
    -- Composicao da mascara squaremap usada pelo HUD de referencia.
    local base = rectangular and {
        minimap = { 'L', 'B', 0.0, -0.047, 0.1638, 0.183 },
        mask = { 'L', 'B', 0.0, 0.0, 0.128, 0.20 },
        blur = { 'L', 'B', -0.01, 0.025, 0.262, 0.300 },
    } or {
        minimap = { 'L', 'B', -0.0045, 0.002, 0.150, 0.188888 },
        mask = { 'L', 'B', 0.020, 0.032, 0.111, 0.159 },
        blur = { 'L', 'B', -0.030, 0.022, 0.266, 0.237 },
    }
    local width, height = base.minimap[5] * scaleX, base.minimap[6] * scaleY
    local marginX = math.max(0.018, math.max(0, originX))
    local marginY = math.max(0.025, math.max(0, 1.0 - originY))
    local left = hudTheme == 'clean' and (1.0 - marginX - width) or marginX
    local top = hudTheme == 'current' and (1.0 - marginY - height) or math.max(0.08, marginY)
    local x = (left - originX) / scaleX
    local y = (top - originY) / scaleY + base.minimap[6]
    local dx, dy = x - base.minimap[3], y - base.minimap[4]
    local layout = base
    for _, component in pairs(layout) do
        component[3] = component[3] + dx
        component[4] = component[4] + dy
    end
    minimapBounds = { left = left, top = top, width = width, height = height }
    SetMinimapClipType(0)
    setMinimapPosition('minimap', layout.minimap)
    setMinimapPosition('minimap_mask', layout.mask)
    setMinimapPosition('minimap_blur', layout.blur)
    minimapLoaded = true
end

local function configureMinimapBars(force)
    if (minimapBarsConfigured and not force) or not HasScaleformMovieLoaded(minimapScaleform) then return end
    BeginScaleformMovieMethod(minimapScaleform, 'SETUP_HEALTH_ARMOUR')
    ScaleformMovieMethodAddParamInt(3)
    EndScaleformMovieMethod()
    minimapBarsConfigured = true
end

local function applyVisualFilter(name, persist)
    if visualFilters[name] == nil then name = 'default' end
    visualFilter = name

    ClearTimecycleModifier()
    ClearExtraTimecycleModifier()
    if type(ResetExtraTimecycleModifierStrength) == 'function' then
        ResetExtraTimecycleModifierStrength()
    end

    local filter = visualFilters[name]
    if filter then
        SetTimecycleModifier(filter.modifier)
        SetTimecycleModifierStrength(tonumber(filter.strength) or 1.0)
        if filter.extra then
            SetExtraTimecycleModifier(filter.extra)
            if type(SetExtraTimecycleModifierStrength) == 'function' then
                SetExtraTimecycleModifierStrength(tonumber(filter.extraStrength) or 1.0)
            end
        end
    end

    if persist ~= false then SetResourceKvp('ob_hud:visualFilter', visualFilter) end
end

local function callOptional(native, ...)
    if type(native) == 'function' then native(...) end
end

local function configureShadows(enabled, trackerScale, depthValue, boundsScale)
    callOptional(RopeDrawShadowEnabled, enabled)
    callOptional(CascadeShadowsClearShadowSampleType)
    callOptional(CascadeShadowsSetAircraftMode, enabled)
    callOptional(CascadeShadowsEnableEntityTracker, true)
    callOptional(CascadeShadowsSetDynamicDepthMode, enabled)
    callOptional(CascadeShadowsSetEntityTrackerScale, trackerScale)
    callOptional(CascadeShadowsSetDynamicDepthValue, depthValue)
    callOptional(CascadeShadowsSetCascadeBoundsScale, boundsScale)
    callOptional(SetPedAoBlobRendering, PlayerPedId(), enabled)
end

local function applyPerformancePreset(name, persist)
    if not validPerformancePresets[name] then name = 'default' end
    performancePreset = name
    lodScale = nil

    if name == 'ultra' then
        configureShadows(false, 0.0, 0.0, 0.0)
        callOptional(SetFlashLightFadeDistance, 0.0)
        callOptional(SetLightsCutoffDistanceTweak, 0.0)
        callOptional(DisableVehicleDistantlights, true)
        lodScale = 0.65
    elseif name == 'performance' then
        configureShadows(false, 0.0, 0.0, 0.0)
        callOptional(SetFlashLightFadeDistance, 3.0)
        callOptional(SetLightsCutoffDistanceTweak, 0.35)
        callOptional(DisableVehicleDistantlights, true)
        lodScale = 0.80
    elseif name == 'balanced' then
        configureShadows(true, 0.65, 0.65, 0.65)
        callOptional(SetFlashLightFadeDistance, 5.0)
        callOptional(SetLightsCutoffDistanceTweak, 0.75)
        callOptional(DisableVehicleDistantlights, false)
    else
        configureShadows(true, 1.0, 1.0, 1.0)
        callOptional(SetFlashLightFadeDistance, 1.0)
        callOptional(SetLightsCutoffDistanceTweak, 1.0)
        callOptional(DisableVehicleDistantlights, false)
    end

    if persist ~= false then SetResourceKvp('ob_hud:performancePreset', performancePreset) end
end

local function applyHudTheme(name, persist)
    if not validThemes[name] then name = configuredDefaultTheme() end
    hudTheme = name
    minimapLoaded = false
    radarRefreshed = false
    configureMinimap(true)
    configureMinimapBars(true)
    SendNUIMessage({ action = 'theme', theme = hudTheme })
    if persist ~= false then SetResourceKvp('ob_hud:theme', hudTheme) end
end

local function currentSettings()
    return {
        theme = hudTheme,
        visualFilter = visualFilter,
        performancePreset = performancePreset,
    }
end

local function closeSettings()
    if not settingsOpen then return end
    settingsOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'settings', visible = false })
end

local function openSettings()
    if settingsOpen or not isLoaded() or IsPauseMenuActive() then return end
    if type(IsNuiFocused) == 'function' and IsNuiFocused() then return end
    settingsOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'settings', visible = true, settings = currentSettings() })
end

do
    local defaultTheme = configuredDefaultTheme()
    local savedTheme = GetResourceKvpString('ob_hud:theme')
    hudTheme = savedTheme and validThemes[savedTheme] and savedTheme or defaultTheme
    applyVisualFilter(GetResourceKvpString('ob_hud:visualFilter') or 'default', false)
    applyPerformancePreset(GetResourceKvpString('ob_hud:performancePreset') or 'default', false)
end

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if radarMaskReady then
        RemoveReplaceTexture('platform:/textures/graphics', 'radarmasksm')
        if radarMask1gReplaced then
            RemoveReplaceTexture('platform:/textures/graphics', 'radarmask1g')
        end
        SetStreamedTextureDictAsNoLongerNeeded('ob_hud_radarmask')
    end
    if settingsOpen then
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
    end
    ClearTimecycleModifier()
    ClearExtraTimecycleModifier()
    applyPerformancePreset('default', false)
end)

CreateThread(function()
    while true do
        local needsFrameUpdate = false
        if ORHudConfig.HideDefaultHud then
            for index = 1, #hiddenHudComponents do
                HideHudComponentThisFrame(hiddenHudComponents[index])
            end
            DisplayAmmoThisFrame(false)
            needsFrameUpdate = true
        end
        if lodScale and type(OverrideLodscaleThisFrame) == 'function' then
            OverrideLodscaleThisFrame(lodScale)
            needsFrameUpdate = true
        end
        if needsFrameUpdate then
            Wait(0)
        else
            Wait(1000)
        end
    end
end)

CreateThread(function()
    -- O scaleform do minimapa pode ser recriado pelo GTA ao abrir o mapa,
    -- alternar o radar grande ou trocar de resolucao. A reaplicacao esparsa
    -- mantem barras nativas e posicionamento corretos sem trabalho por frame.
    while true do
        configureMinimap(true)
        configureMinimapBars(true)
        Wait(minimapBarsConfigured and 5000 or 250)
    end
end)

RegisterCommand('hud', function()
    hudHidden = not hudHidden
    if hudHidden then
        DisplayRadar(false)
        SendNUIMessage({ action = 'player', visible = false })
        SendNUIMessage({ action = 'vehicle', visible = false })
    end
end, false)

RegisterCommand('ob_hud_settings', openSettings, false)
RegisterCommand('hudconfig', openSettings, false)
RegisterKeyMapping('ob_hud_settings', 'Abrir configuracoes da HUD', 'keyboard', ORHudConfig.MenuKey or 'O')

RegisterNUICallback('closeSettings', function(_, callback)
    closeSettings()
    callback({ ok = true })
end)

RegisterNUICallback('updateSettings', function(data, callback)
    if type(data) ~= 'table' then
        callback({ ok = false, settings = currentSettings() })
        return
    end

    if data.theme ~= nil then applyHudTheme(tostring(data.theme), true) end
    if data.visualFilter ~= nil then applyVisualFilter(tostring(data.visualFilter), true) end
    if data.performancePreset ~= nil then applyPerformancePreset(tostring(data.performancePreset), true) end

    callback({ ok = true, settings = currentSettings() })
end)

RegisterNUICallback('resetSettings', function(_, callback)
    applyHudTheme(configuredDefaultTheme(), true)
    applyVisualFilter('default', true)
    applyPerformancePreset('default', true)
    callback({ ok = true, settings = currentSettings() })
end)

RegisterNetEvent('ob_hud:client:setDeathHidden', function(hidden)
    deathHidden = hidden == true
    if deathHidden then
        closeSettings()
        DisplayRadar(false)
        SendNUIMessage({ action = 'player', visible = false })
        SendNUIMessage({ action = 'vehicle', visible = false })
    end
end)

RegisterNetEvent('ob_core:client:playerSpawned', function()
    CreateThread(function()
        Wait(250)
        applyVisualFilter(visualFilter, false)
        applyPerformancePreset(performancePreset, false)
        applyHudTheme(hudTheme, false)
    end)
end)

RegisterNetEvent('ob_hud:client:setSeatbelt', function(belted)
    SendNUIMessage({ action = 'seatbelt', belted = belted == true })
end)

CreateThread(function()
    Wait(400)
    SendNUIMessage({
        action = 'init',
        unit = ORHudConfig.SpeedUnit,
        logoFile = ORHudConfig.LogoFile,
        theme = hudTheme,
    })
end)

CreateThread(function()
    local vehicleInterval = math.max(100, tonumber(ORHudConfig.UpdateInterval) or 150)
    local playerInterval = math.max(vehicleInterval, tonumber(ORHudConfig.PlayerUpdateInterval) or 300)
    local nextUpdate = vehicleInterval
    local vehicleUiVisible = false

    while true do
        Wait(nextUpdate)

        local ped = PlayerPedId()
        local playerId = PlayerId()
        local paused = IsPauseMenuActive()

        if pauseWasActive and not paused then
            configureMinimap(true)
            configureMinimapBars(true)
        end
        pauseWasActive = paused

        if not isLoaded() or hudHidden or deathHidden or isDowned() then
            nextUpdate = 500
            DisplayRadar(false)
            SendNUIMessage({ action = 'player', visible = false })
            if vehicleUiVisible then
                SendNUIMessage({ action = 'vehicle', visible = false })
                vehicleUiVisible = false
            end
        else
            configureMinimap()

            local inVehicle = IsPedInAnyVehicle(ped, false)
            nextUpdate = inVehicle and vehicleInterval or playerInterval
            local showRadar = not paused and (inVehicle or ORHudConfig.ShowMinimapOutOfVehicle)
            DisplayRadar(showRadar)
            local radarVisible = showRadar
            if type(IsRadarHidden) == 'function' then
                radarVisible = not IsRadarHidden()
            end

            if showRadar and not radarRefreshed then
                SetRadarBigmapEnabled(true, false)
                Wait(50)
                SetRadarBigmapEnabled(false, false)
                Wait(0)
                configureMinimap(true)
                configureMinimapBars(true)
                radarRefreshed = true
            end

            local needs = getNeeds()
            local health = percent(GetEntityHealth(ped) - 100)
            local armor = percent(GetPedArmour(ped))
            -- Nesta native, o valor observado representa o percentual ja
            -- consumido: 0 descansado e 100 esgotado. A HUD exibe o restante.
            local stamina = percent(100 - GetPlayerSprintStaminaRemaining(playerId))
            if IsPedSwimmingUnderWater(ped) then
                stamina = percent(GetPlayerUnderwaterTimeRemaining(playerId) * 10)
            end
            local showStamina = stamina < 99

            local weapon = GetSelectedPedWeapon(ped)
            local showAmmo = weapon ~= GetHashKey('WEAPON_UNARMED')
            local ammoClip, ammoReserve = 0, 0
            if showAmmo then
                local hasClip, clip = GetAmmoInClip(ped, weapon)
                ammoClip = hasClip and math.max(0, math.floor(tonumber(clip) or 0)) or 0
                local ammoTotal = math.max(0, GetAmmoInPedWeapon(ped, weapon) or 0)
                ammoReserve = math.max(0, ammoTotal - ammoClip)
            end

            local voiceStatus
            if GetResourceState('ob_voice') == 'started' then
                local ok, current = pcall(function() return exports.ob_voice:GetStatus() end)
                voiceStatus = ok and type(current) == 'table' and current or LocalPlayer.state['ob:voice']
            end
            SendNUIMessage({
                action = 'player',
                visible = not paused,
                data = {
                    minimapBounds = minimapBounds,
                    health = health,
                    armor = armor,
                    hunger = needs.hunger,
                    thirst = needs.thirst,
                    stamina = stamina,
                    showStamina = showStamina,
                    inVehicle = inVehicle,
                    showAmmo = showAmmo,
                    ammoClip = ammoClip,
                    ammoReserve = ammoReserve,
                    gameTime = ('%02d:%02d'):format(GetClockHours(), GetClockMinutes()),
                    radarVisible = radarVisible,
                    voice = voiceStatus,
                }
            })

            if inVehicle then
                local vehicle = GetVehiclePedIsIn(ped, false)
                local gear = GetVehicleCurrentGear(vehicle)
                local flight = aircraftTelemetry(vehicle)
                SendNUIMessage({
                    action = 'vehicle',
                    visible = not paused,
                    data = {
                        speed = vehicleRoadSpeed(vehicle),
                        rpm = percent(GetVehicleCurrentRpm(vehicle) * 100),
                        gear = gear == 0 and 'R' or gear,
                        fuel = percent(GetVehicleFuelLevel(vehicle)),
                        engine = vehicleEnginePercent(vehicle),
                        body = vehicleBodyPercent(vehicle),
                        mileage = math.floor(GetResourceState('ob_fuel') == 'started' and exports.ob_fuel:GetMileage(vehicle) or 0),
                        seatbelt = GetResourceState('ob_seatbelt') == 'started' and exports.ob_seatbelt:IsBuckled() or false,
                        flight = flight,
                    }
                })
                vehicleUiVisible = true
            elseif vehicleUiVisible then
                SendNUIMessage({ action = 'vehicle', visible = false })
                vehicleUiVisible = false
            end
        end
    end
end)
-- A NUI pode ainda nao possuir frame durante a carga inicial. Reaplica depois
-- para manter a HUD persistente abaixo das interfaces temporarias.
CreateThread(function()
    for _ = 1, 3 do
        Wait(1000)
        if type(SetNuiZIndex) == 'function' then SetNuiZIndex(0) end
    end
end)

