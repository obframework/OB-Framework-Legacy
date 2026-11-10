local state = { active = false, task = nil, stage = 1, vehicleNetId = nil, vehicle = 0, completed = 0 }
local group = { members = {}, isLeader = true, maxMembers = 2 }
local npc, npcBlip, routeBlip, toolObject = 0, 0, 0, 0
local sparkFx = {}
local panelOpen, resolvedTask, resolving = false, nil, false
local nextResolveAt, unresolvedNoticeTask = 0, nil
local performingRepair = false
local nextSparkAt, jobGeneration, heldToolId = 0, 0, nil
local missingSince, lastHud = nil, ''
local repairPromise, repairSequence = nil, 0

local function finishRepairUI(success)
    if not repairPromise then return end
    local pending = repairPromise
    repairPromise = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'repairClose' })
    pending:resolve(success == true)
end

RegisterNUICallback('repairResult', function(data, cb)
    if repairPromise and data and data.id == repairSequence then finishRepairUI(data.success) end
    cb({ ok = true })
end)

local function playRepairUI(stage)
    repairSequence = repairSequence + 1
    local pending = promise.new()
    repairPromise = pending
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'repairOpen', payload = { id = repairSequence, stage = stage } })
    SetTimeout(65000, function() if repairPromise == pending then finishRepairUI(false) end end)
    return Citizen.Await(pending)
end

local function notify(message, kind) OR.Notify(message, kind or 'info') end

local function loadModel(name, fallback)
    local model = joaat(name)
    if not IsModelInCdimage(model) or not IsModelValid(model) then
        if fallback then return loadModel(fallback) end
        return nil
    end
    RequestModel(model)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(20) end
    if HasModelLoaded(model) then return model end
    if fallback then return loadModel(fallback) end
end

local function deleteNetworkObject(object)
    if object ~= 0 and DoesEntityExist(object) then exports.ob_core:DeleteNetworkedObject(object) end
end

local function clearTool()
    deleteNetworkObject(toolObject)
    toolObject = 0
    heldToolId = nil
    ClearPedSecondaryTask(PlayerPedId())
end

local function removeRoute()
    if routeBlip ~= 0 and DoesBlipExist(routeBlip) then RemoveBlip(routeBlip) end
    routeBlip = 0
end

local function setRoute(coords, label)
    removeRoute()
    routeBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(routeBlip, 354); SetBlipColour(routeBlip, 5); SetBlipScale(routeBlip, 0.82)
    SetBlipRoute(routeBlip, true); SetBlipRouteColour(routeBlip, 5)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString(label); EndTextCommandSetBlipName(routeBlip)
end

local function currentConfig() return state.task and Electrician.tasks[state.task] end

local function resolveMapObject(task)
    local bestCoords, bestDistance, bestObject
    -- Consulta tambem os objetos estaticos do mapa, sem depender de estarem
    -- enumerados no pool de objetos criados por scripts.
    for _, name in ipairs(task.models or {}) do
        local object = GetClosestObjectOfType(task.search.x, task.search.y, task.search.z,
            task.searchRadius or 2.0, joaat(name), false, false, false)
        if object ~= 0 and DoesEntityExist(object) then
            local coords = GetEntityCoords(object)
            local distance = #(coords - task.search)
            if distance <= (task.searchRadius or 35.0) and (not bestDistance or distance < bestDistance) then
                bestCoords, bestDistance, bestObject = coords, distance, object
            end
        end
    end
    if not bestObject then
        local allowed = {}
        for _, name in ipairs(task.models or {}) do allowed[joaat(name)] = true end
        for _, object in ipairs(GetGamePool('CObject')) do
            if allowed[GetEntityModel(object)] then
                local coords = GetEntityCoords(object)
                local distance = #(coords - task.search)
                if distance <= (task.searchRadius or 2.0) and (not bestDistance or distance < bestDistance) then
                    bestCoords, bestDistance, bestObject = coords, distance, object
                end
            end
        end
    end
    if bestCoords then
        local offset = task.repairOffset or vec3(0, 0, task.zOffset or 0.7)
        return GetOffsetFromEntityInWorldCoords(bestObject, offset.x, offset.y, offset.z), true, bestObject
    end

    -- Sem objeto confirmado, a ancora serve somente para orientar a busca.
    return nil, false, nil
