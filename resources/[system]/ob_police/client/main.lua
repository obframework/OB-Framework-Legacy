local restrained = false
local escortedBy
local escortTarget
local cuffProp
local cuffPropPed
local nextCuffPropCheck = 0
local searchTargetOption = 'ob_police:search_restrained'
local consentTargetOption = 'ob_police:request_search'
local pendingSearchConsent
local takedownBusy = false
local takedownModifierHeld = false
local takedownSprintUntil = 0
local takedownJumpUntil = 0

local function notify(message, kind)
    OR.Notify(message, kind or 'info')
end

local function isPoliceAvailable()
    local organisation = LocalPlayer.state['ob:org']
    return type(organisation) == 'table'
        and type(organisation.key) == 'string'
        and organisation.key:lower() == tostring(OBPoliceConfig.Permission or 'police'):lower()
        and (OBPoliceConfig.RequireDuty == false or organisation.onDuty == true)
end

exports('IsAvailable', isPoliceAvailable)

local function loadAnimDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(0) end
    return HasAnimDictLoaded(dict)
end

local function currentPed()
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    return ped
end

local function removeCuffProp()
    if cuffProp and DoesEntityExist(cuffProp) then
        SetEntityAsMissionEntity(cuffProp, true, true)
        DeleteObject(cuffProp)
        if DoesEntityExist(cuffProp) then DeleteEntity(cuffProp) end
    end
    cuffProp, cuffPropPed = nil, nil
end

local function ensureCuffProp(ped)
    local config = type(OBPoliceConfig.CuffProp) == 'table' and OBPoliceConfig.CuffProp or {}
    if config.enabled == false then return end
    if cuffProp and DoesEntityExist(cuffProp) and cuffPropPed == ped
        and IsEntityAttachedToEntity(cuffProp, ped) then return end

    removeCuffProp()
    local model = GetHashKey(config.model or 'p_cs_cuffs_02_s')
    if not IsModelInCdimage(model) or not IsModelValid(model) then return end
    RequestModel(model)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if not restrained or not HasModelLoaded(model) or not DoesEntityExist(ped) then
        SetModelAsNoLongerNeeded(model)
        return
    end

    local coords = GetEntityCoords(ped)
    local object = CreateObjectNoOffset(model, coords.x, coords.y, coords.z, true, true, false)
    SetModelAsNoLongerNeeded(model)
    if not object or object == 0 or not DoesEntityExist(object) then return end

    local position = type(config.position) == 'table' and config.position or {}
    local rotation = type(config.rotation) == 'table' and config.rotation or {}
    SetEntityCollision(object, false, false)
    AttachEntityToEntity(
        object, ped, GetPedBoneIndex(ped, tonumber(config.bone) or 18905),
        tonumber(position.x) or 0.0, tonumber(position.y) or 0.07, tonumber(position.z) or 0.03,
        tonumber(rotation.x) or 10.0, tonumber(rotation.y) or 115.0, tonumber(rotation.z) or -65.0,
        true, true, false, true, 1, true
    )
    cuffProp, cuffPropPed = object, ped
end

local function stopAnimation(ped, animation, fallbackDict, fallbackClip)
    animation = type(animation) == 'table' and animation or {}
    local dict, clip = animation.dict or fallbackDict, animation.clip or fallbackClip
    if dict and clip and IsEntityPlayingAnim(ped, dict, clip, 3) then
        StopAnimTask(ped, dict, clip, 2.0)
    end
end

