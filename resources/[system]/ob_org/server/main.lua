local ready = false
local routeSessions = {}
local dutyToggleAt = {}
local dutySessions = {}
local dutyBlipSettings = {}

local function text(value, maximum)
    value = tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
    return value:sub(1, maximum or 120)
end

local function key(value)
    value = text(value, 48):lower()
    return value:match('^[a-z0-9_]+$') and value or nil
end

local function integer(value, minimum, maximum, fallback)
    value = math.floor(tonumber(value) or tonumber(fallback) or 0)
    return math.max(minimum or value, math.min(maximum or value, value))
end

local function flag(value)
    return value == true or value == 1 or value == '1'
end

local function decode(value, fallback)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return fallback end
    local ok, result = pcall(json.decode, value)
    return ok and type(result) == 'table' and result or fallback
end

local function accessPermissionList(value)
    local result, seen = {}, {}
    if type(value) ~= 'table' then return result end
    for _, entry in ipairs(value) do
        local permission = text(entry, 64):lower()
        if permission:match('^[a-z0-9_.:%-]+$') and not seen[permission] and #result < 20 then
            seen[permission] = true
            result[#result + 1] = permission
        end
    end
    return result
end

local function userId(source)
    source = tonumber(source)
    if not source or source <= 0 then return nil end
    local ok, value = pcall(function()
        return exports.ob_core:GetUserId(source)
    end)
    return ok and tonumber(value) or nil
end

local function onlineSource(id)
    id = tonumber(id)
    if not id or id <= 0 then return nil end
    local ok, value = pcall(function()
        return exports.ob_core:GetSourceByUserId(id)
    end)
    local source = ok and tonumber(value) or nil
    return source and GetPlayerName(source) and source or nil
end

local function isAdmin(source)
    return tonumber(source) == 0 or exports.ob_admin:HasPermission(tonumber(source), 'panel.open') == true
end

local function notify(source, message, kind)
    source = tonumber(source)
    if not source or source == 0 then return print(('[ob_org] %s'):format(message)) end
    TriggerClientEvent('ob_notification:client:notify', source, message, kind or 'info')
end

local function characterName(id)
    local row = OR.Database.single.await('SELECT firstname, lastname FROM ob_characters WHERE user_id = ? LIMIT 1', { id })
    if not row then return nil end
    return text(('%s %s'):format(row.firstname or '', row.lastname or ''), 80)
end

local function membership(id)
    return OR.Database.single.await([[SELECT m.org_id, m.user_id, m.rank_id, m.on_duty, m.joined_at,
        o.org_key, o.label, o.logo_url, o.org_type, o.max_members, o.auto_duty, o.duty_coords, o.active,
        r.rank_key, r.label AS rank_label, r.level, r.salary, r.permissions
        FROM ob_org_members m
        JOIN ob_orgs o ON o.id = m.org_id
        JOIN ob_org_ranks r ON r.id = m.rank_id
        WHERE m.user_id = ? LIMIT 1]], { id })
end

local function registerLegalJob(org)
    if org and org.org_type == 'legal' then
        exports.ob_core:RegisterJobDefinition(org.org_key, org.label, 100)
    end
end

local function defaultDutyBlip(org)
    local fallback = type(OBOrgConfig.DutyBlips) == 'table'
        and type(OBOrgConfig.DutyBlips.default) == 'table' and OBOrgConfig.DutyBlips.default or {}
    return {
        orgId = tonumber(org.id),
        orgKey = org.org_key,
        enabled = true,
        label = text(org.label, 80),
        sprite = integer(fallback.sprite, 1, 1000, 1),
        colour = integer(fallback.colour, 0, 255, 3),
        scale = math.max(0.30, math.min(2.00, tonumber(fallback.scale) or 0.75)),
        helicopterSprite = integer(fallback.helicopterSprite, 1, 1000, 422),
        visibleTo = { org.org_key },
    }
end

local function loadDutyBlipSettings(createMissing)
    local legal = OR.Database.query.await(
        "SELECT id,org_key,label FROM ob_orgs WHERE org_type='legal' ORDER BY label") or {}
    local byId = {}
    for _, org in ipairs(legal) do byId[tonumber(org.id)] = org end
    local loaded = {}
    for _, row in ipairs(OR.Database.query.await('SELECT * FROM ob_org_duty_blips') or {}) do
        local org = byId[tonumber(row.org_id)]
        if org then
            local visible, seen = {}, {}
            for _, orgKey in ipairs(decode(row.visible_to, {})) do
                orgKey = key(orgKey)
                if orgKey and not seen[orgKey] then
                    seen[orgKey] = true
                    visible[#visible + 1] = orgKey
                end
            end
            loaded[org.org_key] = {
                orgId = tonumber(org.id), orgKey = org.org_key,
                enabled = flag(row.enabled), label = text(row.label, 80),
                sprite = integer(row.sprite, 1, 1000, 1),
                colour = integer(row.colour, 0, 255, 3),
                scale = math.max(0.30, math.min(2.00, tonumber(row.scale) or 0.75)),
                helicopterSprite = integer(row.helicopter_sprite, 1, 1000, 422),
                visibleTo = visible,
            }
        end
    end
    if createMissing then
        for _, org in ipairs(legal) do
            if not loaded[org.org_key] then
                local setting = defaultDutyBlip(org)
                local inserted = OR.Database.insert.await([[INSERT IGNORE INTO ob_org_duty_blips
                    (org_id,enabled,label,sprite,colour,scale,helicopter_sprite,visible_to)
                    VALUES (?,?,?,?,?,?,?,?)]], {
                    org.id, 1, setting.label, setting.sprite, setting.colour, setting.scale,
                    setting.helicopterSprite, json.encode(setting.visibleTo),
                })
                if inserted ~= nil then loaded[org.org_key] = setting end
            end
        end
    end
    dutyBlipSettings = loaded
end

local function memberOnDuty(source, member)
    local session = dutySessions[tonumber(source)]
    local job = exports.ob_core:GetJob(tonumber(source))
    return member ~= nil and flag(member.active) and member.org_type == 'legal'
        and session ~= nil and session.userId == tonumber(member.user_id)
        and session.orgId == tonumber(member.org_id) and session.onDuty == true
        and job ~= nil and job.name == member.org_key and job.onDuty == true
        and (flag(member.auto_duty) or flag(member.on_duty))
end

local function publishMembership(source, member)
    source = tonumber(source)
    if not source or not GetPlayerName(source) then return end
    local player = Player(source)
    if not member or not flag(member.active) then
        dutySessions[source] = nil
        player.state:set('ob:org', nil, true)
        local job = exports.ob_core:GetJob(source)
        local organisationJob = job and OR.Database.scalar.await("SELECT id FROM ob_orgs WHERE org_key=? AND org_type='legal' LIMIT 1", { job.name })
        if organisationJob then exports.ob_core:SetJob(source, 'unemployed', 0, false) end
        return
    end

    member.permissions = decode(member.permissions, {})
    local onDuty = member.org_type == 'legal' and (flag(member.auto_duty) or flag(member.on_duty)) or false
    dutySessions[source] = { userId = tonumber(member.user_id), orgId = tonumber(member.org_id), onDuty = onDuty }
    player.state:set('ob:org', {
        id = tonumber(member.org_id), key = member.org_key, label = member.label,
        type = member.org_type, rank = member.rank_key, rankLabel = member.rank_label,
        level = tonumber(member.level), onDuty = onDuty,
    }, true)

    if member.org_type == 'legal' then
        registerLegalJob(member)
        local grade = math.max(0, 100 - integer(member.level, 1, 100, 100))
        exports.ob_core:SetJob(source, member.org_key, grade, onDuty)
    else
        local job = exports.ob_core:GetJob(source)
        local organisationJob = job and OR.Database.scalar.await("SELECT id FROM ob_orgs WHERE org_key=? AND org_type='legal' LIMIT 1", { job.name })
        if organisationJob then exports.ob_core:SetJob(source, 'unemployed', 0, false) end
    end
end

local function syncMember(source, resetDuty)
    source = tonumber(source)
    local id = userId(source)
    if not id then return end
    if resetDuty then
        dutySessions[source] = nil
        Player(source).state:set('ob:org', nil, true)
        exports.ob_core:SetDuty(source, false)
    end
    local member = membership(id)
    if resetDuty and member and member.org_type == 'legal' and not flag(member.auto_duty) then
        local changed = OR.Database.update.await('UPDATE ob_org_members SET on_duty=0 WHERE user_id=? AND org_id=?', { id, member.org_id })
        if changed == nil then
            notify(source, 'Nao foi possivel inicializar o ponto. Entre novamente para liberar o servico.', 'error')
            return
        end
        member.on_duty = 0
    end
    if userId(source) ~= id then return end
    publishMembership(source, member)
    TriggerClientEvent('ob_org:client:refreshWorld', tonumber(source))
end

local function hasPermission(actor, permission)
    if actor.admin then return true end
    return actor.permissions and actor.permissions[permission] == true
end

local function actorContext(source, requestedOrgId, adminPanel)
    local id = userId(source)
    if not id then return nil, 'Personagem ainda nao esta carregado.' end
    local member = membership(id)
    local admin = adminPanel == true and isAdmin(source)
    local orgId = tonumber(requestedOrgId) or (member and tonumber(member.org_id))
    if not orgId then return nil, 'Voce nao pertence a uma organizacao.' end
    if not admin and (not member or tonumber(member.org_id) ~= orgId) then return nil, 'Organizacao invalida.' end
    if not admin and not flag(member.active) then return nil, 'Essa organizacao esta desativada.' end
    return {
        source = tonumber(source), userId = id, admin = admin, member = member,
        orgId = orgId, permissions = member and decode(member.permissions, {}) or {},
        level = member and tonumber(member.level) or 0,
    }
end

local function organisationPayload(orgId, actor)
    local org = OR.Database.single.await('SELECT * FROM ob_orgs WHERE id = ? LIMIT 1', { orgId })
    if not org then return nil end
    org.duty = decode(org.duty_coords, nil)
    org.duty_coords = nil
    org.auto_duty = flag(org.auto_duty)
    org.active = flag(org.active)

    local dutyBlip, legalOrganisations
    if actor.admin and org.org_type == 'legal' then
        dutyBlip = dutyBlipSettings[org.org_key] or defaultDutyBlip(org)
        legalOrganisations = OR.Database.query.await(
            "SELECT id,org_key,label,active FROM ob_orgs WHERE org_type='legal' ORDER BY label") or {}
        for _, legalOrg in ipairs(legalOrganisations) do legalOrg.active = flag(legalOrg.active) end
    end

    local ranks = OR.Database.query.await('SELECT id, rank_key, label, level, salary, member_limit, permissions FROM ob_org_ranks WHERE org_id = ? ORDER BY level, id', { orgId }) or {}
    for _, rank in ipairs(ranks) do
        rank.permissions = actor.admin and decode(rank.permissions, {}) or nil
    end
    local members = OR.Database.query.await([[SELECT m.user_id, m.rank_id, m.on_duty, m.joined_at,
        r.rank_key, r.label AS rank_label, r.level, c.firstname, c.lastname
        FROM ob_org_members m JOIN ob_org_ranks r ON r.id=m.rank_id
        JOIN ob_characters c ON c.user_id=m.user_id WHERE m.org_id=? ORDER BY r.level, c.firstname, c.lastname]], { orgId }) or {}
    for _, member in ipairs(members) do
        member.name = text(('%s %s'):format(member.firstname or '', member.lastname or ''), 80)
        member.firstname, member.lastname = nil, nil
        member.online = onlineSource(member.user_id) ~= nil
        member.on_duty = member.online and org.org_type == 'legal' and (org.auto_duty or flag(member.on_duty)) or false
    end

    local goals, ranking, routes, chests = {}, {}, {}, {}
    if org.org_type == 'illegal' then
        goals = OR.Database.query.await([[SELECT g.id, g.title, g.target, g.active, g.created_at,
            COALESCE(SUM(CASE WHEN p.period_key=DATE_FORMAT(CURRENT_DATE(), '%Y-%m-%d') THEN p.progress ELSE 0 END),0) AS total_progress
            FROM ob_org_goals g LEFT JOIN ob_org_goal_progress p ON p.goal_id=g.id
            WHERE g.org_id=? GROUP BY g.id ORDER BY g.active DESC, g.id DESC]], { orgId }) or {}
        for _, goal in ipairs(goals) do goal.active = flag(goal.active) end
        for _, goal in ipairs(goals) do
            goal.members = OR.Database.query.await([[SELECT m.user_id,c.firstname,c.lastname,COALESCE(p.progress,0) AS progress
                FROM ob_org_members m JOIN ob_characters c ON c.user_id=m.user_id
                LEFT JOIN ob_org_goal_progress p ON p.goal_id=? AND p.user_id=m.user_id AND p.period_key=CURRENT_DATE()
                WHERE m.org_id=? ORDER BY c.firstname,c.lastname]], { goal.id, orgId }) or {}
            for _, row in ipairs(goal.members) do row.name=text(('%s %s'):format(row.firstname or '',row.lastname or ''),80);row.firstname=nil;row.lastname=nil end
        end
        ranking = OR.Database.query.await([[SELECT l.user_id, c.firstname, c.lastname,
            SUM(CASE WHEN l.completed_at >= DATE_SUB(NOW(), INTERVAL 7 DAY) THEN 1 ELSE 0 END) AS routes_7,
            COUNT(*) AS routes_30
            FROM ob_org_route_log l JOIN ob_characters c ON c.user_id=l.user_id
            WHERE l.org_id=? AND l.completed_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
            GROUP BY l.user_id, c.firstname, c.lastname ORDER BY routes_30 DESC, c.firstname LIMIT 100]], { orgId }) or {}
        for _, row in ipairs(ranking) do row.name = text(('%s %s'):format(row.firstname or '', row.lastname or ''), 80); row.firstname=nil; row.lastname=nil end
        if actor.admin then
            routes = OR.Database.query.await('SELECT * FROM ob_org_routes WHERE org_id=? ORDER BY id', { orgId }) or {}
            for _, route in ipairs(routes) do
                route.npc = decode(route.npc_coords, nil); route.npc_coords=nil; route.enabled=flag(route.enabled)
                route.points = OR.Database.query.await('SELECT id, position, x, y, z FROM ob_org_route_points WHERE route_id=? ORDER BY position,id', { route.id }) or {}
                route.rewards = OR.Database.query.await('SELECT id, item_name, min_amount, max_amount, chance FROM ob_org_route_rewards WHERE route_id=? ORDER BY id', { route.id }) or {}
            end
        end
    end

    if actor.admin then
        chests = OR.Database.query.await([[SELECT id,org_id,label,chest_type,slots,max_weight,coords,
            webhook_url IS NOT NULL AND webhook_url<>'' AS has_webhook,enabled,created_at,updated_at
            FROM ob_org_chests WHERE org_id=? ORDER BY id]], { orgId }) or {}
        for _, chest in ipairs(chests) do
            chest.coords = decode(chest.coords, nil)
            chest.has_webhook = flag(chest.has_webhook)
            chest.enabled = flag(chest.enabled)
        end
    end

    local actorMember = actor.member
    return {
        organisation = org, ranks = ranks, members = members, goals = goals,
        ranking = ranking, routes = routes, chests = chests,
        dutyBlip = dutyBlip, legalOrganisations = legalOrganisations,
        actor = {
            userId = actor.userId, admin = actor.admin,
            rankKey = actorMember and actorMember.rank_key,
            level = actorMember and tonumber(actorMember.level),
            permissions = actor.permissions,
        },
        config = {
            blacklistDays = OBOrgConfig.BlacklistDays,
            payrollIntervalMinutes = math.max(1, tonumber(OBOrgConfig.PayrollIntervalMinutes) or 30),
        },
    }
end

local function onlineLeadersPayload()
    local rows = OR.Database.query.await([[SELECT m.user_id, m.on_duty,
        o.id AS org_id, o.org_key, o.label AS org_label, o.org_type, o.auto_duty,
        r.rank_key, r.label AS rank_label, r.level, c.firstname, c.lastname
        FROM ob_org_members m
        JOIN ob_orgs o ON o.id=m.org_id
        JOIN ob_org_ranks r ON r.id=m.rank_id
        JOIN ob_characters c ON c.user_id=m.user_id
        WHERE o.active=1 AND r.level=(SELECT MIN(r2.level) FROM ob_org_ranks r2 WHERE r2.org_id=o.id)
        ORDER BY o.org_type,o.label,c.firstname,c.lastname]]) or {}
    local leaders = {}
    for _, row in ipairs(rows) do
        local playerSource = onlineSource(row.user_id)
        if playerSource then
            leaders[#leaders + 1] = {
                user_id = tonumber(row.user_id), session_id = playerSource,
                name = text(('%s %s'):format(row.firstname or '', row.lastname or ''), 80),
                org_id = tonumber(row.org_id), org_key = row.org_key, org_label = row.org_label,
                org_type = row.org_type, rank_key = row.rank_key, rank_label = row.rank_label,
                on_duty = row.org_type == 'legal' and (flag(row.auto_duty) or flag(row.on_duty)) or nil,
            }
        end
    end
    return leaders
end

local function refreshWorld()
    TriggerClientEvent('ob_org:client:refreshWorld', -1)
end

RegisterCommand(OBOrgConfig.Commands.admin or 'adminorg', function(source)
    source = tonumber(source)
    if not source or source <= 0 then
        print('[ob_org] O painel administrativo deve ser aberto dentro do jogo.')
        return
    end
    if not isAdmin(source) then
        notify(source, 'Sem permissao para abrir o painel de organizacoes.', 'error')
        return
    end
    TriggerClientEvent('ob_org:client:openPanel', source, 'admin')
end, false)

local schema = {
    [[CREATE TABLE IF NOT EXISTS ob_orgs (
        id int unsigned NOT NULL AUTO_INCREMENT, org_key varchar(48) NOT NULL, label varchar(80) NOT NULL,
        logo_url varchar(512) NULL, org_type enum('legal','illegal') NOT NULL, max_members int unsigned NOT NULL DEFAULT 250,
        auto_duty tinyint(1) NOT NULL DEFAULT 0, duty_coords text NULL, active tinyint(1) NOT NULL DEFAULT 1,
        created_at timestamp NOT NULL DEFAULT current_timestamp(), updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
        PRIMARY KEY(id), UNIQUE KEY uq_ob_org_key(org_key)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS ob_org_ranks (
        id int unsigned NOT NULL AUTO_INCREMENT, org_id int unsigned NOT NULL, rank_key varchar(48) NOT NULL,
        label varchar(80) NOT NULL, level int unsigned NOT NULL, salary int unsigned NOT NULL DEFAULT 0,
        member_limit int unsigned NOT NULL DEFAULT 0, permissions text NOT NULL,
        PRIMARY KEY(id), UNIQUE KEY uq_ob_org_rank(org_id,rank_key), KEY idx_ob_org_rank_level(org_id,level)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS ob_org_members (
        org_id int unsigned NOT NULL, user_id bigint unsigned NOT NULL, rank_id int unsigned NOT NULL,
        on_duty tinyint(1) NOT NULL DEFAULT 0, joined_at timestamp NOT NULL DEFAULT current_timestamp(),
        PRIMARY KEY(user_id), KEY idx_ob_org_members_org(org_id), KEY idx_ob_org_members_rank(rank_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS ob_org_duty_blips (
        org_id int unsigned NOT NULL, enabled tinyint(1) NOT NULL DEFAULT 1,
        label varchar(80) NOT NULL, sprite int unsigned NOT NULL DEFAULT 1,
        colour int unsigned NOT NULL DEFAULT 3, scale decimal(4,2) NOT NULL DEFAULT 0.75,
        helicopter_sprite int unsigned NOT NULL DEFAULT 422, visible_to text NOT NULL,
        updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
        PRIMARY KEY(org_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS ob_org_blacklist (
        user_id bigint unsigned NOT NULL, previous_org_id int unsigned NULL, reason varchar(160) NOT NULL,
        expires_at datetime NOT NULL, created_at timestamp NOT NULL DEFAULT current_timestamp(),
        PRIMARY KEY(user_id), KEY idx_ob_org_blacklist_expiry(expires_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS ob_org_goals (
        id int unsigned NOT NULL AUTO_INCREMENT, org_id int unsigned NOT NULL, title varchar(100) NOT NULL,
        target int unsigned NOT NULL, active tinyint(1) NOT NULL DEFAULT 1, created_at timestamp NOT NULL DEFAULT current_timestamp(),
        PRIMARY KEY(id), KEY idx_ob_org_goals_org(org_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS ob_org_goal_progress (
        goal_id int unsigned NOT NULL, user_id bigint unsigned NOT NULL, period_key date NOT NULL,
        progress int unsigned NOT NULL DEFAULT 0, updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
        PRIMARY KEY(goal_id,user_id,period_key)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS ob_org_routes (
        id int unsigned NOT NULL AUTO_INCREMENT, org_id int unsigned NOT NULL, name varchar(80) NOT NULL,
        npc_model varchar(80) NOT NULL DEFAULT 'g_m_y_mexgoon_01', npc_coords text NULL,
        max_rewards int unsigned NOT NULL DEFAULT 1, collect_duration int unsigned NOT NULL DEFAULT 3000,
        enabled tinyint(1) NOT NULL DEFAULT 1, PRIMARY KEY(id), KEY idx_ob_org_routes_org(org_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS ob_org_route_points (
        id int unsigned NOT NULL AUTO_INCREMENT, route_id int unsigned NOT NULL, position int unsigned NOT NULL,
        x double NOT NULL, y double NOT NULL, z double NOT NULL, PRIMARY KEY(id), KEY idx_ob_org_points(route_id,position)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS ob_org_route_rewards (
        id int unsigned NOT NULL AUTO_INCREMENT, route_id int unsigned NOT NULL, item_name varchar(64) NOT NULL,
        min_amount int unsigned NOT NULL, max_amount int unsigned NOT NULL, chance decimal(5,2) NOT NULL DEFAULT 100,
        PRIMARY KEY(id), KEY idx_ob_org_rewards_route(route_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS ob_org_route_log (
        id bigint unsigned NOT NULL AUTO_INCREMENT, org_id int unsigned NOT NULL, route_id int unsigned NOT NULL,
        user_id bigint unsigned NOT NULL, completed_at timestamp NOT NULL DEFAULT current_timestamp(),
        PRIMARY KEY(id), KEY idx_ob_org_route_rank(org_id,completed_at), KEY idx_ob_org_route_user(user_id,completed_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS ob_org_chests (
        id int unsigned NOT NULL AUTO_INCREMENT, org_id int unsigned NOT NULL, label varchar(80) NOT NULL,
        chest_type enum('storage','discard') NOT NULL DEFAULT 'storage', slots int unsigned NOT NULL DEFAULT 30,
        max_weight bigint unsigned NOT NULL DEFAULT 100000, coords text NOT NULL, webhook_url varchar(1000) NULL,
        enabled tinyint(1) NOT NULL DEFAULT 1, created_at timestamp NOT NULL DEFAULT current_timestamp(),
        updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
        PRIMARY KEY(id), KEY idx_ob_org_chests_org(org_id,enabled)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS ob_org_chest_logs (
        id bigint unsigned NOT NULL AUTO_INCREMENT, chest_id int unsigned NOT NULL, org_id int unsigned NOT NULL,
        user_id bigint unsigned NOT NULL, player_name varchar(80) NOT NULL, action enum('deposit','withdraw','discard') NOT NULL,
        item_name varchar(64) NOT NULL, amount int unsigned NOT NULL, metadata text NULL,
        created_at timestamp NOT NULL DEFAULT current_timestamp(), PRIMARY KEY(id),
        KEY idx_ob_org_chest_logs_chest(chest_id,created_at), KEY idx_ob_org_chest_logs_user(user_id,created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

CreateThread(function()
    if not OR.Database.waitForReady(30000) then return end
    for _, statement in ipairs(schema) do
        local result, err = OR.Database.query.await(statement)
        if result == nil then print(('[ob_org] Falha no schema: %s'):format(err or 'desconhecida')); return end
    end
    loadDutyBlipSettings(true)
    ready = true
    for _, org in ipairs(OR.Database.query.await("SELECT org_key,label,org_type FROM ob_orgs WHERE active=1 AND org_type='legal'") or {}) do registerLegalJob(org) end
    for _, source in ipairs(GetPlayers()) do syncMember(tonumber(source), true) end
    print('[ob_org] Organizacoes, metas, rotas e baus prontos.')
end)

OR.Callback.register('panel', function(source, mode, selectedOrgId)
    if not ready then return nil, 'Banco de organizacoes ainda nao esta pronto.' end
    if mode == 'admin' then
        if not isAdmin(source) then return nil, 'Sem permissao administrativa.' end
        local organisations = OR.Database.query.await([[SELECT o.*, COUNT(m.user_id) AS member_count
            FROM ob_orgs o LEFT JOIN ob_org_members m ON m.org_id=o.id GROUP BY o.id ORDER BY o.org_type,o.label]]) or {}
        for _, org in ipairs(organisations) do org.auto_duty=flag(org.auto_duty);org.active=flag(org.active);org.duty=decode(org.duty_coords,nil);org.duty_coords=nil end
        local blacklist = OR.Database.query.await([[SELECT b.user_id,b.reason,b.expires_at,b.created_at,
            o.label AS previous_org_label,c.firstname,c.lastname
            FROM ob_org_blacklist b
            LEFT JOIN ob_orgs o ON o.id=b.previous_org_id
            LEFT JOIN ob_characters c ON c.user_id=b.user_id
            WHERE b.expires_at>NOW() ORDER BY b.expires_at]]) or {}
        for _, entry in ipairs(blacklist) do
            entry.name = text(('%s %s'):format(entry.firstname or '', entry.lastname or ''), 80)
            entry.firstname, entry.lastname = nil, nil
        end
        local selected
        if tonumber(selectedOrgId) then
            local actor = actorContext(source, selectedOrgId, true)
            selected = actor and organisationPayload(tonumber(selectedOrgId), actor) or nil
        end
        return {
            mode='admin', organisations=organisations, blacklist=blacklist,
            onlineLeaders=onlineLeadersPayload(), selected=selected,
        }
    end

    local actor, err = actorContext(source, nil, false)
    if not actor then return nil, err end
    local expected = mode == 'illegal' and 'illegal' or 'legal'
    if actor.member.org_type ~= expected then return nil, expected == 'illegal' and 'Voce nao pertence a uma organizacao ilegal.' or 'Voce nao pertence a uma organizacao legal.' end
    return { mode=expected, selected=organisationPayload(actor.orgId, actor) }
end)

local defaultLeaderPermissions = {
    view=true, members_add=true, members_rank=true, members_remove=true,
    branding_manage=true, goals_manage=true,
}

local function createOrganisation(source, data)
    if not isAdmin(source) then return false, 'Sem permissao administrativa.' end
    local orgKey, label = key(data.orgKey), text(data.label, 80)
    local orgType = data.orgType == 'illegal' and 'illegal' or data.orgType == 'legal' and 'legal' or nil
    if not orgKey or label == '' or not orgType then return false, 'Nome interno, nome e tipo sao obrigatorios.' end
    local count = tonumber(OR.Database.scalar.await('SELECT COUNT(*) FROM ob_orgs')) or 0
    if count >= OBOrgConfig.Limits.organisations then return false, 'Limite global de organizacoes atingido.' end
    local id, err = OR.Database.insert.await([[INSERT INTO ob_orgs (org_key,label,org_type,max_members,auto_duty)
        VALUES (?,?,?,?,?)]], { orgKey,label,orgType,integer(data.maxMembers,1,2000,OBOrgConfig.Limits.membersDefault),flag(data.autoDuty) and 1 or 0 })
    if not id then return false, err or 'Nao foi possivel criar a organizacao.' end
    local leaderKey = orgType == 'illegal' and 'leader' or 'chief'
    local leaderLabel = orgType == 'illegal' and 'Lider' or 'Chefia'
    OR.Database.insert.await('INSERT INTO ob_org_ranks (org_id,rank_key,label,level,salary,member_limit,permissions) VALUES (?,?,?,?,?,?,?)',
        { id,leaderKey,leaderLabel,1,0,1,json.encode(defaultLeaderPermissions) })
    OR.Database.insert.await('INSERT INTO ob_org_ranks (org_id,rank_key,label,level,salary,member_limit,permissions) VALUES (?,?,?,?,?,?,?)',
        { id,'member','Membro',100,0,0,json.encode({view=true}) })
    if orgType == 'legal' then
        registerLegalJob({org_key=orgKey,label=label,org_type=orgType})
        loadDutyBlipSettings(true)
    end
    refreshWorld()
    return true, 'Organizacao criada.', id
end

local function deleteOrganisation(source, data, adminPanel)
    if not adminPanel or not isAdmin(source) then
        return false, 'Abra o painel administrativo para excluir organizacoes.'
    end
    local orgId = math.floor(tonumber(data.orgId) or 0)
    local org = OR.Database.single.await('SELECT id,org_key,label,org_type FROM ob_orgs WHERE id=? LIMIT 1', {orgId})
    if not org then return false, 'Organizacao invalida.' end

    local members = OR.Database.query.await('SELECT user_id FROM ob_org_members WHERE org_id=?', {orgId}) or {}
    local chests = OR.Database.query.await('SELECT id FROM ob_org_chests WHERE org_id=?', {orgId}) or {}
    local statements = {
        {[[DELETE p FROM ob_org_goal_progress p JOIN ob_org_goals g ON g.id=p.goal_id WHERE g.org_id=?]], {orgId}},
        {[[DELETE p FROM ob_org_route_points p JOIN ob_org_routes r ON r.id=p.route_id WHERE r.org_id=?]], {orgId}},
        {[[DELETE rw FROM ob_org_route_rewards rw JOIN ob_org_routes r ON r.id=rw.route_id WHERE r.org_id=?]], {orgId}},
        {'DELETE FROM ob_org_route_log WHERE org_id=?', {orgId}},
        {'DELETE FROM ob_org_goals WHERE org_id=?', {orgId}},
        {'DELETE FROM ob_org_routes WHERE org_id=?', {orgId}},
        {'DELETE FROM ob_org_chests WHERE org_id=?', {orgId}},
        {'DELETE FROM ob_org_duty_blips WHERE org_id=?', {orgId}},
        {'DELETE FROM ob_org_members WHERE org_id=?', {orgId}},
        {'DELETE FROM ob_org_ranks WHERE org_id=?', {orgId}},
        {'UPDATE ob_org_blacklist SET previous_org_id=NULL WHERE previous_org_id=?', {orgId}},
        {'DELETE FROM ob_orgs WHERE id=?', {orgId}},
    }
    for _, statement in ipairs(statements) do
        local changed, deleteError = OR.Database.update.await(statement[1], statement[2])
        if changed == nil then
            return false, ('Falha ao excluir a organizacao (%s).'):format(deleteError or 'banco de dados')
        end
    end
    loadDutyBlipSettings(false)

    for _, chest in ipairs(chests) do
        local removed, inventoryError = exports.ob_inventory:DeleteOwnedInventory('org_chest', tostring(chest.id))
        if not removed then print(('[ob_org] Falha ao apagar inventario do bau %s: %s'):format(chest.id, tostring(inventoryError))) end
    end

    for playerSource, session in pairs(routeSessions) do
        if tonumber(session.orgId) == orgId then
            routeSessions[playerSource] = nil
            TriggerClientEvent('ob_org:client:organisationRemoved', playerSource)
        end
    end
    for _, member in ipairs(members) do
        local playerSource = onlineSource(member.user_id)
        if playerSource then
            Player(playerSource).state:set('ob:org', nil, true)
            if org.org_type == 'legal' then
                local job = exports.ob_core:GetJob(playerSource)
                if job and job.name == org.org_key then exports.ob_core:SetJob(playerSource, 'unemployed', 0, false) end
            end
            TriggerClientEvent('ob_org:client:refreshWorld', playerSource)
        end
    end
    if org.org_type == 'legal' then exports.ob_core:RemoveJobDefinition(org.org_key) end
    refreshWorld()
    return true, ('Organizacao %s excluida. Os membros foram liberados sem blacklist.'):format(org.label)
end

local function addMember(source, data, adminPanel)
    local actor, err = actorContext(source, data.orgId, adminPanel)
    if not actor then return false, err end
    if not hasPermission(actor, 'members_add') then return false, 'Seu cargo nao pode adicionar membros.' end
    local targetId = math.floor(tonumber(data.userId) or 0)
    if targetId <= 0 or not characterName(targetId) then return false, 'ID fixo de personagem invalido.' end
    if membership(targetId) then return false, 'Esse personagem ja pertence a uma organizacao.' end
    local blocked = OR.Database.single.await('SELECT expires_at FROM ob_org_blacklist WHERE user_id=? AND expires_at>NOW() LIMIT 1', {targetId})
    if blocked then return false, ('Esse personagem esta na blacklist ate %s.'):format(tostring(blocked.expires_at)) end
    OR.Database.update.await('DELETE FROM ob_org_blacklist WHERE user_id=? AND expires_at<=NOW()', {targetId})
    local org = OR.Database.single.await('SELECT max_members FROM ob_orgs WHERE id=? AND active=1', {actor.orgId})
    local count = tonumber(OR.Database.scalar.await('SELECT COUNT(*) FROM ob_org_members WHERE org_id=?',{actor.orgId})) or 0
    if not org or count >= tonumber(org.max_members) then return false, 'Limite de membros atingido.' end
    local rank = OR.Database.single.await('SELECT * FROM ob_org_ranks WHERE id=? AND org_id=?',{tonumber(data.rankId),actor.orgId})
    if not rank then rank=OR.Database.single.await('SELECT * FROM ob_org_ranks WHERE org_id=? ORDER BY level DESC LIMIT 1',{actor.orgId}) end
    if not rank then return false, 'A organizacao nao possui cargo.' end
    if not actor.admin and tonumber(rank.level)<=actor.level then return false,'Voce nao pode adicionar alguem nesse cargo.' end
    local rankCount = tonumber(OR.Database.scalar.await('SELECT COUNT(*) FROM ob_org_members WHERE rank_id=?',{rank.id})) or 0
    if tonumber(rank.member_limit)>0 and rankCount>=tonumber(rank.member_limit) then return false,'Limite desse cargo atingido.' end
    local inserted, insertErr = OR.Database.insert.await('INSERT INTO ob_org_members (org_id,user_id,rank_id,on_duty) VALUES (?,?,?,0)',{actor.orgId,targetId,rank.id})
    if not inserted then return false,insertErr or 'Nao foi possivel adicionar.' end
    local targetSource=onlineSource(targetId);if targetSource then syncMember(targetSource) end
    return true,'Membro adicionado.'
end

local function removeMember(source, data, adminPanel)
    local actor, err = actorContext(source, data.orgId, adminPanel); if not actor then return false,err end
    if not hasPermission(actor,'members_remove') then return false,'Seu cargo nao pode remover membros.' end
    local targetId=math.floor(tonumber(data.userId) or 0)
    local target=membership(targetId)
    if not target or tonumber(target.org_id)~=actor.orgId then return false,'Membro invalido.' end
    if not actor.admin and targetId==actor.userId then return false,'Voce nao pode sair da organizacao pelo painel. A administracao precisa remover o lider pelo adminorg.' end
    if not actor.admin and tonumber(target.level)<=actor.level then return false,'Lideres e membros de hierarquia igual ou superior so podem ser removidos pelo adminorg.' end
    OR.Database.update.await('DELETE FROM ob_org_members WHERE user_id=?',{targetId})
    local expiry=os.time()+(integer(OBOrgConfig.BlacklistDays,0,365,4)*86400)
    OR.Database.query.await([[INSERT INTO ob_org_blacklist (user_id,previous_org_id,reason,expires_at) VALUES (?,?,?,FROM_UNIXTIME(?))
        ON DUPLICATE KEY UPDATE previous_org_id=VALUES(previous_org_id),reason=VALUES(reason),expires_at=VALUES(expires_at)]],
        {targetId,actor.orgId,text(data.reason,160)~='' and text(data.reason,160) or 'Removido da organizacao',expiry})
    local targetSource=onlineSource(targetId);if targetSource then publishMembership(targetSource,nil) end
    if targetSource then TriggerClientEvent('ob_org:client:refreshWorld',targetSource) end
    return true,('Membro removido e bloqueado por %s dia(s).'):format(OBOrgConfig.BlacklistDays)
end

local function setMemberRank(source,data,adminPanel)
    local actor,err=actorContext(source,data.orgId,adminPanel);if not actor then return false,err end
    if not hasPermission(actor,'members_rank') then return false,'Seu cargo nao pode alterar cargos.' end
    local targetId=math.floor(tonumber(data.userId) or 0)
    local target=membership(targetId);local rank=OR.Database.single.await('SELECT * FROM ob_org_ranks WHERE id=? AND org_id=?',{tonumber(data.rankId),actor.orgId})
    if not target or tonumber(target.org_id)~=actor.orgId or not rank then return false,'Membro ou cargo invalido.' end
    if not actor.admin and targetId==actor.userId then return false,'Voce nao pode alterar o proprio cargo. A administracao precisa fazer isso pelo adminorg.' end
    if not actor.admin and (tonumber(target.level)<=actor.level or tonumber(rank.level)<=actor.level) then return false,'Lideres e cargos de hierarquia igual ou superior so podem ser alterados pelo adminorg.' end
    local count=tonumber(OR.Database.scalar.await('SELECT COUNT(*) FROM ob_org_members WHERE rank_id=?',{rank.id})) or 0
    if tonumber(rank.member_limit)>0 and count>=tonumber(rank.member_limit) then return false,'Limite desse cargo atingido.' end
    OR.Database.update.await('UPDATE ob_org_members SET rank_id=? WHERE user_id=?',{rank.id,targetId})
    local targetSource=onlineSource(targetId);if targetSource then syncMember(targetSource) end
    return true,'Cargo atualizado.'
end

local function saveRank(source,data,adminPanel)
    local actor,err=actorContext(source,data.orgId,adminPanel);if not actor then return false,err end
    if not actor.admin then return false,'Cargos so podem ser editados pelo painel administrativo.' end
    local rankKey,label=key(data.rankKey),text(data.label,80)
    if not rankKey or label=='' then return false,'Chave e nome do cargo sao obrigatorios.' end
    local permissions
    permissions={}
    for _,permission in ipairs({'view','members_add','members_rank','members_remove','branding_manage','goals_manage'}) do
        permissions[permission]=type(data.permissions)=='table' and data.permissions[permission]==true or false
    end
    permissions.view=true
    permissions.access=accessPermissionList(data.accessPermissions)
    local level=integer(data.level,1,100,100);local salary=integer(data.salary,0,OBOrgConfig.Limits.maxSalary,0);local limit=integer(data.memberLimit,0,2000,0)
    if tonumber(data.id) then
        local rank=OR.Database.single.await('SELECT id,level,permissions FROM ob_org_ranks WHERE id=? AND org_id=?',{data.id,actor.orgId});if not rank then return false,'Cargo invalido.' end
        OR.Database.update.await('UPDATE ob_org_ranks SET rank_key=?,label=?,level=?,salary=?,member_limit=?,permissions=? WHERE id=?',{rankKey,label,level,salary,limit,json.encode(permissions),rank.id})
    else
        local count=tonumber(OR.Database.scalar.await('SELECT COUNT(*) FROM ob_org_ranks WHERE org_id=?',{actor.orgId})) or 0
        if count>=OBOrgConfig.Limits.ranksPerOrganisation then return false,'Limite de cargos atingido.' end
        local id,insertErr=OR.Database.insert.await('INSERT INTO ob_org_ranks (org_id,rank_key,label,level,salary,member_limit,permissions) VALUES (?,?,?,?,?,?,?)',{actor.orgId,rankKey,label,level,salary,limit,json.encode(permissions)})
        if not id then return false,insertErr or 'Nao foi possivel criar o cargo.' end
    end
    for _,player in ipairs(GetPlayers()) do syncMember(tonumber(player)) end
    return true,'Cargo salvo.'
end

local function saveGoal(source,data,adminPanel)
    local actor,err=actorContext(source,data.orgId,adminPanel);if not actor then return false,err end
    local orgType=OR.Database.scalar.await('SELECT org_type FROM ob_orgs WHERE id=?',{actor.orgId})
    if not hasPermission(actor,'goals_manage') or orgType~='illegal' then return false,'Sem permissao para metas.' end
    local title=text(data.title,100);local target=integer(data.target,1,100000,1)
    if title=='' then return false,'Informe o nome da meta.' end
    if tonumber(data.id) then
        OR.Database.update.await('UPDATE ob_org_goals SET title=?,target=?,active=? WHERE id=? AND org_id=?',{title,target,flag(data.active) and 1 or 0,data.id,actor.orgId})
    else
        local count=tonumber(OR.Database.scalar.await('SELECT COUNT(*) FROM ob_org_goals WHERE org_id=?',{actor.orgId})) or 0
        if count>=OBOrgConfig.Limits.goalsPerOrganisation then return false,'Limite de metas atingido.' end
        OR.Database.insert.await('INSERT INTO ob_org_goals (org_id,title,target,active) VALUES (?,?,?,1)',{actor.orgId,title,target})
    end
    return true,'Meta salva. O progresso e individual por membro e reinicia diariamente.'
end

local function saveRoute(source,data,coords,adminPanel)
    local actor,err=actorContext(source,data.orgId,adminPanel);if not actor then return false,err end
    if not actor.admin then return false,'Somente a administracao pode editar rotas.' end
    local org=OR.Database.single.await('SELECT org_type FROM ob_orgs WHERE id=?',{actor.orgId});if not org or org.org_type~='illegal' then return false,'Rotas pertencem somente a organizacoes ilegais.' end
    local name=text(data.name,80);local model=key(data.npcModel) or 'g_m_y_mexgoon_01'
    if name=='' then return false,'Informe o nome da rota.' end
    local npc=nil
    if type(coords)=='table' and (not tonumber(data.id) or flag(data.moveNpc)) then npc={x=tonumber(coords.x),y=tonumber(coords.y),z=tonumber(coords.z),w=tonumber(coords.w) or 0.0} end
    if tonumber(data.id) then
        local route=OR.Database.single.await('SELECT * FROM ob_org_routes WHERE id=? AND org_id=?',{data.id,actor.orgId});if not route then return false,'Rota invalida.' end
        OR.Database.update.await('UPDATE ob_org_routes SET name=?,npc_model=?,npc_coords=?,max_rewards=?,collect_duration=?,enabled=? WHERE id=?',{
            name,model,npc and json.encode(npc) or route.npc_coords,integer(data.maxRewards,1,20,1),integer(data.collectDuration,500,30000,OBOrgConfig.Interaction.collectDuration),flag(data.enabled) and 1 or 0,route.id})
    else
        if not npc then return false,'Fique no local do NPC para criar a rota.' end
        local count=tonumber(OR.Database.scalar.await('SELECT COUNT(*) FROM ob_org_routes WHERE org_id=?',{actor.orgId})) or 0
        if count>=OBOrgConfig.Limits.routesPerOrganisation then return false,'Limite de rotas atingido.' end
        OR.Database.insert.await('INSERT INTO ob_org_routes (org_id,name,npc_model,npc_coords,max_rewards,collect_duration,enabled) VALUES (?,?,?,?,?,?,1)',{
            actor.orgId,name,model,json.encode(npc),integer(data.maxRewards,1,20,1),integer(data.collectDuration,500,30000,OBOrgConfig.Interaction.collectDuration)})
    end
    refreshWorld();return true,'Rota salva.'
end

local function discordWebhook(value)
    value = text(value, 1000)
    if value == '' then return nil end
    if value:match('^https://discord%.com/api/webhooks/%d+/[%w_%-]+')
        or value:match('^https://discordapp%.com/api/webhooks/%d+/[%w_%-]+') then
        return value
    end
    return false
end

local function saveChest(source, data, coords, adminPanel)
    local actor, err = actorContext(source, data.orgId, adminPanel)
    if not actor then return false, err end
    if not actor.admin then return false, 'Somente a administracao pode editar baus.' end

    local chestId = math.floor(tonumber(data.id) or 0)
    local existing = chestId > 0 and OR.Database.single.await(
        'SELECT * FROM ob_org_chests WHERE id=? AND org_id=? LIMIT 1', { chestId, actor.orgId }
    ) or nil
    if chestId > 0 and not existing then return false, 'Bau invalido.' end

    local label = text(data.label, 80)
    if label == '' then return false, 'Informe o nome do bau.' end
    local chestType = data.chestType == 'discard' and 'discard' or 'storage'
    if existing and existing.chest_type ~= chestType then
        return false, 'O tipo do bau nao pode ser alterado depois da criacao.'
    end

    local maximumSlots = integer(OBOrgConfig.Limits.chestSlots, 5, 500, 200)
    local maximumWeightKg = integer(OBOrgConfig.Limits.chestWeightKg, 1, 1000000, 100000)
    local slots = chestType == 'storage' and integer(data.slots, 5, maximumSlots, 30) or 30
    local weightKg = chestType == 'storage' and integer(data.maxWeightKg, 1, maximumWeightKg, 100) or 1
    local webhook = discordWebhook(data.webhookUrl)
    if webhook == false then return false, 'Webhook invalido. Use uma URL de webhook do Discord.' end
    if existing and webhook == nil and not flag(data.removeWebhook) then webhook = existing.webhook_url end
    -- O wrapper de banco conta parametros posicionais; string vazia evita uma
    -- lacuna Lua no meio do array quando nao houver webhook.
    webhook = webhook or ''

    local position = existing and existing.coords or nil
    if not existing or flag(data.moveChest) then
        if type(coords) ~= 'table' or not tonumber(coords.x) or not tonumber(coords.y) or not tonumber(coords.z) then
            return false, 'Fique no local do bau para salvar a posicao.'
        end
        position = json.encode({ x = tonumber(coords.x), y = tonumber(coords.y), z = tonumber(coords.z) })
    end

    if existing then
        local changed, updateError = OR.Database.update.await([[UPDATE ob_org_chests
            SET label=?,slots=?,max_weight=?,coords=?,webhook_url=?,enabled=? WHERE id=? AND org_id=?]], {
            label, slots, weightKg * 1000, position, webhook, flag(data.enabled) and 1 or 0, chestId, actor.orgId,
        })
        if changed == nil then return false, updateError or 'Nao foi possivel atualizar o bau.' end
    else
        local count = tonumber(OR.Database.scalar.await('SELECT COUNT(*) FROM ob_org_chests WHERE org_id=?', { actor.orgId })) or 0
        if count >= integer(OBOrgConfig.Limits.chestsPerOrganisation, 1, 100, 20) then return false, 'Limite de baus atingido.' end
        local inserted, insertError = OR.Database.insert.await([[INSERT INTO ob_org_chests
            (org_id,label,chest_type,slots,max_weight,coords,webhook_url,enabled) VALUES (?,?,?,?,?,?,?,?)]], {
            actor.orgId, label, chestType, slots, weightKg * 1000, position, webhook, flag(data.enabled) and 1 or 0,
        })
        if not inserted then return false, insertError or 'Nao foi possivel criar o bau.' end
    end
    refreshWorld()
    return true, existing and 'Bau atualizado.' or 'Bau criado na sua posicao.'
end

local function deleteChest(source, data, adminPanel)
    local actor, err = actorContext(source, data.orgId, adminPanel)
    if not actor then return false, err end
    if not actor.admin then return false, 'Somente a administracao pode excluir baus.' end
    local chestId = math.floor(tonumber(data.chestId) or 0)
    local chest = OR.Database.single.await('SELECT id,label FROM ob_org_chests WHERE id=? AND org_id=?', { chestId, actor.orgId })
    if not chest then return false, 'Bau invalido.' end
    local deleted, deleteError = OR.Database.update.await('DELETE FROM ob_org_chests WHERE id=? AND org_id=?', { chestId, actor.orgId })
    if deleted == nil then return false, deleteError or 'Nao foi possivel excluir o bau.' end
    local ok, inventoryError = exports.ob_inventory:DeleteOwnedInventory('org_chest', tostring(chestId))
    if not ok then print(('[ob_org] Falha ao apagar inventario do bau %s: %s'):format(chestId, tostring(inventoryError))) end
    refreshWorld()
    return true, ('Bau %s excluido. O historico de auditoria foi mantido.'):format(chest.label)
end

local function saveDutyBlip(source, data, adminPanel)
    if not adminPanel or not isAdmin(source) then
        return false, 'Abra o adminorg para configurar os blips de servico.'
    end
    local orgId = math.floor(tonumber(data.orgId) or 0)
    local org = OR.Database.single.await(
        "SELECT id,org_key,label FROM ob_orgs WHERE id=? AND org_type='legal' LIMIT 1", { orgId })
    if not org then return false, 'Organizacao legal invalida.' end

    local validKeys = {}
    for _, legalOrg in ipairs(OR.Database.query.await(
        "SELECT org_key FROM ob_orgs WHERE org_type='legal'") or {}) do
        validKeys[legalOrg.org_key] = true
    end
    local visible, seen = {}, {}
    for _, value in ipairs(type(data.visibleTo) == 'table' and data.visibleTo or {}) do
        local orgKey = key(value)
        if orgKey and validKeys[orgKey] and not seen[orgKey] then
            seen[orgKey] = true
            visible[#visible + 1] = orgKey
        end
    end

    local label = text(data.label, 80)
    if label == '' then label = org.label end
    local sprite = integer(data.sprite, 1, 1000, 1)
    local colour = integer(data.colour, 0, 255, 3)
    local scale = math.max(0.30, math.min(2.00, tonumber(data.scale) or 0.75))
    local helicopterSprite = integer(data.helicopterSprite, 1, 1000, 422)
    local saved, saveError = OR.Database.query.await([[INSERT INTO ob_org_duty_blips
        (org_id,enabled,label,sprite,colour,scale,helicopter_sprite,visible_to)
        VALUES (?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE enabled=VALUES(enabled),
        label=VALUES(label),sprite=VALUES(sprite),colour=VALUES(colour),scale=VALUES(scale),
        helicopter_sprite=VALUES(helicopter_sprite),visible_to=VALUES(visible_to)]], {
        orgId, flag(data.enabled) and 1 or 0, label, sprite, colour, scale,
        helicopterSprite, json.encode(visible),
    })
    if saved == nil then return false, saveError or 'Nao foi possivel salvar os blips.' end
    loadDutyBlipSettings(false)
    return true, 'Blips de servico atualizados.'
end

OR.Callback.register('action', function(source, action, data, coords, panelMode)
    if not ready or type(data)~='table' then return false,'Dados invalidos.' end
    local adminPanel=panelMode=='admin' and isAdmin(source)
    if action=='createOrganisation' then
        if not adminPanel then return false,'Abra o painel administrativo para criar organizacoes.' end
        return createOrganisation(source,data)
    end
    if action=='deleteOrganisation' then return deleteOrganisation(source,data,adminPanel) end
    if action=='addMember' then return addMember(source,data,adminPanel) end
    if action=='removeMember' then return removeMember(source,data,adminPanel) end
    if action=='setMemberRank' then return setMemberRank(source,data,adminPanel) end
    if action=='saveRank' then return saveRank(source,data,adminPanel) end
    if action=='saveDutyBlip' then return saveDutyBlip(source,data,adminPanel) end
    if action=='saveGoal' then return saveGoal(source,data,adminPanel) end
    if action=='deleteRank' then
        local actor,err=actorContext(source,data.orgId,adminPanel);if not actor then return false,err end
        if not actor.admin then return false,'Cargos so podem ser excluidos pelo painel administrativo.' end
        local rankId=math.floor(tonumber(data.rankId) or 0)
        local rank=OR.Database.single.await('SELECT id,label FROM ob_org_ranks WHERE id=? AND org_id=?',{rankId,actor.orgId})
        if not rank then return false,'Cargo invalido.' end
        local assigned=tonumber(OR.Database.scalar.await('SELECT COUNT(*) FROM ob_org_members WHERE rank_id=?',{rankId})) or 0
        if assigned>0 then return false,('Retire os %s membro(s) desse cargo antes de excluir.'):format(assigned) end
        local total=tonumber(OR.Database.scalar.await('SELECT COUNT(*) FROM ob_org_ranks WHERE org_id=?',{actor.orgId})) or 0
        if total<=1 then return false,'A organizacao precisa manter pelo menos um cargo.' end
        OR.Database.update.await('DELETE FROM ob_org_ranks WHERE id=? AND org_id=?',{rankId,actor.orgId})
        return true,('Cargo %s excluido.'):format(rank.label)
    end
    if action=='removeBlacklist' then
        if not adminPanel then return false,'Abra o painel administrativo para alterar a blacklist.' end
        local targetId=math.floor(tonumber(data.userId) or 0)
        if targetId<=0 then return false,'ID fixo de personagem invalido.' end
        OR.Database.update.await('DELETE FROM ob_org_blacklist WHERE user_id=?',{targetId})
        return true,'Personagem liberado da blacklist.'
    end
    if action=='updateOrganisation' then
        local actor,err=actorContext(source,data.orgId,adminPanel);if not actor then return false,err end
        if not hasPermission(actor,'branding_manage') then return false,'Sem permissao para editar a organizacao.' end
        local org=OR.Database.single.await('SELECT * FROM ob_orgs WHERE id=?',{actor.orgId});if not org then return false,'Organizacao invalida.' end
        local label=text(data.label,80);if label=='' then return false,'Nome invalido.' end
        local maximum=actor.admin and integer(data.maxMembers,1,2000,org.max_members) or org.max_members
        local automatic=actor.admin and (flag(data.autoDuty) and 1 or 0) or org.auto_duty
        OR.Database.update.await('UPDATE ob_orgs SET label=?,logo_url=?,max_members=?,auto_duty=?,active=? WHERE id=?',{
            label,text(data.logoUrl,512),maximum,automatic,actor.admin and (flag(data.active) and 1 or 0) or org.active,actor.orgId})
        if org.org_type=='legal' then registerLegalJob({org_key=org.org_key,label=label,org_type='legal'}) end
        for _,player in ipairs(GetPlayers()) do syncMember(tonumber(player)) end
        refreshWorld();return true,'Organizacao atualizada.'
    end
    if action=='setDutyPosition' then
        local actor,err=actorContext(source,data.orgId,adminPanel);if not actor then return false,err end
        if not actor.admin then return false,'Somente a administracao pode alterar o local de ponto.' end
        if type(coords)~='table' then return false,'Posicao invalida.' end
        local orgType=OR.Database.scalar.await('SELECT org_type FROM ob_orgs WHERE id=?',{actor.orgId})
        if orgType~='legal' then return false,'Ponto de trabalho pertence somente a organizacoes legais.' end
        OR.Database.update.await('UPDATE ob_orgs SET duty_coords=? WHERE id=?',{json.encode({x=coords.x,y=coords.y,z=coords.z}),actor.orgId});refreshWorld();return true,'Local de ponto atualizado.'
    end
    if action=='saveRoute' then return saveRoute(source,data,coords,adminPanel) end
    if action=='saveChest' then return saveChest(source,data,coords,adminPanel) end
    if action=='deleteChest' then return deleteChest(source,data,adminPanel) end
    if action=='deleteRoute' then
        local actor,err=actorContext(source,data.orgId,adminPanel);if not actor then return false,err end
        if not actor.admin then return false,'Somente a administracao pode excluir rotas.' end
        local routeId=math.floor(tonumber(data.routeId) or 0)
        local route=OR.Database.single.await('SELECT id,name FROM ob_org_routes WHERE id=? AND org_id=?',{routeId,actor.orgId})
        if not route then return false,'Rota invalida.' end
        OR.Database.update.await('DELETE FROM ob_org_route_points WHERE route_id=?',{routeId})
        OR.Database.update.await('DELETE FROM ob_org_route_rewards WHERE route_id=?',{routeId})
        OR.Database.update.await('DELETE FROM ob_org_routes WHERE id=? AND org_id=?',{routeId,actor.orgId})
        for playerSource,session in pairs(routeSessions) do
            if tonumber(session.routeId)==routeId then
                routeSessions[playerSource]=nil
                TriggerClientEvent('ob_org:client:routeRemoved',playerSource,routeId)
            end
        end
        refreshWorld()
        return true,('Rota %s excluida.'):format(route.name)
    end
    if action=='addRoutePoint' then
        local actor,err=actorContext(source,data.orgId,adminPanel);if not actor then return false,err end
        if not actor.admin or type(coords)~='table' then return false,'Somente a administracao pode editar pontos de rota.' end
        local route=OR.Database.single.await('SELECT id FROM ob_org_routes WHERE id=? AND org_id=?',{data.routeId,actor.orgId});if not route then return false,'Rota invalida.' end
        local count=tonumber(OR.Database.scalar.await('SELECT COUNT(*) FROM ob_org_route_points WHERE route_id=?',{route.id})) or 0
        if count>=OBOrgConfig.Limits.pointsPerRoute then return false,'Limite de pontos atingido.' end
        local lastPosition=tonumber(OR.Database.scalar.await('SELECT COALESCE(MAX(position),0) FROM ob_org_route_points WHERE route_id=?',{route.id})) or 0
        OR.Database.insert.await('INSERT INTO ob_org_route_points (route_id,position,x,y,z) VALUES (?,?,?,?,?)',{route.id,lastPosition+1,coords.x,coords.y,coords.z});return true,'Ponto adicionado.'
    end
    if action=='deleteRoutePoint' then
        local actor,err=actorContext(source,data.orgId,adminPanel);if not actor then return false,err end
        if not actor.admin then return false,'Somente a administracao pode editar pontos de rota.' end
        OR.Database.update.await([[DELETE p FROM ob_org_route_points p JOIN ob_org_routes r ON r.id=p.route_id WHERE p.id=? AND r.org_id=?]],{data.pointId,actor.orgId});return true,'Ponto removido.'
    end
    if action=='saveRouteReward' then
        local actor,err=actorContext(source,data.orgId,adminPanel);if not actor then return false,err end
        if not actor.admin then return false,'Somente a administracao pode editar recompensas de rota.' end
        local route=OR.Database.single.await('SELECT id FROM ob_org_routes WHERE id=? AND org_id=?',{data.routeId,actor.orgId});local item=key(data.itemName)
        if not route or not item then return false,'Rota ou item invalido.' end
        local count=tonumber(OR.Database.scalar.await('SELECT COUNT(*) FROM ob_org_route_rewards WHERE route_id=?',{route.id})) or 0
        if count>=OBOrgConfig.Limits.rewardsPerRoute then return false,'Limite de recompensas atingido.' end
        local minimum=integer(data.minAmount,1,OBOrgConfig.Limits.maxRewardAmount,1);local maximum=integer(data.maxAmount,minimum,OBOrgConfig.Limits.maxRewardAmount,minimum)
        OR.Database.insert.await('INSERT INTO ob_org_route_rewards (route_id,item_name,min_amount,max_amount,chance) VALUES (?,?,?,?,?)',{route.id,item,minimum,maximum,math.max(0.01,math.min(100,tonumber(data.chance) or 100))});return true,'Recompensa adicionada.'
    end
    if action=='deleteRouteReward' then
        local actor,err=actorContext(source,data.orgId,adminPanel);if not actor then return false,err end
        if not actor.admin then return false,'Somente a administracao pode editar recompensas de rota.' end
        OR.Database.update.await([[DELETE rw FROM ob_org_route_rewards rw JOIN ob_org_routes r ON r.id=rw.route_id WHERE rw.id=? AND r.org_id=?]],{data.rewardId,actor.orgId});return true,'Recompensa removida.'
    end
    return false,'Acao desconhecida.'
end)

local function chestAccess(source, chestId)
    source = tonumber(source)
    local id = source and userId(source) or nil
    if not id then return nil, 'Personagem ainda nao esta carregado.' end
    local member = membership(id)
    if not member or not flag(member.active) then return nil, 'Voce nao pertence a uma organizacao ativa.' end
    local chest = OR.Database.single.await([[SELECT c.*,o.label AS org_label,o.active AS org_active
        FROM ob_org_chests c JOIN ob_orgs o ON o.id=c.org_id
        WHERE c.id=? LIMIT 1]], { math.floor(tonumber(chestId) or 0) })
    if not chest or not flag(chest.enabled) or not flag(chest.org_active) then return nil, 'Esse bau esta indisponivel.' end
    if tonumber(member.org_id) ~= tonumber(chest.org_id) then return nil, 'Esse bau pertence a outra organizacao.' end
    chest.position = decode(chest.coords, nil)
    if not chest.position then return nil, 'A posicao desse bau e invalida.' end
    local ped = GetPlayerPed(source)
    if not ped or ped <= 0 then return nil, 'Personagem indisponivel.' end
    local here = GetEntityCoords(ped)
    local dx,dy,dz = here.x-chest.position.x,here.y-chest.position.y,here.z-chest.position.z
    local maximum = (tonumber(OBOrgConfig.Interaction.useDistance) or 2.0) + 1.0
    if dx*dx+dy*dy+dz*dz > maximum*maximum then return nil, 'Aproxime-se do bau.' end
    return chest, nil, id
end

local function encodeMetadata(metadata)
    local ok, encoded = pcall(json.encode, type(metadata) == 'table' and metadata or {})
    return ok and text(encoded, 4000) or '{}'
end

local function sendChestWebhook(chest, id, playerName, action, item)
    local webhook = discordWebhook(chest.webhook_url)
    if not webhook then return end
    local labels = { deposit='ENTRADA', withdraw='SAIDA', discard='DESCARTE' }
    local colours = { deposit=5763719, withdraw=16753920, discard=15548997 }
    local payload = {
        username = 'OB Org - Auditoria de baus',
        embeds = {{
            title = ('%s - %s'):format(labels[action] or action:upper(), chest.label),
            color = colours[action] or 3447003,
            fields = {
                { name='Organizacao', value=tostring(chest.org_label or chest.org_id), inline=true },
                { name='Personagem', value=('%s (ID %s)'):format(playerName, id), inline=true },
                { name='Item', value=('%sx %s (`%s`)'):format(item.amount, item.label or item.name, item.name), inline=false },
            },
            footer = { text = ('Bau #%s'):format(chest.id) },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        }},
    }
    PerformHttpRequest(webhook, function(statusCode)
        statusCode = tonumber(statusCode) or 0
        if statusCode < 200 or statusCode >= 300 then
            print(('[ob_org] Webhook do bau %s respondeu HTTP %s.'):format(chest.id, statusCode))
        end
    end, 'POST', json.encode(payload), { ['Content-Type']='application/json' })
end

local function auditChest(chest, id, action, item)
    local playerName = characterName(id) or ('Personagem %s'):format(id)
    local inserted, insertError = OR.Database.insert.await([[INSERT INTO ob_org_chest_logs
        (chest_id,org_id,user_id,player_name,action,item_name,amount,metadata) VALUES (?,?,?,?,?,?,?,?)]], {
        chest.id,chest.org_id,id,playerName,action,item.name,item.amount,encodeMetadata(item.metadata),
    })
    if not inserted then
        print(('[ob_org] Falha ao auditar bau=%s user_id=%s acao=%s: %s'):format(chest.id,id,action,tostring(insertError)))
        return false
    end
    sendChestWebhook(chest,id,playerName,action,item)
    return true
end

OR.Callback.register('openChest', function(source, chestId)
    if not ready then return false, 'Sistema de organizacoes indisponivel.' end
    local chest, err = chestAccess(source, chestId)
    if not chest then return false, err end
    local inventory
    if chest.chest_type == 'storage' then
        inventory, err = exports.ob_inventory:GetOwnedInventory('org_chest', tostring(chest.id), chest.slots, chest.max_weight)
        if not inventory then return false, err or 'Inventario do bau indisponivel.' end
    else
        inventory = { slots=30, maxWeight=0, weight=0, items={} }
    end
    return true, {
        id=tonumber(chest.id), mode=chest.chest_type, label=chest.label,
        coords=chest.position, distance=tonumber(OBOrgConfig.Interaction.useDistance) or 2.0,
        inventory=inventory,
    }
end)

OR.Callback.register('chestPut', function(source, chestId, playerSlot, amount, targetSlot, activeWeaponItem)
    if not OR.Security.rateLimit(source, 'org:chest_put', 20, 10000) then return false, 'Aguarde um instante.' end
    local chest, err, id = chestAccess(source, chestId)
    if not chest then return false, err end
    local ok, response
    if chest.chest_type == 'discard' then
        ok, response = exports.ob_inventory:DiscardPlayerItem(source, playerSlot, amount, activeWeaponItem)
    else
        ok, response = exports.ob_inventory:TransferToOwned(
            source,'org_chest',tostring(chest.id),chest.slots,chest.max_weight,
            playerSlot,amount,targetSlot,activeWeaponItem
        )
    end
    if not ok then return false, response end
    local action = chest.chest_type == 'discard' and 'discard' or 'deposit'
    local audited = auditChest(chest,id,action,response.item)
    return true,response,audited and (action == 'discard' and 'Item descartado e registrado.' or 'Item guardado e registrado.')
        or 'Item movimentado, mas o log de auditoria falhou. Avise a administracao.'
end)

OR.Callback.register('chestTake', function(source, chestId, ownedSlot, amount, targetSlot)
    if not OR.Security.rateLimit(source, 'org:chest_take', 20, 10000) then return false, 'Aguarde um instante.' end
    local chest, err, id = chestAccess(source, chestId)
    if not chest then return false, err end
    if chest.chest_type ~= 'storage' then return false, 'Nao e possivel retirar itens do descarte.' end
    local ok, response = exports.ob_inventory:TransferFromOwned(
        source,'org_chest',tostring(chest.id),chest.slots,chest.max_weight,ownedSlot,amount,targetSlot
    )
    if not ok then return false, response end
    local audited = auditChest(chest,id,'withdraw',response.item)
    return true,response,audited and 'Item retirado e registrado.'
        or 'Item retirado, mas o log de auditoria falhou. Avise a administracao.'
end)

OR.Callback.register('chestMove', function(source, chestId, fromSlot, toSlot)
    if not OR.Security.rateLimit(source, 'org:chest_move', 30, 10000) then return false, 'Aguarde um instante.' end
    local chest, err = chestAccess(source, chestId)
    if not chest then return false, err end
    if chest.chest_type ~= 'storage' then return false, 'O descarte nao armazena itens.' end
    local ok, response = exports.ob_inventory:MoveOwnedItem(
        'org_chest',tostring(chest.id),chest.slots,chest.max_weight,fromSlot,toSlot
    )
    if not ok then return false, response end
    return true,{ owned=response }
end)

OR.Callback.register('world', function(source)
    if not ready then return {duties={},routes={},chests={}} end
    local member=userId(source) and membership(userId(source)) or nil
    local duties={}
    if member and flag(member.active) and member.org_type=='legal' and not flag(member.auto_duty) then
        local coords=decode(member.duty_coords,nil);if coords then duties[1]={orgId=member.org_id,label=member.label,coords=coords,onDuty=flag(member.on_duty)} end
    end
    local routes={}
    for _,row in ipairs(OR.Database.query.await([[SELECT r.id,r.name,r.npc_model,r.npc_coords,o.label AS org_label
        FROM ob_org_routes r JOIN ob_orgs o ON o.id=r.org_id
        WHERE r.enabled=1 AND o.active=1 AND r.npc_coords IS NOT NULL]]) or {}) do
        local coords=decode(row.npc_coords,nil);if coords then routes[#routes+1]={id=row.id,name=row.name,model=row.npc_model,coords=coords,orgLabel=row.org_label} end
    end
    local chests={}
    if member and flag(member.active) then
        for _,row in ipairs(OR.Database.query.await([[SELECT c.id,c.label,c.chest_type,c.coords
            FROM ob_org_chests c JOIN ob_orgs o ON o.id=c.org_id
            WHERE c.org_id=? AND c.enabled=1 AND o.active=1 ORDER BY c.id]],{member.org_id}) or {}) do
            local coords=decode(row.coords,nil)
            if coords then chests[#chests+1]={id=row.id,label=row.label,mode=row.chest_type,coords=coords} end
        end
    end
    return {duties=duties,routes=routes,chests=chests}
end)

OR.Callback.register('toggleDuty', function(source, orgId)
    source = tonumber(source)
    local now = GetGameTimer()
    local previousToggle = source and dutyToggleAt[source] or nil
    if previousToggle and now >= previousToggle and now - previousToggle < 1500 then
        return false, 'Aguarde um instante para bater o ponto novamente.'
    end
    if source then dutyToggleAt[source] = now end

    local actor,err=actorContext(source,orgId);if not actor then return false,err end
    local member=actor.member;if not member or member.org_type~='legal' or flag(member.auto_duty) then return false,'Ponto manual indisponivel.' end
    local coords=decode(member.duty_coords,nil);local ped=GetPlayerPed(source)
    if not coords or not ped or ped<=0 then return false,'Local de ponto indisponivel.' end
    local here=GetEntityCoords(ped);local dx,dy,dz=here.x-coords.x,here.y-coords.y,here.z-coords.z
    if dx*dx+dy*dy+dz*dz>9.0 then return false,'Aproxime-se do ponto.' end
    local enabled=not flag(member.on_duty)
    local changed,updateError=OR.Database.update.await('UPDATE ob_org_members SET on_duty=? WHERE user_id=? AND org_id=?',{enabled and 1 or 0,actor.userId,actor.orgId})
    if changed==nil then
        return false,updateError or 'Nao foi possivel salvar o ponto.'
    end
    if tonumber(changed)<1 then
        return false,'O vinculo deste personagem nao foi atualizado.'
    end

    local updated=membership(actor.userId)
    if not updated or flag(updated.on_duty)~=enabled then
        print(('[ob_org] Falha ao confirmar ponto user_id=%s org_id=%s esperado=%s'):format(actor.userId,actor.orgId,tostring(enabled)))
        return false,'O banco nao confirmou a alteracao do ponto.'
    end

    publishMembership(source,updated)
    TriggerClientEvent('ob_org:client:refreshWorld',source)
    print(('[ob_org] PONTO user_id=%s org=%s on_duty=%s'):format(actor.userId,updated.org_key,tostring(enabled)))
    return true,enabled and 'Ponto iniciado.' or 'Ponto encerrado.',enabled
end)

OR.Callback.register('startRoute', function(source, routeId)
    local id=userId(source);local member=id and membership(id) or nil
    if not member or not flag(member.active) or member.org_type~='illegal' then return false,'Voce nao pertence a uma organizacao ilegal ativa.' end
    local route=OR.Database.single.await('SELECT * FROM ob_org_routes WHERE id=? AND org_id=? AND enabled=1',{routeId,member.org_id})
    if not route then return false,'Essa rota nao pertence a sua organizacao.' end
    local npc=decode(route.npc_coords,nil);local ped=GetPlayerPed(source)
    if not npc or not ped or ped<=0 then return false,'NPC da rota indisponivel.' end
    local here=GetEntityCoords(ped);local dx,dy,dz=here.x-npc.x,here.y-npc.y,here.z-npc.z
    if dx*dx+dy*dy+dz*dz>16.0 then return false,'Aproxime-se do NPC da rota.' end
    local points=OR.Database.query.await('SELECT id,position,x,y,z FROM ob_org_route_points WHERE route_id=? ORDER BY position,id',{route.id}) or {}
    if #points==0 then return false,'Essa rota ainda nao possui pontos.' end
    routeSessions[source]={routeId=route.id,orgId=member.org_id,userId=id,index=1,lastCollect=0,availableAt=GetGameTimer()+integer(route.collect_duration,500,30000,3000)}
    return true,'Rota iniciada.',{routeId=route.id,name=route.name,index=1,point=points[1],total=#points,collectDuration=route.collect_duration}
end)

OR.Callback.register('collectRoute', function(source, routeId, pointIndex)
    local session=routeSessions[source]
    if not session or session.routeId~=tonumber(routeId) or session.index~=tonumber(pointIndex) then return false,'Sessao de rota invalida.' end
    local currentUserId=userId(source);local member=currentUserId and membership(currentUserId) or nil
    if not member or currentUserId~=session.userId or tonumber(member.org_id)~=tonumber(session.orgId) or not flag(member.active) then
        routeSessions[source]=nil
        return false,'Seu personagem nao pode mais continuar essa rota.'
    end
    local now=GetGameTimer();if now-session.lastCollect<1000 or now<(session.availableAt or 0) then return false,'A coleta ainda nao terminou.' end
    local points=OR.Database.query.await('SELECT id,position,x,y,z FROM ob_org_route_points WHERE route_id=? ORDER BY position,id',{session.routeId}) or {}
    local point=points[session.index];local ped=GetPlayerPed(source)
    if not point or not ped or ped<=0 then return false,'Ponto invalido.' end
    local here=GetEntityCoords(ped);local dx,dy,dz=here.x-point.x,here.y-point.y,here.z-point.z
    if dx*dx+dy*dy+dz*dz>16.0 then return false,'Voce esta longe do ponto.' end
    session.lastCollect=now
    local route=OR.Database.single.await('SELECT max_rewards,collect_duration FROM ob_org_routes WHERE id=?',{session.routeId})
    local rewards=OR.Database.query.await('SELECT * FROM ob_org_route_rewards WHERE route_id=?',{session.routeId}) or {}
    local granted={};local maximum=math.min(#rewards,integer(route and route.max_rewards,1,20,1));local shuffled={table.unpack(rewards)}
    for index=#shuffled,2,-1 do local swap=math.random(index);shuffled[index],shuffled[swap]=shuffled[swap],shuffled[index] end
    for index=1,maximum do
        local reward=shuffled[index]
        if reward and math.random()*100<=tonumber(reward.chance) then
            local amount=math.random(tonumber(reward.min_amount),tonumber(reward.max_amount))
            local added=exports.ob_inventory:AddItem(source,reward.item_name,amount)
            if added then granted[#granted+1]=('%sx %s'):format(amount,reward.item_name) end
        end
    end
    session.index=session.index+1;session.availableAt=now+integer(route and route.collect_duration,500,30000,3000);local completed=false
    if session.index>#points then
        session.index=1;completed=true
        OR.Database.insert.await('INSERT INTO ob_org_route_log (org_id,route_id,user_id) VALUES (?,?,?)',{session.orgId,session.routeId,session.userId})
        for _,goal in ipairs(OR.Database.query.await('SELECT id FROM ob_org_goals WHERE org_id=? AND active=1',{session.orgId}) or {}) do
            OR.Database.query.await([[INSERT INTO ob_org_goal_progress (goal_id,user_id,period_key,progress) VALUES (?,?,CURRENT_DATE(),1)
                ON DUPLICATE KEY UPDATE progress=progress+1]],{goal.id,session.userId})
        end
    end
    return true,#granted>0 and table.concat(granted,', ') or 'Nenhum item encontrado.',{routeId=session.routeId,index=session.index,point=points[session.index],total=#points,completed=completed,collectDuration=route and route.collect_duration}
end)

RegisterNetEvent('ob_org:server:cancelRoute',function() routeSessions[source]=nil end)

local function dutyBlipAllowed(viewerKey, targetKey)
    local setting = dutyBlipSettings[targetKey]
    if not setting or setting.enabled ~= true then return false end
    for _, allowedViewer in ipairs(setting.visibleTo or {}) do
        if allowedViewer == viewerKey then return true end
    end
    return false
end

local function dutyBlipSnapshot()
    local entries = {}
    for _, value in ipairs(GetPlayers()) do
        local playerSource = tonumber(value)
        local player = playerSource and Player(playerSource) or nil
        local organisation = player and player.state['ob:org'] or nil
        local session = playerSource and dutySessions[playerSource] or nil
        if type(organisation) == 'table' and organisation.type == 'legal'
            and organisation.onDuty == true and session and session.onDuty == true
            and session.orgId == tonumber(organisation.id) then
            local ped = GetPlayerPed(playerSource)
            if ped and ped > 0 then
                local coords = GetEntityCoords(ped)
                entries[playerSource] = {
                    source = playerSource,
                    orgKey = organisation.key,
                    orgLabel = organisation.label,
                    coords = { x = coords.x, y = coords.y, z = coords.z },
                    heading = GetEntityHeading(ped),
                    blip = dutyBlipSettings[organisation.key],
                }
            end
        end
    end
    return entries
end

CreateThread(function()
    while true do
        local config = OBOrgConfig.DutyBlips or {}
        Wait(math.max(750, tonumber(config.updateInterval) or 1500))
        if ready and config.enabled == true then
            local entries = dutyBlipSnapshot()
            for _, value in ipairs(GetPlayers()) do
                local viewerSource = tonumber(value)
                local viewer = entries[viewerSource]
                local visible = {}
                if viewer then
                    for targetSource, target in pairs(entries) do
                        if (config.showSelf == true or targetSource ~= viewerSource)
                            and dutyBlipAllowed(viewer.orgKey, target.orgKey) then
                            visible[#visible + 1] = target
                        end
                    end
                end
                TriggerClientEvent('ob_org:client:updateDutyBlips', viewerSource, visible)
            end
        end
    end
end)

AddEventHandler('playerDropped',function() routeSessions[source]=nil;dutyToggleAt[source]=nil;dutySessions[source]=nil end)
AddEventHandler('ob_core:server:characterSelected',function(source) routeSessions[source]=nil;dutySessions[source]=nil end)
AddEventHandler('ob_core:server:playerLoaded',function(source) syncMember(source, true) end)
AddEventHandler('onResourceStart',function(resource)
    if resource=='ob_core' and ready then
        for _,org in ipairs(OR.Database.query.await("SELECT org_key,label,org_type FROM ob_orgs WHERE active=1 AND org_type='legal'") or {}) do registerLegalJob(org) end
        for _,source in ipairs(GetPlayers()) do syncMember(tonumber(source), true) end
    end
end)

CreateThread(function()
    while true do
        Wait(math.max(1,tonumber(OBOrgConfig.PayrollIntervalMinutes) or 30)*60000)
        if ready then
            for _,source in ipairs(GetPlayers()) do
                source=tonumber(source);local member=userId(source) and membership(userId(source)) or nil
                if memberOnDuty(source, member) then
                    local salary=integer(member.salary,0,OBOrgConfig.Limits.maxSalary,0)
                    if salary>0 then
                        local paid, payError = false, 'Banco indisponivel.'
                        local economyResult = OR.Economy.PayPlayer(source, salary, 'salary',
                            ('Salario - %s'):format(member.label), {
                                organisation = member.org_key,
                                rank = member.rank_key,
                            }, 'city_treasury')
                        if economyResult.handled == true then
                            paid, payError = economyResult.success == true, economyResult.error
                        elseif GetResourceState('ob_bank') == 'started' then
                            local exportOk, result, exportError = pcall(function()
                                return exports.ob_bank:CreditSalary(source, salary, ('Salario - %s'):format(member.label))
                            end)
                            paid, payError = exportOk and result == true, exportOk and exportError or result
                        end
                        if paid then
                            notify(source,('Salario depositado no banco: %s.'):format(OR.FormatMoney(salary)),'success')
                        else
                            print(('[ob_org] Falha ao pagar salario bancario do personagem %s: %s'):format(member.user_id, payError or 'desconhecida'))
                        end
                    end
                end
            end
        end
    end
end)

local publicEmploymentLocks = {}

local function allowedEmploymentKeys(value)
    local allowed = {}
    if type(value) ~= 'table' then return allowed end
    for _, orgKey in ipairs(value) do
        orgKey = key(orgKey)
        if orgKey then allowed[orgKey] = true end
    end
    return allowed
end

local function publicEmploymentStatus(source, allowedKeys, minimumSeconds)
    if not ready then return nil, 'Sistema de organizacoes indisponivel.' end
    local id = userId(source)
    if not id then return nil, 'Personagem ainda nao esta carregado.' end

    local allowed = allowedEmploymentKeys(allowedKeys)
    local member = membership(id)
    local blocked = OR.Database.single.await([[SELECT previous_org_id,reason,expires_at,
        GREATEST(0,TIMESTAMPDIFF(SECOND,NOW(),expires_at)) AS remaining_seconds
        FROM ob_org_blacklist WHERE user_id=? AND expires_at>NOW() LIMIT 1]], { id })
    OR.Database.update.await('DELETE FROM ob_org_blacklist WHERE user_id=? AND expires_at<=NOW()', { id })

    local jobs = {}
    for _, org in ipairs(OR.Database.query.await([[SELECT o.id,o.org_key,o.label,o.max_members,
        COUNT(m.user_id) AS member_count FROM ob_orgs o
        LEFT JOIN ob_org_members m ON m.org_id=o.id
        WHERE o.org_type='legal' AND o.active=1 GROUP BY o.id ORDER BY o.label]]) or {}) do
        if allowed[org.org_key] then
            local rank = OR.Database.single.await([[SELECT r.id,r.label,r.level,r.member_limit,
                (SELECT COUNT(*) FROM ob_org_members rm WHERE rm.rank_id=r.id) AS member_count
                FROM ob_org_ranks r WHERE r.org_id=? ORDER BY r.level DESC,r.id DESC LIMIT 1]], { org.id })
            local orgFull = tonumber(org.member_count) >= tonumber(org.max_members)
            local rankFull = rank and tonumber(rank.member_limit) > 0
                and tonumber(rank.member_count) >= tonumber(rank.member_limit)
            jobs[#jobs + 1] = {
                key = org.org_key,
                label = org.label,
                rankLabel = rank and rank.label or 'Sem cargo inicial',
                available = rank ~= nil and not orgFull and not rankFull,
                unavailableReason = not rank and 'Organizacao sem cargo configurado.'
                    or orgFull and 'Limite de membros atingido.'
                    or rankFull and 'Limite do cargo inicial atingido.' or nil,
            }
        end
    end

    local current
    if member then
        local elapsed = tonumber(OR.Database.scalar.await(
            'SELECT GREATEST(0,TIMESTAMPDIFF(SECOND,joined_at,NOW())) FROM ob_org_members WHERE user_id=?', { id }
        )) or 0
        local required = integer(minimumSeconds, 0, 2592000, 86400)
        current = {
            key = member.org_key,
            label = member.label,
            type = member.org_type,
            rankLabel = member.rank_label,
            joinedAt = member.joined_at,
            canLeaveHere = member.org_type == 'legal' and allowed[member.org_key] == true,
            remainingSeconds = math.max(0, required - elapsed),
        }
    end

    return {
        jobs = jobs,
        current = current,
        blacklist = blocked and {
            reason = blocked.reason,
            expiresAt = blocked.expires_at,
            remainingSeconds = tonumber(blocked.remaining_seconds) or 0,
        } or nil,
    }
end

local function joinPublicEmployment(source, requestedKey, allowedKeys)
    if not ready then return false, 'Sistema de organizacoes indisponivel.' end
    local id = userId(source)
    local orgKey = key(requestedKey)
    local allowed = allowedEmploymentKeys(allowedKeys)
    if not id then return false, 'Personagem ainda nao esta carregado.' end
    if not orgKey or not allowed[orgKey] then return false, 'Emprego nao autorizado nesta central.' end
    if publicEmploymentLocks[id] then return false, 'Aguarde a operacao anterior.' end
    publicEmploymentLocks[id] = true

    local ok, success, message = pcall(function()
        if membership(id) then return false, 'Saia do seu trabalho atual antes de escolher outro.' end
        local blocked = OR.Database.single.await([[SELECT expires_at FROM ob_org_blacklist
            WHERE user_id=? AND expires_at>NOW() LIMIT 1]], { id })
        if blocked then return false, ('Voce esta bloqueado para novas organizacoes ate %s.'):format(tostring(blocked.expires_at)) end
        OR.Database.update.await('DELETE FROM ob_org_blacklist WHERE user_id=? AND expires_at<=NOW()', { id })

        local org = OR.Database.single.await([[SELECT id,org_key,label,max_members FROM ob_orgs
            WHERE org_key=? AND org_type='legal' AND active=1 LIMIT 1]], { orgKey })
        if not org then return false, 'Esse trabalho legal nao esta disponivel.' end
        local count = tonumber(OR.Database.scalar.await('SELECT COUNT(*) FROM ob_org_members WHERE org_id=?', { org.id })) or 0
        if count >= tonumber(org.max_members) then return false, 'Limite de membros dessa organizacao atingido.' end

        local rank = OR.Database.single.await([[SELECT r.*,
            (SELECT COUNT(*) FROM ob_org_members m WHERE m.rank_id=r.id) AS assigned
            FROM ob_org_ranks r WHERE r.org_id=? ORDER BY r.level DESC,r.id DESC LIMIT 1]], { org.id })
        if not rank then return false, 'A organizacao ainda nao possui cargo inicial.' end
        if tonumber(rank.member_limit) > 0 and tonumber(rank.assigned) >= tonumber(rank.member_limit) then
            return false, 'Limite do cargo inicial atingido.'
        end

        local inserted, insertError = OR.Database.insert.await(
            'INSERT INTO ob_org_members (org_id,user_id,rank_id,on_duty) VALUES (?,?,?,0)',
            { org.id, id, rank.id }
        )
        if not inserted then return false, insertError or 'Nao foi possivel registrar a contratacao.' end
        local synced, syncError = pcall(syncMember, source)
        if not synced then
            print(('[ob_org] Contratacao salva, mas a sincronizacao imediata falhou user_id=%s: %s'):format(id, tostring(syncError)))
        end
        print(('[ob_org] EMPREGO_PUBLICO_ENTRADA user_id=%s org=%s rank=%s'):format(id, org.org_key, rank.rank_key))
        return true, ('Voce entrou em %s como %s.'):format(org.label, rank.label)
    end)

    publicEmploymentLocks[id] = nil
    if not ok then
        print(('[ob_org] Falha na entrada publica user_id=%s: %s'):format(id, tostring(success)))
        return false, 'Nao foi possivel concluir a contratacao.'
    end
    return success, message
end

local function leavePublicEmployment(source, allowedKeys, minimumSeconds, blacklistSeconds)
    if not ready then return false, 'Sistema de organizacoes indisponivel.' end
    local id = userId(source)
    local allowed = allowedEmploymentKeys(allowedKeys)
    if not id then return false, 'Personagem ainda nao esta carregado.' end
    if publicEmploymentLocks[id] then return false, 'Aguarde a operacao anterior.' end
    publicEmploymentLocks[id] = true

    local ok, success, message = pcall(function()
        local member = membership(id)
        if not member then return false, 'Voce nao possui um trabalho vinculado ao ob_org.' end
        if member.org_type ~= 'legal' or not allowed[member.org_key] then
            return false, 'Esse vinculo nao pode ser encerrado nesta central.'
        end

        local required = integer(minimumSeconds, 0, 2592000, 86400)
        local elapsed = tonumber(OR.Database.scalar.await(
            'SELECT GREATEST(0,TIMESTAMPDIFF(SECOND,joined_at,NOW())) FROM ob_org_members WHERE user_id=?', { id }
        )) or 0
        if elapsed < required then
            local remaining = required - elapsed
            return false, ('Voce precisa permanecer mais %s hora(s) antes de sair.'):format(math.max(1, math.ceil(remaining / 3600)))
        end

        local removed, removeError = OR.Database.update.await('DELETE FROM ob_org_members WHERE user_id=? AND org_id=?', { id, member.org_id })
        if removed == nil then return false, removeError or 'Nao foi possivel encerrar o vinculo.' end
        if tonumber(removed) == 0 then return false, 'O vinculo foi alterado. Abra a central novamente.' end
        local blockFor = integer(blacklistSeconds, 0, 604800, 3600)
        local expiry = os.time() + blockFor
        local saved, blacklistError = OR.Database.query.await([[INSERT INTO ob_org_blacklist
            (user_id,previous_org_id,reason,expires_at) VALUES (?,?,?,FROM_UNIXTIME(?))
            ON DUPLICATE KEY UPDATE previous_org_id=VALUES(previous_org_id),reason=VALUES(reason),expires_at=VALUES(expires_at)]],
            { id, member.org_id, 'Saida voluntaria pela Central de Empregos', expiry })
        if saved == nil then
            local restored, restoreError = OR.Database.insert.await('INSERT INTO ob_org_members (org_id,user_id,rank_id,on_duty,joined_at) VALUES (?,?,?,?,?)',
                { member.org_id, id, member.rank_id, member.on_duty, member.joined_at })
            if not restored then
                print(('[ob_org] Falha critica ao restaurar vinculo user_id=%s: %s'):format(id, tostring(restoreError)))
            end
            return false, blacklistError or 'Nao foi possivel registrar o bloqueio. A saida foi cancelada.'
        end
        local synced, syncError = pcall(function()
            publishMembership(source, nil)
            TriggerClientEvent('ob_org:client:refreshWorld', source)
        end)
        if not synced then
            print(('[ob_org] Saida salva, mas a sincronizacao imediata falhou user_id=%s: %s'):format(id, tostring(syncError)))
        end
        print(('[ob_org] EMPREGO_PUBLICO_SAIDA user_id=%s org=%s blacklist=%ss'):format(id, member.org_key, blockFor))
        return true, ('Voce saiu de %s. Aguarde %s minuto(s) para escolher outro trabalho.'):format(
            member.label, math.max(1, math.ceil(blockFor / 60)))
    end)

    publicEmploymentLocks[id] = nil
    if not ok then
        print(('[ob_org] Falha na saida publica user_id=%s: %s'):format(id, tostring(success)))
        return false, 'Nao foi possivel concluir a saida.'
    end
    return success, message
end

exports('GetMembership',function(id) return membership(tonumber(id)) end)
exports('IsMember',function(source,orgKey) local member=userId(source) and membership(userId(source));return member and (not orgKey or member.org_key==orgKey) or false end)
exports('GetPublicEmploymentStatus', publicEmploymentStatus)
exports('JoinPublicEmployment', joinPublicEmployment)
exports('LeavePublicEmployment', leavePublicEmployment)
exports('HasPermission',function(source,permission,requireDuty)
    source=tonumber(source);permission=type(permission)=='string' and permission:lower() or ''
    local id=source and userId(source);local member=id and membership(id) or nil
    if not member or not flag(member.active) or permission=='' then return false end
    local rankPermissions=decode(member.permissions,{})
    -- A chave interna da organizacao tambem e sua permissao base. Assim,
    -- permission='police' autoriza qualquer membro da org police, enquanto
    -- permissions.access continua permitindo aliases/permissoes adicionais.
    local allowed=type(member.org_key)=='string' and member.org_key:lower()==permission
    for _,entry in ipairs(type(rankPermissions.access)=='table' and rankPermissions.access or {}) do
        if type(entry)=='string' and entry:lower()==permission then allowed=true;break end
    end
    if not allowed then return false end
    if requireDuty==true then
        return memberOnDuty(source, member)
    end
    return true
end)
