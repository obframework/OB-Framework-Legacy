local Config = ORCoreConfig.VehicleDamage or { enabled = false }
local damageVehicle, originalDamageHandling
local previousVehicleSpeed, lastWindowBreak = 0.0, 0
local criticalVehicles = {}
local damagedVehicleStates = {}

local DamageHandlingFields = {
    { name = 'fCollisionDamageMult', multiplier = 'collisionMultiplier', minimum = 'minimumCollision' },
    { name = 'fDeformationDamageMult', multiplier = 'deformationMultiplier', minimum = 'minimumDeformation' },
    { name = 'fEngineDamageMult', multiplier = 'engineMultiplier', minimum = 'minimumEngine' },
    { name = 'fWeaponDamageMult', multiplier = 'weaponMultiplier', minimum = 'minimumWeapon' },
}

local function safeNative(native, ...)
    if type(native) == 'function' then pcall(native, ...) end
end

local function setCriticalProtection(vehicle, enabled)
    safeNative(SetDisableVehicleEngineFires, vehicle, enabled == true)
    safeNative(SetDisableVehiclePetrolTankFires, vehicle, enabled == true)
    safeNative(SetDisableVehiclePetrolTankDamage, vehicle, enabled == true)
    safeNative(SetVehicleCanLeakOil, vehicle, enabled == true)
    safeNative(SetVehicleCanLeakPetrol, vehicle, enabled ~= true)
    if enabled then StopEntityFire(vehicle) end
end

local function engineEffectCoords(vehicle)
    local bone = GetEntityBoneIndexByName(vehicle, 'engine')
    if bone and bone ~= -1 then return GetWorldPositionOfEntityBone(vehicle, bone) end
    local _, maximum = GetModelDimensions(GetEntityModel(vehicle))
    return GetOffsetFromEntityInWorldCoords(vehicle, 0.0, maximum.y * 0.62, maximum.z * 0.42)
end

local function startVehicleEffect(effectName, coords, scale)
    local networked = type(StartNetworkedParticleFxNonLoopedAtCoord) == 'function'
    local starter = networked and StartNetworkedParticleFxNonLoopedAtCoord or StartParticleFxNonLoopedAtCoord
    starter(effectName, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0,
        scale, false, false, false)
end

local function updateDamagedEngineEffects(vehicle)
    local effects = type(Config.CriticalEffects) == 'table' and Config.CriticalEffects or {}
    if effects.enabled == false then return end
    local engineHealth = GetVehicleEngineHealth(vehicle)
    local smokeHealth = tonumber(effects.smokeHealth) or 300.0
    local misfireHealth = tonumber(effects.misfireHealth) or 250.0
    local blackSmokeHealth = tonumber(effects.blackSmokeHealth) or 150.0
    if engineHealth > smokeHealth then damagedVehicleStates[vehicle] = nil;return end

    local state = damagedVehicleStates[vehicle] or { nextSmokeAt = 0, nextMisfireAt = 0, misfireUntil = 0 }
    damagedVehicleStates[vehicle] = state
    local now = GetGameTimer()
    if now >= state.nextSmokeAt then
        RequestNamedPtfxAsset('core')
        if HasNamedPtfxAssetLoaded('core') then
            local black = engineHealth <= blackSmokeHealth
            local coords = engineEffectCoords(vehicle)
            UseParticleFxAssetNextCall('core')
            if type(SetParticleFxNonLoopedColour) == 'function' then
                SetParticleFxNonLoopedColour(black and 0.03 or 0.32, black and 0.03 or 0.32, black and 0.03 or 0.32)
            end
            startVehicleEffect('veh_respray_smoke', coords, black and (tonumber(effects.blackSmokeScale) or 0.75)
                or (tonumber(effects.lightSmokeScale) or 0.45))
        end
        state.nextSmokeAt = now + math.max(200, math.floor(engineHealth <= blackSmokeHealth
            and (tonumber(effects.blackSmokeInterval) or 450) or (tonumber(effects.lightSmokeInterval) or 900)))
    end

    if engineHealth > 0.0 and engineHealth <= misfireHealth then
        if now >= state.nextMisfireAt then
            local durationMin = math.max(100, math.floor(tonumber(effects.misfireDurationMin) or 180))
            local durationMax = math.max(durationMin, math.floor(tonumber(effects.misfireDurationMax) or 480))
            local intervalMin = math.max(durationMax, math.floor(tonumber(effects.misfireIntervalMin) or 1400))
            local intervalMax = math.max(intervalMin, math.floor(tonumber(effects.misfireIntervalMax) or 3200))
            state.misfireUntil = now + math.random(durationMin, durationMax)
            state.nextMisfireAt = now + math.random(intervalMin, intervalMax)
        end
        if now < state.misfireUntil then
            SetVehicleEngineTorqueMultiplier(vehicle, tonumber(effects.misfireTorque) or 0.16)
        end
    end
end