end

local function refreshResolvedTask()
    local task = currentConfig()
    if not task then resolvedTask = nil; return end
    local repair, snapped, object = resolveMapObject(task)
    resolvedTask = repair and { index = state.task, repair = repair, snapped = snapped, object = object } or nil
    if resolvedTask then missingSince = nil else missingSince = missingSince or GetGameTimer() end
    nextResolveAt = GetGameTimer() + 2000
end

local function stopSparks()
    for _, handle in ipairs(sparkFx) do StopParticleFxLooped(handle, false) end
    sparkFx = {}
    nextSparkAt = 0
end

local function startSparks()
    if not resolvedTask or state.repaired or state.stage > 1 or GetGameTimer() < nextSparkAt then return end
    local task = currentConfig()
    if not task or #(GetEntityCoords(PlayerPedId()) - task.search) >= (Electrician.work.sparkActivationDistance or 35.0) then return end
    RequestNamedPtfxAsset('core')
    if not HasNamedPtfxAssetLoaded('core') then return end
    nextSparkAt = GetGameTimer() + (Electrician.work.sparkIntervalMs or 650)
    local offsets = task.sparkOffsets or { vec3(0.0, 0.0, 0.0) }
    for _, offset in ipairs(offsets) do
        local p
        if resolvedTask.object and DoesEntityExist(resolvedTask.object) then
            local repairOffset = task.repairOffset or vec3(0, 0, task.zOffset or 0.7)
            p = GetOffsetFromEntityInWorldCoords(resolvedTask.object, repairOffset.x + offset.x, repairOffset.y + offset.y,
                repairOffset.z + offset.z)
        else
            p = resolvedTask.repair + offset
        end
        UseParticleFxAssetNextCall('core')
        StartParticleFxNonLoopedAtCoord(task.sparkName or 'ent_sht_electrical_box',
            p.x, p.y, p.z, 0.0, 0.0, 0.0, task.sparkScale or 1.3, false, false, false)
    end
end

local function resolveVehicle()
    if state.vehicle ~= 0 and DoesEntityExist(state.vehicle) then return state.vehicle end
    if not state.vehicleNetId then return 0 end
    state.vehicle = OR.Entity.AwaitNetwork(state.vehicleNetId, 5000) or 0
    return state.vehicle
end

local function takeTool(toolId)
    if toolObject ~= 0 or performingRepair then return end
    local cfg = Electrician.tools[toolId]
    if not cfg then return end
    local model = loadModel(cfg.model, cfg.fallbackModel)
    if not model then return notify('A ferramenta nao carregou.', 'error') end
    local ok, message = OR.Callback.await('orbis-electrician:server:takeTool', toolId)
    if not ok then return notify(message or 'Ferramenta indisponivel.', 'error') end
    local ped = PlayerPedId()
    toolObject = exports.ob_core:CreateNetworkedObject(model, GetEntityCoords(ped), false)
    if not toolObject or toolObject == 0 then
        toolObject = 0
        OR.Callback.await('orbis-electrician:server:returnTool')
        return notify('A ferramenta nao apareceu. Tente novamente.', 'error')
    end
    AttachEntityToEntity(toolObject, ped, GetPedBoneIndex(ped, cfg.bone), cfg.offset.x, cfg.offset.y, cfg.offset.z,
        cfg.rotation.x, cfg.rotation.y, cfg.rotation.z, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)
    heldToolId = toolId
    notify(('Voce pegou %s. Va ate o defeito.'):format(cfg.label), 'success')
end

