local helpText
local helpOwner = GetCurrentResourceName()

RegisterNUICallback('ob_lib_currency', function(_, callback)
    callback(OR.GetCurrencyConfig())
end)

function OR.Notify(message, notificationType, duration)
    if GetResourceState('ob_notification') == 'started' then
        TriggerEvent('ob_notification:client:notify', tostring(message), notificationType or 'info', duration)
        return true
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(('[%s] %s'):format(notificationType or 'info', tostring(message)))
    EndTextCommandThefeedPostTicker(false, false)
    return true
end

function OR.Progress.Run(data)
    data = type(data) == 'table' and data or {}
    local animation = data.animation or data.anim
    return exports.ob_lib:Progress({
        label = data.label or OR.Locale('common.processing'),
        duration = data.duration or 2500,
        animation = animation and { dict = animation.dict, clip = animation.clip, flag = animation.flag } or nil,
        canCancel = data.canCancel == true,
        cancelControl = data.cancelControl,
    })
end

function OR.Help.Show(text)
    local value = tostring(text or '')
    if value == '' then return OR.Help.Hide() end
    helpText = value
    TriggerEvent('ob_lib:client:help:show', value, helpOwner)
end

function OR.Help.Hide()
    if helpText == nil then return end
    helpText = nil
    TriggerEvent('ob_lib:client:help:hide', helpOwner)
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == helpOwner and helpText ~= nil then
        TriggerEvent('ob_lib:client:help:hide', helpOwner)
    end
end)

function OR.Dialog.Confirm(data)
    data = type(data) == 'table' and data or {}
    local header = data.title or data.header or 'Confirmacao'
    local message = data.message or data.content or ''
    local timeout = math.max(1000, math.floor(tonumber(data.timeout) or 7000))
    OR.Notify(('%s: %s\nPressione Y para confirmar ou N para cancelar.'):format(header, message), 'info', timeout)
    local deadline = GetGameTimer() + timeout
    while GetGameTimer() < deadline do
        DisableControlAction(0, 246, true)
        DisableControlAction(0, 249, true)
        if IsDisabledControlJustReleased(0, 246) then return true end
        if IsDisabledControlJustReleased(0, 249) then return false end
        Wait(0)
    end
    return false
end
