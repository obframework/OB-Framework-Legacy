local active, generation = nil, 0

local function weatherOverride(name)
    if GetResourceState('ob_weather') == 'started' then
        local ok = pcall(function() exports.ob_weather:SetEarthquakeWeather(name) end)
        if ok then return end
    end
    -- Sem ob_weather, o override nao altera o clima persistente de outro script.
    if name then SetOverrideWeather(name) else ClearOverrideWeather() end
end

local function otherBlackoutActive()
    -- Compatibilidade opcional: o terremoto nao precisa do ob_blackout para funcionar.
    if GetResourceState('ob_blackout') ~= 'started' then return false end
    local state = GlobalState['ob:blackout']
    return type(state) == 'table' and state.active == true
end

local function keepVehicleLightsEnabled()
    if type(SetArtificialLightsStateAffectsVehicles) == 'function' then
        pcall(SetArtificialLightsStateAffectsVehicles, false)
    end
end

local function applyRainPhase(remainingMs)
    if not active then return end
    local strong = remainingMs <= (tonumber(OBEarthquakeConfig.StrongRainStartsAtSeconds) or 180) * 1000
    if active.strongRain == strong then return end
    active.strongRain = strong
    active.weather = strong and OBEarthquakeConfig.Weather or OBEarthquakeConfig.LightWeather
    weatherOverride(active.weather)
    SetRainLevel(strong and OBEarthquakeConfig.Rain or OBEarthquakeConfig.LightRain)
end

local function stop()
    generation = generation + 1
    if not active then return end
    active = nil
    SendNUIMessage({ action = 'stopAlert' })
    StopGameplayCamShaking(true)
    SetRainLevel(-1.0)
    weatherOverride(nil)
    SetArtificialLightsState(otherBlackoutActive())
end

local function alertMinute(minutes)
    if minutes == 1 then
        TriggerEvent('ob_notification:client:notify',
            'ALERTA DE TERREMOTO: energia interrompida. Procure um abrigo agora.',
            'warning', OBEarthquakeConfig.NotificationDurationMs)
        return
    end
    local audio = OBEarthquakeConfig.Audio or {}
    local shouldPlay = false
    for _, value in ipairs(audio.PlayAtMinutes or {}) do
        if tonumber(value) == minutes then shouldPlay = true; break end
    end
    if not shouldPlay then return end

    TriggerEvent('ob_notification:client:notify',
        ('ALERTA DE TERREMOTO: faltam %s minutos. Procure um abrigo.'):format(minutes),
        'warning', OBEarthquakeConfig.NotificationDurationMs)
    if audio.Enabled == true and type(audio.File) == 'string' and audio.File ~= '' then
        SendNUIMessage({ action = 'playAlert', file = audio.File, volume = tonumber(audio.Volume) or 0.8 })
    end
end

local function quakePowerOff(remainingMs)
    local power = OBEarthquakeConfig.Power or {}
    if remainingMs <= (tonumber(power.OffAtSeconds) or 60) * 1000 then return true end

    local cycle, offTime
    if remainingMs <= (tonumber(power.FastStartsAtSeconds) or 120) * 1000 then
        cycle, offTime = tonumber(power.FastCycleMs) or 5000, tonumber(power.FastOffMs) or 3000
    elseif remainingMs <= (tonumber(power.SlowStartsAtSeconds) or 180) * 1000 then
        cycle, offTime = tonumber(power.SlowCycleMs) or 8000, tonumber(power.SlowOffMs) or 700
    else
        return nil -- Antes dos 3 minutos, nao altera a energia da cidade.
    end
    cycle = math.max(500, math.floor(cycle))
    offTime = math.max(100, math.min(cycle, math.floor(offTime)))
    return remainingMs % cycle < offTime
end

RegisterNetEvent('ob_earthquake:client:sync', function(data)
    if source ~= 65535 then return end
    if type(data) ~= 'table' or (tonumber(data.remainingMs) or 0) <= 0 then return stop() end
    if active and active.id == data.id then return end
    stop()

    local version = generation
    local duration = math.min(tonumber(data.remainingMs) or 0, (tonumber(OBEarthquakeConfig.MaxDuration) or 300) * 1000)
    active = { id = data.id, deadline = GetGameTimer() + duration }
    applyRainPhase(duration)

    CreateThread(function()
        local lastMinute, nextShake = nil, 0
        while active and generation == version do
            local now = GetGameTimer()
            local remaining = active.deadline - now
            if remaining <= 0 then break end
            applyRainPhase(remaining)

            local minute = math.ceil(remaining / 60000)
            if minute ~= lastMinute then
                lastMinute = minute
                alertMinute(minute)
            end

            local powerOff = quakePowerOff(remaining)
            if powerOff ~= nil then
                keepVehicleLightsEnabled()
                -- Reaplica enquanto o efeito ocorre: outro recurso pode controlar
                -- as luzes sem que este passe a depender dele.
                SetArtificialLightsState(powerOff or otherBlackoutActive())
            end

            if remaining <= (tonumber(OBEarthquakeConfig.ShakeStartsAtSeconds) or 60) * 1000
                and now >= nextShake then
                ShakeGameplayCam(OBEarthquakeConfig.Shake, OBEarthquakeConfig.Intensity)
                nextShake = now + math.max(100, tonumber(OBEarthquakeConfig.ShakeIntervalMs) or 3000)
            end
            Wait(math.min(150, math.max(1, remaining)))
        end
        if generation == version then stop() end
    end)
end)

CreateThread(function()
    while LocalPlayer.state['or:loaded'] ~= true do Wait(500) end
    TriggerServerEvent('ob_earthquake:server:requestSync')
end)

AddEventHandler('onClientResourceStart', function(name)
    if name == 'ob_weather' and active then weatherOverride(active.weather) end
end)
AddEventHandler('onClientResourceStop', function(name)
    if name == GetCurrentResourceName() then stop() end
end)
