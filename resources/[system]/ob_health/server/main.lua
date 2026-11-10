local downedPlayers = {}
local pendingTreatments = {}
local pendingRevives = {}
local carriedPlayers = {}
local carryingPlayers = {}
local releaseCarriedPlayer

local function validSource(playerSource)
    playerSource = tonumber(playerSource)
    return playerSource and playerSource > 0 and GetPlayerName(playerSource) and playerSource or nil
end

local function getCharacterIdentity(playerSource)
    playerSource = validSource(playerSource)
    if not playerSource or GetResourceState('ob_core') ~= 'started' then return nil end

    local fullName = exports.ob_core:GetFullName(playerSource)
    local userId = tonumber(exports.ob_core:GetUserId(playerSource))
    if type(fullName) ~= 'string' or fullName:match('^%s*$') or not userId then return nil end

    return {
        name = fullName:sub(1, 65),
        userId = userId,
    }
end

local function cleanDeathInfo(death)
    death = type(death) == 'table' and death or {}
    local detail = type(death.detail) == 'string' and death.detail:sub(1, 160) or 'Voce sofreu ferimentos graves.'
    local killerSource = validSource(death.killerSource)
    local identity = killerSource and getCharacterIdentity(killerSource)
    local allowedCategories = {
        firearm = true, fall = true, vehicle = true, drowning = true,
        fire = true, explosion = true, melee = true, accident = true,
    }
    local category = type(death.category) == 'string' and death.category:lower() or 'accident'
    if not allowedCategories[category] then category = 'accident' end

    -- O cliente informa apenas qual entidade causou a morte. Nome e ID sao
    -- reconstruidos pelo servidor a partir do personagem carregado no core.
    if identity then
        if death.vehicleDeath == true then
            detail = ('Voce foi atropelado por %s (ID %s).'):format(identity.name, identity.userId)
        else
            detail = ('Responsavel: %s (ID %s).'):format(identity.name, identity.userId)
        end
    end

    return {
        cause = type(death.cause) == 'string' and death.cause:sub(1, 96) or 'Ferimentos graves',
        detail = detail,
        category = category,
        playerCaused = identity ~= nil,
    }
end

local function setDowned(playerSource, value, death)
    playerSource = validSource(playerSource)
    if not playerSource then return false end

    if value then
        local state = downedPlayers[playerSource]
        downedPlayers[playerSource] = state or {
            -- Os state bags sobrevivem ao restart deste recurso. O horario
            -- absoluto permite devolver o mesmo contador ao cliente depois.
            startedAt = os.time(),
            expiresAt = os.time() + math.ceil((tonumber(ORHealthConfig.RespawnDelay) or 120000) / 1000),
            death = cleanDeathInfo(death),
        }
    else
        if releaseCarriedPlayer then releaseCarriedPlayer(playerSource) end
        TriggerEvent('ob_health:server:patientRecovered', playerSource)
        if pendingRevives[playerSource] then
            pendingRevives[playerSource] = nil
            TriggerClientEvent('ob_health:client:medicalPose', playerSource, false)
        end
        downedPlayers[playerSource] = nil
    end

    local player = Player(playerSource)
    if player then
        player.state:set('or:downed', value == true, true)
        player.state:set('or:downedAt', value and downedPlayers[playerSource].startedAt or nil, true)
        player.state:set('or:downedUntil', value and downedPlayers[playerSource].expiresAt or nil, true)
        player.state:set('or:deathInfo', value and downedPlayers[playerSource].death or nil, true)
    end
    return true
end

local function isDowned(playerSource)
    return downedPlayers[tonumber(playerSource)] ~= nil
end

local function playerCoords(playerSource)
    local ped = GetPlayerPed(playerSource)
    if not ped or ped <= 0 then return nil end
    return GetEntityCoords(ped)
end

