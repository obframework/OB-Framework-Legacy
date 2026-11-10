local enhanced = type(CreateVoiceChannel) == 'function'
local players, channels, checks, budgets = {}, {}, {}, {}
local phoneRoutes, phoneSignature = {}, ''
local nameGetter
local generation = tostring(os.time()) .. ':' .. GetGameTimer()

local function finite(value)
    value = tonumber(value)
    return value and value == value and value ~= math.huge and value ~= -math.huge and value or nil
end
local function validSource(src)
    src = tonumber(src)
    return src and src > 0 and GetPlayerName(src) and src or nil
end
local function limited(src, action, maximum)
    local now = GetGameTimer()
    budgets[src] = budgets[src] or {}
    local entry = budgets[src][action]
    if not entry or now - entry.time >= 5000 then entry = { time = now, count = 0 }; budgets[src][action] = entry end
    entry.count = entry.count + 1
    return entry.count <= maximum
end
local function modeData(entry)
    local mode = OBVoiceConfig.Modes[entry.mode]
    return { index = entry.mode, distance = entry.override or mode.distance,
        mode = entry.override and 'Personalizado' or mode.label }
end
local function publish(src)
    local entry = players[src]
    if not entry then return end
    local state = Player(src).state
    state:set('proximity', modeData(entry), true)
    state:set('radioChannel', entry.radio, true)
    state:set('callChannel', entry.call, true)
    state:set('pmaVoiceInit', true, true)
    state:set('ob:voiceBucket', entry.bucket, true)
end
local function ensurePlayer(src)
    if not validSource(src) then return nil end
    if not players[src] then
        players[src] = { mode = OBVoiceConfig.DefaultMode, radio = 0, call = 0, radioTalking = false,
            bucket = GetPlayerRoutingBucket(src), enabled = true, proximityEnabled = true,
            radioEnabled = true, radioListen = true, callListen = true }
        publish(src)
    end
    return players[src]
end

-- Enhanced: todos escutam os alcances do proprio bucket, mas cada pessoa
-- transmite somente no alcance escolhido. Sussurrar nao impede ouvir quem grita.
local function reconcile()
    if not enhanced then return end
    local desired, distances = {}, {}
    for _, p in pairs(players) do
        distances[p.bucket] = distances[p.bucket] or {}
        distances[p.bucket][modeData(p).distance] = true
    end
    local function member(key, mode, distance, src, muted, deaf)
        local channel = desired[key]
        if not channel then channel = { mode = mode, distance = distance, members = {} }; desired[key] = channel end
        channel.members[src] = { muted = muted, deaf = deaf }
    end
    for src, p in pairs(players) do
        for distance in pairs(distances[p.bucket]) do
            member(('p:%s:%s'):format(p.bucket, distance), 1, distance, src,
                not p.enabled or not p.proximityEnabled or modeData(p).distance ~= distance, not p.enabled)
        end
        local bucket = OBVoiceConfig.IsolateCommunicationBuckets and p.bucket or 0
        if p.radio > 0 then member(('r:%s:%s'):format(bucket, p.radio), 0, 0.0, src,
            not p.enabled or not p.radioEnabled or not p.radioTalking, not p.enabled or not p.radioEnabled or not p.radioListen) end
        if p.call > 0 then member(('c:%s:%s'):format(bucket, p.call), 0, 0.0, src, not p.enabled, not p.enabled or not p.callListen) end
    end
    -- Rotas direcionais do telefone: ouvintes do viva-voz nunca transmitem
    -- na chamada apenas por estarem perto. Nao usa canais PMA adivinhaveis.
    for talker, listeners in pairs(phoneRoutes) do
        local p = players[talker]
        if p then
            local key = 'phone:' .. talker
            member(key, 0, 0.0, talker, not p.enabled, true)
            for listener in pairs(listeners) do
                local other = players[listener]
                if other and other.bucket == p.bucket then
                    member(key, 0, 0.0, listener, true, not other.enabled or not other.callListen)
                end
            end
        end
    end
    -- Primeiro retirar rotas antigas, evitando transmitir simultaneamente em dois alcances.
    for key, channel in pairs(channels) do
        local target = desired[key]
        if not target then
            DeleteVoiceChannel(channel.id); channels[key] = nil
        else
            for src, previous in pairs(channel.members) do
                if not target.members[src] then
                    RemovePlayerFromVoiceChannel(channel.id, src); channel.members[src] = nil
                elseif target.members[src].muted and not previous.muted then
                    SetPlayerMutedInVoiceChannel(channel.id, src, true); previous.muted = true
                end
            end
        end
    end
    for key, target in pairs(desired) do
        local channel = channels[key]
        if not channel then
            local id = CreateVoiceChannel(target.mode, target.distance + 0.0)
            if not id or id < 0 or id == 65535 then error('Nao foi possivel criar canal de voz OB: ' .. key) end
            channel = { id = id, members = {} }; channels[key] = channel
        end
        for src, state in pairs(target.members) do
            local previous = channel.members[src]
            if not previous then AddPlayerToVoiceChannel(channel.id, src) end
            if not previous or previous.muted ~= state.muted then SetPlayerMutedInVoiceChannel(channel.id, src, state.muted) end
            if not previous or previous.deaf ~= state.deaf then SetPlayerDeafInVoiceChannel(channel.id, src, state.deaf) end
            channel.members[src] = state
        end
    end
