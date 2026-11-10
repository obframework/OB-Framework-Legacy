local function validSource(value)
    value = tonumber(value)
    return value and value > 0 and GetPlayerName(value) and value or nil
end

local function setHandsUp(playerSource, enabled)
    playerSource = validSource(playerSource)
    if not playerSource then return end

    enabled = enabled == true
    if enabled then
        local state = Player(playerSource).state
        if state['or:loaded'] ~= true
            or state['or:downed'] == true
            or state['or:restrained'] == true
            or state['ob:restrained'] == true
            or state['ob:takedown'] == true then
            enabled = false
        end
    end

    Player(playerSource).state:set('ob:handsUp', enabled, true)
end

RegisterNetEvent('ob_animations:server:setHandsUp', function(enabled)
    local playerSource = validSource(source)
    if not playerSource or type(enabled) ~= 'boolean' then return end
    if enabled and OR.Security and OR.Security.rateLimit
        and not OR.Security.rateLimit(playerSource, 'animations:handsup', 8, 5000) then
        return
    end
    setHandsUp(playerSource, enabled)
end)

AddEventHandler('playerDropped', function()
    local playerSource = validSource(source)
    if playerSource then setHandsUp(playerSource, false) end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, value in ipairs(GetPlayers()) do
        setHandsUp(value, false)
    end
end)