local function isInAdrenalineZone(playerSource)
    local coords = playerCoords(playerSource)
    local zone = ORHealthConfig.AdrenalineZone
    if not coords or type(zone) ~= 'table' then return false end

    local dx, dy, dz = coords.x - zone.x, coords.y - zone.y, coords.z - zone.z
    local horizontal = (dx * dx) + (dy * dy) <= (zone.radius * zone.radius)
    return horizontal and math.abs(dz) <= (tonumber(zone.maxVerticalDistance) or 2.0)
end

local function playersAreClose(firstSource, secondSource, requestedDistance)
    if firstSource == secondSource then return true end
    local firstCoords, secondCoords = playerCoords(firstSource), playerCoords(secondSource)
    if not firstCoords or not secondCoords then return false end

    local maxDistance = tonumber(requestedDistance)
        or (ORHealthConfig.AdrenalineZone and ORHealthConfig.AdrenalineZone.useDistance) or 4.0
    local dx, dy, dz = firstCoords.x - secondCoords.x, firstCoords.y - secondCoords.y, firstCoords.z - secondCoords.z
    return (dx * dx) + (dy * dy) + (dz * dz) <= (maxDistance * maxDistance)
end

local function revivePlayer(playerSource, healerSource, health, instant)
    playerSource = validSource(playerSource)
    if not playerSource then return false, 'Jogador indisponivel.' end

    -- Permite que integracoes peçam revive imediato no terceiro argumento sem
    -- enviar um `nil` intermediario por exports entre resources.
    if type(health) == 'boolean' and instant == nil then
        instant, health = health, nil
    end

    setDowned(playerSource, false)
    print(('[ob_health] REVIVE target=%s healer=%s instant=%s'):format(playerSource, tonumber(healerSource) or 0, tostring(instant == true)))
    TriggerClientEvent('ob_health:client:revive', playerSource, tonumber(health) or ORHealthConfig.ReviveHealth, healerSource, instant == true)
    return true
end

local function healPlayer(playerSource, amount)
    playerSource = validSource(playerSource)
    if not playerSource then return false, 'Jogador indisponivel.' end
    if isDowned(playerSource) then return false, 'O jogador precisa ser reanimado primeiro.' end

    TriggerClientEvent('ob_health:client:heal', playerSource, math.max(1, tonumber(amount) or 1))
    return true
end

local function useMedicalItem(source, itemName, targetSource)
    source = validSource(source)
    targetSource = validSource(targetSource) or source
    if not source or not targetSource then return false, 'Jogador indisponivel.' end

    itemName = type(itemName) == 'string' and itemName:lower() or ''
    local item = ORHealthConfig.Items[itemName]
    if not item then return false, 'Item medico invalido.' end

    if item.revive then
        if not isDowned(targetSource) then return false, 'Esse jogador nao esta incapacitado.' end
        if not isInAdrenalineZone(source) or not isInAdrenalineZone(targetSource) then
            return false, 'A adrenalina so pode ser usada na area do HP ilegal.'
        end
        if not playersAreClose(source, targetSource) then
            return false, 'Fique proximo do jogador para usar a adrenalina.'
        end
        return revivePlayer(targetSource, source, ORHealthConfig.AdrenalineHealth or ORHealthConfig.ReviveHealth)
    end

    return healPlayer(targetSource, item.heal)
end

RegisterNetEvent('ob_health:server:playerDowned', function(death)
    if not OR.Security.rateLimit(source, 'health:downed', 3, 10000) then return end
    setDowned(source, true, death)
end)

OR.Callback.register('getDownedState', function(source)
    local state = downedPlayers[tonumber(source)]
    if not state then return { downed = false } end
    return {
        downed = true,
        remaining = math.max(0, (tonumber(state.expiresAt) or os.time()) - os.time()) * 1000,
        death = state.death,
    }
end)

OR.Callback.register('getDeathIdentity', function(_, playerSource)
    return getCharacterIdentity(playerSource)
end)

