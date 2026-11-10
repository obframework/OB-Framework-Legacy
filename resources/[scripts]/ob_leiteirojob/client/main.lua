local spawnedPeds = {}
local spawnedObjects = {}
local cowPeds = {}
local cowCooldowns = {}
local jobVehicle = 0
local jobVehiclePlate = nil
local jobVehicleBlip = 0
local deliveryBlip = 0
local currentDeliveryIndex = nil
local npcPed = 0
local processMachine = 0
local carriedBox = 0
local updateDeliveryBlip
local panelOpen = false
local jobStatus = {
    active = false,
    pendingPayment = 0,
    deliveredBoxes = 0,
    vehicleBoxes = 0,
    machineBox = false,
    carryingBox = false,
    deliveryCarry = false,
    deliveryIndex = nil,
    deliveryRemaining = 0,
    progress = { level = 1, xp = 0, xpInLevel = 0, xpRequired = 500, boxesDelivered = 0, totalEarned = 0, paymentBonus = 0 },
    contract = { unlocked = false, target = 0, delivered = 0, complete = false, bonus = 0 }
}

local function notify(msg, typ)
    OR.Notify(msg, typ or 'info')
end

local function setStatus(values)
    if not values then return end

    for key, value in pairs(values) do
        jobStatus[key] = value
    end
end

local function refreshStatus()
    local status = OR.Callback.await('orbis-leiteiro:server:getStatus')
    if status then
        setStatus(status)
    end

    if updateDeliveryBlip then
        updateDeliveryBlip()
    end

    return jobStatus
end

local function requestModel(modelName)
    local model = type(modelName) == 'number' and modelName or joaat(modelName)
    if not IsModelInCdimage(model) or not IsModelValid(model) then return nil end

    RequestModel(model)
    local timeout = GetGameTimer() + 5000

    while not HasModelLoaded(model) and GetGameTimer() < timeout do
        Wait(10)
        RequestModel(model)
    end

    if not HasModelLoaded(model) then return nil end
    return model
end

local function playAnim(dict, anim, flag)
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        Wait(10)
    end
    TaskPlayAnim(PlayerPedId(), dict, anim, 8.0, -8.0, -1, flag or 1, 0, false, false, false)
end

local function doProgress(label, duration, anim)
    return OR.Progress.Run({
        duration = duration,
        label = label,
        animation = anim and {
            dict = anim.dict,
            clip = anim.clip,
            flag = anim.flag or 1,
        } or nil,
    })
end

