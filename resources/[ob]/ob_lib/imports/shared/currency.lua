local DEFAULT_CURRENCY = {
    code = 'USD', locale = 'en-US', symbol = '$', symbolPosition = 'before',
    spaceBetween = false, decimals = 0, thousandsSeparator = ',', decimalSeparator = '.',
}

local function currencyConfig()
    local value = {}
    local raw = LoadResourceFile('ob_lib', 'currency.json')
    if type(raw) == 'string' and raw ~= '' then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then value = decoded end
    end
    local decimals = math.max(0, math.min(4, math.floor(tonumber(value.decimals) or DEFAULT_CURRENCY.decimals)))
    return {
        code = type(value.code) == 'string' and value.code ~= '' and value.code or DEFAULT_CURRENCY.code,
        locale = type(value.locale) == 'string' and value.locale ~= '' and value.locale or DEFAULT_CURRENCY.locale,
        symbol = type(value.symbol) == 'string' and value.symbol ~= '' and value.symbol or DEFAULT_CURRENCY.symbol,
        symbolPosition = value.symbolPosition == 'after' and 'after' or 'before',
        spaceBetween = value.spaceBetween == true,
        decimals = decimals,
        thousandsSeparator = type(value.thousandsSeparator) == 'string' and value.thousandsSeparator or DEFAULT_CURRENCY.thousandsSeparator,
        decimalSeparator = type(value.decimalSeparator) == 'string' and value.decimalSeparator or DEFAULT_CURRENCY.decimalSeparator,
    }
end

OR.Currency = currencyConfig()

function OR.GetCurrencyConfig()
    return OR.Copy(OR.Currency)
end

function OR.FormatMoney(value)
    value = tonumber(value) or 0
    local config = OR.Currency or DEFAULT_CURRENCY
    local decimals = math.max(0, math.min(4, math.floor(tonumber(config.decimals) or 0)))
    local factor = 10 ^ decimals
    local rounded = math.floor((math.abs(value) * factor) + 0.5) / factor
    local raw = string.format(('%.' .. decimals .. 'f'), rounded)
    local integer, fraction = raw:match('^(%d+)%.?(%d*)$')
    local groups = {}
    integer = integer or '0'
    while #integer > 3 do
        table.insert(groups, 1, integer:sub(-3))
        integer = integer:sub(1, -4)
    end
    table.insert(groups, 1, integer)
    local grouped = table.concat(groups, tostring(config.thousandsSeparator or ','))
    if decimals > 0 then grouped = grouped .. tostring(config.decimalSeparator or '.') .. (fraction or '') end
    local sign, symbol = value < 0 and '-' or '', tostring(config.symbol or '$')
    local spacing = config.spaceBetween == true and ' ' or ''
    if config.symbolPosition == 'after' then return sign .. grouped .. spacing .. symbol end
    return sign .. symbol .. spacing .. grouped
end
