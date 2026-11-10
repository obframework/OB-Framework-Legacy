ORCore = ORCore or {}
ORCore.Players = ORCore.Players or {}
ORCore.DynamicJobDefinitions = ORCore.DynamicJobDefinitions or {}
ORCore.SpawnedCharactersThisBoot = ORCore.SpawnedCharactersThisBoot or {}

local function connectionLogValue(value)
    -- Nomes de conta/personagem nao podem injetar linhas ou cores no console.
    local clean = tostring(value or ''):gsub('%c', ' '):gsub('%^%d', ''):gsub('["\\]', '')
    return clean:sub(1, 120)
end

local function decodeJson(value, fallback)
    if type(value) ~= 'string' or value == '' then return fallback end
    local ok, decoded = pcall(json.decode, value)
    return ok and decoded or fallback
end

local function copyJob(job)
    return {
        name = job.name,
        label = job.label,
        grade = job.grade,
        onDuty = job.onDuty == true,
    }
end

local function copyValue(value, fallback)
    local ok, encoded = pcall(json.encode, value)
    if not ok then return fallback end
    return decodeJson(encoded, fallback)
end

-- Dados expostos a outros recursos nunca entregam a tabela de sessao interna.
-- Isso evita que um script consumidor altere metadata/personagem por acidente
-- e deixe o cache do core diferente do banco.
local function publicPlayerData(player)
    if type(player) ~= 'table' then return nil end
    local character = player.character
    local publicCharacter
    if character then
        publicCharacter = {
            userId = character.userId,
            slot = character.slot,
            firstname = character.firstname,
            lastname = character.lastname,
            birthdate = character.birthdate,
            gender = character.gender,
            nationality = character.nationality,
            lastPosition = copyValue(character.lastPosition, nil),
            metadata = copyValue(character.metadata, {}),
        }
    end

    return {
        source = player.source,
        name = player.name,
        license = player.license,
        fivemIdentifier = player.fivemIdentifier,
        spawned = player.spawned == true,
        character = publicCharacter,
    }
end

local function defaultJob()
    local configured = (ORCoreConfig.Jobs and ORCoreConfig.Jobs.Default) or {}
    return {
        name = configured.name or 'unemployed',
        label = configured.label or 'Desempregado',
        grade = math.max(0, math.floor(tonumber(configured.grade) or 0)),
        onDuty = configured.onDuty == true,
    }
end

local function jobDefinition(name)
    local configured = ORCoreConfig.Jobs and ORCoreConfig.Jobs.Definitions or {}
    return configured[name] or ORCore.DynamicJobDefinitions[name]
end

-- Nunca confia no metadata bruto nem em nome recebido por outro resource.
-- Isso tambem impede que um personagem fique com um cargo inexistente depois
-- de uma configuracao ser removida.
local function normalizeJob(value)
    local fallback = defaultJob()
    if type(value) ~= 'table' or type(value.name) ~= 'string' then return fallback end

    local name = value.name:lower()
    if not name:match('^[a-z0-9_]+$') then return fallback end

    local definition = jobDefinition(name)
    if type(definition) ~= 'table' then return fallback end

    local maximum = math.max(0, math.floor(tonumber(definition.maxGrade) or 0))
    return {
        name = name,
        label = definition.label or name,
        grade = math.max(0, math.min(maximum, math.floor(tonumber(value.grade) or 0))),
        onDuty = value.onDuty == true,
    }
end

local function publishJob(source, job, dutyChanged)
    local state = Player(source)
    local publicJob = copyJob(job)
    if state then state.state:set('or:job', publicJob, true) end

    -- Sao eventos internos do servidor e um espelho apenas para UI/cliente.
    -- Nao ha evento de rede para o cliente atribuir a si mesmo um cargo.
    TriggerEvent('ob_core:server:jobChanged', source, publicJob)
    TriggerClientEvent('ob_core:client:jobChanged', source, publicJob)
    if dutyChanged then
        TriggerEvent('ob_core:server:jobDutyChanged', source, publicJob.onDuty, publicJob)
        TriggerClientEvent('ob_core:client:jobDutyChanged', source, publicJob.onDuty, publicJob)
    end
end

