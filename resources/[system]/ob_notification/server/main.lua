local function validSource(playerSource)
    playerSource = tonumber(playerSource)
    return playerSource and playerSource > 0 and GetPlayerName(playerSource) and playerSource or nil
end

local function notify(playerSource, message, notificationType, duration)
    playerSource = validSource(playerSource)
    if not playerSource or type(message) ~= 'string' or message == '' then return false end
    TriggerClientEvent('ob_notification:client:notify', playerSource, message:sub(1, 300), notificationType or 'info', duration)
    return true
end

RegisterNetEvent('ob_notification:server:notify', function(message, notificationType, duration)
    if not OR.Security.rateLimit(source, 'notification:self', 8, 10000) then return end
    notify(source, message, notificationType, duration)
end)

exports('Notify', notify)