local function returnTool()
    local ok, message = OR.Callback.await('orbis-electrician:server:returnTool')
    if ok then clearTool() else notify(message or 'Nao foi possivel guardar a ferramenta.', 'error') end
end

local function runMinigame()
    if performingRepair or state.repaired then return end
    if not resolvedTask or heldToolId ~= state.toolId then return notify('Guarde a ferramenta e pegue a indicada para esta etapa.', 'error') end
    performingRepair = true
    local stage, generation, repair = state.stage, jobGeneration, resolvedTask.repair
    local allowed, message = OR.Callback.await('orbis-electrician:server:beginStep', stage)
    if not allowed then performingRepair = false; return notify(message or 'Etapa indisponivel.', 'error') end
    local ped = PlayerPedId()
    local anim = Electrician.repairAnimation
    local started = GetGameTimer()
    CreateThread(function()
        while performingRepair and generation == jobGeneration do
            if IsEntityDead(ped) or #(GetEntityCoords(ped) - repair) > Electrician.work.interactionDistance + 0.5
                or GetGameTimer() - started > Electrician.work.stepTimeoutMs then
                finishRepairUI(false)
                break
            end
            Wait(200)
        end
    end)
    local executed, success = pcall(function()
        TaskTurnPedToFaceCoord(ped, repair.x, repair.y, repair.z, 500)
        Wait(500)
        RequestAnimDict(anim.dict)
        local deadline = GetGameTimer() + 4000
        while not HasAnimDictLoaded(anim.dict) and GetGameTimer() < deadline do Wait(20) end
        if not HasAnimDictLoaded(anim.dict) or generation ~= jobGeneration then return false end
        TaskPlayAnim(ped, anim.dict, anim.clip, 4.0, -4.0, -1, 49, 0.0, false, false, false)
        if IsEntityDead(ped) or #(GetEntityCoords(ped) - repair) > Electrician.work.interactionDistance + 0.5 then return false end
        return playRepairUI(stage)
    end)
    StopAnimTask(ped, anim.dict, anim.clip, 2.0)
    ClearPedSecondaryTask(ped)
    if generation ~= jobGeneration then performingRepair = false; return end
    local ok, completed = OR.Callback.await('orbis-electrician:server:finishStep', stage, executed and success == true)
    performingRepair = false
    if not ok then return notify(completed or 'Reparo falhou. Tente novamente.', 'error') end
    if completed then
        notify('Reparo concluido. Guarde a ferramenta no caminhao e finalize o chamado.', 'success')
    else
        local nextStep = Electrician.steps[stage + 1]
        notify(('Etapa concluida! Guarde a ferramenta e pegue %s para %s.'):format(Electrician.tools[nextStep.tool].label, nextStep.label), 'success')
    end
end

local function completeService()
    local ok, message = OR.Callback.await('orbis-electrician:server:completeService')
    if message then notify(message, ok and 'success' or 'error') end
end

local function cleanupJob()
    jobGeneration = jobGeneration + 1
    finishRepairUI(false)
    performingRepair = false
    stopSparks(); removeRoute(); clearTool()
    state = { active = false, task = nil, stage = 1, vehicleNetId = nil, vehicle = 0, completed = 0 }
    resolvedTask, nextResolveAt, unresolvedNoticeTask = nil, 0, nil
    missingSince, lastHud = nil, ''
    OR.Help.Hide()
    SendNUIMessage({ action = 'jobHud', payload = false })
    if panelOpen then panelOpen = false; SetNuiFocus(false, false); SendNUIMessage({ action = 'close' }) end
    StopAnimTask(PlayerPedId(), Electrician.repairAnimation.dict, Electrician.repairAnimation.clip, 2.0)
end