local function createBlip(coords, cfg)
    if not cfg then return 0 end

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, cfg.sprite or 280)
    SetBlipDisplay(blip, 4)
    SetBlipColour(blip, cfg.color or 0)
    SetBlipScale(blip, cfg.scale or 0.75)
    -- Ponto de emprego segue o padrao das lojas: so aparece ao se aproximar.
    SetBlipAsShortRange(blip, cfg.shortRange ~= false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(cfg.name or 'Leiteiro')
    EndTextCommandSetBlipName(blip)
    return blip
end

local function getDeliveryCoords(index)
    local locations = Leiteiro.delivery.locations or {}
    return locations[index or 0] or Leiteiro.delivery.coords
end

updateDeliveryBlip = function()
    local shouldShow = jobStatus.active and jobStatus.deliveryIndex and ((jobStatus.vehicleBoxes or 0) > 0 or jobStatus.deliveryCarry)

    if not shouldShow then
        if deliveryBlip ~= 0 and DoesBlipExist(deliveryBlip) then
            RemoveBlip(deliveryBlip)
        end

        deliveryBlip = 0
        currentDeliveryIndex = nil
        return
    end

    if deliveryBlip ~= 0 and DoesBlipExist(deliveryBlip) and currentDeliveryIndex == jobStatus.deliveryIndex then
        return
    end

    if deliveryBlip ~= 0 and DoesBlipExist(deliveryBlip) then
        RemoveBlip(deliveryBlip)
    end

    local coords = getDeliveryCoords(jobStatus.deliveryIndex)
    deliveryBlip = createBlip(coords, { sprite = 478, color = 46, scale = 0.7, name = 'Entrega de leite' })
    currentDeliveryIndex = jobStatus.deliveryIndex
    SetNewWaypoint(coords.x, coords.y)
    notify('Entrega marcada no GPS.', 'success')
end

local function createPed(modelName, coords)
    local model = requestModel(modelName)
    if not model then return 0 end

    local ped = CreatePed(4, model, coords.x, coords.y, coords.z - 1.0, coords.w or 0.0, false, true)
    if ped == 0 or not DoesEntityExist(ped) then
        SetModelAsNoLongerNeeded(model)
        return 0
    end

    SetEntityAsMissionEntity(ped, true, true)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityHeading(ped, coords.w or 0.0)
    SetModelAsNoLongerNeeded(model)

    spawnedPeds[#spawnedPeds + 1] = ped
    return ped
end

local function createObject(modelName, coords)
    local model = requestModel(modelName)
    if not model then return 0 end

    local object = CreateObject(model, coords.x, coords.y, coords.z, false, true, false)
    if object == 0 or not DoesEntityExist(object) then
        SetModelAsNoLongerNeeded(model)
        return 0
    end

    SetEntityAsMissionEntity(object, true, true)
    SetEntityHeading(object, coords.w or 0.0)
    PlaceObjectOnGroundProperly(object)
    FreezeEntityPosition(object, true)
    SetModelAsNoLongerNeeded(model)

    spawnedObjects[#spawnedObjects + 1] = object
    return object
end

local function deleteCarryBox()
    if carriedBox ~= 0 and DoesEntityExist(carriedBox) then
        exports.ob_core:DeleteNetworkedObject(carriedBox)
    end

    carriedBox = 0
end

local function createCarryBox()
    deleteCarryBox()

    local cfg = Leiteiro.props and Leiteiro.props.box
    if not cfg then return end

    local model = requestModel(cfg.model)
    if not model then return end

    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)
    local object = exports.ob_core:CreateNetworkedObject(model, pedCoords, true)
    if object == 0 or not DoesEntityExist(object) then
        SetModelAsNoLongerNeeded(model)
        return
    end

    local offset = cfg.offset or vec3(0.0, 0.0, 0.0)
    local rotation = cfg.rotation or vec3(0.0, 0.0, 0.0)
    AttachEntityToEntity(
        object,
        ped,
        GetPedBoneIndex(ped, cfg.bone or 28422),
        offset.x,
        offset.y,
        offset.z,
        rotation.x,
        rotation.y,
        rotation.z,
        true,
        true,
        false,
        true,
        1,
        true
    )

    carriedBox = object
    SetModelAsNoLongerNeeded(model)
end

local function cleanupVehicle()
    exports.ob_target:RemoveEntityOption('orbis_leiteiro_load_vehicle')
    exports.ob_target:RemoveEntityOption('orbis_leiteiro_pickup_delivery_box')
    exports.ob_target:RemoveEntityOption('orbis_leiteiro_cargo_vehicle')
    if jobVehicleBlip ~= 0 and DoesBlipExist(jobVehicleBlip) then
        RemoveBlip(jobVehicleBlip)
        jobVehicleBlip = 0
    end

    if jobVehiclePlate and GetResourceState('mri_Qcarkeys') == 'started' then
        exports.mri_Qcarkeys:RemoveTempKeys(jobVehiclePlate)
        exports.mri_Qcarkeys:RemoveKeyItem(jobVehiclePlate)
    end

    if jobVehicle ~= 0 and DoesEntityExist(jobVehicle) then
        DeleteEntity(jobVehicle)
        jobVehicle = 0
    end

    jobVehiclePlate = nil

    if deliveryBlip ~= 0 and DoesBlipExist(deliveryBlip) then
        RemoveBlip(deliveryBlip)
        deliveryBlip = 0
    end

    currentDeliveryIndex = nil
end

local function fillVehicleFuel(vehicle)
    SetVehicleFuelLevel(vehicle, 100.0)

    if GetResourceState('cdn-fuel') == 'started' then
        exports['cdn-fuel']:SetFuel(vehicle, 100.0)
    end
end

local function isVehicleSpawnBlocked()
    local coords = Leiteiro.vehicle.spawn
    local spawnCoords = vec3(coords.x, coords.y, coords.z)
    local radius = Leiteiro.vehicle.spawnClearRadius or 4.0

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) and vehicle ~= jobVehicle and #(GetEntityCoords(vehicle) - spawnCoords) <= radius then
            return true
        end
    end

    return false
end

local function loadVehicleBox()
    local status = refreshStatus()
    if not status.carryingBox then return notify('Pegue uma caixa pronta na maquina primeiro.', 'error') end
    if jobVehicle == 0 or not DoesEntityExist(jobVehicle) then return notify('O veiculo do leiteiro nao foi encontrado.', 'error') end
    if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(jobVehicle)) > (Leiteiro.vehicle.loadDistance or 5.0) then
        return notify('Chegue mais perto do veiculo para carregar.', 'error')
    end

    if carriedBox == 0 or not DoesEntityExist(carriedBox) then createCarryBox() end
    local completed = doProgress('Colocando caixa no veiculo...', Leiteiro.job.deliveryTimeMs, {
        dict = 'anim@heists@box_carry@', clip = 'idle', flag = 49
    })

    if not completed then
        ClearPedTasks(PlayerPedId())
        return notify('Acao cancelada.', 'inform')
    end

    local ok, amount, total, deliveryIndex, deliveryRemaining = OR.Callback.await('orbis-leiteiro:server:loadVehicleBoxes')
    if ok then
        deleteCarryBox()
        setStatus({ carryingBox = false, vehicleBoxes = total, deliveryIndex = deliveryIndex, deliveryRemaining = deliveryRemaining or jobStatus.deliveryRemaining })
        updateDeliveryBlip()
        notify(('Voce colocou %s caixa no veiculo. Carga atual: %s.'):format(amount or 1, total or 0), 'success')
    end

    ClearPedTasks(PlayerPedId())
