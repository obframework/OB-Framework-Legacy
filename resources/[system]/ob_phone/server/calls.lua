-- Convites, participantes e viva-voz pertencem ao servidor, nao a um canal
-- escolhido pelo cliente. A voz original por proximidade continua independente.
local service, sessions, serial = OBPhoneService, {}, 0
local function samePlayer(src, id)
    return GetPlayerName(src) ~= nil and service.deviceUid(src) == id
end
local function hasDevice(src)
    local state = Player(src).state
    return state['or:downed'] ~= true and state['or:restrained'] ~= true
        and state['ob:restrained'] ~= true and (exports.ob_inventory:GetItemCount(src, 'phone') or 0) > 0
end
local function voiceReady() return GetResourceState('ob_voice') == 'started' end
local function sendState(call)
    for _, src in ipairs({call.a, call.b}) do
        if src and sessions[src] == call then
            local remote = src == call.a and call.b or call.a
            TriggerClientEvent('ob_phone:client:callState', src, {
                id = call.id, phase = call.phase, incoming = src == call.b,
                number = src == call.a and call.bn or call.an,
                ownNumber = src == call.a and call.an or call.bn,
                speaker = call.speaker[src] == true, muted = call.muted[src] == true,
                video = call.video == true, initiator = src == call.a,
                camera = call.camera[src] ~= false, remoteCamera = call.camera[remote] ~= false,
                elapsed = call.started and math.max(0, math.floor((GetGameTimer() - call.started) / 1000)) or 0,
            })
        end
    end
end
local function updateRoutes()
    if not voiceReady() then return end
    local routes = {}
    local function route(talker, listener)
        if talker == listener or not GetPlayerName(talker) or not GetPlayerName(listener) then return end
        if GetPlayerRoutingBucket(talker) ~= GetPlayerRoutingBucket(listener) then return end
        routes[talker] = routes[talker] or {}; routes[talker][listener] = true
    end
    for src, call in pairs(sessions) do
        if src == call.a and call.phase == 'active' then
            for _, owner in ipairs({call.a, call.b}) do
                local remote = owner == call.a and call.b or call.a
                if not call.muted[remote] then
                    route(remote, owner)
                    if call.speaker[owner] then
                        local ped = GetPlayerPed(owner)
                        if ped and ped > 0 then
                            local coords = GetEntityCoords(ped)
                            for _, candidate in ipairs(GetPlayers()) do
                                local listener = tonumber(candidate)
                                local lp = GetPlayerPed(listener)
                                if listener ~= owner and listener ~= remote and lp and lp > 0
                                    and GetPlayerRoutingBucket(listener) == GetPlayerRoutingBucket(owner)
                                    and #(GetEntityCoords(lp) - coords) <= OBPhoneConfig.SpeakerDistance then
                                    route(remote, listener)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return exports.ob_voice:SetPhoneRoutes(routes)
end
local function finish(call, reason)
    if not call or call.finished then return end
    call.finished = true
    for _, src in ipairs({call.a, call.b}) do
        if sessions[src] == call then
            sessions[src] = nil
            TriggerClientEvent('ob_phone:client:callState', src, {phase = 'ended', reason = reason or 'Chamada encerrada.'})
        end
    end
    updateRoutes()
    if call.b and call.bn then
        local duration = call.started and math.max(0, math.floor((GetGameTimer() - call.started) / 1000)) or 0
        CreateThread(function()
            OR.Database.insert.await('INSERT INTO ob_phone_calls (caller_id,callee_id,caller_number,callee_number,call_type,status,duration) VALUES (?,?,?,?,?,?,?)',
                {call.aid,call.bid,call.an,call.bn,call.video and 'video' or 'voice',call.started and 'answered' or 'missed',duration})
        end)
    end
