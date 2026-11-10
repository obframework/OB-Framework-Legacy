local downed = false
local respawnAt = 0
local downedGeneration = 0
local downedPoseTransitionUntil = 0
local medicalPose = false
local carriedBy
local carryingTarget
local medicalMenuTarget

local weaponCauses = {
    [GetHashKey('WEAPON_UNARMED')] = 'Agressao fisica',
    [GetHashKey('WEAPON_RUN_OVER_BY_CAR')] = 'Atropelamento',
    [GetHashKey('WEAPON_RAMMED_BY_CAR')] = 'Atropelamento',
    [GetHashKey('WEAPON_FALL')] = 'Queda fatal',
    [GetHashKey('WEAPON_DROWNING')] = 'Afogamento',
    [GetHashKey('WEAPON_DROWNING_IN_VEHICLE')] = 'Afogamento em veiculo',
    [GetHashKey('WEAPON_FIRE')] = 'Queimaduras',
    [GetHashKey('WEAPON_BURN')] = 'Queimaduras',
    [GetHashKey('WEAPON_EXPLOSION')] = 'Explosao',
    [GetHashKey('WEAPON_STICKYBOMB')] = 'Explosao',
    [GetHashKey('WEAPON_GRENADE')] = 'Explosao',
    [GetHashKey('WEAPON_PROXMINE')] = 'Explosao',
    [GetHashKey('WEAPON_MOLOTOV')] = 'Coquetel molotov',
    [GetHashKey('WEAPON_ANIMAL')] = 'Ataque de animal',
}

local firearmGroups = {
    [GetHashKey('GROUP_PISTOL')] = true,
    [GetHashKey('GROUP_SMG')] = true,
    [GetHashKey('GROUP_RIFLE')] = true,
    [GetHashKey('GROUP_MG')] = true,
    [GetHashKey('GROUP_SHOTGUN')] = true,
    [GetHashKey('GROUP_SNIPER')] = true,
}

local function setPlayerHealth(health)
    local ped = PlayerPedId()
    local maxHealth = tonumber(ORHealthConfig.MaxHealth) or 200
    SetEntityMaxHealth(ped, maxHealth)
    SetEntityHealth(ped, math.max(100, math.min(maxHealth, tonumber(health) or maxHealth)))
end

local function setDeathUi(open, remaining, death)
    SendNUIMessage({
        action = open and 'open' or 'close',
        remaining = remaining or 0,
        death = death,
    })
    SetNuiFocus(open, open)
    SetNuiFocusKeepInput(false)
end

local function getPlayerFromPed(ped)
    if not ped or ped <= 0 or not DoesEntityExist(ped) then return nil end

    local playerIndex = NetworkGetPlayerIndexFromPed(ped)
    if playerIndex and playerIndex >= 0 and NetworkIsPlayerActive(playerIndex) then
        return playerIndex
    end

    for _, activePlayer in ipairs(GetActivePlayers()) do
        if GetPlayerPed(activePlayer) == ped then return activePlayer end
    end
end

local function weaponCauseLabel(causeHash)
    if weaponCauses[causeHash] then
        local label = weaponCauses[causeHash]
        local category = label == 'Atropelamento' and 'vehicle'
            or label == 'Queda fatal' and 'fall'
            or label:find('Afogamento', 1, true) and 'drowning'
            or label == 'Queimaduras' and 'fire'
            or label == 'Explosao' and 'explosion' or 'accident'
        return label, label == 'Atropelamento', category
    end

    local ok, group = pcall(GetWeapontypeGroup, causeHash)
    if ok and firearmGroups[group] then return 'Ferimento por arma de fogo', false, 'firearm' end
    if ok and group == GetHashKey('GROUP_MELEE') then return 'Agressao fisica', false, 'melee' end
    if ok and group == GetHashKey('GROUP_THROWN') then return 'Explosao', false, 'explosion' end
    return 'Ferimentos graves', false, 'accident'
end

