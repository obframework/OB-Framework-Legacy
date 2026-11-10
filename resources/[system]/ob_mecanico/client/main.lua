local tuning = { open = false, vehicle = nil, original = nil, station = nil, camera = nil, visualFlags = {}, toggleStates = {}, extraStates = {}, markupPercent = 0 }
local optionByKey = {}
for _, section in ipairs(OBMechanicConfig.Sections) do
    for _, option in ipairs(section.options) do optionByKey[option.key] = option end
end

local function nearestVehicle()
    local coords = GetEntityCoords(PlayerPedId())
    return GetClosestVehicle(coords.x, coords.y, coords.z, 4.0, 0, 71)
end

local workshopAction, requestControl
local jackedVehicles = {}
local tyreActionActive = false
local removedTyres = {}
local tyreTypes = {}
local replicatedRemovedTyres = {}

local function enableVehicleDamage(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    SetEntityInvincible(vehicle, false)
    SetEntityCanBeDamaged(vehicle, true)
    SetVehicleCanBeVisiblyDamaged(vehicle, true)
    SetVehicleEngineCanDegrade(vehicle, true)
end

local function clearCriticalEngineState(vehicle)
    StopEntityFire(vehicle)
    if type(SetDisableVehicleEngineFires) == 'function' then SetDisableVehicleEngineFires(vehicle, false) end
    if type(SetDisableVehiclePetrolTankFires) == 'function' then SetDisableVehiclePetrolTankFires(vehicle, false) end
    if type(SetDisableVehiclePetrolTankDamage) == 'function' then SetDisableVehiclePetrolTankDamage(vehicle, false) end
    if type(SetVehicleCanLeakOil) == 'function' then SetVehicleCanLeakOil(vehicle, true) end
    if type(SetVehicleCanLeakPetrol) == 'function' then SetVehicleCanLeakPetrol(vehicle, true) end
    SetVehicleUndriveable(vehicle, false)
end

local function tyreStateKey(vehicle)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    return netId > 0 and ('net:%s'):format(netId) or ('local:%s'):format(vehicle)
end

local function isTyreRemoved(vehicle, wheel)
    return removedTyres[tyreStateKey(vehicle)] and removedTyres[tyreStateKey(vehicle)][wheel] == true
end

local function setTyreRemoved(vehicle, wheel, removed)
    local key = tyreStateKey(vehicle)
    removedTyres[key] = removedTyres[key] or {}
    removedTyres[key][wheel] = removed == true

    -- Mantem o estado na propria entidade. Alem de evitar que uma roda traseira
    -- de addon seja confundida com apenas "murcha", isto permite a garagem
    -- salvar exatamente quais rodas foram retiradas.
    local snapshot, hasRemoved = {}, false
    for index, state in pairs(removedTyres[key]) do
        if state == true then
            snapshot[tostring(index)] = true
            hasRemoved = true
        end
    end
    if not hasRemoved then removedTyres[key] = nil end
end

local function getTyreType(vehicle, wheel)
    local key = tyreStateKey(vehicle)
    local localType = tyreTypes[key] and tyreTypes[key][wheel]
    if localType == 'tyre_normal' or localType == 'tyre_armored' then return localType end

    local synced = DoesEntityExist(vehicle) and Entity(vehicle).state['ob:tyre_types'] or nil
    local syncedType = type(synced) == 'table' and synced[tostring(wheel)] or nil
    return syncedType == 'tyre_armored' and 'tyre_armored' or 'tyre_normal'
end

local function setTyreType(vehicle, wheel, itemName)
    local key = tyreStateKey(vehicle)
    tyreTypes[key] = tyreTypes[key] or {}
    tyreTypes[key][wheel] = (itemName == 'tyre_normal' or itemName == 'tyre_armored') and itemName or nil

    local snapshot, hasTypes = {}, false
    for index, tyreType in pairs(tyreTypes[key]) do
        if tyreType == 'tyre_armored' then
            snapshot[tostring(index)] = tyreType
            hasTypes = true
        end
    end
    if not hasTypes then tyreTypes[key] = nil end
end

local wheels = {
    { index = 0, bone = 'wheel_lf', side = 'left' }, { index = 1, bone = 'wheel_rf', side = 'right' },
    -- Indices nativos GTA: eixo do meio 2/3 e eixo traseiro 4/5.
    -- A versao anterior tinha traseira e meio invertidos: o alvo da roda
    -- traseira consultava outro pneu e por isso tentava remove-lo.
    { index = 2, bone = 'wheel_lm', side = 'left' }, { index = 3, bone = 'wheel_rm', side = 'right' },
    { index = 4, bone = 'wheel_lr', side = 'left' }, { index = 5, bone = 'wheel_rr', side = 'right' },
    -- Eixos extras de alguns caminhoes usam estes indices, nao 6/7.
    { index = 45, bone = 'wheel_lm1', side = 'left' }, { index = 47, bone = 'wheel_rm1', side = 'right' },
}

-- O GTA diferencia pneu murcho e pneu ja no aro. Para a mecanica os dois
-- significam que a roda precisa receber um pneu antes de voltar a dirigir.
local function isTyreBurst(vehicle, wheelIndex)
    return IsVehicleTyreBurst(vehicle, wheelIndex, false)
        or IsVehicleTyreBurst(vehicle, wheelIndex, true)
end

local function wheelCoords(vehicle, wheel)
    -- Os ossos addon podem ter altura errada, mas normalmente acertam a
    -- posicao longitudinal da roda. Corrigimos apenas altura e lateralidade.
    local bone = GetEntityBoneIndexByName(vehicle, wheel.bone)
    if bone ~= -1 then
        local point = GetWorldPositionOfEntityBone(vehicle, bone)
        -- GetEntityRightVector nao existe em algumas builds do FiveM.
        local heading = math.rad(GetEntityHeading(vehicle))
        local right = vector3(math.cos(heading), math.sin(heading), 0.0)
        local offset = wheel.side == 'left' and -0.30 or 0.30
        local x, y = point.x + right.x * offset, point.y + right.y * offset
        local found, ground = GetGroundZFor_3dCoord(x, y, point.z + 3.0, false)
        return vector3(x, y, (found and ground or point.z) + 0.10)
    end

    local minimum, maximum = GetModelDimensions(GetEntityModel(vehicle))
    local frontY = maximum.y * 0.62
    local rearY = minimum.y * 0.62
    local y = wheel.index < 2 and frontY or rearY
    if wheel.index == 4 or wheel.index == 5 then y = (frontY + rearY) * 0.15 end
    if wheel.index == 6 or wheel.index == 7 then y = (frontY + rearY) * -0.15 end
    local x = wheel.side == 'left' and minimum.x - 0.22 or maximum.x + 0.22
    return GetOffsetFromEntityInWorldCoords(vehicle, x, y, minimum.z + 0.12)
end

local function jackCoords(vehicle, side)
    -- O macaco deve ficar no meio da lateral. Usar a media das rodas em carros
    -- modificados fazia o prop parar em cima de uma roda ou fora do veiculo.
    return GetOffsetFromEntityInWorldCoords(vehicle, side == 'left' and -0.52 or 0.52, 0.0, -0.72)
end

local function closestWheel(vehicle)
    local here, best, bestDistance = GetEntityCoords(PlayerPedId()), nil, 999.0
    for _, wheel in ipairs(wheels) do
        local distance = #(here - wheelCoords(vehicle, wheel))
        if distance < bestDistance then best, bestDistance = wheel, distance end
    end
    return best, bestDistance
end

local function hasWrench()
    return GetSelectedPedWeapon(PlayerPedId()) == joaat('WEAPON_WRENCH')
end

local function requestModel(name)
    local model = joaat(name)
    RequestModel(model)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    return HasModelLoaded(model) and model or nil
end

local function unregisterJackTargets(entry)
    if GetResourceState('ob_target') == 'started' then
        for _, id in ipairs(entry.targets or {}) do exports.ob_target:RemoveEntityOption(id) end
        for _, id in ipairs(entry.zones or {}) do exports.ob_target:UnregisterZone(id) end
    end
    entry.targets = {}
    entry.zones = {}
end

local function clearWheelProbes(entry)
    for _, probe in pairs(entry.probes or {}) do
        -- Versoes anteriores usavam props invisiveis como ponto de target.
        -- Limpe-os se ainda existirem, mas os pontos atuais sao apenas
        -- coordenadas para nao depender de raycast/entidade invisivel.
        if probe.entity and DoesEntityExist(probe.entity) then DeleteObject(probe.entity) end
    end
    entry.probes = {}
end

local function readPoint(raw)
    if type(raw) ~= 'table' then return nil end
    local x, y, z = tonumber(raw.x), tonumber(raw.y), tonumber(raw.z)
    return x and y and z and vector3(x, y, z) or nil
end

local function clearJackEntry(netId, restoreVehicle)
    local entry = jackedVehicles[netId]
    if not entry then return end
    unregisterJackTargets(entry)
    clearWheelProbes(entry)
    if DoesEntityExist(entry.prop) then DeleteObject(entry.prop) end

    local vehicle = entry.vehicle
    if restoreVehicle and DoesEntityExist(vehicle) and entry.coords and entry.rotation then
        FreezeEntityPosition(vehicle, false)
        SetVehicleHandbrake(vehicle, false)
        SetEntityCoordsNoOffset(vehicle, entry.coords.x, entry.coords.y, entry.coords.z, false, false, false)
        SetEntityRotation(vehicle, entry.rotation.x, entry.rotation.y, entry.rotation.z, 2, true)
        SetVehicleOnGroundProperly(vehicle)
    end
    jackedVehicles[netId] = nil
end

local function removeJack(vehicle)
    local netId, entry = NetworkGetNetworkIdFromEntity(vehicle), jackedVehicles[NetworkGetNetworkIdFromEntity(vehicle)]
    if not entry then return OR.Notify('Nao ha macaco neste veiculo.', 'error') end
    if not OR.Progress.Run({ label = 'Retirando macaco...', duration = 1800, animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 } }) then return end
    TriggerServerEvent('ob_mecanico:server:removeJackState', netId)
end

local function captureConditionBeforeWheelRestore(vehicle, wheelToRestore)
    local state = {
        engine = GetVehicleEngineHealth(vehicle),
        body = GetVehicleBodyHealth(vehicle),
        dirt = GetVehicleDirtLevel(vehicle),
        burstTyres = {},
    }

    for _, data in ipairs(wheels) do
        local index = data.index
        if index ~= wheelToRestore and IsVehicleTyreBurst(vehicle, index, false) then
            state.burstTyres[index] = IsVehicleTyreBurst(vehicle, index, true)
        end
    end
    return state
end

