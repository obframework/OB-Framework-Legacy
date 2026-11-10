local open = false

local function closePanel()
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function openPanel()
    if open then return end
    local data, errorMessage = OR.Callback.await('panel')
    if not data then
        TriggerEvent('ob_notification:client:notify', errorMessage or 'Painel economico indisponivel.', 'error')
        return
    end
    open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data })
end

RegisterCommand(OBEconomyConfig.Command or 'economia', openPanel, false)

RegisterNUICallback('close', function(_, cb)
    closePanel()
    cb({ ok = true })
end)

RegisterNUICallback('refresh', function(data, cb)
    local result, errorMessage = OR.Callback.await('panel', type(data) == 'table' and data or {})
    cb({ ok = result ~= nil, data = result, error = errorMessage })
end)

RegisterNUICallback('adjust', function(data, cb)
    local success, message, panel = OR.Callback.await('adjust', type(data) == 'table' and data or {})
    cb({ ok = success == true, message = message, data = panel })
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        SetNuiFocus(false, false)
    end
end)