local function captureDeathInfo(victimPed)
    local causeHash = GetPedCauseOfDeath(victimPed)
    local cause, vehicleDeath, category = weaponCauseLabel(causeHash)
    local sourceEntity = GetPedSourceOfDeath(victimPed)
    local killerPed = sourceEntity

    if sourceEntity and sourceEntity > 0 and DoesEntityExist(sourceEntity) and IsEntityAVehicle(sourceEntity) then
        vehicleDeath = true
        category = 'vehicle'
        killerPed = GetPedInVehicleSeat(sourceEntity, -1)
    elseif sourceEntity and sourceEntity > 0 and DoesEntityExist(sourceEntity) and IsEntityAPed(sourceEntity) then
        local vehicle = GetVehiclePedIsIn(sourceEntity, false)
        if vehicle and vehicle > 0 and GetPedInVehicleSeat(vehicle, -1) == sourceEntity then vehicleDeath = true end
    end

    local killerPlayer = getPlayerFromPed(killerPed)
    if killerPlayer and killerPlayer ~= PlayerId() then
        local killerSource = GetPlayerServerId(killerPlayer)
        local identity = OR.Callback.await('getDeathIdentity', killerSource)
        local killerName = type(identity) == 'table' and identity.name or 'Desconhecido'
        local killerId = type(identity) == 'table' and identity.userId or 'indisponivel'
        if vehicleDeath then
            return {
                cause = cause,
                detail = ('Voce foi atropelado por %s (ID %s).'):format(killerName, killerId),
                killerSource = killerSource,
                vehicleDeath = true,
                category = 'vehicle',
            }
        end
        return {
            cause = cause,
            detail = ('Responsavel: %s (ID %s).'):format(killerName, killerId),
            killerSource = killerSource,
            vehicleDeath = false,
            category = category,
        }
    end

    return {
        cause = cause,
        detail = ('Voce morreu por %s.'):format(cause:lower()),
        category = category,
    }
end

local function loadAnim(dictionary)
    RequestAnimDict(dictionary)
    local deadline = GetGameTimer() + 4000
    while not HasAnimDictLoaded(dictionary) and GetGameTimer() < deadline do Wait(0) end
    return HasAnimDictLoaded(dictionary)
end

local function playDownedAnimation(generation)
    local ped = PlayerPedId()
    if not downed or generation ~= downedGeneration or IsPedInAnyVehicle(ped, false) then return end
    if loadAnim('dead') then
        -- loadAnim pode aguardar varios frames. Um revive ou uma entrada em
        -- veiculo durante essa espera invalida esta tarefa antiga.
        ped = PlayerPedId()
        if not downed or generation ~= downedGeneration or IsPedInAnyVehicle(ped, false) then return end
        TaskPlayAnim(ped, 'dead', 'dead_a', 8.0, -8.0, -1, 1, 0.0, false, false, false)
    elseif downed and generation == downedGeneration and not IsPedInAnyVehicle(ped, false) then
        SetPedToRagdoll(ped, 1500, 1500, 0, false, false, false)
    end
end

local function restoreDownedPose()
    local ped = PlayerPedId()
    if not downed or medicalPose or carriedBy or LocalPlayer.state['or:downed'] ~= true
        or IsPedInAnyVehicle(ped, false) then return false end

    local generation = downedGeneration
    downedPoseTransitionUntil = GetGameTimer() + 650
    ClearPedTasksImmediately(ped)
    ClearPedSecondaryTask(ped)
    SetEntityInvincible(ped, true)
    SetPedCanRagdoll(ped, true)
    SetPedToRagdoll(ped, 650, 650, 0, false, false, false)

    CreateThread(function()
        Wait(650)
        ped = PlayerPedId()
        if downed and generation == downedGeneration and not IsPedInAnyVehicle(ped, false) then
            ClearPedTasksImmediately(ped)
            playDownedAnimation(generation)
        end
    end)
    return true
end

local function playGetUpAnimation()
    local ped = PlayerPedId()
    if loadAnim('get_up@directional@transition@prone_to_knees@crawl') then
        TaskPlayAnim(ped, 'get_up@directional@transition@prone_to_knees@crawl', 'back', 4.0, -4.0, 2200, 0, 0.0, false, false, false)
    else
        TaskGetUp(ped, 3500)
    end
end

local function startDownedLoops()
    local generation = downedGeneration
    CreateThread(function()
        while downed and generation == downedGeneration do
            Wait(0)
            if not downed or generation ~= downedGeneration then break end
            DisableAllControlActions(0)
            EnableControlAction(0, 1, true)
            EnableControlAction(0, 2, true)
            EnableControlAction(0, 245, true)
            local ped = PlayerPedId()
            -- A animacao dead_a e propria para o chao. Dentro de um veiculo
            -- ela conflita com o assento e pode ocultar/desalinhar o ped.
            if GetGameTimer() >= downedPoseTransitionUntil
                and not medicalPose
                and not carriedBy
                and not IsPedInAnyVehicle(ped, false)
                and not IsEntityPlayingAnim(ped, 'dead', 'dead_a', 3) then
                playDownedAnimation(generation)
            end
        end
    end)

    CreateThread(function()
        while downed and generation == downedGeneration do
            local remaining = math.max(0, respawnAt - GetGameTimer())
            SendNUIMessage({ action = 'tick', remaining = remaining })
            Wait(1000)
        end
    end)