RegisterNetEvent('ob_health:server:requestRespawn', function()
    -- O handler aguarda o inventario/banco. Nessa pausa a variavel global
    -- `source` pode deixar de apontar para este evento, resultando em
    -- TriggerClientEvent sem targetSrcIdx. Capture a sessao logo na entrada.
    local playerSource = validSource(source)
    if not playerSource or not isDowned(playerSource) then return end
    if not OR.Security.rateLimit(playerSource, 'health:respawn', 2, 10000) then return end

    if GetResourceState('ob_inventory') == 'started' then
        local cleared, clearError = exports.ob_inventory:ResetAfterDeath(playerSource)
        if not cleared then
            TriggerClientEvent('ob_notification:client:notify', playerSource, clearError or 'Nao foi possivel processar a mochila apos a morte.', 'error')
            return
        end
    end

    TriggerEvent('ob_health:server:clearInjuries', playerSource)
    setDowned(playerSource, false)
    TriggerClientEvent('ob_health:client:respawn', playerSource, ORHealthConfig.Respawn)
end)

-- O inventario e quem remove a adrenalina. O health apenas valida a regra de
-- reanimacao para impedir que um cliente consuma/levante alguem fora da area.
RegisterNetEvent('ob_health:server:targetRevive', function(targetSource)
    local sourcePlayer = validSource(source)
    local targetPlayer = validSource(targetSource)
    if not sourcePlayer or not targetPlayer or sourcePlayer == targetPlayer then return end
    if not OR.Security.rateLimit(sourcePlayer, 'health:target_revive', 3, 10000) then return end

    if GetResourceState('ob_inventory') ~= 'started' then
        TriggerClientEvent('ob_health:client:targetResult', sourcePlayer, false, 'Inventario ainda nao esta disponivel.')
        return
    end

    local used, message = exports.ob_inventory:UseMedicalItem(sourcePlayer, 'adrenaline', targetPlayer)
    TriggerClientEvent('ob_health:client:targetResult', sourcePlayer, used, message)
end)

local function emsSettings()
    return type(ORHealthConfig.EMS) == 'table' and ORHealthConfig.EMS or {}
end

local function notify(playerSource, message, kind)
    playerSource = validSource(playerSource)
    if playerSource then
        TriggerClientEvent('ob_notification:client:notify', playerSource, message, kind or 'inform')
    end
end

local function hasEmsAccess(playerSource)
    local settings = emsSettings()
    if settings.Enabled ~= true or GetResourceState('ob_org') ~= 'started' then return false end
    local permission = type(settings.Permission) == 'string' and settings.Permission:lower() or 'ambulance'
    local ok, allowed = pcall(function()
        return exports.ob_org:HasPermission(playerSource, permission, settings.RequireDuty == true)
    end)
    return ok and allowed == true
end

local function validEmsPatient(emsSource, targetSource, allowSelf)
    emsSource, targetSource = validSource(emsSource), validSource(targetSource)
    if not emsSource or not targetSource or (not allowSelf and emsSource == targetSource) then
        return nil, 'Paciente indisponivel.'
    end
    if not hasEmsAccess(emsSource) then return nil, 'Voce nao esta autorizado ou nao esta em servico.' end
    local distance = tonumber(emsSettings().InteractionDistance) or 3.0
    if not playersAreClose(emsSource, targetSource, distance) then
        return nil, 'Aproxime-se do paciente.'
    end
    return targetSource
end

local function patientSummary(targetSource)
    targetSource = validSource(targetSource)
    if not targetSource then return nil end
    local identity = getCharacterIdentity(targetSource) or { name = GetPlayerName(targetSource) or 'Paciente' }
    local ped = GetPlayerPed(targetSource)
    local maximum = math.max(101, tonumber(ORHealthConfig.MaxHealth) or 200)
    local health = ped and ped > 0 and GetEntityHealth(ped) or 100
    local percentage = math.floor(math.max(0, math.min(100, ((health - 100) / (maximum - 100)) * 100)) + 0.5)
    local deathState = downedPlayers[targetSource]
    local billing = type(emsSettings().Billing) == 'table' and emsSettings().Billing or {}
    return {
        source = targetSource,
        userId = identity.userId,
        name = identity.name,
        downed = deathState ~= nil,
        health = health,
        healthPercent = percentage,
        inVehicle = ped and ped > 0 and GetVehiclePedIsIn(ped, false) ~= 0 or false,
        carriedBy = carriedPlayers[targetSource],
        death = deathState and deathState.death or nil,
        injuries = Player(targetSource).state['ob:injuries'] or {},
        prices = {
            treatment = OR.FormatMoney(math.max(0, math.floor(tonumber(billing.TreatmentPrice) or 0))),
            revive = OR.FormatMoney(math.max(0, math.floor(tonumber(billing.RevivePrice) or 0))),
        },
    }
