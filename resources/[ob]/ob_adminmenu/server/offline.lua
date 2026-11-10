local Config = OBOfflineAdminConfig or {}
local schemaReady = false
local deletingLicenses = {}
local wipeRunning = false

local function clean(value, maximum)
    value = tostring(value or ''):gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return maximum and value:sub(1, maximum) or value
end

local function integer(value)
    value = tonumber(value)
    return value and value > 0 and value == math.floor(value) and value or nil
end

local function licenseFromSource(playerSource)
    for _, identifier in ipairs(GetPlayerIdentifiers(playerSource)) do
        if identifier:sub(1, 8) == 'license:' then return identifier end
    end
    for _, identifier in ipairs(GetPlayerIdentifiers(playerSource)) do
        if identifier:sub(1, 9) == 'license2:' then return identifier end
    end
end

local function actorUserId(source)
    return tonumber(exports.ob_core:GetUserId(source))
end

local function isOwner(source)
    return exports.ob_admin:GetRole(source) == 'owner'
end

local function canView(source)
    return exports.ob_admin:HasPermission(source, 'offline.players.view') == true
end

local function accountOnline(license)
    for _, rawSource in ipairs(GetPlayers()) do
        local playerSource = tonumber(rawSource)
        local player = playerSource and exports.ob_core:GetPlayer(playerSource)
        if player and player.license == license then return playerSource end
        if playerSource and licenseFromSource(playerSource) == license then return playerSource end
    end
end

local function tableExists(name)
    return tonumber(OR.Database.scalar.await([[SELECT COUNT(*) FROM information_schema.tables
        WHERE table_schema=DATABASE() AND table_name=?]], { name })) == 1
end

