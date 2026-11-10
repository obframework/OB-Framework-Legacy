local groups, memberGroup, invites = {}, {}, {}
local assignments, offers = {}, {}
local slotReservations = { truck = {}, trailer = {} }
local offerGeneration, offerSerial, nextOfferRefresh = 0, 0, 0
local databaseReady = false

local skillNames = { 'distance', 'cargo', 'care', 'efficiency' }

local function userId(source) return exports.ob_core:GetUserId(source) end
local function playerExists(source) return source and GetPlayerName(source) ~= nil and userId(source) ~= nil end
local function notify(source, message, kind)
    TriggerClientEvent('ob_notification:client:notify', source, message, kind or 'info')
end

local function playerNear(source, coords, radius)
    local ped = GetPlayerPed(source)
    return ped ~= 0 and #(GetEntityCoords(ped) - coords) <= radius
end

local function cargoIntegrity(bodyHealth)
    bodyHealth = tonumber(bodyHealth) or 0.0
    if bodyHealth <= Trucker.payment.destroyedBodyHealth then return 0.0 end
    local rawIntegrity = math.max(0.0, math.min(100.0, bodyHealth / 10.0))
    local damage = (100.0 - rawIntegrity) * (Trucker.payment.damageToIntegrity or 0.20)
    return math.max(0.0, math.min(100.0, 100.0 - damage))
end

local function characterIdColumnType()
    local deadline = GetGameTimer() + 30000
    repeat
        local columnType = exports.ob_core:GetCharacterIdColumnType()
        if columnType then return columnType end
        Wait(100)
    until GetGameTimer() >= deadline
end

local function levelFromXp(xp)
    return math.min(math.floor((tonumber(xp) or 0) / Trucker.progress.levelStep) + 1, Trucker.progress.maxLevel)
end

local function ensureProgress(source)
    local id = tonumber(userId(source))
    if not databaseReady or not id then return nil end
    OR.Database.update.await([[INSERT IGNORE INTO ob_trucker_progress
        (user_id, xp, level, deliveries_completed, total_earned, distance_skill, cargo_skill, care_skill, efficiency_skill)
        VALUES (?, 0, 1, 0, 0, 0, 0, 0, 0)]], { id })
    local row = OR.Database.single.await('SELECT * FROM ob_trucker_progress WHERE user_id = ?', { id })
    if row then
        local expected = levelFromXp(row.xp)
        if tonumber(row.level) ~= expected then
            row.level = expected
            OR.Database.update.await('UPDATE ob_trucker_progress SET level = ? WHERE user_id = ?', { expected, id })
        end
    end
    return row
end

local function skillValue(row, name)
    return math.max(0, math.min(Trucker.progress.skillMax, tonumber(row and row[name .. '_skill']) or 0))
end