end

local function inventoryHas(playerSource, itemName)
    if type(itemName) ~= 'string' or itemName == '' then return true end
    if GetResourceState('ob_inventory') ~= 'started' then return false end
    local count = exports.ob_inventory:GetItemCount(playerSource, itemName)
    return (tonumber(count) or 0) > 0
end

local function verifyServiceItem(playerSource, service)
    if type(service) ~= 'table' or service.RequireItem ~= true then return true end
    if inventoryHas(playerSource, service.Item) then return true end
    return false, ('Voce precisa de %s para realizar esse procedimento.'):format(tostring(service.Item or 'equipamento medico'))
end

local function takeServiceItem(playerSource, service)
    if type(service) ~= 'table' or service.RequireItem ~= true or service.ConsumeItem ~= true then return true, false end
    local removed, removeError = exports.ob_inventory:RemoveItem(playerSource, service.Item, 1)
    if removed ~= true then return false, removeError or 'Nao foi possivel consumir o item medico.' end
    return true, true
end

local function restoreServiceItem(playerSource, service, consumed)
    if consumed ~= true or type(service) ~= 'table' or type(service.Item) ~= 'string' then return end
    local restored, restoreError = exports.ob_inventory:AddItem(playerSource, service.Item, 1)
    if restored ~= true then
        print(('[ob_health] Falha ao devolver %s para source=%s: %s'):format(service.Item, playerSource, tostring(restoreError)))
    end
end

local function chargePatient(patientSource, emsSource, serviceName, amount)
    local billing = type(emsSettings().Billing) == 'table' and emsSettings().Billing or {}
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if billing.Enabled ~= true or amount == 0 then return true, 'free' end

    local patientIdentity = getCharacterIdentity(patientSource)
    local medicIdentity = getCharacterIdentity(emsSource)
    local description = ('Atendimento hospitalar: %s'):format(serviceName)
    local metadata = {
        service = serviceName,
        patientUserId = patientIdentity and patientIdentity.userId,
        medicUserId = medicIdentity and medicIdentity.userId,
    }
    local economyResult = OR.Economy.ChargePlayer(
        patientSource, amount, 'hospital_service', description, metadata,
        tostring(billing.DepartmentAccount or 'ambulance'))
    if economyResult.handled == true then
        if economyResult.success == true then return true, economyResult end
        if billing.RequirePayment ~= true then return true, 'unpaid' end
        return false, economyResult.error or 'Pagamento hospitalar recusado.'
    end

    local cardError
    if billing.TryCardFirst == true and GetResourceState('ob_bank') == 'started' then
        local paid, errorMessage = exports.ob_bank:PayWithCard(patientSource, amount, description)
        if paid == true then return true, 'card' end
        cardError = errorMessage
    end
    if billing.AllowCash == true and GetResourceState('ob_inventory') == 'started' then
        if (tonumber(exports.ob_inventory:GetMoney(patientSource, 'money')) or 0) >= amount then
            local paid, errorMessage = exports.ob_inventory:RemoveMoney(patientSource, 'money', amount)
            if paid == true then return true, 'cash' end
            cardError = errorMessage or cardError
        end
    end
    if billing.RequirePayment ~= true then return true, 'unpaid' end
    return false, cardError or 'O paciente nao possui saldo no cartao nem dinheiro em maos.'
end

