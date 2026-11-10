local app = {
    id = 'cidade.exemplo',
    name = 'Exemplo',
    description = 'Modelo para criar novos aplicativos.',
    developer = 'Cidade OB',
    version = '1.0.0',
    category = 'utilidades',
    icon = 'web/icon.svg',
    entry = 'web/index.html',
    defaultInstalled = false,
    removable = true
}

local function registerApp()
    exports.ob_phone:AddApp(app)
end

AddEventHandler('ob_phone:client:appsReady', registerApp)

AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'ob_phone' then registerApp() end
end)

AddEventHandler('ob_phone:client:appEvent', function(owner, appId, event, payload)
    if owner ~= GetCurrentResourceName() or appId ~= app.id then return end
    if event ~= 'save' then return end

    exports.ob_phone:SendAppMessage(app.id, {
        saved = true,
        text = tostring(payload and payload.text or '')
    })
end)
