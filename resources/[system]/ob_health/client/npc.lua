local clinicPed
local clinicTargetRegistered = false
local mobileActive = false
local clinicCreating = false
local stopping = false
local ownedEntities = {}
local ownerTag = ('%s:%s'):format(GetCurrentResourceName(), GetGameTimer())

local function trackEntity(entity)
    if entity and entity ~= 0 and DoesEntityExist(entity) then
        ownedEntities[entity] = GetEntityModel(entity)
        Entity(entity).state:set('ob:healthNpcOwner', ownerTag, false)
    end
end

local function ownsEntity(entity)
    return entity and ownedEntities[entity] ~= nil and DoesEntityExist(entity)
        and GetEntityModel(entity) == ownedEntities[entity]
        and Entity(entity).state['ob:healthNpcOwner'] == ownerTag
end

local function canUseClinic(entity)
    if entity ~= clinicPed or not ownsEntity(entity) then return false end
    local point = ORHealthConfig.NPC and ORHealthConfig.NPC.Clinic and ORHealthConfig.NPC.Clinic.Ped
    if type(point) ~= 'table' then return false end
    local coords = GetEntityCoords(entity)
    local dx, dy, dz = coords.x-point.x, coords.y-point.y, coords.z-point.z
    return dx*dx+dy*dy+dz*dz <= 9.0
end

local function config()
    return type(ORHealthConfig.NPC) == 'table' and ORHealthConfig.NPC or {}
end

local function loadModel(modelName)
    local model = type(modelName) == 'number' and modelName or GetHashKey(tostring(modelName))
    if not IsModelInCdimage(model) or not IsModelValid(model) then return nil end
    RequestModel(model)
    local deadline = GetGameTimer() + 7000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    return HasModelLoaded(model) and model or nil
end

local function loadAnim(dictionary)
    RequestAnimDict(dictionary)
    local deadline = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dictionary) and GetGameTimer() < deadline do Wait(0) end
    return HasAnimDictLoaded(dictionary)
end

local function deleteLocalEntity(entity)
    if ownsEntity(entity) then
        SetEntityAsMissionEntity(entity, true, true)
        DeleteEntity(entity)
    end
    if entity then ownedEntities[entity] = nil end
end

local function placePlayer(point)
    if type(point) ~= 'table' then return end
    local ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, point.x + 0.0, point.y + 0.0, point.z + 0.0, false, false, false)
    SetEntityHeading(ped, tonumber(point.heading) or 0.0)
end

RegisterNetEvent('ob_health:client:useNpcClinic', function()
    if LocalPlayer.state['or:downed'] == true then return OR.Notify('Use /socorro enquanto estiver incapacitado.', 'error') end
    CreateThread(function()
        local ok, treatment = OR.Callback.await('npcClinicBegin')
        if not ok or type(treatment) ~= 'table' then
            return OR.Notify(treatment or 'Atendimento automatico indisponivel.', 'error')
        end
        local ped = PlayerPedId()
        placePlayer(treatment.bed)
        FreezeEntityPosition(ped, true)
        local animation = { dict = 'anim@gangops@morgue@table@', clip = 'body_search', flag = 1 }
        local completed, progressError = OR.Progress.Run({
            label = 'Recebendo tratamento hospitalar...',
            duration = tonumber(treatment.duration) or 15000,
            canCancel = true,
            animation = animation,
        })
        FreezeEntityPosition(ped, false)
        ClearPedTasksImmediately(ped)
        placePlayer(treatment.exit)
        if completed ~= true then
            OR.Callback.await('npcClinicCancel', treatment.token)
            return OR.Notify(progressError or 'Atendimento cancelado.', 'error')
        end
        local success, message = OR.Callback.await('npcClinicFinish', treatment.token)
        OR.Notify(message or (success and 'Tratamento concluido.' or 'Atendimento recusado.'), success and 'success' or 'error')
    end)
end)