local function finishMedicalService(emsSource, targetSource, serviceName, service, price, healAmount, revive)
    local hasItem, itemError = verifyServiceItem(emsSource, service)
    if not hasItem then return false, itemError end
    local itemTaken, consumedOrError = takeServiceItem(emsSource, service)
    if not itemTaken then return false, consumedOrError end
    local consumed = consumedOrError == true

    local paid, paymentOrError = chargePatient(targetSource, emsSource, serviceName, price)
    if not paid then
        restoreServiceItem(emsSource, service, consumed)
        return false, paymentOrError
    end

    local ok, medicalError
    if revive then
        ok, medicalError = revivePlayer(targetSource, emsSource, healAmount, false)
    else
        ok, medicalError = healPlayer(targetSource, healAmount)
        if ok then TriggerEvent('ob_health:server:clearInjuries', targetSource) end
    end
    if not ok then
        restoreServiceItem(emsSource, service, consumed)
        return false, medicalError
    end

    local billing = type(emsSettings().Billing) == 'table' and emsSettings().Billing or {}
    if billing.Enabled == true and price > 0 and paymentOrError ~= 'unpaid' then
        notify(targetSource, ('Atendimento hospitalar cobrado: %s.'):format(OR.FormatMoney(price)), 'inform')
    end
    return true, revive and 'Paciente reanimado com sucesso.' or 'Atendimento concluido com sucesso.'
end

OR.Callback.register('emsPatient', function(source, targetSource)
    local target, errorMessage = validEmsPatient(source, targetSource)
    if not target then return false, errorMessage end
    return true, patientSummary(target)
end)

OR.Callback.register('emsExamine', function(source, targetSource)
    local target, errorMessage = validEmsPatient(source, targetSource)
    if not target then return false, errorMessage end
    local summary = patientSummary(target)
    if not summary then return false, 'Paciente indisponivel.' end
    -- Dados exclusivos do exame: estoque do medico, sem alterar o estado do paciente.
    summary.requiredMaterials = {}
    local causes = (ORHealthConfig.Injuries or {}).Causes or {}
    for region, injury in pairs(summary.injuries or {}) do
        local cause = causes[injury.cause] or causes.generic or { item = 'bandage' }
        local item = tostring(cause.item or 'bandage')
        local available = GetResourceState('ob_inventory') == 'started'
            and (tonumber(exports.ob_inventory:GetItemCount(source, item)) or 0) or 0
        summary.requiredMaterials[region] = { item = item, amount = 1, available = available }
    end
    return true, summary
end)

OR.Callback.register('emsBeginTreatment', function(source, targetSource)
    local target, errorMessage = validEmsPatient(source, targetSource)
    if not target then return false, errorMessage end
    if isDowned(target) then return false, 'O paciente precisa ser reanimado primeiro.' end
    local service = type(emsSettings().Treatment) == 'table' and emsSettings().Treatment or {}
    local hasItem, itemError = verifyServiceItem(source, service)
    if not hasItem then return false, itemError end
    local duration = math.max(1000, math.floor(tonumber(service.Duration) or 8000))
    pendingTreatments[source] = {
        target = target,
        readyAt = GetGameTimer() + duration - 500,
        expiresAt = GetGameTimer() + duration + 10000,
    }
    return true, duration
end)

OR.Callback.register('emsFinishTreatment', function(source, targetSource)
    local attempt = pendingTreatments[source]
    pendingTreatments[source] = nil
    if not attempt or attempt.target ~= tonumber(targetSource) or GetGameTimer() < attempt.readyAt
        or GetGameTimer() > attempt.expiresAt then return false, 'Procedimento medico invalido ou interrompido.' end
    local target, errorMessage = validEmsPatient(source, targetSource)
    if not target then return false, errorMessage end
    if isDowned(target) then return false, 'O paciente ficou incapacitado e precisa ser reanimado.' end
    local settings = emsSettings()
    local service = type(settings.Treatment) == 'table' and settings.Treatment or {}
    local billing = type(settings.Billing) == 'table' and settings.Billing or {}
    return finishMedicalService(source, target, 'tratamento', service,
        math.max(0, math.floor(tonumber(billing.TreatmentPrice) or 0)),
        math.max(1, tonumber(service.Health) or ORHealthConfig.MaxHealth), false)
end)