end

local function pickupDeliveryBox()
    local status = refreshStatus()
    if (status.vehicleBoxes or 0) <= 0 then return notify('O veiculo nao tem caixas de leite para entregar.', 'error') end
    if status.carryingBox or status.deliveryCarry then return notify('Voce ja esta carregando uma caixa.', 'error') end

    local completed = doProgress('Retirando caixa do veiculo...', math.min(Leiteiro.job.deliveryTimeMs, 3000), {
        dict = 'anim@heists@box_carry@', clip = 'idle', flag = 49
    })
    ClearPedTasks(PlayerPedId())
    if not completed then return notify('Acao cancelada.', 'inform') end

    local ok, remaining, deliveryIndex, deliveryRemaining = OR.Callback.await('orbis-leiteiro:server:pickupDeliveryBox')
    if ok then
        setStatus({ vehicleBoxes = remaining, deliveryIndex = deliveryIndex, deliveryRemaining = deliveryRemaining or jobStatus.deliveryRemaining, deliveryCarry = true })
        createCarryBox()
        playAnim('anim@heists@box_carry@', 'idle', 49)
        updateDeliveryBlip()
        notify('Leve a caixa ate o ponto de entrega.', 'success')
    else
        refreshStatus()
    end
end

local function useVehicleCargo()
    local status = refreshStatus()
    if status.carryingBox then return loadVehicleBox() end

    if (status.vehicleBoxes or 0) > 0 and status.deliveryIndex then
        local deliveryCoords = getDeliveryCoords(status.deliveryIndex)
        if jobVehicle ~= 0 and DoesEntityExist(jobVehicle) and #(GetEntityCoords(jobVehicle) - deliveryCoords) <= 20.0 then
            return pickupDeliveryBox()
        end
        return notify('Leve o veiculo ate o ponto de entrega antes de retirar a caixa.', 'inform')
    end

    notify('Retire uma caixa pronta da maquina para colocar no veiculo.', 'inform')
end

RegisterNetEvent('orbis-leiteiro:client:loadVehicleBoxTarget', loadVehicleBox)
RegisterNetEvent('orbis-leiteiro:client:pickupDeliveryBoxTarget', pickupDeliveryBox)
RegisterNetEvent('orbis-leiteiro:client:useVehicleCargoTarget', useVehicleCargo)

local function isAtVehicleCargoArea(entity)
    if entity ~= jobVehicle or not DoesEntityExist(jobVehicle) then return false end

    -- O menor Y do modelo e a traseira do veiculo no sistema de coordenadas
    -- GTA. Usar as dimensoes evita alvo nas portas/cabine de vans diferentes.
    local minimum, maximum = GetModelDimensions(GetEntityModel(jobVehicle))
    local rear = GetOffsetFromEntityInWorldCoords(jobVehicle, 0.0, minimum.y - 0.35, (minimum.z + maximum.z) * 0.35)
    return #(GetEntityCoords(PlayerPedId()) - rear) <= 4.75
