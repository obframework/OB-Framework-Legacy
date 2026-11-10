local validWeather = {
    EXTRASUNNY = true, CLEAR = true, NEUTRAL = true, SMOG = true, FOGGY = true,
    OVERCAST = true, CLOUDS = true, CLEARING = true, RAIN = true, THUNDER = true,
    SNOW = true, BLIZZARD = true, SNOWLIGHT = true, XMAS = true, HALLOWEEN = true,
}

local aliases = {
    sol = 'EXTRASUNNY', ensolarado = 'EXTRASUNNY', extrasunny = 'EXTRASUNNY',
    limpo = 'CLEAR', clear = 'CLEAR', neutro = 'NEUTRAL', neutral = 'NEUTRAL',
    fumaca = 'SMOG', smog = 'SMOG', neblina = 'FOGGY', foggy = 'FOGGY',
    nublado = 'CLOUDS', clouds = 'CLOUDS', encoberto = 'OVERCAST', overcast = 'OVERCAST',
    abrindo = 'CLEARING', clearing = 'CLEARING', chuva = 'RAIN', rain = 'RAIN',
    tempestade = 'THUNDER', thunder = 'THUNDER', neve = 'SNOW', snow = 'SNOW',
    nevasca = 'BLIZZARD', blizzard = 'BLIZZARD', natal = 'XMAS', xmas = 'XMAS',
    halloween = 'HALLOWEEN',
}

local state = {
    weather = OBWeatherConfig.defaultWeather or 'EXTRASUNNY',
    hour = tonumber(OBWeatherConfig.defaultHour) or 12,
    minute = tonumber(OBWeatherConfig.defaultMinute) or 0,
    freezeClock = OBWeatherConfig.freezeClock ~= false,
    anchor = GetGameTimer(),
}

local function gameMinuteMilliseconds()
    return math.max(250, math.floor((tonumber(OBWeatherConfig.secondsPerGameMinute) or 2.0) * 1000))
end

local function currentClock()
    local minuteMilliseconds = gameMinuteMilliseconds()
    local elapsed = state.freezeClock and 0 or math.max(0, GetGameTimer() - state.anchor)
    local elapsedMinutes = math.floor(elapsed / minuteMilliseconds)
    local totalMinutes = ((state.hour * 60) + state.minute + elapsedMinutes) % 1440
    return math.floor(totalMinutes / 60), totalMinutes % 60, elapsed % minuteMilliseconds
end

exports('GetClock', function()
    local hour, minute, minuteProgress = currentClock()
    return {
        hour = hour,
        minute = minute,
        minuteProgress = minuteProgress,
        freezeClock = state.freezeClock,
        secondsPerGameMinute = tonumber(OBWeatherConfig.secondsPerGameMinute) or 2.0,
    }
end)

local function reanchorClock()
    local hour, minute, minuteProgress = currentClock()
    state.hour, state.minute = hour, minute
    state.anchor = GetGameTimer() - minuteProgress
    return hour, minute, minuteProgress
end

local function notify(source, message, kind)
    if source == 0 then return print(('[ob_weather] %s'):format(message)) end
    TriggerClientEvent('ob_notification:client:notify', source, message, kind or 'info')
end

local function can(source, permission)
    return source == 0 or exports.ob_admin:HasPermission(source, permission) == true
end

local function sync(target)
    local hour, minute, minuteProgress = reanchorClock()
    TriggerClientEvent('ob_weather:client:sync', target or -1, {
        weather = state.weather,
        hour = hour,
        minute = minute,
        minuteProgress = minuteProgress,
        freezeClock = state.freezeClock,
        secondsPerGameMinute = tonumber(OBWeatherConfig.secondsPerGameMinute) or 2.0,
    })
end

local function resolveWeather(value)
    local name = tostring(value or ''):upper()
    if validWeather[name] then return name end
    return aliases[tostring(value or ''):lower()]
end

RegisterCommand('clima', function(source, args)
    if not can(source, 'world.weather') then return notify(source, 'Sem permissao para alterar o clima.', 'error') end
    local weather = resolveWeather(args[1])
    if not weather then
        return notify(source, 'Uso: /clima sol, nublado, chuva, tempestade, neblina, neve...', 'error')
    end
    state.weather = weather
    sync()
    notify(source, ('Clima alterado para %s. Transicao iniciada.'):format(weather), 'success')
end, false)

RegisterCommand('time', function(source, args)
    if not can(source, 'world.time') then return notify(source, 'Sem permissao para alterar o horario.', 'error') end
    local hour, minute = math.floor(tonumber(args[1]) or -1), math.floor(tonumber(args[2]) or 0)
    if hour < 0 or hour > 23 or minute < 0 or minute > 59 then
        return notify(source, 'Uso: /time [hora 0-23] [minuto 0-59]. Exemplo: /time 19 20', 'error')
    end
    state.hour, state.minute, state.anchor = hour, minute, GetGameTimer()
    sync()
    local behavior = state.freezeClock and 'fixado' or 'ciclo iniciado'
    notify(source, ('Horario alterado para %02d:%02d (%s).'):format(hour, minute, behavior), 'success')
end, false)

RegisterNetEvent('ob_weather:server:requestSync', function()
    sync(source)
end)

AddEventHandler('ob_core:server:playerSpawned', function(source)
    sync(source)
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then sync() end
end)

CreateThread(function()
    local interval = math.max(5, math.floor(tonumber(OBWeatherConfig.resyncIntervalSeconds) or 30)) * 1000
    while true do
        Wait(interval)
        sync()
    end
end)
