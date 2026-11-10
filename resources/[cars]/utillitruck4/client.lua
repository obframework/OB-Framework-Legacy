local MODEL = GetHashKey('utillitruck4')
local ACTIVE_KEY = 'ob:utillitruckActive'
local ANIM_KEY = 'ob:utillitruckAnim'
local MOVEMENT = {
    { dict = 'va_utillitruck', clip = 'crane' },
    { dict = 'v_boomtruck', clip = 'rotate_crane_base' },
}
local MOVE_SPEED = 0.10
local RETURN_SPEED = 0.08
local HOME_EPSILON = 0.004
local COLLISION = {
    { model = 'prop_crate_06a', bone = 'bucket', offset = { 0.0, -0.36, -0.86 }, rotation = { 0.0, 0.0, 90.0 } },
    { model = 'prop_skate_rail', bone = 'arm_1', offset = { 0.0, 3.0, 0.06 }, rotation = { 0.0, 0.0, 0.0 } },
    { model = 'prop_skate_rail', bone = 'arm_2', offset = { 0.0, -3.4, 0.1 }, rotation = { 0.0, 0.0, 0.0 } },
}
local SOUND = { ambient = 'Crane', bank = 'Container_Lifter', scene = 'DOCKS_HEIST_USING_CRANE', name = 'Move_U_D', ref = 'CRANE_SOUNDS' }

local currentTruck = 0
local craneMode = 1
local animTimes = { 0.0, 0.0 }
local lastRequest, lastSent = 0, 0
local soundId = -1
local collisions, collisionPending = {}, {}
local fallbackLegs = false
local warnedLegsNative = false
local warnedAnim = {}
local returning = false
local lockedTruck = 0
local bucketRider
local RIDER_BOUNDS = { x = 0.62, y = 0.62 }

local function requestAnim(dict)
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(50) end
    local loaded = HasAnimDictLoaded(dict)
    if not loaded and not warnedAnim[dict] then
        warnedAnim[dict] = true
        print(('[ob_utillitruck] Animacao %s nao carregou; cesta nao pode se mover nesse eixo.'):format(dict))
    end
    return loaded
end

local function requestModel(model)
    RequestModel(model)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(50) end
    return HasModelLoaded(model)
end

local function stopSound()
    if soundId == -1 then return end
    StopSound(soundId)
    ReleaseSoundId(soundId)
    soundId = -1
    StopAudioScene(SOUND.scene)
end

local function startSound(vehicle)
    if soundId ~= -1 then return end
    RequestAmbientAudioBank(SOUND.ambient, false)
    RequestScriptAudioBank(SOUND.bank, false)
    if not IsAudioSceneActive(SOUND.scene) then StartAudioScene(SOUND.scene) end
    soundId = GetSoundId()
    PlaySoundFromEntity(soundId, SOUND.name, vehicle, SOUND.ref, false, 0)
end

local function clearCollision(vehicle)
    local objects = collisions[vehicle]
    collisions[vehicle] = nil
    if not objects then return end
    for _, object in ipairs(objects) do
        if DoesEntityExist(object) then DeleteEntity(object) end
    end
end

local function ensureCollision(vehicle)
    if collisions[vehicle] or collisionPending[vehicle] then return end
    collisionPending[vehicle] = true
    CreateThread(function()
        local objects = {}
        for _, part in ipairs(COLLISION) do
            if not DoesEntityExist(vehicle) or Entity(vehicle).state[ACTIVE_KEY] ~= true then break end
            local bone = GetEntityBoneIndexByName(vehicle, part.bone)
            local model = GetHashKey(part.model)
            if bone ~= -1 and requestModel(model) then
                local coords = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 0.0, -20.0)
                local object = CreateObjectNoOffset(model, coords.x, coords.y, coords.z, false, false, false)
                if object and object ~= 0 and DoesEntityExist(object) then
                    SetEntityAsMissionEntity(object, true, true)
                    SetEntityVisible(object, false, false)
                    SetEntityCollision(object, true, true)
                    AttachEntityToEntity(object, vehicle, bone,
                        part.offset[1], part.offset[2], part.offset[3],
                        part.rotation[1], part.rotation[2], part.rotation[3],
                        true, true, true, true, 1, true)
                    objects[#objects + 1] = object
                end
                SetModelAsNoLongerNeeded(model)
            end
        end
        collisionPending[vehicle] = nil
        if DoesEntityExist(vehicle) and Entity(vehicle).state[ACTIVE_KEY] == true then
            collisions[vehicle] = objects
        else
            for _, object in ipairs(objects) do
                if DoesEntityExist(object) then DeleteEntity(object) end
            end
        end
    end)