local function applyRestrained(enabled)
    restrained = enabled == true
    local ped = currentPed()
    if not ped then return end
    SetEnableHandcuffs(ped, restrained)
    if restrained then
        SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
        ensureCuffProp(ped)
        if not IsPedInAnyVehicle(ped, false) and LocalPlayer.state['or:downed'] ~= true then
            local animation = OBPoliceConfig.CuffAnimation or {}
            local dict, clip = animation.dict or 'mp_arresting', animation.clip or 'idle'
            if loadAnimDict(dict) then
                TaskPlayAnim(ped, dict, clip, 8.0, -8.0, -1, tonumber(animation.flag) or 49, 0.0, false, false, false)
            end
        end
        TriggerEvent('ob_inventory:client:forceClose')
        TriggerEvent('ob_radiumenu:client:forceClose')
        TriggerEvent('ob_target:client:forceClose')
        TriggerEvent('ob_phone:client:forceClose')
        TriggerEvent('ob_minigame:client:cancel')
        TriggerEvent('ob_animations:client:cancel')
    else
        removeCuffProp()
        if LocalPlayer.state['or:downed'] ~= true then
            stopAnimation(ped, OBPoliceConfig.CuffAnimation, 'mp_arresting', 'idle')
            stopAnimation(ped, { dict = 'anim@move_m@prisoner_cuffed', clip = 'walk' })
            stopAnimation(ped, { dict = 'anim@move_m@trash', clip = 'run' })
        end
        SetPedCanPlayGestureAnims(ped, true)
    end
end

local function applyEscort(value)
    escortedBy = tonumber(value)
    local ped = currentPed()
    if ped then
        if escortedBy then
            SetPedCanRagdoll(ped, false)
            SetPedCanRagdollFromPlayerImpact(ped, false)
        else
            DetachEntity(ped, true, false)
            stopAnimation(ped, { dict = 'anim@move_m@prisoner_cuffed', clip = 'walk' })
            stopAnimation(ped, { dict = 'anim@move_m@trash', clip = 'run' })
            if LocalPlayer.state['or:downed'] ~= true then
                SetPedCanRagdoll(ped, true)
                SetPedCanRagdollFromPlayerImpact(ped, true)
            end
        end
    end
end

local function localStateBag(bagName)
    local player = GetPlayerFromStateBagName(bagName)
    return player and player == PlayerId()
end

AddStateBagChangeHandler('ob:restrained', nil, function(bagName, _, value)
    if localStateBag(bagName) then applyRestrained(value == true) end
end)

AddStateBagChangeHandler('ob:escortedBy', nil, function(bagName, _, value)
    if localStateBag(bagName) then applyEscort(value) end
end)

RegisterNetEvent('ob_police:client:escortChanged', applyEscort)

RegisterNetEvent('ob_police:client:cuffFeedback', function(enabled)
    applyRestrained(enabled == true)
    notify(enabled and 'Voce foi algemado.' or 'Voce foi desalgemado.', enabled and 'warning' or 'success')
end)

RegisterNetEvent('ob_police:client:restoreRestrained', function(enabled)
    applyRestrained(enabled == true)
    if enabled == true then
        notify('Voce continua algemado.', 'warning')
    end
end)

