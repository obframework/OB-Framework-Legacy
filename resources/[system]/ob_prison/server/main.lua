local active = {}
local trackers = {}
local schemaReady = false

local function validSource(value)
    local playerSource = tonumber(value)
    return playerSource and playerSource > 0 and GetPlayerName(playerSource) and playerSource or nil
end

local function cleanText(value, maximum, fallback)
    local text = type(value) == 'string' and value or ''
    text = text:gsub('[\r\n]+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if text == '' then text = fallback or '' end
    return text:sub(1, maximum)
end

local function notify(playerSource, message, kind)
    playerSource = validSource(playerSource)
    if playerSource then
        TriggerClientEvent('ob_notification:client:notify', playerSource, message, kind or 'info')
    end
end

local function playerCoords(playerSource)
    local ped = GetPlayerPed(playerSource)
    if not ped or ped <= 0 then return nil end
    local coords = GetEntityCoords(ped)
    return coords and vector3(coords.x, coords.y, coords.z) or nil
end

local function distanceFrom(playerSource, target)
    local coords = playerCoords(playerSource)
    if not coords or type(target) ~= 'table' then return math.huge end
    return #(coords - vector3(target.x + 0.0, target.y + 0.0, target.z + 0.0))
end

local function userIdFromSource(playerSource)
    playerSource = tonumber(playerSource)
    if not playerSource or playerSource <= 0 then return nil end
    -- Ao desconectar, o export pode nao retornar nenhum valor. A variavel
    -- garante um nil explicito: tonumber() sem argumentos gera erro em Lua.
    local userId = exports.ob_core:GetUserId(playerSource)
    return tonumber(userId)
end

local function sourceFromUserId(userId)
    return validSource(exports.ob_core:GetSourceByUserId(tonumber(userId)))
end

local function fullName(playerSource)
    return cleanText(exports.ob_core:GetFullName(playerSource), 80, GetPlayerName(playerSource) or 'Sistema')
end

local function isAdmin(playerSource)
    if tonumber(playerSource) == 0 then return true end
    playerSource = validSource(playerSource)
    if not playerSource then return false end
    if GetResourceState('ob_admin') == 'started'
        and exports.ob_admin:HasPermission(playerSource, OBPrisonConfig.AdminPermission or 'panel.open') == true then
        return true
    end
    return exports.ob_core:IsAdmin(playerSource) == true
end

local function isPolice(playerSource)
    playerSource = validSource(playerSource)
    if not playerSource then return false end
    if GetResourceState('ob_org') == 'started' then
        return exports.ob_org:HasPermission(
            playerSource,
            OBPrisonConfig.PolicePermission or 'police',
            OBPrisonConfig.RequirePoliceDuty ~= false
        ) == true
    end
    return false
end

local function onlinePoliceCount()
    local count = 0
    for _, player in ipairs(exports.ob_core:GetPlayers() or {}) do
        if player.source and isPolice(player.source) then count = count + 1 end
    end
    return count
end

local function logActivity(sentenceId, userId, actorUserId, action, detail)
    if not schemaReady then return end
    OR.Database.insert.await([[INSERT INTO ob_prison_activity
        (sentence_id, user_id, actor_user_id, action_name, detail)
        VALUES (?, ?, ?, ?, ?)]], {
        tonumber(sentenceId) or 0,
        tonumber(userId) or 0,
        tonumber(actorUserId) or 0,
        cleanText(action, 32, 'unknown'),
        cleanText(detail, 500, ''),
    })
end

local function ensureSchema()
    if not OR.Database.waitForReady(30000) then
        print(('[ob_prison] Banco indisponível: %s'):format(OR.Database.getError() or 'erro desconhecido'))
        return false
    end

    local characterIdType = exports.ob_core:GetCharacterIdColumnType() or 'BIGINT UNSIGNED'
    local sentencesSql = ([=[CREATE TABLE IF NOT EXISTS ob_prison_sentences (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        mdt_record_id BIGINT UNSIGNED NOT NULL DEFAULT 0,
        user_id %s NOT NULL,
        total_seconds INT UNSIGNED NOT NULL,
        remaining_seconds INT UNSIGNED NOT NULL,
        reason VARCHAR(500) NOT NULL,
        sentenced_by_user_id BIGINT UNSIGNED NOT NULL DEFAULT 0,
        sentenced_by_name VARCHAR(80) NOT NULL DEFAULT 'Sistema',
        status VARCHAR(20) NOT NULL DEFAULT 'active',
        active_service VARCHAR(48) NULL,
        current_point SMALLINT UNSIGNED NULL,
        completed_services INT UNSIGNED NOT NULL DEFAULT 0,
        escape_stage SMALLINT UNSIGNED NOT NULL DEFAULT 0,
        release_reason VARCHAR(255) NULL,
        sentenced_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        completed_at TIMESTAMP NULL DEFAULT NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_ob_prison_user_status (user_id, status),
        KEY idx_ob_prison_mdt_record (mdt_record_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]=]):format(characterIdType)

    local activitySql = ([=[CREATE TABLE IF NOT EXISTS ob_prison_activity (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        sentence_id BIGINT UNSIGNED NOT NULL,
        user_id %s NOT NULL,
        actor_user_id BIGINT UNSIGNED NOT NULL DEFAULT 0,
        action_name VARCHAR(32) NOT NULL,
        detail VARCHAR(500) NOT NULL DEFAULT '',
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_ob_prison_activity_user (user_id, created_at),
        KEY idx_ob_prison_activity_sentence (sentence_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]=]):format(characterIdType)

    local first, firstError = OR.Database.query.await(sentencesSql, {})
    if first == nil then
        print(('[ob_prison] Falha ao criar ob_prison_sentences: %s'):format(firstError or 'desconhecida'))
        return false
    end
    local second, secondError = OR.Database.query.await(activitySql, {})
    if second == nil then
        print(('[ob_prison] Falha ao criar ob_prison_activity: %s'):format(secondError or 'desconhecida'))
        return false
    end
    schemaReady = true
    return true
end

local function publicSentence(data)
    if not data then return { imprisoned = false } end
    return {
        imprisoned = true,
        sentenceId = data.id,
        totalSeconds = data.totalSeconds,
        remainingSeconds = data.remainingSeconds,
        remainingMonths = math.max(1, math.ceil(data.remainingSeconds / math.max(1, OBPrisonConfig.SecondsPerMonth))),
        reason = data.reason,
        activeService = data.activeService,
        currentPoint = data.currentPoint,
        completedServices = data.completedServices,
        escapeStage = data.escapeStage,
    }
end

local function publishState(playerSource, data)
    playerSource = validSource(playerSource)
    if not playerSource then return end
    local player = Player(playerSource)
    if player then player.state:set('ob:prison', data and publicSentence(data) or false, true) end
end

local function saveActive(data)
    if not data or not schemaReady then return false end
    local changed, errorMessage = OR.Database.update.await([[UPDATE ob_prison_sentences
        SET remaining_seconds = ?, active_service = NULLIF(?, ''), current_point = NULLIF(?, 0),
            completed_services = ?, escape_stage = ?
        WHERE id = ? AND status = 'active']], {
        math.max(0, math.floor(data.remainingSeconds or 0)),
        data.activeService or '',
        tonumber(data.currentPoint) or 0,
        math.max(0, math.floor(data.completedServices or 0)),
        math.max(0, math.floor(data.escapeStage or 0)),
        data.id,
    })
    data.lastSavedAt = GetGameTimer()
    return changed ~= nil, errorMessage
end

local function rowToActive(row)
    if not row then return nil end
    return {
        id = tonumber(row.id),
        userId = tonumber(row.user_id),
        totalSeconds = tonumber(row.total_seconds) or 0,
        remainingSeconds = tonumber(row.remaining_seconds) or 0,
        reason = row.reason or 'Sem motivo.',
        activeService = row.active_service,
        currentPoint = tonumber(row.current_point),
        completedServices = tonumber(row.completed_services) or 0,
        escapeStage = tonumber(row.escape_stage) or 0,
        lastSavedAt = GetGameTimer(),
        source = nil,
    }
end

local function loadActive(userId)
    userId = tonumber(userId)
    if not userId or not schemaReady then return nil end
    if OBPrisonConfig.CountTimeOffline == true then
        OR.Database.update.await([[UPDATE ob_prison_sentences
            SET remaining_seconds = GREATEST(0, remaining_seconds - TIMESTAMPDIFF(SECOND, updated_at, CURRENT_TIMESTAMP))
            WHERE user_id = ? AND status = 'active']], { userId })
    end
    local row = OR.Database.single.await([[SELECT id, user_id, total_seconds, remaining_seconds, reason,
        active_service, current_point, completed_services, escape_stage
        FROM ob_prison_sentences WHERE user_id = ? AND status = 'active'
        ORDER BY id DESC LIMIT 1]], { userId })
    return rowToActive(row)
end

local function teleportPayload(coords)
    return { x = coords.x, y = coords.y, z = coords.z, w = coords.w or 0.0 }
end

local function release(userId, status, reason, actorUserId, customCoords)
    userId = tonumber(userId)
    local data = active[userId] or loadActive(userId)
    if not data then return false, 'O personagem não possui pena ativa.' end
    status = status == 'escaped' and 'escaped' or 'released'
    reason = cleanText(reason, 255, status == 'escaped' and 'Fuga concluída.' or 'Pena encerrada.')
    local changed, errorMessage = OR.Database.update.await([[UPDATE ob_prison_sentences
        SET status = ?, remaining_seconds = ?, release_reason = ?, completed_at = CURRENT_TIMESTAMP,
            active_service = NULL, current_point = NULL, escape_stage = 0
        WHERE id = ? AND status = 'active']], {
        status,
        math.max(0, data.remainingSeconds or 0),
        reason,
        data.id,
    })
    if changed == nil or changed < 1 then return false, errorMessage or 'A pena já foi encerrada.' end
    active[userId] = nil
    logActivity(data.id, userId, actorUserId, status, reason)
    local targetSource = sourceFromUserId(userId)
    if targetSource then
        publishState(targetSource, nil)
        TriggerClientEvent('ob_prison:client:released', targetSource, {
            coords = teleportPayload(customCoords or OBPrisonConfig.Release),
            message = reason,
            escaped = status == 'escaped',
        })
    end
    return true, data.id
end

local function restoreForSource(playerSource, teleport)
    playerSource = validSource(playerSource)
    if not playerSource or not schemaReady then return false end
    local userId = userIdFromSource(playerSource)
    if not userId then return false end
    local data = loadActive(userId)
    if not data then
        active[userId] = nil
        publishState(playerSource, nil)
        return false
    end
    if data.remainingSeconds <= 0 then
        active[userId] = data
        release(userId, 'released', 'Pena concluída.', 0)
        return false
    end
    active[userId] = data
    data.source = playerSource
    publishState(playerSource, data)
    TriggerClientEvent('ob_prison:client:restore', playerSource, {
        sentence = publicSentence(data),
        entry = teleportPayload(OBPrisonConfig.Entry),
        teleport = teleport == true,
    })
    return true
end

local function sentenceByUserId(actorSource, targetUserId, months, reason, mdtRecordId)
    targetUserId = math.floor(tonumber(targetUserId) or 0)
    months = math.floor(tonumber(months) or 0)
    if targetUserId < 1 then return false, 'ID fixo do personagem inválido.' end
    if months < 1 or months > (OBPrisonConfig.MaximumMonths or 240) then
        return false, ('A pena deve ter entre 1 e %s meses.'):format(OBPrisonConfig.MaximumMonths or 240)
    end
    if not schemaReady then return false, 'Banco da prisão ainda não está pronto.' end
    local character = OR.Database.single.await([[SELECT user_id, firstname, lastname FROM ob_characters
        WHERE user_id = ? AND deleted_at IS NULL AND blocked_at IS NULL LIMIT 1]], { targetUserId })
    if not character then return false, 'Personagem não encontrado.' end

    local actorUserId = validSource(actorSource) and userIdFromSource(actorSource) or 0
    local actorName = validSource(actorSource) and fullName(actorSource) or 'Sistema'
    local totalSeconds = months * math.max(1, OBPrisonConfig.SecondsPerMonth or 60)
    reason = cleanText(reason, 500, 'Sem motivo informado.')

    OR.Database.update.await([[UPDATE ob_prison_sentences SET status = 'replaced',
        release_reason = 'Substituída por nova sentença.', completed_at = CURRENT_TIMESTAMP
        WHERE user_id = ? AND status = 'active']], { targetUserId })

    local sentenceId, insertError = OR.Database.insert.await([[INSERT INTO ob_prison_sentences
        (mdt_record_id, user_id, total_seconds, remaining_seconds, reason, sentenced_by_user_id, sentenced_by_name)
        VALUES (?, ?, ?, ?, ?, ?, ?)]], {
        tonumber(mdtRecordId) or 0,
        targetUserId,
        totalSeconds,
        totalSeconds,
        reason,
        actorUserId or 0,
        actorName,
    })
    sentenceId = tonumber(sentenceId)
    if not sentenceId then return false, insertError or 'Não foi possível criar a sentença.' end

    active[targetUserId] = {
        id = sentenceId,
        userId = targetUserId,
        totalSeconds = totalSeconds,
        remainingSeconds = totalSeconds,
        reason = reason,
        completedServices = 0,
        escapeStage = 0,
        lastSavedAt = GetGameTimer(),
        source = sourceFromUserId(targetUserId),
    }
    logActivity(sentenceId, targetUserId, actorUserId, 'sentenced', ('%s mês(es): %s'):format(months, reason))
    local targetSource = sourceFromUserId(targetUserId)
    if targetSource then
        publishState(targetSource, active[targetUserId])
        TriggerClientEvent('ob_prison:client:jailed', targetSource, {
            sentence = publicSentence(active[targetUserId]),
            entry = teleportPayload(OBPrisonConfig.Entry),
        })
    end
    return true, sentenceId
end

exports('SentenceByUserId', sentenceByUserId)
exports('GetActiveSentence', function(userId)
    local data = active[tonumber(userId)] or loadActive(userId)
    return data and publicSentence(data) or nil
end)
exports('ReleaseByUserId', function(actorSource, userId, reason)
    return release(userId, 'released', reason, validSource(actorSource) and userIdFromSource(actorSource) or 0)
end)

OR.Callback.register('status', function(playerSource)
    local userId = userIdFromSource(playerSource)
    if not userId then return nil, 'Personagem não carregado.' end
    local data = active[userId]
    if not data then data = loadActive(userId) active[userId] = data end
    return data and publicSentence(data) or { imprisoned = false }
end)

local function choosePoint(service, currentPoint)
    local total = #(service.points or {})
    if total < 2 then return total == 1 and 1 or nil end
    local nextPoint = math.random(1, total - 1)
    if nextPoint >= currentPoint then nextPoint = nextPoint + 1 end
    return nextPoint
end

OR.Callback.register('startService', function(playerSource, serviceId)
    local userId = userIdFromSource(playerSource)
    local data = userId and active[userId]
    local service = type(serviceId) == 'string' and OBPrisonConfig.Services[serviceId] or nil
    if not data then return false, 'Você não está preso.' end
    if not service or not service.npc or #(service.points or {}) < 1 then return false, 'Trabalho inválido.' end
    if data.activeService then return false, 'Cancele o trabalho atual com F7.' end
    if distanceFrom(playerSource, service.npc) > 3.0 then return false, 'Aproxime-se do responsável pelo trabalho.' end
    data.activeService = serviceId
    data.currentPoint = math.random(1, #service.points)
    data.actionToken = nil
    saveActive(data)
    publishState(playerSource, data)
    logActivity(data.id, userId, userId, 'service_start', serviceId)
    return true, 'Trabalho iniciado. Vá até o ponto marcado.', publicSentence(data)
end)

OR.Callback.register('beginServicePoint', function(playerSource)
    local userId = userIdFromSource(playerSource)
    local data = userId and active[userId]
    local service = data and data.activeService and OBPrisonConfig.Services[data.activeService] or nil
    local point = service and service.points[data.currentPoint or 0] or nil
    if not data or not service or not point then return nil, 'Nenhum trabalho ativo.' end
    if data.actionToken then return nil, 'Este ponto já está sendo executado.' end
    if distanceFrom(playerSource, point) > (OBPrisonConfig.Service.ValidationDistance or 3.0) then
        return nil, 'Aproxime-se do ponto correto.'
    end
    data.actionToken = ('%s:%s:%s'):format(userId, GetGameTimer(), math.random(100000, 999999))
    data.actionStartedAt = GetGameTimer()
    return {
        token = data.actionToken,
        label = service.label,
        durationMs = math.max(2000, tonumber(service.durationMs) or 7000),
        scenario = service.scenario,
    }
end)

OR.Callback.register('finishServicePoint', function(playerSource, token)
    local userId = userIdFromSource(playerSource)
    local data = userId and active[userId]
    local service = data and data.activeService and OBPrisonConfig.Services[data.activeService] or nil
    local point = service and service.points[data.currentPoint or 0] or nil
    if not data or not service or not point or token ~= data.actionToken then return false, 'Ação inválida ou expirada.' end
    local elapsed = GetGameTimer() - (data.actionStartedAt or GetGameTimer())
    data.actionToken, data.actionStartedAt = nil, nil
    if elapsed < math.max(1500, (tonumber(service.durationMs) or 7000) - 750) then return false, 'O trabalho terminou rápido demais.' end
    if distanceFrom(playerSource, point) > (OBPrisonConfig.Service.ValidationDistance or 3.0) then return false, 'Você se afastou do ponto.' end

    data.completedServices = (data.completedServices or 0) + 1
    local required = math.max(1, tonumber(OBPrisonConfig.Service.ServicesPerMonth) or 2)
    local reduced = data.completedServices % required == 0
    if reduced then
        data.remainingSeconds = math.max(0, data.remainingSeconds - math.max(1, OBPrisonConfig.SecondsPerMonth or 60))
    end
    local completedPoint = data.currentPoint
    data.currentPoint = choosePoint(service, completedPoint)
    saveActive(data)
    logActivity(data.id, userId, userId, 'service_point', ('%s:%s'):format(data.activeService, completedPoint))
    if data.remainingSeconds <= 0 then
        release(userId, 'released', 'Pena concluída pelos trabalhos.', userId)
        return true, 'Trabalho concluído. Sua pena terminou.', { imprisoned = false }
    end
    publishState(playerSource, data)
    local message = reduced and 'Trabalho concluído: um mês foi reduzido.' or
        ('Trabalho concluído: faltam %s tarefa(s) para reduzir um mês.'):format(required - (data.completedServices % required))
    return true, message, publicSentence(data)
end)

OR.Callback.register('abortServicePoint', function(playerSource, token)
    local userId = userIdFromSource(playerSource)
    local data = userId and active[userId]
    if not data or token ~= data.actionToken then return false end
    data.actionToken, data.actionStartedAt = nil, nil
    return true
end)

OR.Callback.register('cancelService', function(playerSource)
    local userId = userIdFromSource(playerSource)
    local data = userId and active[userId]
    if not data or not data.activeService then return false, 'Nenhum trabalho ativo.' end
    local serviceId = data.activeService
    data.activeService, data.currentPoint, data.actionToken, data.actionStartedAt = nil, nil, nil, nil
    saveActive(data)
    publishState(playerSource, data)
    logActivity(data.id, userId, userId, 'service_cancel', serviceId)
    return true, 'Trabalho cancelado.'
end)

local function currentEscapeStage(data)
    local stageIndex = math.max(1, tonumber(data.escapeStage) or 1)
    return stageIndex, OBPrisonConfig.Escape.Stages[stageIndex]
end

OR.Callback.register('beginEscapeStage', function(playerSource)
    local userId = userIdFromSource(playerSource)
    local data = userId and active[userId]
    if not data then return nil, 'Você não está preso.' end
    local stageIndex, stage = currentEscapeStage(data)
    if not stage then return nil, 'Etapa de fuga inválida.' end
    if distanceFrom(playerSource, stage.coords) > (OBPrisonConfig.Escape.ValidationDistance or 3.0) then
        return nil, 'Aproxime-se do ponto da fuga.'
    end
    if data.escapeToken then return nil, 'A etapa anterior ainda está em andamento.' end
    if data.escapeStage == 0 then
        local needed = math.max(0, tonumber(OBPrisonConfig.Escape.RequiredPolice) or 0)
        local police = onlinePoliceCount()
        if police < needed then return nil, ('Policiais em serviço insuficientes (%s/%s).'):format(police, needed) end
        local item = OBPrisonConfig.Escape.Item or 'prison_key'
        local count, countError = exports.ob_inventory:GetItemCount(playerSource, item)
        if not count or count < 1 then return nil, countError or ('Você precisa de 1x %s.'):format(item) end
        local removed, removeError = exports.ob_inventory:RemoveItem(playerSource, item, 1)
        if not removed then return nil, removeError or 'Não foi possível consumir a chave.' end
        data.escapeStage = 1
        data.activeService, data.currentPoint = nil, nil
        logActivity(data.id, userId, userId, 'escape_start', item)
    end
    data.escapeToken = ('escape:%s:%s:%s'):format(userId, stageIndex, math.random(100000, 999999))
    data.escapeStartedAt = GetGameTimer()
    saveActive(data)
    publishState(playerSource, data)
    return {
        token = data.escapeToken,
        stage = stageIndex,
        label = stage.label,
        minigame = stage.minigame,
        minimumMs = stage.minDurationMs or 4000,
    }
end)

OR.Callback.register('finishEscapeStage', function(playerSource, token, succeeded)
    local userId = userIdFromSource(playerSource)
    local data = userId and active[userId]
    local stageIndex, stage
    if data then stageIndex, stage = currentEscapeStage(data) end
    if not data or not stage or token ~= data.escapeToken then return false, 'Etapa inválida ou expirada.' end
    local elapsed = GetGameTimer() - (data.escapeStartedAt or GetGameTimer())
    data.escapeToken, data.escapeStartedAt = nil, nil
    if succeeded ~= true then
        saveActive(data)
        return false, 'Você falhou. A etapa deverá ser tentada novamente.'
    end
    if elapsed < math.max(1500, (tonumber(stage.minDurationMs) or 4000) - 1000) then return false, 'Resultado rápido demais.' end
    if distanceFrom(playerSource, stage.coords) > (OBPrisonConfig.Escape.ValidationDistance or 3.0) then return false, 'Você se afastou da etapa.' end

    logActivity(data.id, userId, userId, 'escape_stage', tostring(stageIndex))
    if stageIndex >= #OBPrisonConfig.Escape.Stages then
        trackers[userId] = {
            source = playerSource,
            name = fullName(playerSource),
            expiresAt = os.time() + math.max(10, OBPrisonConfig.Escape.TrackerSeconds or 300),
        }
        local released, releaseError = release(userId, 'escaped', 'Fuga concluída.', userId, OBPrisonConfig.Escape.Exit)
        if not released then return false, releaseError end
        return true, 'Você escapou, mas a polícia está recebendo sua posição.', { escaped = true }
    end
    data.escapeStage = stageIndex + 1
    saveActive(data)
    publishState(playerSource, data)
    return true, 'Etapa concluída. Siga para o próximo ponto.', publicSentence(data)
end)

RegisterNetEvent('ob_prison:server:boundaryViolation', function()
    local playerSource = validSource(source)
    local userId = playerSource and userIdFromSource(playerSource)
    local data = userId and active[userId]
    if not data then return end
    local center = OBPrisonConfig.Boundary.center
    if distanceFrom(playerSource, center) <= (OBPrisonConfig.Boundary.radius or 200.0) then return end
    TriggerClientEvent('ob_prison:client:returnToPrison', playerSource, teleportPayload(OBPrisonConfig.Entry))
    logActivity(data.id, userId, userId, 'boundary_return', 'Saiu do perímetro sem concluir a fuga.')
end)

RegisterCommand(OBPrisonConfig.Commands.Jail or 'prender', function(commandSource, args)
    if not isAdmin(commandSource) then return notify(commandSource, 'Sem permissão.', 'error') end
    local userId = tonumber(args[1])
    local months = tonumber(args[2])
    local reason = table.concat(args, ' ', 3)
    local ok, result = sentenceByUserId(commandSource, userId, months, reason ~= '' and reason or 'Prisão administrativa.', 0)
    if commandSource == 0 then
        print(ok and ('[ob_prison] Sentença criada: %s'):format(result) or ('[ob_prison] %s'):format(result))
    else
        notify(commandSource, ok and ('Sentença criada (#%s).'):format(result) or result, ok and 'success' or 'error')
    end
end, false)

RegisterCommand(OBPrisonConfig.Commands.Release or 'soltar', function(commandSource, args)
    if not isAdmin(commandSource) then return notify(commandSource, 'Sem permissão.', 'error') end
    local userId = tonumber(args[1])
    local reason = table.concat(args, ' ', 2)
    local ok, result = release(userId, 'released', reason ~= '' and reason or 'Liberação administrativa.',
        validSource(commandSource) and userIdFromSource(commandSource) or 0)
    if commandSource == 0 then
        print(ok and ('[ob_prison] Personagem %s liberado.'):format(userId) or ('[ob_prison] %s'):format(result))
    else
        notify(commandSource, ok and 'Personagem liberado.' or result, ok and 'success' or 'error')
    end
end, false)

AddEventHandler('ob_core:server:playerLoaded', function(playerSource)
    local capturedSource = validSource(playerSource)
    if not capturedSource then return end
    CreateThread(function()
        Wait(1200)
        if validSource(capturedSource) then restoreForSource(capturedSource, true) end
    end)
end)

AddEventHandler('playerDropped', function()
    local playerSource = tonumber(source)
    if not playerSource then return end
    -- O core pode ter removido o personagem antes deste handler executar.
    local userId
    for activeUserId, entry in pairs(active) do
        if tonumber(entry.source) == playerSource then userId = activeUserId break end
    end
    if not userId then userId = userIdFromSource(playerSource) end
    local data = userId and active[userId]
    if data and tonumber(data.source) == playerSource then
        saveActive(data)
        -- Nao apagar uma nova sessao restaurada enquanto o SQL aguardava.
        if active[userId] == data then active[userId] = nil end
    end
end)

CreateThread(function()
    if not ensureSchema() then return end
    Wait(500)
    for _, player in ipairs(exports.ob_core:GetPlayers() or {}) do
        if player.source and exports.ob_core:IsPlayerLoaded(player.source) then restoreForSource(player.source, false) end
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        local now = GetGameTimer()
        for userId, data in pairs(active) do
            local playerSource = sourceFromUserId(userId)
            if playerSource then
                data.source = playerSource
                data.remainingSeconds = math.max(0, (data.remainingSeconds or 0) - 1)
                if data.remainingSeconds <= 0 then
                    release(userId, 'released', 'Pena concluída.', 0)
                elseif now - (data.lastSavedAt or 0) >= math.max(5, OBPrisonConfig.SaveIntervalSeconds or 15) * 1000 then
                    saveActive(data)
                    publishState(playerSource, data)
                    TriggerClientEvent('ob_prison:client:update', playerSource, publicSentence(data))
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()
        for userId, tracker in pairs(trackers) do
            local trackedSource = sourceFromUserId(userId)
            if now >= tracker.expiresAt or not trackedSource then
                TriggerClientEvent('ob_prison:client:stopTracker', -1, userId)
                trackers[userId] = nil
            else
                local coords = playerCoords(trackedSource)
                if coords then
                    for _, player in ipairs(exports.ob_core:GetPlayers() or {}) do
                        if player.source and isPolice(player.source) then
                            TriggerClientEvent('ob_prison:client:updateTracker', player.source, {
                                userId = userId,
                                name = tracker.name,
                                coords = { x = coords.x, y = coords.y, z = coords.z },
                                expiresAt = tracker.expiresAt,
                            })
                        end
                    end
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, data in pairs(active) do saveActive(data) end
end)
