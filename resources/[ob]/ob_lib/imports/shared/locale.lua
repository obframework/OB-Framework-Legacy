local Locale = OR.Locale
if type(Locale) ~= 'table' then Locale = {} end

local translations = {}
local currentLocale = 'pt-BR'

local rawConfig = LoadResourceFile('ob_lib', 'locale.json')
if type(rawConfig) == 'string' and rawConfig ~= '' then
    local ok, decoded = pcall(json.decode, rawConfig)
    if ok and type(decoded) == 'table' and type(decoded.default) == 'string' and decoded.default ~= '' then
        currentLocale = decoded.default
    end
end

local function merge(target, source)
    for key, value in pairs(type(source) == 'table' and source or {}) do
        if type(value) == 'table' then
            target[key] = type(target[key]) == 'table' and target[key] or {}
            merge(target[key], value)
        else
            target[key] = value
        end
    end
end

local function resolve(key)
    local value = translations
    for part in tostring(key):gmatch('[^.]+') do
        if type(value) ~= 'table' then return nil end
        value = value[part]
    end
    return value
end

function Locale.Add(values)
    merge(translations, values)
end

function Locale.Load(resource, path)
    resource = type(resource) == 'string' and resource or GetCurrentResourceName()
    path = type(path) == 'string' and path or ('locales/%s.json'):format(currentLocale)
    local raw = LoadResourceFile(resource, path)
    if type(raw) ~= 'string' or raw == '' then return false, 'arquivo de idioma ausente' end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return false, 'arquivo de idioma invalido' end
    merge(translations, decoded)
    return true
end

function Locale.Set(locale)
    if type(locale) ~= 'string' or locale == '' then return false end
    currentLocale = locale
    return true
end

function Locale.Get()
    return currentLocale
end

function Locale.Translate(key, replacements)
    local value = resolve(key)
    if type(value) ~= 'string' then return tostring(key) end
    if type(replacements) == 'table' then
        value = value:gsub('{([%w_]+)}', function(name)
            local replacement = replacements[name]
            return replacement == nil and ('{%s}'):format(name) or tostring(replacement)
        end)
    end
    return value
end

setmetatable(Locale, { __call = function(_, key, replacements) return Locale.Translate(key, replacements) end })
OR.Locale = Locale
Locale.Load('ob_lib', ('locales/%s.json'):format(currentLocale))