end
local function radioName(src)
    if nameGetter then local ok, name = pcall(nameGetter.fn, src); if ok and type(name) == 'string' then return name end end
    return GetPlayerName(src) or tostring(src)
end
local function roster(src, kind)
    local p, result = players[src], {}
    if not p or p[kind] == 0 then return result end
    for other, entry in pairs(players) do
        if entry[kind] == p[kind] and (not OBVoiceConfig.IsolateCommunicationBuckets or entry.bucket == p.bucket) then
            result[tostring(other)] = kind == 'call' or (entry.radioTalking and entry.radioEnabled and entry.enabled) or false
        end
    end
    return result
end
local function sync(src)
    local p = players[src]
    if not p then return end
    local radio, call = roster(src, 'radio'), roster(src, 'call')
    local phoneSend, phoneReceive = {}, {}
    for talker, listeners in pairs(phoneRoutes) do
        if talker == src then
            for listener in pairs(listeners) do phoneSend[tostring(listener)] = true end
        elseif listeners[src] then phoneReceive[tostring(talker)] = true end
    end
    TriggerClientEvent('ob_voice:sync', src, { backend = enhanced and 'enhanced' or 'legacy', generation = generation,
        proximity = modeData(p), bucket = p.bucket, radioChannel = p.radio, callChannel = p.call,
        radio = radio, call = call, phoneSend = phoneSend, phoneReceive = phoneReceive, enabled = p.enabled })
    TriggerClientEvent('pma-voice:syncRadioData', src, radio, radioName(src))
    TriggerClientEvent('pma-voice:syncCallData', src, call, p.call)