OR.Callback.register('emsCancelTreatment', function(source)
    pendingTreatments[source] = nil
    return true
end)

OR.Callback.register('emsBeginRevive', function(source, targetSource)
    local target, errorMessage = validEmsPatient(source, targetSource)
    if not target then return false, errorMessage end
    if not isDowned(target) then return false, 'Esse paciente nao esta incapacitado.' end
    if pendingRevives[target] then return false, 'Outro atendimento ja esta em andamento.' end
    local service = type(emsSettings().Revive) == 'table' and emsSettings().Revive or {}
    local hasItem, itemError = verifyServiceItem(source, service)
    if not hasItem then return false, itemError end
    local duration = math.max(1000, math.floor(tonumber(service.Duration) or 15000))
    pendingRevives[target] = {
        ems = source,
        readyAt = GetGameTimer() + duration - 500,
        expiresAt = GetGameTimer() + duration + 10000,
    }
    TriggerClientEvent('ob_health:client:medicalPose', target, true, service.PatientAnimation)
    return true, duration
end)

OR.Callback.register('emsFinishRevive', function(source, targetSource)
    local target = tonumber(targetSource)
    local attempt = target and pendingRevives[target]
    if attempt and attempt.ems == source then pendingRevives[target] = nil end
    if target and validSource(target) then TriggerClientEvent('ob_health:client:medicalPose', target, false) end
    if not attempt or attempt.ems ~= source or GetGameTimer() < attempt.readyAt
        or GetGameTimer() > attempt.expiresAt then return false, 'Reanimacao invalida ou interrompida.' end
    local validTarget, errorMessage = validEmsPatient(source, target)
    if not validTarget then return false, errorMessage end
    if not isDowned(validTarget) then return false, 'O paciente ja foi reanimado.' end
    local settings = emsSettings()
    local service = type(settings.Revive) == 'table' and settings.Revive or {}
    local billing = type(settings.Billing) == 'table' and settings.Billing or {}
    return finishMedicalService(source, validTarget, 'reanimacao', service,
        math.max(0, math.floor(tonumber(billing.RevivePrice) or 0)),
        math.max(101, tonumber(service.Health) or ORHealthConfig.ReviveHealth), true)
end)

OR.Callback.register('emsCancelRevive', function(source, targetSource)
    local target = tonumber(targetSource)
    local attempt = target and pendingRevives[target]
    if not attempt or attempt.ems ~= source then return false end
    pendingRevives[target] = nil
    TriggerClientEvent('ob_health:client:medicalPose', target, false)
    return true
end)

releaseCarriedPlayer = function(targetSource)
    targetSource = tonumber(targetSource)
    local carrierSource = targetSource and carriedPlayers[targetSource]
    if not carrierSource then return false end
    carriedPlayers[targetSource] = nil
    if carryingPlayers[carrierSource] == targetSource then carryingPlayers[carrierSource] = nil end
    local player = Player(targetSource)
    if player then player.state:set('ob:carriedBy', nil, true) end
    TriggerClientEvent('ob_health:client:setCarried', targetSource, false)
    TriggerClientEvent('ob_health:client:setCarrier', carrierSource, false)
    return true
end

OR.Callback.register('emsToggleCarry', function(source, targetSource)
    local target, errorMessage = validEmsPatient(source, targetSource)
    if not target then return false, errorMessage end
    if carriedPlayers[target] == source then
        releaseCarriedPlayer(target)
        return true, 'Paciente colocado no chao.', false
    end
    if carriedPlayers[target] then return false, 'Esse paciente ja esta sendo transportado.' end
    if carryingPlayers[source] then return false, 'Voce ja esta transportando outra pessoa.' end
    local settings = emsSettings()
    if settings.OnlyTransportDowned ~= false and not isDowned(target) then
        return false, 'Somente pacientes incapacitados podem ser carregados.'
    end
    local targetPed = GetPlayerPed(target)
    if targetPed <= 0 or GetVehiclePedIsIn(targetPed, false) ~= 0 then
        return false, 'Retire o paciente do veiculo antes de carrega-lo.'
    end
    carriedPlayers[target], carryingPlayers[source] = source, target
    Player(target).state:set('ob:carriedBy', source, true)
    TriggerClientEvent('ob_health:client:setCarrier', source, true, target)
    TriggerClientEvent('ob_health:client:setCarried', target, true, source)
    return true, 'Paciente sendo transportado. Pressione X para coloca-lo no chao.', true
end)

