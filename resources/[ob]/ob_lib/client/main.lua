local nuiOwner
local progressActive = false
local helpOwner, helpText
local helpTouchedAt = 0

AddEventHandler('ob_lib:client:help:show', function(text, owner)
    text, owner = tostring(text or ''), tostring(owner or '')
    if text == '' or owner == '' then return end
    helpTouchedAt = GetGameTimer()
    if helpOwner == owner and helpText == text then return end
    helpOwner, helpText = owner, text
    SendNUIMessage({ action = 'help', visible = true, text = text })
end)

AddEventHandler('ob_lib:client:help:hide', function(owner)
    if helpOwner == nil or tostring(owner or '') ~= helpOwner then return end
    helpOwner, helpText = nil, nil
    SendNUIMessage({ action = 'help', visible = false })
end)

CreateThread(function()
    while true do
        if helpOwner and GetGameTimer() - helpTouchedAt > 2000 then
            helpOwner, helpText = nil, nil
            SendNUIMessage({ action = 'help', visible = false })
        end
        Wait(250)
    end
end)

exports('GetVersion', function()
    return '0.2.0'
end)

local function requestAnimation(animation)
    if type(animation) ~= 'table' or type(animation.dict) ~= 'string' or type(animation.clip) ~= 'string' then return nil end
    RequestAnimDict(animation.dict)
    local deadline = GetGameTimer() + 5000
    while not HasAnimDictLoaded(animation.dict) and GetGameTimer() < deadline do Wait(0) end
    return HasAnimDictLoaded(animation.dict) and animation or nil
end

exports('Progress', function(data)
    if progressActive then return false, 'Ja existe uma acao em andamento.' end
    data = type(data) == 'table' and data or {}
    local duration = math.max(250, math.floor(tonumber(data.duration) or 2500))
    local cancelControl = math.floor(tonumber(data.cancelControl) or 73)
    local ped = PlayerPedId()
    local animation = requestAnimation(data.animation)
    progressActive = true
    SendNUIMessage({ action = 'progress', open = true, label = data.label or 'Processando...', duration = duration })

    if animation then
        TaskPlayAnim(ped, animation.dict, animation.clip, 4.0, -4.0, duration, animation.flag or 49, 0.0, false, false, false)
    end

    local endsAt, completed = GetGameTimer() + duration, true
    while GetGameTimer() < endsAt do
        if IsEntityDead(ped) or LocalPlayer.state['or:downed'] == true
            or (data.canCancel == true and IsControlJustReleased(0, cancelControl)) then
            completed = false
            break
        end
        Wait(0)
    end

    if animation and DoesEntityExist(ped) then
        StopAnimTask(ped, animation.dict, animation.clip, 1.0)
        RemoveAnimDict(animation.dict)
    end
    SendNUIMessage({ action = 'progress', open = false })
    progressActive = false
    return completed, completed and nil or 'Acao cancelada.'
end)

exports('ClaimNui', function(resourceName, exclusive)
    if type(resourceName) ~= 'string' or resourceName == '' then return false end
    if exclusive ~= false and nuiOwner and nuiOwner ~= resourceName then
        TriggerEvent('ob_lib:client:nui:forceClose', nuiOwner, resourceName)
    end
    nuiOwner = resourceName
    return true
end)

exports('ReleaseNui', function(resourceName)
    if nuiOwner == resourceName then nuiOwner = nil return true end
    return false
end)

exports('GetNuiOwner', function()
    return nuiOwner
end)

AddEventHandler('onResourceStop', function(resourceName)
    if nuiOwner == resourceName then nuiOwner = nil end
    if helpOwner == resourceName then
        helpOwner, helpText = nil, nil
        SendNUIMessage({ action = 'help', visible = false })
    end
end)
