local schemaReady = false

local function canEdit(source)
    return exports.ob_admin:HasPermission(source, 'panel.open')
end

local function fetchBlips()
    if not schemaReady then return {} end
    return OR.Database.query.await('SELECT id, label, sprite, color, scale, x, y, z, short_range FROM ob_world_blips ORDER BY id ASC') or {}
end

CreateThread(function()
    if not OR.Database.waitForReady(30000) then
        print('[ob_editor] Banco indisponivel; editor de blips desativado.')
        return
    end
    local result, err = OR.Database.query.await([[CREATE TABLE IF NOT EXISTS ob_world_blips (
        id int unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,
        label varchar(80) NOT NULL,
        sprite smallint unsigned NOT NULL DEFAULT 1,
        color smallint unsigned NOT NULL DEFAULT 3,
        scale decimal(4,2) NOT NULL DEFAULT 0.80,
        x decimal(12,4) NOT NULL, y decimal(12,4) NOT NULL, z decimal(12,4) NOT NULL,
        short_range tinyint(1) NOT NULL DEFAULT 1,
        created_at timestamp NOT NULL DEFAULT current_timestamp()
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    if not result then print(('[ob_editor] Falha ao criar tabela de blips: %s'):format(tostring(err))); return end
    schemaReady = true
    TriggerClientEvent('ob_editor:client:syncBlips', -1, fetchBlips())
end)

OR.Callback.register('getAccess', function(source)
    return canEdit(source) and { allowed = true, blips = fetchBlips() } or nil, 'Sem permissao administrativa.'
end)

RegisterNetEvent('ob_editor:server:requestBlips', function()
    TriggerClientEvent('ob_editor:client:syncBlips', source, fetchBlips())
end)

local function cleanLabel(value)
    local label = tostring(value or ''):gsub('^%s*(.-)%s*$', '%1')
    return label:sub(1, 80)
end

RegisterNetEvent('ob_editor:server:saveBlip', function(data)
    local source = source
    if not canEdit(source) or not schemaReady or type(data) ~= 'table' then return end
    local label = cleanLabel(data.label)
    if label == '' then return TriggerClientEvent('ob_editor:client:notify', source, 'Informe o nome do blip.', 'error') end
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return end
    local coords = GetEntityCoords(ped)
    local sprite = math.max(1, math.min(900, math.floor(tonumber(data.sprite) or 1)))
    local color = math.max(0, math.min(85, math.floor(tonumber(data.color) or 3)))
    local scale = math.max(0.4, math.min(2.0, tonumber(data.scale) or 0.8))
    local shortRange = data.shortRange ~= false and 1 or 0
    local id = tonumber(data.id)
    if id then
        OR.Database.update.await('UPDATE ob_world_blips SET label=?, sprite=?, color=?, scale=?, x=?, y=?, z=?, short_range=? WHERE id=?', { label, sprite, color, scale, coords.x, coords.y, coords.z, shortRange, id })
    else
        OR.Database.update.await('INSERT INTO ob_world_blips (label, sprite, color, scale, x, y, z, short_range) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', { label, sprite, color, scale, coords.x, coords.y, coords.z, shortRange })
    end
    local blips = fetchBlips()
    TriggerClientEvent('ob_editor:client:syncBlips', -1, blips)
    TriggerClientEvent('ob_editor:client:editorData', source, blips)
end)

RegisterNetEvent('ob_editor:server:deleteBlip', function(id)
    local source = source
    if not canEdit(source) or not schemaReady then return end
    id = tonumber(id)
    if not id then return end
    OR.Database.update.await('DELETE FROM ob_world_blips WHERE id=?', { id })
    local blips = fetchBlips()
    TriggerClientEvent('ob_editor:client:syncBlips', -1, blips)
    TriggerClientEvent('ob_editor:client:editorData', source, blips)
end)
