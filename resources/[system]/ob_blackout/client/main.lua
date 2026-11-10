local active = false
local currentState = { active = false, mode = 'automatic' }
local controlledTrafficLights = {}
local controlledDrivers = {}
local controlledPedestrians = {}
local pedestrianSampleIndex = 0
local manualBusy = false
local manualActionProp
local manualAnimation
local restorePanelObject
local showingManualHelp = false
local FLASHLIGHT = GetHashKey('WEAPON_FLASHLIGHT')
local UNARMED = GetHashKey('WEAPON_UNARMED')
local FLASHLIGHT_PROP = GetHashKey('prop_cs_police_torch_02')
local FLASHLIGHT_BONE = 60309
local FLASHLIGHT_ANIM_DICT = 'amb@world_human_security_shine_torch@male@base'
local FLASHLIGHT_ANIM_CLIP = 'base'

local pedestrianSampleOffsets = {
    { 0.0, 0.0 }, { 18.0, 0.0 }, { -18.0, 0.0 },
    { 0.0, 18.0 }, { 0.0, -18.0 },
    { 14.0, 14.0 }, { -14.0, 14.0 },
    { 14.0, -14.0 }, { -14.0, -14.0 },
}

local function worldEffects()
    return type(OBBlackoutConfig.WorldEffects) == 'table' and OBBlackoutConfig.WorldEffects or {}
end

local function manualConfig()
    return type(OBBlackoutConfig.Manual) == 'table' and OBBlackoutConfig.Manual or {}
end

local function minigameConfig(action)
    local config = type(OBBlackoutConfig.Minigames) == 'table' and OBBlackoutConfig.Minigames or {}
    return type(config[action]) == 'table' and config[action] or {}
end

local function animationConfig(action)
    local config = type(OBBlackoutConfig.Animations) == 'table' and OBBlackoutConfig.Animations or {}
    return type(config[action]) == 'table' and config[action] or {}
end

local function loadAnimationDictionary(dictionary, timeout)
    if type(dictionary) ~= 'string' or dictionary == '' then return false end
    RequestAnimDict(dictionary)
    local deadline = GetGameTimer() + math.max(500, tonumber(timeout) or 7000)
    while not HasAnimDictLoaded(dictionary) and GetGameTimer() < deadline do Wait(0) end
    return HasAnimDictLoaded(dictionary)
end

local function stopManualAnimation()
    local ped = PlayerPedId()
    if manualAnimation and DoesEntityExist(ped) then
        StopAnimTask(ped, manualAnimation.dict, manualAnimation.clip, 1.0)
    end
    manualAnimation = nil
    if manualActionProp and DoesEntityExist(manualActionProp) then
        DetachEntity(manualActionProp, true, true)
        DeleteEntity(manualActionProp)
    end
    manualActionProp = nil
end

local function startManualAnimation(action)
    stopManualAnimation()
    local config = animationConfig(action)
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) or not loadAnimationDictionary(config.dict, 7000) then return end

    TaskPlayAnim(ped, config.dict, config.clip or 'base', 3.0, 3.0, -1, tonumber(config.flag) or 49, 0.0, false, false, false)
    manualAnimation = { dict = config.dict, clip = config.clip or 'base' }

    if type(config.propModel) ~= 'string' or config.propModel == '' then return end
    local model = GetHashKey(config.propModel)
    if not OR.Model.Load(model, 7000) then return end
    local coords = GetEntityCoords(ped)
    manualActionProp = CreateObject(model, coords.x, coords.y, coords.z + 0.2, false, false, false)
    if not manualActionProp or manualActionProp == 0 then return end
    local offset = config.offset or vec3(0.0, 0.0, 0.0)
    local rotation = config.rotation or vec3(0.0, 0.0, 0.0)
    AttachEntityToEntity(manualActionProp, ped, GetPedBoneIndex(ped, tonumber(config.bone) or 60309),
        tonumber(offset.x) or 0.0, tonumber(offset.y) or 0.0, tonumber(offset.z) or 0.0,
        tonumber(rotation.x) or 0.0, tonumber(rotation.y) or 0.0, tonumber(rotation.z) or 0.0,
        true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)
end