local function createClinicNpc()
    local clinic = type(config().Clinic) == 'table' and config().Clinic or {}
    if stopping or clinicCreating or config().Enabled ~= true or clinic.Enabled ~= true or ownsEntity(clinicPed) then return end
    clinicCreating = true
    local model = loadModel(clinic.PedModel or config().PedModel or 's_m_m_paramedic_01')
    local point = clinic.Ped
    if stopping or not model or type(point) ~= 'table' then
        if model then SetModelAsNoLongerNeeded(model) end
        clinicCreating = false
        return
    end
    clinicPed = CreatePed(4, model, point.x + 0.0, point.y + 0.0, point.z - 1.0, tonumber(point.heading) or 0.0, false, true)
    SetModelAsNoLongerNeeded(model)
    clinicCreating = false
    if clinicPed == 0 then return end
    trackEntity(clinicPed)
    SetEntityInvincible(clinicPed, true)
    FreezeEntityPosition(clinicPed, true)
    SetBlockingOfNonTemporaryEvents(clinicPed, true)
    TaskStartScenarioInPlace(clinicPed, 'WORLD_HUMAN_CLIPBOARD', 0, true)
    if GetResourceState('ob_target') == 'started' then
        exports.ob_target:RegisterEntity('ob_health:npc_clinic', clinicPed, {
            label = 'Solicitar tratamento', icon = '+', distance = 3.0,
            event = 'ob_health:client:useNpcClinic',
            canInteract = canUseClinic,
        })
        clinicTargetRegistered = true
    end
end

local function registerClinicTarget()
    if not ownsEntity(clinicPed) or clinicTargetRegistered
        or GetResourceState('ob_target') ~= 'started' then return end
    exports.ob_target:RegisterEntity('ob_health:npc_clinic', clinicPed, {
        label = 'Solicitar tratamento', icon = '+', distance = 3.0,
        event = 'ob_health:client:useNpcClinic',
        canInteract = canUseClinic,
    })
    clinicTargetRegistered = true
end

