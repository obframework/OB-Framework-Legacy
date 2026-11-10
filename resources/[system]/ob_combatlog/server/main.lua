local function readableReason(reason)
    local text = tostring(reason or '')
    local lower = text:lower()
    if lower:find('timed out', 1, true) or lower:find('timeout', 1, true) then return 'Conexao com o servidor expirou.' end
    if lower:find('crash', 1, true) then return 'O jogo fechou inesperadamente.' end
    if lower:find('kicked', 1, true) then return 'Foi removido pelo servidor.' end
    if lower:find('exiting', 1, true) or lower:find('disconnect', 1, true) then return 'Saiu da cidade.' end
    return text ~= '' and text:sub(1, 120) or 'Motivo nao informado.'
end

local positions = {}
local activeMarkers = {}
local nextMarkerId = 0

local function characterIdentity(playerSource)
    local player = exports.ob_core:GetPlayerData(playerSource)
    local character = player and player.character
    local firstname = character and tostring(character.firstname or ''):gsub('^%s+', ''):gsub('%s+$', '') or ''
    local lastname = character and tostring(character.lastname or ''):gsub('^%s+', ''):gsub('%s+$', '') or ''
    local fullName = ('%s %s'):format(firstname, lastname):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return fullName ~= '' and fullName or nil, character and tonumber(character.userId) or nil
end

local function normalizeCoords(coords)
    if type(coords) ~= 'table' and type(coords) ~= 'vector3' then return nil end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z or x ~= x or y ~= y or z ~= z then return nil end
    if math.abs(x) > 20000 or math.abs(y) > 20000 or math.abs(z) > 5000 then return nil end
    return { x = x, y = y, z = z }
end

local function lastPlayerCoords(playerSource)
    local ped = GetPlayerPed(playerSource)
    if ped and ped > 0 and DoesEntityExist(ped) then
        local coords = normalizeCoords(GetEntityCoords(ped))
        if coords and (math.abs(coords.x) + math.abs(coords.y) + math.abs(coords.z)) > 0.1 then return coords end
    end
    local cached = positions[playerSource]
    return cached and cached.coords or nil
end

local function markerTargets(bucket)
    local targets = {}
    for _, playerSource in ipairs(GetPlayers()) do
        playerSource = tonumber(playerSource)
        if playerSource and GetPlayerRoutingBucket(playerSource) == bucket then targets[#targets + 1] = playerSource end
    end
    return targets
end

local function markerPayload(marker)
    -- os.time existe somente no servidor. Enviamos o tempo restante para o
    -- cliente, que usa GetGameTimer apenas para controlar a exibicao local.
    local payload = {}
    for key, value in pairs(marker) do payload[key] = value end
    payload.remainingSeconds = math.max(0, (tonumber(marker.expiresAt) or os.time()) - os.time())
    return payload
end

local function sendMarker(marker)
    local payload = markerPayload(marker)
    for _, target in ipairs(markerTargets(marker.bucket)) do
        TriggerClientEvent('ob_combatlog:client:playerLeft', target, payload)
    end
end

local function activeForBucket(bucket)
    local entries = {}
    local now = os.time()
    for id, marker in pairs(activeMarkers) do
        if marker.expiresAt <= now then
            activeMarkers[id] = nil
        elseif marker.bucket == bucket then
            entries[#entries + 1] = markerPayload(marker)
        end
    end
    return entries
end

RegisterNetEvent('ob_combatlog:server:updatePosition', function(coords)
    local playerSource = tonumber(source)
    local normalized = playerSource and normalizeCoords(coords)
    if normalized then
        local characterName, userId = characterIdentity(playerSource)
        positions[playerSource] = {
            coords = normalized,
            updatedAt = GetGameTimer(),
            characterName = characterName,
            userId = userId,
        }
    end
end)

RegisterNetEvent('ob_combatlog:server:requestMarkers', function()
    local playerSource = tonumber(source)
    if not playerSource then return end
    TriggerClientEvent('ob_combatlog:client:syncMarkers', playerSource, activeForBucket(GetPlayerRoutingBucket(playerSource)))
end)

AddEventHandler('playerDropped', function(reason)
    local playerSource = tonumber(source)
    if not playerSource then return end
    local cached = positions[playerSource]
    local characterName, userId = characterIdentity(playerSource)
    local displayName = GetPlayerName(playerSource) or ('Jogador %s'):format(playerSource)
    local name = characterName or (cached and cached.characterName) or displayName
    userId = userId or (cached and cached.userId) or exports.ob_core:GetUserId(playerSource)
    local state = Player(playerSource).state
    local downed = state and state['or:downed'] == true
    local restrained = state and (state['or:restrained'] == true or state['ob:restrained'] == true)
    local status = downed and 'Saiu incapacitado (combat log).' or restrained and 'Saiu algemado.' or nil
    local coords = lastPlayerCoords(playerSource)
    local bucket = GetPlayerRoutingBucket(playerSource)
    local translatedReason = readableReason(reason)

    if coords then
        nextMarkerId = nextMarkerId + 1
        local marker = {
            id = ('%s:%s:%s'):format(os.time(), playerSource, nextMarkerId),
            name = name:sub(1, 64),
            userId = tonumber(userId),
            reason = translatedReason,
            status = status,
            time = os.date('%d/%m/%Y %H:%M:%S'),
            coords = coords,
            bucket = bucket,
            expiresAt = os.time() + math.max(10, math.floor(tonumber(OBCombatLogConfig.DisplaySeconds) or 300)),
        }
        activeMarkers[marker.id] = marker
        sendMarker(marker)
    else
        print(('[ob_combatlog] Aviso 3D nao criado para sessao %s: posicao indisponivel.'):format(playerSource))
    end

    positions[playerSource] = nil
    print(('[ob_combatlog] %s [display:%s | sessao:%s | user:%s] saiu: %s%s'):format(name, displayName, playerSource, userId or 'n/a', translatedReason, status and (' | ' .. status) or ''))
end)

CreateThread(function()
    while true do
        Wait(30000)
        local now = os.time()
        for id, marker in pairs(activeMarkers) do
            if marker.expiresAt <= now then activeMarkers[id] = nil end
        end
        for playerSource in pairs(positions) do
            if not GetPlayerName(playerSource) then positions[playerSource] = nil end
        end
    end
end)
