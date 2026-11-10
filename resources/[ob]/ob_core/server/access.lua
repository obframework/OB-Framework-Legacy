local function developmentModeEnabled()
    return GetConvar('ob_development_mode', 'false'):lower() == 'true'
end

local function hasFiveMIdentifier(source)
    for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
        if identifier:sub(1, 6) == 'fivem:' then return true end
    end
    return false
end

AddEventHandler('playerConnecting', function(_, _, deferrals)
    if not developmentModeEnabled() then return end

    local source = source
    deferrals.defer()
    Wait(0)
    deferrals.update('Verificando autorizacao de desenvolvimento...')
    Wait(0)

    if hasFiveMIdentifier(source) and IsPlayerAceAllowed(source, 'or.developer') then
        deferrals.done()
        return
    end

    deferrals.done('Servidor em desenvolvimento. Seu identifier.fivem nao esta autorizado para entrar.')
end)