local function applyJob(payload)
    payload = payload or { active = false }
    if not payload.active then cleanupJob(); return end
    local oldTask = state.task
    for key, value in pairs(payload) do state[key] = value end
    state.vehicle = resolveVehicle()
    if oldTask ~= state.task then
        jobGeneration = jobGeneration + 1
        missingSince = nil
        stopSparks(); clearTool(); unresolvedNoticeTask = nil; refreshResolvedTask()
        local task = currentConfig()
        if task then
            setRoute(task.search, task.label)
            local tool = Electrician.tools[state.toolId]
            if tool then notify(('Chamado: %s. Ferramenta: %s.'):format(task.label, tool.label)) end
        end
    end
    if state.toolHolder ~= GetPlayerServerId(PlayerId()) then clearTool() end
    if state.repaired or state.stage > 1 then stopSparks() else startSparks() end
end
RegisterNetEvent('orbis-electrician:client:applyJob', applyJob)
RegisterNetEvent('orbis-electrician:client:jobSync', applyJob)

RegisterNetEvent('orbis-electrician:client:groupUpdated', function(payload)
    group = payload or group
    if panelOpen then TriggerEvent('orbis-electrician:client:refreshPanel') end
end)

RegisterNetEvent('orbis-electrician:client:invite', function(name)
    CreateThread(function()
        local accept = OR.Dialog.Confirm({ header = 'Dupla de eletricistas', content = ('%s convidou voce para trabalhar em dupla.'):format(name), centered = true, cancel = true, labels = { confirm = 'Entrar', cancel = 'Recusar' } })
        local ok, message = OR.Callback.await('orbis-electrician:server:answerInvite', accept)
        if message then notify(message, ok and 'success' or 'error') end
    end)
end)

RegisterNetEvent('orbis-electrician:client:paid', function(payment, xp)
    notify(('Rota de 5 servicos paga: %s | +%s XP'):format(OR.FormatMoney(payment), xp), 'success')
end)

