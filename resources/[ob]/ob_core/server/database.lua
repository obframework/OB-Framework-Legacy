Database = {
    ready = false,
    error = nil,
}

local migrations = {
    [[CREATE TABLE IF NOT EXISTS `ob_players` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `license` varchar(80) NOT NULL,
        `fivem_identifier` varchar(80) DEFAULT NULL,
        `display_name` varchar(100) DEFAULT NULL,
        `first_seen_at` timestamp NOT NULL DEFAULT current_timestamp(),
        `last_seen_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
        PRIMARY KEY (`id`),
        UNIQUE KEY `uq_ob_players_license` (`license`),
        KEY `idx_ob_players_fivem_identifier` (`fivem_identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],
    [[CREATE TABLE IF NOT EXISTS `ob_characters` (
        `user_id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `license` varchar(80) NOT NULL,
        `slot` tinyint unsigned NOT NULL,
        `firstname` varchar(32) NOT NULL,
        `lastname` varchar(32) NOT NULL,
        `birthdate` date NOT NULL,
        `gender` tinyint unsigned NOT NULL DEFAULT 0,
        `nationality` varchar(48) NOT NULL DEFAULT 'Brasileiro',
        `last_position` longtext DEFAULT NULL,
        `metadata` longtext DEFAULT NULL,
        `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
        `last_played_at` timestamp NULL DEFAULT NULL,
        `deleted_at` timestamp NULL DEFAULT NULL,
        PRIMARY KEY (`user_id`),
        UNIQUE KEY `uq_ob_characters_license_slot` (`license`, `slot`),
        KEY `idx_ob_characters_license` (`license`),
        CONSTRAINT `fk_ob_characters_player` FOREIGN KEY (`license`) REFERENCES `ob_players` (`license`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],
    [[CREATE TABLE IF NOT EXISTS `ob_character_appearances` (
        `user_id` bigint unsigned NOT NULL,
        `model` varchar(64) NOT NULL,
        `appearance` mediumtext NOT NULL,
        `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
        `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
        PRIMARY KEY (`user_id`),
        CONSTRAINT `fk_ob_character_appearances_character` FOREIGN KEY (`user_id`) REFERENCES `ob_characters` (`user_id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],
    [[CREATE TABLE IF NOT EXISTS `ob_character_slots` (
        `license` varchar(80) NOT NULL,
        `unlocked_slots` tinyint unsigned NOT NULL DEFAULT 1,
        `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
        PRIMARY KEY (`license`),
        CONSTRAINT `fk_ob_character_slots_player` FOREIGN KEY (`license`) REFERENCES `ob_players` (`license`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],
}

local applyCharacterSchemaUpdates
local applyPlayerSchemaUpdates

CreateThread(function()
    if not OR.Database.waitForReady(15000) then
        Database.error = OR.Database.getError() or 'O banco de dados nao respondeu.'
        print(('[ob_core] Falha ao conectar ao banco: %s'):format(Database.error))
        return
    end

    local ok, err = pcall(function()
        for index = 1, #migrations do
            local result, queryError = OR.Database.query.await(migrations[index])
            if result == nil then error(queryError or 'Falha ao aplicar migration.') end
        end

        local updated, updateError = applyPlayerSchemaUpdates()
        if not updated then error(updateError or 'Falha ao atualizar contas.') end

        updated, updateError = applyCharacterSchemaUpdates()
        if not updated then error(updateError or 'Falha ao atualizar personagens.') end
    end)

    Database.ready = ok
    Database.error = ok and nil or tostring(err)

    if ok then
        print('[ob_core] Banco de dados pronto; schema OR aplicado.')
    else
        print(('[ob_core] Falha ao aplicar o schema OR: %s'):format(Database.error))
    end
end)

function Database.waitForReady(timeout)
    local deadline = GetGameTimer() + (timeout or 0)
    while not Database.ready and not Database.error and GetGameTimer() < deadline do
        Wait(100)
    end
    return Database.ready
end

local function hasCharacterColumn(column)
    local row, err = OR.Database.single.await([[SELECT 1 AS exists_column
        FROM information_schema.COLUMNS
        WHERE table_schema = DATABASE() AND table_name = 'ob_characters' AND column_name = ?
        LIMIT 1]], { column })
    if row == nil and err then return nil, err end
    return row ~= nil
end

local function hasPlayerColumn(column)
    local row, err = OR.Database.single.await([[SELECT 1 AS exists_column
        FROM information_schema.COLUMNS
        WHERE table_schema = DATABASE() AND table_name = 'ob_players' AND column_name = ?
        LIMIT 1]], { column })
    if row == nil and err then return nil, err end
    return row ~= nil
end

local function playerPrimaryKey()
    local row, err = OR.Database.single.await([[SELECT column_name
        FROM information_schema.KEY_COLUMN_USAGE
        WHERE table_schema = DATABASE() AND table_name = 'ob_players'
          AND constraint_name = 'PRIMARY' AND ordinal_position = 1
        LIMIT 1]])
    if row == nil and err then return nil, err end
    return row and tostring(row.column_name):lower() or nil
end

local function hasUniqueLicenseIndex()
    local row, err = OR.Database.single.await([[SELECT 1 AS exists_index
        FROM information_schema.STATISTICS
        WHERE table_schema = DATABASE() AND table_name = 'ob_players'
          AND column_name = 'license' AND non_unique = 0 AND index_name <> 'PRIMARY'
        LIMIT 1]])
    if row == nil and err then return nil, err end
    return row ~= nil
end

local function hasForeignKey(tableName, constraintName)
    local row, err = OR.Database.single.await([[SELECT 1 AS exists_constraint
        FROM information_schema.TABLE_CONSTRAINTS
        WHERE table_schema = DATABASE() AND table_name = ?
          AND constraint_name = ? AND constraint_type = 'FOREIGN KEY'
        LIMIT 1]], { tableName, constraintName })
    if row == nil and err then return nil, err end
    return row ~= nil
end

-- Versoes antigas tinham a license como PRIMARY KEY. A license permanece
-- unica para os relacionamentos, mas id passa a ser a chave sequencial da
-- conta: facilita administracao e mantem a ordem de entrada previsivel.
applyPlayerSchemaUpdates = function()
    local hasId, idError = hasPlayerColumn('id')
    if hasId == nil then return false, idError end
    if not hasId then
        local result, alterError = OR.Database.query.await([[ALTER TABLE ob_players
            ADD COLUMN id bigint unsigned NOT NULL AUTO_INCREMENT FIRST,
            ADD UNIQUE KEY uq_ob_players_id (id)]])
        if result == nil then return false, alterError end

        -- A coluna nova recebe valores na ordem fisica antiga. Reordene os
        -- registros existentes pela primeira entrada para que o ID reflita a
        -- ordem real de chegada, sem tocar nas licenses ou personagens.
        local rows, rowsError = OR.Database.query.await([[SELECT license
            FROM ob_players ORDER BY first_seen_at ASC, license ASC]])
        if rows == nil then return false, rowsError end

        local temporaryOffset = 1000000000000
        for index = 1, #rows do
            local updateResult, updateError = OR.Database.update.await('UPDATE ob_players SET id = ? WHERE license = ?', {
                temporaryOffset + index, rows[index].license
            })
            if updateResult == nil then return false, updateError end
        end
        for index = 1, #rows do
            local updateResult, updateError = OR.Database.update.await('UPDATE ob_players SET id = ? WHERE license = ?', {
                index, rows[index].license
            })
            if updateResult == nil then return false, updateError end
        end

        local nextId = #rows + 1
        result, alterError = OR.Database.query.await(('ALTER TABLE ob_players AUTO_INCREMENT = %d'):format(nextId))
        if result == nil then return false, alterError end
    end

    local hasLicenseIndex, licenseError = hasUniqueLicenseIndex()
    if hasLicenseIndex == nil then return false, licenseError end
    if not hasLicenseIndex then
        local result, alterError = OR.Database.query.await('ALTER TABLE ob_players ADD UNIQUE KEY uq_ob_players_license (license)')
        if result == nil then return false, alterError end
    end

    local primaryKey, primaryError = playerPrimaryKey()
    if primaryKey == nil then return false, primaryError or 'Chave primaria de ob_players nao encontrada.' end
    if primaryKey == 'id' then return true end

    local foreignKeys = {
        { table = 'ob_characters', name = 'fk_ob_characters_player', statement = [[ALTER TABLE ob_characters
            ADD CONSTRAINT fk_ob_characters_player FOREIGN KEY (license) REFERENCES ob_players (license) ON DELETE CASCADE]] },
        { table = 'ob_character_slots', name = 'fk_ob_character_slots_player', statement = [[ALTER TABLE ob_character_slots
            ADD CONSTRAINT fk_ob_character_slots_player FOREIGN KEY (license) REFERENCES ob_players (license) ON DELETE CASCADE]] },
    }
    local dropped = {}

    for index = 1, #foreignKeys do
        local foreignKey = foreignKeys[index]
        local exists, existsError = hasForeignKey(foreignKey.table, foreignKey.name)
        if exists == nil then return false, existsError end
        if exists then
            local result, alterError = OR.Database.query.await(('ALTER TABLE %s DROP FOREIGN KEY %s'):format(foreignKey.table, foreignKey.name))
            if result == nil then return false, alterError end
            dropped[#dropped + 1] = foreignKey
        end
    end

    local result, alterError = OR.Database.query.await('ALTER TABLE ob_players DROP PRIMARY KEY, ADD PRIMARY KEY (id)')
    if result == nil then
        -- Se o banco recusar a troca, restaure imediatamente os relacionamentos
        -- que foram removidos antes de reportar a falha do schema.
        for index = 1, #dropped do
            OR.Database.query.await(dropped[index].statement)
        end
        return false, alterError
    end

    for index = 1, #dropped do
        local foreignKey = dropped[index]
        result, alterError = OR.Database.query.await(foreignKey.statement)
        if result == nil then return false, alterError end
    end

    return true
end

applyCharacterSchemaUpdates = function()
    local columns = {
        {
            name = 'blocked_at',
            statement = 'ALTER TABLE ob_characters ADD COLUMN blocked_at timestamp NULL DEFAULT NULL AFTER deleted_at',
        },
        {
            name = 'blocked_reason',
            statement = 'ALTER TABLE ob_characters ADD COLUMN blocked_reason varchar(255) DEFAULT NULL AFTER blocked_at',
        },
        {
            name = 'blocked_by_user_id',
            statement = 'ALTER TABLE ob_characters ADD COLUMN blocked_by_user_id bigint unsigned DEFAULT NULL AFTER blocked_reason',
        },
    }

    for index = 1, #columns do
        local exists, existsError = hasCharacterColumn(columns[index].name)
        if exists == nil then return false, existsError end
        if not exists then
            local result, alterError = OR.Database.query.await(columns[index].statement)
            if result == nil then return false, alterError end
        end
    end

    local typeRow, typeError = OR.Database.single.await([[SELECT column_type
        FROM information_schema.COLUMNS
        WHERE table_schema = DATABASE() AND table_name = 'ob_characters' AND column_name = 'slot'
        LIMIT 1]])
    if typeRow == nil then return false, typeError or 'Coluna slot nao foi encontrada.' end
    if tostring(typeRow.column_type):lower() ~= 'int unsigned' then
        local result, alterError = OR.Database.query.await('ALTER TABLE ob_characters MODIFY COLUMN slot int unsigned NOT NULL')
        if result == nil then return false, alterError end
    end

    return true
end