RegisterNetEvent('ob_police:client:useRestraintItem', function(itemName, targetSource, token)
    CreateThread(function()
        itemName, targetSource = tostring(itemName or ''), tonumber(targetSource)
        local targetPlayer = targetSource and GetPlayerFromServerId(targetSource) or -1
        local targetPed = targetPlayer >= 0 and GetPlayerPed(targetPlayer) or 0
        local myPed = PlayerPedId()
        local maximum = tonumber(OBPoliceConfig.InteractionDistance) or 3.0
        if targetPed == 0 or not DoesEntityExist(targetPed)
            or #(GetEntityCoords(myPed) - GetEntityCoords(targetPed)) > maximum
            or not HasEntityClearLosToEntity(myPed, targetPed, 17) then
            TriggerServerEvent('ob_police:server:itemUseResult', false, token)
            return
        end

        local items = type(OBPoliceConfig.Items) == 'table' and OBPoliceConfig.Items or {}
        local lockpick = type(items.Lockpicks) == 'table' and items.Lockpicks[itemName] == true
        local success = true
        if lockpick then
            if GetResourceState('ob_minigame') ~= 'started' then
                TriggerServerEvent('ob_police:server:itemUseResult', false, token)
                return notify('Minigame de lockpick indisponivel.', 'error')
            end
            local lockpickConfig = type(OBPoliceConfig.Lockpick) == 'table' and OBPoliceConfig.Lockpick or {}
            local difficulties = type(lockpickConfig.Difficulty) == 'table' and lockpickConfig.Difficulty or {}
            local difficulty = type(difficulties[itemName]) == 'table' and difficulties[itemName] or {}
            local ok, result = pcall(function() return exports.ob_minigame:Keypress({
                title = 'ARROMBAR ALGEMA',
                key = 'E',
                steps = tonumber(difficulty.steps) or 7,
                speed = tonumber(difficulty.speed) or 2.35,
                tolerance = tonumber(difficulty.tolerance) or 0.065,
                timeoutMs = math.max(5000, (tonumber(lockpickConfig.TimeoutMs) or 25000) - 1500),
            }) end)
            success = ok and result == true
        else
            local animation = type(OBPoliceConfig.CuffActionAnimation) == 'table'
                and OBPoliceConfig.CuffActionAnimation or {}
            local dict, clip = animation.dict or 'mp_arresting', animation.clip or 'a_uncuff'
            local duration = math.max(500, tonumber(animation.duration) or 1300)
            TaskTurnPedToFaceEntity(myPed, targetPed, 400)
            Wait(250)
            if loadAnimDict(dict) then
                TaskPlayAnim(myPed, dict, clip, 8.0, -8.0, duration, tonumber(animation.flag) or 49, 0.0, false, false, false)
                Wait(duration)
                stopAnimation(myPed, animation, 'mp_arresting', 'a_uncuff')
            end
        end
        TriggerServerEvent('ob_police:server:itemUseResult', success == true, token)
    end)
end)

local function openSearch(targetSource, callbackName, mode)
    CreateThread(function()
        local payload, errorMessage = OR.Callback.awaitResource('ob_police', callbackName, targetSource)
        if not payload then return notify(errorMessage or 'Nao foi possivel revistar.', 'error') end
        TriggerEvent('ob_inventory:client:openOtherInventory', {
            mode = mode,
            targetSource = tonumber(targetSource),
            label = payload.target and payload.target.name or 'Outra pessoa',
            userId = payload.target and payload.target.userId,
            inventory = payload.inventory,
            distance = tonumber(OBPoliceConfig.InteractionDistance) or 3.0,
            requiresHandsUp = mode == 'readonly',
            durationSeconds = mode == 'readonly'
                and tonumber(OBPoliceConfig.ConsentSearch and OBPoliceConfig.ConsentSearch.ViewTimeoutSeconds)
                or nil,
        })
    end)
end

RegisterNetEvent('ob_police:client:escortState', function(targetSource)
    escortTarget = tonumber(targetSource)
    local ped = currentPed()
    if not ped then return end
    local animation = type(OBPoliceConfig.EscortOfficerAnimation) == 'table'
        and OBPoliceConfig.EscortOfficerAnimation or {}
    if escortTarget then
        local dict, clip = animation.dict or 'amb@world_human_drinking@coffee@female@base', animation.clip or 'base'
        if loadAnimDict(dict) then
            TaskPlayAnim(ped, dict, clip, 8.0, 8.0, -1, tonumber(animation.flag) or 50, 0.0, false, false, false)
        end
    else
        stopAnimation(ped, animation, 'amb@world_human_drinking@coffee@female@base', 'base')
    end
end)

RegisterCommand('+ob_police_escort', function()
    if restrained or LocalPlayer.state['or:downed'] == true then return end
    if IsPedInAnyVehicle(PlayerPedId(), false) then return end
    TriggerServerEvent('ob_police:server:toggleEscort')
end, false)

RegisterCommand('-ob_police_escort', function() end, false)
RegisterKeyMapping(
    '+ob_police_escort',
    'Escoltar ou soltar uma pessoa algemada',
    'keyboard',
    OBPoliceConfig.EscortKey or 'H'
)