local function getNearbyPlayers()
    local result, coords = {}, GetEntityCoords(PlayerPedId())
    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() then
            local ped = GetPlayerPed(player)
            if ped ~= 0 and #(coords - GetEntityCoords(ped)) <= Electrician.group.inviteDistance then
                result[#result + 1] = { id = GetPlayerServerId(player), name = GetPlayerName(player) or ('ID %s'):format(GetPlayerServerId(player)) }
            end
        end
    end
    return result
end

local function refreshPanel(open)
    local data = OR.Callback.await('orbis-electrician:server:getPanelData')
    if not data then return end
    group = data.group or group
    data.nearby, data.tutorial = getNearbyPlayers(), Electrician.tutorial
    if open then panelOpen = true; SetNuiFocus(true, true); SendNUIMessage({ action = 'open', payload = data })
    else SendNUIMessage({ action = 'update', payload = data }) end
end
RegisterNetEvent('orbis-electrician:client:refreshPanel', function() refreshPanel(false) end)

local function closePanel() panelOpen = false; SetNuiFocus(false, false); SendNUIMessage({ action = 'close' }) end

local function startJob()
    local ok, payload = OR.Callback.await('orbis-electrician:server:startJob')
    if not ok then return notify(payload or 'Nao foi possivel iniciar.', 'error') end
    applyJob(payload); notify(#(group.members or {}) >= 2 and 'Turno em dupla iniciado. Servicos aereos foram liberados.' or 'Turno individual iniciado. Somente servicos no solo.', 'success')
    refreshPanel(false)
end

local function spawnTruck()
    local ok, result = OR.Callback.await('orbis-electrician:server:spawnVehicle')
    if not ok or type(result) ~= 'table' then return notify(result or 'Nao foi possivel retirar o caminhao.', 'error') end
    state.vehicleNetId, state.vehicle = result.netId, OR.Entity.AwaitNetwork(result.netId, 10000) or 0
    if state.vehicle == 0 then return notify('O caminhao nao sincronizou.', 'error') end
    SetVehicleOnGroundProperly(state.vehicle); SetVehicleFuelLevel(state.vehicle, 100.0)
    TriggerEvent('vehiclekeys:client:SetOwner', GetVehicleNumberPlateText(state.vehicle))
    refreshPanel(false)
    notify('Caminhao retirado. Siga para o chamado marcado.', 'success')
end

RegisterNUICallback('close', function(_, cb) closePanel(); cb('ok') end)
RegisterNUICallback('start', function(_, cb) startJob(); cb('ok') end)
RegisterNUICallback('stop', function(_, cb)
    local ok, message = OR.Callback.await('orbis-electrician:server:stopJob')
    if not ok then notify(message or 'Nao foi possivel finalizar.', 'error') else cleanupJob(); closePanel(); notify('Turno finalizado.', 'inform') end
    cb(ok and 'ok' or 'fail')
end)
RegisterNUICallback('truck', function(_, cb) spawnTruck(); cb('ok') end)
RegisterNUICallback('invite', function(data, cb)
    local ok, message = OR.Callback.await('orbis-electrician:server:invite', data and data.id)
    if message then notify(message, ok and 'success' or 'error') end
    refreshPanel(false); cb(ok and 'ok' or 'fail')
end)
RegisterNUICallback('leaveGroup', function(_, cb)
    local ok, message = OR.Callback.await('orbis-electrician:server:leaveGroup')
    if message then notify(message, ok and 'success' or 'error') end
    refreshPanel(false); cb(ok and 'ok' or 'fail')
end)

RegisterNetEvent('orbis-electrician:client:openPanel', function()
    if not panelOpen then refreshPanel(true) end
end)

local MarkerTypeUpsideDownCone = 0

local function drawWorldText(coords, text)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    SetTextFont(4)
    SetTextScale(0.0, 0.31)
    SetTextColour(255, 255, 255, 235)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function drawInteractionMarker(coords, color, scale)
    scale = scale or Electrician.vehicle.markerScale or 0.38
    DrawMarker(MarkerTypeUpsideDownCone, coords.x, coords.y, coords.z + 0.32, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        scale, scale, 0.28, color[1], color[2], color[3], color[4], false, false, 2, false, nil, nil, false)
end

local function drawNearbyInteraction(playerCoords, point, label, color, drawDistance, scale)
    if not point then return math.huge end
    local distance = #(playerCoords - point)
    if distance <= (drawDistance or 22.0) then
        drawInteractionMarker(point, color, scale)
        if distance <= 7.0 and label then drawWorldText(point + vec3(0.0, 0.0, 0.72), label) end
    end
    return distance
end

local function groundAdjustedPoint(vehicle, x, y, z)
    local point = GetOffsetFromEntityInWorldCoords(vehicle, x, y, z)
    local foundGround, groundZ = GetGroundZFor_3dCoord(point.x, point.y, point.z + 2.0, false)
    return vec3(point.x, point.y, foundGround and groundZ or point.z)
end

local function truckSidePoints(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return nil, nil end
    local minimum, maximum = GetModelDimensions(GetEntityModel(vehicle))
    local gap = Electrician.vehicle.sideMarkerGap or 0.45
    local y = Electrician.vehicle.sideMarkerY or 0.35
    local z = (minimum and minimum.z or -0.5) + 0.08
    local leftX = (minimum and minimum.x or -1.2) - gap
    local rightX = (maximum and maximum.x or 1.2) + gap
    return groundAdjustedPoint(vehicle, leftX, y, z), groundAdjustedPoint(vehicle, rightX, y, z)
end

local registerNpcTarget

CreateThread(function()
    while true do
        if not state.active then Wait(700) else
            local task, ped = currentConfig(), PlayerPedId()
            if not task then Wait(500) else
                local coords = GetEntityCoords(ped)
                local distanceToTask = #(coords - task.search)
                local help, interaction
                local localServerId = GetPlayerServerId(PlayerId())
                local drawDistance = Electrician.vehicle.markerDrawDistance or 22.0
                if distanceToTask < 80.0 and GetGameTimer() >= nextResolveAt and not resolving then
                    resolving = true; refreshResolvedTask(); resolving = false
                end

                if distanceToTask < (Electrician.work.sparkActivationDistance or 35.0) then
                    RequestCollisionAtCoord(task.search.x, task.search.y, task.search.z)
                    startSparks()
                else
                    stopSparks()
                end

                if resolvedTask and not state.repaired and distanceToTask < Electrician.work.routeMarkerDistance then
                    local repairLabel = heldToolId == state.toolId and ('[E] ' .. Electrician.steps[state.stage].label) or 'Defeito eletrico'
                    local repairDistance = drawNearbyInteraction(coords, resolvedTask.repair, repairLabel,
                        { 255, 210, 0, 230 }, Electrician.work.routeMarkerDistance or 45.0, 0.34)
                    if toolObject ~= 0 and heldToolId == state.toolId and not performingRepair
                        and repairDistance <= Electrician.work.interactionDistance then
                        help, interaction = repairLabel, runMinigame
                    end
                end

                local vehicle, sideDistance = resolveVehicle(), math.huge
                if vehicle ~= 0 and DoesEntityExist(vehicle) and GetEntitySpeed(vehicle) < 0.5
                    and #(GetEntityCoords(vehicle) - task.search) <= (Electrician.work.truckTaskDistance or 38.0) then
                    local sideLabel, sideAction
                    if state.toolHolder == localServerId then
                        if state.repaired or heldToolId ~= state.toolId then
                            sideLabel, sideAction = '[E] Guardar ferramenta', returnTool
                        else
                            sideLabel = 'Leve a ferramenta ate o defeito'
                        end
                    elseif state.toolHolder then
                        sideLabel = 'Ferramenta em uso pelo parceiro'
                    elseif state.repaired then
                        sideLabel, sideAction = '[E] Finalizar chamado', completeService
                    else
                        local tool = Electrician.tools[state.toolId]
                        sideLabel = ('[E] Pegar %s'):format(tool and tool.label or 'ferramenta')
                        sideAction = function() takeTool(state.toolId) end
                    end

                    local leftPoint, rightPoint = truckSidePoints(vehicle)
                    local leftDistance = drawNearbyInteraction(coords, leftPoint, sideLabel,
                        { 55, 190, 255, 225 }, drawDistance, Electrician.vehicle.markerScale)
                    local rightDistance = drawNearbyInteraction(coords, rightPoint, sideLabel,
                        { 55, 190, 255, 225 }, drawDistance, Electrician.vehicle.markerScale)
                    sideDistance = math.min(leftDistance, rightDistance)
                    if sideAction and sideDistance <= Electrician.work.interactionDistance then
                        help, interaction = sideLabel, sideAction
                    end
                end

                if not resolvedTask and missingSince and GetGameTimer() - missingSince > 10000 and distanceToTask < 20.0 then
                    help = '[E] Objeto indisponivel neste mapa: solicitar outro chamado'
                    interaction = function()
                        local ok, message = OR.Callback.await('orbis-electrician:server:unavailableTask')
                        if not ok then notify(message or 'Nao foi possivel trocar o chamado.', 'error') end
                    end
                end
                if help and interaction and not performingRepair then
                    OR.Help.Show(help)
                    if IsControlJustReleased(0, 38) then OR.Help.Hide(); interaction() end
                else
                    OR.Help.Hide()
                end
                Wait((distanceToTask < 80.0 or sideDistance < drawDistance) and 0 or 400)
            end
        end
    end
end)

CreateThread(function()
    while LocalPlayer.state['or:loaded'] ~= true do Wait(250) end
    local status, payloadGroup = OR.Callback.await('orbis-electrician:server:getStatus')
    group = payloadGroup or group; applyJob(status)
    local cfg, model = Electrician.npc, loadModel(Electrician.npc.model)
    if model then
        npc = CreatePed(4, model, cfg.coords.x, cfg.coords.y, cfg.coords.z - 1.0, cfg.coords.w, false, true)
        FreezeEntityPosition(npc, true); SetEntityInvincible(npc, true); SetBlockingOfNonTemporaryEvents(npc, true)
        SetModelAsNoLongerNeeded(model)
    end
    npcBlip = AddBlipForCoord(cfg.coords.x, cfg.coords.y, cfg.coords.z)
    SetBlipSprite(npcBlip, cfg.blip.sprite); SetBlipColour(npcBlip, cfg.blip.color); SetBlipScale(npcBlip, cfg.blip.scale); SetBlipAsShortRange(npcBlip, true)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString(cfg.blip.name); EndTextCommandSetBlipName(npcBlip)
end)

registerNpcTarget = function()
    if npc == 0 or not DoesEntityExist(npc) or GetResourceState('ob_target') ~= 'started' then return end
    exports.ob_target:RegisterEntity('orbis_electrician_npc', npc, {
        icon = 'fas fa-bolt',
        label = 'Falar com encarregado',
        event = 'orbis-electrician:client:openPanel',
        distance = 3.0,
        canInteract = function(entity) return entity == npc end,
    })
end

AddEventHandler('ob_target:client:ready', registerNpcTarget)

CreateThread(function()
    while LocalPlayer.state['or:loaded'] ~= true or npc == 0 or not DoesEntityExist(npc) do Wait(250) end
    registerNpcTarget()
end)

-- Ferramenta de manutencao: imprime uma linha pronta para a configuracao e o
-- modelo do objeto de mapa mais proximo. Nao altera nem salva nada sozinho.
RegisterCommand('eletricistaponto', function(_, args)
    local ped, coords = PlayerPedId(), GetEntityCoords(PlayerPedId())
    local closest, distance
    for _, object in ipairs(GetGamePool('CObject')) do
        local current = #(coords - GetEntityCoords(object))
        if current < 12.0 and (not distance or current < distance) then closest, distance = object, current end
    end
    local archetype = 'desconhecido'
    if closest then
        local ok, value = pcall(GetEntityArchetypeName, closest)
        if ok and value and value ~= '' then archetype = value end
    end
    print(('[ob_electricianjob] %s = vec3(%.4f, %.4f, %.4f), heading = %.2f, objeto = %s, hash = %s (%s)'):format(
        args[1] or 'ponto', coords.x, coords.y, coords.z, GetEntityHeading(ped), archetype,
        closest ~= nil and GetEntityModel(closest) or 0, distance and ('%.2fm'):format(distance) or 'nenhum'))
    notify('Coordenada impressa no F8.', 'success')
end, false)

-- Ferramenta de aprendizado: mire no ponto desejado de um carro/prop e use
-- /eletricistaoffset. O F8 recebe tanto a coordenada mundial quanto o offset
-- local da entidade, pronto para GetOffsetFromEntityInWorldCoords.
local function cameraDirection(rotation)
    local rx, rz = math.rad(rotation.x), math.rad(rotation.z)
    return vec3(-math.sin(rz) * math.abs(math.cos(rx)), math.cos(rz) * math.abs(math.cos(rx)), math.sin(rx))
end

local function cameraHitPoint(distance)
    local origin = GetGameplayCamCoord()
    local destination = origin + (cameraDirection(GetGameplayCamRot(2)) * (distance or 30.0))
    local handle = StartShapeTestLosProbe(origin.x, origin.y, origin.z,
        destination.x, destination.y, destination.z, 511, PlayerPedId(), 7)
    local deadline = GetGameTimer() + 1500
    while GetGameTimer() < deadline do
        local status, hit, point, _, entity = GetShapeTestResult(handle)
        if status == 2 then return hit == true or hit == 1, point, entity end
        Wait(0)
    end
    return false
end

RegisterCommand('eletricistaoffset', function()
    CreateThread(function()
        local hit, point, entity = cameraHitPoint(40.0)
        if not hit or not point then return notify('Mire em uma parte visivel do veiculo ou objeto.', 'error') end

        print(('[ob_electricianjob] mundo = vec3(%.4f, %.4f, %.4f)'):format(point.x, point.y, point.z))
        if entity and entity ~= 0 and DoesEntityExist(entity) then
            local offset = GetOffsetFromEntityGivenWorldCoords(entity, point.x, point.y, point.z)
            local archetype = 'desconhecido'
            local ok, value = pcall(GetEntityArchetypeName, entity)
            if ok and value and value ~= '' then archetype = value end
            print(('[ob_electricianjob] entidade=%s modelo=%s tipo=%s offset local = vec3(%.4f, %.4f, %.4f)'):format(
                archetype, GetEntityModel(entity), GetEntityType(entity), offset.x, offset.y, offset.z))
        else
            print('[ob_electricianjob] Nenhuma entidade foi retornada; use apenas a coordenada mundial acima.')
        end

        local expires = GetGameTimer() + 10000
        while GetGameTimer() < expires do
            DrawMarker(MarkerTypeUpsideDownCone, point.x, point.y, point.z + 0.32, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                0.38, 0.38, 0.28, 255, 210, 0, 230, false, false, 2, false, nil, nil, false)
            Wait(0)
        end
    end)
end, false)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    cleanupJob()
    if GetResourceState('ob_target') == 'started' then exports.ob_target:RemoveEntityOption('orbis_electrician_npc') end
    if npc ~= 0 and DoesEntityExist(npc) then DeleteEntity(npc) end
    if npcBlip ~= 0 and DoesBlipExist(npcBlip) then RemoveBlip(npcBlip) end
end)
CreateThread(function()
    while true do
        if state.active then
            if state.vehicle == 0 and state.vehicleNetId then resolveVehicle() end
            local task = currentConfig()
            if task then
                local instruction = 'Siga o GPS ate o chamado.'
                if not state.vehicleNetId then instruction = 'Retire o caminhao com o encarregado.'
                elseif state.vehicle == 0 or not DoesEntityExist(state.vehicle)
                    or #(GetEntityCoords(state.vehicle) - task.search) > (Electrician.work.truckTaskDistance or 38.0) then
                    instruction = 'Leve o caminhao ate a area do chamado.'
                elseif state.toolHolder then
                    if state.toolHolder == GetPlayerServerId(PlayerId()) then
                        instruction = (state.repaired or heldToolId ~= state.toolId)
                            and 'Volte a uma lateral do caminhao e guarde a ferramenta.'
                            or 'Leve a ferramenta ate o defeito.'
                    else
                        instruction = 'Seu parceiro esta usando a ferramenta.'
                    end
                elseif state.repaired then
                    instruction = 'Va ate uma das laterais do caminhao e finalize o chamado.'
                else
                    instruction = 'Pegue ' .. Electrician.tools[state.toolId].label .. ' em uma das laterais do caminhao.'
                end
                if task.type == 'aerial' and not state.repaired then instruction = instruction .. ' Dupla: motorista H + setas; reparador na cesta.' end
                if not resolvedTask and missingSince and GetGameTimer() - missingSince > 10000 and #(GetEntityCoords(PlayerPedId()) - task.search) < 20.0 then
                    instruction = 'Objeto nao encontrado neste mapa. Pressione E perto do destino para trocar o chamado.'
                end
                local signature = table.concat({state.task, state.stage, state.batchCompleted or 0, instruction}, '|')
                if signature ~= lastHud then
                    lastHud = signature
                    SendNUIMessage({ action = 'jobHud', payload = { title = task.label, step = Electrician.steps[state.stage].label,
                        stage = state.stage, total = #Electrician.steps, instruction = instruction, completed = state.batchCompleted or 0, batch = state.batchSize or 5 } })
                end
            end
        end
        Wait(400)
    end
end)