end

local function registerVehicleTarget(vehicle)
    exports.ob_target:RegisterEntity('orbis_leiteiro_cargo_vehicle', vehicle, {
        icon = 'fas fa-boxes-stacked',
        label = 'Usar compartimento de carga',
        distance = 7.0,
        canInteract = function(entity)
            return isAtVehicleCargoArea(entity)
        end,
        event = 'orbis-leiteiro:client:useVehicleCargoTarget',
    })
end

local function spawnDeliveryVehicle(silent)
    local status = refreshStatus()
    if not status.active then
        if not silent then notify('Inicie o trabalho primeiro.', 'error') end
        return false
    end

    if jobVehicle ~= 0 and DoesEntityExist(jobVehicle) then
        if not silent then notify('Voce ja esta com um caminhao do leiteiro.', 'error') end
        return true
    end

    if isVehicleSpawnBlocked() then
        if not silent then notify('A vaga do caminhao esta ocupada. Retire o veiculo do local primeiro.', 'error') end
        return false
    end

    local cfg = Leiteiro.vehicle
    local ok, result = OR.Callback.await('orbis-leiteiro:server:spawnVehicle')
    if not ok or type(result) ~= 'table' then
        if not silent then notify(result or 'Nao foi possivel criar o veiculo.', 'error') end
        return false
    end
    local vehicle = OR.Entity.AwaitNetwork(result.netId, 10000)
    if not vehicle then
        if not silent then notify('O veiculo criado nao sincronizou.', 'error') end
        return false
    end

    jobVehicle = vehicle
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleNumberPlateText(vehicle, result.plate)
    SetVehicleColours(vehicle, cfg.primaryColor or 111, cfg.secondaryColor or 111)
    SetVehicleDirtLevel(vehicle, 0.0)
    fillVehicleFuel(vehicle)

    local plate = GetVehicleNumberPlateText(vehicle)
    jobVehiclePlate = plate:gsub('%W', '')
    if GetResourceState('mri_Qcarkeys') == 'started' then
        exports.mri_Qcarkeys:GiveTempKeys(plate)
    else
        TriggerEvent('vehiclekeys:client:SetOwner', plate)
    end
    registerVehicleTarget(vehicle)

    jobVehicleBlip = AddBlipForEntity(vehicle)
    SetBlipSprite(jobVehicleBlip, 67)
    SetBlipColour(jobVehicleBlip, 46)
    SetBlipScale(jobVehicleBlip, 0.75)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Veiculo do leiteiro')
    EndTextCommandSetBlipName(jobVehicleBlip)

    if not silent then
        notify('Veiculo do leiteiro criado.', 'success')
    end

    return true
end

local function requestDeliveryVehicle()
    if spawnDeliveryVehicle(false) then
        refreshStatus()
    end
end

local function startJob()
    local ok, message, members = OR.Callback.await('orbis-leiteiro:server:startJob')
    if ok then
        setStatus({
            active = true,
            machineBox = false,
            carryingBox = false,
            deliveryCarry = false,
            vehicleBoxes = 0,
            deliveryIndex = nil,
            deliveryRemaining = 0
        })
        updateDeliveryBlip()
        notify((members or 1)>1 and 'Trabalho do grupo iniciado. Cada integrante recebeu 4 baldes.'
            or 'Trabalho de leiteiro iniciado. Ordenhe as vacas e depois envase o leite.','success')
    elseif message then notify(message,'error') end
end

local function clearLocalJob()
    setStatus({
        active = false,
        machineBox = false,
        carryingBox = false,
        deliveryCarry = false,
        vehicleBoxes = 0,
        deliveryIndex = nil,
        deliveryRemaining = 0
    })
    updateDeliveryBlip()
    cleanupVehicle()
    deleteCarryBox()
end

local function stopJob()
    local ok,message=OR.Callback.await('orbis-leiteiro:server:stopJob')
    if not ok then return notify(message or 'Nao foi possivel finalizar o trabalho.','error') end
    clearLocalJob()
    notify('Trabalho de leiteiro finalizado.', 'inform')
end

local function claimPayment()
    local ok = OR.Callback.await('orbis-leiteiro:server:claimPayment')
    refreshStatus()

    if ok then
        notify('Pagamento recebido. Finalize a entrega com o responsavel para guardar o caminhao.', 'success')
    end
