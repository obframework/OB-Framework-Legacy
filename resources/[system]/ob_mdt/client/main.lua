local opened = false
local opening = false
local currentData

local function closeMdt()
    if not opened then return end
    opened = false
    currentData = nil
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
end

local function displayMdt(data)
    currentData = data
    opened = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'open', payload = data })
end

local function openMdt(mode)
    if opened or opening then return end
    opening = true
    CreateThread(function()
        local data, errorMessage = OR.Callback.await('bootstrap', mode == 'lawyer' and 'lawyer' or 'police')
        opening = false
        if type(data) ~= 'table' or data.allowed ~= true then
            return OR.Notify(errorMessage or (data and data.message) or 'Você não possui acesso a este MDT.', 'error')
        end
        displayMdt(data)
        TriggerServerEvent('ob_mdt:server:trace', 'nui_message_sent')
    end)
end

RegisterNetEvent('ob_mdt:client:open', function(mode, data)
    TriggerServerEvent('ob_mdt:server:trace', 'client_event_received')
    if type(data) ~= 'table' or data.allowed ~= true then
        return OR.Notify('Não foi possível carregar os dados do MDT.', 'error')
    end
    displayMdt(data)
    TriggerServerEvent('ob_mdt:server:trace', 'nui_message_sent')
end)

-- O console integrado do Enhanced executa comandos locais. Mantemos também
-- os registros no servidor para compatibilidade com chat, RCON e Legacy.
RegisterCommand(OBMdtConfig.Commands.Police or 'mdt', function()
    openMdt('police')
end, false)

RegisterCommand(OBMdtConfig.Commands.Lawyer or 'adv', function()
    openMdt('lawyer')
end, false)

RegisterNUICallback('ready', function(_, callback)
    callback({ ok = true })
    TriggerServerEvent('ob_mdt:server:trace', 'nui_ready')
    if opened and currentData then
        SendNUIMessage({ action = 'open', payload = currentData })
    end
end)

RegisterNUICallback('trace', function(data, callback)
    TriggerServerEvent('ob_mdt:server:trace', data and data.stage or 'nui_trace')
    callback({ ok = true })
end)

RegisterNUICallback('close', function(_, callback)
    closeMdt()
    callback({ ok = true })
end)

local callbacks = {
    queryPerson = 'queryPerson',
    queryPlate = 'queryPlate',
    getHistory = 'getHistory',
    createRecord = 'createRecord',
    clearRecord = 'clearRecord',
    getClearAudit = 'getClearAudit',
}

for nuiName, callbackName in pairs(callbacks) do
    RegisterNUICallback(nuiName, function(payload, callback)
        local response, errorMessage = OR.Callback.await(callbackName, payload or {})
        callback(response or { ok = false, message = errorMessage or 'Servidor indisponível.' })
    end)
end

CreateThread(function()
    while true do
        if opened and IsControlJustReleased(0, 322) then closeMdt() end
        Wait(opened and 0 or 500)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        opening = false
        closeMdt()
    end
end)