RegisterNetEvent('ob_health:client:startMobileNpc', function(token, mobile)
    if mobileActive then return end
    mobileActive = true
    CreateThread(function()
        local vehicleModel = loadModel(mobile.VehicleModel or 'ambulance')
        local medicModel = loadModel(mobile.PedModel or 's_m_m_paramedic_01')
        if stopping then return end
        if not vehicleModel or not medicModel then
            OR.Callback.await('npcMobileCancel', token)
            OR.Notify('A ambulancia automatica nao conseguiu carregar.', 'error')
            mobileActive = false
            return
        end

        local patientPed = PlayerPedId()
        local patientCoords = GetEntityCoords(patientPed)
        local found, spawn, heading = GetNthClosestVehicleNodeWithHeading(
            patientCoords.x, patientCoords.y, patientCoords.z, 18, 0, 3.0, 0)
        if not found then
            found, spawn, heading = GetClosestVehicleNodeWithHeading(
                patientCoords.x + 80.0, patientCoords.y + 80.0, patientCoords.z, 0, 3.0, 0)
        end
        if not found or not spawn then
            OR.Callback.await('npcMobileCancel', token)
            OR.Notify('Nao foi encontrada uma rota para a ambulancia.', 'error')
            SetModelAsNoLongerNeeded(vehicleModel)
            SetModelAsNoLongerNeeded(medicModel)
            mobileActive = false
            return
        end

        local ambulance = CreateVehicle(vehicleModel, spawn.x, spawn.y, spawn.z, heading or 0.0, true, true)
        local medic = ambulance ~= 0 and CreatePedInsideVehicle(ambulance, 4, medicModel, -1, true, true) or 0
        trackEntity(ambulance)
        trackEntity(medic)
        SetModelAsNoLongerNeeded(vehicleModel)
        SetModelAsNoLongerNeeded(medicModel)
        if ambulance == 0 or medic == 0 then
            deleteLocalEntity(medic)
            deleteLocalEntity(ambulance)
            OR.Callback.await('npcMobileCancel', token)
            OR.Notify('A ambulancia automatica nao conseguiu sair.', 'error')
            mobileActive = false
            return
        end

        SetEntityAsMissionEntity(ambulance, true, true)
        SetEntityAsMissionEntity(medic, true, true)
        SetVehicleEngineOn(ambulance, true, true, false)
        SetVehicleSiren(ambulance, true)
        SetBlockingOfNonTemporaryEvents(medic, true)
        TaskVehicleDriveToCoordLongrange(medic, ambulance, patientCoords.x, patientCoords.y, patientCoords.z,
            24.0, 786603, 10.0)
        OR.Notify('A ambulancia automatica esta a caminho.', 'inform')

        local timeout = GetGameTimer() + math.max(10000, tonumber(mobile.DriveTimeoutMs) or 35000)
        while DoesEntityExist(ambulance) and GetGameTimer() < timeout
            and LocalPlayer.state['or:downed'] == true do
            patientCoords = GetEntityCoords(PlayerPedId())
            if #(GetEntityCoords(ambulance) - patientCoords) <= 16.0 then break end
            Wait(500)
        end

        if LocalPlayer.state['or:downed'] ~= true then
            OR.Callback.await('npcMobileCancel', token)
            deleteLocalEntity(medic)
            deleteLocalEntity(ambulance)
            mobileActive = false
            return
        end

        patientCoords = GetEntityCoords(PlayerPedId())
        if #(GetEntityCoords(ambulance) - patientCoords) > 22.0 then
            local nodeFound, nearNode, nearHeading = GetNthClosestVehicleNodeWithHeading(
                patientCoords.x, patientCoords.y, patientCoords.z, 3, 0, 3.0, 0)
            if nodeFound and nearNode then
                SetEntityCoordsNoOffset(ambulance, nearNode.x, nearNode.y, nearNode.z, false, false, false)
                SetEntityHeading(ambulance, nearHeading or 0.0)
            end
        end

        TaskLeaveVehicle(medic, ambulance, 0)
        local leaveDeadline = GetGameTimer() + 5000
        while IsPedInAnyVehicle(medic, false) and GetGameTimer() < leaveDeadline do Wait(100) end
        patientCoords = GetEntityCoords(PlayerPedId())
        TaskGoStraightToCoord(medic, patientCoords.x, patientCoords.y, patientCoords.z, 1.4, 10000, 0.0, 0.25)
        local walkDeadline = GetGameTimer() + 10000
        while DoesEntityExist(medic) and GetGameTimer() < walkDeadline do
            patientCoords = GetEntityCoords(PlayerPedId())
            if #(GetEntityCoords(medic) - patientCoords) <= 2.2 then break end
            Wait(250)
        end

        local accepted, durationOrError = OR.Callback.await('npcMobileArrived', token)
        if not accepted then
            OR.Notify(durationOrError or 'O atendimento automatico foi cancelado.', 'error')
            deleteLocalEntity(medic)
            deleteLocalEntity(ambulance)
            mobileActive = false
            return
        end

        TaskTurnPedToFaceEntity(medic, PlayerPedId(), 800)
        Wait(800)
        if loadAnim('mini@cpr@char_a@cpr_str') then
            TaskPlayAnim(medic, 'mini@cpr@char_a@cpr_str', 'cpr_pumpchest', 8.0, -8.0,
                tonumber(durationOrError) or 15000, 1, 0.0, false, false, false)
        end
        OR.Notify('O paramedico iniciou o atendimento.', 'inform')
        Wait(math.max(3000, tonumber(durationOrError) or 15000))
        local success, message = OR.Callback.await('npcMobileFinish', token)
        OR.Notify(message or (success and 'Atendimento concluido.' or 'Atendimento recusado.'), success and 'success' or 'error')
        ClearPedTasks(medic)
        if DoesEntityExist(ambulance) then
            TaskEnterVehicle(medic, ambulance, 8000, -1, 1.5, 1, 0)
            Wait(2500)
        end
        deleteLocalEntity(medic)
        deleteLocalEntity(ambulance)
        mobileActive = false
    end)
end)

CreateThread(function()
    Wait(800)
    createClinicNpc()
end)

AddEventHandler('ob_target:client:ready', function()
    clinicTargetRegistered = false
    if ownsEntity(clinicPed) then registerClinicTarget() else createClinicNpc() end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    stopping = true
    if clinicTargetRegistered and GetResourceState('ob_target') == 'started' then
        exports.ob_target:RemoveEntityOption('ob_health:npc_clinic')
    end
    local cleanup = {}
    for entity in pairs(ownedEntities) do cleanup[#cleanup + 1] = entity end
    for _, entity in ipairs(cleanup) do deleteLocalEntity(entity) end
    clinicPed, clinicTargetRegistered, mobileActive = nil, false, false
end)