local function restoreBrokenWheel(vehicle, wheel)
    -- BREAK_OFF_VEHICLE_WHEEL nao possui uma native para recolocar somente a
    -- roda. SET_VEHICLE_FIXED a recria, entao restauramos imediatamente os
    -- danos que importam para nao transformar a troca de pneu em reparo geral.
    local condition = captureConditionBeforeWheelRestore(vehicle, wheel.index)
    SetVehicleFixed(vehicle)
    SetVehicleEngineHealth(vehicle, condition.engine)
    SetVehicleBodyHealth(vehicle, condition.body)
    SetVehicleDirtLevel(vehicle, condition.dirt)
    SetVehicleTyresCanBurst(vehicle, true)
    enableVehicleDamage(vehicle)

    for index, onRim in pairs(condition.burstTyres) do
        SetVehicleTyreBurst(vehicle, index, onRim == true, 1000.0)
    end
end

local function replaceTyre(vehicle, wheel)
    if not hasWrench() then return OR.Notify('Equipe a chave inglesa para trocar o pneu.', 'error') end
    if not isTyreRemoved(vehicle, wheel.index) and not isTyreBurst(vehicle, wheel.index) then return OR.Notify('Esse pneu nao foi removido nem esta furado.', 'error') end
    local itemName
    if OR.Callback.awaitResource('ob_inventory', 'hasTargetTyre', 'tyre_normal') == true then
        itemName = 'tyre_normal'
    elseif OR.Callback.awaitResource('ob_inventory', 'hasTargetTyre', 'tyre_armored') == true then
        itemName = 'tyre_armored'
    else
        return OR.Notify('Voce precisa de um pneu na mochila.', 'error')
    end
    if exports.ob_minigame:PrecisionBar({ steps = 3 }) ~= true then return OR.Notify('Falha ao instalar o pneu.', 'error') end
    if not workshopAction('Instalando pneu...', 6000, 3) then return end
    if not requestControl(vehicle) then
        return OR.Notify('Nao foi possivel controlar este veiculo para trocar o pneu.', 'error')
    end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local authorized, authorizationMessage = OR.Callback.awaitResource('ob_mecanico', 'completeTyreAction', netId, wheel.index, 'install', itemName)
    if not authorized then return OR.Notify(authorizationMessage or 'O servidor recusou a troca do pneu.', 'error') end
    local brokenOff = type(IsVehicleWheelBrokenOff) == 'function' and IsVehicleWheelBrokenOff(vehicle, wheel.index)
    if brokenOff then restoreBrokenWheel(vehicle, wheel) end

    SetVehicleTyresCanBurst(vehicle, true)
    -- Mesmo comportamento do sistema original: nao altere a vida da roda.
    -- SetVehicleWheelHealth deixa alguns modelos addon presos visualmente no
    -- estado murcho. A native de reparo do pneu e suficiente.
    for _ = 1, 3 do
        SetVehicleTyreFixed(vehicle, wheel.index)
        Wait(50)
    end
    setTyreType(vehicle, wheel.index, itemName)
    setTyreRemoved(vehicle, wheel.index, false)
    OR.Notify('Pneu trocado.', 'success')
end

local function removeTyre(vehicle, wheel)
    if not hasWrench() then return OR.Notify('Equipe a chave inglesa para remover o pneu.', 'error') end
    if isTyreRemoved(vehicle, wheel.index) then return OR.Notify('Esse pneu ja foi removido.', 'error') end
    if isTyreBurst(vehicle, wheel.index) then return OR.Notify('Esse pneu ja esta furado.', 'error') end
    if not workshopAction('Removendo pneu...', 5000, 3) then return end
    if not requestControl(vehicle) then
        return OR.Notify('Nao foi possivel controlar este veiculo para remover o pneu.', 'error')
    end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local authorized, authorizationMessage, itemName = OR.Callback.awaitResource('ob_mecanico', 'completeTyreAction', netId, wheel.index, 'remove')
    if not authorized then return OR.Notify(authorizationMessage or 'O servidor recusou a remocao do pneu.', 'error') end
    -- O GTA trata aro e pneu como a mesma roda. A native de quebrar a roda
    -- remove os dois; para tirar somente o pneu, deixamos o veiculo no aro.
    -- Este e o estado visual mais proximo de um pneu desmontado sem apagar a
    -- roda inteira do carro.
    SetVehicleTyresCanBurst(vehicle, true)
    for _ = 1, 3 do
        SetVehicleTyreBurst(vehicle, wheel.index, true, 1000.0)
        Wait(50)
    end
    setTyreType(vehicle, wheel.index, nil)
    setTyreRemoved(vehicle, wheel.index, true)
    OR.Notify('Pneu removido e guardado na mochila.', 'success')
end

local function serviceWheel(vehicle, entry, wheel)
    if tyreActionActive then return OR.Notify('Ja existe uma acao em andamento.', 'error') end
    if jackedVehicles[entry.netId] ~= entry then return end
    if not hasWrench() then return OR.Notify('Equipe a chave inglesa para trabalhar no pneu.', 'error') end
    if not wheel then return end

    tyreActionActive = true
    if isTyreRemoved(vehicle, wheel.index) or isTyreBurst(vehicle, wheel.index) then
        replaceTyre(vehicle, wheel)
    else
        removeTyre(vehicle, wheel)
    end
    tyreActionActive = false
end

local function serviceNearestTyre(vehicle, entry)
    local wheel, distance = closestWheel(vehicle)
    if not wheel or distance > 2.1 then
        return OR.Notify('Aproxime-se de uma roda para fazer o servico.', 'error')
    end
    serviceWheel(vehicle, entry, wheel)
end