local function createRestorePanel()
    if restorePanelObject and DoesEntityExist(restorePanelObject) then return end
    local point = manualConfig().restorePoint
    if type(point) ~= 'table' or not point.objectCoords then return end

    local models = { point.objectModel, point.fallbackObjectModel }
    local model
    for _, modelName in ipairs(models) do
        if type(modelName) == 'string' and modelName ~= '' then
            local candidate = GetHashKey(modelName)
            if OR.Model.Load(candidate, 4000) then model = candidate break end
        end
    end
    if not model then return end

    local coords = point.objectCoords
    restorePanelObject = CreateObjectNoOffset(model, coords.x, coords.y, coords.z, false, false, false)
    if restorePanelObject and restorePanelObject ~= 0 then
        SetEntityHeading(restorePanelObject, tonumber(point.objectHeading) or tonumber(point.heading) or 0.0)
        FreezeEntityPosition(restorePanelObject, true)
        SetEntityAsMissionEntity(restorePanelObject, true, false)
    end
    SetModelAsNoLongerNeeded(model)
end

local function drawActionMarker(point)
    local marker = type(point.marker) == 'table' and point.marker or {}
    local scale = marker.scale or vec3(0.24, 0.24, 0.18)
    local color = type(marker.color) == 'table' and marker.color or { 41, 196, 255, 190 }
    DrawMarker(tonumber(marker.type) or 2,
        point.coords.x, point.coords.y, point.coords.z + 0.16,
        0.0, 0.0, 0.0, 0.0, 180.0, 0.0,
        tonumber(scale.x) or 0.24, tonumber(scale.y) or 0.24, tonumber(scale.z) or 0.18,
        tonumber(color[1]) or 41, tonumber(color[2]) or 196, tonumber(color[3]) or 255, tonumber(color[4]) or 190,
        false, true, 2, false, nil, nil, false)
end

local function addModelHash(result, value)
    local hash = type(value) == 'string' and GetHashKey(value) or tonumber(value)
    if not hash then return end
    hash = math.floor(hash)
    local unsigned = hash < 0 and hash + 4294967296 or hash
    local signed = unsigned > 2147483647 and unsigned - 4294967296 or unsigned
    result[unsigned] = true
    result[signed] = true
end

local function hashSet(names, hashes)
    local result = {}
    for _, name in ipairs(names or {}) do addModelHash(result, name) end
    for _, hash in ipairs(hashes or {}) do addModelHash(result, hash) end
    return result
end

local trafficLightModels = hashSet(worldEffects().trafficLightModels, worldEffects().trafficLightHashes)