local function closestTakedownTarget()
    local ped = currentPed()
    if not ped then return nil end
    local config = OBPoliceConfig.Takedown or {}
    local maximum = tonumber(config.Distance) or 1.10
    local minimumDot = tonumber(config.MinimumForwardDot) or 0.80
    local coords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local closestSource, closestDistance

    for _, playerIndex in ipairs(GetActivePlayers()) do
        if playerIndex ~= PlayerId() and NetworkIsPlayerActive(playerIndex) then
            local targetPed = GetPlayerPed(playerIndex)
            if targetPed and targetPed > 0 and DoesEntityExist(targetPed)
                and not IsPedInAnyVehicle(targetPed, false) then
                local targetCoords = GetEntityCoords(targetPed)
                local offset = targetCoords - coords
                local distance = #offset
                if distance > 0.05 and distance <= maximum then
                    local dot = (
                        forward.x * offset.x
                        + forward.y * offset.y
                        + forward.z * offset.z
                    ) / distance
                    local targetSource = GetPlayerServerId(playerIndex)
                    if dot >= minimumDot
                        and Player(targetSource).state['or:downed'] ~= true
                        and Player(targetSource).state['ob:restrained'] ~= true
                        and HasEntityClearLosToEntity(ped, targetPed, 17)
                        and (not closestDistance or distance < closestDistance) then
                        closestSource, closestDistance = targetSource, distance
                    end
                end
            end
        end
    end
    return closestSource
end

local function tryTakedown()
    if not isPoliceAvailable() or restrained or takedownBusy
        or LocalPlayer.state['or:downed'] == true then return end
    local ped = currentPed()
    if not ped or IsPedInAnyVehicle(ped, false) then return end
    local config = OBPoliceConfig.Takedown or {}
    if config.RequireSprint ~= false
        and (GetGameTimer() > takedownSprintUntil
            or GetEntitySpeed(ped) < (tonumber(config.MinimumSpeed) or 2.5)) then
        return
    end
    if config.RequireJump ~= false and GetGameTimer() > takedownJumpUntil then return end
    local targetSource = closestTakedownTarget()
    if targetSource then TriggerServerEvent('ob_police:server:requestTakedown', targetSource) end
end

RegisterCommand('+ob_police_takedown_modifier', function()
    takedownModifierHeld = true
end, false)
RegisterCommand('-ob_police_takedown_modifier', function()
    takedownModifierHeld = false
    takedownSprintUntil = 0
    takedownJumpUntil = 0
end, false)
RegisterKeyMapping(
    '+ob_police_takedown_modifier',
    'Derrubada policial (correndo, pule e pressione Shift + E)',
    'keyboard',
    'LSHIFT'
)

CreateThread(function()
    while true do
        if takedownModifierHeld then
            local ped = currentPed()
            local config = OBPoliceConfig.Takedown or {}
            if ped then
                local now = GetGameTimer()
                if IsPedSprinting(ped) then
                    takedownSprintUntil = now + math.max(300, tonumber(config.SprintWindowMs) or 850)
                end
                if IsPedJumping(ped) then
                    takedownJumpUntil = now + math.max(200, tonumber(config.JumpWindowMs) or 650)
                end
            end
            if IsControlJustPressed(0, 38) or IsDisabledControlJustPressed(0, 38) then
                tryTakedown()
                Wait(350)
            else
                Wait(0)
            end
        else
            Wait(200)
        end
    end
end)

RegisterNetEvent('ob_police:client:targetSearch', function(targetSource)
    targetSource = tonumber(targetSource)
    if not targetSource or restrained or LocalPlayer.state['or:downed'] == true then return end
    openSearch(targetSource, 'search', 'police')
end)

RegisterNetEvent('ob_police:client:requestSearch', function(targetSource)
    targetSource = tonumber(targetSource)
    if not targetSource or restrained or LocalPlayer.state['or:downed'] == true then return end
    TriggerServerEvent('ob_police:server:requestSearchConsent', targetSource)
end)