local function progressPayload(row)
    row = row or {}
    local level = levelFromXp(row.xp)
    local spent = 0
    local skills = {}
    for _, name in ipairs(skillNames) do
        local points = skillValue(row, name)
        spent = spent + points
        skills[name] = points
    end
    local earned = math.min((level - 1) * Trucker.progress.pointsPerLevel, Trucker.progress.skillMax * #skillNames)
    return {
        level = level,
        maxLevel = Trucker.progress.maxLevel,
        xp = tonumber(row.xp) or 0,
        xpInLevel = level >= Trucker.progress.maxLevel and Trucker.progress.levelStep
            or (tonumber(row.xp) or 0) - ((level - 1) * Trucker.progress.levelStep),
        xpRequired = Trucker.progress.levelStep,
        deliveries = tonumber(row.deliveries_completed) or 0,
        totalEarned = tonumber(row.total_earned) or 0,
        availablePoints = math.max(0, earned - spent),
        skills = skills,
        skillMax = Trucker.progress.skillMax,
    }
end

local function getLeader(source) return memberGroup[source] or source end

local function getGroup(source, create)
    local leader = getLeader(source)
    local group = groups[leader]
    if not group and create then
        group = { leader = source, members = { [source] = true } }
        groups[source], memberGroup[source] = group, source
        leader = source
    end
    return leader, group
end

local function groupSources(leader)
    local result, group = {}, groups[leader]
    if not group then return playerExists(leader) and { leader } or {} end
    for source in pairs(group.members) do
        if playerExists(source) then
            result[#result + 1] = source
        else
            group.members[source], memberGroup[source] = nil, nil
        end
    end
    table.sort(result)
    return result
end

local function groupSize(leader) return #groupSources(leader) end

local function groupPayload(source)
    local leader, group = getGroup(source, false)
    if not group then leader = source end
    local members = {}
    for _, member in ipairs(groupSources(leader)) do
        members[#members + 1] = {
            id = member,
            name = GetPlayerName(member) or ('ID %s'):format(member),
            leader = member == leader,
        }
    end
    return {
        leader = leader,
        isLeader = source == leader,
        maxMembers = Trucker.group.maxMembers,
        members = members,
    }
end

local function broadcastGroup(leader)
    for _, member in ipairs(groupSources(leader)) do
        TriggerClientEvent('orbis-truckerjob:client:groupUpdated', member, groupPayload(member))
    end
end

local function distanceLimitForRow(row)
    local skill = skillValue(row, 'distance')
    return tonumber(Trucker.skills.distance.kilometers[skill]) or 2.0
end

local function groupAccess(leader)
    local members = groupSources(leader)
    local total, leaderCargo = 0.0, 0
    for _, member in ipairs(members) do
        local row = ensureProgress(member)
        total = total + distanceLimitForRow(row)
        if member == leader then leaderCargo = skillValue(row, 'cargo') end
    end
    return #members > 0 and total / #members or 2.0, leaderCargo
end

local function displayName(row)
    local name = ((row and row.firstname or '') .. ' ' .. (row and row.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
    return name ~= '' and name or ('ID %s'):format(row and row.user_id or '?')
end

local function leaderboard(source, ownRow)
    local xpRows = OR.Database.query.await([[SELECT p.user_id,p.xp,p.deliveries_completed,c.firstname,c.lastname
        FROM ob_trucker_progress p LEFT JOIN ob_characters c ON c.user_id=p.user_id
        ORDER BY p.xp DESC,p.deliveries_completed DESC,p.user_id ASC LIMIT 25]]) or {}
    local deliveryRows = OR.Database.query.await([[SELECT p.user_id,p.xp,p.deliveries_completed,c.firstname,c.lastname
        FROM ob_trucker_progress p LEFT JOIN ob_characters c ON c.user_id=p.user_id
        ORDER BY p.deliveries_completed DESC,p.xp DESC,p.user_id ASC LIMIT 25]]) or {}
    local function build(rows)
        local list = {}
        for rank, row in ipairs(rows) do
            list[#list + 1] = { rank = rank, name = displayName(row), xp = tonumber(row.xp) or 0,
                deliveries = tonumber(row.deliveries_completed) or 0 }
        end
        return list
    end
    local id, xp, deliveries = tonumber(userId(source)), tonumber(ownRow.xp) or 0, tonumber(ownRow.deliveries_completed) or 0
    local xpCount = OR.Database.single.await([[SELECT COUNT(*) total FROM ob_trucker_progress
        WHERE xp>? OR (xp=? AND deliveries_completed>?) OR (xp=? AND deliveries_completed=? AND user_id<?)]],
        { xp, xp, deliveries, xp, deliveries, id })
    local deliveryCount = OR.Database.single.await([[SELECT COUNT(*) total FROM ob_trucker_progress
        WHERE deliveries_completed>? OR (deliveries_completed=? AND xp>?) OR (deliveries_completed=? AND xp=? AND user_id<?)]],
        { deliveries, deliveries, xp, deliveries, xp, id })
    return {
        xp = { list = build(xpRows), myRank = (tonumber(xpCount and xpCount.total) or 0) + 1, myValue = xp },
        deliveries = { list = build(deliveryRows), myRank = (tonumber(deliveryCount and deliveryCount.total) or 0) + 1, myValue = deliveries },
    }
end

local function weightedChoice(list)
    local total = 0
    for _, item in ipairs(list) do total = total + math.max(0, tonumber(item.chance) or 0) end
    if total <= 0 then return list[math.random(#list)] end
    local pick = math.random() * total
    for _, item in ipairs(list) do
        pick = pick - math.max(0, tonumber(item.chance) or 0)
        if pick <= 0 then return item end
    end
    return list[#list]
end

local function flattenDestinations()
    local result = {}
    for _, groupId in ipairs(Trucker.distanceGroupOrder) do
        local group = Trucker.distanceGroups[groupId]
        for _, location in ipairs(group.locations or {}) do
            result[#result + 1] = { group = groupId, groupLabel = group.label, label = location.label, coords = location.coords }
        end
    end
    return result
end

local function baseCargoTypes()
    local result = {}
    for _, cargo in ipairs(Trucker.cargoTypes) do
        if (tonumber(cargo.requiredCargo) or 0) <= 0 then result[#result + 1] = cargo end
    end
    return #result > 0 and result or Trucker.cargoTypes
end

local function destinationForGroup(groupId, initialRangeOnly)
    local group = Trucker.distanceGroups[groupId]
    local candidates = {}
    for _, location in ipairs(group.locations or {}) do
        local distanceKm = #(location.coords - Trucker.depot.cargoCenter) / 1000.0 * Trucker.offers.roadDistanceFactor
        if not initialRangeOnly or distanceKm <= (Trucker.skills.distance.kilometers[0] or 2.0) then
            candidates[#candidates + 1] = location
        end
    end
    if #candidates == 0 then candidates = group.locations end
    local location = candidates[math.random(#candidates)]
    return { group = groupId, groupLabel = group.label, label = location.label, coords = location.coords }
end

local function appendOffer(destination, cargoPool)
    local cargo, truck = weightedChoice(cargoPool or Trucker.cargoTypes), weightedChoice(Trucker.trucks)
    local straightKm = #(destination.coords - Trucker.depot.cargoCenter) / 1000.0
    local distanceKm = math.max(0.3, straightKm * Trucker.offers.roadDistanceFactor)
    local basePay = math.max(Trucker.offers.minimumPay,
        math.floor(distanceKm * Trucker.offers.payPerKm * cargo.multiplier))
    local baseXp = math.max(Trucker.offers.minimumXp,
        math.floor(distanceKm * Trucker.offers.xpPerKm * cargo.multiplier))
    offerSerial = offerSerial + 1
    offers[#offers + 1] = {
        id = ('%s-%04d'):format(offerGeneration, offerSerial),
        cargoId = cargo.id,
        cargoModel = cargo.model,
        cargoLabel = cargo.label,
        requiredCargo = cargo.requiredCargo,
        cargoMultiplier = cargo.multiplier,
        truckModel = truck.model,
        truckLabel = truck.label,
        destinationLabel = destination.label,
        distanceGroup = destination.group,
        distanceGroupLabel = destination.groupLabel,
        destination = destination.coords,
        distanceKm = math.floor(distanceKm * 100 + 0.5) / 100,
        basePay = basePay,
        baseXp = baseXp,
        displayOrder = math.random(1, 2147483647),
    }
end

local function sortOffers()
    local groupOrder = {}
    for index, groupId in ipairs(Trucker.distanceGroupOrder) do groupOrder[groupId] = index end
    table.sort(offers, function(a, b)
        local aGroup = groupOrder[a.distanceGroup] or 999
        local bGroup = groupOrder[b.distanceGroup] or 999
        if aGroup ~= bGroup then return aGroup < bGroup end
        if a.displayOrder ~= b.displayOrder then return a.displayOrder < b.displayOrder end
        return a.id < b.id
    end)
end

local function generateOffers()
    local destinations, unrestrictedCargo = flattenDestinations(), baseCargoTypes()
    offers, offerGeneration, offerSerial = {}, os.time(), 0
    local guaranteed = math.max(0, tonumber(Trucker.offers.minimumPerDistanceGroup) or 0)
    for _, groupId in ipairs(Trucker.distanceGroupOrder) do
        for _ = 1, guaranteed do
            if #offers >= Trucker.offers.count then break end
            appendOffer(destinationForGroup(groupId, groupId == 'short'), unrestrictedCargo)
        end
    end
    while #offers < Trucker.offers.count do appendOffer(destinations[math.random(#destinations)]) end
    sortOffers()
    nextOfferRefresh = os.time() + Trucker.offers.refreshSeconds
    TriggerClientEvent('orbis-truckerjob:client:offersUpdated', -1, nextOfferRefresh)
end

local function replaceAcceptedOffer(selected)
    local guaranteed = math.max(0, tonumber(Trucker.offers.minimumPerDistanceGroup) or 0)
    local unrestricted = 0
    for _, offer in ipairs(offers) do
        if offer.distanceGroup == selected.distanceGroup and (tonumber(offer.requiredCargo) or 0) <= 0 then
            unrestricted = unrestricted + 1
        end
    end
    local needsUnrestricted = unrestricted < guaranteed
    appendOffer(destinationForGroup(selected.distanceGroup, needsUnrestricted and selected.distanceGroup == 'short'),
        needsUnrestricted and baseCargoTypes() or nil)
    sortOffers()
    TriggerClientEvent('orbis-truckerjob:client:offersUpdated', -1, nextOfferRefresh)
end

local function publicOffer(offer, maxDistance, cargoSkill)
    local available, reason = true, nil
    if offer.distanceKm > maxDistance + 0.001 then
        available, reason = false, ('Distancia do grupo: %.2f km'):format(maxDistance)
    elseif offer.requiredCargo > cargoSkill then
        available, reason = false, ('Licenca de carga nivel %d'):format(offer.requiredCargo)
    end
    return {
        id = offer.id, cargoLabel = offer.cargoLabel, cargoModel = offer.cargoModel,
        truckLabel = offer.truckLabel, truckModel = offer.truckModel,
        destinationLabel = offer.destinationLabel, distanceGroup = offer.distanceGroup,
        distanceGroupLabel = offer.distanceGroupLabel, distanceKm = offer.distanceKm,
        basePay = offer.basePay, baseXp = offer.baseXp, requiredCargo = offer.requiredCargo,
        available = available, unavailableReason = reason,
    }
end

local function entityFromNet(netId)
    netId = tonumber(netId)
    if not netId or netId <= 0 then return 0 end
    -- NetworkGetEntityFromNetworkId emite warning no Legacy quando o NetID ja
    -- foi removido. Procurar apenas entre veiculos existentes evita consultar
    -- diretamente um objeto de rede vencido durante limpeza, quit ou crash.
    for _, vehicle in ipairs(GetAllVehicles()) do
        if DoesEntityExist(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) == netId then return vehicle end
    end
    return 0
end

local function slotConfig(kind)
    if kind == 'truck' then return Trucker.depot.truckSpawns, Trucker.depot.slotSafety.truck end
    return Trucker.depot.trailerSpawns, Trucker.depot.slotSafety.trailer
end

local function slotOccupied(point, safety)
    local heading = math.rad(tonumber(point.w) or 0.0)
    local forwardX, forwardY = -math.sin(heading), math.cos(heading)
    local rightX, rightY = math.cos(heading), math.sin(heading)
    for _, vehicle in ipairs(GetAllVehicles()) do
        if DoesEntityExist(vehicle) then
            local coords = GetEntityCoords(vehicle)
            local dx, dy, dz = coords.x - point.x, coords.y - point.y, math.abs(coords.z - point.z)
            local longitudinal = math.abs(dx * forwardX + dy * forwardY)
            local lateral = math.abs(dx * rightX + dy * rightY)
            if longitudinal <= safety.length * 0.5 and lateral <= safety.width * 0.5 and dz <= safety.height then
                return true
            end
        end
    end
    return false
end

local function validReservation(kind, index, owner)
    local reservation = slotReservations[kind][index]
    if not reservation then return false end
    if reservation.expires <= GetGameTimer() then
        slotReservations[kind][index] = nil
        return false
    end
    return reservation.owner == owner
end

local function releaseDriverReservations(driver)
    if not driver then return end
    local owner = driver.reservationOwner
    for _, kind in ipairs({ 'truck', 'trailer' }) do
        local field = kind == 'truck' and 'reservedTruckSlot' or 'reservedTrailerSlot'
        local index = driver[field]
        local reservation = index and slotReservations[kind][index]
        if reservation and reservation.owner == owner then slotReservations[kind][index] = nil end
        driver[field] = nil
    end
    driver.reservationOwner = nil
end

local function reserveSlot(kind, owner)
    local list, safety = slotConfig(kind)
    for index, point in ipairs(list) do
        local reservation = slotReservations[kind][index]
        if reservation and reservation.expires <= GetGameTimer() then
            slotReservations[kind][index] = nil
            reservation = nil
        end
        if not reservation and not slotOccupied(point, safety) then
            slotReservations[kind][index] = {
                owner = owner,
                expires = GetGameTimer() + Trucker.depot.slotSafety.reservationMs,
            }
            return point, index
        end
    end
end

local function reserveSpawnPair(source, driver)
    local truckList, truckSafety = slotConfig('truck')
    local trailerList, trailerSafety = slotConfig('trailer')
    if driver.reservedTruckSlot and driver.reservedTrailerSlot
        and validReservation('truck', driver.reservedTruckSlot, source)
        and validReservation('trailer', driver.reservedTrailerSlot, source)
        and not slotOccupied(truckList[driver.reservedTruckSlot], truckSafety)
        and not slotOccupied(trailerList[driver.reservedTrailerSlot], trailerSafety) then
        return truckList[driver.reservedTruckSlot], trailerList[driver.reservedTrailerSlot]
    end

    releaseDriverReservations(driver)
    local truckPoint, truckIndex = reserveSlot('truck', source)
    if not truckPoint then return nil end
    driver.reservationOwner = source
    driver.reservedTruckSlot = truckIndex
    local trailerPoint, trailerIndex = reserveSlot('trailer', source)
    if not trailerPoint then
        releaseDriverReservations(driver)
        return nil
    end
    driver.reservedTrailerSlot = trailerIndex
    return truckPoint, trailerPoint
end

local function plainCoords(coords)
    return coords and { x = coords.x, y = coords.y, z = coords.z } or nil
end

local function assignmentPayload(leader, source)
    local assignment = assignments[leader]
    if not assignment then return false end
    local driver = assignment.drivers[source]
    if not driver then return false end
    local offer = assignment.offer
    return {
        active = driver.state ~= 'paid' and driver.state ~= 'abandoned',
        state = driver.state,
        leader = leader,
        memberCount = assignment.memberCount,
        truckNetId = driver.truckNetId,
        trailerNetId = driver.trailerNetId,
        integrity = driver.integrity,
        cargoLabel = offer.cargoLabel,
        cargoModel = offer.cargoModel,
        truckLabel = offer.truckLabel,
        truckModel = offer.truckModel,
        destinationLabel = offer.destinationLabel,
        destination = plainCoords(offer.destination),
        distanceKm = offer.distanceKm,
        basePay = offer.basePay,
        baseXp = offer.baseXp,
    }
end

local function broadcastAssignment(leader)
    local assignment = assignments[leader]
    local recipients = assignment and assignment.members or groupSources(leader)
    for _, member in ipairs(recipients) do
        if playerExists(member) then
            TriggerClientEvent('orbis-truckerjob:client:assignment', member, assignmentPayload(leader, member))
        end
    end
end

local function ensureEntityDeleted(entity, delay)
    if not entity or entity == 0 then return end
    CreateThread(function()
        if delay and delay > 0 then Wait(delay) end
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end)
end

local function deleteTrailer(driver)
    local trailer = driver and entityFromNet(driver.trailerNetId)
    if trailer ~= 0 then
        DeleteEntity(trailer)
        ensureEntityDeleted(trailer, 0)
    end
    if driver then driver.trailerNetId = nil end
end

local function deleteTruck(source, driver, detached)
    if not driver or not driver.truckNetId then return end
    local vehicle = entityFromNet(driver.truckNetId)
    if detached then
        TriggerEvent('ob_core:server:deleteTemporaryVehicleDetached', source, driver.truckNetId)
        -- Da um instante para o sistema de chaves limpar a chave temporaria;
        -- depois garante a remocao mesmo se o jogador caiu durante a migracao.
        ensureEntityDeleted(vehicle, 250)
    else
        if not exports.ob_core:DeleteTemporaryVehicle(source, driver.truckNetId) and vehicle ~= 0 then DeleteEntity(vehicle) end
        ensureEntityDeleted(vehicle, 0)
    end
    driver.truckNetId = nil
end

local function cleanupAssignment(leader, detached)
    local assignment = assignments[leader]
    if not assignment then return end
    for member, driver in pairs(assignment.drivers) do
        releaseDriverReservations(driver)
        deleteTrailer(driver)
        deleteTruck(member, driver, detached)
    end
    assignments[leader] = nil
end

local function makePanelData(source)
    local row = ensureProgress(source)
    if not row then return nil, 'Banco de progresso indisponivel.' end
    local leader = getLeader(source)
    local maxDistance, cargoSkill = groupAccess(leader)
    local list = {}
    for _, offer in ipairs(offers) do list[#list + 1] = publicOffer(offer, maxDistance, cargoSkill) end
    return {
        progress = progressPayload(row),
        group = groupPayload(source),
        leaderboard = leaderboard(source, row),
        offers = list,
        offersRefreshAt = nextOfferRefresh,
        access = { maxDistance = math.floor(maxDistance * 100 + 0.5) / 100, cargoSkill = cargoSkill },
        assignment = assignmentPayload(leader, source),
        skills = Trucker.skills,
        tutorial = Trucker.tutorial,
    }
end

OR.Callback.register('orbis-truckerjob:server:getPanelData', makePanelData)

OR.Callback.register('orbis-truckerjob:server:getStatus', function(source)
    local leader = getLeader(source)
    return assignmentPayload(leader, source), groupPayload(source)
end)

OR.Callback.register('orbis-truckerjob:server:allocateSkill', function(source, name)
    if not OR.Security.rateLimit(source, 'trucker:allocate_skill', 2, 1500) then return false, 'Aguarde um instante.' end
    if not playerNear(source, Trucker.npc.coords.xyz, 15.0) then return false, 'Aproxime-se do encarregado.' end
    if not Trucker.skills[name] then return false, 'Habilidade invalida.' end
    local leader = getLeader(source)
    if assignments[leader] then return false, 'Distribua pontos fora de uma entrega.' end
    local row = ensureProgress(source)
    local progress = progressPayload(row)
    if progress.availablePoints < 1 then return false, 'Voce nao possui pontos disponiveis.' end
    if skillValue(row, name) >= Trucker.progress.skillMax then return false, 'Essa habilidade ja esta no maximo.' end
    OR.Database.update.await(('UPDATE ob_trucker_progress SET %s_skill=%s_skill+1 WHERE user_id=?'):format(name, name), { userId(source) })
    return true, makePanelData(source)
end)

OR.Callback.register('orbis-truckerjob:server:invite', function(source, target)
    target = tonumber(target)
    local leader, group = getGroup(source, true)
    if source ~= leader then return false, 'Somente o lider pode convidar.' end
    if assignments[leader] then return false, 'O grupo nao pode mudar durante uma entrega.' end
    if not playerExists(target) or target == source or memberGroup[target] then return false, 'Pessoa indisponivel.' end
    if groupSize(leader) >= Trucker.group.maxMembers then return false, 'O grupo esta cheio.' end
    local sourcePed, targetPed = GetPlayerPed(source), GetPlayerPed(target)
    if sourcePed == 0 or targetPed == 0 or #(GetEntityCoords(sourcePed) - GetEntityCoords(targetPed)) > Trucker.group.inviteDistance then
        return false, 'A pessoa precisa estar proxima.'
    end
    invites[target] = { leader = leader, expires = os.time() + Trucker.group.inviteSeconds }
    TriggerClientEvent('orbis-truckerjob:client:invite', target, GetPlayerName(source) or ('ID %s'):format(source))
    return true, 'Convite enviado.'
end)

OR.Callback.register('orbis-truckerjob:server:answerInvite', function(source, accept)
    local invite = invites[source]
    invites[source] = nil
    if not invite or invite.expires < os.time() then return false, 'Convite expirado.' end
    local group = groups[invite.leader]
    if not group or assignments[invite.leader] or groupSize(invite.leader) >= Trucker.group.maxMembers then
        return false, 'Grupo indisponivel.'
    end
    if accept ~= true then return true, 'Convite recusado.' end
    if memberGroup[source] then return false, 'Voce ja esta em um grupo.' end
    group.members[source], memberGroup[source] = true, invite.leader
    broadcastGroup(invite.leader)
    return true, 'Voce entrou no grupo.'
end)

OR.Callback.register('orbis-truckerjob:server:leaveGroup', function(source)
    local leader, group = getGroup(source, false)
    if not group then return true end
    if assignments[leader] then return false, 'Cancele ou conclua a entrega antes de sair.' end
    if source == leader then
        for member in pairs(group.members) do memberGroup[member] = nil end
        groups[leader] = nil
        for member in pairs(group.members) do
            if playerExists(member) then TriggerClientEvent('orbis-truckerjob:client:groupUpdated', member, groupPayload(member)) end
        end
    else
        group.members[source], memberGroup[source] = nil, nil
        broadcastGroup(leader)
        TriggerClientEvent('orbis-truckerjob:client:groupUpdated', source, groupPayload(source))
    end
    return true
end)

OR.Callback.register('orbis-truckerjob:server:acceptOffer', function(source, offerId)
    if not OR.Security.rateLimit(source, 'trucker:accept_offer', 1, 2500) then return false, 'Aguarde um instante.' end
    if not playerNear(source, Trucker.npc.coords.xyz, 15.0) then return false, 'Aproxime-se do encarregado.' end
    local leader, group = getGroup(source, true)
    if source ~= leader then return false, 'Somente o lider escolhe a entrega.' end
    if assignments[leader] then return false, 'O grupo ja possui uma entrega.' end
    local selected, selectedIndex
    for index, offer in ipairs(offers) do
        if offer.id == offerId then selected, selectedIndex = offer, index break end
    end
    if not selected then return false, 'Essa oferta acabou de ser escolhida. Selecione outra da lista.' end
    local maxDistance, cargoSkill = groupAccess(leader)
    if selected.distanceKm > maxDistance + 0.001 then return false, 'A distancia excede a media do grupo.' end
    if selected.requiredCargo > cargoSkill then return false, 'O lider nao possui a licenca dessa carga.' end
    -- groupAccess consulta o banco e pode ceder a thread. Confirme a oferta
    -- novamente para impedir que duas equipes consumam o mesmo ID.
    selectedIndex = nil
    for index, offer in ipairs(offers) do
        if offer.id == offerId then selected, selectedIndex = offer, index break end
    end
    if not selectedIndex then return false, 'Essa oferta acabou de ser escolhida. Selecione outra da lista.' end
    local members = groupSources(leader)
    local drivers = {}
    for _, member in ipairs(members) do drivers[member] = { state = 'waiting_truck' } end
    if not reserveSpawnPair(source, drivers[source]) then
        return false, 'Nao ha uma vaga livre para o caminhao e a carga. Aguarde o patio liberar.'
    end
    local assignment = { leader = leader, offer = selected, members = members, memberCount = #members,
        acceptedAt = os.time(), drivers = drivers }
    assignments[leader] = assignment
    table.remove(offers, selectedIndex)
    replaceAcceptedOffer(selected)
    broadcastAssignment(leader)
    return true, 'Entrega aceita. Cada integrante deve retirar seu caminhao.'
end)

OR.Callback.register('orbis-truckerjob:server:spawnTruck', function(source)
    local leader = getLeader(source)
    local assignment = assignments[leader]
    local driver = assignment and assignment.drivers[source]
    if not driver or driver.state ~= 'waiting_truck' or driver.truckNetId then return false, 'Caminhao indisponivel.' end
    if not playerNear(source, Trucker.npc.coords.xyz, 140.0) then return false, 'Aproxime-se da transportadora.' end
    local truckSpawn, trailerSpawn = reserveSpawnPair(source, driver)
    if not truckSpawn or not trailerSpawn then
        return false, 'Aguarde uma vaga livre para o caminhao e a carga.'
    end
    local spawned, data = exports.ob_core:SpawnTemporaryVehicle(source, assignment.offer.truckModel, truckSpawn, {
        platePrefix = 'CARGA', fuel = 100.0, clearRadius = Trucker.depot.truckClearRadius,
        maxDistance = 160.0, serverSetterType = 'automobile',
    })
    if not spawned then
        releaseDriverReservations(driver)
        return false, data or 'Nao foi possivel criar o caminhao.'
    end
    driver.truckNetId = data.netId
    local cargoResult = exports.ob_core:CreateServerVehicle(source, assignment.offer.cargoModel, trailerSpawn, {
        clearRadius = Trucker.depot.trailerClearRadius, maxDistance = 220.0, serverSetterType = 'trailer',
    })
    if not cargoResult or cargoResult.ok ~= true then
        deleteTruck(source, driver, false)
        releaseDriverReservations(driver)
        return false, cargoResult and cargoResult.error or 'Nao foi possivel criar a carga.'
    end
    driver.trailerNetId, driver.state, driver.cargoStartedAt = cargoResult.netId, 'delivering', os.time()
    local vehicle = entityFromNet(data.netId)
    if vehicle ~= 0 then
        local state = Entity(vehicle).state
        state:set('ob:truckerOwner', source, true)
        state:set('ob:locked', true, true)
    end
    local trailer = entityFromNet(cargoResult.netId)
    if trailer ~= 0 then
        local state = Entity(trailer).state
        state:set('ob:truckerCargoOwner', source, true)
        state:set('ob:truckerAssignment', assignment.offer.id, true)
    end
    releaseDriverReservations(driver)
    broadcastAssignment(leader)
    data.trailerNetId = cargoResult.netId
    return true, data
end)

OR.Callback.register('orbis-truckerjob:server:spawnTrailer', function(source)
    local leader = getLeader(source)
    local assignment = assignments[leader]
    local driver = assignment and assignment.drivers[source]
    if not driver or (driver.state ~= 'pickup_cargo' and driver.state ~= 'need_cargo') or driver.trailerNetId then
        return false, 'Carga indisponivel.'
    end
    local truck = entityFromNet(driver.truckNetId)
    if truck == 0 then driver.state = 'waiting_truck'; driver.truckNetId = nil; return false, 'Seu caminhao nao esta disponivel.' end
    if not playerNear(source, Trucker.depot.cargoCenter, 130.0)
        or #(GetEntityCoords(truck) - Trucker.depot.cargoCenter) > 130.0 then
        return false, 'Leve seu caminhao ao patio de cargas.'
    end
    releaseDriverReservations(driver)
    local spawn, slotIndex = reserveSlot('trailer', source)
    driver.reservationOwner = source
    driver.reservedTrailerSlot = slotIndex
    if not spawn then
        releaseDriverReservations(driver)
        return false, 'As vagas de carga estao ocupadas. Aguarde a carreta sair.'
    end
    local result = exports.ob_core:CreateServerVehicle(source, assignment.offer.cargoModel, spawn, {
        clearRadius = Trucker.depot.trailerClearRadius, maxDistance = 160.0, serverSetterType = 'trailer',
    })
    if not result or result.ok ~= true then
        releaseDriverReservations(driver)
        return false, result and result.error or 'Nao foi possivel criar a carga.'
    end
    driver.trailerNetId, driver.state, driver.cargoStartedAt = result.netId, 'delivering', os.time()
    local trailer = entityFromNet(result.netId)
    if trailer ~= 0 then
        local state = Entity(trailer).state
        state:set('ob:truckerCargoOwner', source, true)
        state:set('ob:truckerAssignment', assignment.offer.id, true)
    end
    releaseDriverReservations(driver)
    broadcastAssignment(leader)
    return true, result.netId
end)

local function resetDestroyedCargo(leader, source, driver)
    deleteTrailer(driver)
    driver.state, driver.integrity, driver.cargoStartedAt = 'need_cargo', nil, nil
    notify(source, 'A carga foi destruida. Volte ao patio e retire outra carreta; a entrega continua ativa.', 'error')
    broadcastAssignment(leader)
end

OR.Callback.register('orbis-truckerjob:server:reportDestroyedCargo', function(source)
    local leader = getLeader(source)
    local assignment = assignments[leader]
    local driver = assignment and assignment.drivers[source]
    if not driver or driver.state ~= 'delivering' then return false end
    local trailer = entityFromNet(driver.trailerNetId)
    if trailer ~= 0 and GetVehicleBodyHealth(trailer) > Trucker.payment.destroyedBodyHealth then return false end
    resetDestroyedCargo(leader, source, driver)
    return true
end)

OR.Callback.register('orbis-truckerjob:server:deliverCargo', function(source, reportedIntegrity)
    if not OR.Security.rateLimit(source, 'trucker:deliver', 1, 2000) then return false, 'Aguarde um instante.' end
    local leader = getLeader(source)
    local assignment = assignments[leader]
    local driver = assignment and assignment.drivers[source]
    if not driver or driver.state ~= 'delivering' then return false, 'Voce nao possui uma carga para entregar.' end
    if os.time() - (driver.cargoStartedAt or os.time()) < Trucker.payment.minimumDeliverySeconds then
        return false, 'A viagem foi curta demais para validar a entrega.'
    end
    local trailer, truck = entityFromNet(driver.trailerNetId), entityFromNet(driver.truckNetId)
    if trailer == 0 then resetDestroyedCargo(leader, source, driver); return false, 'A carga nao existe mais.' end
    if truck == 0 then return false, 'Seu caminhao nao esta disponivel.' end
    local destination = assignment.offer.destination
    if not playerNear(source, destination, Trucker.delivery.serverRadius + 12.0)
        or #(GetEntityCoords(trailer) - destination) > Trucker.delivery.serverRadius
        or #(GetEntityCoords(truck) - destination) > Trucker.delivery.truckRadius then
        return false, 'Posicione a carreta dentro da area de entrega.'
    end
    local body = GetVehicleBodyHealth(trailer)
    if body <= Trucker.payment.destroyedBodyHealth then
        resetDestroyedCargo(leader, source, driver)
        return false, 'A carga foi destruida.'
    end
    local serverIntegrity = cargoIntegrity(body)
    local clientIntegrity = math.max(0.0, math.min(100.0, tonumber(reportedIntegrity) or serverIntegrity))
    -- O cliente que possui a entidade enxerga o dano antes do servidor em alguns
    -- ticks. Usar o menor valor preserva esse dano sem permitir aumentar o bonus.
    driver.integrity = math.floor(math.min(serverIntegrity, clientIntegrity) * 10 + 0.5) / 10
    deleteTrailer(driver)
    driver.state, driver.deliveredAt = 'return_truck', os.time()
    broadcastAssignment(leader)
    return true, ('Carga entregue com %.1f%% de integridade. Devolva o caminhao.'):format(driver.integrity)
end)

local function allDriversFinished(assignment)
    for _, driver in pairs(assignment.drivers) do
        if driver.state ~= 'paid' and driver.state ~= 'abandoned' then return false end
    end
    return true
end

OR.Callback.register('orbis-truckerjob:server:returnTruck', function(source)
    if not OR.Security.rateLimit(source, 'trucker:return_truck', 1, 2500) then return false, 'Aguarde um instante.' end
    local leader = getLeader(source)
    local assignment = assignments[leader]
    local driver = assignment and assignment.drivers[source]
    if not driver or driver.state ~= 'return_truck' then return false, 'Conclua a entrega antes de devolver o caminhao.' end
    local truck = entityFromNet(driver.truckNetId)
    local ped = GetPlayerPed(source)
    if truck == 0 or ped == 0 or #(GetEntityCoords(truck) - Trucker.depot.returnArea.coords) > Trucker.depot.returnArea.radius
        or GetPedInVehicleSeat(truck, -1) ~= ped or GetEntitySpeed(truck) > 2.0 then
        return false, 'Entre devagar na area de devolucao como motorista e pare o caminhao.'
    end
    local row = ensureProgress(source)
    if not row then return false, 'Banco de progresso indisponivel.' end
    local groupBonus = math.min((assignment.memberCount - 1) * Trucker.payment.groupBonusPerExtraMember,
        Trucker.payment.maxGroupBonus)
    local efficiency = skillValue(row, 'efficiency')
    local care = skillValue(row, 'care')
    local share = assignment.offer.basePay / math.max(1, assignment.memberCount)
    local integrityFactor = math.max(0.0, math.min(1.0, (driver.integrity or 0) / 100.0))
    local cargoBonus = (Trucker.payment.perfectCargoBonus + care * Trucker.skills.care.bonusPerPoint) * integrityFactor
    local money = math.max(1, math.floor(share * (1.0 + groupBonus
        + efficiency * Trucker.skills.efficiency.moneyPerPoint + cargoBonus)))
    local xp = math.max(1, math.floor((assignment.offer.baseXp / math.max(1, assignment.memberCount))
        * (1.0 + efficiency * Trucker.skills.efficiency.xpPerPoint)))
    if not exports.ob_inventory:AddItem(source, 'money', money) then
        return false, 'Sem espaco para o pagamento. Libere espaco e tente novamente.'
    end
    local newXp = (tonumber(row.xp) or 0) + xp
    OR.Database.update.await([[UPDATE ob_trucker_progress SET xp=?,level=?,deliveries_completed=deliveries_completed+1,
        total_earned=total_earned+? WHERE user_id=?]], { newXp, levelFromXp(newXp), money, userId(source) })
    deleteTruck(source, driver, false)
    driver.state = 'paid'
    TriggerClientEvent('orbis-truckerjob:client:paid', source, money, xp, driver.integrity or 0)
    if allDriversFinished(assignment) then
        local members = assignment.members
        assignments[leader] = nil
        for _, member in ipairs(members) do
            if playerExists(member) then TriggerClientEvent('orbis-truckerjob:client:assignment', member, false) end
        end
    else
        broadcastAssignment(leader)
    end
    return true
end)

OR.Callback.register('orbis-truckerjob:server:cancelAssignment', function(source)
    local leader = getLeader(source)
    if source ~= leader or not assignments[leader] then return false, 'Somente o lider pode cancelar a entrega.' end
    local members = assignments[leader].members
    cleanupAssignment(leader, false)
    for _, member in ipairs(members) do
        if playerExists(member) then TriggerClientEvent('orbis-truckerjob:client:assignment', member, false) end
    end
    return true, 'Entrega cancelada sem pagamento.'
end)

RegisterNetEvent('orbis-truckerjob:server:forceStop', function()
    local source = source
    local leader = getLeader(source)
    if source == leader and assignments[leader] then cleanupAssignment(leader, false) end
end)

AddEventHandler('playerDropped', function()
    local source, leader = source, getLeader(source)
    invites[source] = nil
    local assignment = assignments[leader]
    local group = groups[leader]

    if assignment and assignment.drivers[source] then
        local driver = assignment.drivers[source]
        releaseDriverReservations(driver)
        deleteTrailer(driver); deleteTruck(source, driver, true); driver.state = 'abandoned'
    end

    if source ~= leader then
        if group then
            group.members[source], memberGroup[source] = nil, nil
            broadcastGroup(leader)
        end
        if assignment then
            if allDriversFinished(assignment) then
                assignments[leader] = nil
            else
                broadcastAssignment(leader)
            end
        end
        return
    end

    local remaining = {}
    if group then
        for _, member in ipairs(groupSources(leader)) do
            if member ~= source then remaining[#remaining + 1] = member end
        end
    elseif assignment then
        for _, member in ipairs(assignment.members) do
            if member ~= source and playerExists(member) then remaining[#remaining + 1] = member end
        end
        table.sort(remaining)
    end

    local newLeader = remaining[1]
    memberGroup[source] = nil
    groups[leader] = nil

    if group and newLeader then
        group.leader = newLeader
        group.members[source] = nil
        groups[newLeader] = group
        for member in pairs(group.members) do
            if playerExists(member) then
                memberGroup[member] = newLeader
            else
                group.members[member], memberGroup[member] = nil, nil
            end
        end
    elseif group then
        for member in pairs(group.members) do memberGroup[member] = nil end
    end

    local assignmentContinues = assignment and newLeader and not allDriversFinished(assignment)
    assignments[leader] = nil
    if assignmentContinues then
        assignment.leader = newLeader
        assignments[newLeader] = assignment
        for _, member in ipairs(remaining) do
            notify(member, member == newLeader
                and 'O lider saiu da cidade. Voce agora lidera a entrega.'
                or 'O lider saiu da cidade, mas a entrega do grupo continua.', 'info')
        end
        if group then broadcastGroup(newLeader) end
        broadcastAssignment(newLeader)
    elseif newLeader and group then
        broadcastGroup(newLeader)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for leader in pairs(assignments) do cleanupAssignment(leader, true) end
end)

CreateThread(function()
    if not OR.Database.waitForReady(30000) then
        print('[ob_truckerjob] Banco indisponivel; emprego nao iniciado.')
        return
    end
    local idType = characterIdColumnType()
    if not idType then return print('[ob_truckerjob] Tipo de ob_characters.user_id indisponivel.') end
    local created, errorMessage = OR.Database.query.await(([[CREATE TABLE IF NOT EXISTS ob_trucker_progress (
        user_id %s NOT NULL PRIMARY KEY,
        xp INT NOT NULL DEFAULT 0,
        level INT NOT NULL DEFAULT 1,
        deliveries_completed INT NOT NULL DEFAULT 0,
        total_earned BIGINT NOT NULL DEFAULT 0,
        distance_skill TINYINT UNSIGNED NOT NULL DEFAULT 0,
        cargo_skill TINYINT UNSIGNED NOT NULL DEFAULT 0,
        care_skill TINYINT UNSIGNED NOT NULL DEFAULT 0,
        efficiency_skill TINYINT UNSIGNED NOT NULL DEFAULT 0,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        CONSTRAINT fk_ob_trucker_progress_character FOREIGN KEY (user_id) REFERENCES ob_characters(user_id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]]):format(idType))
    databaseReady = created ~= nil
    if not databaseReady then
        print(('[ob_truckerjob] Falha ao criar tabela: %s'):format(errorMessage or 'desconhecida'))
        return
    end
    generateOffers()
    while true do
        Wait(1000)
        if os.time() >= nextOfferRefresh then generateOffers() end
        for leader, assignment in pairs(assignments) do
            for source, driver in pairs(assignment.drivers) do
                if driver.state == 'delivering' and os.time() - (driver.cargoStartedAt or os.time()) >= 5 then
                    local trailer = entityFromNet(driver.trailerNetId)
                    if trailer == 0 or GetVehicleBodyHealth(trailer) <= Trucker.payment.destroyedBodyHealth then
                        resetDestroyedCargo(leader, source, driver)
                    end
                end
                if driver.truckNetId and driver.state ~= 'paid' then
                    if entityFromNet(driver.truckNetId) == 0 then
                        deleteTrailer(driver)
                        driver.truckNetId, driver.state = nil, 'waiting_truck'
                        notify(source, 'Seu caminhao nao esta mais disponivel. Retire outro na transportadora.', 'error')
                        broadcastAssignment(leader)
                    end
                end
            end
        end
    end
end)