local function getIdentifier(source, prefix)
    for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
        if identifier:sub(1, #prefix) == prefix then
            return identifier
        end
    end
end

local function getLicense(source)
    return getIdentifier(source, 'license:')
        or getIdentifier(source, 'license2:')
        or getIdentifier(source, 'fivem:')
end

local function characterFromRow(row)
    if not row then return nil end

    return {
        userId = tonumber(row.user_id),
        slot = tonumber(row.slot),
        firstname = row.firstname,
        lastname = row.lastname,
        birthdate = row.birthdate,
        gender = tonumber(row.gender) or 0,
        nationality = row.nationality,
        lastPosition = decodeJson(row.last_position, nil),
        metadata = decodeJson(row.metadata, {}),
        appearance = decodeJson(row.appearance, nil),
    }
end

local function trim(value)
    if type(value) ~= 'string' then return '' end
    return value:gsub('^%s+', ''):gsub('%s+$', '')
end

local function validText(value, maximum)
    value = trim(value)
    if #value < 2 or #value > maximum then return nil end
    if value:find('[%c<>"/\\]') then return nil end
    return value
end

local function validBirthdate(value)
    if type(value) ~= 'string' then return nil end
    local year, month, day = value:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    if not year or not month or not day then return nil end

    local timestamp = os.time({ year = year, month = month, day = day, hour = 12 })
    if not timestamp then return nil end
    local normalized = os.date('*t', timestamp)
    if normalized.year ~= year or normalized.month ~= month or normalized.day ~= day then return nil end

    local now = os.date('*t')
    local age = now.year - year
    if now.month < month or (now.month == month and now.day < day) then age = age - 1 end
    if age < ORCoreConfig.MinimumAge or age > 120 then return nil end

    return ('%04d-%02d-%02d'):format(year, month, day)
end

local function characterSlotLimit(license)
    local configuredDefault = tonumber(ORCoreConfig.DefaultCharacterSlots) or 1
    local configuredMaximum = tonumber(ORCoreConfig.CharacterSlots) or 1
    local stored = OR.Database.scalar.await('SELECT unlocked_slots FROM ob_character_slots WHERE license = ? LIMIT 1', { license })
    local limit = tonumber(stored) or configuredDefault
    return math.max(1, math.min(configuredMaximum, math.floor(limit)))
end

-- Slots ativos usam somente os numeros configurados (1, 2, 3...). Ao excluir
-- ou bloquear, movemos o registro para uma faixa interna sem colisao. Assim a
-- vaga original fica disponivel sem perder o historico do personagem.
local function releasedSlot(userId)
    return 1000000 + userId
end

function ORCore.GetSelectionBucket(source)
    source = tonumber(source)
    if not source or source <= 0 then return nil end
    return ORCoreConfig.SelectorBucketOffset + source
end

function ORCore.SetSelectionInstance(source)
    local bucket = ORCore.GetSelectionBucket(source)
    if bucket and GetPlayerName(source) then
        SetPlayerRoutingBucket(source, bucket)
        return bucket
    end
end

function ORCore.EnsureSession(source)
    source = tonumber(source)
    if not source or source <= 0 then return nil, 'Fonte invalida.' end

    local license = getLicense(source)
    if not license then return nil, 'Nenhum identificador FiveM foi encontrado.' end

    local session = ORCore.Players[source]
    if session then return session end

    -- Nem todo cliente disponibiliza o identificador fivem:. Ele e apenas
    -- informativo; a license continua sendo a identidade obrigatoria. Nunca
    -- envie nil dentro de uma lista de parametros SQL, pois o msgpack remove
    -- esse indice e o mysql2 recebe menos valores que os placeholders.
    local fivemIdentifier = getIdentifier(source, 'fivem:') or ''
    local name = GetPlayerName(source) or 'Desconhecido'
    local registered, registerError = OR.Database.update.await([[INSERT INTO ob_players (license, fivem_identifier, display_name)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE fivem_identifier = VALUES(fivem_identifier), display_name = VALUES(display_name), last_seen_at = current_timestamp()]], {
        license, fivemIdentifier, name
    })
    if registered == nil then
        return nil, registerError or 'Nao foi possivel registrar o jogador no banco de dados.'
    end

    session = {
        source = source,
        license = license,
        fivemIdentifier = fivemIdentifier,
        name = name,
        character = nil,
        spawned = false,
    }
    ORCore.Players[source] = session
    print(('[ob_core] CONEXAO conta="%s" sessao=%s personagem=aguardando_selecao'):format(
        connectionLogValue(session.name), source))
    TriggerEvent('ob_core:server:sessionCreated', source, publicPlayerData(session))
    return session
end

function ORCore.GetPlayer(source)
    return ORCore.Players[tonumber(source)]
end

function ORCore.GetCharacter(source)
    local player = ORCore.GetPlayer(source)
    return player and player.character or nil
end

function ORCore.GetUserId(source)
    local character = ORCore.GetCharacter(source)
    return character and character.userId or nil
end

function ORCore.GetPlayerData(source)
    return publicPlayerData(ORCore.GetPlayer(source))
end

function ORCore.GetPlayers()
    local players = {}
    for source, player in pairs(ORCore.Players) do
        if GetPlayerName(source) then
            players[#players + 1] = publicPlayerData(player)
        end
    end
    table.sort(players, function(first, second) return first.source < second.source end)
    return players
end

function ORCore.GetSourceByUserId(userId)
    userId = tonumber(userId)
    if not userId or userId <= 0 then return nil end
    for source, player in pairs(ORCore.Players) do
        if player.character and player.character.userId == userId and GetPlayerName(source) then
            return source
        end
    end
end

function ORCore.GetPlayerByUserId(userId)
    local source = ORCore.GetSourceByUserId(userId)
    return source and ORCore.GetPlayerData(source) or nil
end

function ORCore.GetIdentifier(source, identifierType)
    local player = ORCore.GetPlayer(source)
    if not player or type(identifierType) ~= 'string' then return nil end

    identifierType = identifierType:lower()
    if identifierType == 'license' then return player.license end
    if identifierType == 'fivem' then return player.fivemIdentifier end
    if not identifierType:match('^[a-z0-9_]+$') then return nil end
    return getIdentifier(player.source, identifierType .. ':')
end

function ORCore.GetFullName(source)
    local character = ORCore.GetCharacter(source)
    if not character then return nil end
    local fullName = ('%s %s'):format(character.firstname or '', character.lastname or '')
    fullName = fullName:gsub('^%s+', ''):gsub('%s+$', '')
    return fullName
end

function ORCore.ListCharacters(source)
    if not Database.ready then return nil, 'Banco de dados ainda nao esta pronto.' end

    local player, err = ORCore.EnsureSession(source)
    if not player then return nil, err end

    local rows = OR.Database.query.await([[SELECT c.user_id, c.slot, c.firstname, c.lastname, c.birthdate, c.gender, c.nationality, c.last_position, c.metadata, a.appearance
        FROM ob_characters AS c
        LEFT JOIN ob_character_appearances AS a ON a.user_id = c.user_id
        WHERE c.license = ? AND c.deleted_at IS NULL AND c.blocked_at IS NULL
        ORDER BY c.slot ASC]], { player.license }) or {}

    local characters = {}
    for index = 1, #rows do
        characters[index] = characterFromRow(rows[index])
    end

    return {
        characters = characters,
        maxSlots = ORCoreConfig.CharacterSlots,
        unlockedSlots = characterSlotLimit(player.license),
    }
end

function ORCore.CreateCharacter(source, payload)
    if not Database.ready then return nil, 'Banco de dados ainda nao esta pronto.' end

    local player, err = ORCore.EnsureSession(source)
    if not player then return nil, err end
    if player.character then return nil, 'Voce ja possui um personagem selecionado nesta sessao.' end
    if type(payload) ~= 'table' then return nil, 'Dados de personagem invalidos.' end

    local firstname = validText(payload.firstname, 32)
    local lastname = validText(payload.lastname, 32)
    local nationality = validText(payload.nationality or 'Brasileiro', 48) or 'Brasileiro'
    local birthdate = validBirthdate(payload.birthdate)
    local gender = tonumber(payload.gender) == 1 and 1 or 0
    if not firstname or not lastname or not birthdate then
        return nil, 'Dados de identidade invalidos.'
    end

    local rows = OR.Database.query.await([[SELECT slot FROM ob_characters
        WHERE license = ? AND deleted_at IS NULL AND blocked_at IS NULL]], { player.license }) or {}
    local occupied = {}
    for index = 1, #rows do occupied[tonumber(rows[index].slot)] = true end

    local unlockedSlots = characterSlotLimit(player.license)
    local requestedSlot = tonumber(payload.slot)
    local slot
    if requestedSlot and requestedSlot >= 1 and requestedSlot <= unlockedSlots and not occupied[requestedSlot] then
        slot = requestedSlot
    else
        for index = 1, unlockedSlots do
            if not occupied[index] then
                slot = index
                break
            end
        end
    end
    if not slot then return nil, 'Nenhum slot de personagem esta disponivel.' end

    local inserted = OR.Database.insert.await([[INSERT INTO ob_characters
        (license, slot, firstname, lastname, birthdate, gender, nationality, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)]], {
        player.license, slot, firstname, lastname, birthdate, gender, nationality, json.encode({})
    })
    local userId = tonumber(inserted)
    local character = userId and {
        userId = userId,
        slot = slot,
        firstname = firstname,
        lastname = lastname,
        birthdate = birthdate,
        gender = gender,
        nationality = nationality,
        lastPosition = nil,
        metadata = {},
    } or nil
    if not character then return nil, 'Nao foi possivel criar o personagem.' end

    player.character = character
    player.spawned = false
    local state = Player(source)
    if state then
        state.state:set('or:userId', character.userId, true)
        state.state:set('or:loaded', false, true)
    end
    ORCore.SetSelectionInstance(source)
    TriggerEvent('ob_core:server:characterSelected', source, character)
    TriggerEvent('ob_core:server:characterCreated', source, character)
    return character
end

function ORCore.SelectCharacter(source, userId)
    if not Database.ready then return nil, 'Banco de dados ainda nao esta pronto.' end

    local player, err = ORCore.EnsureSession(source)
    if not player then return nil, err end
    userId = tonumber(userId)
    if not userId or userId <= 0 or userId ~= math.floor(userId) then return nil, 'Personagem invalido.' end

    local row = OR.Database.single.await([[SELECT user_id, slot, firstname, lastname, birthdate, gender, nationality, last_position, metadata
        FROM ob_characters
        WHERE user_id = ? AND license = ? AND deleted_at IS NULL AND blocked_at IS NULL
        LIMIT 1]], { userId, player.license })
    local character = characterFromRow(row)
    if not character then return nil, 'Personagem nao encontrado.' end

    player.character = character
    player.spawned = false
    OR.Database.update.await('UPDATE ob_characters SET last_played_at = current_timestamp() WHERE user_id = ?', { character.userId })
    local state = Player(source)
    if state then
        state.state:set('or:userId', character.userId, true)
        state.state:set('or:loaded', false, true)
    end
    ORCore.SetSelectionInstance(source)
    TriggerEvent('ob_core:server:characterSelected', source, character)
    return character
end

function ORCore.SavePosition(source)
    local player = ORCore.GetPlayer(source)
    if not player or not player.character then return false end

    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end
    local coords = GetEntityCoords(ped)
    if not coords then return false end

    local position = {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        w = GetEntityHeading(ped) or 0.0,
    }
    OR.Database.update.await('UPDATE ob_characters SET last_position = ?, last_played_at = current_timestamp() WHERE user_id = ?', {
        json.encode(position), player.character.userId
    })
    player.character.lastPosition = position
    return true
end

function ORCore.IsPlayerLoaded(source)
    local player = ORCore.GetPlayer(source)
    return player ~= nil and player.character ~= nil and player.spawned == true
end

function ORCore.GetLastPosition(source)
    local character = ORCore.GetCharacter(source)
    return character and character.lastPosition or nil
end

function ORCore.GetMetadata(source)
    local character = ORCore.GetCharacter(source)
    return character and character.metadata or nil
end

function ORCore.GetJob(source)
    local character = ORCore.GetCharacter(source)
    local metadata = character and character.metadata or nil
    return copyJob(normalizeJob(metadata and metadata.job))
end

function ORCore.HasJob(source, jobName, minimumGrade)
    if type(jobName) ~= 'string' then return false end
    local job = ORCore.GetJob(source)
    local requiredGrade = math.max(0, math.floor(tonumber(minimumGrade) or 0))
    return job.name == jobName:lower() and job.grade >= requiredGrade
end

function ORCore.IsOnDuty(source)
    return ORCore.GetJob(source).onDuty == true
end

function ORCore.SetMetadata(source, key, value)
    local player = ORCore.GetPlayer(source)
    if not player or not player.character or type(key) ~= 'string' or key == '' or #key > 64 then
        return false
    end

    player.character.metadata = type(player.character.metadata) == 'table' and player.character.metadata or {}
    local previousJob = key == 'job' and normalizeJob(player.character.metadata.job) or nil
    if key == 'job' then value = normalizeJob(value) end
    player.character.metadata[key] = value
    local userId = player.character.userId
    local metadata = json.encode(player.character.metadata)

    -- Esta funcao tambem e chamada por exports de outros resources. Uma exportacao
    -- nao deve ficar aguardando SQL se o resource chamador estiver parando.
    CreateThread(function()
        local changed, errorMessage = OR.Database.update.await('UPDATE ob_characters SET metadata = ? WHERE user_id = ?', {
            metadata, userId
        })
        if changed == nil then
            print(('[ob_core] Falha ao salvar metadata do personagem %s: %s'):format(userId, errorMessage or 'desconhecida'))
        end
    end)
    if key == 'job' then
        publishJob(source, value, previousJob.onDuty ~= value.onDuty)
    end
    TriggerEvent('ob_core:server:metadataChanged', source, key, value)
    TriggerClientEvent('ob_core:client:metadataChanged', source, key, value)
    return true
end

function ORCore.SetJob(source, jobName, grade, onDuty)
    source = tonumber(source)
    if not source or source <= 0 or type(jobName) ~= 'string' then
        return false, 'Cargo invalido.'
    end

    local name = jobName:lower()
    local definition = jobDefinition(name)
    if type(definition) ~= 'table' then
        return false, 'Esse cargo nao esta cadastrado no ob_core.'
    end

    local maximum = math.max(0, math.floor(tonumber(definition.maxGrade) or 0))
    local job = {
        name = name,
        label = definition.label or name,
        grade = math.max(0, math.min(maximum, math.floor(tonumber(grade) or 0))),
        onDuty = onDuty == true,
    }
    local saved = ORCore.SetMetadata(source, 'job', job)
    return saved, saved and copyJob(job) or 'Personagem nao esta carregado.'
end

function ORCore.RegisterJobDefinition(jobName, label, maxGrade)
    jobName = type(jobName) == 'string' and jobName:lower() or ''
    if jobName == '' or not jobName:match('^[a-z0-9_]+$') or #jobName > 48 then
        return false, 'Nome de emprego invalido.'
    end

    local configured = ORCoreConfig.Jobs and ORCoreConfig.Jobs.Definitions or {}
    if configured[jobName] then return false, 'Esse emprego pertence ao config do core.' end
    ORCore.DynamicJobDefinitions[jobName] = {
        label = type(label) == 'string' and label:sub(1, 80) or jobName,
        maxGrade = math.max(0, math.min(100, math.floor(tonumber(maxGrade) or 0))),
    }
    return true
end

function ORCore.RemoveJobDefinition(jobName)
    jobName = type(jobName) == 'string' and jobName:lower() or ''
    if ORCore.DynamicJobDefinitions[jobName] == nil then return false end
    ORCore.DynamicJobDefinitions[jobName] = nil
    return true
end

function ORCore.SetDuty(source, enabled)
    local current = ORCore.GetJob(source)
    return ORCore.SetJob(source, current.name, current.grade, enabled == true)
end

function ORCore.HasSpawned(source)
    local player = ORCore.GetPlayer(source)
    return player and player.spawned == true or false
end

function ORCore.HasCharacterSpawnedThisBoot(source)
    local userId = ORCore.GetUserId(source)
    return userId ~= nil and ORCore.SpawnedCharactersThisBoot[userId] == true
end

function ORCore.GetCharacterSlotLimit(license)
    if type(license) ~= 'string' or license == '' then return nil end
    return characterSlotLimit(license)
end

function ORCore.SetCharacterSlotLimit(license, slots)
    if type(license) ~= 'string' or license == '' then return false, 'License invalida.' end
    local maximum = tonumber(ORCoreConfig.CharacterSlots) or 1
    slots = tonumber(slots)
    if not slots then return false, 'Quantidade de slots invalida.' end
    slots = math.max(1, math.min(maximum, math.floor(slots)))

    local changed, err = OR.Database.query.await([[INSERT INTO ob_character_slots (license, unlocked_slots)
        VALUES (?, ?)
        ON DUPLICATE KEY UPDATE unlocked_slots = VALUES(unlocked_slots), updated_at = current_timestamp()]], { license, slots })
    if changed == nil then return false, err end
    return true
end

function ORCore.DeleteCharacter(userId)
    userId = tonumber(userId)
    if not userId or userId <= 0 or userId ~= math.floor(userId) then
        return false, 'ID fixo do personagem invalido.'
    end

    local changed, err = OR.Database.update.await([[UPDATE ob_characters
        SET deleted_at = current_timestamp(), slot = ?
        WHERE user_id = ? AND deleted_at IS NULL]], { releasedSlot(userId), userId })
    if changed == nil then return false, err or 'Nao foi possivel excluir o personagem.' end
    if changed == 0 then return false, 'Personagem nao encontrado ou ja excluido.' end
    return true
end

function ORCore.BlockCharacter(userId, reason, blockedByUserId)
    userId = tonumber(userId)
    blockedByUserId = tonumber(blockedByUserId)
    if not userId or userId <= 0 or userId ~= math.floor(userId) then
        return false, 'ID fixo do personagem invalido.'
    end
    if not blockedByUserId or blockedByUserId <= 0 then
        return false, 'Administrador responsavel invalido.'
    end

    reason = type(reason) == 'string' and reason:sub(1, 255) or 'Bloqueado pela administracao.'
    if reason == '' then reason = 'Bloqueado pela administracao.' end

    local changed, err = OR.Database.update.await([[UPDATE ob_characters
        SET blocked_at = current_timestamp(), blocked_reason = ?, blocked_by_user_id = ?, slot = ?
        WHERE user_id = ? AND deleted_at IS NULL AND blocked_at IS NULL]], {
        reason, blockedByUserId, releasedSlot(userId), userId
    })
    if changed == nil then return false, err or 'Nao foi possivel bloquear o personagem.' end
    if changed == 0 then return false, 'Personagem nao encontrado, excluido ou ja bloqueado.' end
    return true
end

function ORCore.MarkSpawned(source)
    local player = ORCore.GetPlayer(source)
    if not player or not player.character then return false end

    player.spawned = true
    ORCore.SpawnedCharactersThisBoot[player.character.userId] = true
    SetPlayerRoutingBucket(source, 0)
    ORCore.SavePosition(source)
    -- SavePosition pode aguardar o banco. Nao atribuir a entrada a uma sessao
    -- que saiu ou foi substituida enquanto o salvamento estava em andamento.
    if ORCore.GetPlayer(source) == player and player.character
        and player.lastLoggedEntryUserId ~= player.character.userId then
        player.lastLoggedEntryUserId = player.character.userId
        local characterName = ('%s %s'):format(player.character.firstname or '', player.character.lastname or '')
        print(('[ob_core] ENTRADA personagem="%s" conta="%s" user_id=%s sessao=%s entrou na cidade.'):format(
            connectionLogValue(characterName), connectionLogValue(GetPlayerName(source) or player.name),
            player.character.userId, source))
    end
    local state = Player(source)
    if state then state.state:set('or:loaded', true, true) end
    publishJob(source, ORCore.GetJob(source), false)
    TriggerEvent('ob_core:server:playerLoaded', source, player.character)
    TriggerEvent('ob_core:server:playerSpawned', source, player.character)
    TriggerClientEvent('ob_core:client:playerSpawned', source, player.character)
    return true
end

function ORCore.HasPermission(source, permission)
    source = tonumber(source)
    if not source or source <= 0 or type(permission) ~= 'string' or permission == '' then
        return false
    end

    return IsPlayerAceAllowed(source, permission) == true
end

function ORCore.IsAdmin(source)
    if ORCore.HasPermission(source, 'or.admin') then
        return true
    end

    -- Durante o desenvolvimento, o mesmo identifier que passou pela whitelist
    -- de acesso recebe administracao. Em producao continua valendo somente
    -- a permissao explicita or.admin.
    local developmentMode = GetConvar('ob_development_mode', 'false'):lower() == 'true'
    return developmentMode and ORCore.HasPermission(source, 'or.developer')
end

function ORCore.GetMaximumCharacterSlots()
    local maximum = tonumber(ORCoreConfig.CharacterSlots) or 1
    return math.max(1, math.floor(maximum))
end

function ORCore.IsDatabaseReady()
    return Database.ready == true
end

-- Recursos que mantem dados por personagem devem usar o mesmo tipo SQL da
-- chave real. Isso permite copiar a framework para uma base que ja possuia
-- ob_characters criado por uma versao anterior, sem quebrar chaves estrangeiras.
function ORCore.GetCharacterIdColumnType()
    if not Database.ready then return nil end

    local row = OR.Database.single.await([[SELECT column_type
        FROM information_schema.COLUMNS
        WHERE table_schema = DATABASE() AND table_name = 'ob_characters' AND column_name = 'user_id'
        LIMIT 1]])
    local columnType = row and tostring(row.column_type or ''):lower():gsub('%s+', ' ') or ''
    local bases = { 'tinyint', 'smallint', 'mediumint', 'int', 'bigint' }
    for index = 1, #bases do
        local base = bases[index]
        if columnType == base or columnType == base .. ' unsigned'
            or columnType:match('^' .. base .. '%(%d+%)$')
            or columnType:match('^' .. base .. '%(%d+%) unsigned$') then
            return columnType:upper()
        end
    end
end

exports('GetPlayer', ORCore.GetPlayer)
exports('GetCharacter', ORCore.GetCharacter)
exports('GetUserId', ORCore.GetUserId)
exports('GetPlayerData', ORCore.GetPlayerData)
exports('GetPlayers', ORCore.GetPlayers)
exports('GetSourceByUserId', ORCore.GetSourceByUserId)
exports('GetPlayerByUserId', ORCore.GetPlayerByUserId)
exports('GetIdentifier', ORCore.GetIdentifier)
exports('GetFullName', ORCore.GetFullName)
exports('GetSelectionBucket', ORCore.GetSelectionBucket)
exports('SavePosition', ORCore.SavePosition)
exports('GetLastPosition', ORCore.GetLastPosition)
exports('GetMetadata', ORCore.GetMetadata)
exports('SetMetadata', ORCore.SetMetadata)
exports('GetJob', ORCore.GetJob)
exports('HasJob', ORCore.HasJob)
exports('IsOnDuty', ORCore.IsOnDuty)
exports('SetJob', ORCore.SetJob)
exports('RegisterJobDefinition', ORCore.RegisterJobDefinition)
exports('RemoveJobDefinition', ORCore.RemoveJobDefinition)
exports('SetDuty', ORCore.SetDuty)
exports('HasSpawned', ORCore.HasSpawned)
exports('HasCharacterSpawnedThisBoot', ORCore.HasCharacterSpawnedThisBoot)
exports('IsPlayerLoaded', ORCore.IsPlayerLoaded)
exports('MarkSpawned', ORCore.MarkSpawned)
exports('GetCharacterSlotLimit', ORCore.GetCharacterSlotLimit)
exports('SetCharacterSlotLimit', ORCore.SetCharacterSlotLimit)
exports('DeleteCharacter', ORCore.DeleteCharacter)
exports('BlockCharacter', ORCore.BlockCharacter)
exports('HasPermission', ORCore.HasPermission)
exports('IsAdmin', ORCore.IsAdmin)
exports('GetMaximumCharacterSlots', ORCore.GetMaximumCharacterSlots)
exports('IsDatabaseReady', ORCore.IsDatabaseReady)
exports('GetCharacterIdColumnType', ORCore.GetCharacterIdColumnType)