OR.Callback.register('emsPutInVehicle', function(source, targetSource, netId, seat)
    local target, errorMessage = validEmsPatient(source, targetSource)
    if not target then return false, errorMessage end
    local settings = emsSettings()
    if settings.OnlyTransportDowned ~= false and not isDowned(target) then
        return false, 'Somente pacientes incapacitados podem ser transportados.'
    end
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    seat = math.floor(tonumber(seat) or -1)
    if vehicle == 0 or not DoesEntityExist(vehicle) or seat < 0 or seat > 15 then
        return false, 'Veiculo ou assento invalido.'
    end
    local targetPed = GetPlayerPed(target)
    if targetPed <= 0 or #(GetEntityCoords(targetPed) - GetEntityCoords(vehicle)) > (tonumber(settings.VehicleDistance) or 7.0) then
        return false, 'Aproxime o paciente do veiculo.'
    end
    if GetPedInVehicleSeat(vehicle, seat) ~= 0 then return false, 'Esse assento esta ocupado.' end
    releaseCarriedPlayer(target)
    TriggerEvent('ob_health:server:beforePatientVehicle', target)
    TriggerClientEvent('ob_health:client:medicalVehicle', target, true, tonumber(netId), seat)
    return true, 'Paciente colocado no veiculo.'
end)

OR.Callback.register('emsRemoveFromVehicle', function(source, targetSource)
    local target, errorMessage = validEmsPatient(source, targetSource)
    if not target then return false, errorMessage end
    local targetPed = GetPlayerPed(target)
    local vehicle = targetPed > 0 and GetVehiclePedIsIn(targetPed, false) or 0
    if vehicle == 0 or not DoesEntityExist(vehicle) then return false, 'O paciente nao esta em um veiculo.' end
    TriggerClientEvent('ob_health:client:medicalVehicle', target, false, NetworkGetNetworkIdFromEntity(vehicle))
    return true, 'Paciente retirado do veiculo.'
end)

RegisterNetEvent('ob_health:server:stopCarry', function()
    local carrierSource = validSource(source)
    local targetSource = carrierSource and carryingPlayers[carrierSource]
    if targetSource then releaseCarriedPlayer(targetSource) end
end)

AddEventHandler('playerDropped', function()
    local playerSource = tonumber(source)
    downedPlayers[playerSource] = nil
    pendingTreatments[playerSource] = nil
    local carriedTarget = carryingPlayers[playerSource]
    if carriedTarget then releaseCarriedPlayer(carriedTarget) end
    if carriedPlayers[playerSource] then releaseCarriedPlayer(playerSource) end
    for targetSource, attempt in pairs(pendingRevives) do
        if targetSource == playerSource or attempt.ems == playerSource then
            pendingRevives[targetSource] = nil
            if targetSource ~= playerSource then TriggerClientEvent('ob_health:client:medicalPose', targetSource, false) end
        end
    end
end)

CreateThread(function()
    -- Ao reiniciar somente o ob_health, o estado da sessao continua no core.
    -- Reconstituimos a pequena tabela local sem resetar a contagem de morte.
    Wait(250)
    for _, playerSource in ipairs(GetPlayers()) do
        playerSource = tonumber(playerSource)
        local state = playerSource and Player(playerSource) and Player(playerSource).state
        if state and state['or:downed'] == true then
            downedPlayers[playerSource] = {
                startedAt = tonumber(state['or:downedAt']) or os.time(),
                expiresAt = tonumber(state['or:downedUntil']) or os.time(),
                death = cleanDeathInfo(state['or:deathInfo']),
            }
        end
        if state then state:set('ob:carriedBy', nil, true) end
    end
end)

