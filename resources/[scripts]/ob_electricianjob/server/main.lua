local groups, memberGroup, invites, jobs = {}, {}, {}, {}
local databaseReady = false

local function userId(source) return exports.ob_core:GetUserId(source) end
local function playerExists(source) return source and GetPlayerName(source) ~= nil and userId(source) ~= nil end
local function near(source, coords, distance)
    local ped = GetPlayerPed(source)
    return ped ~= 0 and #(GetEntityCoords(ped) - coords) <= distance
end

local function getGroup(source, create)
    local leader = memberGroup[source] or source
    local group = groups[leader]
    if not group and create then
        group = { leader = source, members = { [source] = true } }
        groups[source], memberGroup[source] = group, source
        leader = source
    end
    return leader, group
end

local function members(leader)
    local result, group = {}, groups[leader]
    if not group then return { leader } end
    for source in pairs(group.members) do
        if playerExists(source) then result[#result + 1] = source else group.members[source], memberGroup[source] = nil, nil end
    end
    table.sort(result)
    return result
end

local function groupSize(leader) return #members(leader) end

local function groupPayload(source)
    local leader, group = getGroup(source, false)
    if not group then leader = source end
    local list = {}
    for _, member in ipairs(members(leader)) do
        list[#list + 1] = { id = member, name = GetPlayerName(member) or ('ID %s'):format(member), leader = member == leader }
    end
    return { leader = leader, isLeader = source == leader, maxMembers = Electrician.group.maxMembers, members = list }
end

local function broadcastGroup(leader)
    for _, member in ipairs(members(leader)) do
        TriggerClientEvent('orbis-electrician:client:groupUpdated', member, groupPayload(member))
    end
end

local function jobFor(source)
    local leader = memberGroup[source] or source
    return jobs[leader], leader
end

local function publicJob(job)
    if not job then return { active = false } end
    return {
        active = true,
        task = job.task,
        stage = job.stage,
        stepLabel = Electrician.steps[job.stage].label,
        stepCount = #Electrician.steps,
        vehicleNetId = job.vehicleNetId,
        toolId = job.toolId,
        toolHolder = job.toolHolder or false,
        repaired = job.repaired == true,
        batchCompleted = job.batchCompleted or 0,
        batchSize = Electrician.work.servicesPerBatch,
        completed = job.completed,
        pending = job.pending or 0,
    }
end

local function broadcastJob(leader)
    local payload = publicJob(jobs[leader])
    for _, member in ipairs(members(leader)) do TriggerClientEvent('orbis-electrician:client:jobSync', member, payload) end
end

local function levelFromXp(xp)
    return math.min(math.floor((tonumber(xp) or 0) / Electrician.work.levelStep) + 1, Electrician.work.maxLevel)
end

local function progressRow(source)
    local id = tonumber(userId(source))
    if not databaseReady or not id then return { xp = 0, level = 1, repairs = 0, total_earned = 0 } end
    OR.Database.update.await('INSERT IGNORE INTO ob_electrician_progress (user_id) VALUES (?)', { id })
    return OR.Database.single.await('SELECT * FROM ob_electrician_progress WHERE user_id = ?', { id })
        or { xp = 0, level = 1, repairs = 0, total_earned = 0 }
end

local function progressPayload(row)
    local level = levelFromXp(row.xp)
    return {
        level = level,
        xp = tonumber(row.xp) or 0,
        xpInLevel = (tonumber(row.xp) or 0) - ((level - 1) * Electrician.work.levelStep),
        xpRequired = Electrician.work.levelStep,
        completed = tonumber(row.repairs) or 0,
        totalEarned = tonumber(row.total_earned) or 0,
        paymentBonus = math.floor(math.min((level - 1) * Electrician.work.paymentBonusPerLevel, Electrician.work.maxPaymentBonus) * 100),
        paymentBonusStep = Electrician.work.paymentBonusPerLevel * 100,
        maxPaymentBonus = Electrician.work.maxPaymentBonus * 100,
        maxLevel = Electrician.work.maxLevel,
    }
end

local function displayName(row)
    local name = ((row and row.firstname or '') .. ' ' .. (row and row.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
    return name ~= '' and name or ('ID %s'):format(row and row.user_id or '?')
end

local function leaderboard(source, ownRow)
    if not databaseReady then
        return {
            xp = { list = {}, myRank = 0, myValue = 0 },
            repairs = { list = {}, myRank = 0, myValue = 0 },
        }
    end
    local xpRows = OR.Database.query.await([[SELECT p.user_id,p.xp,p.repairs,c.firstname,c.lastname
        FROM ob_electrician_progress p LEFT JOIN ob_characters c ON c.user_id=p.user_id
        ORDER BY p.xp DESC,p.repairs DESC,p.user_id ASC LIMIT 50]]) or {}
    local repairRows = OR.Database.query.await([[SELECT p.user_id,p.xp,p.repairs,c.firstname,c.lastname
        FROM ob_electrician_progress p LEFT JOIN ob_characters c ON c.user_id=p.user_id
        ORDER BY p.repairs DESC,p.xp DESC,p.user_id ASC LIMIT 50]]) or {}
    local function build(rows)
        local list = {}
        for rank, row in ipairs(rows) do
            list[#list + 1] = {
                rank = rank,
                name = displayName(row),
                xp = tonumber(row.xp) or 0,
                repairs = tonumber(row.repairs) or 0,
            }
        end
        return list
    end
    local id = tonumber(userId(source))
    local xp = tonumber(ownRow and ownRow.xp) or 0
    local repairs = tonumber(ownRow and ownRow.repairs) or 0
    local xpCount = OR.Database.single.await([[SELECT COUNT(*) total FROM ob_electrician_progress
        WHERE xp>? OR (xp=? AND repairs>?) OR (xp=? AND repairs=? AND user_id<?)]],
        { xp, xp, repairs, xp, repairs, id })
    local repairCount = OR.Database.single.await([[SELECT COUNT(*) total FROM ob_electrician_progress
        WHERE repairs>? OR (repairs=? AND xp>?) OR (repairs=? AND xp=? AND user_id<?)]],
        { repairs, repairs, xp, repairs, xp, id })
    return {
        xp = { list = build(xpRows), myRank = (tonumber(xpCount and xpCount.total) or 0) + 1, myValue = xp },
        repairs = { list = build(repairRows), myRank = (tonumber(repairCount and repairCount.total) or 0) + 1, myValue = repairs },
    }
end

local function chooseTask(leader, previous, blocked)
    local choices = {}
    local allowAerial = groupSize(leader) >= 2
    for index, task in ipairs(Electrician.tasks) do
        if index ~= previous and not (blocked and blocked[index]) and (task.type ~= 'aerial' or allowAerial) then choices[#choices + 1] = index end
    end
    if #choices == 0 then return nil end
    return choices[math.random(#choices)]
end

local function vehicleEntity(job)
    if not job or not job.vehicleNetId then return 0 end
    local vehicle = NetworkGetEntityFromNetworkId(job.vehicleNetId)
    return vehicle ~= 0 and DoesEntityExist(vehicle) and vehicle or 0
end

local function aerialHasOperator(source, leader, vehicle)
    local driver = vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) or 0
    if driver == 0 or driver == GetPlayerPed(source) then return false end
    for _, member in ipairs(members(leader)) do
        if member ~= source and GetPlayerPed(member) == driver then return true end
    end
    return false
end

OR.Callback.register('orbis-electrician:server:getPanelData', function(source)
    local job = jobFor(source)
    local row = progressRow(source)
    return {
        progress = progressPayload(row),
        group = groupPayload(source),
        work = publicJob(job),
        leaderboard = leaderboard(source, row),
    }
end)

OR.Callback.register('orbis-electrician:server:getStatus', function(source)
    local job = jobFor(source)
    return publicJob(job), groupPayload(source)
end)

OR.Callback.register('orbis-electrician:server:startJob', function(source)
    if not databaseReady then return false, 'O banco de progresso ainda nao esta disponivel.' end
    local leader, group = getGroup(source, true)
    if source ~= leader then return false, 'Somente o lider pode iniciar o turno.' end
    if jobs[leader] then return false, 'O grupo ja esta em servico.' end
    local task = chooseTask(leader)
    if not task then return false, 'Nenhum chamado disponivel.' end
    jobs[leader] = { task = task, stage = 1, completed = 0, busy = nil, invalidTasks = {}, toolId = Electrician.steps[1].tool, rewards = {}, batchCompleted = 0 }
    broadcastJob(leader)
    return true, publicJob(jobs[leader])
end)

OR.Callback.register('orbis-electrician:server:spawnVehicle', function(source)
    local job, leader = jobFor(source)
    if not job or source ~= leader then return false, 'Somente o lider pode retirar o caminhao.' end
    if vehicleEntity(job) ~= 0 or job.spawning then return false, 'O caminhao ja foi retirado ou esta sendo criado.' end
    job.spawning = true
    local ok, result = exports.ob_core:SpawnTemporaryVehicle(source, Electrician.vehicle.model, Electrician.vehicle.spawn, {
        platePrefix = Electrician.vehicle.platePrefix, fuel = 100.0,
        clearRadius = Electrician.vehicle.spawnClearRadius, maxDistance = 120.0,
        serverSetterType = 'automobile',
    })
    job.spawning = nil
    if not ok then return false, result end
    if jobs[leader] ~= job then
        exports.ob_core:DeleteTemporaryVehicle(source, result.netId)
        return false, 'Turno encerrado.'
    end
    job.vehicleNetId = result.netId
    Entity(NetworkGetEntityFromNetworkId(result.netId)).state:set('ob:electricianVehicle', true, true)
    for _, member in ipairs(members(leader)) do
        if member ~= source then exports.ob_vehiclekeys:GrantTemporaryKey(member, result.netId) end
    end
    broadcastJob(leader)
    return true, result
end)

local function nearTruck(source, vehicle)
    return vehicle ~= 0 and near(source, GetEntityCoords(vehicle), 6.0)
end

local function truckAtTask(job)
    local task = job and Electrician.tasks[job.task]
    local vehicle = vehicleEntity(job)
    return task and vehicle ~= 0 and #(GetEntityCoords(vehicle) - task.search) <= (Electrician.work.truckTaskDistance or 38.0)
end

local function canUseTools(source, job)
    local vehicle = vehicleEntity(job)
    return nearTruck(source, vehicle) and truckAtTask(job)
end

OR.Callback.register('orbis-electrician:server:takeTool', function(source, toolId)
    local job, leader = jobFor(source)
    if not job or job.repaired or job.toolHolder or job.busy then return false, 'Ferramenta indisponivel.' end
    if not canUseTools(source, job) then return false, 'Leve o caminhao ate a area do chamado e aproxime-se da lateral.' end
    if tonumber(toolId) ~= job.toolId then return false, ('Este chamado precisa de %s.'):format(Electrician.tools[job.toolId].label) end
    job.toolHolder = source
    broadcastJob(leader)
    return true
end)

OR.Callback.register('orbis-electrician:server:returnTool', function(source)
    local job, leader = jobFor(source)
    if not job or job.toolHolder ~= source or job.busy then return false, 'Voce nao esta com a ferramenta.' end
    if not canUseTools(source, job) then return false, 'Aproxime-se da lateral do caminhao no local do chamado.' end
    job.toolHolder = nil
    job.mustReturnTool = nil
    broadcastJob(leader)
    return true
end)

-- Cada integrante acumula cinco servicos. Marcar cada pagamento evita repetir
-- dinheiro para quem ja recebeu caso o inventario do parceiro esteja cheio.
local function payBatch(job, leader)
    for _, member in ipairs(members(leader)) do
        local reward = job.rewards[member]
        if reward and not reward.paid then
            local row = progressRow(member)
            if not exports.ob_inventory:AddItem(member, 'money', reward.money) then
                return false, 'Inventario sem espaco para o pagamento. Libere espaco e finalize o chamado novamente.'
            end
            reward.paid = true
            local xp = (tonumber(row.xp) or 0) + reward.xp
            OR.Database.update.await([[UPDATE ob_electrician_progress SET xp = ?, level = ?, repairs = repairs + ?,
                total_earned = total_earned + ? WHERE user_id = ?]], { xp, levelFromXp(xp), reward.count, reward.money, userId(member) })
            TriggerClientEvent('orbis-electrician:client:paid', member, reward.money, reward.xp)
        end
    end
    return true
end

OR.Callback.register('orbis-electrician:server:completeService', function(source)
    local job, leader = jobFor(source)
    if not job or not job.repaired or job.toolHolder or job.busy or job.completing then return false, 'Guarde a ferramenta antes de finalizar.' end
    if not canUseTools(source, job) then return false, 'Aproxime-se da lateral do caminhao no local do chamado.' end
    job.completing = true
    if job.repaired and not job.rewardCounted then
        job.rewardCounted = true
        job.completed, job.batchCompleted = job.completed + 1, job.batchCompleted + 1
        for _, member in ipairs(members(leader)) do
            local row = progressRow(member)
            local bonus = math.min((levelFromXp(row.xp) - 1) * Electrician.work.paymentBonusPerLevel, Electrician.work.maxPaymentBonus)
            local reward = job.rewards[member] or { money = 0, xp = 0, count = 0 }
            reward.money = reward.money + math.floor(math.random(Electrician.work.payment.min, Electrician.work.payment.max) * (1 + bonus))
            reward.xp, reward.count = reward.xp + Electrician.work.xpPerRepair, reward.count + 1
            job.rewards[member] = reward
        end
    end
    if job.batchCompleted >= Electrician.work.servicesPerBatch then
        local paid, message = payBatch(job, leader)
        if not paid then job.completing = nil; broadcastJob(leader); return false, message end
        job.batchCompleted, job.rewards = 0, {}
    end
    job.toolHolder, job.mustReturnTool, job.completing = nil, nil, nil
    if job.repaired then
        job.task = chooseTask(leader, job.task, job.invalidTasks)
        -- Mantem uma rota utilizavel quando so resta um local disponivel.
        if not job.task then
            for index, task in ipairs(Electrician.tasks) do
                if not job.invalidTasks[index] and (task.type ~= 'aerial' or groupSize(leader) >= 2) then job.task = index; break end
            end
        end
        job.stage = 1
        job.toolId, job.repaired, job.rewardCounted = Electrician.steps[1].tool, false, false
    end
    broadcastJob(leader)
    return true, ('Chamado concluido. Rota: %d/%d servicos.'):format(job.batchCompleted, Electrician.work.servicesPerBatch)
end)

OR.Callback.register('orbis-electrician:server:beginStep', function(source, stage)
    local job, leader = jobFor(source)
    local task = job and Electrician.tasks[job.task]
    stage = tonumber(stage)
    if not task or stage ~= job.stage or job.busy or job.repaired or job.toolHolder ~= source or job.mustReturnTool then return false, 'Guarde a ferramenta anterior e pegue a indicada para esta etapa.' end
    -- O cliente encaixa o marcador no prop de mapa carregado mais proximo da
    -- ancora. O servidor valida a mesma area, sem confiar na coordenada enviada.
    local repair = task.search + vector3(0, 0, task.zOffset or 0.75)
    if not near(source, repair, Electrician.work.interactionDistance + (task.searchRadius or 2.0)) then return false, 'Chegue ao ponto do reparo.' end
    local vehicle = vehicleEntity(job)
    if vehicle == 0 then return false, 'O caminhao do turno nao esta disponivel.' end
    if task.type == 'aerial' then
        if groupSize(leader) < 2 then return false, 'Esse servico exige uma dupla.' end
        if not aerialHasOperator(source, leader, vehicle) then return false, 'Seu parceiro precisa controlar a cesta no banco do motorista.' end
    end
    job.busy = source
    job.stepStarted = GetGameTimer()
    local started = job.stepStarted
    SetTimeout(Electrician.work.stepTimeoutMs + 5000, function()
        if jobs[leader] == job and job.busy == source and job.stepStarted == started then
            job.busy, job.stepStarted = nil, nil
            broadcastJob(leader)
        end
    end)
    return true
end)

OR.Callback.register('orbis-electrician:server:unavailableTask', function(source)
    if not OR.Security.rateLimit(source, 'electrician:unavailable', 2, 10000) then return false end
    local job, leader = jobFor(source)
    local task = job and Electrician.tasks[job.task]
    if not task or job.busy or job.repaired or job.toolHolder or not near(source, task.search, (task.searchRadius or 35.0) + 25.0) then return false end
    job.invalidTasks = job.invalidTasks or {}
    local nextTask = chooseTask(leader, job.task, job.invalidTasks)
    if not nextTask then return false, 'Nenhum outro local disponivel. Finalize o turno no encarregado.' end
    job.invalidTasks[job.task] = true
    job.task, job.stage = nextTask, 1
    job.toolId = Electrician.steps[1].tool
    broadcastJob(leader)
    return true
end)

OR.Callback.register('orbis-electrician:server:finishStep', function(source, stage, success)
    local job, leader = jobFor(source)
    stage = tonumber(stage)
    if not job or job.busy ~= source or stage ~= job.stage then return false, 'Etapa invalida.' end
    local elapsed = GetGameTimer() - (job.stepStarted or GetGameTimer())
    job.busy, job.stepStarted = nil, nil
    if success ~= true then return false, 'O procedimento falhou. Tente novamente.' end
    if elapsed < Electrician.work.minimumStepMs then return false, 'Procedimento concluido rapido demais.' end
    local task = Electrician.tasks[job.task]
    if GetEntityHealth(GetPlayerPed(source)) <= 0 then return false, 'Procedimento interrompido.' end
    if elapsed > Electrician.work.stepTimeoutMs then return false, 'Tempo do procedimento esgotado.' end
    if not near(source, task.search + vector3(0, 0, task.zOffset or 0.75), Electrician.work.interactionDistance + (task.searchRadius or 2)) then return false, 'Voce se afastou do reparo.' end
    if task.type == 'aerial' and not aerialHasOperator(source, leader, vehicleEntity(job)) then return false, 'O operador precisa permanecer no caminhao.' end
    if job.stage < #Electrician.steps then
        job.stage = job.stage + 1
        -- A ferramenta continua na mao ate ser devolvida ao caminhao.
        job.toolId = Electrician.steps[job.stage].tool
        job.mustReturnTool = true
        broadcastJob(leader)
        return true, false, publicJob(job)
    end
    job.repaired = true
    broadcastJob(leader)
    return true, true, publicJob(job)
end)

local function stopJob(leader, resourceStopping)
    local job = jobs[leader]
    if job and job.vehicleNetId then
        local vehicle = vehicleEntity(job)
        if vehicle ~= 0 then
            if resourceStopping then
                -- Nao espere um export que consulta o banco enquanto este
                -- runtime esta sendo destruido. O ob_core assume a limpeza.
                TriggerEvent('ob_core:server:deleteTemporaryVehicleDetached', leader, job.vehicleNetId)
            elseif not exports.ob_core:DeleteTemporaryVehicle(leader, job.vehicleNetId) then
                DeleteEntity(vehicle)
            end
        end
    end
    jobs[leader] = nil
    for _, member in ipairs(members(leader)) do TriggerClientEvent('orbis-electrician:client:jobSync', member, { active = false }) end
end

OR.Callback.register('orbis-electrician:server:stopJob', function(source)
    local job, leader = jobFor(source)
    if source ~= leader then return false, 'Somente o lider pode finalizar o turno.' end
    if job and (job.completing or job.busy or job.spawning) then return false, 'Aguarde terminar o procedimento atual.' end
    stopJob(leader)
    return true
end)

OR.Callback.register('orbis-electrician:server:invite', function(source, target)
    if not OR.Security.rateLimit(source, 'electrician:invite', 3, 10000) then return false, 'Aguarde antes de convidar novamente.' end
    target = tonumber(target)
    local leader, group = getGroup(source, true)
    if source ~= leader or jobs[leader] then return false, 'O grupo nao pode ser alterado agora.' end
    if not target or target == source or not playerExists(target) then return false, 'Jogador indisponivel.' end
    local targetLeader, targetGroup = getGroup(target, false)
    if targetGroup and groupSize(targetLeader) == 1 and not jobs[targetLeader] then
        groups[targetLeader], memberGroup[target] = nil, nil
    elseif memberGroup[target] then
        return false, 'Jogador indisponivel.'
    end
    if groupSize(leader) >= Electrician.group.maxMembers then return false, 'A dupla ja esta completa.' end
    if not near(target, GetEntityCoords(GetPlayerPed(source)), Electrician.group.inviteDistance) then return false, 'O jogador precisa estar proximo.' end
    invites[target] = { leader = leader, expires = os.time() + Electrician.group.inviteSeconds }
    TriggerClientEvent('orbis-electrician:client:invite', target, GetPlayerName(source) or ('ID %s'):format(source))
    return true, 'Convite enviado.'
end)

OR.Callback.register('orbis-electrician:server:answerInvite', function(source, accept)
    local invite = invites[source]
    invites[source] = nil
    if not invite or invite.expires < os.time() or not groups[invite.leader] then return false, 'Convite expirado.' end
    if not accept then return true, 'Convite recusado.' end
    if memberGroup[source] or jobs[invite.leader] or groupSize(invite.leader) >= Electrician.group.maxMembers then return false, 'A dupla nao esta mais disponivel.' end
    groups[invite.leader].members[source], memberGroup[source] = true, invite.leader
    broadcastGroup(invite.leader)
    return true, 'Voce entrou na dupla de eletricistas.'
end)

OR.Callback.register('orbis-electrician:server:leaveGroup', function(source)
    local leader, group = getGroup(source, false)
    if not group then return true end
    if jobs[leader] then return false, 'Finalize o turno antes de sair da dupla.' end
    if source == leader then
        for _, member in ipairs(members(leader)) do memberGroup[member] = nil; TriggerClientEvent('orbis-electrician:client:groupUpdated', member, groupPayload(member)) end
        groups[leader] = nil
    else
        group.members[source], memberGroup[source] = nil, nil
        TriggerClientEvent('orbis-electrician:client:groupUpdated', source, groupPayload(source))
        broadcastGroup(leader)
    end
    return true, 'Voce saiu da dupla.'
end)

AddEventHandler('playerDropped', function()
    local source = source
    invites[source] = nil
    local leader, group = getGroup(source, false)
    if jobs[leader] then stopJob(leader) end
    if group then
        for _, member in ipairs(members(leader)) do memberGroup[member] = nil; TriggerClientEvent('orbis-electrician:client:groupUpdated', member, groupPayload(member)) end
        groups[leader] = nil
    end
    memberGroup[source] = nil
end)

-- Libera a ferramenta e a etapa quando o portador morre sem desconectar.
CreateThread(function()
    while true do
        Wait(1000)
        for leader, job in pairs(jobs) do
            local changed = false
            local function incapacitated(member)
                if not member then return false end
                local ped = GetPlayerPed(member)
                return ped == 0 or GetEntityHealth(ped) <= 0
            end
            if incapacitated(job.toolHolder) then
                job.toolHolder, job.mustReturnTool, job.busy, job.stepStarted = nil, nil, nil, nil
                changed = true
            end
            if changed then broadcastJob(leader) end
        end
    end
end)

CreateThread(function()
    if not OR.Database.waitForReady(30000) then return print('[ob_electricianjob] Banco indisponivel.') end
    local columnType, deadline = nil, GetGameTimer() + 30000
    repeat
        -- Nao chame um export do ob_core que aguarda uma resposta assincrona:
        -- a coroutine seria retomada pelo ob_database dentro de outro resource
        -- e o host pode rejeitar essa referencia. Consulte no contexto daqui.
        local row, queryError = OR.Database.single.await([[SELECT column_type
            FROM information_schema.COLUMNS
            WHERE table_schema = DATABASE() AND table_name = 'ob_characters' AND column_name = 'user_id'
            LIMIT 1]])
        if queryError then
            return print(('[ob_electricianjob] Falha ao ler tipo do personagem: %s'):format(queryError))
        end
        local candidate = row and tostring(row.column_type or ''):lower():gsub('%s+', ' ') or ''
        local validTypes = {
            ['tinyint'] = true, ['tinyint unsigned'] = true,
            ['smallint'] = true, ['smallint unsigned'] = true,
            ['mediumint'] = true, ['mediumint unsigned'] = true,
            ['int'] = true, ['int unsigned'] = true,
            ['bigint'] = true, ['bigint unsigned'] = true,
        }
        local normalized = candidate:gsub('%(%d+%)', '')
        if validTypes[normalized] then columnType = normalized:upper() end
        if not columnType then Wait(250) end
    until columnType or GetGameTimer() >= deadline
    if not columnType then return print('[ob_electricianjob] Tipo de personagem indisponivel.') end
    local created, errorMessage = OR.Database.query.await(([[CREATE TABLE IF NOT EXISTS ob_electrician_progress (
        user_id %s NOT NULL PRIMARY KEY, xp INT NOT NULL DEFAULT 0, level INT NOT NULL DEFAULT 1,
        repairs INT NOT NULL DEFAULT 0, total_earned INT NOT NULL DEFAULT 0,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        CONSTRAINT fk_ob_electrician_character FOREIGN KEY (user_id) REFERENCES ob_characters(user_id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]]):format(columnType))
    databaseReady = created ~= nil
    if not databaseReady then print(('[ob_electricianjob] Falha na tabela: %s'):format(errorMessage or 'desconhecida')) end
end)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for leader in pairs(jobs) do stopJob(leader, true) end
end)
