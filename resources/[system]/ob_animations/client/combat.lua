local combatConfig = OBAnimationsConfig.Combat or {}
local crouched = false
local crouchMove = 'move_ped_crouched'
local crouchStrafe = 'move_ped_crouched_strafing'

local function applyCoverRestriction()
    if combatConfig.DisableCover ~= false then
        SetPlayerCanUseCover(PlayerId(), false)
    end
end

-- O bloqueio do controle precisa ocorrer em todos os frames: o GTA permite
-- entrar em cobertura mesmo desarmado. A native do jogador reforca a regra
-- apos cada spawn, enquanto o Q continua disponivel para NUI e key mappings.
CreateThread(function()
    if combatConfig.DisableCover == false then return end
    while not NetworkIsPlayerActive(PlayerId()) do Wait(250) end
    applyCoverRestriction()
    while true do
        DisableControlAction(0, 44, true)
        Wait(0)
    end
end)

AddEventHandler('playerSpawned', applyCoverRestriction)

local function loadMovementSet(name)
    RequestAnimSet(name)
    local deadline = GetGameTimer() + 5000
    while not HasAnimSetLoaded(name) and GetGameTimer() < deadline do Wait(0) end
    return HasAnimSetLoaded(name)
end

local function canCrouch(ped)
    return ped and ped ~= 0 and not IsEntityDead(ped) and not IsPedInAnyVehicle(ped, false)
        and not IsPedRagdoll(ped) and not IsPedFalling(ped)
        and LocalPlayer.state['or:downed'] ~= true
        and LocalPlayer.state['or:restrained'] ~= true
        and LocalPlayer.state['ob:restrained'] ~= true
        and LocalPlayer.state['ob:takedown'] ~= true
end

local function setCrouched(enabled)
    local ped = PlayerPedId()
    enabled = enabled == true and canCrouch(ped)
    if crouched == enabled then return end
    crouched = enabled
    SetPedStealthMovement(ped, false, 'DEFAULT_ACTION')
    if enabled then
        if not loadMovementSet(crouchMove) or not loadMovementSet(crouchStrafe) then
            crouched = false
            return
        end
        SetPedMovementClipset(ped, crouchMove, 0.35)
        SetPedWeaponMovementClipset(ped, crouchMove)
        SetPedStrafeClipset(ped, crouchStrafe)
    else
        ResetPedMovementClipset(ped, 0.35)
        ResetPedWeaponMovementClipset(ped)
        ResetPedStrafeClipset(ped)
    end
end

-- O nome v3 impede que o bind v2 salvo no C continue ativo. O Ctrl nativo e
-- bloqueado no mesmo frame para nao executar a postura furtiva do GTA.
RegisterCommand('+ob_crouch_v3', function()
    DisableControlAction(0, 36, true)
    setCrouched(not crouched)
end, false)
RegisterCommand('-ob_crouch_v3', function() end, false)
RegisterKeyMapping('+ob_crouch_v3', 'Agachar ou levantar', 'keyboard', combatConfig.CrouchKey or 'LCONTROL')

CreateThread(function()
    while true do
        if crouched then
            local ped = PlayerPedId()
            if not canCrouch(ped) then
                setCrouched(false)
                Wait(100)
            else
                -- Impede a furtividade nativa no Ctrl enquanto o clipset de
                -- agachado controla a postura e a arma. O C fica livre.
                DisableControlAction(0, 36, true)
                Wait(0)
            end
        else
            Wait(250)
        end
    end
end)

local function hasFirearm(ped)
    local weapon = GetSelectedPedWeapon(ped)
    if weapon == joaat('WEAPON_UNARMED') then return false end
    local ok, group = pcall(GetWeapontypeGroup, weapon)
    return ok and group ~= joaat('GROUP_UNARMED') and group ~= joaat('GROUP_MELEE')
end

CreateThread(function()
    local aimWasPressed = false
    while true do
        local ped = PlayerPedId()
        if hasFirearm(ped) and not IsPedInAnyVehicle(ped, false) then
            if combatConfig.DisableFirearmMelee ~= false then
                DisableControlAction(0, 140, true)
                DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true)
                DisableControlAction(0, 143, true)
            end

            local aiming
            if combatConfig.ForceHoldAim ~= false then
                -- Ignora o modo "Toggle Aim" salvo no perfil do jogador. O
                -- controle desabilitado ainda permite ler o botao fisico e a
                -- mira forcada existe somente enquanto ele estiver segurado.
                DisableControlAction(0, 25, true)
                aiming = not IsPauseMenuActive()
                    and not IsNuiFocused()
                    and IsDisabledControlPressed(0, 25)
                SetPlayerForcedAim(PlayerId(), aiming)
            else
                aiming = IsControlPressed(0, 25) or IsDisabledControlPressed(0, 25)
            end

            if combatConfig.ReleaseAimWithMouse ~= false and aimWasPressed and not aiming then
                SetPlayerForcedAim(PlayerId(), false)
                SetPedUsingActionMode(ped, false, -1, 'DEFAULT_ACTION')
                ClearPedSecondaryTask(ped)
            end
            aimWasPressed = aiming
            Wait(0)
        else
            if aimWasPressed then SetPlayerForcedAim(PlayerId(), false) end
            aimWasPressed = false
            Wait(250)
        end
    end
end)

AddEventHandler('onClientResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    if combatConfig.DisableCover ~= false then SetPlayerCanUseCover(PlayerId(), true) end
    if crouched then
        local ped = PlayerPedId()
        ResetPedMovementClipset(ped, 0.0)
        ResetPedWeaponMovementClipset(ped)
        ResetPedStrafeClipset(ped)
    end
end)