RegisterNetEvent('ob_police:client:searchConsentRequest', function(requesterSource, requesterName, timeoutSeconds)
    requesterSource = tonumber(requesterSource)
    if not requesterSource then return end
    local duration = math.max(5, tonumber(timeoutSeconds) or 15)
    pendingSearchConsent = {
        requesterSource = requesterSource,
        expiresAt = GetGameTimer() + (duration * 1000),
    }
    notify(('%s quer ver sua mochila. Pressione Y para aceitar ou N para recusar.'):format(
        tostring(requesterName or 'Uma pessoa')
    ), 'warning')
end)

RegisterNetEvent('ob_police:client:openConsentInventory', function(targetSource)
    targetSource = tonumber(targetSource)
    if targetSource then openSearch(targetSource, 'consentSearch', 'readonly') end
end)

local function answerSearchConsent(accepted)
    local request = pendingSearchConsent
    if not request then return end
    pendingSearchConsent = nil
    if request.expiresAt < GetGameTimer() then
        return notify('O pedido de revista expirou.', 'error')
    end
    TriggerServerEvent('ob_police:server:answerSearchConsent', request.requesterSource, accepted == true)
end

RegisterCommand('+ob_police_accept_search', function() answerSearchConsent(true) end, false)
RegisterCommand('-ob_police_accept_search', function() end, false)
RegisterKeyMapping('+ob_police_accept_search', 'Aceitar pedido para ver sua mochila', 'keyboard', 'Y')

RegisterCommand('+ob_police_reject_search', function() answerSearchConsent(false) end, false)
RegisterCommand('-ob_police_reject_search', function() end, false)
RegisterKeyMapping('+ob_police_reject_search', 'Recusar pedido para ver sua mochila', 'keyboard', 'N')

local function registerSearchTarget()
    if GetResourceState('ob_target') ~= 'started' then return end
    local success, added, errorMessage = pcall(function()
        return exports.ob_target:AddPlayerOption(searchTargetOption, {
            label = 'Revistar e apreender',
            icon = 'R',
            event = 'ob_police:client:targetSearch',
            stateKey = 'ob:restrained',
            stateValue = true,
            distance = tonumber(OBPoliceConfig.InteractionDistance) or 3.0,
            canInteract = function()
                return not restrained
                    and isPoliceAvailable()
                    and LocalPlayer.state['or:downed'] ~= true
            end,
        })
    end)
    if not success or added ~= true then
        print(('[ob_police] Falha ao registrar revista no ob_target: %s'):format(
            tostring(success and errorMessage or added)
        ))
    end


    local consentSuccess, consentAdded, consentError = pcall(function()
        return exports.ob_target:AddPlayerOption(consentTargetOption, {
            label = 'Pedir para revistar',
            icon = '?',
            event = 'ob_police:client:requestSearch',
            stateKey = 'ob:handsUp',
            stateValue = true,
            distance = tonumber(OBPoliceConfig.InteractionDistance) or 3.0,
            canInteract = function(targetSource)
                return not restrained and not isPoliceAvailable()
                    and LocalPlayer.state['or:downed'] ~= true
                    and Player(targetSource).state['ob:restrained'] ~= true
            end,
        })
    end)
    if not consentSuccess or consentAdded ~= true then
        print(('[ob_police] Falha ao registrar pedido de revista no ob_target: %s'):format(
            tostring(consentSuccess and consentError or consentAdded)
        ))
    end

end

AddEventHandler('ob_target:client:ready', registerSearchTarget)

CreateThread(function()
    while GetResourceState('ob_target') ~= 'started' do Wait(250) end
    registerSearchTarget()
end)