end

local function applyRemoteAnim(vehicle, snapshot)
    if not DoesEntityExist(vehicle) or GetEntityModel(vehicle) ~= MODEL or type(snapshot) ~= 'table' then return end
    if currentTruck == vehicle and GetPedInVehicleSeat(vehicle, -1) == PlayerPedId() then return end
    local mode = tonumber(snapshot.mode)
    if mode ~= 1 and mode ~= 2 then return end
    local movement = MOVEMENT[mode]
    if not HasAnimDictLoaded(movement.dict) then RequestAnimDict(movement.dict); return end
    local progress = tonumber(mode == 1 and snapshot.vertical or snapshot.horizontal)
    if not progress or progress < 0.0 or progress > 1.0 then return end
    if not IsEntityPlayingAnim(vehicle, movement.dict, movement.clip, 3) then
        PlayEntityAnim(vehicle, movement.clip, movement.dict, 8.0, false, true, false, 0.0, 0)
    end
    SetEntityAnimSpeed(vehicle, movement.dict, movement.clip, 0.0)
    SetEntityAnimCurrentTime(vehicle, movement.dict, movement.clip, progress)
end

local function releaseBucketRider()
    if not bucketRider then return end
    local ped = PlayerPedId()
    SetPedCanRagdoll(ped, true)
    SetEntityMaxSpeed(ped, 1000.0)
    bucketRider = nil
end

local function findBucketRide(ped)
    local pedCoords = GetEntityCoords(ped)
    for vehicle, objects in pairs(collisions) do
        local snapshot = DoesEntityExist(vehicle) and Entity(vehicle).state[ANIM_KEY]
        local raised = type(snapshot) == 'table' and (tonumber(snapshot.vertical) or 0.0) > 0.012
        local bucket = objects and objects[1]
        if raised and bucket and DoesEntityExist(bucket) and #(pedCoords - GetEntityCoords(bucket)) <= 1.8 then
            local localCoords = GetOffsetFromEntityGivenWorldCoords(bucket, pedCoords.x, pedCoords.y, pedCoords.z)
            return {
                vehicle = vehicle,
                bucket = bucket,
                lastCoords = GetEntityCoords(bucket),
                floorZ = localCoords.z,
            }
        end
    end
end

-- A cesta se move por animacao do veiculo, e essa mudanca nao gera uma
-- velocidade fisica confiavel no ped remoto. Transferir o delta da cesta a
-- cada frame mantem o trabalhador sobre o piso sem prende-lo em uma animacao:
-- ele ainda anda e gira normalmente, mas fica limitado a area interna.
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then
            releaseBucketRider()
            Wait(250)
        else
            if not bucketRider then bucketRider = findBucketRide(ped) end
            local ride = bucketRider
            if not ride then
                Wait(100)
            elseif not DoesEntityExist(ride.vehicle) or not DoesEntityExist(ride.bucket)
                or Entity(ride.vehicle).state[ACTIVE_KEY] ~= true then
                releaseBucketRider()
                Wait(100)
            else
                local snapshot = Entity(ride.vehicle).state[ANIM_KEY]
                if type(snapshot) ~= 'table' or (tonumber(snapshot.vertical) or 0.0) <= 0.008 then
                    releaseBucketRider()
                    Wait(100)
                else
                    DisableControlAction(0, 21, true)
                    DisableControlAction(0, 22, true)
                    SetPedCanRagdoll(ped, false)
                    SetEntityMaxSpeed(ped, 1.65)

                    local bucketCoords = GetEntityCoords(ride.bucket)
                    local delta = bucketCoords - ride.lastCoords
                    ride.lastCoords = bucketCoords
                    local pedCoords = GetEntityCoords(ped)
                    if #delta < 3.0 and #delta > 0.0001 then
                        SetEntityCoordsNoOffset(ped, pedCoords.x + delta.x, pedCoords.y + delta.y, pedCoords.z + delta.z, false, false, false)
                        pedCoords = GetEntityCoords(ped)
                    end

                    local relative = GetOffsetFromEntityGivenWorldCoords(ride.bucket, pedCoords.x, pedCoords.y, pedCoords.z)
                    local clampedX = math.max(-RIDER_BOUNDS.x, math.min(RIDER_BOUNDS.x, relative.x))
                    local clampedY = math.max(-RIDER_BOUNDS.y, math.min(RIDER_BOUNDS.y, relative.y))
                    local clampedZ = math.max(ride.floorZ - 0.04, relative.z)
                    if math.abs(relative.x - clampedX) > 0.015 or math.abs(relative.y - clampedY) > 0.015 or relative.z < ride.floorZ - 0.04 then
                        local safe = GetOffsetFromEntityInWorldCoords(ride.bucket, clampedX, clampedY, clampedZ)
                        SetEntityCoordsNoOffset(ped, safe.x, safe.y, safe.z, false, false, false)
                    end
                    ResetPedRagdollTimer(ped)
                    Wait(0)
                end
            end
        end
    end