CreateThread(function()
    while true do
        Wait(10000)
        local now = GetGameTimer()
        for emsSource, attempt in pairs(pendingTreatments) do
            if not validSource(emsSource) or now > (tonumber(attempt.expiresAt) or 0) then
                pendingTreatments[emsSource] = nil
            end
        end
        for targetSource, attempt in pairs(pendingRevives) do
            if not validSource(targetSource) or not validSource(attempt.ems)
                or now > (tonumber(attempt.expiresAt) or 0) then
                pendingRevives[targetSource] = nil
                if validSource(targetSource) then TriggerClientEvent('ob_health:client:medicalPose', targetSource, false) end
            end
        end
    end
end)

exports('IsDowned', isDowned)
exports('RevivePlayer', revivePlayer)
-- Restauracao administrativa: revive de RP continua preservando as lesoes.
exports('RestorePlayer', function(playerSource, healerSource)
    playerSource = validSource(playerSource)
    if not playerSource then return false, 'Jogador indisponivel.' end
    local cleared = exports.ob_health:ClearInjuries(playerSource)
    if cleared ~= true then return false, 'Nao foi possivel limpar as lesoes.' end
    return revivePlayer(playerSource, healerSource, ORHealthConfig.ReviveHealth, true)
end)
exports('HealPlayer', healPlayer)
exports('HasEmsAccess', hasEmsAccess)

-- Atalho do inventario para os mesmos exames/tratamentos usados pelo target.
exports('BeginMedicalEquipmentUse', function(playerSource, itemName)
    playerSource = validSource(playerSource)
    if not playerSource or not hasEmsAccess(playerSource) or isDowned(playerSource) then
        return false, 'Somente EMS consciente e em servico pode usar esse equipamento.'
    end
    local supported = itemName == 'emstablet'
    for _, cause in pairs((ORHealthConfig.Injuries or {}).Causes or {}) do
        if cause.item == itemName then supported = true; break end
    end
    if not supported then return false, 'Equipamento medico nao configurado.' end
    if GetResourceState('ob_inventory') ~= 'started'
        or (tonumber(exports.ob_inventory:GetItemCount(playerSource, itemName)) or 0) < 1 then
        return false, 'Voce precisa ter o material medico no inventario.'
    end
    if not OR.Security.rateLimit(playerSource, 'health:equipment', 2, 3000) then
        return false, 'Aguarde antes de usar o equipamento novamente.'
    end
    local ped = GetPlayerPed(playerSource)
    if not ped or ped == 0 then return false, 'Posicao indisponivel.' end
    local position = GetEntityCoords(ped)
    local closest, closestDistance = nil, tonumber(emsSettings().InteractionDistance) or 3.0
    local bucket = GetPlayerRoutingBucket(playerSource)
    for _, candidate in ipairs(GetPlayers()) do
        local target = validSource(candidate)
        if target and target ~= playerSource and GetPlayerRoutingBucket(target) == bucket then
            local targetPed = GetPlayerPed(target)
            if targetPed and targetPed ~= 0 then
                local distance = #(GetEntityCoords(targetPed) - position)
                if distance <= closestDistance then closest, closestDistance = target, distance end
            end
        end
    end
    if not closest then return false, 'Aproxime-se do paciente para usar o equipamento.' end
    local target, errorMessage = validEmsPatient(playerSource, closest)
    if not target then return false, errorMessage end
    TriggerClientEvent('ob_health:client:useMedicalEquipment', playerSource, target, itemName == 'emstablet' and 'panel' or 'examine')
    return true, 'Atendimento iniciado.'
end)
exports('ValidateEmsPatient', validEmsPatient)
exports('ChargePatient', chargePatient)
exports('GetDownedInfo', function(playerSource)
    local state = downedPlayers[tonumber(playerSource)]
    return state and { startedAt = state.startedAt, expiresAt = state.expiresAt, death = state.death } or nil
end)
-- O futuro ob_inventory deve chamar este export e remover o item somente se
-- receber true. Assim falhas de distancia/area nao consomem o item.
exports('UseMedicalItem', useMedicalItem)
