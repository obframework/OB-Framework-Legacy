local sequence = 0

-- Fica acima da HUD e do inventario. O atraso garante que o frame NUI exista.
CreateThread(function()
    for _ = 1, 3 do
        Wait(1000)
        if type(SetNuiZIndex) == 'function' then SetNuiZIndex(50) end
    end
end)

local function notify(message, notificationType, duration)
    if type(message) ~= 'string' or message == '' then return false end

    sequence = sequence + 1
    SendNUIMessage({
        action = 'notify',
        id = ('%s:%s'):format(GetGameTimer(), sequence),
        message = message:sub(1, 300),
        notificationType = type(notificationType) == 'string' and notificationType or 'info',
        duration = math.max(1500, math.min(15000, tonumber(duration) or 4500)),
    })
    return true
end

RegisterNetEvent('ob_notification:client:notify', function(message, notificationType, duration)
    notify(message, notificationType, duration)
end)

exports('Notify', notify)