end)

AddStateBagChangeHandler(ACTIVE_KEY, nil, function(bagName, _, value)
    local vehicle = GetEntityFromStateBagName(bagName)
    if not vehicle or vehicle == 0 or GetEntityModel(vehicle) ~= MODEL then return end
    if value == true then ensureCollision(vehicle) else clearCollision(vehicle) end
end)

AddStateBagChangeHandler(ANIM_KEY, nil, function(bagName, _, value)
    local vehicle = GetEntityFromStateBagName(bagName)
    if vehicle and vehicle ~= 0 then applyRemoteAnim(vehicle, value) end
end)

local function setLocalProgress(vehicle, mode, progress)
    local movement = MOVEMENT[mode]
    if not HasAnimDictLoaded(movement.dict) and not requestAnim(movement.dict) then return false end
    if not IsEntityPlayingAnim(vehicle, movement.dict, movement.clip, 3) then
        PlayEntityAnim(vehicle, movement.clip, movement.dict, 8.0, false, true, false, 0.0, 0)
        Wait(0)
    end
    SetEntityAnimSpeed(vehicle, movement.dict, movement.clip, 0.0)
    SetEntityAnimCurrentTime(vehicle, movement.dict, movement.clip, progress)
    animTimes[mode] = progress
    return true
end

local function localMove(vehicle, mode, direction)
    local progress = animTimes[mode] + MOVE_SPEED * direction * math.min(GetFrameTime(), 0.05)
    if mode == 2 then
        if progress >= 1.0 then progress = progress - 1.0 end
        if progress < 0.0 then progress = progress + 1.0 end
    else
        progress = math.max(0.0, math.min(1.0, progress))
    end
    if not setLocalProgress(vehicle, mode, progress) then return false end
    craneMode = mode
    return true
end

local function isAtHome()
    return animTimes[1] <= HOME_EPSILON
        and math.min(animTimes[2], 1.0 - animTimes[2]) <= HOME_EPSILON
end

local function releaseDriveLock()
    if lockedTruck ~= 0 and DoesEntityExist(lockedTruck) then SetVehicleHandbrake(lockedTruck, false) end
    lockedTruck = 0
end

local function lockDrive(vehicle)
    lockedTruck = vehicle
    SetVehicleHandbrake(vehicle, true)
    for _, control in ipairs({ 59, 63, 64, 71, 72, 76 }) do
        DisableControlAction(0, control, true)
    end
end

local function returnToHome(vehicle)
    local step = RETURN_SPEED * math.min(GetFrameTime(), 0.05)
    local horizontal = animTimes[2]
    if math.min(horizontal, 1.0 - horizontal) > HOME_EPSILON then
        if horizontal > 0.5 then
            horizontal = horizontal + step
            if horizontal >= 1.0 - HOME_EPSILON then horizontal = 0.0 end
        else
            horizontal = math.max(0.0, horizontal - step)
        end
        if not setLocalProgress(vehicle, 2, horizontal) then return false end
        craneMode = 2
        return false
    end
    local vertical = math.max(0.0, animTimes[1] - step)
    if vertical <= HOME_EPSILON then vertical = 0.0 end
    if not setLocalProgress(vehicle, 1, vertical) then return false end
    craneMode = 1
    return isAtHome()
end

