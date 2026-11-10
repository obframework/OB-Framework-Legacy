local currentInjuries = {}
local scanTarget
local injuryMovementApplied = false
local reportCooldowns = {}

local firearmGroups = {
    [GetHashKey('GROUP_PISTOL')] = true, [GetHashKey('GROUP_SMG')] = true,
    [GetHashKey('GROUP_RIFLE')] = true, [GetHashKey('GROUP_MG')] = true,
    [GetHashKey('GROUP_SHOTGUN')] = true, [GetHashKey('GROUP_SNIPER')] = true,
}

local sharpWeapons = {
    [GetHashKey('WEAPON_KNIFE')] = true, [GetHashKey('WEAPON_DAGGER')] = true,
    [GetHashKey('WEAPON_SWITCHBLADE')] = true, [GetHashKey('WEAPON_MACHETE')] = true,
    [GetHashKey('WEAPON_BOTTLE')] = true, [GetHashKey('WEAPON_HATCHET')] = true,
    [GetHashKey('WEAPON_BATTLEAXE')] = true,
}

local fireWeapons = {
    [GetHashKey('WEAPON_FIRE')] = true, [GetHashKey('WEAPON_BURN')] = true,
    [GetHashKey('WEAPON_MOLOTOV')] = true, [GetHashKey('WEAPON_PETROLCAN')] = true,
}

local explosionWeapons = {
    [GetHashKey('WEAPON_EXPLOSION')] = true, [GetHashKey('WEAPON_GRENADE')] = true,
    [GetHashKey('WEAPON_STICKYBOMB')] = true, [GetHashKey('WEAPON_PROXMINE')] = true,
}

local function settings()
    return type(ORHealthConfig.Injuries) == 'table' and ORHealthConfig.Injuries or {}
end

local function buildBoneMap()
    local map = {}
    for region, part in pairs(type(settings().BodyParts) == 'table' and settings().BodyParts or {}) do
        for _, bone in ipairs(type(part.bones) == 'table' and part.bones or {}) do map[tonumber(bone)] = region end
    end
    return map
end

local boneRegions = buildBoneMap()

local function causeForWeapon(weapon)
    if weapon == GetHashKey('WEAPON_FALL') then return 'fall' end
    if weapon == GetHashKey('WEAPON_RUN_OVER_BY_CAR') or weapon == GetHashKey('WEAPON_RAMMED_BY_CAR') then return 'impact' end
    if fireWeapons[weapon] or explosionWeapons[weapon] then return 'burn' end
    if sharpWeapons[weapon] then return 'cut' end
    local ok, group = pcall(GetWeapontypeGroup, weapon)
    if ok and firearmGroups[group] then return 'shot' end
    if ok and group == GetHashKey('GROUP_MELEE') then return 'beaten' end
    return 'generic'
end

local function severityFor(cause)
    local causeData = type(settings().Causes) == 'table' and settings().Causes[cause] or nil
    local severity = tonumber(causeData and causeData.baseSeverity) or 10
    local ped = PlayerPedId()
    if cause == 'impact' and IsPedInAnyVehicle(ped, false) then
        severity = severity + math.floor(GetEntitySpeed(GetVehiclePedIsIn(ped, false)) * 0.6)
    end
    return math.min(50, math.max(1, severity))
end

AddEventHandler('gameEventTriggered', function(eventName, data)
    if eventName ~= 'CEventNetworkEntityDamage' or settings().Enabled ~= true then return end
    local victim = data[1]
    if victim ~= PlayerPedId() then return end
    local found, bone = GetPedLastDamageBone(victim)
    local region = found and boneRegions[tonumber(bone)] or nil
    if not region then region = 'torso' end
    local now = GetGameTimer()
    if reportCooldowns[region] and now - reportCooldowns[region] < (tonumber(settings().ReportCooldownMs) or 650) then return end
    reportCooldowns[region] = now
    local cause = causeForWeapon(tonumber(data[7]) or 0)
    TriggerServerEvent('ob_health:server:reportInjury', region, cause, severityFor(cause), bone or 0)
end)

local function maximumSeverity(regions)
    local maximum = 0
    for _, region in ipairs(regions) do
        maximum = math.max(maximum, tonumber(currentInjuries[region] and currentInjuries[region].severity) or 0)
    end
    return maximum
end