local function isAmbientEntity(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    if type(GetEntityPopulationType) ~= 'function' then return not IsEntityAMissionEntity(entity) end
    local populationType = GetEntityPopulationType(entity)
    return populationType >= 1 and populationType <= 5
end

local function hasEntityControl(entity)
    if not NetworkGetEntityIsNetworked(entity) then return true end
    return NetworkHasControlOfEntity(entity)
end

local function safePool(poolName)
    if type(GetGamePool) ~= 'function' then return {} end
    local ok, pool = pcall(GetGamePool, poolName)
    return ok and type(pool) == 'table' and pool or {}
end

local function keepVehicleLightsEnabled()
    if type(SetArtificialLightsStateAffectsVehicles) == 'function' then
        local ok = pcall(SetArtificialLightsStateAffectsVehicles, false)
        if ok then return end
    end
    -- Native sem nome em alguns artifacts Legacy; false impede que o apagao
    -- global desligue farois, lanternas e luzes internas dos veiculos.
    pcall(Citizen.InvokeNative, 0xE2B187C0939B3D32, false)
end

local function restoreTrafficLights()
    for entity in pairs(controlledTrafficLights) do
        if DoesEntityExist(entity) then
            -- -1 devolve o ciclo do semaforo ao controle normal do jogo.
            pcall(SetEntityTrafficlightOverride, entity, -1)
            pcall(SetEntityLights, entity, false)
        end
    end
    controlledTrafficLights = {}
end

local function updateTrafficLights()
    local config = worldEffects()
    if config.disableTrafficLights ~= true then return end

    local playerCoords = GetEntityCoords(PlayerPedId())
    local radius = math.max(25.0, tonumber(config.trafficLightScanRadius) or 220.0)
    for _, entity in ipairs(safePool('CObject')) do
        if trafficLightModels[GetEntityModel(entity)] then
            local coords = GetEntityCoords(entity)
            if #(playerCoords - coords) <= radius then
                -- TLO_NONE (3) apaga especificamente vermelho/amarelo/verde.
                -- SetEntityLights continua como reforco para a emissao do prop.
                pcall(SetEntityTrafficlightOverride, entity, 3)
                pcall(SetEntityLights, entity, true)
                controlledTrafficLights[entity] = true
            end
        end
    end
end

local function restoreNpcDrivers()
    local normalStyle = tonumber(worldEffects().normalNpcDriverStyle) or 786603
    for driver in pairs(controlledDrivers) do
        if DoesEntityExist(driver) and not IsPedAPlayer(driver) and hasEntityControl(driver) then
            pcall(SetDriverAggressiveness, driver, 0.0)
            pcall(SetDriveTaskDrivingStyle, driver, normalStyle)
        end
    end
    controlledDrivers = {}
end

local function updateNpcDrivers()
    local config = worldEffects()
    if config.npcDriversIgnoreLights ~= true then return end

    local playerCoords = GetEntityCoords(PlayerPedId())
    local radius = math.max(25.0, tonumber(config.npcDriverScanRadius) or 180.0)
    local style = tonumber(config.npcDriverStyle) or 786475
    local cruiseSpeed = tonumber(config.npcDriverCruiseSpeed) or 14.0
    local aggressiveness = math.max(0.0, math.min(1.0, tonumber(config.npcDriverAggressiveness) or 0.35))

    for _, vehicle in ipairs(safePool('CVehicle')) do
        if isAmbientEntity(vehicle) and not IsEntityAMissionEntity(vehicle) then
            local driver = GetPedInVehicleSeat(vehicle, -1)
            if driver ~= 0
                and not IsPedAPlayer(driver)
                and not IsPedDeadOrDying(driver, true)
                and isAmbientEntity(driver)
                and hasEntityControl(driver)
                and #(playerCoords - GetEntityCoords(vehicle)) <= radius
            then
                pcall(SetDriverAggressiveness, driver, aggressiveness)
                pcall(SetDriveTaskDrivingStyle, driver, style)
                if type(SetDriveTaskCruiseSpeed) == 'function' then
                    pcall(SetDriveTaskCruiseSpeed, driver, cruiseSpeed)
                end

                controlledDrivers[driver] = true
                if type(IsVehicleStoppedAtTrafficLights) == 'function'
                    and IsVehicleStoppedAtTrafficLights(vehicle)
                    and type(TaskVehicleDriveWander) == 'function'
                then
                    pcall(TaskVehicleDriveWander, driver, vehicle, cruiseSpeed, style)
                end
            end
        end
    end
end

local function setPedFlashlight(ped, enabled)
    if type(SetFlashLightEnabled) == 'function' then
        pcall(SetFlashLightEnabled, ped, enabled == true)
    else
        pcall(Citizen.InvokeNative, 0x988DB6FE9B3AC000, ped, enabled == true)
    end
end

local function deletePedFlashlightProp(data)
    if not data then return end
    local prop = data.flashlightProp
    if prop and DoesEntityExist(prop) then
        DetachEntity(prop, true, true)
        DeleteEntity(prop)
    end
    data.flashlightProp = nil
end

local function createPedFlashlightProp(ped, data)
    if not data or not DoesEntityExist(ped) then return false end
    if data.flashlightProp and DoesEntityExist(data.flashlightProp) then return true end
    if not OR.Model.Load(FLASHLIGHT_PROP, 3000) then return false end

    local coords = GetEntityCoords(ped)
    local prop = CreateObject(FLASHLIGHT_PROP, coords.x, coords.y, coords.z + 0.2, false, false, false)
    SetModelAsNoLongerNeeded(FLASHLIGHT_PROP)
    if not prop or prop == 0 or not DoesEntityExist(prop) then return false end

    SetEntityCollision(prop, false, false)
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, FLASHLIGHT_BONE),
        0.0, 0.0, 0.0, 0.0, 0.0, 80.0,
        true, true, false, true, 0, true)
    data.flashlightProp = prop
    return true
end

