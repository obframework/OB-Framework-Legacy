local handsUp = false
local pointing = false
local pointingStopping = false
local pointingStartedAt = 0
local pointingStopToken = 0
local menuOpen = false
local currentAnimation
local animationToken = 0

local function notify(message, kind)
    if OR and OR.Notify then OR.Notify(message, kind or 'info') end
end

local function currentPed()
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    return ped
end

local function isRestrained()
    return LocalPlayer.state['or:restrained'] == true
        or LocalPlayer.state['ob:restrained'] == true
end

local function canAnimate()
    local ped = currentPed()
    return ped
        and LocalPlayer.state['or:loaded'] == true
        and LocalPlayer.state['or:downed'] ~= true
        and LocalPlayer.state['ob:takedown'] ~= true
        and not isRestrained()
        and not IsEntityDead(ped)
        and not IsPedInAnyVehicle(ped, false)
end

local function loadAnimDict(dict)
    if type(dict) ~= 'string' or dict == '' then return false end
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(0) end
    return HasAnimDictLoaded(dict)
end

local function stopCurrentAnimation()
    animationToken = animationToken + 1
    local ped = currentPed()
    if ped and currentAnimation
        and IsEntityPlayingAnim(ped, currentAnimation.dict, currentAnimation.clip, 3) then
        StopAnimTask(ped, currentAnimation.dict, currentAnimation.clip, 2.0)
    end
    currentAnimation = nil
end

local function setHandsUp(enabled)
    enabled = enabled == true and canAnimate() and not pointing
    if handsUp == enabled then return end
    handsUp = enabled
    TriggerServerEvent('ob_animations:server:setHandsUp', enabled)

    local ped = currentPed()
    local animation = OBAnimationsConfig.HandsUp or {}
    if not ped then return end
    if enabled then
        stopCurrentAnimation()
        SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
        if loadAnimDict(animation.dict or 'missminuteman_1ig_2') then
            TaskPlayAnim(
                ped,
                animation.dict or 'missminuteman_1ig_2',
                animation.clip or 'handsup_base',
                8.0, -8.0, -1, tonumber(animation.flag) or 49,
                0.0, false, false, false
            )
        end
    elseif IsEntityPlayingAnim(
        ped,
        animation.dict or 'missminuteman_1ig_2',
        animation.clip or 'handsup_base',
        3
    ) then
        StopAnimTask(
            ped,
            animation.dict or 'missminuteman_1ig_2',
            animation.clip or 'handsup_base',
            2.0
        )
    end
end

exports('IsHandsUp', function() return handsUp end)

local function finishPointing(ped, token)
    if token ~= pointingStopToken or not ped or not DoesEntityExist(ped) then return end
    pointingStopping = false
    SetPedConfigFlag(ped, 36, false)
    SetPedCurrentWeaponVisible(ped, true, true, true, true)
end

local function stopPointing(immediate)
    if not pointing then
        if immediate ~= true or not pointingStopping then return end
        pointingStopToken = pointingStopToken + 1
        pointingStopping = false
        local interruptedPed = currentPed()
        if interruptedPed then
            if IsTaskMoveNetworkActive(interruptedPed) then
                RequestTaskMoveNetworkStateTransition(interruptedPed, 'Stop')
            end
            SetPedConfigFlag(interruptedPed, 36, false)
            SetPedCurrentWeaponVisible(interruptedPed, true, true, true, true)
        end
        return
    end
    pointing = false
    pointingStopping = true
    pointingStartedAt = 0
    pointingStopToken = pointingStopToken + 1
    local token = pointingStopToken
    local ped = currentPed()
    if not ped then
        pointingStopping = false
        return
    end
    local taskActive = IsTaskMoveNetworkActive(ped)
    if taskActive then
        RequestTaskMoveNetworkStateTransition(ped, 'Stop')
    end
    if immediate == true or not taskActive then return finishPointing(ped, token) end

    -- A transicao Stop possui a animacao de abaixar o braco. Esperamos a
    -- tarefa concluir (com limite de seguranca) antes de restaurar a arma.
    CreateThread(function()
        local deadline = GetGameTimer() + 1000
        while token == pointingStopToken and DoesEntityExist(ped)
            and IsTaskMoveNetworkActive(ped) and GetGameTimer() < deadline do
            Wait(0)
        end
        finishPointing(ped, token)
    end)
end

local function startPointing()
    if pointing or pointingStopping or handsUp or not canAnimate() then return end
    local ped = currentPed()
    if not ped or not loadAnimDict('anim@mp_point') then return end
    stopCurrentAnimation()
    pointing = true
    pointingStartedAt = GetGameTimer()
    SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
    SetPedCurrentWeaponVisible(ped, false, true, true, true)
    SetPedConfigFlag(ped, 36, true)
    TaskMoveNetworkByName(ped, 'task_mp_pointing', 0.5, false, 'anim@mp_point', 24)
end

local function togglePointing()
    if pointing then return stopPointing() end
    startPointing()
end

local function closeMenu()
    if not menuOpen then return end
    menuOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
end

local function openMenu()
    if menuOpen then return closeMenu() end
    if not canAnimate() then return notify('Voce nao pode abrir os emotes nesse estado.', 'error') end
    setHandsUp(false)
    stopPointing()
    menuOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({
        action = 'open',
        emotes = OBAnimationsConfig.Emotes or {},
    })
end

local function findEmote(emoteId)
    for _, entry in ipairs(OBAnimationsConfig.Emotes or {}) do
        if entry.id == emoteId then return entry end
    end
end