RegisterNetEvent('ob_police:client:takedownAttacker', function(targetSource)
    if takedownBusy then return end
    takedownBusy = true
    TriggerEvent('ob_animations:client:cancel')
    TriggerEvent('ob_inventory:client:forceClose')
    TriggerEvent('ob_target:client:forceClose')
    CreateThread(function()
        local ped = currentPed()
        local targetPlayer = GetPlayerFromServerId(tonumber(targetSource) or -1)
        local targetPed = targetPlayer >= 0 and GetPlayerPed(targetPlayer) or 0
        local config = OBPoliceConfig.Takedown or {}
        local animation = config.Animation or {}
        local duration = math.max(1200, tonumber(config.AnimationDurationMs) or 3000)
        if ped and targetPed > 0 and DoesEntityExist(targetPed) then
            TaskTurnPedToFaceEntity(ped, targetPed, 350)
            Wait(250)
            if loadAnimDict(animation.dict or 'missmic2ig_11') then
                TaskPlayAnim(
                    ped, animation.dict or 'missmic2ig_11',
                    animation.attacker or 'mic_2_ig_11_intro_goon',
                    8.0, -8.0, duration, 0, 0.0, false, false, false
                )
                Wait(duration)
                stopAnimation(ped, {
                    dict = animation.dict or 'missmic2ig_11',
                    clip = animation.attacker or 'mic_2_ig_11_intro_goon',
                })
            end
        end
        takedownBusy = false
    end)
end)

RegisterNetEvent('ob_police:client:takedownVictim', function(officerSource)
    if takedownBusy then return end
    takedownBusy = true
    TriggerEvent('ob_animations:client:cancel')
    TriggerEvent('ob_inventory:client:forceClose')
    TriggerEvent('ob_target:client:forceClose')
    CreateThread(function()
        local ped = currentPed()
        local officerPlayer = GetPlayerFromServerId(tonumber(officerSource) or -1)
        local officerPed = officerPlayer >= 0 and GetPlayerPed(officerPlayer) or 0
        local config = OBPoliceConfig.Takedown or {}
        local animation = config.Animation or {}
        local duration = math.max(1200, tonumber(config.AnimationDurationMs) or 3000)
        local ragdollMs = math.max(1000, tonumber(config.RagdollMs) or 3500)

        if ped and officerPed > 0 and DoesEntityExist(officerPed) then
            SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
            SetPedCanRagdoll(ped, false)
            AttachEntityToEntity(
                ped, officerPed, 11816,
                0.25, 0.50, 0.0, 0.0, 0.0, 180.0,
                false, false, false, false, 2, false
            )
            if loadAnimDict(animation.dict or 'missmic2ig_11') then
                TaskPlayAnim(
                    ped, animation.dict or 'missmic2ig_11',
                    animation.victim or 'mic_2_ig_11_intro_p_one',
                    8.0, -8.0, duration, 0, 0.0, false, false, false
                )
            end
            Wait(duration)
            if DoesEntityExist(ped) then
                DetachEntity(ped, true, false)
                stopAnimation(ped, {
                    dict = animation.dict or 'missmic2ig_11',
                    clip = animation.victim or 'mic_2_ig_11_intro_p_one',
                })
                SetPedCanRagdoll(ped, true)
                SetPedToRagdoll(ped, ragdollMs, ragdollMs, 0, false, false, false)
                Wait(ragdollMs)
            end
        end
        local current = currentPed()
        if current then
            DetachEntity(current, true, false)
            if LocalPlayer.state['or:downed'] ~= true then SetPedCanRagdoll(current, true) end
        end
        takedownBusy = false
    end)
end)

CreateThread(function()
    while true do
        if takedownBusy then
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 21, true)
            DisableControlAction(0, 22, true)
            DisableControlAction(0, 23, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)
            DisableControlAction(0, 75, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            Wait(0)
        else
            Wait(250)
        end
    end
end)

