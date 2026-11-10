local resource = GetCurrentResourceName()
local appId = 'cidade.emergencia'
local sending = false

local app = {
    id = appId,
    name = 'Emergencia',
    description = 'Solicite atendimento policial ou medico.',
    developer = 'Cidade',
    version = '1.0.0',
    category = 'servicos',
    icon = 'phone/icon.svg',
    entry = 'phone/index.html',
    defaultInstalled = true,
    removable = false,
}

local function registerApp()
    if GetResourceState('ob_phone') ~= 'started' then return end
    local ok, registered, reason = pcall(function() return exports.ob_phone:AddApp(app) end)
    if not ok or registered ~= true then
        print(('[ob_dispatch] Nao foi possivel registrar o app Emergencia: %s'):format(tostring(reason or registered)))
    end
end

local function sendStatus(payload)
    if GetResourceState('ob_phone') == 'started' then exports.ob_phone:SendAppMessage(appId, payload) end
end

AddEventHandler('ob_phone:client:appsReady', registerApp)

AddEventHandler('onClientResourceStart', function(name)
    if name == resource or name == 'ob_phone' then Wait(400); registerApp() end
end)

AddEventHandler('ob_phone:client:appEvent', function(owner, incomingAppId, event, payload)
    if owner ~= resource or incomingAppId ~= appId or event ~= 'request' or sending then return end
    local service = type(payload) == 'table' and tostring(payload.service or '') or ''
    local message = type(payload) == 'table' and tostring(payload.message or '') or ''
    if service ~= 'police' and service ~= 'ambulance' then return end
    sending = true
    sendStatus({ state = 'sending' })
    CreateThread(function()
        local ok, result = OR.Callback.await('phoneRequest', service, message)
        sending = false
        sendStatus({ state = ok and 'sent' or 'error', message = result })
    end)
end)