local function ensureSchema()
    if schemaReady then return true end
    if not OR.Database.waitForReady(30000) then return false end
    local statements = {
        [[CREATE TABLE IF NOT EXISTS ob_admin_account_bans (
            license varchar(80) NOT NULL PRIMARY KEY,
            player_id bigint unsigned NULL,
            reason varchar(255) NOT NULL,
            banned_by_user_id bigint unsigned NOT NULL,
            active tinyint(1) NOT NULL DEFAULT 1,
            expires_at datetime NULL,
            created_at timestamp NOT NULL DEFAULT current_timestamp(),
            revoked_at datetime NULL,
            revoked_by_user_id bigint unsigned NULL,
            KEY idx_ob_admin_bans_player (player_id),
            KEY idx_ob_admin_bans_active (active,expires_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS ob_admin_account_archives (
            id bigint unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,
            player_id bigint unsigned NOT NULL,
            license varchar(80) NOT NULL,
            archived_by_user_id bigint unsigned NOT NULL,
            reason varchar(255) NOT NULL,
            snapshot longtext NOT NULL,
            created_at timestamp NOT NULL DEFAULT current_timestamp(),
            KEY idx_ob_admin_archive_player (player_id,created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS ob_admin_destructive_audit (
            id bigint unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,
            actor_user_id bigint unsigned NOT NULL,
            action varchar(64) NOT NULL,
            target_player_id bigint unsigned NULL,
            target_user_id bigint unsigned NULL,
            details longtext NULL,
            created_at timestamp NOT NULL DEFAULT current_timestamp(),
            KEY idx_ob_admin_destructive_actor (actor_user_id,created_at),
            KEY idx_ob_admin_destructive_target (target_player_id,target_user_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    }
    for _, statement in ipairs(statements) do
        local result, err = OR.Database.query.await(statement)
        if result == nil then
            print(('[ob_adminmenu] Falha ao preparar gerenciador offline: %s'):format(tostring(err)))
            return false
        end
    end
    schemaReady = true
    return true
end

CreateThread(ensureSchema)

local function destructiveAuditByActor(actor, action, playerId, userId, details)
    if not actor then return end
    OR.Database.insert.await([[INSERT INTO ob_admin_destructive_audit
        (actor_user_id,action,target_player_id,target_user_id,details) VALUES (?,?,?,?,?)]], {
        -- A ponte Lua/JS remove nil do array e isso causaria PARAMETER_COUNT.
        -- Zero representa "sem alvo" nos eventos globais, como o wipe.
        actor, clean(action, 64), integer(playerId) or 0, integer(userId) or 0, clean(details, 12000)
    })
end

local function destructiveAudit(source, action, playerId, userId, details)
    local actor = actorUserId(source)
    destructiveAuditByActor(actor, action, playerId, userId, details)
    if not actor then return end
    exports.ob_admin:RecordOfflineAudit(source, userId, action, clean(details, 900))
end

local function accountByCharacter(userId)
    return OR.Database.single.await([[SELECT p.id AS player_id,p.license,p.display_name,p.first_seen_at,p.last_seen_at,
        c.user_id,c.firstname,c.lastname,c.slot,c.deleted_at,c.blocked_at,c.blocked_reason,
        a.role AS admin_role
        FROM ob_characters c JOIN ob_players p ON BINARY p.license=BINARY c.license
        LEFT JOIN ob_admin_characters a ON a.user_id=c.user_id
        WHERE c.user_id=? LIMIT 1]], { userId })
end

local function hasStaffCharacter(playerId)
    return OR.Database.scalar.await([[SELECT a.user_id FROM ob_players p
        JOIN ob_characters c ON BINARY c.license=BINARY p.license
        JOIN ob_admin_characters a ON a.user_id=c.user_id
        WHERE p.id=? LIMIT 1]], { playerId }) ~= nil
end

local function inventoryFor(userId)
    local encoded = OR.Database.scalar.await([[SELECT items FROM ob_inventories
        WHERE owner_type='player' AND owner_id=? LIMIT 1]], { tostring(userId) })
    local ok, payload = pcall(json.decode, type(encoded) == 'string' and encoded or '{}')
    payload = ok and type(payload) == 'table' and payload or {}
    -- Inventarios novos usam { items = {...} }; a migracao antiga salvava o
    -- mapa de slots diretamente. O painel precisa conseguir ler os dois.
    local storedItems = type(payload.items) == 'table' and payload.items or payload
    local result = {}
    for slot, item in pairs(storedItems) do
        if type(item) == 'table' then
            result[#result + 1] = {
                slot = tonumber(slot) or slot,
                name = clean(item.name, 80),
                amount = math.max(0, math.floor(tonumber(item.amount) or 0)),
                metadata = type(item.metadata) == 'table' and item.metadata or {},
            }
        end
    end
    table.sort(result, function(a, b) return (tonumber(a.slot) or 9999) < (tonumber(b.slot) or 9999) end)
    return result
end

OR.Callback.register('offlineBootstrap', function(source)
    if not canView(source) then return nil, 'Sem permissao para gerenciar jogadores.' end
    if not ensureSchema() then return nil, 'Banco administrativo indisponivel.' end
    return {
        roles = exports.ob_admin:GetRoles(),
        isOwner = isOwner(source),
        canBan = exports.ob_admin:HasPermission(source, 'account.ban') == true,
        canDeleteCharacter = exports.ob_admin:HasPermission(source, 'character.delete') == true,
    }
end)

OR.Callback.register('offlineSearch', function(source, rawQuery)
    if not canView(source) then return nil, 'Sem permissao para consultar jogadores.' end
    if not OR.Security.rateLimit(source, 'adminmenu:offline:search', 8, 10000) then
        return nil, 'Aguarde um instante antes de pesquisar novamente.'
    end
    local query = clean(rawQuery, 80)
    local like = '%' .. query:gsub('([%%_])', '\\%1') .. '%'
    local numeric = integer(query)
    local limit = math.max(10, math.min(100, tonumber(Config.SearchLimit) or 60))
    local rows, searchError = OR.Database.query.await(([[SELECT p.id AS player_id,p.display_name,p.last_seen_at,
        c.user_id,c.firstname,c.lastname,c.deleted_at,c.blocked_at,a.role AS admin_role,
        CASE WHEN b.active=1 AND (b.expires_at IS NULL OR b.expires_at>NOW()) THEN 1 ELSE 0 END AS banned
        FROM ob_players p LEFT JOIN ob_characters c ON BINARY c.license=BINARY p.license
        LEFT JOIN ob_admin_characters a ON a.user_id=c.user_id
        LEFT JOIN ob_admin_account_bans b ON BINARY b.license=BINARY p.license
        WHERE (?='' OR p.display_name LIKE ? ESCAPE '\\' OR c.firstname LIKE ? ESCAPE '\\'
            OR c.lastname LIKE ? ESCAPE '\\' OR p.id=? OR c.user_id=?)
        ORDER BY p.last_seen_at DESC,c.user_id ASC LIMIT %d]]):format(limit), {
        query, like, like, like, numeric or 0, numeric or 0
    })
    if not rows then return nil, searchError or 'Nao foi possivel consultar as contas offline.' end
    for _, row in ipairs(rows) do
        row.player_id, row.user_id = tonumber(row.player_id), tonumber(row.user_id)
        row.banned = tonumber(row.banned) == 1
        row.online = row.user_id and exports.ob_core:GetSourceByUserId(row.user_id) ~= nil or false
    end
    return rows
end)

OR.Callback.register('offlineDetails', function(source, rawUserId)
    if not canView(source) then return nil, 'Sem permissao para consultar jogadores.' end
    local userId = integer(rawUserId)
    if not userId then return nil, 'ID fixo invalido.' end
    local row = accountByCharacter(userId)
    if not row then return nil, 'Personagem nao encontrado.' end
    local ban = OR.Database.single.await([[SELECT reason,expires_at,created_at FROM ob_admin_account_bans
        WHERE license=? AND active=1 AND (expires_at IS NULL OR expires_at>NOW()) LIMIT 1]], { row.license })
    local characters = OR.Database.query.await([[SELECT c.user_id,c.firstname,c.lastname,c.slot,c.deleted_at,c.blocked_at,
        a.role AS admin_role FROM ob_characters c LEFT JOIN ob_admin_characters a ON a.user_id=c.user_id
        WHERE c.license=? ORDER BY c.user_id]], { row.license }) or {}
    for _, character in ipairs(characters) do
        character.user_id = tonumber(character.user_id)
        character.online = exports.ob_core:GetSourceByUserId(character.user_id) ~= nil
    end
    return {
        account = { playerId=tonumber(row.player_id), displayName=row.display_name,
            firstSeen=row.first_seen_at, lastSeen=row.last_seen_at, online=accountOnline(row.license) ~= nil },
        character = { userId=tonumber(row.user_id), firstname=row.firstname, lastname=row.lastname,
            slot=tonumber(row.slot), deleted=row.deleted_at ~= nil, blocked=row.blocked_at ~= nil,
            blockedReason=row.blocked_reason, role=row.admin_role or 'player' },
        characters = characters,
        inventory = exports.ob_admin:HasPermission(source, 'offline.inventory.view') and inventoryFor(userId) or {},
        ban = ban,
        isOwner = isOwner(source),
        canBan = exports.ob_admin:HasPermission(source, 'account.ban') == true,
        canDeleteCharacter = exports.ob_admin:HasPermission(source, 'character.delete') == true,
    }
end)

OR.Callback.register('offlineSetRole', function(source, payload)
    payload = type(payload) == 'table' and payload or {}
    local userId = integer(payload.userId)
    if not userId then return nil, 'ID fixo invalido.' end
    local account = accountByCharacter(userId)
    if not account then return nil, 'Personagem nao encontrado.' end
    if accountOnline(account.license) then return nil, 'Use o painel online para essa conta conectada.' end
    local ok, message = exports.ob_admin:SetOfflineRole(source, userId, clean(payload.role, 32))
    return ok and true or nil, message
end)

OR.Callback.register('offlineBan', function(source, payload)
    if not exports.ob_admin:HasPermission(source, 'account.ban') then return nil, 'Sem permissao para banir contas.' end
    if not ensureSchema() then return nil, 'Banco administrativo indisponivel.' end
    payload = type(payload) == 'table' and payload or {}
    local userId, reason = integer(payload.userId), clean(payload.reason, 255)
    if not userId or #reason < 3 then return nil, 'Informe um motivo com pelo menos 3 caracteres.' end
    local row = accountByCharacter(userId)
    if not row then return nil, 'Conta nao encontrada.' end
    if accountOnline(row.license) then return nil, 'Este gerenciador aceita apenas contas offline.' end
    if hasStaffCharacter(row.player_id) and not isOwner(source) then return nil, 'Somente o owner pode punir uma conta de staff.' end
    local hours = math.max(0, math.min(87600, math.floor(tonumber(payload.hours) or 0)))
    local statement, parameters
    if hours > 0 then
        statement = [[INSERT INTO ob_admin_account_bans
            (license,player_id,reason,banned_by_user_id,active,expires_at,revoked_at,revoked_by_user_id)
            VALUES (?,?,?,?,1,DATE_ADD(NOW(),INTERVAL ? HOUR),NULL,NULL)
            ON DUPLICATE KEY UPDATE player_id=VALUES(player_id),reason=VALUES(reason),
            banned_by_user_id=VALUES(banned_by_user_id),active=1,expires_at=VALUES(expires_at),revoked_at=NULL,revoked_by_user_id=NULL]]
        parameters = { row.license, row.player_id, reason, actorUserId(source), hours }
    else
        statement = [[INSERT INTO ob_admin_account_bans
            (license,player_id,reason,banned_by_user_id,active,expires_at,revoked_at,revoked_by_user_id)
            VALUES (?,?,?,?,1,NULL,NULL,NULL)
            ON DUPLICATE KEY UPDATE player_id=VALUES(player_id),reason=VALUES(reason),
            banned_by_user_id=VALUES(banned_by_user_id),active=1,expires_at=NULL,revoked_at=NULL,revoked_by_user_id=NULL]]
        parameters = { row.license, row.player_id, reason, actorUserId(source) }
    end
    local changed, err = OR.Database.query.await(statement, parameters)
    if changed == nil then return nil, err or 'Nao foi possivel salvar o banimento.' end
    destructiveAudit(source, 'offline_account_ban', row.player_id, userId,
        ('hours=%s reason=%s'):format(hours, reason))
    return true, hours > 0 and ('Conta banida por %s hora(s).'):format(hours) or 'Conta banida permanentemente.'
end)

OR.Callback.register('offlineUnban', function(source, rawUserId)
    if not exports.ob_admin:HasPermission(source, 'account.ban') then return nil, 'Sem permissao para remover banimentos.' end
    local userId = integer(rawUserId)
    local row = userId and accountByCharacter(userId)
    if not row then return nil, 'Conta nao encontrada.' end
    local changed, err = OR.Database.update.await([[UPDATE ob_admin_account_bans SET active=0,revoked_at=NOW(),
        revoked_by_user_id=? WHERE license=? AND active=1]], { actorUserId(source), row.license })
    if changed == nil then return nil, err or 'Nao foi possivel remover o banimento.' end
    destructiveAudit(source, 'offline_account_unban', row.player_id, userId, '')
    return true, tonumber(changed) > 0 and 'Banimento removido.' or 'A conta nao possuia banimento ativo.'
end)

OR.Callback.register('offlineDeleteCharacter', function(source, payload)
    if not exports.ob_admin:HasPermission(source, 'character.delete') then return nil, 'Sem permissao para excluir personagens.' end
    payload = type(payload) == 'table' and payload or {}
    local userId = integer(payload.userId)
    if not userId or clean(payload.confirm, 80) ~= ('EXCLUIR PERSONAGEM %s'):format(userId) then
        return nil, ('Digite EXCLUIR PERSONAGEM %s para confirmar.'):format(userId or '?')
    end
    local row = accountByCharacter(userId)
    if not row then return nil, 'Personagem nao encontrado.' end
    if exports.ob_core:GetSourceByUserId(userId) then return nil, 'O personagem precisa estar offline.' end
    if row.admin_role then return nil, 'Remova primeiro o cargo de staff desse personagem.' end
    if hasStaffCharacter(row.player_id) and not isOwner(source) then
        return nil, 'Somente o owner pode excluir personagens vinculados a uma conta de staff.'
    end
    local ok, err = exports.ob_core:DeleteCharacter(userId)
    if not ok then return nil, err end
    destructiveAudit(source, 'offline_character_delete', row.player_id, userId,
        ('name=%s %s'):format(row.firstname or '', row.lastname or ''))
    return true, 'Personagem excluido logicamente. Os dados permanecem recuperaveis no banco.'
end)

local protectedTables = {
    ob_admin_audit=true, ob_admin_destructive_audit=true, ob_admin_account_archives=true,
    ob_players=true, ob_characters=true, ob_character_slots=true, ob_admin_account_bans=true,
}

local function accountSnapshot(player, characters)
    local inventories = {}
    for _, character in ipairs(characters) do inventories[tostring(character.user_id)] = inventoryFor(character.user_id) end
    return json.encode({ player=player, characters=characters, inventories=inventories, archivedAt=os.time() })
end

local function deletionStatements(player, characters)
    local statements, seen = {}, {}
    local function add(statement, parameters)
        local key = statement .. '|' .. json.encode(parameters)
        if seen[key] then return end
        seen[key] = true
        statements[#statements + 1] = { kind='update', statement=statement, parameters=parameters }
    end
    local columns, columnsError = OR.Database.query.await([[SELECT DISTINCT c.table_name,c.column_name
        FROM information_schema.columns c
        WHERE c.table_schema=DATABASE() AND c.column_name IN ('user_id','owner_user_id','character_id','purchaser_user_id')]])
    if not columns then return nil, columnsError or 'Nao foi possivel mapear os dados da conta.' end
    local foreign, foreignError = OR.Database.query.await([[SELECT DISTINCT table_name,column_name FROM information_schema.key_column_usage
        WHERE table_schema=DATABASE() AND referenced_table_name='ob_characters' AND referenced_column_name='user_id']])
    if not foreign then return nil, foreignError or 'Nao foi possivel mapear as dependencias dos personagens.' end
    for _, row in ipairs(foreign) do columns[#columns + 1] = row end

    local userIds, textUserIds = {}, {}
    for _, character in ipairs(characters) do
        local userId = tonumber(character.user_id)
        if userId then
            userIds[#userIds + 1] = userId
            textUserIds[#textUserIds + 1] = tostring(userId)
        end
    end
    if #userIds > 0 then
        local placeholders = table.concat((function()
            local values = {}; for index = 1, #userIds do values[index] = '?' end; return values
        end)(), ',')
        add(("DELETE FROM ob_inventories WHERE owner_type='player' AND owner_id IN (%s)"):format(placeholders), textUserIds)

        -- Agrupa varias colunas da mesma tabela numa unica instrucao. Alem de
        -- ser atomico, isso impede ultrapassar o limite de 100 operacoes da
        -- transacao quando uma conta possui varios personagens.
        local tableColumns = {}
        for _, entry in ipairs(columns) do
            local tableName, columnName = tostring(entry.table_name or ''), tostring(entry.column_name or '')
            if not protectedTables[tableName] and tableName:match('^[%w_]+$') and columnName:match('^[%w_]+$') then
                tableColumns[tableName] = tableColumns[tableName] or {}
                tableColumns[tableName][columnName] = true
            end
        end

        -- Tabelas filhas sao removidas antes das tabelas que elas referenciam.
        local edges, edgesError = OR.Database.query.await([[SELECT table_name,referenced_table_name
            FROM information_schema.key_column_usage WHERE table_schema=DATABASE()
            AND referenced_table_name IS NOT NULL]])
        if not edges then return nil, edgesError or 'Nao foi possivel ordenar as dependencias da conta.' end
        local depth = {}
        for _ = 1, 32 do
            local changed = false
            for _, edge in ipairs(edges) do
                local child, parent = tostring(edge.table_name or ''), tostring(edge.referenced_table_name or '')
                local nextDepth = (depth[parent] or 0) + 1
                if nextDepth > (depth[child] or 0) then depth[child] = nextDepth; changed = true end
            end
            if not changed then break end
        end
        local tables = {}
        for tableName in pairs(tableColumns) do tables[#tables + 1] = tableName end
        table.sort(tables, function(a, b)
            if (depth[a] or 0) == (depth[b] or 0) then return a < b end
            return (depth[a] or 0) > (depth[b] or 0)
        end)
        for _, tableName in ipairs(tables) do
            local clauses, parameters = {}, {}
            for columnName in pairs(tableColumns[tableName]) do
                clauses[#clauses + 1] = ('`%s` IN (%s)'):format(columnName, placeholders)
                for _, userId in ipairs(userIds) do parameters[#parameters + 1] = userId end
            end
            add(('DELETE FROM `%s` WHERE %s'):format(tableName, table.concat(clauses, ' OR ')), parameters)
        end
    end
    add('DELETE FROM ob_admin_account_bans WHERE license=?', { player.license })
    add('DELETE FROM ob_character_slots WHERE license=?', { player.license })
    add('DELETE FROM ob_characters WHERE license=?', { player.license })
    statements[#statements + 1] = { kind='update', statement='DELETE FROM ob_players WHERE id=? AND license=?',
        parameters={ player.id, player.license }, expectAffectedMin=1 }
    if #statements > 100 then
        return nil, ('A conta exige %s operacoes e excede o limite seguro da transacao.'):format(#statements)
    end
    return statements
end

local function deleteAccountInternal(source, playerId, reason, archivedByUserId, protectedLicense)
    local player = OR.Database.single.await([[SELECT id,license,fivem_identifier,display_name,first_seen_at,last_seen_at
        FROM ob_players WHERE id=? LIMIT 1]], { playerId })
    if not player then return false, 'Conta nao encontrada.' end
    if protectedLicense and player.license == protectedLicense then
        return false, 'A conta que ativou o wipe esta protegida.'
    end
    if accountOnline(player.license) then return false, 'A conta precisa estar offline.' end
    if hasStaffCharacter(playerId) then return false, 'A conta possui personagem de staff e foi protegida.' end
    if deletingLicenses[player.license] then return false, 'Esta conta ja possui uma exclusao em andamento.' end
    deletingLicenses[player.license] = true
    local function finish(ok, value)
        deletingLicenses[player.license] = nil
        return ok, value
    end
    local characters = OR.Database.query.await('SELECT * FROM ob_characters WHERE license=? ORDER BY user_id', { player.license }) or {}
    local snapshot = accountSnapshot(player, characters)
    if Config.ArchiveBeforeAccountDelete ~= false then
        local archiveId, archiveError = OR.Database.insert.await([[INSERT INTO ob_admin_account_archives
            (player_id,license,archived_by_user_id,reason,snapshot) VALUES (?,?,?,?,?)]], {
            playerId, player.license, archivedByUserId or actorUserId(source), clean(reason, 255), snapshot
        })
        if not archiveId then return finish(false, archiveError or 'Nao foi possivel criar o arquivo de seguranca.') end
    end
    local statements, statementError = deletionStatements(player, characters)
    if not statements then return finish(false, statementError) end
    local results, transactionError = OR.Database.transaction.await(statements)
    if not results then return finish(false, transactionError or 'A transacao de exclusao foi recusada.') end
    return finish(true, #characters)
end

OR.Callback.register('offlineDeleteAccount', function(source, payload)
    if not isOwner(source) then return nil, 'Somente o owner pode excluir uma conta inteira.' end
    payload = type(payload) == 'table' and payload or {}
    local playerId = integer(payload.playerId)
    if not playerId or clean(payload.confirm, 80) ~= ('EXCLUIR CONTA %s'):format(playerId) then
        return nil, ('Digite EXCLUIR CONTA %s para confirmar.'):format(playerId or '?')
    end
    if not OR.Security.rateLimit(source, 'adminmenu:offline:delete-account', 1, 30000) then
        return nil, 'Aguarde antes de executar outra exclusao de conta.'
    end
    local ok, countOrError = deleteAccountInternal(source, playerId, 'Exclusao manual pelo gerenciador offline')
    if not ok then return nil, countOrError end
    destructiveAudit(source, 'offline_account_delete', playerId, nil,
        ('characters=%s archive=1'):format(countOrError))
    return true, ('Conta e %s personagem(ns) excluidos. Um arquivo de seguranca foi criado. IDs intermediarios nao sao reciclados automaticamente.'):format(countOrError)
end)

OR.Callback.register('offlineWipeStatus', function(source)
    if not isOwner(source) then return nil, 'Somente o owner pode consultar o wipe.' end
    return { running=wipeRunning, confirmation=Config.WipeConfirmation or 'ATIVAR MODO WIPE' }
end)

OR.Callback.register('offlineWipe', function(source, payload)
    if not isOwner(source) then return nil, 'Somente o owner pode executar o wipe.' end
    if wipeRunning then return nil, 'O modo wipe ja esta em andamento.' end
    if not ensureSchema() then return nil, 'Banco administrativo indisponivel.' end
    if not OR.Security.rateLimit(source, 'adminmenu:offline:wipe', 1, 60000) then
        return nil, 'Aguarde antes de tentar ativar outro wipe.'
    end
    payload = type(payload) == 'table' and payload or {}
    local confirmation = clean(Config.WipeConfirmation or 'ATIVAR MODO WIPE', 80)
    if clean(payload.confirm, 80) ~= confirmation then
        return nil, ('Digite exatamente %s para confirmar.'):format(confirmation)
    end

    local actor = actorUserId(source)
    if not actor then return nil, 'O personagem do owner nao esta carregado.' end
    local actorLicense = licenseFromSource(source)
    if not actorLicense then return nil, 'Nao foi possivel proteger a conta do owner.' end
    local actorPlayerId = OR.Database.scalar.await('SELECT id FROM ob_players WHERE BINARY license=BINARY ? LIMIT 1', { actorLicense })
    actorPlayerId = tonumber(actorPlayerId)
    if not actorPlayerId then return nil, 'A conta do owner nao foi localizada e o wipe foi bloqueado.' end
    local actorSource = tonumber(source)
    wipeRunning = true
    destructiveAudit(source, 'wipe_mode_activated', nil, nil, 'Expulsao geral e exclusao automatica iniciadas.')

    CreateThread(function()
        -- Um pequeno intervalo permite que a confirmacao chegue a NUI do owner
        -- antes de a propria conexao dele ser encerrada.
        Wait(500)
        local kickMessage = clean(Config.WipeKickMessage or 'A cidade entrou em modo wipe. Tente novamente mais tarde.', 500)
        for _, rawSource in ipairs(GetPlayers()) do
            local playerSource = tonumber(rawSource)
            if playerSource and playerSource ~= actorSource then
                DropPlayer(tostring(rawSource), kickMessage)
            end
        end

        local deadline = GetGameTimer() + math.max(5000, tonumber(Config.WipeDisconnectWaitMs) or 15000)
        local function connectedExceptOwner()
            local count = 0
            for _, rawSource in ipairs(GetPlayers()) do
                if tonumber(rawSource) ~= actorSource then count = count + 1 end
            end
            return count
        end
        while connectedExceptOwner() > 0 and GetGameTimer() < deadline do Wait(250) end
        local remainingPlayers = connectedExceptOwner()
        if remainingPlayers > 0 then
            wipeRunning = false
            destructiveAuditByActor(actor, 'wipe_disconnect_failure', nil, nil,
                ('remaining_players=%s'):format(remainingPlayers))
            return print('[ob_adminmenu] WIPE CANCELADO: nem todos os jogadores foram desconectados.')
        end

        local accounts, accountsError = OR.Database.query.await([[SELECT p.id FROM ob_players p WHERE NOT EXISTS (
            SELECT 1 FROM ob_characters c JOIN ob_admin_characters a ON a.user_id=c.user_id
            WHERE BINARY c.license=BINARY p.license
        ) AND p.id<>? AND BINARY p.license<>BINARY ? ORDER BY p.id]], { actorPlayerId, actorLicense })
        if not accounts then
            wipeRunning = false
            destructiveAuditByActor(actor, 'wipe_start_failure', nil, nil, tostring(accountsError or 'account_query_failed'))
            return print(('[ob_adminmenu] WIPE INTERROMPIDO: %s'):format(accountsError or 'falha ao listar contas'))
        end

        local completed = 0
        for _, row in ipairs(accounts) do
            local ok, err = deleteAccountInternal(0, tonumber(row.id), 'Wipe de contas nao-staff', actor, actorLicense)
            if not ok then
                wipeRunning = false
                destructiveAuditByActor(actor, 'wipe_partial_failure', row.id, nil,
                    ('completed=%s error=%s'):format(completed, err))
                return print(('[ob_adminmenu] WIPE INTERROMPIDO apos %s conta(s): %s'):format(completed, err))
            end
            completed = completed + 1
            if completed % 10 == 0 then Wait(0) end
        end
        wipeRunning = false
        destructiveAuditByActor(actor, 'wipe_non_staff_complete', nil, nil, ('accounts=%s'):format(completed))
        print(('[ob_adminmenu] WIPE CONCLUIDO: %s conta(s) nao-staff excluidas e arquivadas.'):format(completed))
    end)

    return true, 'Modo wipe ativado. Os outros jogadores serao desconectados e sua conta permanecera protegida.'
end)

AddEventHandler('playerConnecting', function(_, _, deferrals)
    local playerSource = source
    local license = licenseFromSource(playerSource)
    if not license then return end
    deferrals.defer()
    Wait(0)
    if wipeRunning then
        return deferrals.done('O servidor esta concluindo uma manutencao administrativa. Tente novamente em instantes.')
    end
    if deletingLicenses[license] then
        return deferrals.done('Sua conta esta em manutencao administrativa. Tente novamente em instantes.')
    end
    deferrals.update('Verificando situacao administrativa...')
    if not ensureSchema() then
        return deferrals.done('O sistema administrativo esta indisponivel. Tente novamente em instantes.')
    end
    OR.Database.update.await([[UPDATE ob_admin_account_bans SET active=0
        WHERE active=1 AND expires_at IS NOT NULL AND expires_at<=NOW()]])
    local ban = OR.Database.single.await([[SELECT reason,expires_at FROM ob_admin_account_bans
        WHERE license=? AND active=1 AND (expires_at IS NULL OR expires_at>NOW()) LIMIT 1]], { license })
    if ban then
        local suffix = ban.expires_at and (' Ate: '..tostring(ban.expires_at)) or ' Permanente.'
        return deferrals.done(('Conta banida. Motivo: %s.%s'):format(clean(ban.reason,255), suffix))
    end
    deferrals.done()
end)