local function applyPedFlashlightPose(ped, data)
    if not data or data.flashlight ~= true or not DoesEntityExist(ped) then return end
    if IsEntityPlayingAnim(ped, FLASHLIGHT_ANIM_DICT, FLASHLIGHT_ANIM_CLIP, 3) then return end

    local now = GetGameTimer()
    if now < (tonumber(data.nextPoseAttempt) or 0) then return end
    if not HasAnimDictLoaded(FLASHLIGHT_ANIM_DICT) then
        RequestAnimDict(FLASHLIGHT_ANIM_DICT)
        data.nextPoseAttempt = now + 500
        return
    end
    data.nextPoseAttempt = now + 500

    -- 49 mantem somente a parte superior do corpo em loop. O ped continua
    -- andando, mas segura a lanterna na postura criada pelo proprio GTA em
    -- vez de balanca-la como uma arma branca.
    TaskPlayAnim(ped, FLASHLIGHT_ANIM_DICT, FLASHLIGHT_ANIM_CLIP,
        4.0, -4.0, -1, 49, 0.0, false, false, false)
    SetPedCanPlayAmbientAnims(ped, false)
    pcall(SetPedCanPlayAmbientBaseAnims, ped, false)
    SetPedCanPlayGestureAnims(ped, false)
end

local function restorePedestrians()
    for ped, data in pairs(controlledPedestrians) do
        deletePedFlashlightProp(data)
        if DoesEntityExist(ped) and not IsPedAPlayer(ped) and hasEntityControl(ped) then
            pcall(SetPedAlertness, ped, 0)
            if data.flashlight == true then
                StopAnimTask(ped, FLASHLIGHT_ANIM_DICT, FLASHLIGHT_ANIM_CLIP, 2.0)
                SetPedCanPlayAmbientAnims(ped, true)
                pcall(SetPedCanPlayAmbientBaseAnims, ped, true)
                SetPedCanPlayGestureAnims(ped, true)
                setPedFlashlight(ped, false)
                RemoveWeaponFromPed(ped, FLASHLIGHT)
            end
        end
    end
    controlledPedestrians = {}
end

local function isRegularAmbientPed(ped)
    return ped ~= 0
        and DoesEntityExist(ped)
        and not IsPedAPlayer(ped)
        and not IsPedInAnyVehicle(ped, false)
        and not IsPedDeadOrDying(ped, true)
        and not IsEntityAMissionEntity(ped)
        and isAmbientEntity(ped)
        and hasEntityControl(ped)
end

