local activeJobs = {}
local cowCooldowns = {}
local groups = {}
local memberGroup = {}
local pendingInvites = {}
local databaseReady = false

local function characterIdColumnType()
    local deadline = GetGameTimer() + 30000
    repeat
        local columnType = exports.ob_core:GetCharacterIdColumnType()
        if columnType then return columnType end
        Wait(100)
    until GetGameTimer() >= deadline
end

local function getUserId(src)
    return exports.ob_core:GetUserId(src)
end

local function getLeader(src)
    return memberGroup[src] or src
end

local function getGroup(src, create)
    local leader = getLeader(src)
    local group = groups[leader]
    if not group and create then
        group = { leader = leader, members = { [leader] = true } }
        groups[leader] = group
        memberGroup[leader] = leader
    end
    return leader, group
end

local function groupSources(leader)
    local group,result=groups[leader],{}
    if not group then return { leader } end
    for member in pairs(group.members) do
        if getUserId(member) then result[#result+1]=member
        else group.members[member]=nil;memberGroup[member]=nil end
    end
    return result
end

local function groupSize(leader)
    return #groupSources(leader)
end

local function groupPayload(src)
    local leader,group=getGroup(src,false)
    if not group then
        return {leader=src,isLeader=true,maxMembers=Leiteiro.group.maxMembers,
            members={{id=src,name=GetPlayerName(src) or ('ID %s'):format(src),leader=true}}}
    end
    local members={}
    for _,member in ipairs(groupSources(leader)) do
        members[#members+1]={id=member,name=GetPlayerName(member) or ('ID %s'):format(member),leader=member==leader}
    end
    return {leader=leader,isLeader=src==leader,maxMembers=Leiteiro.group.maxMembers,members=members}
end

local function broadcastGroup(leader)
    for _,member in ipairs(groupSources(leader)) do
        TriggerClientEvent('orbis-leiteiro:client:groupUpdated',member,groupPayload(member))
    end
end

local function groupHasActiveJob(leader)
    for _,member in ipairs(groupSources(leader)) do
        if activeJobs[member] and activeJobs[member].active then return true end
    end
    return false
end

local function getLevelFromXp(xp)
    local progress = Leiteiro.progress
    return math.min(math.floor((tonumber(xp) or 0) / progress.levelStep) + 1, progress.maxLevel)
end

local function ensureProgress(userId)
    userId = tonumber(userId)
    if not databaseReady or not userId then return nil end
    OR.Database.update.await('INSERT IGNORE INTO ob_leiteiro_progress (user_id) VALUES (?)', { userId })
    local row = OR.Database.single.await('SELECT * FROM ob_leiteiro_progress WHERE user_id = ?', { userId })
    if not row then return nil end
    local expectedLevel = getLevelFromXp(row.xp)
    if row.level ~= expectedLevel then
        row.level = expectedLevel
        OR.Database.update.await('UPDATE ob_leiteiro_progress SET level = ? WHERE user_id = ?', { expectedLevel, userId })
    end
    return row
end

local function notify(src, msg, typ)
    TriggerClientEvent('ob_notification:client:notify', src, msg, typ or 'info')
end

local function getJob(src)
    activeJobs[src] = activeJobs[src] or {
        active = false,
        pendingPayment = 0,
        deliveredBoxes = 0,
        vehicleBoxes = 0,
        machineBox = false,
        carryingBox = false,
        deliveryCarry = false,
        deliveryIndex = nil,
        deliveryRemaining = 0,
        lastDeliveryIndex = nil,
        vehicleNetId = nil,
        userId = nil,
        contractTarget = 0,
        contractDelivered = 0,
        contractComplete = false
    }

    return activeJobs[src]
end

local function getCowCooldowns(src)
    local key=getLeader(src)
    cowCooldowns[key] = cowCooldowns[key] or {}
    return cowCooldowns[key]
end

local function getDeliveryCoords(index)
    local locations = Leiteiro.delivery.locations or {}
    return locations[index or 0] or Leiteiro.delivery.coords
end

local function chooseDeliveryIndex(job)
    local locations = Leiteiro.delivery.locations or {}
    if job.deliveryIndex and (job.deliveryRemaining or 0) > 0 then
        return job.deliveryIndex
    end

    if #locations < 1 then
        job.deliveryIndex = 1
    else
        local index = math.random(#locations)
        if #locations > 1 then
            while index == job.lastDeliveryIndex do
                index = math.random(#locations)
            end
        end

        job.deliveryIndex = index
    end

    local boxesPerStore = Leiteiro.delivery.boxesPerStore or {}
    local minBoxes = tonumber(boxesPerStore.min) or 2
    local maxBoxes = tonumber(boxesPerStore.max) or 4
    if maxBoxes < minBoxes then maxBoxes = minBoxes end
    job.deliveryRemaining = math.random(minBoxes, maxBoxes)

    return job.deliveryIndex
end

local function paymentPerBox()
    local payment = Leiteiro.job.paymentPerBox
    if type(payment) == 'table' then
        local minPayment = tonumber(payment.min) or 430
        local maxPayment = tonumber(payment.max) or minPayment
        if maxPayment < minPayment then maxPayment = minPayment end
        return math.random(minPayment, maxPayment)
    end

    return tonumber(payment) or 0
end

local function buildProgress(row)
    local progress = Leiteiro.progress
    local level = row.level or 1
    local levelBase = (level - 1) * progress.levelStep
    return {
        xp = row.xp or 0,
        level = level,
        xpInLevel = (row.xp or 0) - levelBase,
        xpRequired = progress.levelStep,
        boxesDelivered = row.boxes_delivered or 0,
        totalEarned = row.total_earned or 0,
        paymentBonus = math.min((level - 1) * progress.paymentBonusPerLevel, progress.maxPaymentBonus)
    }
end

local function buildContract(job, row)
    local cfg = Leiteiro.progress.contract
    local unlocked = (row.level or 1) >= cfg.minimumLevel
    return {
        unlocked = unlocked,
        target = job.contractTarget or 0,
        delivered = job.contractDelivered or 0,
        complete = job.contractComplete == true,
        bonus = cfg.completionBonus or 0
    }
end

local function leaderboard(userId, row)
    local rows = OR.Database.query.await([[SELECT l.user_id, l.xp, l.boxes_delivered, p.firstname, p.lastname
        FROM ob_leiteiro_progress l LEFT JOIN ob_characters p ON p.user_id = l.user_id
        ORDER BY l.xp DESC, l.boxes_delivered DESC, l.user_id ASC LIMIT 10]]) or {}
    local list = {}
    for rank, entry in ipairs(rows) do
        list[#list + 1] = { rank = rank, name = ((entry.firstname or '') .. ' ' .. (entry.lastname or '')):gsub('^%s*(.-)%s*$', '%1'), xp = entry.xp or 0, boxes = entry.boxes_delivered or 0 }
    end
    local higher = OR.Database.scalar.await([[SELECT COUNT(*) FROM ob_leiteiro_progress
        WHERE xp > ? OR (xp = ? AND boxes_delivered > ?) OR (xp = ? AND boxes_delivered = ? AND user_id < ?)]], { row.xp or 0, row.xp or 0, row.boxes_delivered or 0, row.xp or 0, row.boxes_delivered or 0, userId })
    return { list = list, myRank = (tonumber(higher) or 0) + 1, myValue = row.xp or 0 }
end

local function panelData(source)
    local job = getJob(source)
    local userId = getUserId(source)
    local row = ensureProgress(userId)
    if not row then return nil end
    return { progress = buildProgress(row), contract = buildContract(job, row),
        work = { active = job.active, boxes = job.vehicleBoxes or 0, pending = job.pendingPayment or 0, destination = job.deliveryIndex ~= nil },
        group = groupPayload(source), leaderboard = leaderboard(userId, row) }
end

local function isNear(src, coords, distance)
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end

    return #(GetEntityCoords(ped) - coords) <= distance
end

local function addMoney(src, amount)
    if amount <= 0 then return true end
    return exports.ob_inventory:AddItem(src, 'money', amount)
end

local function canCarry(src, item, amount)
    return exports.ob_inventory:CanCarryItem(src, item, amount)
end

local function itemCount(src, item)
    return exports.ob_inventory:GetItemCount(src, item) or 0
end

local function clearEmptyBuckets(src)
    local emptyBuckets = itemCount(src, Leiteiro.items.bucket)
    if emptyBuckets > 0 then
        exports.ob_inventory:RemoveItem(src, Leiteiro.items.bucket, emptyBuckets)
    end
end

local function hasValidVehicle(job)
    if not job.vehicleNetId then return false end

    local vehicle = NetworkGetEntityFromNetworkId(job.vehicleNetId)
    return vehicle ~= 0 and DoesEntityExist(vehicle)
end

local function canMilkCow(src, cowId, shouldNotify)
    local job = getJob(src)
    if not job.active then
        if shouldNotify then notify(src, 'Inicie o trabalho de leiteiro primeiro.', 'error') end
        return false
    end

    cowId = tonumber(cowId)
    local cowCoords = cowId and Leiteiro.cows[cowId]
    if not cowCoords then return false end

    if not isNear(src, cowCoords.xyz, 8.0) then
        if shouldNotify then notify(src, 'Voce esta longe desta vaca.', 'error') end
        return false
    end

    local now = os.time()
    local playerCooldowns = getCowCooldowns(src)
    if playerCooldowns[cowId] and playerCooldowns[cowId] > now then
        local remaining = playerCooldowns[cowId] - now
        if shouldNotify then
            notify(src, ('Esta vaca ainda nao tem leite. Aguarde %s segundos.'):format(remaining), 'inform')
        end
        return false, remaining
    end

    if itemCount(src, Leiteiro.items.bucket) < 1 then
        if shouldNotify then notify(src, 'Voce precisa de um balde vazio.', 'error') end
        return false
    end

    if not canCarry(src, Leiteiro.items.rawMilk, 1) then
        if shouldNotify then notify(src, 'Sem espaco na mochila.', 'error') end
        return false
    end

    return true, 0
end

local function canProcessMilk(src, shouldNotify)
    local job = getJob(src)
    if not job.active then
        if shouldNotify then notify(src, 'Inicie o trabalho de leiteiro primeiro.', 'error') end
        return false
    end

    if not isNear(src, Leiteiro.process.coords, 6.0) then
        if shouldNotify then notify(src, 'Voce esta longe do envase.', 'error') end
        return false
    end

    if not hasValidVehicle(job) then
        if shouldNotify then notify(src, 'Pegue o caminhao com o responsavel antes de usar a maquina.', 'error') end
        return false
    end

    if job.machineBox then
        if shouldNotify then notify(src, 'Retire a caixa pronta da maquina antes de processar outra.', 'error') end
        return false
    end

    if job.carryingBox then
        if shouldNotify then notify(src, 'Coloque a caixa que voce esta carregando no veiculo primeiro.', 'error') end
        return false
    end

    if job.deliveryCarry then
        if shouldNotify then notify(src, 'Entregue a caixa que voce esta carregando primeiro.', 'error') end
        return false
    end

    local neededRaw = tonumber(Leiteiro.job.rawMilkPerBox) or 2
    if itemCount(src, Leiteiro.items.rawMilk) < neededRaw then
        if shouldNotify then
            notify(src, ('Voce precisa de %s baldes de leite para fazer uma caixa.'):format(neededRaw), 'error')
        end
        return false
    end

    return true
end

OR.Callback.register('orbis-leiteiro:server:getStatus', function(source)
    local job = getJob(source)
    local row = ensureProgress(getUserId(source)) or { xp = 0, level = 1, boxes_delivered = 0, total_earned = 0 }

    return {
        active = job.active,
        pendingPayment = job.pendingPayment,
        deliveredBoxes = job.deliveredBoxes,
        vehicleBoxes = job.vehicleBoxes,
        machineBox = job.machineBox,
        carryingBox = job.carryingBox,
        deliveryCarry = job.deliveryCarry,
        deliveryIndex = job.deliveryIndex,
        deliveryRemaining = job.deliveryRemaining,
        progress = buildProgress(row),
        contract = buildContract(job, row)
    }
end)

OR.Callback.register('orbis-leiteiro:server:getPanelData', function(source)
    return panelData(source)
end)

OR.Callback.register('orbis-leiteiro:server:startJob', function(source)
    local leader,group=getGroup(source,true)
    if source~=leader then return false,'Somente o lider pode iniciar o trabalho do grupo.' end
    if groupHasActiveJob(leader) then return false,'O trabalho do grupo ja foi iniciado.' end
    local members=groupSources(leader)
    local bucketAmount = tonumber(Leiteiro.job.startBuckets) or 0
    local prepared={}
    for _,member in ipairs(members) do
        local userId=getUserId(member)
        local row=ensureProgress(userId)
        if not row then return false,'Um integrante esta com o personagem ou banco indisponivel.' end
        local missing=math.max(0,bucketAmount-itemCount(member,Leiteiro.items.bucket))
        if missing>0 and not canCarry(member,Leiteiro.items.bucket,missing) then
            return false,('O integrante %s esta sem espaco para receber %s baldes.'):format(GetPlayerName(member) or member,bucketAmount)
        end
        prepared[#prepared+1]={source=member,userId=userId,row=row,missing=missing}
    end
    local added={}
    for _,entry in ipairs(prepared) do
        if entry.missing>0 then
            local ok=exports.ob_inventory:AddItem(entry.source,Leiteiro.items.bucket,entry.missing)
            if not ok then
                for _,rollback in ipairs(added) do exports.ob_inventory:RemoveItem(rollback.source,Leiteiro.items.bucket,rollback.amount) end
                return false,'Nao foi possivel entregar os baldes para todo o grupo.'
            end
            added[#added+1]={source=entry.source,amount=entry.missing}
        end
    end
    cowCooldowns[leader]={}
    for _,entry in ipairs(prepared) do
        local job=getJob(entry.source)
        job.active=true;job.machineBox=false;job.carryingBox=false;job.deliveryCarry=false
        job.deliveryIndex=nil;job.deliveryRemaining=0;job.vehicleBoxes=0;job.vehicleNetId=nil
        job.userId=entry.userId;job.contractDelivered=0;job.contractComplete=false
        job.contractTarget=(entry.row.level or 1)>=Leiteiro.progress.contract.minimumLevel
            and math.random(Leiteiro.progress.contract.targetBoxes.min,Leiteiro.progress.contract.targetBoxes.max) or 0
        if entry.source~=source then TriggerClientEvent('orbis-leiteiro:client:groupJobStarted',entry.source,bucketAmount) end
    end
    broadcastGroup(leader)
    return true,nil,#members
end)

OR.Callback.register('orbis-leiteiro:server:stopJob', function(source)
    local leader=getLeader(source)
    if source~=leader then return false,'Somente o lider pode finalizar o trabalho do grupo.' end
    for _,member in ipairs(groupSources(leader)) do
        local job=getJob(member)
        if job.vehicleNetId then exports.ob_core:DeleteTemporaryVehicle(member,job.vehicleNetId) end
        job.active=false;job.vehicleNetId=nil;job.vehicleBoxes=0;job.machineBox=false
        job.carryingBox=false;job.deliveryCarry=false;job.deliveryIndex=nil;job.deliveryRemaining=0
        job.contractTarget=0;job.contractDelivered=0;job.contractComplete=false
        clearEmptyBuckets(member)
        if member~=source then TriggerClientEvent('orbis-leiteiro:client:groupJobStopped',member) end
    end
    cowCooldowns[leader]=nil
    return true
end)

OR.Callback.register('orbis-leiteiro:server:spawnVehicle', function(source)
    local job = getJob(source)
    if not job.active then return false, 'Inicie o trabalho primeiro.' end
    if hasValidVehicle(job) then return false, 'Voce ja retirou o veiculo do trabalho.' end
    local spawned, result = exports.ob_core:SpawnTemporaryVehicle(source, Leiteiro.vehicle.model, Leiteiro.vehicle.spawn, {
        platePrefix = Leiteiro.vehicle.platePrefix or 'LEITE',
        fuel = 100.0,
        clearRadius = Leiteiro.vehicle.spawnClearRadius or 4.0,
        maxDistance = 100.0,
        serverSetterType = 'automobile',
    })
    if not spawned then return false, result end
    job.vehicleNetId = result.netId
    return true, result
end)

OR.Callback.register('orbis-leiteiro:server:canMilkCow', function(source, cowId)
    return canMilkCow(source, cowId, true)
end)

OR.Callback.register('orbis-leiteiro:server:canProcessMilk', function(source)
    return canProcessMilk(source, true)
end)

OR.Callback.register('orbis-leiteiro:server:requestBuckets', function(source)
    local job = getJob(source)
    if not job.active then
        notify(source, 'Inicie o trabalho de leiteiro primeiro.', 'error')
        return false
    end

    if not isNear(source, Leiteiro.npc.coords.xyz, 6.0) then
        notify(source, 'Volte ao responsavel para pegar mais baldes.', 'error')
        return false
    end

    if itemCount(source, Leiteiro.items.bucket) > 0 then
        notify(source, 'Voce ainda tem balde vazio no inventario.', 'error')
        return false
    end

    local bucketAmount = tonumber(Leiteiro.job.startBuckets) or 4
    if not canCarry(source, Leiteiro.items.bucket, bucketAmount) then
        notify(source, 'Sem espaco na mochila.', 'error')
        return false
    end

    if not exports.ob_inventory:AddItem(source, Leiteiro.items.bucket, bucketAmount) then
        notify(source, 'Nao foi possivel entregar os baldes agora.', 'error')
        return false
    end

    local leader=getLeader(source)
    local resetCooldown=groupSize(leader)<=1
    if resetCooldown then cowCooldowns[leader]={} end
    notify(source,resetCooldown and ('Voce recebeu %s baldes. As vacas ja podem ser ordenhadas novamente.'):format(bucketAmount)
        or ('Voce recebeu %s baldes. O tempo das vacas continua compartilhado com a dupla.'):format(bucketAmount),'success')
    return true,bucketAmount,resetCooldown
end)

OR.Callback.register('orbis-leiteiro:server:milkCow', function(source, cowId)
    if not OR.Security.rateLimit(source, 'milkman:milk_cow', 1, math.max(1000, tonumber(Leiteiro.job.milkTimeMs) or 12000)) then return false end
    cowId = tonumber(cowId)
    if not canMilkCow(source, cowId, true) then
        return false
    end

    if not exports.ob_inventory:RemoveItem(source, Leiteiro.items.bucket, 1) then
        return false
    end

    local added = exports.ob_inventory:AddItem(source, Leiteiro.items.rawMilk, 1)
    if not added then return false end
    local expires=os.time()+(tonumber(Leiteiro.job.milkCooldownSeconds) or 300)
    getCowCooldowns(source)[cowId]=expires
    local leader=getLeader(source)
    for _,member in ipairs(groupSources(leader)) do
        TriggerClientEvent('orbis-leiteiro:client:cowCooldown',member,cowId,expires-os.time())
    end
    return true
end)

OR.Callback.register('orbis-leiteiro:server:processMilk', function(source)
    if not OR.Security.rateLimit(source, 'milkman:process_milk', 1, math.max(1000, tonumber(Leiteiro.job.processTimeMs) or 7000)) then return false end
    if not canProcessMilk(source, true) then
        return false
    end

    local job = getJob(source)
    local neededRaw = tonumber(Leiteiro.job.rawMilkPerBox) or 2

    if not exports.ob_inventory:RemoveItem(source, Leiteiro.items.rawMilk, neededRaw) then
        return false
    end

    job.machineBox = true
    return true, 1
end)

OR.Callback.register('orbis-leiteiro:server:pickupMachineBox', function(source)
    local job = getJob(source)
    if not job.active then
        notify(source, 'Inicie o trabalho de leiteiro primeiro.', 'error')
        return false
    end

    if not isNear(source, Leiteiro.process.coords, 6.0) then
        notify(source, 'Voce esta longe da maquina.', 'error')
        return false
    end

    if not job.machineBox then
        notify(source, 'Nao tem caixa pronta na maquina.', 'error')
        return false
    end

    if not hasValidVehicle(job) then
        notify(source, 'Pegue o caminhao com o responsavel antes de retirar a caixa.', 'error')
        return false
    end

    if job.carryingBox then
        notify(source, 'Voce ja esta carregando uma caixa.', 'error')
        return false
    end

    if job.deliveryCarry then
        notify(source, 'Entregue a caixa que voce esta carregando primeiro.', 'error')
        return false
    end

    job.machineBox = false
    job.carryingBox = true
    return true
end)

OR.Callback.register('orbis-leiteiro:server:loadVehicleBoxes', function(source)
    local job = getJob(source)
    if not job.active then
        notify(source, 'Inicie o trabalho de leiteiro primeiro.', 'error')
        return false
    end

    if not job.vehicleNetId then
        notify(source, 'Retire o veiculo de entrega primeiro.', 'error')
        return false
    end

    local vehicle = NetworkGetEntityFromNetworkId(job.vehicleNetId)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        notify(source, 'O veiculo do leiteiro nao foi encontrado.', 'error')
        return false
    end

    local ped = GetPlayerPed(source)
    if ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > (Leiteiro.vehicle.loadDistance or 5.0) + 3.0 then
        notify(source, 'Chegue mais perto do veiculo para carregar.', 'error')
        return false
    end

    if not job.carryingBox then
        notify(source, 'Pegue uma caixa pronta na maquina primeiro.', 'error')
        return false
    end

    local maxBoxes = tonumber(Leiteiro.vehicle.maxBoxes) or 80
    local availableSpace = math.max(0, maxBoxes - (job.vehicleBoxes or 0))
    if availableSpace < 1 then
        notify(source, 'O veiculo ja esta cheio de caixas.', 'error')
        return false
    end

    local deliveryIndex = chooseDeliveryIndex(job)
    job.carryingBox = false
    job.vehicleBoxes = (job.vehicleBoxes or 0) + 1
    return true, 1, job.vehicleBoxes, deliveryIndex, job.deliveryRemaining
end)

OR.Callback.register('orbis-leiteiro:server:pickupDeliveryBox', function(source)
    local job = getJob(source)
    if not job.active then
        notify(source, 'Inicie o trabalho de leiteiro primeiro.', 'error')
        return false
    end

    local deliveryCoords = getDeliveryCoords(job.deliveryIndex)
    if not isNear(source, deliveryCoords, 25.0) then
        notify(source, 'Voce esta longe do local de entrega.', 'error')
        return false
    end

    if not job.vehicleNetId then
        notify(source, 'O veiculo do leiteiro nao foi encontrado.', 'error')
        return false
    end

    local vehicle = NetworkGetEntityFromNetworkId(job.vehicleNetId)
    if vehicle == 0 or not DoesEntityExist(vehicle) or #(GetEntityCoords(vehicle) - deliveryCoords) > 20.0 then
        notify(source, 'Estacione o veiculo do leiteiro perto da entrega.', 'error')
        return false
    end

    local ped = GetPlayerPed(source)
    if ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > (Leiteiro.vehicle.loadDistance or 5.0) + 3.0 then
        notify(source, 'Chegue mais perto do veiculo para retirar a caixa.', 'error')
        return false
    end

    if job.carryingBox or job.deliveryCarry then
        notify(source, 'Voce ja esta carregando uma caixa.', 'error')
        return false
    end

    local amount = job.vehicleBoxes or 0
    local minAmount = tonumber(Leiteiro.job.minBoxesToDeliver) or 1
    if amount < minAmount then
        notify(source, 'O veiculo nao tem caixas de leite para entregar.', 'error')
        return false
    end

    job.vehicleBoxes = amount - 1
    job.deliveryCarry = true
    return true, job.vehicleBoxes, job.deliveryIndex, job.deliveryRemaining
end)

OR.Callback.register('orbis-leiteiro:server:deliverMilk', function(source)
    local job = getJob(source)
    if not job.active then
        notify(source, 'Inicie o trabalho de leiteiro primeiro.', 'error')
        return false
    end

    local deliveryCoords = getDeliveryCoords(job.deliveryIndex)
    if not isNear(source, deliveryCoords, 8.0) then
        notify(source, 'Voce esta longe do local de entrega.', 'error')
        return false
    end

    if not job.deliveryCarry then
        notify(source, 'Retire uma caixa do veiculo antes de entregar.', 'error')
        return false
    end

    local userId = getUserId(source)
    local row = ensureProgress(userId)
    if not row then return false, 'Progresso indisponivel.' end
    local basePayment = paymentPerBox()
    local paymentBonus = math.min(((row.level or 1) - 1) * Leiteiro.progress.paymentBonusPerLevel, Leiteiro.progress.maxPaymentBonus)
    local payment = math.floor(basePayment * (1 + paymentBonus))
    local xp = Leiteiro.progress.xpPerBox
    local newXp = (row.xp or 0) + xp
    local newLevel = getLevelFromXp(newXp)
    job.deliveryCarry = false
    job.pendingPayment = job.pendingPayment + payment
    job.deliveredBoxes = job.deliveredBoxes + 1
    if (job.contractTarget or 0) > 0 then
        job.contractDelivered = (job.contractDelivered or 0) + 1
        job.contractComplete = job.contractDelivered >= job.contractTarget
    end
    OR.Database.update.await([[UPDATE ob_leiteiro_progress
        SET xp = ?, level = ?, boxes_delivered = boxes_delivered + 1 WHERE user_id = ?
    ]], { newXp, newLevel, userId })

    job.deliveryRemaining = math.max(0, (job.deliveryRemaining or 0) - 1)
    if job.deliveryRemaining <= 0 then
        job.lastDeliveryIndex = job.deliveryIndex
        job.deliveryIndex = nil
        job.deliveryRemaining = 0
    end

    if job.vehicleBoxes > 0 and not job.deliveryIndex then
        chooseDeliveryIndex(job)
    end

    local progress = buildProgress({ xp = newXp, level = newLevel, boxes_delivered = (row.boxes_delivered or 0) + 1, total_earned = row.total_earned or 0 })
    notify(source, ('Entrega feita. Volte ao responsavel para receber %s.'):format(OR.FormatMoney(payment)), 'success')
    return true, payment, job.vehicleBoxes, job.deliveryIndex, job.deliveryRemaining, progress, buildContract(job, { level = newLevel })
end)

OR.Callback.register('orbis-leiteiro:server:claimPayment', function(source)
    local job = getJob(source)
    if job.pendingPayment <= 0 then
        notify(source, 'Voce nao tem pagamento pendente.', 'error')
        return false
    end

    if not isNear(source, Leiteiro.npc.coords.xyz, 6.0) then
        notify(source, 'Volte ao responsavel para receber.', 'error')
        return false
    end

    local userId = getUserId(source)
    if not userId then return false end
    local payment = job.pendingPayment
    local contractBonus = 0
    if job.contractComplete then
        contractBonus = math.floor(payment * (Leiteiro.progress.contract.completionBonus or 0))
        payment = payment + contractBonus
    end
    if not addMoney(source, payment) then
        notify(source, 'Nao foi possivel pagar agora.', 'error')
        return false
    end

    job.pendingPayment = 0
    job.deliveredBoxes = 0
    OR.Database.update.await('UPDATE ob_leiteiro_progress SET total_earned = total_earned + ? WHERE user_id = ?', { payment, userId })
    if contractBonus > 0 then
        notify(source, ('Voce recebeu %s, incluindo %s do contrato de entrega.'):format(OR.FormatMoney(payment), OR.FormatMoney(contractBonus)), 'success')
    else
        notify(source, ('Voce recebeu %s pelo leite entregue.'):format(OR.FormatMoney(payment)), 'success')
    end
    return true, payment, contractBonus
end)

OR.Callback.register('orbis-leiteiro:server:inviteMember',function(source,targetSource)
    if not OR.Security.rateLimit(source,'milkman:group_invite',3,10000) then return false,'Aguarde antes de convidar novamente.' end
    targetSource=tonumber(targetSource)
    local leader,group=getGroup(source,true)
    if source~=leader then return false,'Somente o lider pode convidar.' end
    if groupHasActiveJob(leader) then return false,'Finalize o trabalho antes de alterar o grupo.' end
    if not targetSource or targetSource==source or not getUserId(targetSource) then return false,'Jogador invalido.' end
    local targetLeader,targetGroup=getGroup(targetSource,false)
    if targetGroup and groupSize(targetLeader)==1 and not groupHasActiveJob(targetLeader) then
        groups[targetLeader]=nil;memberGroup[targetSource]=nil
    elseif memberGroup[targetSource] then return false,'Esse jogador ja esta em um grupo.' end
    if groupSize(leader)>=(Leiteiro.group.maxMembers or 2) then return false,'O grupo ja esta cheio.' end
    local leaderPed,targetPed=GetPlayerPed(source),GetPlayerPed(targetSource)
    if leaderPed==0 or targetPed==0 or #(GetEntityCoords(leaderPed)-GetEntityCoords(targetPed))>(Leiteiro.group.inviteDistance or 18.0) then
        return false,'O jogador precisa estar proximo.'
    end
    pendingInvites[targetSource]={leader=leader,expires=os.time()+(Leiteiro.group.inviteSeconds or 30)}
    TriggerClientEvent('orbis-leiteiro:client:groupInvite',targetSource,{name=GetPlayerName(source) or ('ID %s'):format(source)})
    return true,'Convite enviado.'
end)

OR.Callback.register('orbis-leiteiro:server:answerInvite',function(source,accept)
    local invite=pendingInvites[source];pendingInvites[source]=nil
    local group=invite and groups[invite.leader]
    if not invite or invite.expires<os.time() or not group then return false,'Convite expirado.' end
    if not accept then return true,'Convite recusado.' end
    if memberGroup[source] or groupHasActiveJob(invite.leader) or groupSize(invite.leader)>=(Leiteiro.group.maxMembers or 2) then
        return false,'Grupo indisponivel.'
    end
    local leaderPed,targetPed=GetPlayerPed(invite.leader),GetPlayerPed(source)
    if leaderPed==0 or targetPed==0 or #(GetEntityCoords(leaderPed)-GetEntityCoords(targetPed))>(Leiteiro.group.inviteDistance or 18.0) then
        return false,'Aproxime-se do lider para entrar no grupo.'
    end
    group.members[source]=true;memberGroup[source]=invite.leader
    broadcastGroup(invite.leader)
    return true,'Voce entrou no grupo de leiteiros.'
end)

OR.Callback.register('orbis-leiteiro:server:leaveGroup',function(source)
    local leader,group=getGroup(source,false)
    if not group then return true end
    if groupHasActiveJob(leader) then return false,'Finalize o trabalho antes de sair do grupo.' end
    if source==leader then
        local members=groupSources(leader)
        groups[leader]=nil
        for _,member in ipairs(members) do
            memberGroup[member]=nil
            TriggerClientEvent('orbis-leiteiro:client:groupUpdated',member,groupPayload(member))
        end
    else
        group.members[source]=nil;memberGroup[source]=nil
        TriggerClientEvent('orbis-leiteiro:client:groupUpdated',source,groupPayload(source))
        broadcastGroup(leader)
    end
    return true,'Voce saiu do grupo.'
end)

AddEventHandler('playerDropped', function()
    local src=source
    pendingInvites[src]=nil
    local leader,group=getGroup(src,false)
    local job=activeJobs[src]
    if job and job.vehicleNetId then exports.ob_core:DeleteTemporaryVehicle(src,job.vehicleNetId) end
    activeJobs[src]=nil
    if group then
        group.members[src]=nil;memberGroup[src]=nil
        if src==leader then
            local nextLeader
            for member in pairs(group.members) do if getUserId(member) then nextLeader=member break end end
            groups[leader]=nil
            if nextLeader then
                group.leader=nextLeader;groups[nextLeader]=group
                cowCooldowns[nextLeader]=cowCooldowns[leader];cowCooldowns[leader]=nil
                for member in pairs(group.members) do memberGroup[member]=nextLeader end
                broadcastGroup(nextLeader)
            else cowCooldowns[leader]=nil end
        else broadcastGroup(leader) end
    else cowCooldowns[src]=nil end
end)

CreateThread(function()
    if not OR.Database.waitForReady(30000) then
        print('[ob_leiteirojob] Banco indisponivel; emprego nao iniciado.')
        return
    end
    local userIdType = characterIdColumnType()
    if not userIdType then
        print('[ob_leiteirojob] Tipo de ob_characters.user_id indisponivel.')
        return
    end
    local created, errorMessage = OR.Database.query.await(([[CREATE TABLE IF NOT EXISTS ob_leiteiro_progress (
        user_id %s NOT NULL PRIMARY KEY,
        xp INT NOT NULL DEFAULT 0,
        level INT NOT NULL DEFAULT 1,
        boxes_delivered INT NOT NULL DEFAULT 0,
        total_earned INT NOT NULL DEFAULT 0,
        CONSTRAINT fk_ob_leiteiro_progress_character FOREIGN KEY (user_id) REFERENCES ob_characters(user_id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]]):format(userIdType))
    databaseReady = created ~= nil
    if not databaseReady then print(('[ob_leiteirojob] Falha ao criar tabela: %s'):format(errorMessage or 'desconhecida')) end
end)
