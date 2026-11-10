local snapshots = {}
local sessions = {}
local schemaReady = false

local DROP_REASONS = {
    [1] = 'resource',
    [2] = 'client',
    [3] = 'server',
    [4] = 'client_replaced',
    [5] = 'client_connection_timed_out',
    [6] = 'client_connection_timed_out_with_pending_commands',
    [7] = 'server_shutdown',
    [8] = 'state_bag_rate_limit',
    [9] = 'net_event_rate_limit',
    [10] = 'latent_net_event_rate_limit',
    [11] = 'command_rate_limit',
    [12] = 'onesync_too_many_missed_frames',
}

local function finiteNumber(value, minimum, maximum, fallback, integer)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then value = fallback or 0 end
    if integer then value = math.floor(value) end
    return math.max(minimum, math.min(maximum, value))
end

local function safeText(value, maximum, fallback)
    if type(value) ~= 'string' then return fallback or '' end
    value = value:gsub('%z', ''):gsub('[\r\n]+', ' '):gsub('%s+', ' ')
    return value:sub(1, maximum)
end

local function safePed(data)
    if type(data) ~= 'table' then return nil end
    local coords = type(data.coords) == 'table' and data.coords or {}
    return {
        model = finiteNumber(data.model, -2147483648, 4294967295, 0, true),
        coords = {
            x = finiteNumber(coords.x, -10000.0, 10000.0, 0),
            y = finiteNumber(coords.y, -10000.0, 10000.0, 0),
            z = finiteNumber(coords.z, -2000.0, 5000.0, 0),
        },
        health = finiteNumber(data.health, 0, 10000, 0, true),
        armour = finiteNumber(data.armour, 0, 10000, 0, true),
        visible = data.visible == true,
        dead = data.dead == true,
        speed = finiteNumber(data.speed, 0, 1000.0, 0),
        head = finiteNumber(data.head, -1, 4096, -1, true),
        mask = finiteNumber(data.mask, -1, 4096, -1, true),
        maskTexture = finiteNumber(data.maskTexture, 0, 512, 0, true),
        hair = finiteNumber(data.hair, -1, 4096, -1, true),
        hairTexture = finiteNumber(data.hairTexture, 0, 512, 0, true),
        hairColor = finiteNumber(data.hairColor, -1, 255, -1, true),
        hairHighlight = finiteNumber(data.hairHighlight, -1, 255, -1, true),
        vehicleNetId = finiteNumber(data.vehicleNetId, 0, 65535, 0, true),
        vehicleModel = finiteNumber(data.vehicleModel, -2147483648, 4294967295, 0, true),
    }
end