end

local function currentVehicleSeat(ped)
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return 0 end
    for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        if GetPedInVehicleSeat(vehicle, seat) == ped then return vehicle, seat end
    end
    return 0
end

local function restoreVehicleSeat(ped, vehicle, seat)
    if vehicle == 0 or seat == nil or not DoesEntityExist(vehicle) then return end
    if GetPedInVehicleSeat(vehicle, seat) == ped then return end
    if IsVehicleSeatFree(vehicle, seat) then SetPedIntoVehicle(ped, vehicle, seat) end
end

local function resurrectInPlace(ped)
    local vehicle, seat = currentVehicleSeat(ped)
    local coords = GetEntityCoords(ped)
    -- bLeaveDeadPed=false: nao criar o corpo local que parece um clone na Legacy.
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, GetEntityHeading(ped), 0, false, false)
    Wait(0)
    ped = PlayerPedId()
    restoreVehicleSeat(ped, vehicle, seat)
    return ped
end

local function applyDownedState(remaining, death)
    if downed then return end

    downedGeneration = downedGeneration + 1
    downed = true
    medicalMenuTarget = nil
    SendNUIMessage({ action = 'medicalClose' })
    remaining = math.max(0, tonumber(remaining) or ORHealthConfig.RespawnDelay)
    respawnAt = GetGameTimer() + remaining
    local ped = PlayerPedId()
    if IsEntityDead(ped) or GetEntityHealth(ped) <= 0 then
        ped = resurrectInPlace(ped)
    end
    setPlayerHealth(ORHealthConfig.DownedHealth)
    SetEntityInvincible(ped, true)
    if not IsPedInAnyVehicle(ped, false) then playDownedAnimation(downedGeneration) end
    TriggerEvent('ob_hud:client:setDeathHidden', true)
    setDeathUi(true, remaining, death)
    startDownedLoops()
end

local function enterDowned()
    if downed or LocalPlayer.state['or:loaded'] ~= true then return end

    local ped = PlayerPedId()
    local death = captureDeathInfo(ped)
    applyDownedState(ORHealthConfig.RespawnDelay, death)
    TriggerServerEvent('ob_health:server:playerDowned', death)
    TriggerServerEvent('ob_health:server:stopCarry')
end

local function restoreRevivedPed(health, instant)
    local ped = PlayerPedId()
    local vehicle, seat = currentVehicleSeat(ped)
    local wasDowned = downed
        or LocalPlayer.state['or:downed'] == true
        or IsEntityDead(ped)
        or GetEntityHealth(ped) <= 0

    -- O /revive tambem funciona como recuperacao completa para um jogador que
    -- ja esta vivo. Nesse caso nao ressuscite nem limpe as tarefas do ped:
    -- ClearPedTasksImmediately remove a tarefa do assento e expulsa o jogador
    -- do veiculo, enquanto NetworkResurrectLocalPlayer recria seu estado local.
    if not wasDowned then
        setPlayerHealth(tonumber(health) or ORHealthConfig.ReviveHealth)
        ClearPedBloodDamage(ped)
        ResetPedVisibleDamage(ped)
        return
    end

    downedGeneration = downedGeneration + 1
    downed = false
    medicalPose = false
    carriedBy = nil
    setDeathUi(false)
    TriggerEvent('ob_hud:client:setDeathHidden', false)

    if IsEntityDead(ped) or GetEntityHealth(ped) <= 0 then
        ped = resurrectInPlace(ped)
    end

    SetEntityInvincible(ped, false)
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    if vehicle == 0 then DetachEntity(ped, true, false) end
    ResetEntityAlpha(ped)
    SetPedCanRagdoll(ped, false)
    setPlayerHealth(tonumber(health) or ORHealthConfig.ReviveHealth)
    if vehicle == 0 then ClearPedTasksImmediately(ped) end
    ClearPedSecondaryTask(ped)
    ResetPedMovementClipset(ped, 0.0)
    ResetPedStrafeClipset(ped)
    ResetPedWeaponMovementClipset(ped)
    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)

    -- O loop de incapacitado desabilita todos os controles a cada frame. Como
    -- ele pode ter executado no mesmo frame do revive, liberamos explicitamente
    -- os controles depois de derrubar a flag.
    Wait(0)
    -- Garante que nenhuma tarefa criada antes da troca de geracao sobreviveu
    -- ao mesmo frame do revive.
    if not IsPedInAnyVehicle(ped, false) then ClearPedTasksImmediately(ped) end
    ClearPedSecondaryTask(ped)
    SetPedCanRagdoll(ped, true)
    SetPedCanRagdollFromPlayerImpact(ped, true)
    EnableAllControlActions(0)

    restoreVehicleSeat(ped, vehicle, seat)
    if not instant and not IsPedInAnyVehicle(ped, false) then playGetUpAnimation() end
