local active, scheduleVersion, runVersion = nil, 0, 0
local requests = {}

local function notify(src, message, kind)
    if src == 0 then print('[ob_earthquake] ' .. message)
    else TriggerClientEvent('ob_notification:client:notify', src, message, kind or 'info') end
end

local function sync(target)
    local remaining = active and math.max(0, active.endsAt - GetGameTimer()) or 0
    TriggerClientEvent('ob_earthquake:client:sync', target or -1,
        remaining > 0 and { remainingMs = remaining, kind = active.kind, id = active.id } or false)
end

local function stop()
    runVersion = runVersion + 1
    active = nil
    sync()
end

local function start(seconds, kind)
    seconds = math.max(1, math.min(OBEarthquakeConfig.MaxDuration, math.floor(seconds)))
    runVersion = runVersion + 1
    local version = runVersion
    active = { endsAt = GetGameTimer() + seconds * 1000, kind = kind, id = version }
    sync()
    print(('[ob_earthquake] Tremor iniciado: %s, %ss.'):format(kind, seconds))
    SetTimeout(seconds * 1000, function()
        if runVersion == version then stop() end
    end)
end

local function permitted(src)
    if src == 0 then return true end
    if GetResourceState('ob_admin') ~= 'started' then return false end
    local ok, allowed = pcall(function() return exports.ob_admin:HasPermission(src, OBEarthquakeConfig.Permission) end)
    return ok and allowed == true
end

RegisterCommand('terremoto', function(src, args)
    if not permitted(src) then return notify(src, 'Sem permissao para iniciar ou parar terremotos.', 'error') end
    if args[1] == 'parar' then
        scheduleVersion = scheduleVersion + 1
        stop()
        return notify(src, 'Terremoto encerrado. O reinicio do servidor nao foi cancelado.', 'success')
    end
    local seconds = args[1] and tonumber(args[1]) or OBEarthquakeConfig.DefaultDuration
    if not seconds or seconds ~= seconds or seconds < 1 or seconds > OBEarthquakeConfig.MaxDuration then
        return notify(src, ('Uso: /terremoto [1-%s segundos] ou /terremoto parar.'):format(OBEarthquakeConfig.MaxDuration), 'error')
    end
    if active then return notify(src, 'Ja existe um terremoto em andamento.', 'error') end
    start(seconds, 'manual')
end, false)

-- Eventos locais: clientes nao podem anunciar nem cancelar reinicios.
AddEventHandler('txAdmin:events:scheduledRestart', function(data)
    if (tonumber(source) or 0) > 0 or not OBEarthquakeConfig.Automatic or type(data) ~= 'table' then return end
    local seconds = tonumber(data.secondsRemaining)
    if not seconds or seconds ~= seconds or seconds <= 0 or seconds > 86400 then return end
    scheduleVersion = scheduleVersion + 1
    local version = scheduleVersion
    local duration = math.min(seconds, OBEarthquakeConfig.SecondsBeforeRestart)
    SetTimeout(math.max(0, seconds - duration) * 1000, function()
        if scheduleVersion ~= version then return end
        if active and active.kind == 'restart' then return end
        start(duration, 'restart')
    end)
end)

AddEventHandler('txAdmin:events:scheduledRestartSkipped', function()
    if (tonumber(source) or 0) > 0 then return end
    scheduleVersion = scheduleVersion + 1
    if active and active.kind == 'restart' then stop() end
end)

RegisterNetEvent('ob_earthquake:server:requestSync', function()
    local src, now = source, GetGameTimer()
    if requests[src] and now - requests[src] < 5000 then return end
    requests[src] = now
    sync(src)
end)
AddEventHandler('playerDropped', function() requests[source] = nil end)
AddEventHandler('ob_core:server:playerSpawned', function(src) sync(src) end)
