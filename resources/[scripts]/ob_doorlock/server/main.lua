local groups, doors = {}, {}
local ready = false
local stateVersions = {}
local stateLocks = {}
local groupTable = 'ob_doorlock_groups'
local doorTable = 'ob_doorlock_doors'

local function clean(value, maximum)
    value = tostring(value or ''):gsub('[\r\n%z]', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''
    return value:sub(1, maximum or 100)
end

local function whole(value, low, high, fallback)
    local number = math.floor(tonumber(value) or tonumber(fallback) or 0)
    return math.max(low or 0, math.min(high or 2147483647, number))
end

local function decimal(value, low, high, fallback)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then number = fallback end
    return math.max(low, math.min(high, tonumber(number) or low))
end

local function count(map)
    local total = 0
    for _ in pairs(map) do total = total + 1 end
    return total
end

local function sorted(map)
    local rows = {}
    for _, row in pairs(map) do rows[#rows + 1] = row end
    table.sort(rows, function(a, b)
        local al, bl = tostring(a.label):lower(), tostring(b.label):lower()
        return al == bl and a.id < b.id or al < bl
    end)
    return rows
end

local function permissions(raw)
    local result, seen = {}, {}
    for _, permission in ipairs(type(raw) == 'table' and raw or {}) do
        permission = clean(permission, 64):lower()
        if permission ~= '' and permission:match('^[a-z0-9_%.:%-]+$') and not seen[permission] then
            seen[permission] = true
            result[#result + 1] = permission
            if #result >= (OBDoorlock.MaximumPermissionsPerGroup or 12) then break end
        end
    end
    table.sort(result)
    return result
end

local function point(raw)
    if type(raw) ~= 'table' then return nil end
    local x = decimal(raw.x, -10000.0, 10000.0)
    local y = decimal(raw.y, -10000.0, 10000.0)
    local z = decimal(raw.z, -1000.0, 3000.0)
    return { x=x, y=y, z=z, heading=decimal(raw.heading or raw.w, 0.0, 360.0, 0.0) }
end

local function normalizeGroup(raw, forcedId)
    if type(raw) ~= 'table' then return nil, 'Grupo invalido.' end
    local label = clean(raw.label, 80)
    if label == '' then return nil, 'Informe o nome do grupo.' end
    return {
        id = tonumber(forcedId or raw.id),
        label = label,
        permissions = permissions(raw.permissions),
        publicAccess = raw.publicAccess == true,
        requireDuty = raw.requireDuty == true,
        interactionDistance = decimal(raw.interactionDistance, 1.0,
            tonumber(OBDoorlock.MaximumInteractionDistance) or 8.0,
            tonumber(OBDoorlock.DefaultInteractionDistance) or 2.0),
        autoLockSeconds = whole(raw.autoLockSeconds, 0, 86400, 0),
        defaultLocked = raw.defaultLocked ~= false,
        enabled = raw.enabled ~= false,
    }
end

local function normalizeLeaves(raw)
    local result = {}
    for _, leaf in ipairs(type(raw) == 'table' and raw or {}) do
        local coords = point(leaf.coords)
        local model = tonumber(leaf.model)
        if coords and model and model ~= 0 then
            result[#result + 1] = {
                model = math.floor(model),
                name = clean(leaf.name, 80),
                coords = coords,
                center = point(leaf.center),
                offset = point(leaf.offset),
            }
            if #result == 2 then break end
        end
    end
    return result
end

local function normalizeDoor(raw, forcedId)
    if type(raw) ~= 'table' then return nil, 'Porta invalida.' end
    local label = clean(raw.label, 80)
    local groupId = tonumber(raw.groupId)
    local leaves = normalizeLeaves(raw.leaves)
    if label == '' then return nil, 'Informe o nome da porta.' end
    if not groupId or not groups[groupId] then return nil, 'Selecione um grupo existente.' end
    if #leaves < 1 then return nil, 'Capture pelo menos uma folha da porta.' end
    if raw.doorType == 'double' and #leaves ~= 2 then return nil, 'Capture as duas folhas da porta dupla.' end
    return {
        id = tonumber(forcedId or raw.id),
        groupId = groupId,
        label = label,
        doorType = #leaves == 2 and 'double' or 'single',
        leaves = leaves,
        locked = raw.locked ~= false,
        enabled = raw.enabled ~= false,
    }
end

local function decode(value, fallback)
    local ok, result = pcall(json.decode, value or '')
    return ok and type(result) == 'table' and result or fallback
end

local function groupFromRow(row)
    return normalizeGroup({
        label=row.label, permissions=decode(row.permissions, {}), publicAccess=tonumber(row.public_access)==1,
        requireDuty=tonumber(row.require_duty)==1, interactionDistance=row.interaction_distance,
        autoLockSeconds=row.auto_lock_seconds, defaultLocked=tonumber(row.default_locked)==1,
        enabled=tonumber(row.enabled)==1,
    }, row.id)
end

local function doorFromRow(row)
    return normalizeDoor({
        groupId=row.group_id, label=row.label, doorType=row.door_type, leaves=decode(row.leaves, {}),
        locked=tonumber(row.locked)==1, enabled=tonumber(row.enabled)==1,
    }, row.id)
end

local function payload()
    return { groups=sorted(groups), doors=sorted(doors) }
end

local function publish(target)
    TriggerLatentClientEvent('ob_doorlock:client:sync', target or -1, 100000, payload())
end

local function isAdmin(source)
    return GetResourceState('ob_admin') == 'started'
        and exports.ob_admin:HasPermission(source, OBDoorlock.AdminPermission or 'world.doors') == true
end

local function playerNearDoor(source, door, group)
    local ped = GetPlayerPed(source)
    if not ped or ped <= 0 then return false end
    local origin = GetEntityCoords(ped)
    local nearest = math.huge
    for _, leaf in ipairs(door.leaves) do
        local coords = leaf.coords
        nearest = math.min(nearest, #(origin - vector3(coords.x, coords.y, coords.z)))
    end
    local allowed = (tonumber(group.interactionDistance) or 2.0)
        + (tonumber(OBDoorlock.ServerDistanceTolerance) or 1.5)
    return nearest <= allowed
end

local function hasGroupAccess(source, group)
    if group.publicAccess == true then return true end
    if GetResourceState('ob_org') ~= 'started' then return false end
    for _, permission in ipairs(group.permissions or {}) do
        local ok, allowed = pcall(function()
            return exports.ob_org:HasPermission(source, permission, group.requireDuty == true)
        end)
        if ok and allowed == true then return true end
    end
    return false
end

local function applyState(door, locked, actor)
    locked = locked == true
    stateVersions[door.id] = (stateVersions[door.id] or 0) + 1
    local version = stateVersions[door.id]
    door.locked = locked
    local changed, err = OR.Database.update.await(('UPDATE %s SET locked=? WHERE id=?'):format(doorTable),
        { locked and 1 or 0, door.id })
    if changed == nil then return nil, err or 'Nao foi possivel salvar o estado da porta.' end
    TriggerClientEvent('ob_doorlock:client:state', -1, door.id, locked, actor)

    local group = groups[door.groupId]
    local delay = group and tonumber(group.autoLockSeconds) or 0
    if not locked and delay > 0 then
        SetTimeout(math.floor(delay * 1000), function()
            local current = doors[door.id]
            if current and current.enabled and current.locked == false and stateVersions[door.id] == version then
                applyState(current, true, nil)
            end
        end)
    end
    return true
end

OR.Callback.register('bootstrap', function()
    if not ready then return nil, 'Trancas carregando.' end
    return payload()
end)

OR.Callback.register('editorData', function(source)
    if not ready then return nil, 'Trancas carregando.' end
    if not isAdmin(source) then return nil, 'Sem permissao para editar portas.' end
    local data = payload()
    data.defaults = {
        interactionDistance=OBDoorlock.DefaultInteractionDistance,
        maximumInteractionDistance=OBDoorlock.MaximumInteractionDistance,
        maxPermissions=OBDoorlock.MaximumPermissionsPerGroup,
    }
    return data
end)

OR.Callback.register('editorSave', function(source, raw)
    if not ready then return nil, 'Trancas carregando.' end
    if not isAdmin(source) then return nil, 'Sem permissao para editar portas.' end
    raw = type(raw) == 'table' and raw or {}
    if raw.kind == 'group' then
        local existingId = tonumber(raw.id)
        local row, validationError = normalizeGroup(raw, existingId)
        if not row then return nil, validationError end
        if not existingId and count(groups) >= (OBDoorlock.MaximumGroups or 100) then return nil, 'Limite de grupos atingido.' end
        if existingId and not groups[existingId] then return nil, 'Grupo nao encontrado.' end
        local encoded = json.encode(row.permissions)
        if existingId then
            local changed, err = OR.Database.update.await(([[UPDATE %s SET label=?,permissions=?,public_access=?,require_duty=?,
                interaction_distance=?,auto_lock_seconds=?,default_locked=?,enabled=? WHERE id=?]]):format(groupTable),
                {row.label,encoded,row.publicAccess and 1 or 0,row.requireDuty and 1 or 0,row.interactionDistance,
                    row.autoLockSeconds,row.defaultLocked and 1 or 0,row.enabled and 1 or 0,existingId})
            if changed == nil then return nil, err or 'Nao foi possivel atualizar o grupo.' end
        else
            local id, err = OR.Database.insert.await(([[INSERT INTO %s
                (label,permissions,public_access,require_duty,interaction_distance,auto_lock_seconds,default_locked,enabled)
                VALUES (?,?,?,?,?,?,?,?)]]):format(groupTable),
                {row.label,encoded,row.publicAccess and 1 or 0,row.requireDuty and 1 or 0,row.interactionDistance,
                    row.autoLockSeconds,row.defaultLocked and 1 or 0,row.enabled and 1 or 0})
            if not id then return nil, err or 'Nao foi possivel criar o grupo.' end
            row.id = tonumber(id)
        end
        groups[row.id] = row
        publish()
        return row, 'Grupo salvo e aplicado a todas as portas vinculadas.'
    end

    local existingId = tonumber(raw.id)
    if not existingId and count(doors) >= (OBDoorlock.MaximumDoors or 1000) then return nil, 'Limite de portas atingido.' end
    if existingId and not doors[existingId] then return nil, 'Porta nao encontrada.' end
    if raw.locked == nil and groups[tonumber(raw.groupId)] then raw.locked = groups[tonumber(raw.groupId)].defaultLocked end
    local row, validationError = normalizeDoor(raw, existingId)
    if not row then return nil, validationError end
    local encoded = json.encode(row.leaves)
    if existingId then
        local changed, err = OR.Database.update.await(([[UPDATE %s SET group_id=?,label=?,door_type=?,leaves=?,locked=?,enabled=? WHERE id=?]]):format(doorTable),
            {row.groupId,row.label,row.doorType,encoded,row.locked and 1 or 0,row.enabled and 1 or 0,existingId})
        if changed == nil then return nil, err or 'Nao foi possivel atualizar a porta.' end
    else
        local id, err = OR.Database.insert.await(([[INSERT INTO %s (group_id,label,door_type,leaves,locked,enabled)
            VALUES (?,?,?,?,?,?)]]):format(doorTable),
            {row.groupId,row.label,row.doorType,encoded,row.locked and 1 or 0,row.enabled and 1 or 0})
        if not id then return nil, err or 'Nao foi possivel criar a porta.' end
        row.id = tonumber(id)
    end
    doors[row.id] = row
    stateVersions[row.id] = (stateVersions[row.id] or 0) + 1
    publish()
    return row, 'Porta salva e sincronizada.'
end, { rateLimit={limit=8,window=10000}, payload={maxNodes=3000,maxDepth=10} })

OR.Callback.register('editorDelete', function(source, raw)
    if not ready then return nil, 'Trancas carregando.' end
    if not isAdmin(source) then return nil, 'Sem permissao para editar portas.' end
    local id = tonumber(type(raw) == 'table' and raw.id or raw)
    local kind = type(raw) == 'table' and raw.kind or 'door'
    if kind == 'group' then
        if not groups[id] then return nil, 'Grupo nao encontrado.' end
        for _, door in pairs(doors) do
            if door.groupId == id then return nil, 'Este grupo ainda possui portas vinculadas.' end
        end
        local changed, err = OR.Database.update.await(('DELETE FROM %s WHERE id=?'):format(groupTable), {id})
        if not changed or changed < 1 then return nil, err or 'Grupo nao encontrado.' end
        groups[id] = nil
    else
        if not doors[id] then return nil, 'Porta nao encontrada.' end
        local changed, err = OR.Database.update.await(('DELETE FROM %s WHERE id=?'):format(doorTable), {id})
        if not changed or changed < 1 then return nil, err or 'Porta nao encontrada.' end
        doors[id] = nil
        stateVersions[id] = nil
    end
    publish()
    return true, kind == 'group' and 'Grupo removido.' or 'Porta removida.'
end, { rateLimit={limit=4,window=10000} })

RegisterNetEvent('ob_doorlock:server:toggle', function(rawId)
    local source = source
    local allowed = OR.Security.rateLimit(source, 'doorlock:toggle', 8, 5000)
    if not allowed or not ready then return end
    local door = doors[tonumber(rawId)]
    local group = door and groups[door.groupId]
    if not door or not group or not door.enabled or not group.enabled then return end
    if not playerNearDoor(source, door, group) then
        return TriggerClientEvent('ob_notification:client:notify', source, 'Aproxime-se da porta.', 'error', 3500)
    end
    if not hasGroupAccess(source, group) then
        return TriggerClientEvent('ob_notification:client:notify', source, 'Voce nao possui a chave desta porta.', 'error', 3500)
    end
    if stateLocks[door.id] then return end
    stateLocks[door.id] = true
    local saved, err = applyState(door, not door.locked, source)
    stateLocks[door.id] = nil
    if not saved then TriggerClientEvent('ob_notification:client:notify', source, err, 'error', 3500) end
end)

CreateThread(function()
    local statements = {
        ([[CREATE TABLE IF NOT EXISTS %s (
            id int unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,label varchar(80) NOT NULL,permissions longtext NOT NULL,
            public_access tinyint unsigned NOT NULL DEFAULT 0,require_duty tinyint unsigned NOT NULL DEFAULT 0,
            interaction_distance decimal(5,2) NOT NULL DEFAULT 2.00,auto_lock_seconds int unsigned NOT NULL DEFAULT 0,
            default_locked tinyint unsigned NOT NULL DEFAULT 1,enabled tinyint unsigned NOT NULL DEFAULT 1,
            created_at timestamp NOT NULL DEFAULT current_timestamp(),updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]):format(groupTable),
        ([[CREATE TABLE IF NOT EXISTS %s (
            id int unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,group_id int unsigned NOT NULL,label varchar(80) NOT NULL,
            door_type enum('single','double') NOT NULL DEFAULT 'single',leaves longtext NOT NULL,
            locked tinyint unsigned NOT NULL DEFAULT 1,enabled tinyint unsigned NOT NULL DEFAULT 1,
            created_at timestamp NOT NULL DEFAULT current_timestamp(),updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
            KEY idx_ob_doorlock_group(group_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]):format(doorTable),
    }
    while not ready do
        if not OR.Database.waitForReady(30000) then
            print(('[ob_doorlock] Banco indisponivel; nova tentativa em %sms.'):format(OBDoorlock.DatabaseRetryMs or 5000))
            Wait(OBDoorlock.DatabaseRetryMs or 5000)
        else
            local preparationOk = true
            for _, statement in ipairs(statements) do
                local result, err = OR.Database.query.await(statement)
                if result == nil then
                    preparationOk = false
                    print('[ob_doorlock] Falha ao preparar tabelas: '..tostring(err))
                    break
                end
            end
            if preparationOk then
                local groupRows, groupError = OR.Database.query.await(('SELECT * FROM %s ORDER BY id'):format(groupTable))
                local doorRows, doorError = OR.Database.query.await(('SELECT * FROM %s ORDER BY id'):format(doorTable))
                if groupRows and doorRows then
                    local loadedGroups, loadedDoors = {}, {}
                    groups = loadedGroups
                    for _, raw in ipairs(groupRows) do
                        local row, err = groupFromRow(raw)
                        if row then loadedGroups[row.id] = row else print(('[ob_doorlock] Grupo %s ignorado: %s'):format(raw.id,tostring(err))) end
                    end
                    groups = loadedGroups
                    for _, raw in ipairs(doorRows) do
                        local row, err = doorFromRow(raw)
                        if row then loadedDoors[row.id] = row else print(('[ob_doorlock] Porta %s ignorada: %s'):format(raw.id,tostring(err))) end
                    end
                    doors = loadedDoors
                    ready = true
                else
                    print('[ob_doorlock] Falha ao carregar cadastros: '..tostring(groupError or doorError))
                end
            end
            if not ready then Wait(OBDoorlock.DatabaseRetryMs or 5000) end
        end
    end
    publish()
    print(('[ob_doorlock] %s grupo(s) e %s porta(s) carregados.'):format(count(groups),count(doors)))
end)
