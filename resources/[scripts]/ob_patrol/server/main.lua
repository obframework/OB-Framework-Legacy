local sessions, groups, memberGroup, pendingInvites, builders = {}, {}, {}, {}, {}
local limiterDisabled = {}
local routeCache = { south = {}, north = {} }
local databaseReady = false

local function notify(src, message, kind)
    exports.ob_notification:Notify(src, message, kind or 'info')
end

local function isStaff(src)
    if GetResourceState('ob_admin') ~= 'started' then return false end
    local ok, value = pcall(function()
        return exports.ob_admin:HasPermission(src, Patrol.staffPermission or 'panel.open')
    end)
    return ok and value == true
end

local function isPolice(src)
    if GetResourceState('ob_org') ~= 'started' then return false end
    local ok, value = pcall(function()
        return exports.ob_org:HasPermission(src, Patrol.policePermission or 'police', Patrol.requireDuty ~= false)
    end)
    return ok and value == true
end

local function authorize(src)
    src = tonumber(src)
    if not src or src <= 0 or not GetPlayerName(src) then return false, 'Jogador indisponivel.' end
    if not isStaff(src) and not isPolice(src) then
        return false, 'Somente policiais em servico ou integrantes da staff podem patrulhar.'
    end
    if GetPlayerRoutingBucket(src) ~= 0 then return false, 'A patrulha funciona somente na cidade principal.' end
    local player = Player(src)
    local state = player and player.state
    if not state or state['or:loaded'] ~= true or state['or:downed'] == true or state['ob:restrained'] == true then
        return false, 'Nao e possivel patrulhar no estado atual.'
    end
    local ped = GetPlayerPed(src)
    if ped == 0 or not DoesEntityExist(ped) or GetEntityHealth(ped) <= 0 then return false, 'Personagem indisponivel.' end
    return true, nil, ped
end

local function nearNpc(src, distance)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and DoesEntityExist(ped)
        and #(GetEntityCoords(ped) - Patrol.npc.coords.xyz) <= (distance or Patrol.npc.startDistance or 30.0)
end

local function getLeader(src) return memberGroup[src] or src end

local function getGroup(src, create)
    local leader = getLeader(src)
    local group = groups[leader]
    if not group and create then
        group = { leader = leader, members = { [leader] = true } }
        groups[leader], memberGroup[leader] = group, leader
    end
    return leader, group
end

