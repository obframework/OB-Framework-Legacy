local schemaReady = false
local phoneTableAvailable = false

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

local function characterName(row)
    if not row then return 'Desconhecido' end
    return cleanText(('%s %s'):format(row.firstname or '', row.lastname or ''), 80, 'Desconhecido')
end

local function isAdmin(playerSource)
    if GetResourceState('ob_admin') == 'started'
        and exports.ob_admin:HasPermission(playerSource, 'panel.open') == true then return true end
    return exports.ob_core:IsAdmin(playerSource) == true
end

local function hasOrgPermission(playerSource, permission, requireDuty)
    return GetResourceState('ob_org') == 'started'
        and exports.ob_org:HasPermission(playerSource, permission, requireDuty == true) == true
end

local function canOpen(playerSource, mode)
    if OBMdtConfig.AllowAdminAccess == true and isAdmin(playerSource) then return true end
    if mode == 'police' then
        return hasOrgPermission(playerSource, OBMdtConfig.Permissions.Police or 'police', OBMdtConfig.RequirePoliceDuty ~= false)
    end
    if mode == 'lawyer' then
        return hasOrgPermission(playerSource, OBMdtConfig.Permissions.Lawyer or 'lawyer', OBMdtConfig.RequireLawyerDuty == true)
    end
    return false
end

local function permissionFlags(playerSource, mode)
    local adminAllowed = OBMdtConfig.AllowAdminClear == true and isAdmin(playerSource)
    local roleCanClear = mode == 'police'
        and OBMdtConfig.AllowPoliceClear ~= false
        or mode == 'lawyer' and OBMdtConfig.AllowLawyerClear ~= false
    local roleCanAudit = mode == 'police'
        and OBMdtConfig.AllowPoliceAudit ~= false
        or mode == 'lawyer' and OBMdtConfig.AllowLawyerAudit ~= false
    return {
        canCreate = mode == 'police' and canOpen(playerSource, 'police'),
        canClear = adminAllowed or roleCanClear
            or hasOrgPermission(playerSource, OBMdtConfig.Permissions.Clear or 'mdt.clear', mode == 'police'),
        canSeeAudit = adminAllowed or roleCanAudit
            or hasOrgPermission(playerSource, OBMdtConfig.Permissions.Audit or 'mdt.audit', false),
    }
end