end

local function requestBuckets()
    local ok,_,resetCooldown = OR.Callback.await('orbis-leiteiro:server:requestBuckets')
    if ok and resetCooldown then
        cowCooldowns = {}
    end

    refreshStatus()
end

local function getNearbyPlayers()
    local nearby,myCoords={},GetEntityCoords(PlayerPedId())
    for _,player in ipairs(GetActivePlayers()) do
        if player~=PlayerId() then
            local ped=GetPlayerPed(player)
            if ped~=0 and #(myCoords-GetEntityCoords(ped))<=(Leiteiro.group.inviteDistance or 18.0) then
                nearby[#nearby+1]={id=GetPlayerServerId(player),name=GetPlayerName(player) or ('ID %s'):format(GetPlayerServerId(player))}
            end
        end
    end
    return nearby
end

local function openNpcMenu()
    local data = OR.Callback.await('orbis-leiteiro:server:getPanelData')
    if not data then return end
    data.tutorial = Leiteiro.tutorial
    data.nearby = getNearbyPlayers()
    panelOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', payload = data })
end

local function refreshPanel()
    if not panelOpen then return end
    local data = OR.Callback.await('orbis-leiteiro:server:getPanelData')
    if data then data.nearby=getNearbyPlayers();SendNUIMessage({ action = 'update', payload = data }) end
end

local function closePanel()
    panelOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function approachCow(cowId)
    local cow = cowPeds[cowId]
    if not cow or cow == 0 or not DoesEntityExist(cow) then return end

    local ped = PlayerPedId()
    local targetCoords = GetOffsetFromEntityInWorldCoords(cow, 0.0, -1.0, 0.0)
    if #(GetEntityCoords(ped) - targetCoords) > 1.2 then
        TaskGoStraightToCoord(ped, targetCoords.x, targetCoords.y, targetCoords.z, 1.0, 4000, GetEntityHeading(cow), 0.25)
        local timeout = GetGameTimer() + 4000

        while GetGameTimer() < timeout and #(GetEntityCoords(ped) - targetCoords) > 1.2 do
            Wait(50)
        end
    end

    TaskTurnPedToFaceEntity(ped, cow, 800)
    Wait(800)
end

local function milkCow(cowId)
    local status = refreshStatus()
    if not status.active then
        return notify('Inicie o trabalho de leiteiro primeiro.', 'error')
    end

    local canMilk, remaining = OR.Callback.await('orbis-leiteiro:server:canMilkCow', cowId)
    if not canMilk then
        if remaining and remaining > 0 then
            cowCooldowns[cowId] = GetGameTimer() + (remaining * 1000)
        end
        return
    end

    approachCow(cowId)

    local completed = doProgress('Ordenhando vaca...', Leiteiro.job.milkTimeMs, {
        dict = 'anim@amb@business@weed@weed_inspecting_lo_med_hi@',
        clip = 'weed_crouch_checkingleaves_idle_01_inspector',
        flag = 1
    })
    ClearPedTasks(PlayerPedId())

    if not completed then
        return notify('Acao cancelada.', 'inform')
    end

    local ok = OR.Callback.await('orbis-leiteiro:server:milkCow', cowId)
    if ok then
        cowCooldowns[cowId] = GetGameTimer() + ((Leiteiro.job.milkCooldownSeconds or 300) * 1000)
        notify('Voce encheu um balde de leite.', 'success')
    end
    refreshPanel()
end

local function processMilk()
    local status = refreshStatus()
    if not status.active then
        return notify('Inicie o trabalho de leiteiro primeiro.', 'error')
    end

    if status.machineBox then
        return notify('Retire a caixa pronta da maquina antes de processar outra.', 'error')
    end

    if status.carryingBox then
        return notify('Coloque a caixa que voce esta carregando no veiculo primeiro.', 'error')
    end

    if status.deliveryCarry then
        return notify('Entregue a caixa que voce esta carregando primeiro.', 'error')
    end

    if jobVehicle == 0 or not DoesEntityExist(jobVehicle) then
        return notify('Pegue o caminhao com o responsavel antes de usar a maquina.', 'error')
    end

    local canProcess = OR.Callback.await('orbis-leiteiro:server:canProcessMilk')
    if not canProcess then
        refreshStatus()
        return
    end

    local completed = doProgress('Envasando leite...', Leiteiro.job.processTimeMs, {
        dict = 'amb@prop_human_bum_bin@base',
        clip = 'base',
        flag = 1
    })
    ClearPedTasks(PlayerPedId())

    if not completed then
        return notify('Acao cancelada.', 'inform')
    end

    local ok = OR.Callback.await('orbis-leiteiro:server:processMilk')
    if ok then
        setStatus({ machineBox = true })
        notify('Uma caixa ficou pronta na maquina. Retire e coloque no veiculo.', 'success')
    else
        refreshStatus()
    end
    refreshPanel()
end

local function pickupMachineBox()
    local status = refreshStatus()
    if not status.active then
        return notify('Inicie o trabalho de leiteiro primeiro.', 'error')
    end

    if not status.machineBox then
        return notify('Nao tem caixa pronta na maquina.', 'error')
    end

    if status.carryingBox then
        return notify('Voce ja esta carregando uma caixa.', 'error')
    end

    if status.deliveryCarry then
        return notify('Entregue a caixa que voce esta carregando primeiro.', 'error')
    end

    if jobVehicle == 0 or not DoesEntityExist(jobVehicle) then
        return notify('Pegue o caminhao com o responsavel antes de retirar a caixa.', 'error')
    end

    local completed = doProgress('Retirando caixa da maquina...', math.min(Leiteiro.job.deliveryTimeMs, 3000), {
        dict = 'anim@heists@box_carry@',
        clip = 'idle',
        flag = 49
    })
    ClearPedTasks(PlayerPedId())

    if not completed then
        return notify('Acao cancelada.', 'inform')
    end

    local ok = OR.Callback.await('orbis-leiteiro:server:pickupMachineBox')
    if ok then
        setStatus({ machineBox = false, carryingBox = true })
        createCarryBox()
        playAnim('anim@heists@box_carry@', 'idle', 49)
        notify('Leve a caixa ate o veiculo do leiteiro.', 'success')
    else
        refreshStatus()
    end
    refreshPanel()
end

local function deliverMilk()
    local status = refreshStatus()
    if not status.active then
        return notify('Inicie o trabalho de leiteiro primeiro.', 'error')
    end

    if not status.deliveryCarry then
        return notify('Retire uma caixa do veiculo antes de entregar.', 'error')
    end

    if carriedBox == 0 or not DoesEntityExist(carriedBox) then
        createCarryBox()
    end
    local completed = doProgress('Descarregando caixa...', Leiteiro.job.deliveryTimeMs, {
        dict = 'anim@heists@box_carry@',
        clip = 'idle',
        flag = 49
    })

    if not completed then
        deleteCarryBox()
        ClearPedTasks(PlayerPedId())
        return notify('Acao cancelada.', 'inform')
    end

    local ok, _, remaining, deliveryIndex, deliveryRemaining, progressData, contractData = OR.Callback.await('orbis-leiteiro:server:deliverMilk')
    if ok then
        setStatus({
            vehicleBoxes = remaining or math.max(0, (status.vehicleBoxes or 1) - 1),
            deliveryIndex = deliveryIndex,
            deliveryRemaining = deliveryRemaining or 0,
            deliveryCarry = false,
            progress = progressData or status.progress,
            contract = contractData or status.contract
        })
        updateDeliveryBlip()
        deleteCarryBox()
        if (remaining or 0) <= 0 then
            SetNewWaypoint(Leiteiro.npc.coords.x, Leiteiro.npc.coords.y)
            notify('Todas as caixas foram entregues. Volte ao responsavel para receber.', 'success')
        end
    else
        refreshStatus()
        deleteCarryBox()
    end
    refreshPanel()

    ClearPedTasks(PlayerPedId())
end

RegisterNetEvent('orbis-leiteiro:client:groupUpdated',function()
    refreshPanel()
end)

RegisterNetEvent('orbis-leiteiro:client:groupInvite',function(invite)
    CreateThread(function()
        local answer=OR.Dialog.Confirm({header='Grupo de Leiteiros',
            content=('%s convidou voce para trabalhar em dupla.'):format(invite.name),centered=true,cancel=true,
            labels={confirm='Entrar',cancel='Recusar'}})
        local ok,message=OR.Callback.await('orbis-leiteiro:server:answerInvite',answer)
        if message then notify(message,ok and'success'or'error') end
        refreshPanel()
    end)
end)

RegisterNetEvent('orbis-leiteiro:client:groupJobStarted',function(bucketAmount)
    setStatus({active=true,machineBox=false,carryingBox=false,deliveryCarry=false,vehicleBoxes=0,
        deliveryIndex=nil,deliveryRemaining=0})
    cowCooldowns={};updateDeliveryBlip()
    notify(('Trabalho em dupla iniciado. Voce recebeu %s baldes.'):format(bucketAmount or 4),'success')
    refreshPanel()
end)

RegisterNetEvent('orbis-leiteiro:client:groupJobStopped',function()
    clearLocalJob();cowCooldowns={}
    notify('O lider finalizou o trabalho do grupo.','inform')
    refreshPanel()
end)

RegisterNetEvent('orbis-leiteiro:client:cowCooldown',function(cowId,seconds)
    cowId=tonumber(cowId);seconds=math.max(0,tonumber(seconds) or 0)
    if cowId then cowCooldowns[cowId]=GetGameTimer()+seconds*1000 end
end)

RegisterNUICallback('close', function(_, cb)
    closePanel()
    cb('ok')
end)

RegisterNUICallback('start', function(_, cb)
    startJob()
    refreshPanel()
    cb('ok')
end)
RegisterNUICallback('stop', function(_, cb)
    stopJob()
    closePanel()
    cb('ok')
end)
RegisterNUICallback('truck', function(_, cb)
    requestDeliveryVehicle()
    refreshPanel()
    cb('ok')
end)
RegisterNUICallback('buckets', function(_, cb)
    requestBuckets()
    refreshPanel()
    cb('ok')
end)
RegisterNUICallback('payment', function(_, cb)
    claimPayment()
    refreshPanel()
    cb('ok')
end)
RegisterNUICallback('invite',function(data,cb)
    local ok,message=OR.Callback.await('orbis-leiteiro:server:inviteMember',data and data.id)
    if message then notify(message,ok and'success'or'error') end
    refreshPanel();cb(ok and'ok'or'fail')
end)
RegisterNUICallback('leaveGroup',function(_,cb)
    local ok,message=OR.Callback.await('orbis-leiteiro:server:leaveGroup')
    if message then notify(message,ok and'success'or'error') end
    refreshPanel();cb(ok and'ok'or'fail')
end)

local function registerCowTarget(index, ped)
    if GetResourceState('ob_target') ~= 'started' or not ped or not DoesEntityExist(ped) then return end

    exports.ob_target:RegisterEntity(('orbis_leiteiro_cow_%s'):format(index), ped, {
        icon = 'fas fa-cow',
        label = 'Ordenhar vaca',
        distance = 3.0,
        event = 'orbis-leiteiro:client:milkCowTarget',
        args = { index },
    })

    -- Reserva por proximidade: animais locais podem nao ser retornados pelo
    -- raycast em todos os artifacts Enhanced. A acao ainda valida no servidor
    -- qual vaca foi usada, distancia, balde e cooldown.
    exports.ob_target:RegisterSphereZone(('orbis_leiteiro_cow_zone_%s'):format(index), {
        coords = GetEntityCoords(ped),
        radius = 2.25,
        option = {
            icon = 'fas fa-cow',
            label = 'Ordenhar vaca',
            event = 'orbis-leiteiro:client:milkCowTarget',
            args = { index },
        },
    })
end

RegisterNetEvent('orbis-leiteiro:client:openPanel', openNpcMenu)
RegisterNetEvent('orbis-leiteiro:client:milkCowTarget', function(_, cowId)
    cowId = tonumber(cowId)
    if cowId then milkCow(cowId) end
end)
RegisterNetEvent('orbis-leiteiro:client:useMachineTarget', function()
    -- O servidor e a fonte da verdade. Assim o texto/acao nao fica preso em
    -- um status local antigo apos restart de recurso ou callback atrasado.
    local status = refreshStatus()
    if status.machineBox then
        pickupMachineBox()
    else
        processMilk()
    end
end)
RegisterNetEvent('orbis-leiteiro:client:deliverMilkTarget', deliverMilk)

local function setupTargets()
    if GetResourceState('ob_target') ~= 'started' or not npcPed or not DoesEntityExist(npcPed) then return end

    exports.ob_target:RegisterEntity('orbis_leiteiro_npc', npcPed, {
        icon = 'fas fa-cow',
        label = 'Falar com leiteiro',
        event = 'orbis-leiteiro:client:openPanel',
        distance = 3.0,
        canInteract = function(entity)
            return entity == npcPed
        end,
    })

    -- Uma unica opcao evita concorrencia entre "processar" e "retirar".
    -- No clique, o status atual vem do servidor e determina a proxima acao.
    exports.ob_target:RegisterSphereZone('orbis_leiteiro_machine', {
        coords = Leiteiro.process.coords,
        radius = 3.0,
        option = {
            icon = 'fas fa-industry',
            label = 'Usar maquina de leite',
            event = 'orbis-leiteiro:client:useMachineTarget',
        },
    })

    local deliveryLocations = Leiteiro.delivery.locations or { Leiteiro.delivery.coords }
    for index, coords in ipairs(deliveryLocations) do
        local zoneId = ('orbis_leiteiro_delivery_%s'):format(index)
        -- Mesmo padrao robusto da maquina: proximidade sem depender da
        -- rotacao do box. O servidor confirma ponto, distancia e a caixa.
        exports.ob_target:RegisterSphereZone(zoneId, {
            coords = coords,
            radius = 3.0,
            option = {
                icon = 'fas fa-truck-ramp-box',
                label = Leiteiro.delivery.label,
                canInteract = function()
                    return jobStatus.active and jobStatus.deliveryCarry and jobStatus.deliveryIndex == index
                end,
                event = 'orbis-leiteiro:client:deliverMilkTarget',
            },
        })
    end
end

CreateThread(function()
    -- Mesmo ciclo do modulo de lojas: so cria ped e target apos o personagem.
    while LocalPlayer.state['or:loaded'] ~= true do Wait(250) end
    refreshStatus()

    npcPed = createPed(Leiteiro.npc.model, Leiteiro.npc.coords)
    if Leiteiro.process.machine then
        processMachine = createObject(Leiteiro.process.machine.model, Leiteiro.process.machine.coords)
    end

    createBlip(Leiteiro.npc.coords, Leiteiro.npc.blip)

    for index, coords in ipairs(Leiteiro.cows or {}) do
        local modelName = Leiteiro.cowModels[math.random(#Leiteiro.cowModels)]
        local ped = createPed(modelName, coords)
        if ped ~= 0 then
            cowPeds[index] = ped
            registerCowTarget(index, ped)
        end
        Wait(50)
    end

    if npcPed ~= 0 then
        setupTargets()
    end
    print(('[ob_leiteirojob] Ponto criado: ped=%s.'):format(tostring(npcPed)))
end)

AddEventHandler('ob_target:client:ready', function()
    setupTargets()
    for index, ped in pairs(cowPeds) do
        registerCowTarget(index, ped)
    end
end)

CreateThread(function()
    while LocalPlayer.state['or:loaded'] ~= true or not npcPed or not DoesEntityExist(npcPed) do Wait(250) end
    setupTargets()
    print('[ob_leiteirojob] Target do NPC registrado apos o carregamento.')
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    cleanupVehicle()
    exports.ob_target:RemoveEntityOption('orbis_leiteiro_npc')
    exports.ob_target:UnregisterZone('orbis_leiteiro_machine')
    -- Compatibilidade com as versoes anteriores durante restart parcial.
    exports.ob_target:UnregisterZone('orbis_leiteiro_process')
    exports.ob_target:UnregisterZone('orbis_leiteiro_pickup_machine_box')
    for index = 1, #(Leiteiro.delivery.locations or { Leiteiro.delivery.coords }) do
        exports.ob_target:UnregisterZone(('orbis_leiteiro_delivery_%s'):format(index))
    end
    for index = 1, #cowPeds do
        exports.ob_target:RemoveEntityOption(('orbis_leiteiro_cow_%s'):format(index))
        exports.ob_target:UnregisterZone(('orbis_leiteiro_cow_zone_%s'):format(index))
    end

    for i = 1, #spawnedPeds do
        if DoesEntityExist(spawnedPeds[i]) then
            DeleteEntity(spawnedPeds[i])
        end
    end

    for i = 1, #spawnedObjects do
        if DoesEntityExist(spawnedObjects[i]) then
            DeleteEntity(spawnedObjects[i])
        end
    end

    deleteCarryBox()
end)