end

RegisterNetEvent('ob_health:client:revive', function(health, _, instant)
    print(('[ob_health] Revive recebido (instantaneo=%s).'):format(tostring(instant == true)))
    restoreRevivedPed(health, instant == true)
end)

RegisterNetEvent('ob_health:client:heal', function(amount)
    if downed then return end
    local ped = PlayerPedId()
    local health = GetEntityHealth(ped)
    setPlayerHealth(health + math.max(1, tonumber(amount) or 1))
    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)
end)

local function hasLocalEmsAccess()
    local settings = type(ORHealthConfig.EMS) == 'table' and ORHealthConfig.EMS or {}
    if settings.Enabled ~= true then return false end
    local membership = LocalPlayer.state['ob:org']
    if type(membership) ~= 'table' then return false end
    local permission = tostring(settings.Permission or 'ambulance'):lower()
    if tostring(membership.key or ''):lower() ~= permission then return false end
    return settings.RequireDuty ~= true or membership.onDuty == true
end

local function setMedicalMenu(open, patient)
    if open ~= true then
        medicalMenuTarget = nil
        SendNUIMessage({ action = 'medicalClose' })
        SetNuiFocus(false, false)
        return
    end
    medicalMenuTarget = tonumber(patient and patient.source)
    SendNUIMessage({ action = 'medicalOpen', patient = patient or {} })
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
end

local function firstFreePassengerSeat(vehicle)
    local passengers = math.max(0, tonumber(GetVehicleMaxNumberOfPassengers(vehicle)) or 0)
    for seat = 0, passengers - 1 do
        if IsVehicleSeatFree(vehicle, seat) then return seat end
    end
end

local function runMedicalProgress(label, duration, animation)
    return exports.ob_lib:Progress({
        label = label,
        duration = duration,
        canCancel = true,
        animation = animation,
    })
end