CreateThread(function()
    while true do
        currentInjuries = type(LocalPlayer.state['ob:injuries']) == 'table' and LocalPlayer.state['ob:injuries'] or {}
        Wait(350)
    end
end)

CreateThread(function()
    while true do
        local config = settings()
        local ped = PlayerPedId()
        local maximumHealth = math.max(101, GetEntityMaxHealth(ped))
        local healthPercent = math.max(0, math.min(100, ((GetEntityHealth(ped) - 100) / (maximumHealth - 100)) * 100))
        local legSeverity = maximumSeverity({ 'left_leg', 'right_leg' })
        local shouldLimp = LocalPlayer.state['or:downed'] ~= true
            and (healthPercent <= (tonumber(config.LimpBelowHealthPercent) or 20)
                or legSeverity >= (tonumber(config.LegLimpSeverity) or 35))
        if shouldLimp then
            if not injuryMovementApplied then
                RequestAnimSet('move_m@injured')
                local deadline = GetGameTimer() + 3000
                while not HasAnimSetLoaded('move_m@injured') and GetGameTimer() < deadline do Wait(0) end
                if HasAnimSetLoaded('move_m@injured') then SetPedMovementClipset(ped, 'move_m@injured', 0.35) end
                injuryMovementApplied = true
            end
            if config.DisableSprint ~= false then DisableControlAction(0, 21, true) end
            if config.DisableJump ~= false then DisableControlAction(0, 22, true) end
        elseif injuryMovementApplied then
            ResetPedMovementClipset(ped, 0.35)
            injuryMovementApplied = false
        end

        local handSeverity = maximumSeverity({ 'left_hand', 'right_hand' })
        if config.DisableWeaponsWithSevereHandInjury ~= false
            and handSeverity >= (tonumber(config.HandBlockSeverity) or 60) then
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
        end
        local restrictionsActive = shouldLimp or handSeverity > 0
        Wait(restrictionsActive and 0 or 250)
    end
end)

RegisterNetEvent('ob_health:client:openBodyScan', function(targetSource, patient)
    scanTarget = tonumber(targetSource)
    if not scanTarget or type(patient) ~= 'table' then return end
    SendNUIMessage({ action = 'bodyScanOpen', patient = patient })
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
end)

RegisterNUICallback('bodyScanClose', function(_, callback)
    scanTarget = nil
    SendNUIMessage({ action = 'bodyScanClose' })
    SetNuiFocus(false, false)
    callback({ ok = true })
end)

RegisterNUICallback('injuryTreat', function(data, callback)
    local targetSource = scanTarget
    local region = type(data) == 'table' and tostring(data.region or '') or ''
    SendNUIMessage({ action = 'bodyScanClose' })
    SetNuiFocus(false, false)
    callback({ ok = targetSource ~= nil and region ~= '' })
    if not targetSource or region == '' then return end
    CreateThread(function()
        local ok, durationOrError, injury = OR.Callback.await('emsBeginInjuryTreatment', targetSource, region)
        if not ok then return OR.Notify(durationOrError or 'Nao foi possivel iniciar o tratamento.', 'error') end
        local completed, progressError = OR.Progress.Run({
            label = ('Tratando %s...'):format(injury and injury.label or 'lesao'),
            duration = durationOrError,
            canCancel = true,
            animation = { dict = 'amb@medic@standing@tendtodead@base', clip = 'base', flag = 49 },
        })
        if completed ~= true then
            OR.Callback.await('emsCancelInjuryTreatment')
            return OR.Notify(progressError or 'Tratamento cancelado.', 'error')
        end
        local success, message = OR.Callback.await('emsFinishInjuryTreatment', targetSource, region)
        OR.Notify(message or (success and 'Lesao tratada.' or 'Tratamento recusado.'), success and 'success' or 'error')
        if success then
            local refreshed, patient = OR.Callback.await('emsExamine', targetSource)
            if refreshed and type(patient) == 'table' then
                scanTarget = targetSource
                SendNUIMessage({ action = 'bodyScanOpen', patient = patient })
                SetNuiFocus(true, true)
            else
                scanTarget = nil
            end
        else
            scanTarget = nil
        end
    end)
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if injuryMovementApplied then ResetPedMovementClipset(PlayerPedId(), 0.0) end
    SetNuiFocus(false, false)
end)

exports('CanUseWeapon', function()
    return maximumSeverity({ 'left_hand', 'right_hand' }) < (tonumber(settings().HandBlockSeverity) or 60)
end)
