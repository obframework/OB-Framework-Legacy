AdminDatabase = {
    ready = false,
    characterAdmins = {},
}

local migrations = {
    [[CREATE TABLE IF NOT EXISTS ob_admin_audit (
    id bigint unsigned NOT NULL AUTO_INCREMENT,
    admin_license varchar(80) DEFAULT NULL,
    admin_source smallint unsigned DEFAULT NULL,
    admin_user_id bigint unsigned DEFAULT NULL,
    target_license varchar(80) DEFAULT NULL,
    target_source smallint unsigned DEFAULT NULL,
    target_user_id bigint unsigned DEFAULT NULL,
    action varchar(40) NOT NULL,
    details varchar(255) DEFAULT NULL,
    created_at timestamp NOT NULL DEFAULT current_timestamp(),
    PRIMARY KEY (id),
    KEY idx_ob_admin_audit_created_at (created_at),
    KEY idx_ob_admin_audit_target_license (target_license)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],
    [[CREATE TABLE IF NOT EXISTS ob_admin_characters (
    user_id bigint unsigned NOT NULL,
    role varchar(32) NOT NULL DEFAULT 'admin',
    granted_by_user_id bigint unsigned DEFAULT NULL,
    created_at timestamp NOT NULL DEFAULT current_timestamp(),
    PRIMARY KEY (user_id),
    KEY idx_ob_admin_characters_granted_by (granted_by_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],
}

local function validUserId(userId)
    userId = tonumber(userId)
    if not userId or userId <= 0 or userId ~= math.floor(userId) then return nil end
    return userId
end

local function validRole(role)
    role = type(role) == 'string' and role:lower() or ''
    return ORAdminConfig.Roles[role] and role or nil
end

local function ensureRoleColumn()
    local row, err = OR.Database.single.await([[SELECT 1 AS exists_column
        FROM information_schema.COLUMNS
        WHERE table_schema = DATABASE() AND table_name = 'ob_admin_characters' AND column_name = 'role'
        LIMIT 1]])
    if row == nil and err then return false, err end
    if row then return true end

    local result, alterError = OR.Database.query.await([[ALTER TABLE ob_admin_characters
        ADD COLUMN role varchar(32) NOT NULL DEFAULT 'admin' AFTER user_id]])
    if result == nil then return false, alterError end
    return true
end

CreateThread(function()
    if not OR.Database.waitForReady(15000) then
        print(('[ob_admin] Auditoria indisponivel: %s'):format(OR.Database.getError() or 'banco de dados nao respondeu.'))
        return
    end

    local coreDeadline = GetGameTimer() + 15000
    while not exports.ob_core:IsDatabaseReady() and GetGameTimer() < coreDeadline do
        Wait(100)
    end
    if not exports.ob_core:IsDatabaseReady() then
        print('[ob_admin] Schema do ob_core nao ficou pronto a tempo.')
        return
    end

    for index = 1, #migrations do
        local result, err = OR.Database.query.await(migrations[index])
        if result == nil then
            print(('[ob_admin] Falha ao preparar o banco administrativo: %s'):format(err or 'erro desconhecido.'))
            return
        end
    end

    local roleColumnReady, roleColumnError = ensureRoleColumn()
    if not roleColumnReady then
        print(('[ob_admin] Falha ao atualizar os cargos administrativos: %s'):format(roleColumnError or 'erro desconhecido.'))
        return
    end

    local normalized, normalizeError = OR.Database.query.await([[UPDATE ob_admin_characters
        SET role = 'admin'
        WHERE role IS NULL OR role = '']])
    if normalized == nil then
        print(('[ob_admin] Falha ao normalizar os cargos administrativos: %s'):format(normalizeError or 'erro desconhecido.'))
        return
    end

    local rows, err = OR.Database.query.await('SELECT user_id, role FROM ob_admin_characters')
    if rows == nil then
        print(('[ob_admin] Falha ao carregar administradores por personagem: %s'):format(err or 'erro desconhecido.'))
        return
    end

    for index = 1, #rows do
        local userId = validUserId(rows[index].user_id)
        if userId then
            AdminDatabase.characterAdmins[userId] = validRole(rows[index].role) or ORAdminConfig.DefaultRole
        end
    end

    AdminDatabase.ready = true
    print(('[ob_admin] Banco administrativo pronto. %s administrador(es) por personagem carregado(s).'):format(#rows))
end)

function AdminDatabase.isCharacterAdmin(userId)
    userId = validUserId(userId)
    return userId and AdminDatabase.characterAdmins[userId] ~= nil or false
end

function AdminDatabase.getCharacterRole(userId)
    userId = validUserId(userId)
    return userId and AdminDatabase.characterAdmins[userId] or nil
end

function AdminDatabase.getRoles()
    local roles = {}
    for key, definition in pairs(ORAdminConfig.Roles) do
        roles[#roles + 1] = { key = key, label = definition.label or key }
    end
    table.sort(roles, function(a, b) return a.label < b.label end)
    return roles
end

function AdminDatabase.hasOwner(exceptUserId)
    exceptUserId = validUserId(exceptUserId)
    for userId, role in pairs(AdminDatabase.characterAdmins) do
        if role == 'owner' and userId ~= exceptUserId then return true end
    end
    return false
end

function AdminDatabase.grantCharacterAdmin(userId, role, grantedByUserId)
    if not AdminDatabase.ready then return false, 'Banco administrativo ainda nao esta pronto.' end

    userId = validUserId(userId)
    if role == nil then
        role = validRole(ORAdminConfig.DefaultRole)
    else
        role = validRole(role)
    end
    grantedByUserId = validUserId(grantedByUserId)
    if not userId then return false, 'ID fixo do personagem invalido.' end
    if not role then return false, 'Cargo administrativo invalido.' end
    if role == 'owner' and AdminDatabase.hasOwner(userId) then
        return false, 'Ja existe um owner. O owner atual precisa ser removido pelo console antes da troca.'
    end

    local character = OR.Database.single.await([[SELECT user_id FROM ob_characters
        WHERE user_id = ? AND deleted_at IS NULL AND blocked_at IS NULL LIMIT 1]], { userId })
    if not character then return false, 'Nenhum personagem ativo foi encontrado com esse ID fixo.' end

    local statement
    local parameters
    if grantedByUserId then
        statement = [[INSERT INTO ob_admin_characters (user_id, role, granted_by_user_id)
            VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE role = VALUES(role), granted_by_user_id = VALUES(granted_by_user_id)]]
        parameters = { userId, role, grantedByUserId }
    else
        -- O console do txAdmin nao possui personagem autor. Nao passe nil
        -- para mysql2: a ponte Lua/JS remove esse argumento da consulta.
        statement = [[INSERT INTO ob_admin_characters (user_id, role)
            VALUES (?, ?)
            ON DUPLICATE KEY UPDATE role = VALUES(role)]]
        parameters = { userId, role }
    end

    local result, err = OR.Database.query.await(statement, parameters)
    if result == nil then return false, err or 'Nao foi possivel salvar a permissao administrativa.' end

    AdminDatabase.characterAdmins[userId] = role
    return true
end

function AdminDatabase.revokeCharacterAdmin(userId)
    if not AdminDatabase.ready then return false, 'Banco administrativo ainda nao esta pronto.' end

    userId = validUserId(userId)
    if not userId then return false, 'ID fixo do personagem invalido.' end

    local result, err = OR.Database.update.await('DELETE FROM ob_admin_characters WHERE user_id = ?', { userId })
    if result == nil then return false, err or 'Nao foi possivel remover a permissao administrativa.' end

    AdminDatabase.characterAdmins[userId] = nil
    return true, tonumber(result) and tonumber(result) > 0 or false
end

function AdminDatabase.record(actor, target, action, details)
    if not AdminDatabase.ready then return false end

    local columns = {}
    local placeholders = {}
    local parameters = {}
    local function add(column, value)
        if value == nil then return end
        columns[#columns + 1] = column
        placeholders[#placeholders + 1] = '?'
        parameters[#parameters + 1] = value
    end

    add('admin_license', actor and actor.license)
    add('admin_source', actor and actor.source)
    add('admin_user_id', actor and actor.character and actor.character.userId)
    add('target_license', target and target.license)
    add('target_source', target and target.source)
    add('target_user_id', target and target.character and target.character.userId)
    add('action', action)
    add('details', details)

    local statement = ('INSERT INTO ob_admin_audit (%s) VALUES (%s)'):format(table.concat(columns, ', '), table.concat(placeholders, ', '))
    local result, err = OR.Database.insert.await(statement, parameters)

    if result == nil then
        print(('[ob_admin] Falha ao registrar acao %s: %s'):format(action, err or 'erro desconhecido.'))
        return false
    end

    return true
end