local function performMedicalAction(action, targetSource)
    local settings = type(ORHealthConfig.EMS) == 'table' and ORHealthConfig.EMS or {}
    if not hasLocalEmsAccess() then
        OR.Notify('Voce nao esta autorizado ou nao esta em servico.', 'error')
        return
    end

    if action == 'examine' then
        local examination = type(settings.Examination) == 'table' and settings.Examination or {}
        local completed, progressError = runMedicalProgress('Examinando paciente...', examination.Duration or 3000, examination.Animation)
        if completed ~= true then return OR.Notify(progressError or 'Exame cancelado.', 'error') end
        local ok, result = OR.Callback.await('emsExamine', targetSource)
        if not ok then return OR.Notify(result or 'Nao foi possivel examinar o paciente.', 'error') end
        TriggerEvent('ob_health:client:openBodyScan', targetSource, result)
        return
    end

    if action == 'treat' then
        local treatment = type(settings.Treatment) == 'table' and settings.Treatment or {}
        local ok, durationOrError = OR.Callback.await('emsBeginTreatment', targetSource)
        if not ok then return OR.Notify(durationOrError or 'Nao foi possivel iniciar o atendimento.', 'error') end
        local completed, progressError = runMedicalProgress('Prestando atendimento...', durationOrError or treatment.Duration or 8000, treatment.Animation)
        if completed ~= true then
            OR.Callback.await('emsCancelTreatment')
            return OR.Notify(progressError or 'Atendimento cancelado.', 'error')
        end
        local success, result = OR.Callback.await('emsFinishTreatment', targetSource)
        OR.Notify(result or (success and 'Atendimento concluido.' or 'Atendimento recusado.'), success and 'success' or 'error')
        return
    end

    if action == 'revive' then
        local revive = type(settings.Revive) == 'table' and settings.Revive or {}
        local ok, durationOrError = OR.Callback.await('emsBeginRevive', targetSource)
        if not ok then return OR.Notify(durationOrError or 'Nao foi possivel iniciar a reanimacao.', 'error') end
        local completed, progressError = runMedicalProgress('Realizando reanimacao...', durationOrError or revive.Duration or 15000, revive.MedicAnimation)
        if completed ~= true then
            OR.Callback.await('emsCancelRevive', targetSource)
            return OR.Notify(progressError or 'Reanimacao cancelada.', 'error')
        end
        local success, result = OR.Callback.await('emsFinishRevive', targetSource)
        OR.Notify(result or (success and 'Paciente reanimado.' or 'Reanimacao recusada.'), success and 'success' or 'error')
        return
    end

    if action == 'carry' then
        local ok, message = OR.Callback.await('emsToggleCarry', targetSource)
        OR.Notify(message or (ok and 'Transporte atualizado.' or 'Nao foi possivel transportar o paciente.'), ok and 'success' or 'error')
        return
    end

    if action == 'stretcher' then
        TriggerEvent('ob_health:client:patientStretcher', targetSource)
        return
    end

    if action == 'putVehicle' then
        local coords = GetEntityCoords(PlayerPedId())
        local vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, tonumber(settings.VehicleDistance) or 7.0, 0, 71)
        if vehicle == 0 then return OR.Notify('Nenhum veiculo proximo.', 'error') end
        local seat = firstFreePassengerSeat(vehicle)
        if seat == nil then return OR.Notify('Nao ha banco de passageiro livre nesse veiculo.', 'error') end
        local ok, message = OR.Callback.await('emsPutInVehicle', targetSource, NetworkGetNetworkIdFromEntity(vehicle), seat)
        OR.Notify(message or (ok and 'Paciente colocado no veiculo.' or 'Transporte recusado.'), ok and 'success' or 'error')
        return
    end

    if action == 'removeVehicle' then
        local ok, message = OR.Callback.await('emsRemoveFromVehicle', targetSource)
        OR.Notify(message or (ok and 'Paciente retirado do veiculo.' or 'Transporte recusado.'), ok and 'success' or 'error')
    end
end

RegisterNetEvent('ob_health:client:openEmsPatient', function(targetSource)
    if downed or not hasLocalEmsAccess() then return end
    CreateThread(function()
        local ok, patientOrError = OR.Callback.await('emsPatient', targetSource)
        if not ok then return OR.Notify(patientOrError or 'Paciente indisponivel.', 'error') end
        setMedicalMenu(true, patientOrError)
    end)
end)

local equipmentBusy = false
RegisterNetEvent('ob_health:client:useMedicalEquipment', function(targetSource, action)
    if equipmentBusy or downed or not hasLocalEmsAccess() then return end
    -- Fecha antes de dar foco ao painel medico, inclusive ao usar por atalho.
    TriggerEvent('ob_inventory:client:forceClose')
    if action == 'panel' then
        TriggerEvent('ob_health:client:openEmsPatient', targetSource)
        return
    end
    if action ~= 'examine' then return end
    equipmentBusy = true
    CreateThread(function()
        local ok, errorMessage = pcall(performMedicalAction, 'examine', targetSource)
        equipmentBusy = false
        if not ok then
            print(('[ob_health] Falha ao abrir exame pelo item: %s'):format(tostring(errorMessage)))
            OR.Notify('Nao foi possivel abrir o exame.', 'error')
        end
    end)
end)

RegisterNUICallback('medicalClose', function(_, callback)
    setMedicalMenu(false)
    callback({ ok = true })
end)

RegisterNUICallback('medicalAction', function(data, callback)
    local action = type(data) == 'table' and tostring(data.action or '') or ''
    local targetSource = medicalMenuTarget
    setMedicalMenu(false)
    callback({ ok = targetSource ~= nil and action ~= '' })
    if not targetSource or action == '' then return end
    CreateThread(function() performMedicalAction(action, targetSource) end)
end)