local function safeSnapshot(data)
    if type(data) ~= 'table' then return nil end
    local localPed = safePed(data.localPed)
    if not localPed then return nil end

    local nearby = {}
    for _, entry in ipairs(type(data.nearby) == 'table' and data.nearby or {}) do
        if #nearby >= math.max(1, math.min(16, tonumber(OBDiagnosticsConfig.MaxNearbyPlayers) or 8)) then break end
        local ped = safePed(entry)
        local serverId = finiteNumber(entry.serverId, 1, 65535, 0, true)
        if ped and serverId > 0 then
            ped.serverId = serverId
            ped.distance = finiteNumber(entry.distance, 0, 10000.0, 0)
            nearby[#nearby + 1] = ped
        end
    end

    return {
        clientTimer = finiteNumber(data.clientTimer, 0, 2147483647, 0, true),
        networkSession = data.networkSession == true,
        paused = data.paused == true,
        localPed = localPed,
        nearby = nearby,
    }
end

local function cacheIdentity(src)
    src = tonumber(src)
    if not src or src <= 0 then return end
    local player = exports.ob_core:GetPlayer(src)
    local character = exports.ob_core:GetCharacter(src)
    sessions[src] = sessions[src] or { connectedAt = os.time() }
    sessions[src].name = safeText(GetPlayerName(src) or (player and player.name) or 'Desconhecido', 128, 'Desconhecido')
    sessions[src].userId = character and tonumber(character.userId) or sessions[src].userId
end

RegisterNetEvent('ob_diagnostics:server:clientStarted', function(clientTimer)
    if not OBDiagnosticsConfig.Enabled then return end
    local src = tonumber(source)
    if not src or src <= 0 then return end

    cacheIdentity(src)
    local firstStart = not sessions[src].clientStartedAt
    sessions[src].clientStartedAt = os.time()
    sessions[src].clientTimerAtStart = finiteNumber(clientTimer, 0, 2147483647, 0, true)
    if firstStart and OBDiagnosticsConfig.ConsolePrint then
        print(('[ob_diagnostics] CLIENT_READY session=%s user_id=%s name="%s"'):format(
            src,
            sessions[src].userId or 'null',
            sessions[src].name or 'Desconhecido'
        ))
    end
end)

RegisterNetEvent('ob_diagnostics:server:clientError', function(message)
    if not OBDiagnosticsConfig.Enabled then return end
    local src = tonumber(source)
    if not src or src <= 0 then return end

    cacheIdentity(src)
    local now = GetGameTimer()
    if sessions[src].lastClientErrorAt and now - sessions[src].lastClientErrorAt < 30000 then return end
    sessions[src].lastClientErrorAt = now
    print(('[ob_diagnostics] CLIENT_ERROR session=%s message="%s"'):format(src, safeText(message, 512, 'erro desconhecido')))
end)

RegisterNetEvent('ob_diagnostics:server:heartbeat', function(data)
    if not OBDiagnosticsConfig.Enabled then return end
    local src = tonumber(source)
    if not src or src <= 0 then return end

    local now = GetGameTimer()
    local previous = snapshots[src]
    if previous and now - previous.receivedAt < 750 then return end

    local snapshot = safeSnapshot(data)
    if not snapshot then return end
    cacheIdentity(src)
    snapshots[src] = {
        receivedAt = now,
        data = snapshot,
        lastAction = previous and previous.lastAction or nil,
    }
    if (not previous or not previous.data) and OBDiagnosticsConfig.ConsolePrint then
        print(('[ob_diagnostics] HEARTBEAT session=%s user_id=%s nearby=%s'):format(
            src,
            sessions[src] and sessions[src].userId or 'null',
            #snapshot.nearby
        ))
    end
end)

RegisterNetEvent('ob_diagnostics:server:action', function(action, data)
    if not OBDiagnosticsConfig.Enabled then return end
    local src = tonumber(source)
    if not src or src <= 0 then return end

    action = safeText(action, 64)
    if action == '' then return end
    local encoded = '{}'
    if type(data) == 'table' then
        local ok, result = pcall(json.encode, data)
        if ok and type(result) == 'string' then encoded = result:sub(1, 1500) end
    end

    cacheIdentity(src)
    snapshots[src] = snapshots[src] or { receivedAt = GetGameTimer(), data = nil }
    snapshots[src].lastAction = {
        name = action,
        data = encoded,
        receivedAt = GetGameTimer(),
    }
end)

AddEventHandler('ob_core:server:sessionCreated', function(src)
    cacheIdentity(src)
end)

AddEventHandler('ob_core:server:playerLoaded', function(src)
    cacheIdentity(src)
end)

AddEventHandler('playerJoining', function()
    local src = tonumber(source)
    if src then sessions[src] = { connectedAt = os.time(), name = safeText(GetPlayerName(src) or 'Conectando', 128) } end
end)

local function persistDrop(entry)
    if not schemaReady then return false end
    local inserted, err = OR.Database.insert.await([[INSERT INTO ob_disconnect_logs
        (user_id, session_id, player_name, reason, resource_name, client_drop_reason,
         drop_reason_label, classification, connected_seconds, last_snapshot_age_ms, snapshot)
        VALUES (NULLIF(?, 0), ?, ?, ?, ?, ?, ?, ?, NULLIF(?, -1), NULLIF(?, -1), NULLIF(?, ''))]], {
        entry.userId or 0,
        entry.sessionId,
        entry.playerName,
        entry.reason,
        entry.resourceName,
        entry.dropCode,
        entry.dropLabel,
        entry.classification,
        entry.connectedSeconds == nil and -1 or entry.connectedSeconds,
        entry.snapshotAge == nil and -1 or entry.snapshotAge,
        entry.snapshotJson or '',
    })
    if inserted == nil then
        print(('[ob_diagnostics] Falha ao persistir desconexao da sessao %s: %s'):format(entry.sessionId, err or 'erro desconhecido'))
        return false
    end
    return inserted
end

RegisterCommand('ob_diagtest', function(source)
    if source ~= 0 and not IsPlayerAceAllowed(source, 'or.developer') then return end
    if not schemaReady then
        print('[ob_diagnostics] AUTOTEST falhou: banco ainda nao esta pronto.')
        return
    end

    CreateThread(function()
        local inserted = persistDrop({
            userId = nil,
            sessionId = 0,
            playerName = 'ob_diagnostics self-test',
            reason = 'self_test_optional_nulls',
            resourceName = 'ob_diagnostics',
            dropCode = 0,
            dropLabel = 'self_test',
            classification = 'self_test',
            connectedSeconds = nil,
            snapshotAge = nil,
            snapshotJson = nil,
        })
        if not inserted then
            print('[ob_diagnostics] AUTOTEST falhou no INSERT.')
            return
        end

        local removed, err = OR.Database.update.await('DELETE FROM ob_disconnect_logs WHERE id = ? AND classification = ?', {
            inserted,
            'self_test',
        })
        if removed == nil then
            print(('[ob_diagnostics] AUTOTEST inseriu #%s, mas nao conseguiu remover: %s'):format(inserted, err or 'erro desconhecido'))
            return
        end
        print(('[ob_diagnostics] AUTOTEST OK: 11 parametros preservados; registro temporario #%s removido.'):format(inserted))
    end)
end, false)

AddEventHandler('playerDropped', function(reason, resourceName, clientDropReason)
    local src = tonumber(source)
    if not src then return end

    local now = GetGameTimer()
    local session = sessions[src] or {}
    local snapshot = snapshots[src]
    local dropCode = finiteNumber(clientDropReason, 0, 4294967295, 0, true)
    local normalizedReason = safeText(reason, 512, 'Sem motivo informado')
    local lowerReason = normalizedReason:lower()
    local enhancedNoInteraction = dropCode == 14 and lowerReason:find('no interaction', 1, true) ~= nil
    local dropLabel = enhancedNoInteraction and 'enhanced_no_interaction_timeout' or (DROP_REASONS[dropCode] or 'unknown')
    local timedOut = dropCode == 5 or dropCode == 6
        or lowerReason:find('timeout', 1, true) ~= nil
        or lowerReason:find('timed out', 1, true) ~= nil
    local classification = timedOut and 'timeout_or_hard_crash' or dropLabel
    local snapshotAge = snapshot and math.max(0, now - snapshot.receivedAt) or nil
    local snapshotPayload = (snapshot or session.clientStartedAt) and {
        clientReady = session.clientStartedAt ~= nil,
        clientStartedAt = session.clientStartedAt,
        clientTimerAtStart = session.clientTimerAtStart,
        heartbeat = snapshot and snapshot.data or nil,
        lastAction = snapshot and snapshot.lastAction or nil,
    } or nil
    local snapshotJson = snapshotPayload and json.encode(snapshotPayload) or nil

    local entry = {
        userId = session.userId,
        sessionId = src,
        playerName = safeText(session.name or GetPlayerName(src) or 'Desconhecido', 128, 'Desconhecido'),
        reason = normalizedReason,
        resourceName = safeText(resourceName, 128, 'desconhecido'),
        dropCode = dropCode,
        dropLabel = dropLabel,
        classification = classification,
        connectedSeconds = session.connectedAt and math.max(0, os.time() - session.connectedAt) or nil,
        snapshotAge = snapshotAge,
        snapshotJson = snapshotJson,
    }

    if OBDiagnosticsConfig.ConsolePrint then
        local nearbyCount = snapshot and snapshot.data and snapshot.data.nearby and #snapshot.data.nearby or 0
        local action = snapshot and snapshot.lastAction and snapshot.lastAction.name or 'nenhuma'
        print(('[ob_diagnostics] DROP session=%s user_id=%s name="%s" code=%s(%s) class=%s resource=%s connected_s=%s client_ready=%s heartbeat=%s snapshot_age_ms=%s nearby=%s last_action=%s reason="%s"'):format(
            entry.sessionId,
            entry.userId or 'null',
            entry.playerName,
            entry.dropCode,
            entry.dropLabel,
            entry.classification,
            entry.resourceName,
            entry.connectedSeconds or 'null',
            session.clientStartedAt and 'yes' or 'no',
            snapshot and snapshot.data and 'yes' or 'no',
            entry.snapshotAge or 'null',
            nearbyCount,
            action,
            entry.reason
        ))
    end

    snapshots[src] = nil
    sessions[src] = nil
    CreateThread(function() persistDrop(entry) end)
end)

local function commandAllowed(src)
    return src == 0 or IsPlayerAceAllowed(src, 'or.developer')
end

RegisterCommand('ob_disconnects', function(source, args)
    if not commandAllowed(source) or not schemaReady then return end
    local limit = finiteNumber(args and args[1], 1, 25, 10, true)
    CreateThread(function()
        local rows = OR.Database.query.await([[SELECT id, user_id, session_id, player_name, reason,
            client_drop_reason, drop_reason_label, classification, crash_report_code,
            last_snapshot_age_ms, created_at
            FROM ob_disconnect_logs ORDER BY id DESC LIMIT ?]], { limit }) or {}
        print(('[ob_diagnostics] Ultimas %s desconexoes:'):format(#rows))
        for _, row in ipairs(rows) do
            print(('[ob_diagnostics] #%s time=%s session=%s user_id=%s name="%s" code=%s(%s) class=%s snapshot_age_ms=%s crash=%s reason="%s"'):format(
                row.id,
                tostring(row.created_at),
                row.session_id,
                row.user_id or 'null',
                safeText(row.player_name, 128),
                row.client_drop_reason,
                row.drop_reason_label,
                row.classification,
                row.last_snapshot_age_ms or 'null',
                row.crash_report_code or 'null',
                safeText(row.reason, 512)
            ))
        end
    end)
end, false)

RegisterCommand('ob_disconnect', function(source, args)
    if not commandAllowed(source) or not schemaReady then return end
    local id = finiteNumber(args and args[1], 1, 4294967295, 0, true)
    if id <= 0 then return end
    CreateThread(function()
        local row = OR.Database.single.await('SELECT * FROM ob_disconnect_logs WHERE id = ? LIMIT 1', { id })
        if not row then
            print(('[ob_diagnostics] Registro #%s nao encontrado.'):format(id))
            return
        end
        print(('[ob_diagnostics] DETALHE #%s %s'):format(id, json.encode(row)))
    end)
end, false)

RegisterCommand('ob_crashcode', function(source, args)
    if not commandAllowed(source) or not schemaReady then return end
    local selector = safeText(args and args[1], 16):lower()
    local id = selector == 'latest' and nil or finiteNumber(selector, 1, 4294967295, 0, true)
    local crashCode = safeText(args and args[2], 64)
    if (selector ~= 'latest' and (not id or id <= 0)) or not crashCode:match('^[%x%-]+$') then
        print('[ob_diagnostics] Uso: ob_crashcode [id do log|latest] [codigo exibido pelo FiveM]')
        return
    end
    CreateThread(function()
        local changed
        if selector == 'latest' then
            changed = OR.Database.update.await([[UPDATE ob_disconnect_logs SET crash_report_code = ?
                WHERE id = (SELECT id FROM (SELECT id FROM ob_disconnect_logs ORDER BY id DESC LIMIT 1) latest_drop)]], { crashCode })
        else
            changed = OR.Database.update.await('UPDATE ob_disconnect_logs SET crash_report_code = ? WHERE id = ?', { crashCode, id })
        end
        print(changed and ('[ob_diagnostics] Codigo associado ao registro %s.'):format(selector)
            or ('[ob_diagnostics] Nao foi possivel atualizar o registro %s.'):format(selector))
    end)
end, false)

CreateThread(function()
    if not OBDiagnosticsConfig.Enabled then return end
    if not OR.Database.waitForReady(15000) then
        print('[ob_diagnostics] Banco indisponivel; quedas aparecerao somente no console.')
        return
    end

    local created, err = OR.Database.query.await([[CREATE TABLE IF NOT EXISTS ob_disconnect_logs (
        id bigint unsigned NOT NULL AUTO_INCREMENT,
        user_id bigint unsigned NULL,
        session_id int unsigned NOT NULL,
        player_name varchar(128) NOT NULL,
        reason varchar(512) NOT NULL,
        resource_name varchar(128) NOT NULL,
        client_drop_reason int unsigned NOT NULL DEFAULT 0,
        drop_reason_label varchar(64) NOT NULL,
        classification varchar(64) NOT NULL,
        connected_seconds int unsigned NULL,
        last_snapshot_age_ms int unsigned NULL,
        snapshot mediumtext NULL,
        crash_report_code varchar(64) NULL,
        created_at timestamp(3) NOT NULL DEFAULT current_timestamp(3),
        PRIMARY KEY (id),
        KEY idx_ob_disconnect_logs_user_time (user_id, created_at),
        KEY idx_ob_disconnect_logs_time (created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]])

    if created == nil then
        print(('[ob_diagnostics] Falha ao criar tabela: %s'):format(err or 'erro desconhecido'))
        return
    end
    schemaReady = true
    print('[ob_diagnostics] Registro persistente de desconexoes pronto.')

    local retention = math.max(1, math.min(365, math.floor(tonumber(OBDiagnosticsConfig.RetentionDays) or 30)))
    OR.Database.update.await(('DELETE FROM ob_disconnect_logs WHERE created_at < (current_timestamp() - INTERVAL %d DAY)'):format(retention))
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, playerSource in ipairs(GetPlayers()) do
        local src = tonumber(playerSource)
        if src then
            sessions[src] = { connectedAt = os.time() }
            cacheIdentity(src)
        end
    end
end)
