local cameraActive, cameraFront, cameraLooking, cameraHorizontal, videoCallMode = false, false, false, false, false
local previousRadar, previousPedView, previousVehicleView
local frontCamera, frontYaw, frontPitch = nil, 0.0, 0.0
local frontHeadHeight
local frontBaseHeading
local rearWasInVehicle
local movementBlockUntil = 0

local rearViewMode = 4
local frontFov, frontDistance = 32.0, 1.05
local frontHeight, frontTargetHeight = 0.05, 0.03
local frontHorizontalLimit, frontVerticalLimit, frontRotateSpeed = 75.0, 35.0, 5.0

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function clearFrontCamera()
    if frontCamera and DoesCamExist(frontCamera) then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(frontCamera, false)
    end
    frontCamera = nil
    frontHeadHeight = nil
    frontBaseHeading = nil
end

local function frontCameraTransform(ped)
    local origin = GetEntityCoords(ped)
    if not frontHeadHeight then
        local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
        frontHeadHeight = head.z - origin.z
    end
    local direction = GetEntityForwardVector(ped)
    local pitch = math.rad(frontPitch)
    local head = origin + vector3(0.0, 0.0, frontHeadHeight)
    local position = head
        + (direction * (math.cos(pitch) * frontDistance))
        + vector3(0.0, 0.0, frontHeight + (math.sin(pitch) * frontDistance))
    return position, head + vector3(0.0, 0.0, frontTargetHeight)
end

local function applyFrontCamera(ped)
    if not frontCamera or not DoesCamExist(frontCamera) then
        frontCamera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        SetCamFov(frontCamera, frontFov)
        SetCamActive(frontCamera, true)
        RenderScriptCams(true, false, 0, true, true)
    end
    SetCamActive(frontCamera, true)
    RenderScriptCams(true, false, 0, true, true)
    SetFollowPedCamViewMode(0)
    local position, target = frontCameraTransform(ped)
    SetCamCoord(frontCamera, position.x, position.y, position.z)
    PointCamAtCoord(frontCamera, target.x, target.y, target.z)
end

local function applyRearCamera(ped)
    clearFrontCamera()
    rearWasInVehicle = IsPedInAnyVehicle(ped, false)
    if rearWasInVehicle then
        SetFollowVehicleCamViewMode(rearViewMode)
    else
        SetFollowPedCamViewMode(rearViewMode)
    end
end

local function setFrontCamera(active)
    cameraFront = active == true
    movementBlockUntil = GetGameTimer() + 250
    frontYaw, frontPitch = 0.0, 0.0
    frontHeadHeight = nil
    if not cameraActive then return end
    local ped = PlayerPedId()
    if cameraFront then
        frontBaseHeading = GetEntityHeading(ped)
        TriggerEvent('ob_phone:client:cameraVisual', true)
        applyFrontCamera(ped)
    else
        applyRearCamera(ped)
    end
end

local function setHorizontalCamera(active)
    cameraHorizontal = active == true
    return true
end

local function restoreCameraView()
    if previousPedView ~= nil then SetFollowPedCamViewMode(previousPedView) end
    if previousVehicleView ~= nil then SetFollowVehicleCamViewMode(previousVehicleView) end
    if previousRadar ~= nil then DisplayRadar(not previousRadar) end
end

local function stopCamera()
    TriggerEvent('ob_phone:client:cameraInput', false)
    if not cameraActive then return end
    cameraActive = false
    cameraFront = false
    videoCallMode = false
    cameraHorizontal = false
    cameraLooking = false
    movementBlockUntil = 0
    clearFrontCamera()
    restoreCameraView()
    SetNuiFocusKeepInput(true)
    SetNuiFocus(true, true)
    TriggerEvent('ob_phone:client:cameraVisual', false)
end

local function startCamera(forVideoCall)
    if cameraActive then return end
    local ped = PlayerPedId()
    cameraActive = true
    videoCallMode = forVideoCall == true
    cameraFront = false
    cameraHorizontal = false
    cameraLooking = videoCallMode
    movementBlockUntil = 0
    frontYaw, frontPitch = 0.0, 0.0
    previousRadar = IsRadarHidden()
    previousPedView = GetFollowPedCamViewMode()
    previousVehicleView = GetFollowVehicleCamViewMode()
    DisplayRadar(false)

    TriggerEvent('ob_phone:client:cameraVisual', true)
    applyRearCamera(ped)
    SetNuiFocusKeepInput(true)

    CreateThread(function()
        while cameraActive do
            ped = PlayerPedId()
            HideHudAndRadarThisFrame()
            DisablePlayerFiring(PlayerId(), true)
            for _, control in ipairs({24, 25, 37, 44, 45, 140, 141, 142, 257, 263, 264}) do
                DisableControlAction(0, control, true)
            end

            if cameraFront then
                for _, control in ipairs({21, 22, 30, 31, 32, 33, 34, 35, 59, 60, 71, 72}) do
                    DisableControlAction(0, control, true)
                end
                DisableControlAction(0, 1, true)
                DisableControlAction(0, 2, true)
                if cameraLooking then
                    local lookX = GetDisabledControlNormal(0, 1)
                    local lookY = GetDisabledControlNormal(0, 2)
                    frontYaw = clamp(frontYaw - (lookX * frontRotateSpeed), -frontHorizontalLimit, frontHorizontalLimit)
                    frontPitch = clamp(frontPitch - (lookY * frontRotateSpeed), -frontVerticalLimit, frontVerticalLimit)
                end
                if frontBaseHeading then SetEntityHeading(ped, frontBaseHeading + frontYaw) end
                applyFrontCamera(ped)
            else
                if GetGameTimer() < movementBlockUntil then
                    for _, control in ipairs({21, 22, 30, 31, 32, 33, 34, 35, 59, 60, 71, 72}) do
                        DisableControlAction(0, control, true)
                    end
                end
                local inVehicle = IsPedInAnyVehicle(ped, false)
                if rearWasInVehicle ~= inVehicle then applyRearCamera(ped) end
                if not cameraLooking then
                    DisableControlAction(0, 1, true)
                    DisableControlAction(0, 2, true)
                end
            end
            Wait(0)
        end
    end)
end

RegisterNUICallback('cameraActive', function(data, cb)
    if data.active == true then startCamera(data.videoCall == true) else stopCamera() end
    cb({ ok = true })
end)

AddEventHandler('ob_phone:client:videoCallFreeLook', function(active)
    if not cameraActive then return end
    cameraLooking = active == true
    TriggerEvent('ob_phone:client:cameraInput', cameraLooking)
end)

RegisterNUICallback('cameraLook', function(data, cb)
    if not cameraActive then return cb({ ok = false }) end
    cameraLooking = data.active == true
    TriggerEvent('ob_phone:client:cameraInput', cameraLooking)
    cb({ ok = true })
end)

RegisterNUICallback('cameraFacing', function(data, cb)
    if not cameraActive then return cb({ ok = false }) end
    setFrontCamera(data.front == true)
    cb({ ok = true, front = cameraFront })
end)

RegisterNUICallback('cameraOrientation', function(data, cb)
    if not cameraActive then return cb({ ok = false }) end
    local ok = setHorizontalCamera(data.horizontal == true)
    cb({ ok = ok, horizontal = cameraHorizontal })
end)

AddEventHandler('ob_phone:client:cameraStop', stopCamera)
AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then stopCamera() end
end)
