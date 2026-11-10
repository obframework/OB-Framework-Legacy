local ready = false

CreateThread(function()
    if not OR.Database.waitForReady(30000) then return end
    ready = OR.Database.query.await([[CREATE TABLE IF NOT EXISTS ob_character_outfits (
        user_id bigint unsigned NOT NULL, slot tinyint unsigned NOT NULL, label varchar(32) NOT NULL,
        appearance mediumtext NOT NULL, updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
        PRIMARY KEY (user_id, slot)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]) ~= nil
end)

local function userId(source)
    source = tonumber(source)
    if not source or source <= 0 then return nil end
    local ok, id = pcall(function()
        return exports.ob_core:GetUserId(source)
    end)
    return ok and tonumber(id) or nil
end

local function restricted(source)
    local state = Player(source).state
    local policeRestrained = false
    if GetResourceState('ob_police') == 'started' then
        local ok, value = pcall(function() return exports.ob_police:IsRestrained(source) end)
        policeRestrained = ok and value == true
    end
    return state['or:downed'] == true or state['or:restrained'] == true
        or state['ob:restrained'] == true or policeRestrained
end

local function validPair(source, target, netId)
    source, target, netId = tonumber(source), tonumber(target), tonumber(netId)
    if not source or source <= 0 or not target or target <= 0 or source == target then return nil end
    local actor, victim = GetPlayerPed(source), GetPlayerPed(target)
    local vehicle = netId and netId > 0 and NetworkGetEntityFromNetworkId(netId) or 0
    if not actor or actor <= 0 or not victim or victim <= 0 or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    if not restricted(target) or #(GetEntityCoords(actor) - GetEntityCoords(victim)) > 3.0 or #(GetEntityCoords(victim) - GetEntityCoords(vehicle)) > 7.0 then return nil end
    return vehicle
end

local function validPassengerSeat(vehicle, requestedSeat)
    local seat = math.floor(tonumber(requestedSeat) or -1)
    -- O total exato de assentos e validado novamente no cliente que recebera
    -- a tarefa (essa native existe apenas no client). Aqui o servidor bloqueia
    -- o motorista (-1), limita valores abusivos e confirma que o lugar esta
    -- desocupado na entidade OneSync.
    if seat < 0 or seat > 15 then return nil end
    if GetPedInVehicleSeat(vehicle, seat) ~= 0 then return nil end
    return seat
end

RegisterNetEvent('ob_radiumenu:server:putInVehicle', function(target, netId, seat)
    if not OR.Security.rateLimit(source, 'radial:put_vehicle', 3, 10000) then return end
    local vehicle = validPair(source, target, netId)
    if not vehicle then return end
    seat = validPassengerSeat(vehicle, seat)
    if seat == nil then return end
    if GetResourceState('ob_police') == 'started' then
        pcall(function() exports.ob_police:StopEscort(tonumber(target)) end)
    end
    TriggerClientEvent('ob_radiumenu:client:enterVehicle', tonumber(target), tonumber(netId), seat)
end)

RegisterNetEvent('ob_radiumenu:server:removeFromVehicle', function(target)
    local actorSource, targetSource = tonumber(source), tonumber(target)
    if not actorSource or actorSource <= 0 or not targetSource or targetSource <= 0 or actorSource == targetSource then return end
    if not OR.Security.rateLimit(actorSource, 'radial:remove_vehicle', 3, 10000) then return end
    local actor, victim = GetPlayerPed(actorSource), GetPlayerPed(targetSource)
    if not actor or actor <= 0 or not victim or victim <= 0 or not restricted(targetSource) then return end
    if #(GetEntityCoords(actor) - GetEntityCoords(victim)) > 3.0 then return end

    -- O servidor resolve o veiculo real do alvo em vez de confiar no NetID
    -- enviado pelo cliente, que pode ficar desatualizado no OneSync.
    local vehicle = GetVehiclePedIsIn(victim, false)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    TriggerClientEvent('ob_radiumenu:client:leaveVehicle', targetSource, NetworkGetNetworkIdFromEntity(vehicle))
end)

OR.Callback.register('outfits', function(source)
    local id = userId(source)
    if not ready or not id then return {} end
    return OR.Database.query.await('SELECT slot, label FROM ob_character_outfits WHERE user_id = ? ORDER BY slot', { id }) or {}
end)

OR.Callback.register('saveOutfit', function(source, slot, label, appearance)
    local id = userId(source); slot = math.max(1, math.min(5, math.floor(tonumber(slot) or 1)))
    if not ready or not id or type(appearance) ~= 'table' then return false end
    if GetResourceState('ob_creator') == 'started' then
        local ok, normalized = pcall(function()
            return exports.ob_creator:NormalizeAppearance(appearance)
        end)
        if not ok or type(normalized) ~= 'table' then return false end
        appearance = normalized
    end
    label = tostring(label or ('Roupa %d'):format(slot)):sub(1, 32)
    local encoded = json.encode(appearance)
    if type(encoded) ~= 'string' or encoded == '' or #encoded > 150000 then return false end
    local result = OR.Database.query.await([[INSERT INTO ob_character_outfits (user_id, slot, label, appearance) VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE label=VALUES(label), appearance=VALUES(appearance), updated_at=current_timestamp()]], {
        id, slot, label, encoded
    })
    if result == nil then return false end
    return OR.Database.scalar.await('SELECT 1 FROM ob_character_outfits WHERE user_id = ? AND slot = ? LIMIT 1', { id, slot }) ~= nil
end)

OR.Callback.register('loadOutfit', function(source, slot)
    local id = userId(source); slot = math.max(1, math.min(5, math.floor(tonumber(slot) or 1)))
    if not ready or not id then return nil end
    local raw = OR.Database.scalar.await('SELECT appearance FROM ob_character_outfits WHERE user_id = ? AND slot = ?', { id, slot })
    local ok, appearance = raw and pcall(json.decode, raw)
    return ok and appearance or nil
end)