local function stopMovement(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    for _, movement in ipairs(MOVEMENT) do
        if HasAnimDictLoaded(movement.dict) and IsEntityPlayingAnim(vehicle, movement.dict, movement.clip, 3) then
            SetEntityAnimSpeed(vehicle, movement.dict, movement.clip, 0.0)
        end
    end
end

local function showControls()
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName('Cesta eletrica: setas para mover; H recolhe a cesta antes de liberar o caminhao.')
    EndTextCommandDisplayHelp(0, false, false, -1)
end

local function showReturning()
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName('Recolhendo a cesta. Aguarde para dirigir.')
    EndTextCommandDisplayHelp(0, false, false, -1)
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local driving = vehicle ~= 0 and GetEntityModel(vehicle) == MODEL and GetPedInVehicleSeat(vehicle, -1) == ped
        if not driving then
            if currentTruck ~= 0 then
                stopMovement(currentTruck)
                stopSound()
                releaseDriveLock()
                currentTruck = 0
                returning = false
            end
            Wait(350)
        else
            if currentTruck ~= vehicle then
                stopMovement(currentTruck)
                stopSound()
                releaseDriveLock()
                currentTruck, craneMode = vehicle, 1
                fallbackLegs = false
                returning = false
                local snapshot = Entity(vehicle).state[ANIM_KEY]
                animTimes = type(snapshot) == 'table'
                    and { tonumber(snapshot.vertical) or 0.0, tonumber(snapshot.horizontal) or 0.0 }
                    or { 0.0, 0.0 }
                lastRequest, lastSent = 0, 0
            end

            local ok, nativeLegs = pcall(AreOutriggerLegsDeployed, vehicle)
            nativeLegs = ok and (nativeLegs == true or nativeLegs == 1)
            if not ok and not warnedLegsNative then
                warnedLegsNative = true
                print('[ob_utillitruck] Leitura nativa dos estabilizadores indisponivel; usando a tecla H como alternativa.')
            end
            if IsControlJustPressed(0, 101) or IsControlJustPressed(0, 74) then
                if nativeLegs then
                    fallbackLegs = false
                else
                    fallbackLegs = not fallbackLegs
                end
            end
            local legsDeployed = nativeLegs or fallbackLegs
            if legsDeployed then
                returning = false
                if isAtHome() then releaseDriveLock() end
            elseif not isAtHome() then
                returning = true
            end
            local active = Entity(vehicle).state[ACTIVE_KEY] == true
            local now = GetGameTimer()
            if (legsDeployed or returning) ~= active and now - lastRequest >= 1000 then
                local netId = NetworkGetNetworkIdFromEntity(vehicle)
                if netId and netId > 0 then
                    lastRequest = now
                    TriggerServerEvent('ob_utillitruck:server:setActive', netId, legsDeployed or returning)
                end
            end

            if legsDeployed then
                startSound(vehicle)
                showControls()
                for control = 172, 175 do DisableControlAction(0, control, true) end
                local mode, direction
                if IsDisabledControlPressed(0, 172) then mode, direction = 1, 1
                elseif IsDisabledControlPressed(0, 173) then mode, direction = 1, -1
                elseif IsDisabledControlPressed(0, 174) then mode, direction = 2, 1
                elseif IsDisabledControlPressed(0, 175) then mode, direction = 2, -1 end

                if mode and localMove(vehicle, mode, direction) then
                    if now - lastSent >= 100 then
                        lastSent = now
                        TriggerServerEvent('ob_utillitruck:server:setAnim',
                            NetworkGetNetworkIdFromEntity(vehicle), craneMode, animTimes[1], animTimes[2])
                    end
                else
                    stopMovement(vehicle)
                end
                if not isAtHome() then lockDrive(vehicle) end
                Wait(0)
            elseif returning then
                lockDrive(vehicle)
                startSound(vehicle)
                showReturning()
                local done = returnToHome(vehicle)
                if now - lastSent >= 100 then
                    lastSent = now
                    TriggerServerEvent('ob_utillitruck:server:setAnim',
                        NetworkGetNetworkIdFromEntity(vehicle), craneMode, animTimes[1], animTimes[2])
                end
                if done then
                    returning = false
                    releaseDriveLock()
                    stopSound()
                end
                Wait(0)
            else
                stopMovement(vehicle)
                stopSound()
                releaseDriveLock()
                Wait(0)
            end
        end
    end
end)

CreateThread(function()
    while true do
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            if GetEntityModel(vehicle) == MODEL and Entity(vehicle).state[ACTIVE_KEY] == true then
                ensureCollision(vehicle)
                applyRemoteAnim(vehicle, Entity(vehicle).state[ANIM_KEY])
            end
        end
        for vehicle in pairs(collisions) do
            if not DoesEntityExist(vehicle) or Entity(vehicle).state[ACTIVE_KEY] ~= true then clearCollision(vehicle) end
        end
        Wait(1000)
    end
end)

AddEventHandler('onClientResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    stopMovement(currentTruck)
    stopSound()
    releaseDriveLock()
    releaseBucketRider()
    for vehicle in pairs(collisions) do clearCollision(vehicle) end
end)