local function ensureSchema()
    if not OR.Database.waitForReady(30000) then
        print(('[ob_mdt] Banco indisponível: %s'):format(OR.Database.getError() or 'erro desconhecido'))
        return false
    end
    local idType = exports.ob_core:GetCharacterIdColumnType() or 'BIGINT UNSIGNED'
    local recordsSql = ([=[CREATE TABLE IF NOT EXISTS ob_mdt_records (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        suspect_user_id %s NOT NULL,
        suspect_name VARCHAR(80) NOT NULL,
        officer_user_id %s NOT NULL,
        officer_name VARCHAR(80) NOT NULL,
        reason VARCHAR(1000) NOT NULL,
        crimes_json LONGTEXT NOT NULL,
        months SMALLINT UNSIGNED NOT NULL DEFAULT 0,
        fine BIGINT UNSIGNED NOT NULL DEFAULT 0,
        fine_status VARCHAR(16) NOT NULL DEFAULT 'pending',
        bail_amount BIGINT UNSIGNED NOT NULL DEFAULT 0,
        lawyer_required TINYINT(1) NOT NULL DEFAULT 0,
        mugshot_url VARCHAR(500) NOT NULL DEFAULT '',
        inventory_photo_url VARCHAR(500) NOT NULL DEFAULT '',
        seized_items VARCHAR(1000) NOT NULL DEFAULT '',
        cleared TINYINT(1) NOT NULL DEFAULT 0,
        cleared_by_user_id BIGINT UNSIGNED NOT NULL DEFAULT 0,
        cleared_by_name VARCHAR(80) NOT NULL DEFAULT '',
        cleared_reason VARCHAR(500) NOT NULL DEFAULT '',
        cleared_at TIMESTAMP NULL DEFAULT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_ob_mdt_suspect (suspect_user_id, created_at),
        KEY idx_ob_mdt_officer (officer_user_id, created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]=]):format(idType, idType)
    local auditSql = ([=[CREATE TABLE IF NOT EXISTS ob_mdt_clear_audit (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        record_id BIGINT UNSIGNED NOT NULL,
        cleaner_user_id %s NOT NULL,
        cleaner_name VARCHAR(80) NOT NULL,
        cleaner_mode VARCHAR(16) NOT NULL,
        note VARCHAR(500) NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_ob_mdt_audit_record (record_id),
        KEY idx_ob_mdt_audit_cleaner (cleaner_user_id, created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]=]):format(idType)
    local records, recordsError = OR.Database.query.await(recordsSql, {})
    if records == nil then print(('[ob_mdt] Falha ao criar registros: %s'):format(recordsError or 'desconhecida')) return false end
    local audit, auditError = OR.Database.query.await(auditSql, {})
    if audit == nil then print(('[ob_mdt] Falha ao criar auditoria: %s'):format(auditError or 'desconhecida')) return false end
    phoneTableAvailable = (tonumber(OR.Database.scalar.await([[SELECT COUNT(*) FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ob_phone_numbers']], {})) or 0) > 0
    schemaReady = true
    return true
end

local function catalog()
    local result = {}
    for index, crime in ipairs(OBMdtCrimes or {}) do
        result[index] = {
            code = cleanText(crime.code, 48, ('crime_%s'):format(index)),
            label = cleanText(crime.label, 100, 'Infração'),
            months = math.max(0, math.floor(tonumber(crime.months) or 0)),
            fine = math.max(0, math.floor(tonumber(crime.fine) or 0)),
        }
    end
    table.sort(result, function(first, second) return first.label < second.label end)
    return result
end

local function normalizeCrimes(codes)
    local available = {}
    for _, crime in ipairs(catalog()) do available[crime.code] = crime end
    local selected, seen, months, fine = {}, {}, 0, 0
    for _, code in ipairs(type(codes) == 'table' and codes or {}) do
        code = type(code) == 'string' and code or ''
        local crime = available[code]
        if crime and not seen[code] then
            seen[code] = true
            selected[#selected + 1] = crime
            months = months + crime.months
            fine = fine + crime.fine
        end
    end
    return selected, months, fine
end

local function safeUrl(value)
    local url = cleanText(value, 500, '')
    if url == '' then return '' end
    if not url:lower():match('^https?://') then return '' end
    return url
end

local function bootstrapData(playerSource, mode)
    mode = mode == 'lawyer' and 'lawyer' or 'police'
    if not schemaReady then return nil, 'O banco do MDT ainda está iniciando.' end
    if not canOpen(playerSource, mode) then return nil, 'Você não possui acesso ou não está em serviço.' end
    local job = exports.ob_core:GetJob(playerSource) or {}
    return {
        allowed = true,
        mode = mode,
        profile = {
            name = exports.ob_core:GetFullName(playerSource) or GetPlayerName(playerSource),
            userId = exports.ob_core:GetUserId(playerSource),
            job = job.label or job.name or 'Organização',
            grade = tonumber(job.grade) or 0,
            onDuty = job.onDuty == true,
        },
        permissions = permissionFlags(playerSource, mode),
        crimeCatalog = catalog(),
        maximumMonths = OBMdtConfig.MaximumMonths or 240,
        maximumFine = OBMdtConfig.MaximumFine or 10000000,
    }
end

OR.Callback.register('bootstrap', function(playerSource, mode)
    local data, errorMessage = bootstrapData(playerSource, mode)
    if not data then
        print(('[ob_mdt] CALLBACK source=%s mode=%s allowed=false reason=%s'):format(
            tostring(playerSource),
            tostring(mode),
            errorMessage or 'indisponível'
        ))
        return nil, errorMessage
    end
    print(('[ob_mdt] CALLBACK source=%s user_id=%s mode=%s allowed=true'):format(
        tostring(playerSource),
        tostring(data.profile and data.profile.userId or 'unknown'),
        tostring(mode)
    ))
    return data
end)

local function commandOpen(playerSource, mode)
    if tonumber(playerSource) == 0 then
        print(('[ob_mdt] O comando /%s deve ser usado dentro do jogo.'):format(
            mode == 'lawyer' and (OBMdtConfig.Commands.Lawyer or 'adv') or (OBMdtConfig.Commands.Police or 'mdt')
        ))
        return
    end
    playerSource = validSource(playerSource)
    if not playerSource then return end
    local data, errorMessage = bootstrapData(playerSource, mode)
    if not data then
        print(('[ob_mdt] OPEN source=%s mode=%s allowed=false reason=%s'):format(
            playerSource,
            mode,
            errorMessage or 'indisponível'
        ))
        return notify(playerSource, errorMessage or 'Não foi possível abrir o MDT.', 'error')
    end
    print(('[ob_mdt] OPEN source=%s user_id=%s mode=%s allowed=true'):format(
        playerSource,
        tostring(data.profile and data.profile.userId or 'unknown'),
        mode
    ))
    TriggerClientEvent('ob_mdt:client:open', playerSource, mode, data)
end

RegisterNetEvent('ob_mdt:server:openRequest', function(mode)
    local playerSource = source
    commandOpen(playerSource, mode == 'lawyer' and 'lawyer' or 'police')
end)

local traceStages = {
    client_event_received = true,
    nui_message_sent = true,
    nui_ready = true,
    nui_open_received = true,
    nui_rendered = true,
    nui_render_error = true,
}

RegisterNetEvent('ob_mdt:server:trace', function(stage)
    local playerSource = validSource(source)
    stage = type(stage) == 'string' and stage or ''
    if not playerSource or not traceStages[stage] then return end
    print(('[ob_mdt] TRACE source=%s stage=%s'):format(playerSource, stage))
end)

RegisterCommand(OBMdtConfig.Commands.Police or 'mdt', function(playerSource)
    commandOpen(playerSource, 'police')
end, false)

RegisterCommand(OBMdtConfig.Commands.Lawyer or 'adv', function(playerSource)
    commandOpen(playerSource, 'lawyer')
end, false)

OR.Callback.register('queryPerson', function(playerSource, payload)
    payload = type(payload) == 'table' and payload or {}
    local mode = payload.mode == 'lawyer' and 'lawyer' or 'police'
    if not canOpen(playerSource, mode) then return { ok = false, message = 'Sem permissão.' } end
    local term = cleanText(payload.term, 64, '')
    if term == '' then return { ok = false, message = 'Informe o ID fixo ou o nome.' } end
    local numericId = tonumber(term) or 0
    local like = '%' .. term .. '%'
    local phoneSelect = phoneTableAvailable and "COALESCE(p.phone_number, 'N/A') AS phone_number" or "'N/A' AS phone_number"
    local phoneJoin = phoneTableAvailable and 'LEFT JOIN ob_phone_numbers p ON p.user_id = c.user_id' or ''
    local query = ([=[SELECT c.user_id, c.firstname, c.lastname, c.birthdate,
        c.gender, c.nationality, %s
        FROM ob_characters c %s
        WHERE c.deleted_at IS NULL AND c.blocked_at IS NULL
          AND (c.user_id = ? OR c.firstname LIKE ? OR c.lastname LIKE ? OR CONCAT(c.firstname, ' ', c.lastname) LIKE ?)
        ORDER BY c.user_id ASC LIMIT ?]=]):format(phoneSelect, phoneJoin)
    local rows, errorMessage = OR.Database.query.await(query, {
        numericId,
        like,
        like,
        like,
        math.max(1, math.min(50, OBMdtConfig.SearchLimit or 30)),
    })
    if rows == nil then return { ok = false, message = errorMessage or 'Falha na consulta.' } end
    local people = {}
    for _, row in ipairs(rows) do
        people[#people + 1] = {
            userId = tonumber(row.user_id),
            name = characterName(row),
            phone = row.phone_number or 'N/A',
            birthdate = row.birthdate,
            gender = tonumber(row.gender) or 0,
            nationality = row.nationality or 'N/A',
        }
    end
    return { ok = true, data = people }
end)

OR.Callback.register('queryPlate', function(playerSource, payload)
    payload = type(payload) == 'table' and payload or {}
    if not canOpen(playerSource, 'police') then return { ok = false, message = 'Sem permissão.' } end
    local plate = cleanText(payload.plate, 16, ''):upper():gsub('%s+', '')
    if plate == '' then return { ok = false, message = 'Informe a placa.' } end
    local row, errorMessage = OR.Database.single.await([[SELECT v.plate, v.model, v.label, v.owner_user_id,
        c.firstname, c.lastname FROM ob_vehicles v
        LEFT JOIN ob_characters c ON c.user_id = v.owner_user_id
        WHERE REPLACE(UPPER(v.plate), ' ', '') = ? LIMIT 1]], { plate })
    if row == nil then return { ok = false, message = errorMessage or 'Placa não encontrada.' } end
    return { ok = true, data = {
        plate = row.plate,
        model = row.label or row.model,
        ownerUserId = tonumber(row.owner_user_id),
        ownerName = characterName(row),
    } }
end)

OR.Callback.register('getHistory', function(playerSource, payload)
    payload = type(payload) == 'table' and payload or {}
    local mode = payload.mode == 'lawyer' and 'lawyer' or 'police'
    if not canOpen(playerSource, mode) then return { ok = false, message = 'Sem permissão.' } end
    local userId = math.floor(tonumber(payload.userId) or 0)
    if userId < 1 then return { ok = false, message = 'ID fixo inválido.' } end
    local rows, errorMessage = OR.Database.query.await([[SELECT id, suspect_user_id, suspect_name, officer_name,
        reason, crimes_json, months, fine, fine_status, bail_amount, lawyer_required, mugshot_url,
        inventory_photo_url, seized_items, cleared, cleared_by_name, cleared_reason, cleared_at, created_at
        FROM ob_mdt_records WHERE suspect_user_id = ? ORDER BY id DESC LIMIT ?]], {
        userId,
        math.max(1, math.min(200, OBMdtConfig.HistoryLimit or 100)),
    })
    if rows == nil then return { ok = false, message = errorMessage or 'Falha ao consultar o histórico.' } end
    for _, row in ipairs(rows) do
        local decoded = type(row.crimes_json) == 'string' and json.decode(row.crimes_json) or row.crimes_json
        row.crimes = type(decoded) == 'table' and decoded or {}
        row.crimes_json = nil
        row.suspect_user_id = tonumber(row.suspect_user_id)
        row.months = tonumber(row.months) or 0
        row.fine = tonumber(row.fine) or 0
        row.bail_amount = tonumber(row.bail_amount) or 0
        row.lawyer_required = tonumber(row.lawyer_required) == 1
        row.cleared = tonumber(row.cleared) == 1
    end
    return { ok = true, data = rows }
end)

OR.Callback.register('createRecord', function(playerSource, payload)
    payload = type(payload) == 'table' and payload or {}
    if not canOpen(playerSource, 'police') then return { ok = false, message = 'Você precisa estar em serviço na Polícia.' } end
    local suspects = type(payload.suspects) == 'table' and payload.suspects or {}
    local maximumSuspects = math.max(1, OBMdtConfig.MaximumSuspectsPerRecord or 8)
    if #suspects < 1 then return { ok = false, message = 'Adicione ao menos um suspeito.' } end
    if #suspects > maximumSuspects then return { ok = false, message = ('Máximo de %s suspeitos por registro.'):format(maximumSuspects) } end

    local crimes, automaticMonths, automaticFine = normalizeCrimes(payload.crimeCodes)
    local months = math.max(0, math.min(OBMdtConfig.MaximumMonths or 240, math.floor(tonumber(payload.months) or automaticMonths)))
    local fine = math.max(0, math.min(OBMdtConfig.MaximumFine or 10000000, math.floor(tonumber(payload.fine) or automaticFine)))
    local reason = cleanText(payload.reason, 1000, 'Sem descrição.')
    local bailAmount = math.max(0, math.min(OBMdtConfig.MaximumFine or 10000000, math.floor(tonumber(payload.bailAmount) or 0)))
    local officerUserId = tonumber(exports.ob_core:GetUserId(playerSource))
    if not officerUserId then return { ok = false, message = 'Personagem do policial não carregado.' } end
    local officerName = exports.ob_core:GetFullName(playerSource) or GetPlayerName(playerSource)
    local warnings, records, seen = {}, {}, {}

    for _, suspect in ipairs(suspects) do
        local targetUserId = math.floor(tonumber(type(suspect) == 'table' and suspect.userId) or 0)
        if targetUserId > 0 and not seen[targetUserId] then
            seen[targetUserId] = true
            local character = OR.Database.single.await([[SELECT user_id, firstname, lastname FROM ob_characters
                WHERE user_id = ? AND deleted_at IS NULL AND blocked_at IS NULL LIMIT 1]], { targetUserId })
            if character then
                local suspectName = characterName(character)
                local recordId, insertError = OR.Database.insert.await([[INSERT INTO ob_mdt_records
                    (suspect_user_id, suspect_name, officer_user_id, officer_name, reason, crimes_json, months,
                     fine, bail_amount, lawyer_required, mugshot_url, inventory_photo_url, seized_items)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
                    targetUserId,
                    suspectName,
                    officerUserId,
                    cleanText(officerName, 80, 'Policial'),
                    reason,
                    json.encode(crimes),
                    months,
                    fine,
                    bailAmount,
                    payload.lawyerRequired == true and 1 or 0,
                    safeUrl(payload.mugshotUrl),
                    safeUrl(payload.inventoryPhotoUrl),
                    cleanText(payload.seizedItems, 1000, ''),
                })
                recordId = tonumber(recordId)
                if recordId then
                    records[#records + 1] = recordId
                    if months > 0 then
                        local prisonOk, prisonResult = exports.ob_prison:SentenceByUserId(playerSource, targetUserId, months, reason, recordId)
                        if not prisonOk then warnings[#warnings + 1] = ('%s: %s'):format(suspectName, prisonResult or 'prisão não aplicada') end
                    end
                else
                    warnings[#warnings + 1] = ('%s: %s'):format(suspectName, insertError or 'registro não salvo')
                end
            else
                warnings[#warnings + 1] = ('ID %s: personagem não encontrado'):format(targetUserId)
            end
        end
    end
    if #records < 1 then return { ok = false, message = table.concat(warnings, ' | ') } end
    local message = ('%s registro(s) criado(s).'):format(#records)
    if fine > 0 then message = message .. ' Multa registrada como pendente.' end
    if #warnings > 0 then message = message .. ' Avisos: ' .. table.concat(warnings, ' | ') end
    return { ok = true, message = message, recordIds = records }
end)

OR.Callback.register('clearRecord', function(playerSource, payload)
    payload = type(payload) == 'table' and payload or {}
    local mode = payload.mode == 'lawyer' and 'lawyer' or 'police'
    if not canOpen(playerSource, mode) then return { ok = false, message = 'Sem acesso ao MDT.' } end
    local permissions = permissionFlags(playerSource, mode)
    if not permissions.canClear then return { ok = false, message = 'Seu cargo não pode limpar fichas.' } end
    local recordId = math.floor(tonumber(payload.recordId) or 0)
    local reason = cleanText(payload.reason, 500, '')
    if recordId < 1 then return { ok = false, message = 'Registro inválido.' } end
    if #reason < 3 then return { ok = false, message = 'Informe o motivo da limpeza.' } end
    local cleanerUserId = tonumber(exports.ob_core:GetUserId(playerSource))
    local cleanerName = exports.ob_core:GetFullName(playerSource) or GetPlayerName(playerSource)
    local changed, updateError = OR.Database.update.await([[UPDATE ob_mdt_records SET cleared = 1,
        cleared_by_user_id = ?, cleared_by_name = ?, cleared_reason = ?, cleared_at = CURRENT_TIMESTAMP
        WHERE id = ? AND cleared = 0]], {
        cleanerUserId,
        cleanText(cleanerName, 80, 'Responsável'),
        reason,
        recordId,
    })
    if changed == nil then return { ok = false, message = updateError or 'Falha no banco.' } end
    if changed < 1 then return { ok = false, message = 'Registro inexistente ou já limpo.' } end
    OR.Database.insert.await([[INSERT INTO ob_mdt_clear_audit
        (record_id, cleaner_user_id, cleaner_name, cleaner_mode, note) VALUES (?, ?, ?, ?, ?)]], {
        recordId,
        cleanerUserId,
        cleanText(cleanerName, 80, 'Responsável'),
        mode,
        reason,
    })
    return { ok = true, message = 'Ficha limpa e ação registrada na auditoria.' }
end)

OR.Callback.register('getClearAudit', function(playerSource, payload)
    payload = type(payload) == 'table' and payload or {}
    local mode = payload.mode == 'lawyer' and 'lawyer' or 'police'
    if not canOpen(playerSource, mode) then return { ok = false, message = 'Sem acesso ao MDT.' } end
    if not permissionFlags(playerSource, mode).canSeeAudit then return { ok = false, message = 'Sem permissão para a auditoria.' } end
    local rows, errorMessage = OR.Database.query.await([[SELECT a.id, a.record_id, a.cleaner_user_id,
        a.cleaner_name, a.cleaner_mode, a.note, a.created_at, r.suspect_user_id, r.suspect_name
        FROM ob_mdt_clear_audit a
        LEFT JOIN ob_mdt_records r ON r.id = a.record_id
        ORDER BY a.id DESC LIMIT 200]], {})
    if rows == nil then return { ok = false, message = errorMessage or 'Falha ao consultar auditoria.' } end
    return { ok = true, data = rows }
end)

CreateThread(ensureSchema)