end
local function syncAll() for src in pairs(players) do sync(src) end end
exports('SetPhoneRoutes', function(routes)
    -- Somente o recurso de telefone instalado pode publicar estas rotas.
    -- Nao existe evento de rede equivalente a este export.
    if GetInvokingResource() ~= 'ob_phone' or type(routes) ~= 'table' then return false end
    local clean, signature = {}, {}
    for talker, listeners in pairs(routes) do
        talker = validSource(talker)
        if talker and type(listeners) == 'table' then
            for listener, allowed in pairs(listeners) do
                listener = validSource(listener)
                if allowed == true and listener and listener ~= talker
                    and GetPlayerRoutingBucket(talker) == GetPlayerRoutingBucket(listener) then
                    ensurePlayer(talker); ensurePlayer(listener)
                    clean[talker] = clean[talker] or {}; clean[talker][listener] = true
                    signature[#signature+1] = talker .. '>' .. listener
                end
            end
        end
    end
    table.sort(signature); signature = table.concat(signature, ',')
    if signature ~= phoneSignature then
        phoneRoutes, phoneSignature = clean, signature
        reconcile(); syncAll()
    end
    return true
end)
local function canRadio(src, channel)
    if channel == 0 then return true end
    local ace = OBVoiceConfig.RestrictedRadio[channel]
    if ace and not IsPlayerAceAllowed(src, ace) then return false end
    local check = checks[channel]
    if check then local ok, allowed = pcall(check.fn, src); return ok and allowed == true end
    return true
end
local function setChannel(src, kind, value)
    src = validSource(src)
    value = finite(value)
    if not src or not value or value < 0 or value > 2147483647 then return false end
    if kind == 'call' and value ~= math.floor(value) then return false end
    if kind == 'radio' then value = math.floor(value * 100 + 0.5) / 100 end
    local p = ensurePlayer(src)
    if kind == 'radio' and not canRadio(src, value) then
        TriggerClientEvent('pma-voice:radioChangeRejected', src)
        TriggerClientEvent('ob_voice:notice', src, 'Voce nao tem acesso a essa frequencia.')
        sync(src); return false
    end
    if p[kind] == value then sync(src); return true end
    local previous = p[kind]
    p[kind] = value
    if kind == 'radio' then p.radioTalking = false end
    publish(src); reconcile()
    for listener, entry in pairs(players) do
        if listener == src or (previous > 0 and entry[kind] == previous) or (value > 0 and entry[kind] == value) then sync(listener) end
    end
    TriggerClientEvent(kind == 'radio' and 'pma-voice:clSetPlayerRadio' or 'pma-voice:clSetPlayerCall', src, value)
    return true
end
local function register(event, fn, limit)
    RegisterNetEvent(event, function(...)
        local src = validSource(source)
        if not src or not limited(src, event, limit or 20) then return end
        fn(src, ...)
    end)
end
register('ob_voice:ready', function(src)
    ensurePlayer(src); reconcile(); sync(src)
end, 4)
register('ob_voice:mode', function(src, index, override)
    local p = ensurePlayer(src)
    index = finite(index)
    if not index or index ~= math.floor(index) or not OBVoiceConfig.Modes[index] then return end
    if override ~= nil then
        override = finite(override)
        if not override or override < 0 or override > OBVoiceConfig.MaxOverrideDistance then return end
        override = math.floor(override * 2 + .5) / 2
    end
    p.mode, p.override = index, override
    publish(src); reconcile(); sync(src)
end)
register('ob_voice:properties', function(src, properties)
    if type(properties) ~= 'table' then return end
    local p = ensurePlayer(src)
    for _, key in ipairs({ 'enabled', 'proximityEnabled', 'radioEnabled', 'radioListen', 'callListen' }) do
        if type(properties[key]) == 'boolean' then p[key] = properties[key] end
    end
    if not p.enabled or not p.radioEnabled then p.radioTalking = false end
    reconcile(); sync(src)
    for listener in pairs(roster(src, 'radio')) do if tonumber(listener) ~= src then sync(tonumber(listener)) end end
end)
register('pma-voice:setPlayerCall', function(src, channel)
    if OBVoiceConfig.AllowClientCalls then setChannel(src, 'call', channel) end
end)
register('pma-voice:setPlayerRadio', function(src, channel)
    if OBVoiceConfig.AllowClientRadio then setChannel(src, 'radio', channel) end
end)
register('pma-voice:setTalkingOnRadio', function(src, talking)
    local p = ensurePlayer(src)
    if type(talking) ~= 'boolean' then return end
    if p.radio == 0 then return end
    local state = Player(src).state
    talking = talking and p.enabled and p.radioEnabled and canRadio(src, p.radio)
        and state['or:downed'] ~= true and (tonumber(state.disableRadio) or 0) == 0
    if p.radioTalking == talking then return end
    p.radioTalking = talking
    p.radioPressedAt = talking and GetGameTimer() or nil
    reconcile()
    for listener in pairs(roster(src, 'radio')) do sync(tonumber(listener)) end
    for listener in pairs(roster(src, 'radio')) do TriggerClientEvent('pma-voice:setTalkingOnRadio', tonumber(listener), src, talking) end
end, 60)
exports('setPlayerCall', function(src, channel) return setChannel(src, 'call', channel) end)
exports('setPlayerRadio', function(src, channel) return setChannel(src, 'radio', channel) end)
local function getRadio(channel)
    local result = {}
    for src, p in pairs(players) do if p.radio == tonumber(channel) and p.radio > 0 then result[src] = p.radioTalking end end
    return result
end
exports('getPlayersInRadioChannel', getRadio)
exports('GetPlayersInRadioChannel', getRadio)
exports('isValidPlayer', function(src) return players[tonumber(src)] ~= nil end)
exports('addChannelCheck', function(channel, fn, owner)
    channel = finite(channel)
    if not channel or channel <= 0 or type(fn) ~= 'function' then return false end
    checks[channel] = { fn = fn, owner = owner or GetInvokingResource() }; return true
end)
exports('overrideRadioNameGetter', function(fn, owner)
    if type(fn) ~= 'function' then return false end
    nameGetter = { fn = fn, owner = owner or GetInvokingResource() }; return true
end)
exports('GetBackend', function() return enhanced and 'enhanced' or 'legacy' end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    phoneRoutes[src] = nil
    for _, listeners in pairs(phoneRoutes) do listeners[src] = nil end
    phoneSignature = nil -- obriga publicar mesmo que a proxima lista esteja vazia
    players[src], budgets[src] = nil, nil
    reconcile(); syncAll()
end)
AddEventHandler('onResourceStop', function(resource)
    if resource == 'ob_phone' then phoneRoutes, phoneSignature = {}, ''; reconcile(); syncAll() end
    if resource == GetCurrentResourceName() then
        for _, channel in pairs(channels) do DeleteVoiceChannel(channel.id) end
        for src in pairs(players) do
            Player(src).state:set('pmaVoiceInit', false, true)
        end
    else
        for channel, check in pairs(checks) do
            if check.owner == resource then
                -- Mantem o canal fechado enquanto o script de permissao esta parado.
                checks[channel] = { fn = function() return false end, owner = resource }
            end
        end
        if nameGetter and nameGetter.owner == resource then nameGetter = nil end
    end
end)

-- voice_internal e inicializado pelo server.cfg (o Enhanced proibe ExecuteCommand aqui).
if enhanced then
    SetConvarReplicated('sv_mumble', 'false')
else
    SetConvarReplicated('voice_useNativeAudio', 'true')
    SetConvarReplicated('voice_useSendingRangeOnly', 'true')
end
print('[ob_voice] Backend automatico: ' .. (enhanced and 'Enhanced (canais no servidor)' or 'Legacy (Mumble nativo)') .. '. Distancia: HOME.')
CreateThread(function()
    Wait(500)
    for _, src in ipairs(GetPlayers()) do ensurePlayer(tonumber(src)) end
    reconcile(); syncAll()
    while true do
        Wait(500)
        local changed = false
        for src, p in pairs(players) do
            if not validSource(src) then players[src] = nil; budgets[src] = nil; changed = true
            else
                local bucket = GetPlayerRoutingBucket(src)
                if bucket ~= p.bucket then p.bucket = bucket; p.radioTalking = false; publish(src); changed = true end
                if p.radio > 0 and not canRadio(src, p.radio) then p.radio = 0; p.radioTalking = false; publish(src); changed = true end
                if p.radioTalking and (Player(src).state['or:downed'] == true or not p.radioPressedAt or GetGameTimer() - p.radioPressedAt > 60000) then
                    p.radioTalking = false; changed = true
                end
            end
        end
        if changed then reconcile(); syncAll() end
    end
end)