RegisterNetEvent('ob_health:client:medicalPose', function(enabled, animation)
    local ped = PlayerPedId()
    medicalPose = enabled == true
    if medicalPose then
        ClearPedTasksImmediately(ped)
        if type(animation) == 'table' and loadAnim(animation.dict) then
            TaskPlayAnim(ped, animation.dict, animation.clip, 4.0, -4.0, -1, animation.flag or 1, 0.0, false, false, false)
        end
        return
    end
    if not IsPedInAnyVehicle(ped, false) then ClearPedTasksImmediately(ped) end
    if downed and not carriedBy and not IsPedInAnyVehicle(ped, false) then
        CreateThread(function() Wait(100); restoreDownedPose() end)
    end
end)

RegisterNetEvent('ob_health:client:setCarried', function(enabled, carrierSource)
    local ped = PlayerPedId()
    if enabled ~= true then
        carriedBy = nil
        medicalPose = false
        if not IsPedInAnyVehicle(ped, false) then
            DetachEntity(ped, true, false)
            ClearPedTasksImmediately(ped)
        end
        if downed and not IsPedInAnyVehicle(ped, false) then
            CreateThread(function() Wait(100); restoreDownedPose() end)
        end
        return
    end
    local carrierPlayer = GetPlayerFromServerId(tonumber(carrierSource) or -1)
    if carrierPlayer < 0 then return end
    local carrierPed = GetPlayerPed(carrierPlayer)
    if carrierPed <= 0 then return end
    carriedBy = tonumber(carrierSource)
    medicalPose = true
    ClearPedTasksImmediately(ped)
    if loadAnim('nm') then TaskPlayAnim(ped, 'nm', 'firemans_carry', 8.0, -8.0, -1, 33, 0.0, false, false, false) end
    AttachEntityToEntity(ped, carrierPed, 0, 0.27, 0.15, 0.63, 0.5, 0.5, 180.0, false, false, false, false, 2, false)
end)

RegisterNetEvent('ob_health:client:setCarrier', function(enabled, targetSource)
    carryingTarget = enabled == true and tonumber(targetSource) or nil
    local generationTarget = carryingTarget
    local ped = PlayerPedId()
    if not carryingTarget then
        StopAnimTask(ped, 'missfinale_c2mcs_1', 'fin_c2_mcs_1_camman', 1.0)
        return
    end
    CreateThread(function()
        if not loadAnim('missfinale_c2mcs_1') then return end
        while carryingTarget == generationTarget do
            ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false) then
                TriggerServerEvent('ob_health:server:stopCarry')
                break
            end
            DisableControlAction(0, 73, true)
            if IsDisabledControlJustPressed(0, 73) then
                TriggerServerEvent('ob_health:server:stopCarry')
            end
            if not IsEntityPlayingAnim(ped, 'missfinale_c2mcs_1', 'fin_c2_mcs_1_camman', 3) then
                TaskPlayAnim(ped, 'missfinale_c2mcs_1', 'fin_c2_mcs_1_camman', 8.0, -8.0, -1, 49, 0.0, false, false, false)
            end
            Wait(0)
        end
    end)
end)

RegisterNetEvent('ob_health:client:medicalVehicle', function(enter, netId, seat)
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    local ped = PlayerPedId()
    if enter == true then
        carriedBy = nil
        medicalPose = false
        DetachEntity(ped, true, false)
        ClearPedTasksImmediately(ped)
        seat = math.floor(tonumber(seat) or -1)
        if seat >= 0 and IsVehicleSeatFree(vehicle, seat) then SetPedIntoVehicle(ped, vehicle, seat) end
        return
    end
    if GetVehiclePedIsIn(ped, false) ~= vehicle then return end
    ClearPedTasksImmediately(ped)
    TaskLeaveVehicle(ped, vehicle, 16)
    local deadline = GetGameTimer() + 2500
    while GetVehiclePedIsIn(ped, false) == vehicle and GetGameTimer() < deadline do Wait(0) end
    if downed and GetVehiclePedIsIn(ped, false) == 0 then
        CreateThread(function() Wait(100); restoreDownedPose() end)
    end
end)