local function playAnimationStep(step, token)
    if token ~= animationToken or not canAnimate() or type(step) ~= 'table'
        or not loadAnimDict(step.dict) then return false end
    local ped = currentPed()
    if not ped then return false end
    currentAnimation = { dict = step.dict, clip = step.clip }
    TaskPlayAnim(
        ped, step.dict, step.clip,
        tonumber(step.blendIn) or 8.0, tonumber(step.blendOut) or -8.0,
        tonumber(step.duration) or -1, tonumber(step.flag) or 49,
        0.0, false, false, false
    )
    return true
end

local function playEmote(emoteId)
    local entry = findEmote(emoteId)
    if not entry or not canAnimate() then return end
    setHandsUp(false)
    stopPointing()
    stopCurrentAnimation()
    local token = animationToken

    if type(entry.steps) == 'table' and #entry.steps > 0 then
        CreateThread(function()
            for _, step in ipairs(entry.steps) do
                if token ~= animationToken or not playAnimationStep(step, token) then return end
                local duration = math.max(250, tonumber(step.duration) or 2000)
                local deadline = GetGameTimer() + duration
                while token == animationToken and GetGameTimer() < deadline do Wait(50) end
                if token ~= animationToken then return end
                local ped = currentPed()
                if ped and currentAnimation then
                    StopAnimTask(ped, currentAnimation.dict, currentAnimation.clip, 2.0)
                end
            end
            if token == animationToken then currentAnimation = nil end
        end)
    else
        playAnimationStep(entry, token)
    end
end

RegisterCommand('+ob_handsup', function()
    if menuOpen then return end
    setHandsUp(not handsUp)
end, false)
RegisterCommand('-ob_handsup', function() end, false)
RegisterKeyMapping('+ob_handsup', 'Levantar ou abaixar as maos', 'keyboard', OBAnimationsConfig.HandsUpKey or 'X')

RegisterCommand('+ob_point', togglePointing, false)
RegisterCommand('-ob_point', function() end, false)
RegisterKeyMapping('+ob_point', 'Apontar ou parar de apontar', 'keyboard', OBAnimationsConfig.PointKey or 'B')

RegisterCommand(OBAnimationsConfig.MenuCommand or 'emotes', openMenu, false)
RegisterKeyMapping(
    OBAnimationsConfig.MenuCommand or 'emotes',
    'Abrir menu de emotes',
    'keyboard',
    OBAnimationsConfig.MenuKey or 'F3'
)

RegisterNUICallback('close', function(_, callback)
    callback({ ok = true })
    closeMenu()
end)

RegisterNUICallback('play', function(data, callback)
    callback({ ok = true })
    local emoteId = type(data) == 'table' and tostring(data.id or '') or ''
    closeMenu()
    playEmote(emoteId)
end)

RegisterNUICallback('stop', function(_, callback)
    callback({ ok = true })
    closeMenu()
    setHandsUp(false)
    stopPointing()
    stopCurrentAnimation()
end)

RegisterNetEvent('ob_animations:client:cancel', function()
    closeMenu()
    setHandsUp(false)
    stopPointing(true)
    stopCurrentAnimation()
end)

CreateThread(function()
    TriggerServerEvent('ob_animations:server:setHandsUp', false)
    while true do
        if handsUp then
            if not canAnimate() then
                setHandsUp(false)
                Wait(200)
            else
                local ped = currentPed()
                local animation = OBAnimationsConfig.HandsUp or {}
                local dict = animation.dict or 'missminuteman_1ig_2'
                local clip = animation.clip or 'handsup_base'
                if ped and not IsEntityPlayingAnim(ped, dict, clip, 3) and loadAnimDict(dict) then
                    TaskPlayAnim(
                        ped, dict, clip, 8.0, -8.0, -1,
                        tonumber(animation.flag) or 49, 0.0, false, false, false
                    )
                end
                DisablePlayerFiring(PlayerId(), true)
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                DisableControlAction(0, 37, true)
                DisableControlAction(0, 44, true)
                DisableControlAction(0, 140, true)
                DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true)
                Wait(0)
            end
        else
            Wait(250)
        end
    end
end)

CreateThread(function()
    while true do
        if pointing then
            if not canAnimate() then
                stopPointing(true)
                Wait(200)
            else
                local ped = currentPed()
                if not ped or (not IsTaskMoveNetworkActive(ped)
                    and GetGameTimer() - pointingStartedAt > 500) then
                    stopPointing()
                    Wait(100)
                else
                    local camPitch = GetGameplayCamRelativePitch()
                    camPitch = math.max(-70.0, math.min(42.0, camPitch))
                    camPitch = (camPitch + 70.0) / 112.0
                    local camHeading = GetGameplayCamRelativeHeading()
                    camHeading = math.max(-180.0, math.min(180.0, camHeading))
                    camHeading = (camHeading + 180.0) / 360.0
                    SetTaskMoveNetworkSignalFloat(ped, 'Pitch', camPitch)
                    SetTaskMoveNetworkSignalFloat(ped, 'Heading', (camHeading * -1.0) + 1.0)
                    SetTaskMoveNetworkSignalBool(ped, 'isBlocked', false)
                    SetTaskMoveNetworkSignalBool(ped, 'isFirstPerson', GetFollowPedCamViewMode() == 4)
                    DisablePlayerFiring(PlayerId(), true)
                    Wait(0)
                end
            end
        else
            Wait(250)
        end
    end
end)

CreateThread(function()
    while true do
        if currentAnimation and not canAnimate() then stopCurrentAnimation() end
        Wait(300)
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    closeMenu()
    setHandsUp(false)
    stopPointing(true)
    stopCurrentAnimation()
end)