end
OR.Callback.register('dial', function(src, number, mode)
    if not service.gate(src, 'dial', 4, 15000) then return false, 'Aguarde antes de ligar novamente.' end
    if sessions[src] then return false, 'Voce ja esta em uma chamada.' end
    if not voiceReady() then return false, 'Sistema de voz indisponivel.' end
    number = tostring(number or '')
    mode = mode == 'video' and 'video' or 'voice'
    if not number:match('^%d+$') or #number < 5 or #number > 16 then return false, 'Numero invalido.' end
    local id = service.uid(src)
    if not id or not service.isReady() then return false, 'Celular indisponivel.' end
    serial = serial + 1
    local call = {id = serial, a = src, aid = id, phase = 'preparing', speaker = {}, muted = {}, camera = {}, video = mode == 'video', created = GetGameTimer()}
    sessions[src] = call -- reserva antes de consultar inventario/banco
    local ok, message = pcall(function()
        if not hasDevice(src) then return 'Voce precisa do celular e estar livre para ligar.' end
        local own = service.getPhone(id)
        if not own or (tonumber(own.battery) or 0) <= 0 then return 'Celular sem bateria.' end
        if own.phone_number == number then return 'Voce nao pode ligar para si mesmo.' end
        local target = OR.Database.single.await([[SELECT n.user_id,n.phone_number,n.battery,COALESCE(s.airplane_mode,0) AS airplane_mode
            FROM ob_phone_numbers n LEFT JOIN ob_phone_settings s ON s.user_id=n.user_id WHERE n.phone_number=?]], {number})
        if not target or (tonumber(target.battery) or 0) <= 0 or tonumber(target.airplane_mode)==1 then return 'Celular fora de area.' end
        local peer = OBPhoneDevice.SourceForUser(tonumber(target.user_id)) or exports.ob_core:GetSourceByUserId(tonumber(target.user_id))
        peer = tonumber(peer)
        if not peer or peer == src or not samePlayer(peer, tonumber(target.user_id)) or not hasDevice(peer) then return 'Celular fora de area.' end
        if call.finished or sessions[src] ~= call or not samePlayer(src, id) then return 'Ligacao cancelada.' end
        if not samePlayer(peer, tonumber(target.user_id)) then return 'Celular fora de area.' end
        if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(peer) then return 'Celular fora de area.' end
        if sessions[peer] then return 'Numero ocupado.' end
        call.b, call.bid, call.an, call.bn = peer, tonumber(target.user_id), own.phone_number, number
        call.phase = 'ringing'; sessions[peer] = call
        sendState(call)
        SetTimeout(OBPhoneConfig.RingSeconds * 1000, function()
            if not call.finished and call.phase == 'ringing' then finish(call, 'Chamada nao atendida.') end
        end)
    end)
    if not ok or message then
        finish(call, ok and message or 'Falha ao iniciar ligacao.')
        if not ok then print('[ob_phone] Falha ao preparar chamada: ' .. tostring(message)) end
        return false, ok and message or 'Nao foi possivel ligar.'
    end
    return true
end)
OR.Callback.register('callAction', function(src, action, value)
    if not service.gate(src, 'callAction', 20, 5000) then return false, 'Aguarde um instante.' end
    local call = sessions[src]
    if not call or call.finished then return false, 'Nenhuma chamada em andamento.' end
    if action == 'hangup' then finish(call); return true end
    if action == 'answer' then
        if call.phase ~= 'ringing' or src ~= call.b then return false, 'Chamada invalida.' end
        local usable = hasDevice(src)
        if sessions[src] ~= call or call.finished then return false, 'Chamada encerrada.' end
        if not usable or not samePlayer(src, call.bid) then finish(call); return false, 'Celular indisponivel.' end
        call.phase, call.started = 'active', GetGameTimer()
    elseif (action == 'speaker' or action == 'mute') and call.phase == 'active' and type(value) == 'boolean' then
        call[action == 'speaker' and 'speaker' or 'muted'][src] = value
    elseif action == 'camera' and call.video and call.phase == 'active' and type(value) == 'boolean' then
        call.camera[src] = value
    else return false, 'Acao indisponivel.' end
    updateRoutes(); sendState(call)
    return true
end)
OR.Callback.register('callHistory', function(src)
    local id = service.uid(src)
    if not id or not service.isReady() or not service.gate(src, 'history', 8, 10000) then return false, 'Historico indisponivel.' end
    local rows = OR.Database.query.await([[SELECT CASE WHEN caller_id=? THEN callee_number ELSE caller_number END AS number,call_type,
        CASE WHEN caller_id=? THEN 'out' ELSE 'in' END AS direction,status,duration,
        DATE_FORMAT(created_at,'%d/%m %H:%i') AS created_at FROM ob_phone_calls
        WHERE caller_id=? OR callee_id=? ORDER BY id DESC LIMIT 40]], {id,id,id,id})
    return true, rows or {}
end)
RegisterNetEvent('ob_phone:server:videoSignal', function(callId, payload)
    local src, call = tonumber(source), sessions[tonumber(source)]
    if not src or not call or call.finished or not call.video or call.phase ~= 'active' or tonumber(callId) ~= call.id then return end
    if not service.gate(src, 'videoSignal', 120, 10000) or type(payload) ~= 'table' then return end
    local kind = tostring(payload.type or '')
    if kind ~= 'ready' and kind ~= 'offer' and kind ~= 'answer' and kind ~= 'candidate' then return end
    local encoded = json.encode(payload)
    if type(encoded) ~= 'string' or #encoded > 24000 then return end
    local peer = src == call.a and call.b or call.a
    if peer and sessions[peer] == call and GetPlayerName(peer) then
        TriggerClientEvent('ob_phone:client:videoSignal', peer, call.id, payload)
    end
end)
AddEventHandler('playerDropped', function() finish(sessions[tonumber(source)], 'A outra pessoa desconectou.') end)
AddEventHandler('ob_core:server:characterSelected', function(src) finish(sessions[tonumber(src)], 'Personagem alterado.') end)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() and resource ~= 'ob_voice' then return end
    local pending = {}; for src, call in pairs(sessions) do if src == call.a then pending[#pending+1] = call end end
    for _, call in ipairs(pending) do finish(call, 'Servico de chamadas reiniciado.') end
end)
CreateThread(function()
    local lastDrain = GetGameTimer()
    while true do
        Wait(750)
        local now, work = GetGameTimer(), {}
        for src, call in pairs(sessions) do if src == call.a then work[#work+1] = call end end
        local drain = now - lastDrain >= OBPhoneConfig.CallBatteryInterval * 1000
        if drain then lastDrain = now end
        for _, call in ipairs(work) do
            if call.phase == 'preparing' then
                if now - call.created > 45000 then finish(call, 'Tempo de conexao esgotado.') end
            else
                for _, src in ipairs({call.a, call.b}) do
                    local id = src == call.a and call.aid or call.bid
                    if not samePlayer(src, id) or not hasDevice(src) or not voiceReady()
                        or GetPlayerRoutingBucket(call.a) ~= GetPlayerRoutingBucket(call.b) then
                        finish(call, 'Chamada interrompida.'); break
                    end
                    if not call.finished and drain then
                        OR.Database.update.await('UPDATE ob_phone_numbers SET battery=GREATEST(0,battery-1) WHERE user_id=?', {id})
                        local battery = OR.Database.scalar.await('SELECT battery FROM ob_phone_numbers WHERE user_id=?', {id})
                        if samePlayer(src, id) and sessions[src] == call then
                            TriggerClientEvent('ob_phone:client:battery', src, tonumber(battery) or 0)
                            if (tonumber(battery) or 0) <= 0 then finish(call, 'Bateria esgotada.') end
                        end
                    end
                end
            end
        end
        updateRoutes()
    end
end)