local function updatePedestrianSample()
    local config = worldEffects()
    if config.alertPedestrians ~= true then return end

    pedestrianSampleIndex = (pedestrianSampleIndex % #pedestrianSampleOffsets) + 1
    local offset = pedestrianSampleOffsets[pedestrianSampleIndex]
    local playerCoords = GetEntityCoords(PlayerPedId())
    local searchRadius = math.max(4.0, tonumber(config.pedestrianSearchRadius) or 18.0)
    local found, ped = GetClosestPed(
        playerCoords.x + offset[1], playerCoords.y + offset[2], playerCoords.z,
        searchRadius, true, false, false, false, 26
    )
    if not found or not isRegularAmbientPed(ped) then return end

    local data = controlledPedestrians[ped]
    if not data then
        data = { flashlight = false }
        controlledPedestrians[ped] = data

        local chance = math.max(0.0, math.min(1.0, tonumber(config.pedestrianFlashlightChance) or 0.18))
        local roll = math.abs((ped * 73) + GetEntityModel(ped)) % 1000 / 1000
        if chance > 0.0 and roll < chance and GetSelectedPedWeapon(ped) == UNARMED then
            if createPedFlashlightProp(ped, data) then
                -- A arma-lanterna usa a postura de combate e disputa a mao com
                -- esta animacao. O prop pertence a propria animacao e fica no
                -- osso correto sem alterar a arma ou a tarefa de caminhada.
                data.flashlight = true
                applyPedFlashlightPose(ped, data)
            else
                -- Permite uma nova tentativa caso o modelo ainda estivesse
                -- carregando quando este ped foi encontrado pela primeira vez.
                controlledPedestrians[ped] = nil
                return
            end
        end
    end

    if data.flashlight == true then applyPedFlashlightPose(ped, data) end

    pcall(SetPedAlertness, ped, 2)
    pcall(SetPedSeeingRange, ped, tonumber(config.pedestrianSeeingRange) or 45.0)
    pcall(SetPedHearingRange, ped, tonumber(config.pedestrianHearingRange) or 45.0)

    -- A postura da lanterna ja mantem a parte superior alinhada. O olhar
    -- aleatorio continua apenas nos demais pedestres para nao fazer o NPC com
    -- lanterna girar o tronco e balancar o foco repetidamente.
    if data.flashlight ~= true then
        local duration = math.max(500, math.floor(tonumber(config.pedestrianAttentionDurationMs) or 2800))
        local pedCoords = GetEntityCoords(ped)
        local direction = ((ped * 37) % 360) * math.pi / 180.0
        TaskLookAtCoord(ped,
            pedCoords.x + math.cos(direction) * 12.0,
            pedCoords.y + math.sin(direction) * 12.0,
            pedCoords.z + 0.5,
            duration, 0, 2)
    end
end

local function maintainPedestrianFlashlights()
    local playerCoords = GetEntityCoords(PlayerPedId())
    for ped, data in pairs(controlledPedestrians) do
        local remove = not DoesEntityExist(ped)
            or IsPedAPlayer(ped)
            or IsPedDeadOrDying(ped, true)
            or IsPedInAnyVehicle(ped, false)

        if not remove then
            remove = #(GetEntityCoords(ped) - playerCoords) > 90.0
        end

        if remove then
            deletePedFlashlightProp(data)
            if DoesEntityExist(ped) and data.flashlight == true then
                StopAnimTask(ped, FLASHLIGHT_ANIM_DICT, FLASHLIGHT_ANIM_CLIP, 1.0)
                SetPedCanPlayAmbientAnims(ped, true)
                pcall(SetPedCanPlayAmbientBaseAnims, ped, true)
                SetPedCanPlayGestureAnims(ped, true)
            end
            controlledPedestrians[ped] = nil
        elseif data.flashlight == true then
            if not data.flashlightProp or not DoesEntityExist(data.flashlightProp) then
                createPedFlashlightProp(ped, data)
            end
            applyPedFlashlightPose(ped, data)
        end
    end
end

local function drawPedestrianFlashlights()
    local drewLight = false
    for ped, data in pairs(controlledPedestrians) do
        local prop = data.flashlightProp
        if data.flashlight == true and DoesEntityExist(ped)
            and prop and DoesEntityExist(prop)
        then
            local origin = GetOffsetFromEntityInWorldCoords(prop, 0.0, 0.16, 0.0)
            local direction = GetEntityForwardVector(prop)
            DrawSpotLight(origin.x, origin.y, origin.z,
                direction.x, direction.y, direction.z,
                238, 245, 255, 24.0, 3.0, 0.12, 10.0, 1.0)
            drewLight = true
        end
    end
    return drewLight
end

local function restoreWorldEffects()
    restoreTrafficLights()
    restoreNpcDrivers()
    restorePedestrians()
end

local function applyState(payload)
    payload = type(payload) == 'table' and payload or {}
    currentState = payload
    active = payload.active == true
    keepVehicleLightsEnabled()
    SetArtificialLightsState(active)
    if not active then restoreWorldEffects() end
    TriggerEvent('ob_blackout:client:changed', currentState)
end

RegisterNetEvent('ob_blackout:client:apply', applyState)

RegisterNetEvent('ob_blackout:client:startManual', function(action, token)
    if manualBusy then
        TriggerServerEvent('ob_blackout:server:finishManual', token, false)
        return
    end
    manualBusy = true
    CreateThread(function()
        local point = action == 'disable' and manualConfig().disablePoint or manualConfig().restorePoint
        local ped = PlayerPedId()
        if type(point) == 'table' and point.coords and DoesEntityExist(ped) then
            TaskTurnPedToFaceCoord(ped, point.coords.x, point.coords.y, point.coords.z, 700)
            Wait(450)
        end

        startManualAnimation(action)
        local callOk, minigameSuccess
        if GetResourceState('ob_minigame') == 'started' then
            if action == 'disable' then
                callOk, minigameSuccess = pcall(function()
                    return exports.ob_minigame:DataCrack(minigameConfig('disable'))
                end)
            else
                callOk, minigameSuccess = pcall(function()
                    return exports.ob_minigame:Circuit(minigameConfig('restore'))
                end)
            end
        end

        stopManualAnimation()
        ped = PlayerPedId()
        local completed = callOk == true and minigameSuccess == true
            and DoesEntityExist(ped) and not IsEntityDead(ped)
        manualBusy = false
        TriggerServerEvent('ob_blackout:server:finishManual', token, completed == true)
    end)
end)

CreateThread(function()
    while LocalPlayer.state['or:loaded'] ~= true do Wait(250) end
    Wait(250)
    applyState(GlobalState['ob:blackout'])
    createRestorePanel()
end)

CreateThread(function()
    while true do
        local config = manualConfig()
        if config.enabled == false or LocalPlayer.state['or:loaded'] ~= true then
            if showingManualHelp then OR.Help.Hide(); showingManualHelp = false end
            Wait(1000)
        else
            local action = active and 'restore' or 'disable'
            local point = action == 'disable' and config.disablePoint or config.restorePoint
            if type(point) ~= 'table' or not point.coords then
                if showingManualHelp then OR.Help.Hide(); showingManualHelp = false end
                Wait(1000)
            else
                local distance = #(GetEntityCoords(PlayerPedId()) - point.coords)
                local drawDistance = math.max(5.0, tonumber(config.drawDistance) or 22.0)
                local interactDistance = math.max(1.0, tonumber(point.interactDistance) or 2.5)
                if distance <= drawDistance then
                    drawActionMarker(point)
                    if distance <= interactDistance and not manualBusy then
                        OR.Help.Show(action == 'disable'
                            and 'Pressione ~INPUT_CONTEXT~ para invadir a rede eletrica'
                            or 'Pressione ~INPUT_CONTEXT~ para reparar a rede eletrica')
                        showingManualHelp = true
                        if IsControlJustReleased(0, 38) then
                            OR.Help.Hide()
                            showingManualHelp = false
                            TriggerServerEvent('ob_blackout:server:beginManual', action)
                        end
                    elseif showingManualHelp then
                        OR.Help.Hide()
                        showingManualHelp = false
                    end
                    Wait(0)
                else
                    if showingManualHelp then OR.Help.Hide(); showingManualHelp = false end
                    Wait(math.min(1000, math.max(200, math.floor(distance * 20))))
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        if active then
            updateTrafficLights()
            Wait(math.max(500, math.floor(tonumber(worldEffects().trafficLightScanIntervalMs) or 1500)))
        else
            Wait(1500)
        end
    end
end)

CreateThread(function()
    while true do
        if active then
            updateNpcDrivers()
            Wait(math.max(750, math.floor(tonumber(worldEffects().npcDriverScanIntervalMs) or 1500)))
        else
            Wait(1500)
        end
    end
end)

CreateThread(function()
    while true do
        if active then
            updatePedestrianSample()
            Wait(math.max(350, math.floor(tonumber(worldEffects().pedestrianScanIntervalMs) or 650)))
        else
            Wait(1500)
        end
    end
end)

-- A busca espacial escolhe novos pedestres aos poucos; a manutencao da pose
-- precisa ser independente dela para uma tarefa ambiente nao substituir a
-- animacao da lanterna por varios segundos.
CreateThread(function()
    while true do
        if active then
            maintainPedestrianFlashlights()
            Wait(250)
        else
            Wait(1000)
        end
    end
end)

CreateThread(function()
    while true do
        if active and drawPedestrianFlashlights() then
            Wait(0)
        else
            Wait(250)
        end
    end
end)

CreateThread(function()
    while true do
        if active then
            keepVehicleLightsEnabled()
            SetArtificialLightsState(true)
            Wait(1000)
        else
            Wait(1500)
        end
    end
end)

exports('IsActive', function() return active end)
exports('GetState', function() return currentState end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if GetResourceState('ob_minigame') == 'started' then pcall(function() exports.ob_minigame:Cancel() end) end
    stopManualAnimation()
    if restorePanelObject and DoesEntityExist(restorePanelObject) then DeleteEntity(restorePanelObject) end
    restorePanelObject = nil
    if showingManualHelp then OR.Help.Hide(); showingManualHelp = false end
    restoreWorldEffects()
    keepVehicleLightsEnabled()
    SetArtificialLightsState(false)
end)