local function updateCriticalVehicle(vehicle, shutdownHealth)
    local engineHealth = GetVehicleEngineHealth(vehicle)
    local critical = engineHealth <= shutdownHealth
    local state = criticalVehicles[vehicle]
    if not critical then
        if state then setCriticalProtection(vehicle, false);criticalVehicles[vehicle] = nil end
        return false
    end

    if not state then
        state = { nextSparkAt = 0 }
        criticalVehicles[vehicle] = state
        setCriticalProtection(vehicle, true)
    end
    StopEntityFire(vehicle)
    SetVehicleEngineHealth(vehicle, shutdownHealth)
    SetVehicleUndriveable(vehicle, true)
    SetVehicleEngineOn(vehicle, false, true, true)

    local effects = type(Config.CriticalEffects) == 'table' and Config.CriticalEffects or {}
    local now = GetGameTimer()
    if effects.enabled ~= false and now >= (state.nextSparkAt or 0) then
        RequestNamedPtfxAsset('core')
        if HasNamedPtfxAssetLoaded('core') then
            local coords = engineEffectCoords(vehicle)
            UseParticleFxAssetNextCall('core')
            startVehicleEffect('ent_sht_electrical_box', coords, tonumber(effects.sparkScale) or 0.75)
        end
        local minimum = math.max(500, math.floor(tonumber(effects.sparkIntervalMin) or 1100))
        local maximum = math.max(minimum, math.floor(tonumber(effects.sparkIntervalMax) or 2200))
        state.nextSparkAt = now + math.random(minimum, maximum)
    end
    return true
end

local function restoreVehicleDamageHandling()
    if damageVehicle and DoesEntityExist(damageVehicle) and type(originalDamageHandling) == 'table' then
        for name, value in pairs(originalDamageHandling) do
            SetVehicleHandlingFloat(damageVehicle, 'CHandlingData', name, value)
        end
    end
    damageVehicle, originalDamageHandling = nil, nil
    previousVehicleSpeed = 0.0
end

local function applyVehicleDamageHandling(vehicle)
    restoreVehicleDamageHandling()
    damageVehicle = vehicle
    originalDamageHandling = {}

    for _, field in ipairs(DamageHandlingFields) do
        local original = GetVehicleHandlingFloat(vehicle, 'CHandlingData', field.name)
        originalDamageHandling[field.name] = original
        local minimum = math.max(0.0, tonumber(Config[field.minimum]) or 0.0)
        local multiplier = math.max(0.0, tonumber(Config[field.multiplier]) or 1.0)
        SetVehicleHandlingFloat(vehicle, 'CHandlingData', field.name, math.max(original, minimum) * multiplier)
    end

    SetEntityInvincible(vehicle, false)
    SetEntityCanBeDamaged(vehicle, true)
    SetVehicleCanBeVisiblyDamaged(vehicle, true)
    SetVehicleEngineCanDegrade(vehicle, true)
    SetVehicleTyresCanBurst(vehicle, true)
    SetVehicleCanBreak(vehicle, true)
    previousVehicleSpeed = GetEntitySpeed(vehicle) * 3.6
end

local function tryBreakWindowOnImpact(vehicle, speedLoss)
    local settings = type(Config.Windows) == 'table' and Config.Windows or {}
    if settings.enabled ~= true then return end
    local minimum = math.max(1.0, tonumber(settings.minimumImpactLossKmh) or 18.0)
    local guaranteed = math.max(minimum + 1.0, tonumber(settings.guaranteedImpactLossKmh) or 50.0)
    if speedLoss < minimum then return end

    local now = GetGameTimer()
    if now - lastWindowBreak < math.max(0, tonumber(settings.cooldown) or 750) then return end
    local progress = math.min(1.0, (speedLoss - minimum) / (guaranteed - minimum))
    local minimumChance = math.max(0, math.min(100, tonumber(settings.chanceAtMinimumPercent) or 45))
    local chance = minimumChance + ((100.0 - minimumChance) * progress)
    if math.random(1, 100) > chance then return end

    local intact = {}
    for _, window in ipairs(settings.indexes or { 0, 1, 2, 3, 6, 7 }) do
        if IsVehicleWindowIntact(vehicle, window) then intact[#intact + 1] = window end
    end
    if not next(intact) then return end
    SmashVehicleWindow(vehicle, intact[math.random(1, #intact)])
    lastWindowBreak = now
end

CreateThread(function()
    while true do
        local wait = 500
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local isDriver = vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped
        local isCar = isDriver and IsThisModelACar(GetEntityModel(vehicle))

        if Config.enabled == true and isCar then
            local windows = type(Config.Windows) == 'table' and Config.Windows or {}
            wait = math.max(0, tonumber(windows.sampleInterval) or 0)
            if damageVehicle ~= vehicle then applyVehicleDamageHandling(vehicle) end

            local shutdownHealth = tonumber(Config.engineShutdownHealth) or 0.0
            updateDamagedEngineEffects(vehicle)
            if updateCriticalVehicle(vehicle, shutdownHealth) then
                DisableControlAction(0, 71, true)
                DisableControlAction(0, 72, true)
            end

            local currentSpeed = GetEntitySpeed(vehicle) * 3.6
            if HasEntityCollidedWithAnything(vehicle) then
                tryBreakWindowOnImpact(vehicle, math.max(0.0, previousVehicleSpeed - currentSpeed))
            end
            previousVehicleSpeed = currentSpeed
        elseif damageVehicle then
            restoreVehicleDamageHandling()
        end
        Wait(wait)
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    restoreVehicleDamageHandling()
    for vehicle in pairs(criticalVehicles) do
        if DoesEntityExist(vehicle) then setCriticalProtection(vehicle, false) end
    end
    criticalVehicles = {}
    damagedVehicleStates = {}
end)