CreateThread(function()
    while true do
        if restrained then
            local ped = currentPed()
            if ped then
                DisablePlayerFiring(PlayerId(), true)
                DisableControlAction(0, 21, true) -- correr
                DisableControlAction(0, 22, true) -- pular
                DisableControlAction(0, 23, true) -- entrar em veiculo
                DisableControlAction(0, 24, true) -- ataque
                DisableControlAction(0, 25, true) -- mirar
                DisableControlAction(0, 37, true) -- roda de armas
                DisableControlAction(0, 44, true) -- cobertura
                DisableControlAction(0, 75, true) -- sair do veiculo
                DisableControlAction(0, 140, true)
                DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true)
                SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)

                if GetGameTimer() >= nextCuffPropCheck then
                    nextCuffPropCheck = GetGameTimer() + 1000
                    ensureCuffProp(ped)
                end

                if not escortedBy and not IsPedInAnyVehicle(ped, false)
                    and LocalPlayer.state['or:downed'] ~= true then
                    local animation = OBPoliceConfig.CuffAnimation or {}
                    local dict, clip = animation.dict or 'mp_arresting', animation.clip or 'idle'
                    if not IsEntityPlayingAnim(ped, dict, clip, 3) and loadAnimDict(dict) then
                        TaskPlayAnim(ped, dict, clip, 8.0, -8.0, -1, tonumber(animation.flag) or 49, 0.0, false, false, false)
                    end
                end
                Wait(0)
            else
                Wait(100)
            end
        else
            Wait(300)
        end
    end
end)

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        if escortedBy and restrained and not IsPedInAnyVehicle(ped, false) then
            local officer = GetPlayerFromServerId(escortedBy)
            local officerPed = officer and officer >= 0 and GetPlayerPed(officer) or 0
            if officerPed ~= 0 and DoesEntityExist(officerPed) and not IsPedInAnyVehicle(officerPed, false) then
                if not IsEntityAttachedToEntity(ped, officerPed) then
                    SetPedCanRagdoll(ped, false)
                    SetPedCanRagdollFromPlayerImpact(ped, false)
                    AttachEntityToEntity(
                        ped, officerPed, 11816,
                        0.38, 0.4, 0.0, 0.0, 0.0, 0.0,
                        false, false, false, true, 2, true
                    )
                end

                local dict, clip, flag
                if IsPedWalking(officerPed) then
                    dict, clip, flag = 'anim@move_m@prisoner_cuffed', 'walk', 1
                elseif IsPedRunning(officerPed) or IsPedSprinting(officerPed) then
                    dict, clip, flag = 'anim@move_m@trash', 'run', 1
                else
                    local animation = OBPoliceConfig.CuffAnimation or {}
                    dict, clip, flag = animation.dict or 'mp_arresting', animation.clip or 'idle', tonumber(animation.flag) or 49
                end
                if not IsEntityPlayingAnim(ped, dict, clip, 3) and loadAnimDict(dict) then
                    TaskPlayAnim(ped, dict, clip, 8.0, -8.0, -1, flag, 0.0, false, false, false)
                end
            else
                DetachEntity(ped, true, false)
            end
            Wait(0)
        else
            if IsEntityAttached(ped) then DetachEntity(ped, true, false) end
            Wait(250)
        end
    end
end)

CreateThread(function()
    while LocalPlayer.state['or:loaded'] ~= true do Wait(250) end
    applyRestrained(LocalPlayer.state['ob:restrained'] == true)
    applyEscort(LocalPlayer.state['ob:escortedBy'])
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if GetResourceState('ob_target') == 'started' then
        exports.ob_target:RemovePlayerOption(searchTargetOption)
        exports.ob_target:RemovePlayerOption(consentTargetOption)
    end
    TriggerEvent('ob_minigame:client:cancel')
    removeCuffProp()
    local ped = currentPed()
    if ped then
        DetachEntity(ped, true, false)
        SetEnableHandcuffs(ped, false)
        SetPedCanPlayGestureAnims(ped, true)
        SetPedCanRagdoll(ped, true)
        SetPedCanRagdollFromPlayerImpact(ped, true)
        stopAnimation(ped, OBPoliceConfig.EscortOfficerAnimation, 'amb@world_human_drinking@coffee@female@base', 'base')
    end
end)