local function registerJackTargets(entry)
    local targetState = GetResourceState('ob_target')
    if targetState ~= 'started' then
        print(('[ob_mecanico] Target indisponivel ao registrar rodas (estado: %s).'):format(tostring(targetState)))
        return
    end
    if not DoesEntityExist(entry.vehicle) then return end
    unregisterJackTargets(entry)
    local vehicle, netId = entry.vehicle, entry.netId
    local function add(id, entity, label, action, canInteract)
        exports.ob_target:RegisterEntity(id, entity, {
            -- A distancia do alvo usa o centro do veiculo; para vans/caminhoes
            -- ela precisa ser maior que a distancia real ate a roda.
            label = label, icon = 'fa-solid fa-screwdriver-wrench', distance = 5.0, action = action, canInteract = canInteract,
        })
        entry.targets[#entry.targets + 1] = id
    end
    local function addWheelZone(id, coords, label, action, canInteract)
        local ok, registered, reason = pcall(function()
            return exports.ob_target:RegisterSphereZone(id, {
                coords = coords,
                -- A zona e um segundo caminho para o target. Ela acompanha a
                -- distancia do atalho E e tolera a diferenca entre a posicao do
                -- osso da roda e o ponto onde o jogador realmente fica em pe.
                radius = 1.70,
                option = {
                    label = label,
                    icon = 'fa-solid fa-screwdriver-wrench',
                    distance = 2.2,
                    action = action,
                    canInteract = canInteract,
                },
            })
        end)
        if not ok or registered ~= true then
            print(('[ob_mecanico] Nao foi possivel registrar o alvo %s: %s'):format(id, tostring(reason or registered)))
            return
        end
        entry.zones[#entry.zones + 1] = id
    end

    add(('ob_mecanico:jack:%s'):format(netId), entry.prop, 'Retirar macaco hidraulico', function() removeJack(vehicle) end, function()
        return jackedVehicles[netId] == entry and #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(entry.prop)) <= 2.2
    end)

    -- O pcall acima faz uma falha de export aparecer no console sem impedir o
    -- resto do script de manter o macaco e o atalho E.
    for index, probe in pairs(entry.probes or {}) do
        local wheelData = probe.wheel
        local zoneId = ('ob_mecanico:tyre_zone:%s:%s'):format(netId, index)
        addWheelZone(zoneId, probe.coords, 'Servico no pneu', function()
            serviceWheel(vehicle, entry, wheelData)
        end, function()
            return jackedVehicles[netId] == entry
                and #(GetEntityCoords(PlayerPedId()) - probe.coords) <= 2.5
        end)
    end
    print(('[ob_mecanico] %s alvo(s) de roda registrado(s) no lado %s do veiculo %s.'):format(#entry.zones, entry.side, netId))
end

-- O prop do macaco e local em cada cliente, mas a decisao de que o veiculo
-- esta elevado vem do servidor. Assim todos veem o mesmo macaco e recebem os
-- mesmos pontos de target sem depender da entidade de prop ser networkada.
local function syncJack(netId, state)
    CreateThread(function()
        local deadline, vehicle = GetGameTimer() + 5000, 0
        while GetGameTimer() < deadline do
            vehicle = NetworkGetEntityFromNetworkId(netId)
            if DoesEntityExist(vehicle) then break end
            Wait(100)
        end
        if not DoesEntityExist(vehicle) then return end

        clearJackEntry(netId, false)
        local model = requestModel('sf_prop_car_jack_01a') or requestModel('prop_carjack')
        local propCoords, originalCoords, originalRotation = readPoint(state.prop), readPoint(state.coords), readPoint(state.rotation)
        local liftedCoords, liftedRotation = readPoint(state.liftedCoords), readPoint(state.liftedRotation)
        if not model or not propCoords or not originalCoords or not originalRotation or not liftedCoords or not liftedRotation then return end

        local prop = CreateObjectNoOffset(model, propCoords.x, propCoords.y, propCoords.z, false, false, false)
        if prop == 0 or not DoesEntityExist(prop) then return end
        SetEntityHeading(prop, tonumber(state.propHeading) or GetEntityHeading(vehicle))
        FreezeEntityPosition(prop, true)

        SetVehicleEngineOn(vehicle, false, true, true)
        SetVehicleHandbrake(vehicle, true)
        FreezeEntityPosition(vehicle, true)
        SetEntityCoordsNoOffset(vehicle, liftedCoords.x, liftedCoords.y, liftedCoords.z, false, false, false)
        SetEntityRotation(vehicle, liftedRotation.x, liftedRotation.y, liftedRotation.z, 2, true)

        local entry = {
            netId = netId, vehicle = vehicle, prop = prop, coords = originalCoords, rotation = originalRotation,
            side = state.side, targets = {}, zones = {}, probes = {},
        }
        for _, wheelData in ipairs(wheels) do
            if wheelData.side == entry.side and (wheelData.index < 4 or GetEntityBoneIndexByName(vehicle, wheelData.bone) ~= -1) then
                entry.probes[wheelData.index] = { coords = wheelCoords(vehicle, wheelData), wheel = wheelData }
            end
        end
        jackedVehicles[netId] = entry
        registerJackTargets(entry)
        SetTimeout(500, function()
            if jackedVehicles[netId] == entry then registerJackTargets(entry) end
        end)
    end)
end

RegisterNetEvent('ob_mecanico:client:syncJack', function(netId, state)
    netId = math.floor(tonumber(netId) or 0)
    if netId > 0 and type(state) == 'table' then syncJack(netId, state) end
end)

RegisterNetEvent('ob_mecanico:client:removeJack', function(netId, state)
    netId = math.floor(tonumber(netId) or 0)
    if netId < 1 then return end
    clearJackEntry(netId, true)
    OR.Notify('Macaco hidraulico retirado.', 'success')
end)

RegisterNetEvent('ob_mecanico:client:syncRemovedTyres', function(netId, state)
    netId = math.floor(tonumber(netId) or 0)
    local vehicle = netId > 0 and NetworkGetEntityFromNetworkId(netId) or 0
    if not DoesEntityExist(vehicle) then return end
    state = type(state) == 'table' and state or {}
    local previous = replicatedRemovedTyres[netId] or {}
    for wheel in pairs(previous) do
        if state[tostring(wheel)] ~= true then SetVehicleTyreFixed(vehicle, tonumber(wheel)) end
    end
    for wheel, removed in pairs(state) do
        if removed == true then SetVehicleTyreBurst(vehicle, tonumber(wheel), true, 1000.0) end
    end
    replicatedRemovedTyres[netId] = state
end)

local function mechanicProgress(label, duration)
    local ped = PlayerPedId()
    RequestAnimDict('mini@repair')
    local deadline = GetGameTimer() + 2500
    while not HasAnimDictLoaded('mini@repair') and GetGameTimer() < deadline do Wait(0) end
    SendNUIMessage({ action = 'serviceProgress', open = true, label = label, duration = duration })
    if HasAnimDictLoaded('mini@repair') then
        TaskPlayAnim(ped, 'mini@repair', 'fixing_a_ped', 4.0, -4.0, duration, 49, 0.0, false, false, false)
    end
    local endsAt, completed = GetGameTimer() + duration, true
    while GetGameTimer() < endsAt do
        if IsEntityDead(ped) or LocalPlayer.state['or:downed'] == true then completed = false break end
        Wait(0)
    end
    SendNUIMessage({ action = 'serviceProgress', open = false })
    ClearPedTasks(ped)
    return completed
end

workshopAction = function(label, duration, steps)
    -- O E no ponto azul ja e a confirmacao da acao. Nao pedimos um segundo E,
    -- pois a camada de ajuda de algumas HUDs nao exibe esse aviso.
    return mechanicProgress(label, duration)
end

local function repair(kind, slot, itemName)
    local vehicle = nearestVehicle()
    if vehicle == 0 then
        OR.Notify('Nenhum veiculo proximo.', 'error')
        return
    end
    local advanced = tostring(itemName or ''):lower() == 'advancedrepairkit'
    local label = kind == 'tyre' and 'Trocando pneu...'
        or advanced and 'Fazendo reparo completo...' or 'Reparando motor...'
    local duration = kind == 'tyre' and 6000 or advanced and 10000 or 8000
    if not workshopAction(label, duration, kind == 'tyre' and 3 or 4) then return end
    if kind == 'tyre' then
        local repaired = false
        for _, data in ipairs(wheels) do
            if isTyreBurst(vehicle, data.index) then
                -- O mecanico continua independente. Quando ob_pneu estiver
                -- ligado ele replica o reparo; sem ele usamos o native GTA.
                if GetResourceState('ob_pneu') == 'started' then
                    exports.ob_pneu:RepairTyre(vehicle, data.index)
                else
                    SetVehicleTyreFixed(vehicle, data.index)
                end
                repaired = true
            end
        end
        if not repaired then
            OR.Notify('Nao existe pneu furado neste veiculo.', 'error')
            return
        end
        OR.Notify('Pneu reparado.', 'success')
    elseif advanced then
        local damagedTyres = {}
        for _, data in ipairs(wheels) do
            if isTyreBurst(vehicle, data.index) or isTyreRemoved(vehicle, data.index) then
                damagedTyres[data.index] = true
            end
        end
        SetVehicleFixed(vehicle)
        SetVehicleEngineHealth(vehicle, 1000.0)
        SetVehicleBodyHealth(vehicle, 1000.0)
        for wheel in pairs(damagedTyres) do SetVehicleTyreBurst(vehicle, wheel, true, 1000.0) end
        clearCriticalEngineState(vehicle)
        enableVehicleDamage(vehicle)
        OR.Notify('Motor e lataria reparados. Pneus danificados foram preservados.', 'success')
    else
        SetVehicleEngineHealth(vehicle, 1000.0)
        clearCriticalEngineState(vehicle)
        enableVehicleDamage(vehicle)
        OR.Notify('Motor reparado. A lataria nao foi alterada.', 'success')
    end
    TriggerServerEvent('ob_inventory:server:mechanicUseResult', slot, itemName, true)
end

exports('CanUseRepairKit', function() return nearestVehicle() ~= 0 end)
RegisterNetEvent('ob_mecanico:client:useRepairKit', function(slot, itemName) repair('repair', slot, itemName) end)
RegisterNetEvent('ob_mecanico:client:useTyreKit', function(slot, itemName) repair('tyre', slot, itemName) end)
RegisterNetEvent('ob_mecanico:client:useJack', function()
    local vehicle = nearestVehicle()
    if vehicle == 0 then return OR.Notify('Nenhum veiculo proximo.', 'error') end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId <= 0 then return OR.Notify('Esse veiculo ainda nao esta sincronizado.', 'error') end
    if jackedVehicles[netId] then return removeJack(vehicle) end
    if not OR.Progress.Run({ label = 'Posicionando macaco...', duration = 1800, animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 } }) then return end
    local wheel = closestWheel(vehicle)
    if not wheel then return OR.Notify('Aproxime-se de uma roda.', 'error') end
    if not requestControl(vehicle) then return OR.Notify('Nao foi possivel controlar este veiculo.', 'error') end
    local originalCoords, originalRotation = GetEntityCoords(vehicle), GetEntityRotation(vehicle, 2)
    local position = jackCoords(vehicle, wheel.side)
    local _, ground = GetGroundZFor_3dCoord(position.x, position.y, position.z + 2.0, false)
    local liftedCoords = vector3(originalCoords.x, originalCoords.y, originalCoords.z + 0.06)
    local liftedRotation = vector3(originalRotation.x, originalRotation.y + (wheel.side == 'left' and 4.2 or -4.2), originalRotation.z)
    SetVehicleEngineOn(vehicle, false, true, true)
    SetVehicleHandbrake(vehicle, true)
    FreezeEntityPosition(vehicle, true)
    SetEntityCoordsNoOffset(vehicle, liftedCoords.x, liftedCoords.y, liftedCoords.z, false, false, false)
    SetEntityRotation(vehicle, liftedRotation.x, liftedRotation.y, liftedRotation.z, 2, true)
    TriggerServerEvent('ob_mecanico:server:setJackState', netId, {
        side = wheel.side,
        coords = { x = originalCoords.x, y = originalCoords.y, z = originalCoords.z },
        rotation = { x = originalRotation.x, y = originalRotation.y, z = originalRotation.z },
        prop = { x = position.x, y = position.y, z = ground or position.z },
        propHeading = GetEntityHeading(vehicle) + (wheel.side == 'left' and 90.0 or -90.0),
        liftedCoords = { x = liftedCoords.x, y = liftedCoords.y, z = liftedCoords.z },
        liftedRotation = { x = liftedRotation.x, y = liftedRotation.y, z = liftedRotation.z },
    })
    OR.Notify('Veiculo elevado. Equipe a chave inglesa e use o target na roda.', 'success')
end)

requestControl = function(vehicle)
    local deadline = GetGameTimer() + 1500
    while DoesEntityExist(vehicle) and not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < deadline do
        NetworkRequestControlOfEntity(vehicle)
        Wait(0)
    end
    return NetworkHasControlOfEntity(vehicle)
end

-- A garagem chama este export no mesmo cliente que esta guardando o carro.
-- State bags replicam de forma assincrona; por isso lemos primeiro o estado
-- local da oficina e tambem registramos pneus furados por tiro, que nao sao
-- necessariamente pneus removidos.
exports('GetVehicleTyreState', function(vehicle)
    if not DoesEntityExist(vehicle) then return {} end

    local key = tyreStateKey(vehicle)
    local state = { removedTyres = {}, tyreTypes = {}, burstTyres = {} }
    local removed = removedTyres[key] or Entity(vehicle).state['ob:removed_tyres'] or {}
    local types = tyreTypes[key] or Entity(vehicle).state['ob:tyre_types'] or {}

    for index, removedState in pairs(removed) do
        if removedState == true then state.removedTyres[tostring(index)] = true end
    end
    for index, itemName in pairs(types) do
        if itemName == 'tyre_armored' then state.tyreTypes[tostring(index)] = itemName end
    end
    for _, wheel in ipairs(wheels) do
        if isTyreBurst(vehicle, wheel.index) then
            -- Ao recriar um veiculo, o GTA restaura um furo "murcho" se o
            -- terceiro argumento for false e so o converte em aro apos andar.
            -- Para a garagem preservar o defeito imediatamente, todo pneu
            -- danificado salvo volta diretamente no aro.
            state.burstTyres[tostring(wheel.index)] = true
        end
    end

    if not next(state.removedTyres) then state.removedTyres = nil end
    if not next(state.tyreTypes) then state.tyreTypes = nil end
    if not next(state.burstTyres) then state.burstTyres = nil end
    return state
end)

exports('ApplySavedBurstTyres', function(vehicle, saved)
    if not DoesEntityExist(vehicle) then return end
    SetVehicleTyresCanBurst(vehicle, true)
    for index, onRim in pairs(type(saved) == 'table' and saved or {}) do
        local wheel = tonumber(index)
        if wheel and type(onRim) == 'boolean' then
            -- Tambem converte registros antigos gravados como false para o
            -- estado visual persistente no aro.
            SetVehicleTyreBurst(vehicle, wheel, true, 1000.0)
        end
    end
end)

-- Chamado pela garagem depois de criar o veiculo. O native nao remove a malha
-- de todas as rodas addon, mas preserva o estado mecanico: a roda continua
-- indisponivel para dirigir e so pode receber outro pneu pelo macaco/chave.
exports('ApplySavedTyres', function(vehicle, saved)
    if not DoesEntityExist(vehicle) then return end
    local key, restored = tyreStateKey(vehicle), {}
    for index, removed in pairs(type(saved) == 'table' and saved or {}) do
        local wheel = tonumber(index)
        if wheel and removed == true then
            restored[wheel] = true
            SetVehicleTyresCanBurst(vehicle, true)
            SetVehicleTyreBurst(vehicle, wheel, true, 1000.0)
        end
    end
    if next(restored) then
        removedTyres[key] = restored
    else
        removedTyres[key] = nil
    end
end)

exports('ApplySavedTyreTypes', function(vehicle, saved)
    if not DoesEntityExist(vehicle) then return end
    for index, itemName in pairs(type(saved) == 'table' and saved or {}) do
        local wheel = tonumber(index)
        if wheel and (itemName == 'tyre_normal' or itemName == 'tyre_armored') then
            setTyreType(vehicle, wheel, itemName)
        end
    end
end)

local function captureVehicle(vehicle)
    local data = {
        mods = {}, toggles = {}, neons = {}, tint = GetVehicleWindowTint(vehicle),
        wheelType = GetVehicleWheelType(vehicle),
    }
    if GetResourceState('ob_garage') == 'started' then
        local ok, properties = pcall(function()
            return exports.ob_garage:CaptureProperties(vehicle)
        end)
        if ok and type(properties) == 'table' then data.properties = properties end
    end
    local primary, secondary = GetVehicleColours(vehicle)
    local pearl, wheel = GetVehicleExtraColours(vehicle)
    local paintType1, paintColor1, paintPearlescent1 = GetVehicleModColor_1(vehicle)
    local paintType2, paintColor2 = GetVehicleModColor_2(vehicle)
    local primaryR, primaryG, primaryB = GetVehicleCustomPrimaryColour(vehicle)
    local secondaryR, secondaryG, secondaryB = GetVehicleCustomSecondaryColour(vehicle)
    data.primary, data.secondary, data.pearl, data.wheel = primary, secondary, pearl, wheel
    data.paintType1, data.paintColor1, data.paintPearlescent1 = paintType1, paintColor1, paintPearlescent1
    data.paintType2, data.paintColor2 = paintType2, paintColor2
    data.primaryCustom = GetIsVehiclePrimaryColourCustom(vehicle) == true
    data.secondaryCustom = GetIsVehicleSecondaryColourCustom(vehicle) == true
    data.primaryCustomColor = { primaryR, primaryG, primaryB }
    data.secondaryCustomColor = { secondaryR, secondaryG, secondaryB }
    local nr, ng, nb = GetVehicleNeonLightsColour(vehicle)
    data.neonColor = { nr, ng, nb }
    data.headlightColor = GetVehicleXenonLightsColor(vehicle)
    for _, option in pairs(optionByKey) do
        if option.type == 'mod' then data.mods[option.index] = GetVehicleMod(vehicle, option.index) end
        if option.type == 'toggle' then data.toggles[option.index] = IsToggleModOn(vehicle, option.index) end
    end
    local visualFlags = Entity(vehicle).state['ob:visual_flags']
    if type(visualFlags) == 'table' then
        if type(visualFlags.turboEnabled) == 'boolean' then data.toggles[18] = visualFlags.turboEnabled end
        if type(visualFlags.xenonEnabled) == 'boolean' then data.toggles[22] = visualFlags.xenonEnabled end
    end
    -- As familias de roda possuem chaves diferentes, mas compartilham o mod 23.
    data.mods[23] = GetVehicleMod(vehicle, 23)
    for side = 0, 3 do data.neons[side] = IsVehicleNeonLightEnabled(vehicle, side) end
    return data
end

local function restoreVehicle(vehicle, saved)
    if not vehicle or vehicle == 0 or not saved then return end
    local restoredComplete = false
    if type(saved.properties) == 'table' and GetResourceState('ob_garage') == 'started' then
        restoredComplete = pcall(function()
            exports.ob_garage:ApplyProperties(vehicle, saved.properties)
        end)
    end

    -- Compatibilidade caso a garagem esteja indisponivel ou ainda seja uma
    -- versao anterior sem o export de restauracao completa.
    if not restoredComplete then
        SetVehicleModKit(vehicle, 0)
        if saved.wheelType ~= nil then SetVehicleWheelType(vehicle, saved.wheelType) end
        for index, value in pairs(saved.mods or {}) do SetVehicleMod(vehicle, tonumber(index), value, false) end
        for index, value in pairs(saved.toggles or {}) do
            local modIndex = tonumber(index)
            local attempts = modIndex == 18 and 6 or 1
            for _ = 1, attempts do
                ToggleVehicleMod(vehicle, modIndex, value == true)
                if modIndex == 18 then Wait(0) end
            end
        end
        SetVehicleColours(vehicle, saved.primary or 0, saved.secondary or 0)
        ClearVehicleCustomPrimaryColour(vehicle)
        ClearVehicleCustomSecondaryColour(vehicle)
        if saved.paintType1 ~= nil then
            SetVehicleModColor_1(vehicle, saved.paintType1, saved.paintColor1 or saved.primary or 0,
                saved.paintPearlescent1 or saved.pearl or 0)
        end
        if saved.paintType2 ~= nil then
            SetVehicleModColor_2(vehicle, saved.paintType2, saved.paintColor2 or saved.secondary or 0)
        end
        if saved.primaryCustom == true and type(saved.primaryCustomColor) == 'table' then
            SetVehicleCustomPrimaryColour(vehicle,
                tonumber(saved.primaryCustomColor[1]) or 0,
                tonumber(saved.primaryCustomColor[2]) or 0,
                tonumber(saved.primaryCustomColor[3]) or 0)
        end
        if saved.secondaryCustom == true and type(saved.secondaryCustomColor) == 'table' then
            SetVehicleCustomSecondaryColour(vehicle,
                tonumber(saved.secondaryCustomColor[1]) or 0,
                tonumber(saved.secondaryCustomColor[2]) or 0,
                tonumber(saved.secondaryCustomColor[3]) or 0)
        end
        SetVehicleExtraColours(vehicle, saved.pearl or 0, saved.wheel or 0)
        SetVehicleWindowTint(vehicle, saved.tint or -1)
        for side = 0, 3 do SetVehicleNeonLightEnabled(vehicle, side, saved.neons and saved.neons[side] == true) end
        local color = saved.neonColor or { 255, 255, 255 }
        SetVehicleNeonLightsColour(vehicle, color[1], color[2], color[3])
        if saved.headlightColor ~= nil then
            SetVehicleXenonLightsColor(vehicle, tonumber(saved.headlightColor) or -1)
        end
    end
end

local neonPalette = {
    { 255, 255, 255 }, { 40, 150, 255 }, { 0, 230, 170 }, { 255, 40, 90 }, { 190, 80, 255 }, { 255, 170, 30 },
}

local headlightLabels = {
    [-1] = 'Original', [0] = 'Branco', [1] = 'Azul', [2] = 'Azul eletrico',
    [3] = 'Verde menta', [4] = 'Verde lima', [5] = 'Amarelo', [6] = 'Dourado',
    [7] = 'Laranja', [8] = 'Vermelho', [9] = 'Rosa', [10] = 'Rosa forte',
    [11] = 'Roxo', [12] = 'Luz negra',
}

local paintTypeLabels = {
    [0] = 'Classica', [1] = 'Metalica', [2] = 'Perolada', [3] = 'Fosca',
    [4] = 'Metal escovado', [5] = 'Cromada', [6] = 'Camaleao',
}

local function availablePaintTypes()
    local types = { 0, 1, 2, 3, 4, 5 }
    -- Camaleao nao existe em todos os clientes/builds. O proprio jogo informa
    -- se esse acabamento possui cores antes de ele aparecer no menu.
    if GetNumModColors(6, false) > 0 then types[#types + 1] = 6 end
    return types
end

local function applyPaintType(vehicle, secondary, paintType)
    local colorCount = GetNumModColors(paintType, false)
    if paintType == 6 and colorCount <= 0 then return false end
    if secondary then
        local red, green, blue = GetVehicleCustomSecondaryColour(vehicle)
        local wasCustom = tuning.visualFlags.secondaryCustom
        if type(wasCustom) ~= 'boolean' then wasCustom = GetIsVehicleSecondaryColourCustom(vehicle) == true end
        local _, color = GetVehicleModColor_2(vehicle)
        color = math.max(0, math.min(math.floor(tonumber(color) or 0), math.max(0, colorCount - 1)))
        ClearVehicleCustomSecondaryColour(vehicle)
        SetVehicleModColor_2(vehicle, paintType, color)
        if wasCustom then SetVehicleCustomSecondaryColour(vehicle, red, green, blue) end
        tuning.visualFlags.secondaryCustom = wasCustom
    else
        local red, green, blue = GetVehicleCustomPrimaryColour(vehicle)
        local wasCustom = tuning.visualFlags.primaryCustom
        if type(wasCustom) ~= 'boolean' then wasCustom = GetIsVehiclePrimaryColourCustom(vehicle) == true end
        local _, color, pearlescent = GetVehicleModColor_1(vehicle)
        color = math.max(0, math.min(math.floor(tonumber(color) or 0), math.max(0, colorCount - 1)))
        ClearVehicleCustomPrimaryColour(vehicle)
        SetVehicleModColor_1(vehicle, paintType, color, tonumber(pearlescent) or 0)
        if wasCustom then SetVehicleCustomPrimaryColour(vehicle, red, green, blue) end
        tuning.visualFlags.primaryCustom = wasCustom
    end
    return true
end

local function cycle(value, minimum, maximum, delta)
    local range = maximum - minimum + 1
    return ((value - minimum + delta) % range) + minimum
end

local function availableVehicleExtras(vehicle)
    local extras = {}
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return extras end
    for extra = 0, 20 do
        if DoesExtraExist(vehicle, extra) then extras[#extras + 1] = extra end
    end
    return extras
end

local function selectedVehicleExtra(states, vehicle)
    states = type(states) == 'table' and states or {}
    for _, extra in ipairs(availableVehicleExtras(vehicle)) do
        if states[extra] == true or states[tostring(extra)] == true then return extra end
    end
    return -1
end

local function applyChange(option, delta)
    local vehicle = tuning.vehicle
    if not vehicle or vehicle == 0 then return end
    SetVehicleModKit(vehicle, 0)
    if option.type == 'mod' then
        local maximum = GetNumVehicleMods(vehicle, option.index) - 1
        if maximum < -1 then return end
        local current = GetVehicleMod(vehicle, option.index)
        SetVehicleMod(vehicle, option.index, cycle(current, -1, maximum, delta), false)
    elseif option.type == 'toggle' then
        tuning.toggleStates = tuning.toggleStates or {}
        local current = tuning.toggleStates[option.index]
        if type(current) ~= 'boolean' then current = IsToggleModOn(vehicle, option.index) == true end
        local enabled = not current
        tuning.toggleStates[option.index] = enabled
        local attempts = option.index == 18 and 6 or 2
        for _ = 1, attempts do
            ToggleVehicleMod(vehicle, option.index, enabled)
            Wait(0)
            if option.index ~= 18 and IsToggleModOn(vehicle, option.index) == enabled then break end
        end
        if option.index == 18 then tuning.visualFlags.turboEnabled = enabled end
        if option.index == 22 then tuning.visualFlags.xenonEnabled = enabled end
    elseif option.type == 'color' or option.type == 'color2' then
        local primary, secondary = GetVehicleColours(vehicle)
        if option.type == 'color' then
            ClearVehicleCustomPrimaryColour(vehicle)
            primary = cycle(primary, 0, 159, delta)
        else
            ClearVehicleCustomSecondaryColour(vehicle)
            secondary = cycle(secondary, 0, 159, delta)
        end
        SetVehicleColours(vehicle, primary, secondary)
    elseif option.type == 'pearl' or option.type == 'wheel_color' then
        local pearl, wheel = GetVehicleExtraColours(vehicle)
        if option.type == 'pearl' then pearl = cycle(pearl, 0, 159, delta) else wheel = cycle(wheel, 0, 159, delta) end
        SetVehicleExtraColours(vehicle, pearl, wheel)
    elseif option.type == 'paint_type1' or option.type == 'paint_type2' then
        local types = availablePaintTypes()
        local current = select(1, option.type == 'paint_type1'
            and GetVehicleModColor_1(vehicle) or GetVehicleModColor_2(vehicle))
        local position = 1
        for index, paintType in ipairs(types) do
            if paintType == current then position = index break end
        end
        local selected = types[cycle(position, 1, #types, delta)]
        applyPaintType(vehicle, option.type == 'paint_type2', selected)
    elseif option.type == 'tint' then
        SetVehicleWindowTint(vehicle, cycle(GetVehicleWindowTint(vehicle), -1, 6, delta))
    elseif option.type == 'neon' then
        local nr, ng, nb = GetVehicleNeonLightsColour(vehicle)
        local current = 1
        for index, color in ipairs(neonPalette) do if color[1] == nr and color[2] == ng and color[3] == nb then current = index break end end
        local color = neonPalette[cycle(current, 1, #neonPalette, delta)]
        for side = 0, 3 do SetVehicleNeonLightEnabled(vehicle, side, true) end
        SetVehicleNeonLightsColour(vehicle, color[1], color[2], color[3])
    elseif option.type == 'extra' and DoesExtraExist(vehicle, option.index) then
        SetVehicleExtra(vehicle, option.index, IsVehicleExtraTurnedOn(vehicle, option.index) and 1 or 0)
    end
end

local function displayValue(vehicle, option)
    if option.type == 'mod' then
        local value = GetVehicleMod(vehicle, option.index)
        return value < 0 and 'Original' or ('Nivel %s'):format(value + 1)
    elseif option.type == 'toggle' then
        local enabled = tuning.toggleStates and tuning.toggleStates[option.index]
        if type(enabled) ~= 'boolean' then enabled = IsToggleModOn(vehicle, option.index) == true end
        return enabled and 'Ativo' or 'Desativado'
    elseif option.type == 'color' or option.type == 'color2' then
        if option.type == 'color' and GetIsVehiclePrimaryColourCustom(vehicle) then
            local r, g, b = GetVehicleCustomPrimaryColour(vehicle)
            return ('#%02X%02X%02X'):format(r, g, b)
        elseif option.type == 'color2' and GetIsVehicleSecondaryColourCustom(vehicle) then
            local r, g, b = GetVehicleCustomSecondaryColour(vehicle)
            return ('#%02X%02X%02X'):format(r, g, b)
        end
        local primary, secondary = GetVehicleColours(vehicle)
        return ('Cor %s'):format(option.type == 'color' and primary or secondary)
    elseif option.type == 'pearl' or option.type == 'wheel_color' then
        local pearl, wheel = GetVehicleExtraColours(vehicle)
        return ('Cor %s'):format(option.type == 'pearl' and pearl or wheel)
    elseif option.type == 'paint_type1' or option.type == 'paint_type2' then
        local value = select(1, option.type == 'paint_type1'
            and GetVehicleModColor_1(vehicle) or GetVehicleModColor_2(vehicle))
        return paintTypeLabels[value] or ('Tipo %s'):format(value)
    elseif option.type == 'tint' then
        return GetVehicleWindowTint(vehicle) < 0 and 'Sem pelicula' or ('Nivel %s'):format(GetVehicleWindowTint(vehicle))
    elseif option.type == 'neon' then
        local r, g, b = GetVehicleNeonLightsColour(vehicle)
        return ('#%02X%02X%02X'):format(r, g, b)
    elseif option.type == 'neon_toggle' then
        for side = 0, 3 do
            if IsVehicleNeonLightEnabled(vehicle, side) then return 'Ativo' end
        end
        return 'Desativado'
    elseif option.type == 'headlight_color' then
        local value = GetVehicleXenonLightsColor(vehicle)
        return headlightLabels[value] or ('Cor %s'):format(value)
    elseif option.type == 'wheel' then
        if GetVehicleWheelType(vehicle) ~= option.wheelType then return 'Ver modelos' end
        local value = GetVehicleMod(vehicle, option.index)
        return value < 0 and 'Original' or ('Modelo %s'):format(value + 1)
    elseif option.type == 'extra' then
        return IsVehicleExtraTurnedOn(vehicle, option.index) and 'Ativado' or 'Desativado'
    elseif option.type == 'extras' then
        local selected = selectedVehicleExtra(tuning.extraStates, vehicle)
        return selected >= 0 and ('Extra %s'):format(selected) or 'Sem extras'
    end
    return '-'
end

local tintLabels = {
    [-1] = 'Sem pelicula', [0] = 'Original', [1] = 'Preto puro', [2] = 'Escura',
    [3] = 'Media', [4] = 'Clara', [5] = 'Limousine', [6] = 'Verde',
}

local function modChoiceLabel(vehicle, option, value)
    if value < 0 then return 'Original' end
    local labelKey = GetModTextLabel(vehicle, option.index, value)
    if labelKey and labelKey ~= '' and labelKey ~= 'NULL' then
        local translated = GetLabelText(labelKey)
        if translated and translated ~= '' and translated ~= 'NULL' then return translated end
    end
    if option.type == 'wheel' then return ('%s %s'):format(option.label, value + 1) end
    return ('%s %s'):format(option.label, value + 1)
end

local function configuredChoicePrice(option, value)
    local payment = OBMechanicConfig.Payment or {}
    local fallback = math.max(0, math.floor(tonumber(option.price) or tonumber(payment.DefaultPrice) or 100))
    value = tonumber(value)
    if (option.type == 'mod' or option.type == 'wheel') and value then
        if value < 0 then fallback = math.max(0, math.floor(tonumber(option.originalPrice) or fallback))
        elseif type(option.levelPrices) == 'table' then
            fallback = math.max(0, math.floor(tonumber(option.levelPrices[value + 1]) or fallback))
        end
    elseif option.type == 'toggle' or option.type == 'neon_toggle' or option.type == 'extra' then
        local configured = value == 1 and option.enabledPrice or option.disabledPrice
        fallback = math.max(0, math.floor(tonumber(configured) or fallback))
    elseif value and type(option.choicePrices) == 'table' then
        fallback = math.max(0, math.floor(tonumber(option.choicePrices[value]) or fallback))
    end
    return fallback
end

local function choicePrice(option, value)
    if OBMechanicConfig.TuningFree == true then return 0 end
    local fallback = configuredChoicePrice(option, value)
    return math.floor(fallback * (1.0 + math.max(0, tuning.markupPercent or 0) / 100.0) + 0.5)
end

local function propertyValue(container, key)
    if type(container) ~= 'table' then return nil end
    if container[key] ~= nil then return container[key] end
    return container[tostring(key)]
end

local function propertyMod(properties, index)
    local value = propertyValue(properties and properties.mods, index)
    return type(value) == 'table' and tonumber(value.value) or tonumber(value)
end

local function propertyToggle(properties, index)
    local value = propertyValue(properties and properties.toggles, index)
    return type(value) == 'boolean' and value or nil
end

local function propertyExtra(properties, index)
    return propertyValue(properties and properties.extras, index) == true
end

local function propertyExtrasChanged(oldProperties, newProperties)
    for extra = 0, 20 do
        if propertyExtra(oldProperties, extra) ~= propertyExtra(newProperties, extra) then return true end
    end
    return false
end

local function propertyChanged(oldValue, newValue)
    if oldValue == nil then return false end
    if type(oldValue) == 'table' or type(newValue) == 'table' then
        if type(oldValue) ~= 'table' or type(newValue) ~= 'table' then return true end
        for key, value in pairs(oldValue) do
            if propertyChanged(value, propertyValue(newValue, key)) then return true end
        end
        for key, value in pairs(newValue) do
            local previous = propertyValue(oldValue, key)
            if previous ~= nil and propertyChanged(previous, value) then return true end
        end
        return false
    end
    return oldValue ~= newValue
end

local function propertiesNeonEnabled(properties)
    for side = 0, 3 do
        if propertyValue(properties and properties.neons, side) == true then return true end
    end
    return false
end

local function previewOptionChanged(option, oldProperties, newProperties)
    if option.type == 'mod' then
        return propertyChanged(propertyMod(oldProperties, option.index), propertyMod(newProperties, option.index))
    elseif option.type == 'toggle' then
        -- A ausencia em propriedades antigas significa desativado. Isso faz a
        -- primeira instalacao do turbo aparecer imediatamente no total.
        return (propertyToggle(oldProperties, option.index) == true)
            ~= (propertyToggle(newProperties, option.index) == true)
    elseif option.type == 'color' then
        return propertyChanged(oldProperties.primary, newProperties.primary)
            or propertyChanged(oldProperties.primaryCustom, newProperties.primaryCustom)
            or propertyChanged(oldProperties.primaryCustomColor, newProperties.primaryCustomColor)
    elseif option.type == 'color2' then
        return propertyChanged(oldProperties.secondary, newProperties.secondary)
            or propertyChanged(oldProperties.secondaryCustom, newProperties.secondaryCustom)
            or propertyChanged(oldProperties.secondaryCustomColor, newProperties.secondaryCustomColor)
    elseif option.type == 'paint_type1' then
        return propertyChanged(oldProperties.paintType1, newProperties.paintType1)
    elseif option.type == 'paint_type2' then
        return propertyChanged(oldProperties.paintType2, newProperties.paintType2)
    elseif option.type == 'pearl' then
        return propertyChanged(oldProperties.pearlescent, newProperties.pearlescent)
    elseif option.type == 'wheel_color' then
        return propertyChanged(oldProperties.wheel, newProperties.wheel)
    elseif option.type == 'tint' then
        return propertyChanged(oldProperties.windowTint, newProperties.windowTint)
    elseif option.type == 'neon_toggle' then
        return propertiesNeonEnabled(oldProperties) ~= propertiesNeonEnabled(newProperties)
    elseif option.type == 'neon' then
        return propertyChanged(oldProperties.neonColor, newProperties.neonColor)
    elseif option.type == 'headlight_color' then
        return propertyChanged(oldProperties.xenonColor, newProperties.xenonColor)
    elseif option.type == 'extra' then
        return propertyExtra(oldProperties, option.index) ~= propertyExtra(newProperties, option.index)
    elseif option.type == 'extras' then
        return propertyExtrasChanged(oldProperties, newProperties)
    end
    return false
end

local function previewOptionValue(option, properties)
    if option.type == 'mod' or option.type == 'wheel' then
        return propertyMod(properties, option.index)
    elseif option.type == 'toggle' then
        return propertyToggle(properties, option.index) == true and 1 or 0
    elseif option.type == 'neon_toggle' then
        return propertiesNeonEnabled(properties) and 1 or 0
    elseif option.type == 'paint_type1' then
        return tonumber(properties.paintType1)
    elseif option.type == 'paint_type2' then
        return tonumber(properties.paintType2)
    elseif option.type == 'pearl' then
        return tonumber(properties.pearlescent)
    elseif option.type == 'wheel_color' then
        return tonumber(properties.wheel)
    elseif option.type == 'tint' then
        return tonumber(properties.windowTint)
    elseif option.type == 'headlight_color' then
        return tonumber(properties.xenonColor)
    elseif option.type == 'extra' then
        return propertyExtra(properties, option.index) and 1 or 0
    elseif option.type == 'extras' then
        for extra = 0, 20 do if propertyExtra(properties, extra) then return extra end end
        return -1
    end
    return nil
end

local function previewProperties()
    if GetResourceState('ob_garage') ~= 'started' then return nil end
    local ok, properties = pcall(function()
        return exports.ob_garage:CaptureProperties(tuning.vehicle)
    end)
    if not ok or type(properties) ~= 'table' then return nil end
    properties.toggles = type(properties.toggles) == 'table' and properties.toggles or {}
    for index, enabled in pairs(tuning.toggleStates or {}) do
        properties.toggles[tostring(index)] = enabled == true
    end
    properties.extras = type(properties.extras) == 'table' and properties.extras or {}
    for index, enabled in pairs(tuning.extraStates or {}) do
        properties.extras[tostring(index)] = enabled == true
    end
    local flags = tuning.visualFlags or {}
    if type(flags.primaryCustom) == 'boolean' then properties.primaryCustom = flags.primaryCustom end
    if type(flags.secondaryCustom) == 'boolean' then properties.secondaryCustom = flags.secondaryCustom end
    if type(flags.neonEnabled) == 'boolean' then
        properties.neons = type(properties.neons) == 'table' and properties.neons or {}
        for side = 0, 3 do properties.neons[tostring(side)] = flags.neonEnabled end
    end
    if type(flags.xenonEnabled) == 'boolean' then properties.toggles['22'] = flags.xenonEnabled end
    if type(flags.turboEnabled) == 'boolean' then properties.toggles['18'] = flags.turboEnabled end
    return properties
end

local function pendingTuningPrice()
    if OBMechanicConfig.TuningFree == true then return 0 end
    local oldProperties = tuning.original and tuning.original.properties
    local newProperties = previewProperties()
    if type(oldProperties) ~= 'table' or type(newProperties) ~= 'table' then return 0 end
    local subtotal, wheelsProcessed = 0, false
    local stationCategory = tuning.station and tuning.station.category or nil
    for _, section in ipairs(OBMechanicConfig.Sections or {}) do
        if not stationCategory or not section.category or section.category == stationCategory then
            for _, option in ipairs(section.options or {}) do
                if option.type == 'wheel' then
                    if not wheelsProcessed then
                        wheelsProcessed = true
                        local wheelChanged = propertyChanged(oldProperties.wheelType, newProperties.wheelType)
                            or propertyChanged(propertyMod(oldProperties, option.index), propertyMod(newProperties, option.index))
                        if wheelChanged then
                            local selectedType = tonumber(newProperties.wheelType)
                            local selectedOption = option
                            for _, wheelOption in ipairs(section.options or {}) do
                                if wheelOption.type == 'wheel' and tonumber(wheelOption.wheelType) == selectedType then
                                    selectedOption = wheelOption
                                    break
                                end
                            end
                            subtotal = subtotal + configuredChoicePrice(
                                selectedOption, propertyMod(newProperties, selectedOption.index))
                        end
                    end
                elseif previewOptionChanged(option, oldProperties, newProperties) then
                    subtotal = subtotal + configuredChoicePrice(option, previewOptionValue(option, newProperties))
                end
            end
        end
    end
    return math.floor(subtotal * (1.0 + math.max(0, tuning.markupPercent or 0) / 100.0) + 0.5)
end

local function choicesForOption(option, initializeWheelFamily)
    local vehicle = tuning.vehicle
    if not tuning.open or not option or not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return {}
    end

    SetVehicleModKit(vehicle, 0)
    local choices = {}
    if option.type == 'wheel' then
        local originalFamily = tuning.original and tonumber(tuning.original.wheelType)
        local originalModel = tuning.original and tuning.original.mods and tonumber(tuning.original.mods[option.index])
        local installedFamily = originalFamily == option.wheelType
        local activeFamily = GetVehicleWheelType(vehicle)
        local activeModel = GetVehicleMod(vehicle, option.index)
        SetVehicleWheelType(vehicle, option.wheelType)
        local maximum = GetNumVehicleMods(vehicle, option.index) - 1
        local current = GetVehicleMod(vehicle, option.index)
        if initializeWheelFamily == true then
            if activeFamily == option.wheelType then
                current = activeModel
            else
                current = installedFamily and (originalModel or -1) or (maximum >= 0 and 0 or -1)
            end
            SetVehicleMod(vehicle, option.index, current, false)
        end
        if current > maximum then
            current = -1
            SetVehicleMod(vehicle, option.index, current, false)
        end
        for value = -1, maximum do
            choices[#choices + 1] = {
                value = value,
                label = modChoiceLabel(vehicle, option, value),
                selected = value == current,
            }
        end
    elseif option.type == 'mod' then
        local current = GetVehicleMod(vehicle, option.index)
        local maximum = GetNumVehicleMods(vehicle, option.index) - 1
        for value = -1, maximum do
            choices[#choices + 1] = {
                value = value,
                label = modChoiceLabel(vehicle, option, value),
                selected = value == current,
            }
        end
    elseif option.type == 'toggle' then
        local enabled = tuning.toggleStates and tuning.toggleStates[option.index]
        if type(enabled) ~= 'boolean' then enabled = IsToggleModOn(vehicle, option.index) == true end
        choices = {
            { value = 0, label = 'Desativado', selected = not enabled },
            { value = 1, label = 'Ativado', selected = enabled },
        }
    elseif option.type == 'neon_toggle' then
        local enabled = false
        for side = 0, 3 do
            if IsVehicleNeonLightEnabled(vehicle, side) then enabled = true break end
        end
        choices = {
            { value = 0, label = 'Desativado', selected = not enabled },
            { value = 1, label = 'Ativado', selected = enabled },
        }
    elseif option.type == 'extra' and DoesExtraExist(vehicle, option.index) then
        local enabled = IsVehicleExtraTurnedOn(vehicle, option.index) == true
        choices = {
            { value = 0, label = 'Desativado', selected = not enabled },
            { value = 1, label = 'Ativado', selected = enabled },
        }
    elseif option.type == 'extras' then
        local selected = selectedVehicleExtra(tuning.extraStates, vehicle)
        choices[#choices + 1] = { value = -1, label = 'Sem extras', selected = selected < 0 }
        for _, extra in ipairs(availableVehicleExtras(vehicle)) do
            choices[#choices + 1] = {
                value = extra,
                label = ('Extra %s'):format(extra),
                selected = selected == extra,
            }
        end
    elseif option.type == 'tint' then
        local current = GetVehicleWindowTint(vehicle)
        for value = -1, 6 do
            choices[#choices + 1] = { value = value, label = tintLabels[value], selected = value == current }
        end
    elseif option.type == 'headlight_color' then
        local current = GetVehicleXenonLightsColor(vehicle)
        for value = -1, 12 do
            choices[#choices + 1] = { value = value, label = headlightLabels[value], selected = value == current }
        end
    elseif option.type == 'paint_type1' or option.type == 'paint_type2' then
        local current = select(1, option.type == 'paint_type1'
            and GetVehicleModColor_1(vehicle) or GetVehicleModColor_2(vehicle))
        for _, value in ipairs(availablePaintTypes()) do
            choices[#choices + 1] = {
                value = value,
                label = paintTypeLabels[value] or ('Tipo %s'):format(value),
                selected = value == current,
            }
        end
    end
    for _, choice in ipairs(choices) do
        choice.price = choicePrice(option, choice.value)
        choice.priceLabel = OR.FormatMoney(choice.price)
    end
    return choices
end

local function selectChoice(option, value)
    local vehicle = tuning.vehicle
    if not tuning.open or not option or not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    SetVehicleModKit(vehicle, 0)
    value = math.floor(tonumber(value) or -1)
    if option.type == 'wheel' then
        SetVehicleWheelType(vehicle, option.wheelType)
        local maximum = GetNumVehicleMods(vehicle, option.index) - 1
        if value < -1 or value > maximum then return false end
        SetVehicleMod(vehicle, option.index, value, false)
    elseif option.type == 'mod' then
        local maximum = GetNumVehicleMods(vehicle, option.index) - 1
        if value < -1 or value > maximum then return false end
        SetVehicleMod(vehicle, option.index, value, false)
    elseif option.type == 'toggle' then
        local enabled = value == 1
        tuning.toggleStates = tuning.toggleStates or {}
        tuning.toggleStates[option.index] = enabled
        local attempts = option.index == 18 and 6 or 2
        for _ = 1, attempts do
            ToggleVehicleMod(vehicle, option.index, enabled)
            Wait(0)
            if option.index ~= 18 and IsToggleModOn(vehicle, option.index) == enabled then break end
        end
        -- No Enhanced o getter do turbo pode continuar falso mesmo com o mod
        -- aplicado. Para o indice 18, o estado escolhido no painel e a fonte
        -- autoritativa e tambem sera salvo no state bag pela garagem.
        if option.index ~= 18 and IsToggleModOn(vehicle, option.index) ~= enabled then return false end
        if option.index == 18 then tuning.visualFlags.turboEnabled = enabled end
        if option.index == 22 then tuning.visualFlags.xenonEnabled = enabled end
    elseif option.type == 'neon_toggle' then
        if value ~= 0 and value ~= 1 then return false end
        for side = 0, 3 do SetVehicleNeonLightEnabled(vehicle, side, value == 1) end
        tuning.visualFlags.neonEnabled = value == 1
    elseif option.type == 'extra' then
        if (value ~= 0 and value ~= 1) or not DoesExtraExist(vehicle, option.index) then return false end
        SetVehicleExtra(vehicle, option.index, value == 1 and 0 or 1)
    elseif option.type == 'extras' then
        if value < -1 or value > 20 or (value >= 0 and not DoesExtraExist(vehicle, value)) then return false end
        tuning.extraStates = tuning.extraStates or {}
        for _, extra in ipairs(availableVehicleExtras(vehicle)) do
            local enabled = value == extra
            tuning.extraStates[extra] = enabled
            SetVehicleExtra(vehicle, extra, enabled and 0 or 1)
        end
        -- O getter dos extras de alguns add-ons demora a refletir a troca.
        -- Enviar a escolha separadamente mantem preco e persistencia estaveis.
        tuning.visualFlags.selectedExtra = value
    elseif option.type == 'tint' then
        if value < -1 or value > 6 then return false end
        SetVehicleWindowTint(vehicle, value)
    elseif option.type == 'headlight_color' then
        if value < -1 or value > 12 then return false end
        ToggleVehicleMod(vehicle, 22, true)
        SetVehicleXenonLightsColor(vehicle, value)
        tuning.visualFlags.xenonEnabled = true
    elseif option.type == 'paint_type1' or option.type == 'paint_type2' then
        local available = false
        for _, paintType in ipairs(availablePaintTypes()) do
            if value == paintType then available = true break end
        end
        if not available then return false end
        return applyPaintType(vehicle, option.type == 'paint_type2', value)
    else
        return false
    end
    return true
end

local function menuState()
    local total = pendingTuningPrice()
    local data = {
        title = tuning.station and tuning.station.label or 'Oficina',
        stationId = tuning.station and tuning.station.id or nil,
        totalPrice = total,
        totalPriceLabel = OR.FormatMoney(total),
        sections = {},
    }
    local stationCategory = tuning.station and tuning.station.category or nil
    for _, section in ipairs(OBMechanicConfig.Sections) do
        if not stationCategory or not section.category or section.category == stationCategory then
        local public = { id = section.id, label = section.label, options = {} }
        for _, option in ipairs(section.options) do
            local available = true
            if option.type == 'extra' then
                available = DoesExtraExist(tuning.vehicle, option.index)
            elseif option.type == 'extras' then
                available = #availableVehicleExtras(tuning.vehicle) > 0
            end
            if available then
            local payment = OBMechanicConfig.Payment or {}
            local basePrice = math.max(0, math.floor(tonumber(option.price) or tonumber(payment.DefaultPrice) or 100))
            local price = OBMechanicConfig.TuningFree == true and 0
                or math.floor(basePrice * (1.0 + math.max(0, tuning.markupPercent or 0) / 100.0) + 0.5)
            local entry = {
                key = option.key,
                label = option.label,
                display = displayValue(tuning.vehicle, option),
                kind = option.type,
                price = price,
                priceLabel = OR.FormatMoney(price),
            }
            if option.type == 'color' or option.type == 'color2' or option.type == 'neon' then
                entry.colorMode = 'rgb'
                if option.type == 'color' and GetIsVehiclePrimaryColourCustom(tuning.vehicle) then
                    entry.colorHex = entry.display
                elseif option.type == 'color2' and GetIsVehicleSecondaryColourCustom(tuning.vehicle) then
                    entry.colorHex = entry.display
                elseif option.type == 'neon' then
                    entry.colorHex = entry.display
                else
                    local primary, secondary = GetVehicleColours(tuning.vehicle)
                    entry.colorIndex = option.type == 'color' and primary or secondary
                end
            elseif option.type == 'pearl' or option.type == 'wheel_color' then
                local pearl, wheel = GetVehicleExtraColours(tuning.vehicle)
                entry.colorMode = 'indexed'
                entry.colorIndex = option.type == 'pearl' and pearl or wheel
            end
            public.options[#public.options + 1] = entry
            end
        end
        if #public.options > 0 then data.sections[#data.sections + 1] = public end
        end
    end
    return data
end

local cameraFocusKinds = {
    overview = 'overview',
    performance = 'front_high', engine = 'front_high', turbo = 'front_high',
    brakes = 'wheel_front', suspension = 'wheel_front', transmission = 'side_low', armor = 'side',
    body = 'overview', spoiler = 'rear_high', front_bumper = 'front', rear_bumper = 'rear',
    side_skirt = 'side_low', exhaust = 'rear', grille = 'front', hood = 'front_high',
    roof = 'roof', livery = 'side',
    wheels = 'wheel_front', wheel_color = 'wheel_front',
    visual = 'side', primary = 'side', secondary = 'side', pearlescent = 'side',
    paint_type_primary = 'side', paint_type_secondary = 'side',
    window_tint = 'side_high', neon_enabled = 'side_low', neon = 'side_low',
    xenon = 'front', headlight_color = 'front',
}

local function cameraPreset(vehicle, rawKey)
    local key = tostring(rawKey or 'overview')
    local kind = key:sub(1, 6) == 'wheel_' and 'wheel_front' or cameraFocusKinds[key] or 'overview'
    local minimum, maximum = GetModelDimensions(GetEntityModel(vehicle))
    local width = math.max(1.4, math.abs(maximum.x - minimum.x))
    local length = math.max(2.5, math.abs(maximum.y - minimum.y))
    local height = math.max(1.0, math.abs(maximum.z - minimum.z))
    local config = OBMechanicConfig.Camera or {}
    local minDistance = tonumber(config.MinDistance) or 4.5
    local maxDistance = tonumber(config.MaxDistance) or 8.5
    local distance = math.max(minDistance, math.min(maxDistance, math.max(width, length) * 1.15 + 1.6))
    local centerZ = minimum.z + height * 0.52
    local top = maximum.z
    local front, rear, left = maximum.y, minimum.y, minimum.x

    if kind == 'front' then
        return { x = 0.0, y = front + distance * 0.58, z = centerZ + 0.25 },
            { x = 0.0, y = front * 0.72, z = centerZ }
    elseif kind == 'front_high' then
        return { x = 0.0, y = front + distance * 0.60, z = top + 1.0 },
            { x = 0.0, y = front * 0.34, z = minimum.z + height * 0.72 }
    elseif kind == 'rear' then
        return { x = 0.0, y = rear - distance * 0.58, z = centerZ + 0.15 },
            { x = 0.0, y = rear * 0.75, z = minimum.z + height * 0.45 }
    elseif kind == 'rear_high' then
        return { x = 0.0, y = rear - distance * 0.58, z = top + 0.85 },
            { x = 0.0, y = rear * 0.72, z = minimum.z + height * 0.78 }
    elseif kind == 'side_low' then
        return { x = left - distance * 0.58, y = 0.0, z = minimum.z + 0.65 },
            { x = left * 0.72, y = 0.0, z = minimum.z + 0.28 }
    elseif kind == 'side_high' then
        return { x = left - distance * 0.62, y = 0.0, z = top + 0.55 },
            { x = left * 0.62, y = 0.0, z = minimum.z + height * 0.72 }
    elseif kind == 'side' then
        return { x = left - distance * 0.72, y = 0.0, z = centerZ + 0.35 },
            { x = left * 0.48, y = 0.0, z = centerZ }
    elseif kind == 'wheel_front' then
        return { x = left - distance * 0.48, y = front * 0.68, z = minimum.z + 0.75 },
            { x = left * 0.92, y = front * 0.58, z = minimum.z + 0.32 }
    elseif kind == 'roof' then
        return { x = left - distance * 0.60, y = 0.0, z = top + 2.15 },
            { x = 0.0, y = 0.0, z = minimum.z + height * 0.90 }
    end

    return { x = left - distance * 0.62, y = rear - distance * 0.42, z = top + 0.75 },
        { x = 0.0, y = 0.0, z = centerZ }
end

local function desiredCameraPoints(state, vehicle)
    local position, target = state.localPosition, state.localTarget
    local radians = math.rad(state.yaw or 0.0)
    local offsetX, offsetY = position.x - target.x, position.y - target.y
    local rotatedX = target.x + offsetX * math.cos(radians) - offsetY * math.sin(radians)
    local rotatedY = target.y + offsetX * math.sin(radians) + offsetY * math.cos(radians)
    local worldPosition = GetOffsetFromEntityInWorldCoords(vehicle,
        rotatedX, rotatedY, position.z + (state.heightOffset or 0.0))
    local worldTarget = GetOffsetFromEntityInWorldCoords(vehicle, target.x, target.y, target.z)
    return worldPosition, worldTarget
end

local function updateTuningCamera()
    local state, vehicle = tuning.camera, tuning.vehicle
    if not state or not state.handle or not DoesCamExist(state.handle)
        or not vehicle or not DoesEntityExist(vehicle) or not state.localPosition then return end

    local position, target = desiredCameraPoints(state, vehicle)
    if state.transitionDuration and state.transitionDuration > 0 then
        local elapsed = GetGameTimer() - state.transitionStart
        local progress = math.max(0.0, math.min(1.0, elapsed / state.transitionDuration))
        progress = progress * progress * (3.0 - 2.0 * progress)
        local fromPosition, fromTarget = state.fromPosition, state.fromTarget
        position = vector3(
            fromPosition.x + (position.x - fromPosition.x) * progress,
            fromPosition.y + (position.y - fromPosition.y) * progress,
            fromPosition.z + (position.z - fromPosition.z) * progress)
        target = vector3(
            fromTarget.x + (target.x - fromTarget.x) * progress,
            fromTarget.y + (target.y - fromTarget.y) * progress,
            fromTarget.z + (target.z - fromTarget.z) * progress)
        if elapsed >= state.transitionDuration then state.transitionDuration = 0 end
    end
    state.currentTarget = target
    SetCamCoord(state.handle, position.x, position.y, position.z)
    PointCamAtCoord(state.handle, target.x, target.y, target.z)
end

local function focusTuningCamera(rawKey, instant)
    local state, vehicle = tuning.camera, tuning.vehicle
    if not state or not vehicle or not DoesEntityExist(vehicle) then return false end
    local position, target = cameraPreset(vehicle, rawKey)
    local targetWorld = GetOffsetFromEntityInWorldCoords(vehicle, target.x, target.y, target.z)
    state.fromPosition = GetCamCoord(state.handle)
    state.fromTarget = state.currentTarget or targetWorld
    state.localPosition = position
    state.localTarget = target
    state.yaw = 0.0
    state.heightOffset = 0.0
    state.transitionStart = GetGameTimer()
    state.transitionDuration = instant and 0 or 550
    updateTuningCamera()
    return true
end

local function stopTuningCamera()
    local state = tuning.camera
    if state and state.handle and DoesCamExist(state.handle) then
        RenderScriptCams(false, true, 350, true, true)
        DestroyCam(state.handle, false)
    end
    tuning.camera = nil
end

local function startTuningCamera(vehicle)
    local config = OBMechanicConfig.Camera or {}
    if config.Enabled == false then return end

    local handle = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    if not handle or handle == 0 then return end

    tuning.camera = {
        handle = handle,
        yaw = 0.0,
        heightOffset = 0.0,
    }
    SetCamFov(handle, tonumber(config.FieldOfView) or 45.0)
    SetCamActive(handle, true)
    focusTuningCamera('overview', true)
    RenderScriptCams(true, true, 350, true, true)

    CreateThread(function()
        while tuning.open and tuning.camera and tuning.camera.handle == handle do
            updateTuningCamera()
            Wait(0)
        end
    end)
end

local function closeTuning(revert)
    if not tuning.open then return end
    if revert then restoreVehicle(tuning.vehicle, tuning.original) end
    stopTuningCamera()
    if tuning.vehicle and DoesEntityExist(tuning.vehicle) then FreezeEntityPosition(tuning.vehicle, false) end
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
    tuning = { open = false, vehicle = nil, original = nil, station = nil, camera = nil, visualFlags = {}, toggleStates = {}, extraStates = {}, markupPercent = 0 }
end

local function openTuning(station)
    if tuning.open then return end
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then return OR.Notify('Entre no veiculo como motorista para usar a oficina.', 'error') end
    if not requestControl(vehicle) then return OR.Notify('Nao foi possivel controlar este veiculo.', 'error') end
    local allowed, access = OR.Callback.awaitResource('ob_mecanico', 'stationAccess', station.id)
    if allowed ~= true then return OR.Notify(access or 'Voce nao pode usar esta oficina.', 'error') end
    SetVehicleModKit(vehicle, 0)
    tuning = {
        open = true, vehicle = vehicle, original = nil, station = station,
        camera = nil, visualFlags = {}, toggleStates = {}, extraStates = {},
        markupPercent = tonumber(type(access) == 'table' and access.markupPercent) or 0,
    }
    tuning.original = captureVehicle(vehicle)
    for index, enabled in pairs(tuning.original.toggles or {}) do
        tuning.toggleStates[index] = enabled == true
    end
    for index, enabled in pairs((tuning.original.properties and tuning.original.properties.extras) or {}) do
        tuning.extraStates[tonumber(index) or index] = enabled == true
    end
    FreezeEntityPosition(vehicle, true)
    startTuningCamera(vehicle)
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'open', data = menuState() })
end

RegisterNUICallback('state', function(_, cb) cb(menuState()) end)
RegisterNUICallback('cameraFocus', function(data, cb)
    local key = data and (data.key or data.section) or 'overview'
    cb({ ok = tuning.open and focusTuningCamera(key, false) == true })
end)
RegisterNUICallback('cameraRotate', function(data, cb)
    local camera = tuning.camera
    if not tuning.open or not camera then return cb({ ok = false }) end
    local sensitivity = tonumber((OBMechanicConfig.Camera or {}).ManualSensitivity) or 0.28
    camera.yaw = camera.yaw - math.max(-120.0, math.min(120.0, tonumber(data and data.x) or 0.0)) * sensitivity
    camera.heightOffset = math.max(-1.3, math.min(2.0,
        camera.heightOffset - math.max(-80.0, math.min(80.0, tonumber(data and data.y) or 0.0)) * sensitivity * 0.035))
    camera.transitionDuration = 0
    updateTuningCamera()
    cb({ ok = true })
end)
RegisterNUICallback('change', function(data, cb)
    local option = data and optionByKey[data.key]
    if tuning.open and option then applyChange(option, tonumber(data.delta) or 1) end
    cb({ ok = true })
end)
RegisterNUICallback('choices', function(data, cb)
    local option = data and optionByKey[data.key]
    if not option then return cb({ ok = false, choices = {} }) end
    local choices = choicesForOption(option, true)
    local total = pendingTuningPrice()
    cb({
        ok = true,
        key = option.key,
        label = option.label,
        choices = choices,
        totalPrice = total,
        totalPriceLabel = OR.FormatMoney(total),
    })
end)
RegisterNUICallback('selectChoice', function(data, cb)
    local option = data and optionByKey[data.key]
    local ok = selectChoice(option, data and data.value)
    cb({ ok = ok, choices = ok and choicesForOption(option, false) or {} })
end)
RegisterNUICallback('setColor', function(data, cb)
    local option = data and optionByKey[data.key]
    local vehicle = tuning.vehicle
    if not tuning.open or not option or not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return cb({ ok = false })
    end

    local red = math.max(0, math.min(255, math.floor(tonumber(data.r) or 0)))
    local green = math.max(0, math.min(255, math.floor(tonumber(data.g) or 0)))
    local blue = math.max(0, math.min(255, math.floor(tonumber(data.b) or 0)))
    if option.type == 'color' then
        SetVehicleCustomPrimaryColour(vehicle, red, green, blue)
        tuning.visualFlags.primaryCustom = true
    elseif option.type == 'color2' then
        SetVehicleCustomSecondaryColour(vehicle, red, green, blue)
        tuning.visualFlags.secondaryCustom = true
    elseif option.type == 'neon' then
        for side = 0, 3 do SetVehicleNeonLightEnabled(vehicle, side, true) end
        SetVehicleNeonLightsColour(vehicle, red, green, blue)
        tuning.visualFlags.neonEnabled = true
    elseif option.type == 'pearl' or option.type == 'wheel_color' then
        local index = math.max(0, math.min(159, math.floor(tonumber(data.index) or 0)))
        local pearl, wheel = GetVehicleExtraColours(vehicle)
        if option.type == 'pearl' then pearl = index else wheel = index end
        SetVehicleExtraColours(vehicle, pearl, wheel)
    else
        return cb({ ok = false })
    end
    cb({ ok = true })
end)
RegisterNUICallback('apply', function(_, cb)
    local vehicle = tuning.vehicle
    if not tuning.open or not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return cb({ ok = false, message = 'O veiculo da oficina nao esta mais disponivel.' })
    end
    if GetResourceState('ob_garage') ~= 'started' then
        OR.Notify('A garagem esta indisponivel para salvar o tuning.', 'error')
        return cb({ ok = false, message = 'Garagem indisponivel.' })
    end

    local captured, properties = pcall(function()
        return exports.ob_garage:CaptureProperties(vehicle)
    end)
    if not captured or type(properties) ~= 'table' then
        OR.Notify('Nao foi possivel ler as modificacoes do veiculo.', 'error')
        return cb({ ok = false, message = 'Falha ao capturar o tuning.' })
    end
    properties.toggles = type(properties.toggles) == 'table' and properties.toggles or {}
    for index, enabled in pairs(tuning.toggleStates or {}) do
        properties.toggles[tostring(index)] = enabled == true
        if tonumber(index) == 18 then
            for _ = 1, 6 do ToggleVehicleMod(vehicle, 18, enabled == true); Wait(0) end
        end
    end
    properties.extras = type(properties.extras) == 'table' and properties.extras or {}
    for index, enabled in pairs(tuning.extraStates or {}) do
        properties.extras[tostring(index)] = enabled == true
    end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local saved, saveMessage = OR.Callback.awaitResource(
        'ob_garage', 'ob_garage:server:saveTuning', netId, properties, tuning.visualFlags, tuning.station.id)
    if saved ~= true then
        OR.Notify(saveMessage or 'Nao foi possivel salvar o tuning.', 'error')
        return cb({ ok = false, message = saveMessage })
    end

    cb({ ok = true })
    closeTuning(false)
    local paid = tonumber(saveMessage) or 0
    OR.Notify(paid > 0 and ('Tuning aplicado por %s.'):format(OR.FormatMoney(paid)) or 'Tuning aplicado.', 'success')
end)
RegisterNUICallback('cancel', function(_, cb) cb({ ok = true }); closeTuning(true) end)

CreateThread(function()
    local showingTyreHelp = false
    while true do
        local sleep = 1000
        if not tuning.open and LocalPlayer.state['or:loaded'] == true then
            local coords = GetEntityCoords(PlayerPedId())
            for _, station in ipairs(OBMechanicConfig.Stations) do
                local distance = #(coords - vector3(station.coords.x, station.coords.y, station.coords.z))
                if distance <= (OBMechanicConfig.MarkerDistance or 35.0) then
                    sleep = 0
                    local color = station.color or { 31, 157, 255, 180 }
                    DrawMarker(1, station.coords.x, station.coords.y, station.coords.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 3.0, 6.0, 0.25, color[1], color[2], color[3], color[4], false, false, 2, false, nil, nil, false)
                    if distance <= (OBMechanicConfig.InteractDistance or 3.2) then
                        OR.Help.Show(('Pressione [E] para abrir %s'):format(station.label))
                        if IsControlJustPressed(0, 38) then openTuning(station) end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- Interacao fisica de reserva. Ela nao depende de raycast/NUI e garante que
-- o jogador consiga terminar o servico mesmo se um carro addon nao aceitar
-- o target. So aparece com o macaco instalado e a chave inglesa equipada.
CreateThread(function()
    while true do
        local nearestEntry, nearestDistance
        local playerCoords = GetEntityCoords(PlayerPedId())
        for _, entry in pairs(jackedVehicles) do
            if DoesEntityExist(entry.vehicle) then
                for _, probe in pairs(entry.probes or {}) do
                    local distance = #(playerCoords - probe.coords)
                    if distance <= 1.65 and (not nearestDistance or distance < nearestDistance) then
                        nearestEntry, nearestDistance = entry, distance
                    end
                end
            end
        end

        if nearestEntry and hasWrench() and not tyreActionActive then
            OR.Help.Show('Pressione ~INPUT_CONTEXT~ para fazer servico no pneu')
            showingTyreHelp = true
            if IsControlJustPressed(0, 38) then serviceNearestTyre(nearestEntry.vehicle, nearestEntry) end
            Wait(0)
        else
            if showingTyreHelp then OR.Help.Hide(); showingTyreHelp = false end
            Wait(200)
        end
    end
end)

-- Pontos discretos para indicar exatamente onde o target de cada roda esta.
-- Eles so existem enquanto o macaco esta instalado.
CreateThread(function()
    while true do
        local showing = false
        for _, entry in pairs(jackedVehicles) do
            for _, probe in pairs(entry.probes or {}) do
                local coords = probe.coords
                DrawMarker(2, coords.x, coords.y, coords.z + 0.30,
                    0.0, 0.0, 0.0, 0.0, 180.0, 0.0,
                    0.18, 0.18, 0.18, 40, 165, 255, 190,
                    false, true, 2, false, nil, nil, false)
                showing = true
            end
        end
        Wait(showing and 0 or 500)
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    closeTuning(true)
    for netId in pairs(jackedVehicles) do clearJackEntry(netId, false) end
end)

AddEventHandler('ob_target:client:ready', function()
    for _, entry in pairs(jackedVehicles) do registerJackTargets(entry) end
end)

CreateThread(function()
    Wait(1200)
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        local netId = NetworkGetNetworkIdFromEntity(vehicle)
        local jackState = Entity(vehicle).state['ob:jack_state']
        if netId > 0 and type(jackState) == 'table' then syncJack(netId, jackState) end
        local removedState = Entity(vehicle).state['ob:removed_tyres']
        if netId > 0 and type(removedState) == 'table' then
            TriggerEvent('ob_mecanico:client:syncRemovedTyres', netId, removedState)
        end
    end
end)
