local weather, freezeClock
local earthquakeWeather
local clockInitialized = false
local weatherGeneration = 0
local secondsPerGameMinute = math.max(0.25, tonumber(OBWeatherConfig.secondsPerGameMinute) or 2.0)

local function minuteMilliseconds()
    return math.max(250, math.floor(secondsPerGameMinute * 1000))
end

local function clockSeconds(hour, minute, second)
    return ((hour * 3600) + (minute * 60) + second) % 86400
end

local function clockDistance(first, second)
    local difference = math.abs(first - second) % 86400
    return math.min(difference, 86400 - difference)
end

local function applyClock(data)
    local expectedHour = math.max(0, math.min(23, math.floor(tonumber(data.hour) or 12)))
    local expectedMinute = math.max(0, math.min(59, math.floor(tonumber(data.minute) or 0)))

    freezeClock = data.freezeClock ~= false
    secondsPerGameMinute = math.max(
        0.25,
        tonumber(data.secondsPerGameMinute) or tonumber(OBWeatherConfig.secondsPerGameMinute) or 2.0
    )

    local gameMinuteMs = minuteMilliseconds()
    local minuteProgress = math.max(0, math.min(gameMinuteMs - 1, tonumber(data.minuteProgress) or 0))
    local expectedSecond = freezeClock and 0 or math.floor((minuteProgress / gameMinuteMs) * 60)

    -- O proprio relogio do jogo interpola os segundos e o movimento do sol.
    -- Reaplicar NetworkOverrideClockTime em um loop fazia o sol saltar.
    if type(NetworkOverrideClockMillisecondsPerGameMinute) == 'function' then
        NetworkOverrideClockMillisecondsPerGameMinute(gameMinuteMs)
    end

    PauseClock(freezeClock)

    local current = clockSeconds(GetClockHours(), GetClockMinutes(), GetClockSeconds())
    local expected = clockSeconds(expectedHour, expectedMinute, expectedSecond)
    local correctionThreshold = math.max(1, tonumber(OBWeatherConfig.clockCorrectionThresholdSeconds) or 5)

    if not clockInitialized or freezeClock or clockDistance(current, expected) > correctionThreshold then
        NetworkOverrideClockTime(expectedHour, expectedMinute, expectedSecond)
    end

    clockInitialized = true
end

local function restoreBaseWeather()
    ClearOverrideWeather()
    if weather then SetWeatherTypeNowPersist(weather) end
end

local function applyWeather(name)
    name = type(name) == 'string' and name:upper() or 'EXTRASUNNY'

    -- A sincronizacao periodica tambem reafirma o clima persistente. Isso evita
    -- que o ciclo local do GTA derive para chuva em apenas alguns clientes.
    if weather == name then
        if not earthquakeWeather then SetWeatherTypeNowPersist(name) end
        return
    end

    local firstSync = weather == nil
    weather = name
    weatherGeneration = weatherGeneration + 1
    local generation = weatherGeneration

    if not earthquakeWeather then ClearOverrideWeather() end
    ClearWeatherTypePersist()

    -- Ao entrar, nao herda por alguns segundos o clima aleatorio local do GTA.
    -- Depois da primeira sincronizacao, mudancas administrativas usam transicao.
    if firstSync then
        SetWeatherTypeNowPersist(name)
        return
    end

    local transitionSeconds = math.max(0.0, tonumber(OBWeatherConfig.transitionSeconds) or 15.0)
    if transitionSeconds > 0.0 then
        SetWeatherTypeOvertimePersist(name, transitionSeconds)
    else
        SetWeatherTypeNowPersist(name)
    end

    CreateThread(function()
        if transitionSeconds > 0.0 then Wait(math.floor(transitionSeconds * 1000)) end
        if weatherGeneration == generation and weather == name and not earthquakeWeather then
            SetWeatherTypeNowPersist(name)
        end
    end)
end

-- Override local temporario; o clima e o relogio do servidor continuam intactos.
exports('SetEarthquakeWeather', function(name)
    if GetInvokingResource() ~= 'ob_earthquake' then return false end

    earthquakeWeather = type(name) == 'string' and name:upper() or nil
    if earthquakeWeather then
        SetOverrideWeather(earthquakeWeather)
    else
        restoreBaseWeather()
    end
    return true
end)

AddEventHandler('onClientResourceStop', function(name)
    if name == 'ob_earthquake' then
        earthquakeWeather = nil
        restoreBaseWeather()
    end
end)

RegisterNetEvent('ob_weather:client:sync', function(data)
    if type(data) ~= 'table' then return end
    applyWeather(data.weather or OBWeatherConfig.defaultWeather or 'EXTRASUNNY')
    applyClock(data)
end)

CreateThread(function()
    while LocalPlayer.state['or:loaded'] ~= true do Wait(250) end
    TriggerServerEvent('ob_weather:server:requestSync')
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    if OBWeatherConfig.freezeOnResourceStop ~= false then
        NetworkOverrideClockTime(GetClockHours(), GetClockMinutes(), GetClockSeconds())
        PauseClock(true)
    else
        NetworkClearClockTimeOverride()
        PauseClock(false)
    end
end)
