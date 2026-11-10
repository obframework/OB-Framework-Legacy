local Logger = OR.Logger
local webhooks = {}
local levels = { debug = 10, info = 20, warn = 30, error = 40 }
local minimumLevel = levels.info

local function encode(value)
    if value == nil then return '' end
    if type(value) == 'string' then return value end
    local ok, encoded = pcall(json.encode, value)
    return ok and encoded or tostring(value)
end

local function write(level, event, data)
    level = levels[level] and level or 'info'
    if levels[level] < minimumLevel then return false end
    local suffix = data == nil and '' or (' ' .. encode(data))
    local stamp = tostring(GetGameTimer())
    print(('[%s] [%s] [%s] %s%s'):format(stamp, level, GetCurrentResourceName(), tostring(event), suffix))
    return true
end

function Logger.SetLevel(level)
    if not levels[level] then return false end
    minimumLevel = levels[level]
    return true
end

function Logger.debug(event, data) return write('debug', event, data) end
function Logger.info(event, data) return write('info', event, data) end
function Logger.warn(event, data) return write('warn', event, data) end
function Logger.error(event, data) return write('error', event, data) end

function Logger.SetWebhook(channel, url)
    if not IsDuplicityVersion() then return false end
    if type(channel) ~= 'string' or channel == '' then return false end
    webhooks[channel] = type(url) == 'string' and url ~= '' and url or nil
    return true
end

function Logger.Discord(channel, title, data, color)
    if not IsDuplicityVersion() then return false, 'webhook disponivel apenas no servidor' end
    local url = webhooks[channel] or (type(channel) == 'string' and channel:match('^https://') and channel or nil)
    if not url then return false, 'webhook nao configurado' end
    local description = encode(data)
    if #description > 3800 then description = description:sub(1, 3800) .. '...' end
    PerformHttpRequest(url, function(status)
        status = tonumber(status) or 0
        if status < 200 or status >= 300 then Logger.warn('webhook recusado', { channel = channel, status = status }) end
    end, 'POST', json.encode({
        username = 'OB Framework',
        embeds = {{ title = tostring(title or 'Log'), description = ('```json\n%s\n```'):format(description), color = tonumber(color) or 3447003 }},
    }), { ['Content-Type'] = 'application/json' })
    return true
end

Logger.setLevel = Logger.SetLevel
Logger.setWebhook = Logger.SetWebhook
Logger.discord = Logger.Discord