local function groupSources(leader)
    local group, result = groups[leader], {}
    if not group then return GetPlayerName(leader) and { leader } or {} end
    for member in pairs(group.members) do
        if GetPlayerName(member) then
            result[#result + 1] = member
        else
            group.members[member], memberGroup[member] = nil, nil
        end
    end
    table.sort(result)
    return result
end

local function groupPayload(src)
    local leader, group = getGroup(src, false)
    local members = {}
    if group then
        for _, member in ipairs(groupSources(leader)) do
            members[#members + 1] = {
                id = member,
                name = GetPlayerName(member) or ('ID %s'):format(member),
                leader = member == leader,
            }
        end
    else
        members[1] = { id = src, name = GetPlayerName(src) or ('ID %s'):format(src), leader = true }
    end
    return { leader = leader, isLeader = src == leader, maxMembers = Patrol.group.maxMembers or 4, members = members }
end

local function broadcastGroup(leader)
    for _, member in ipairs(groupSources(leader)) do
        TriggerClientEvent('ob_patrol:client:groupUpdated', member, groupPayload(member))
    end
end

local function getSession(src)
    local leader = getLeader(src)
    return sessions[leader], leader
end

local function cleanLabel(value)
    value = tostring(value or ''):gsub('%c', ''):match('^%s*(.-)%s*$')
    if #value < 3 or #value > 64 then return nil end
    return value
end

local function validRegion(region)
    return region == 'south' or region == 'north'
end

local function point(raw)
    return { x = tonumber(raw.x) or 0.0, y = tonumber(raw.y) or 0.0, z = tonumber(raw.z) or 0.0 }
end

local function routeById(routeId)
    routeId = tonumber(routeId)
    for _, region in ipairs({ 'south', 'north' }) do
        for _, route in ipairs(routeCache[region]) do
            if route.dbId == routeId then return route end
        end
    end
end

local function loadRoutesFromDatabase()
    local routes, routeError = OR.Database.query.await([[
        SELECT id, slug, region, label FROM ob_patrol_routes WHERE enabled = 1 ORDER BY region, label, id
    ]])
    if routes == nil then return false, routeError end
    local points, pointError = OR.Database.query.await([[
        SELECT route_id, position, x, y, z FROM ob_patrol_route_points ORDER BY route_id, position
    ]])
    if points == nil then return false, pointError end
    local nextCache, byId = { south = {}, north = {} }, {}
    for _, row in ipairs(routes) do
        if validRegion(row.region) then
            local route = { dbId = tonumber(row.id), id = row.slug, label = row.label, region = row.region, points = {} }
            nextCache[row.region][#nextCache[row.region] + 1] = route
            byId[route.dbId] = route
        end
    end
    for _, row in ipairs(points) do
        local route = byId[tonumber(row.route_id)]
        if route then route.points[#route.points + 1] = point(row) end
    end
    routeCache = nextCache
    return true
end

local function uniqueSlug(label)
    local slug = tostring(label):lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', '')
    if slug == '' then slug = 'rota' end
    return ('%s_%s_%s'):format(slug:sub(1, 40), os.time(), math.random(1000, 9999))
end

local function insertRoute(region, label, points, slug, createdBy)
    local routeId, insertError
    if createdBy then
        routeId, insertError = OR.Database.insert.await([[
            INSERT INTO ob_patrol_routes (slug, region, label, enabled, created_by) VALUES (?, ?, ?, 1, ?)
        ]], { slug or uniqueSlug(label), region, label, createdBy })
    else
        routeId, insertError = OR.Database.insert.await([[
            INSERT INTO ob_patrol_routes (slug, region, label, enabled) VALUES (?, ?, ?, 1)
        ]], { slug or uniqueSlug(label), region, label })
    end
    if not routeId then return nil, insertError end
    for position, coords in ipairs(points) do
        local inserted, pointError = OR.Database.insert.await([[
            INSERT INTO ob_patrol_route_points (route_id, position, x, y, z) VALUES (?, ?, ?, ?, ?)
        ]], { routeId, position, coords.x, coords.y, coords.z })
        if not inserted then
            OR.Database.update.await('DELETE FROM ob_patrol_routes WHERE id = ?', { routeId })
            return nil, pointError
        end
    end
    return tonumber(routeId)
end

local function seedRoutes()
    local countRow = OR.Database.single.await('SELECT COUNT(*) AS total FROM ob_patrol_routes')
    if (tonumber(countRow and countRow.total) or 0) > 0 then return true end
    for _, region in ipairs({ 'south', 'north' }) do
        for _, route in ipairs((Patrol.routes and Patrol.routes[region]) or {}) do
            local inserted, insertError = insertRoute(region, route.label, route.points or {}, route.id, nil)
            if not inserted then return false, insertError end
        end
    end
    local raw = LoadResourceFile(GetCurrentResourceName(), 'data/generated_routes.json')
    local ok, generated = pcall(json.decode, raw or '')
    if ok and type(generated) == 'table' then
        for _, region in ipairs({ 'south', 'north' }) do
            for _, route in ipairs(generated[region] or {}) do
                if route.points and #route.points >= (Patrol.creator.minimumPoints or 3) then
                    insertRoute(region, route.label or 'Rota migrada', route.points, nil, nil)
                end
            end
        end
    end
    return true
end

local function routeAdminPayload()
    local result = {}
    for _, region in ipairs({ 'south', 'north' }) do
        for _, route in ipairs(routeCache[region]) do
            result[#result + 1] = {
                id = route.dbId,
                slug = route.id,
                label = route.label,
                region = region,
                points = #route.points,
            }
        end
    end
    return result
end

local function regionSummary()
    return {
        south = { label = 'Sul da cidade', routes = #routeCache.south },
        north = { label = 'Norte da cidade', routes = #routeCache.north },
    }
end

local function rotatePoints(points, origin)
    local nearest, distance = 1, math.huge
    for index, current in ipairs(points) do
        local value = #(origin - vector3(current.x, current.y, current.z))
        if value < distance then nearest, distance = index, value end
    end
    local result = {}
    for offset = 0, #points - 1 do result[#result + 1] = point(points[((nearest + offset - 1) % #points) + 1]) end
    return result
end

local function vehicleFromNet(netId)
    netId = tonumber(netId)
    if not netId or netId <= 0 then return 0 end
    for _, vehicle in ipairs(GetAllVehicles()) do
        if DoesEntityExist(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) == netId then return vehicle end
    end
    return 0
end

local function configuredVehicle(model)
    for name, label in pairs(Patrol.allowedVehicles or {}) do
        if joaat(name) == model then return name, label end
    end
end

local function patrolVehicle(src, netId)
    local vehicle = vehicleFromNet(netId)
    if vehicle == 0 then return nil, 'Entre em uma viatura autorizada como motorista.' end
    local ped = GetPlayerPed(src)
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return nil, 'Voce precisa dirigir a viatura.' end
    if not configuredVehicle(GetEntityModel(vehicle)) then return nil, 'Este veiculo nao esta autorizado para patrulhamento.' end
    return vehicle
end

local function rewardPlayer(src, range, reason)
    local minimum = math.max(0, math.floor(tonumber(range and range.min) or 0))
    local maximum = math.max(minimum, math.floor(tonumber(range and range.max) or minimum))
    local amount = math.random(minimum, maximum)
    if amount <= 0 then return true, 0 end
    local item = Patrol.payment.item or 'money'
    local canCarry, carryError = exports.ob_inventory:CanCarryItem(src, item, amount)
    if not canCarry then return false, carryError or 'Sem espaco para receber o pagamento.' end
    local added, addError = exports.ob_inventory:AddItem(src, item, amount)
    if not added then return false, addError or 'Nao foi possivel entregar o pagamento.' end
    notify(src, ('%s: %s'):format(reason, OR.FormatMoney(amount)), 'success')
    return true, amount
end

local function publicSession(session)
    if not session then return { active = false } end
    return {
        active = true,
        region = session.region,
        routeId = session.routeId,
        routeLabel = session.routeLabel,
        checkpoint = session.checkpoint,
        total = #session.points,
        points = session.points,
        cycle = session.cycle,
    }
end

local function broadcastSession(leader)
    local payload = publicSession(sessions[leader])
    for _, member in ipairs(groupSources(leader)) do
        TriggerClientEvent('ob_patrol:client:jobSync', member, payload)
    end
end

local function stopPatrol(leader, reason, completed)
    if not sessions[leader] then return end
    sessions[leader] = nil
    for _, member in ipairs(groupSources(leader)) do
        limiterDisabled[member] = nil
        TriggerClientEvent('ob_patrol:client:stopped', member, reason, completed == true)
    end
end

local function chooseRoute(region, previousId)
    local routes, choices = routeCache[region] or {}, {}
    for _, route in ipairs(routes) do
        if #route.points >= 2 and (route.dbId ~= previousId or #routes == 1) then choices[#choices + 1] = route end
    end
    if #choices == 0 then
        for _, route in ipairs(routes) do if #route.points >= 2 then choices[#choices + 1] = route end end
    end
    return #choices > 0 and choices[math.random(#choices)] or nil
end

local function beginRoute(session, route, origin)
    session.routeId = route.dbId
    session.routeSlug = route.id
    session.routeLabel = route.label
    session.points = rotatePoints(route.points, origin)
    session.checkpoint = 1
    session.cycle = (session.cycle or 0) + 1
end

local function advanceOrLoop(session, leader, origin)
    session.checkpoint = session.checkpoint + 1
    if session.checkpoint <= #session.points then return true end
    local route = chooseRoute(session.region, session.routeId)
    if not route then
        stopPatrol(leader, 'Patrulha encerrada: nao existem mais rotas disponiveis.', false)
        return false
    end
    beginRoute(session, route, origin)
    for _, member in ipairs(groupSources(leader)) do
        notify(member, ('Nova rota continua: %s.'):format(route.label), 'info')
    end
    return true
end

local function eventPublic(event, token, handler)
    local payload = {
        token = token,
        handler = handler,
        type = event.type or 'assist',
        label = event.label,
        action = event.action,
        coords = { x = event.coords.x, y = event.coords.y, z = event.coords.z, w = event.coords.w },
        model = event.model,
        victimModel = event.victimModel,
        weapon = event.weapon,
        scenario = event.scenario,
    }
    return payload
end

local function randomDelay(range, fallbackMin, fallbackMax)
    local minimum = math.max(1, math.floor(tonumber(range and range.min) or fallbackMin))
    local maximum = math.max(minimum, math.floor(tonumber(range and range.max) or fallbackMax))
    return math.random(minimum, maximum)
end

local function scheduleNextEvent(session, initial)
    local cfg = Patrol.events or {}
    session.nextEventAt = os.time() + randomDelay(initial and cfg.firstDelaySeconds or cfg.intervalSeconds,
        initial and 45 or 90, initial and 80 or 180)
end

local function activePatrolDriver(src)
    if limiterDisabled[src] or not GetPlayerName(src) then return nil end
    local ped = GetPlayerPed(src)
    if ped == 0 or not DoesEntityExist(ped) then return nil end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then return nil end
    if not configuredVehicle(GetEntityModel(vehicle)) then return nil end
    return ped
end

local function eventHandler(leader)
    local drivers = {}
    for _, member in ipairs(groupSources(leader)) do
        if activePatrolDriver(member) then drivers[#drivers + 1] = member end
    end
    return #drivers > 0 and drivers[math.random(#drivers)] or nil
end

local function chooseEvent(session, leader)
    local cfg = Patrol.events or {}
    local handler = eventHandler(leader)
    if not handler then return nil end
    local ped = GetPlayerPed(handler)
    local origin = GetEntityCoords(ped)
    local minimumDistance = tonumber(cfg.minimumSpawnDistance) or 180.0
    local maximumDistance = math.max(minimumDistance, tonumber(cfg.maximumSpawnDistance) or 2800.0)
    local choices = {}
    for index, event in ipairs(cfg.locations or {}) do
        if event.region == session.region and not session.usedEvents[index] then
            local distance = #(origin - event.coords.xyz)
            if distance >= minimumDistance and distance <= maximumDistance then
                choices[#choices + 1] = { index = index, event = event, distance = distance }
            end
        end
    end
    if #choices == 0 and next(session.usedEvents) then
        session.usedEvents = {}
        return chooseEvent(session, leader)
    end
    table.sort(choices, function(a, b) return a.distance < b.distance end)
    if #choices == 0 then return nil end

    local selectedType = choices[math.random(#choices)].event.type
    local selected
    for _, choice in ipairs(choices) do
        if choice.event.type == selectedType then selected = choice; break end
    end
    selected = selected or choices[1]
    session.usedEvents[selected.index] = true
    session.eventSerial = session.eventSerial + 1
    local token = ('%s:%s:%s'):format(session.startedAt, session.passed, session.eventSerial)
    local public = eventPublic(selected.event, token, handler)
    session.waitingEvent = {
        token = token,
        handler = handler,
        coords = point(selected.event.coords),
        startedAt = os.time(),
        expiresAt = os.time() + ((Patrol.events and Patrol.events.timeoutSeconds) or 480),
        public = public,
    }
    session.nextEventAt = nil
    return public
end

local function panelPayload(src)
    local session = getSession(src)
    return {
        regions = regionSummary(),
        speedLimit = Patrol.speedLimitKmh,
        group = groupPayload(src),
        work = publicSession(session),
    }
end

local function routeManagerPayload()
    return { adminOnly = true, isStaff = true, staffRoutes = routeAdminPayload() }
end

OR.Callback.register('ob_patrol:server:panel', function(src)
    if not OR.Security.rateLimit(src, 'patrol:panel', 4, 5000) then return false, 'Aguarde antes de abrir novamente.' end
    local allowed, message = authorize(src)
    if not allowed then return false, message end
    if not databaseReady then return false, 'As rotas de patrulha ainda estao carregando.' end
    if not nearNpc(src, (Patrol.npc.targetDistance or 3.0) + 2.0) then return false, 'Aproxime-se do responsavel pela patrulha.' end
    return true, panelPayload(src)
end)

OR.Callback.register('ob_patrol:server:start', function(src, region)
    if not OR.Security.rateLimit(src, 'patrol:start', 2, 5000) then return false, 'Aguarde antes de iniciar novamente.' end
    local leader = getLeader(src)
    if src ~= leader then return false, 'Somente o lider pode iniciar a patrulha.' end
    if sessions[leader] then return false, 'O grupo ja esta patrulhando.' end
    if not validRegion(region) then return false, 'Regiao invalida.' end
    if not databaseReady then return false, 'Banco de rotas indisponivel.' end
    for _, member in ipairs(groupSources(leader)) do
        local allowed, message = authorize(member)
        if not allowed then return false, ('%s: %s'):format(GetPlayerName(member) or member, message) end
        if not nearNpc(member, Patrol.npc.startDistance or 30.0) then
            return false, ('%s precisa estar proximo do responsavel.'):format(GetPlayerName(member) or member)
        end
    end
    local route = chooseRoute(region)
    if not route then return false, 'Nao existem rotas validas nesta regiao.' end
    local session = {
        region = region,
        startedAt = os.time(),
        passed = 0,
        cycle = 0,
    }
    beginRoute(session, route, GetEntityCoords(GetPlayerPed(src)))
    sessions[leader] = session
    for _, member in ipairs(groupSources(leader)) do limiterDisabled[member] = nil end
    print(('[ob_patrol] START leader=%s members=%s region=%s route=%s'):format(leader, #groupSources(leader), region, route.id))
    broadcastSession(leader)
    broadcastGroup(leader)
    return true, publicSession(session)
end)

OR.Callback.register('ob_patrol:server:checkpoint', function(src, checkpoint, netId)
    if not OR.Security.rateLimit(src, 'patrol:checkpoint', 4, 3000) then return false, 'Aguarde.' end
    local session, leader = getSession(src)
    checkpoint = tonumber(checkpoint)
    if not session or checkpoint ~= session.checkpoint or session.waitingEvent then return false, 'Checkpoint invalido.' end
    if session.processingCheckpoint then return false, 'Este checkpoint ja esta sendo processado.' end
    local allowed, message = authorize(src)
    if not allowed then stopPatrol(leader, message); return false, message end
    local vehicle, vehicleError = patrolVehicle(src, netId)
    if not vehicle then return false, vehicleError end
    local target = session.points[checkpoint]
    if #(GetEntityCoords(vehicle) - vector3(target.x, target.y, target.z)) > ((Patrol.checkpoint and Patrol.checkpoint.serverTolerance) or 13.0) then
        return false, 'Passe pelo checkpoint dirigindo a viatura.'
    end
    session.processingCheckpoint = true
    local paid, payment = rewardPlayer(src, Patrol.payment.checkpoint, 'Checkpoint concluido')
    if not paid then session.processingCheckpoint = nil; return false, payment end
    session.passed = session.passed + 1
    if advanceOrLoop(session, leader, GetEntityCoords(vehicle)) then broadcastSession(leader) end
    session.processingCheckpoint = nil
    return true, { payment = payment }
end)

OR.Callback.register('ob_patrol:server:completeEvent', function(src, token)
    if not OR.Security.rateLimit(src, 'patrol:event', 2, 5000) then return false, 'Aguarde.' end
    local session, leader = getSession(src)
    local event = session and session.waitingEvent
    if not event or event.handler ~= src or type(token) ~= 'string' or token ~= event.token then
        return false, 'Esta ocorrencia foi designada para outro integrante.'
    end
    if session.processingEvent then return false, 'Esta ocorrencia ja esta sendo processada.' end
    local allowed, message, ped = authorize(src)
    if not allowed then stopPatrol(leader, message); return false, message end
    if #(GetEntityCoords(ped) - vector3(event.coords.x, event.coords.y, event.coords.z)) > 350.0 then
        return false, 'Voce se afastou demais da ocorrencia.'
    end
    session.processingEvent = true
    local paid, payment = rewardPlayer(src, Patrol.payment.occurrence, 'Ocorrencia concluida')
    if not paid then session.processingEvent = nil; return false, payment end
    session.waitingEvent = nil
    scheduleNextEvent(session, false)
    broadcastSession(leader)
    session.processingEvent = nil
    return true, { payment = payment }
end)

OR.Callback.register('ob_patrol:server:setLimiter', function(src, enabled)
    local session, leader = getSession(src)
    if not session then return false, 'Nenhuma patrulha esta ativa.' end
    local allowed, message = authorize(src)
    if not allowed then return false, message end
    limiterDisabled[src] = enabled ~= true
    local event = session.waitingEvent
    if enabled ~= true and event and event.handler == src then
        local replacement = eventHandler(leader)
        if replacement then
            event.handler = replacement
            event.public.handler = replacement
            notify(replacement, 'A ocorrencia foi transferida para voce.', 'info')
        else
            session.waitingEvent = nil
            scheduleNextEvent(session, false)
        end
        broadcastSession(leader)
    end
    return true
end)

OR.Callback.register('ob_patrol:server:stop', function(src)
    local session, leader = getSession(src)
    if not session then return true end
    if src ~= leader then return false, 'Somente o lider pode encerrar a patrulha do grupo.' end
    stopPatrol(leader, 'O lider encerrou a patrulha.', false)
    return true
end)

OR.Callback.register('ob_patrol:server:invite', function(src, target)
    if not OR.Security.rateLimit(src, 'patrol:invite', 3, 10000) then return false, 'Aguarde antes de convidar novamente.' end
    target = tonumber(target)
    local leader, group = getGroup(src, true)
    if src ~= leader then return false, 'Somente o lider pode convidar.' end
    if sessions[leader] then return false, 'Encerre a patrulha antes de alterar o grupo.' end
    if not target or target == src or not GetPlayerName(target) then return false, 'Jogador invalido.' end
    local allowed, message = authorize(target)
    if not allowed then return false, message end
    if not nearNpc(src, Patrol.npc.startDistance) or not nearNpc(target, Patrol.npc.startDistance) then
        return false, 'Todos precisam estar proximos do responsavel.'
    end
    local targetLeader, targetGroup = getGroup(target, false)
    if sessions[targetLeader] then return false, 'Esse jogador esta patrulhando.' end
    if targetGroup and #groupSources(targetLeader) == 1 then
        groups[targetLeader], memberGroup[target] = nil, nil
    elseif memberGroup[target] then
        return false, 'Esse jogador ja esta em um grupo.'
    end
    if #groupSources(leader) >= (Patrol.group.maxMembers or 4) then return false, 'O grupo ja esta completo.' end
    local p1, p2 = GetPlayerPed(src), GetPlayerPed(target)
    if p1 == 0 or p2 == 0 or #(GetEntityCoords(p1) - GetEntityCoords(p2)) > (Patrol.group.inviteDistance or 18.0) then
        return false, 'O jogador precisa estar proximo.'
    end
    pendingInvites[target] = { leader = leader, expires = os.time() + (Patrol.group.inviteSeconds or 30) }
    TriggerClientEvent('ob_patrol:client:groupInvite', target, { name = GetPlayerName(src) or ('ID %s'):format(src) })
    return true, 'Convite enviado.'
end)

OR.Callback.register('ob_patrol:server:answerInvite', function(src, accept)
    local invite = pendingInvites[src]
    pendingInvites[src] = nil
    local group = invite and groups[invite.leader]
    if not invite or invite.expires < os.time() or not group then return false, 'Convite expirado.' end
    if not accept then return true, 'Convite recusado.' end
    local allowed, message = authorize(src)
    if not allowed then return false, message end
    if memberGroup[src] or sessions[src] or sessions[invite.leader] or #groupSources(invite.leader) >= (Patrol.group.maxMembers or 4) then
        return false, 'Grupo indisponivel.'
    end
    local p1, p2 = GetPlayerPed(invite.leader), GetPlayerPed(src)
    if p1 == 0 or p2 == 0 or #(GetEntityCoords(p1) - GetEntityCoords(p2)) > (Patrol.group.inviteDistance or 18.0) then
        return false, 'Aproxime-se do lider para entrar.'
    end
    group.members[src], memberGroup[src] = true, invite.leader
    broadcastGroup(invite.leader)
    return true, 'Voce entrou no grupo de patrulha.'
end)

OR.Callback.register('ob_patrol:server:leaveGroup', function(src)
    local leader, group = getGroup(src, false)
    if not group then return true end
    if sessions[leader] then return false, 'Encerre a patrulha antes de sair do grupo.' end
    if src == leader then
        local members = groupSources(leader)
        groups[leader] = nil
        for _, member in ipairs(members) do
            memberGroup[member] = nil
            TriggerClientEvent('ob_patrol:client:groupUpdated', member, groupPayload(member))
        end
    else
        group.members[src], memberGroup[src] = nil, nil
        TriggerClientEvent('ob_patrol:client:groupUpdated', src, groupPayload(src))
        broadcastGroup(leader)
    end
    return true, 'Voce saiu do grupo.'
end)

local function staffRouteAccess(src)
    if not isStaff(src) then return false, 'Somente a staff pode gerenciar rotas.' end
    if not databaseReady then return false, 'Banco de rotas indisponivel.' end
    return true
end


OR.Callback.register('ob_patrol:server:adminPanel', function(src)
    if not OR.Security.rateLimit(src, 'patrol:admin_panel', 4, 5000) then return false, 'Aguarde antes de abrir novamente.' end
    local allowed, message = staffRouteAccess(src)
    if not allowed then return false, message end
    return true, routeManagerPayload()
end)

OR.Callback.register('ob_patrol:server:adminStartRecording', function(src, data)
    local allowed, message = staffRouteAccess(src)
    if not allowed then return false, message end
    data = type(data) == 'table' and data or {}
    local region, label, routeId = tostring(data.region or ''), cleanLabel(data.label), tonumber(data.routeId)
    if not validRegion(region) or not label then return false, 'Informe regiao e nome validos.' end
    if routeId and not routeById(routeId) then return false, 'Rota nao encontrada.' end
    builders[src] = { region = region, label = label, points = {}, replaceId = routeId }
    return true, routeId and 'Regravacao iniciada. Use /patrulhaponto e depois /patrulhasalvar.'
        or 'Criacao iniciada. Use /patrulhaponto e depois /patrulhasalvar.'
end)

OR.Callback.register('ob_patrol:server:adminUpdateRoute', function(src, data)
    local allowed, message = staffRouteAccess(src)
    if not allowed then return false, message end
    data = type(data) == 'table' and data or {}
    local route, region, label = routeById(data.id), tostring(data.region or ''), cleanLabel(data.label)
    if not route or not validRegion(region) or not label then return false, 'Dados da rota invalidos.' end
    if route.region ~= region and #routeCache[route.region] <= 1 then return false, 'A regiao precisa manter pelo menos uma rota.' end
    local updated, updateError = OR.Database.update.await('UPDATE ob_patrol_routes SET label = ?, region = ? WHERE id = ?', { label, region, route.dbId })
    if updated == nil then return false, updateError or 'Nao foi possivel atualizar a rota.' end
    local loaded, loadError = loadRoutesFromDatabase()
    if not loaded then return false, loadError or 'Rota alterada, mas o cache nao foi atualizado.' end
    return true, routeManagerPayload()
end)

OR.Callback.register('ob_patrol:server:adminDeleteRoute', function(src, routeId)
    local allowed, message = staffRouteAccess(src)
    if not allowed then return false, message end
    local route = routeById(routeId)
    if not route then return false, 'Rota nao encontrada.' end
    if #routeCache[route.region] <= 1 then return false, 'A regiao precisa manter pelo menos uma rota.' end
    local deleted, deleteError = OR.Database.update.await('DELETE FROM ob_patrol_routes WHERE id = ?', { route.dbId })
    if deleted == nil then return false, deleteError or 'Nao foi possivel excluir a rota.' end
    local loaded, loadError = loadRoutesFromDatabase()
    if not loaded then return false, loadError or 'Rota excluida, mas o cache nao foi atualizado.' end
    return true, routeManagerPayload()
end)

local function saveRecordedRoute(src)
    local builder = builders[src]
    if not builder then return false, 'Nenhuma rota esta sendo gravada.' end
    if #builder.points < (Patrol.creator.minimumPoints or 3) then return false, 'Adicione pelo menos 3 checkpoints.' end
    if builder.replaceId then
        local route = routeById(builder.replaceId)
        if not route then return false, 'A rota original nao existe mais.' end
        local oldPoints = route.points
        OR.Database.update.await('DELETE FROM ob_patrol_route_points WHERE route_id = ?', { route.dbId })
        for position, coords in ipairs(builder.points) do
            local inserted, insertError = OR.Database.insert.await([[
                INSERT INTO ob_patrol_route_points (route_id, position, x, y, z) VALUES (?, ?, ?, ?, ?)
            ]], { route.dbId, position, coords.x, coords.y, coords.z })
            if not inserted then
                OR.Database.update.await('DELETE FROM ob_patrol_route_points WHERE route_id = ?', { route.dbId })
                for oldPosition, old in ipairs(oldPoints) do
                    OR.Database.insert.await('INSERT INTO ob_patrol_route_points (route_id, position, x, y, z) VALUES (?, ?, ?, ?, ?)',
                        { route.dbId, oldPosition, old.x, old.y, old.z })
                end
                return false, insertError or 'Falha ao substituir os pontos; a rota anterior foi restaurada.'
            end
        end
        OR.Database.update.await('UPDATE ob_patrol_routes SET label = ?, region = ? WHERE id = ?', { builder.label, builder.region, route.dbId })
    else
        local inserted, insertError = insertRoute(builder.region, builder.label, builder.points, nil, exports.ob_core:GetUserId(src))
        if not inserted then return false, insertError or 'Nao foi possivel criar a rota.' end
    end
    builders[src] = nil
    local loaded, loadError = loadRoutesFromDatabase()
    if not loaded then return false, loadError or 'Rota salva, mas o cache nao foi atualizado.' end
    return true, ('Rota "%s" salva com %s checkpoints.'):format(builder.label, #builder.points)
end

RegisterCommand(Patrol.creator.startCommand, function(src, args)
    if src <= 0 or not isStaff(src) then return end
    local region, label = tostring(args[1] or ''):lower(), cleanLabel(table.concat(args, ' ', 2))
    if not validRegion(region) or not label then return notify(src, 'Use /patrulhacriar sul|norte Nome.', 'error') end
    builders[src] = { region = region, label = label, points = {} }
    notify(src, 'Criacao iniciada. Use /patrulhaponto dirigindo em cada checkpoint.', 'success')
end, false)

RegisterCommand(Patrol.creator.pointCommand, function(src)
    if src <= 0 or not isStaff(src) then return end
    local builder = builders[src]
    if not builder then return notify(src, 'Inicie a gravacao pelo painel do NPC.', 'error') end
    if #builder.points >= (Patrol.creator.maximumPoints or 80) then return notify(src, 'Limite de pontos atingido.', 'error') end
    local ped = GetPlayerPed(src)
    local vehicle = ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then return notify(src, 'Entre no banco do motorista para marcar o ponto.', 'error') end
    local coords = GetEntityCoords(vehicle)
    builder.points[#builder.points + 1] = { x = coords.x, y = coords.y, z = coords.z }
    notify(src, ('Checkpoint %s registrado.'):format(#builder.points), 'success')
end, false)

RegisterCommand(Patrol.creator.saveCommand, function(src)
    if src <= 0 or not isStaff(src) then return end
    local ok, message = saveRecordedRoute(src)
    notify(src, message, ok and 'success' or 'error')
end, false)

RegisterCommand(Patrol.creator.cancelCommand, function(src)
    if src <= 0 or not isStaff(src) then return end
    builders[src] = nil
    notify(src, 'Gravacao de rota cancelada.', 'info')
end, false)

AddEventHandler('ob_core:server:jobDutyChanged', function(src, onDuty)
    if onDuty ~= true then
        local session, leader = getSession(src)
        if session and not isStaff(src) then stopPatrol(leader, 'Patrulha encerrada: um integrante saiu de servico.') end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    pendingInvites[src], builders[src], limiterDisabled[src] = nil, nil, nil
    local session, leader = getSession(src)
    local group = groups[leader]
    if session then
        if src == leader then
            stopPatrol(leader, 'O lider saiu; a patrulha foi encerrada.')
        elseif session.waitingEvent and session.waitingEvent.handler == src then
            local replacement
            for _, member in ipairs(groupSources(leader)) do
                if member ~= src and activePatrolDriver(member) then replacement = member break end
            end
            if replacement then
                session.waitingEvent.handler = replacement
                session.waitingEvent.public.handler = replacement
                notify(replacement, 'A ocorrencia foi transferida para voce.', 'info')
                broadcastSession(leader)
            else
                session.waitingEvent = nil
                scheduleNextEvent(session, false)
            end
        end
    end
    if not group then return end
    group.members[src], memberGroup[src] = nil, nil
    if src == leader then
        groups[leader] = nil
        local nextLeader
        for member in pairs(group.members) do if GetPlayerName(member) then nextLeader = member break end end
        if nextLeader then
            group.leader, groups[nextLeader] = nextLeader, group
            for member in pairs(group.members) do memberGroup[member] = nextLeader end
            broadcastGroup(nextLeader)
        end
    else
        broadcastGroup(leader)
    end
end)

CreateThread(function()
    if not OR.Database.waitForReady(30000) then return print('[ob_patrol] Banco indisponivel; patrulha nao iniciada.') end
    local routesCreated, routesError = OR.Database.query.await([[
        CREATE TABLE IF NOT EXISTS ob_patrol_routes (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            slug VARCHAR(64) NOT NULL,
            region VARCHAR(8) NOT NULL,
            label VARCHAR(64) NOT NULL,
            enabled TINYINT(1) NOT NULL DEFAULT 1,
            created_by BIGINT UNSIGNED NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id), UNIQUE KEY uq_ob_patrol_route_slug (slug), KEY idx_ob_patrol_region (region, enabled)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
    if routesCreated == nil then return print(('[ob_patrol] Falha na tabela de rotas: %s'):format(routesError or 'desconhecida')) end
    local pointsCreated, pointsError = OR.Database.query.await([[
        CREATE TABLE IF NOT EXISTS ob_patrol_route_points (
            route_id BIGINT UNSIGNED NOT NULL,
            position SMALLINT UNSIGNED NOT NULL,
            x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL,
            PRIMARY KEY (route_id, position),
            CONSTRAINT fk_ob_patrol_route_points FOREIGN KEY (route_id) REFERENCES ob_patrol_routes(id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
    if pointsCreated == nil then return print(('[ob_patrol] Falha na tabela de pontos: %s'):format(pointsError or 'desconhecida')) end
    local seeded, seedError = seedRoutes()
    if not seeded then return print(('[ob_patrol] Falha ao migrar rotas: %s'):format(seedError or 'desconhecida')) end
    local loaded, loadError = loadRoutesFromDatabase()
    databaseReady = loaded == true
    if not databaseReady then print(('[ob_patrol] Falha ao carregar rotas: %s'):format(loadError or 'desconhecida'))
    else print(('[ob_patrol] Rotas carregadas do banco: sul=%s norte=%s'):format(#routeCache.south, #routeCache.north)) end
end)