local function registerTargetOption()
    if GetResourceState('ob_target') ~= 'started' then return end

    exports.ob_target:AddPlayerOption('ob_health:adrenaline', {
        label = 'Usar adrenalina para reanimar',
        icon = '+',
        event = 'ob_health:client:targetRevive',
        stateKey = 'or:downed',
        stateValue = true,
        distance = (ORHealthConfig.AdrenalineZone and ORHealthConfig.AdrenalineZone.useDistance) or 4.0,
        canInteract = function(_, targetPed)
            if hasLocalEmsAccess() then return false end
            local zone = ORHealthConfig.AdrenalineZone
            if type(zone) ~= 'table' then return false end
            local function inside(coords)
                local dx, dy, dz = coords.x - zone.x, coords.y - zone.y, coords.z - zone.z
                return (dx * dx) + (dy * dy) <= (zone.radius * zone.radius)
                    and math.abs(dz) <= (tonumber(zone.maxVerticalDistance) or 2.0)
            end
            return inside(GetEntityCoords(PlayerPedId())) and inside(GetEntityCoords(targetPed))
        end,
    })

    exports.ob_target:AddPlayerOption('ob_health:ems_patient', {
        label = 'Atendimento EMS',
        icon = '+',
        event = 'ob_health:client:openEmsPatient',
        distance = (ORHealthConfig.EMS and ORHealthConfig.EMS.InteractionDistance) or 3.0,
        canInteract = function()
            return hasLocalEmsAccess()
        end,
    })
end

RegisterNetEvent('ob_health:client:targetRevive', function(targetSource)
    if downed then
        OR.Notify('Voce nao pode reanimar alguem enquanto estiver incapacitado.', 'error')
        return
    end
    CreateThread(function()
        local completed, errorMessage = exports.ob_core:Progress(ORHealthConfig.AdrenalineProgress)
        if completed ~= true then
            OR.Notify(errorMessage or 'Acao cancelada.', 'error')
            return
        end
        TriggerServerEvent('ob_health:server:targetRevive', targetSource)
    end)
end)

RegisterNetEvent('ob_health:client:targetResult', function(success, message)
    OR.Notify(message or (success and 'Jogador reanimado.' or 'Nao foi possivel reanimar o jogador.'), success and 'success' or 'error')
end)

CreateThread(function()
    Wait(500)
    registerTargetOption()
end)

RegisterNetEvent('ob_health:client:respawn', function(coords)
    if type(coords) ~= 'table' then return end
    downedGeneration = downedGeneration + 1
    downed = false
    medicalPose = false
    carriedBy = nil
    carryingTarget = nil
    setDeathUi(false)
    TriggerEvent('ob_hud:client:setDeathHidden', false)
    DoScreenFadeOut(300)
    Wait(350)
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, coords.heading or 0.0, 0, false, false)
    local ped = PlayerPedId()
    DetachEntity(ped, true, false)
    setPlayerHealth(ORHealthConfig.ReviveHealth)
    SetEntityInvincible(ped, false)
    ClearPedTasksImmediately(ped)
    DoScreenFadeIn(500)
end)

RegisterNUICallback('giveUp', function(_, callback)
    if downed and GetGameTimer() >= respawnAt then
        TriggerServerEvent('ob_health:server:requestRespawn')
        callback({ ok = true })
        return
    end
    callback({ ok = false })
end)

RegisterNUICallback('npcRescue', function(_, callback)
    TriggerServerEvent('ob_health:server:requestNpcRescue')
    callback({ ok = true })
end)

CreateThread(function()
    while true do
        Wait(250)
        if not downed and LocalPlayer.state['or:loaded'] == true then
            local ped = PlayerPedId()
            if IsEntityDead(ped) or GetEntityHealth(ped) <= 0 then enterDowned() end
        end
    end
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() or resourceName == 'ob_target' then
        CreateThread(function()
            Wait(500)
            registerTargetOption()
            if resourceName == GetCurrentResourceName() and LocalPlayer.state['or:loaded'] == true then
                local deathState = OR.Callback.await('getDownedState')
                if type(deathState) == 'table' and deathState.downed == true then
                    applyDownedState(deathState.remaining, deathState.death)
                end
            end
        end)
    end
end)

AddEventHandler('ob_target:client:ready', function()
    registerTargetOption()
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        downedGeneration = downedGeneration + 1
        downed = false
        setDeathUi(false)
        TriggerEvent('ob_hud:client:setDeathHidden', false)
        local ped = PlayerPedId()
        medicalPose = false
        carriedBy = nil
        carryingTarget = nil
        DetachEntity(ped, true, false)
        SetEntityInvincible(ped, false)
        SetNuiFocus(false, false)
        if GetResourceState('ob_target') == 'started' then
            exports.ob_target:RemovePlayerOption('ob_health:adrenaline')
            exports.ob_target:RemovePlayerOption('ob_health:ems_patient')
        end
    end
end)

exports('RestoreDownedPose', restoreDownedPose)
