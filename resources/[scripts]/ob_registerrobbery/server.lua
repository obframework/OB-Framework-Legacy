local resource = GetCurrentResourceName()
local states, sessions, locks, population = {}, {}, {}, {}
local serial, globalUntil, pendingStart = 0, 0, nil
local function decode(value, fallback)
    local ok, data = pcall(json.decode, value or '')
    return ok and type(data) == 'table' and data or fallback
end
local saved = decode(GetResourceKvpString('heist:cooldowns:v1'), {})
HeistLocations = Config.Locations
HeistStates = states

local function distance(a, b)
    if not a or not b then return math.huge end
    return math.sqrt((a.x-b.x)^2 + (a.y-b.y)^2 + (a.z-b.z)^2)
end
local function userId(src)
    local value = exports.ob_core:GetUserId(src)
    return tonumber(value)
end
local function alive(src, point, radius)
    local ped = GetPlayerPed(src)
    if ped == 0 or not DoesEntityExist(ped) or GetEntityHealth(ped) <= 0 then return false end
    local state = Player(src).state
    return not state['or:downed'] and not state['or:dead']
        and GetPlayerRoutingBucket(src) == 0 and distance(GetEntityCoords(ped), point) <= radius
end
local function police(src)
    for _, permission in ipairs(Config.PolicePermissions or {'police'}) do
        if GetResourceState('ob_org') == 'started' then
            local ok, allowed = pcall(function() return exports.ob_org:HasPermission(src, permission, true) end)
            if ok and allowed then return true end
        else
            local job = exports.ob_core:GetJob(src)
            if job and job.name == permission and job.onDuty == true then return true end
        end
    end
    return false
end
local function countPolice()
    local count = 0
    for _, value in ipairs(GetPlayers()) do if police(tonumber(value)) then count = count+1 end end
    return count
end
local function stateFor(id)
    if not states[id] then
        states[id] = { phase = 'idle', stage = 0, taken = {}, cooldown = tonumber(saved[id]) or 0 }
    end
    return states[id]
end
local function persist()
    SetResourceKvp('heist:cooldowns:v1', json.encode(saved))
end
local function broadcast()
    TriggerClientEvent(resource..':sync', -1, HeistLocations, states)
end
HeistBroadcast = broadcast
HeistStateFor = stateFor
HeistDistance = distance
local function deletePopulation(id)
    for _, ped in ipairs(population[id] or {}) do if DoesEntityExist(ped) then DeleteEntity(ped) end end
    population[id] = nil
    stateFor(id).peds = nil
end
local function finishRobbery(id)
    local state = stateFor(id)
    state.phase, state.stage, state.taken = 'idle', 0, {}
    state.endsAt, state.lootReadyAt, state.complete = nil, nil, nil
    deletePopulation(id)
    broadcast()
end
local function notify(src, message, kind)
    TriggerClientEvent('ob_notification:client:notify', src, message, kind or 'info')
end
local function alert(location)
    for _, value in ipairs(GetPlayers()) do
        local src = tonumber(value)
        if police(src) then TriggerClientEvent(resource..':alert', src, location.label, location.coords, Config.AlertSeconds or 180) end
    end
end
local function beginRobbery(id, location)
    local state, now = stateFor(id), os.time()
    state.phase, state.stage, state.taken = 'active', 0, {}
    state.complete = nil
    state.endsAt = now + (Config.RobberySeconds or 1200)
    state.cooldown = state.endsAt + (location.cooldown or Config.CooldownSeconds or 1800)
    saved[id] = state.cooldown
    globalUntil = now + (Config.GlobalCooldownSeconds or 0)
    saved.__global = globalUntil
    persist()
    alert(location)
    broadcast()
end
globalUntil = tonumber(saved.__global) or 0

-- O cliente nunca envia premio, policia minima, etapa ou coordenadas da acao.
local function begin(src, id, lootIndex)
    if type(id) ~= 'string' then return nil, 'Local invalido.' end
    local location = HeistLocations[id]
    if not location then return nil, 'Local nao cadastrado.' end
    local state, now = stateFor(id), os.time()
    local uid = userId(src)
    if not uid then return nil, 'Selecione seu personagem.' end
    if sessions[src] then return nil, 'Conclua ou cancele sua acao atual.' end
    if locks[id] then return nil, 'Outra pessoa esta realizando uma etapa aqui.' end
    if state.complete then return nil, 'Este local ja foi esvaziado. Deixe a area.' end
    if not alive(src, location.coords, location.radius or 35) then return nil, 'Voce esta longe ou incapacitado.' end
    local step, point, loot
    if lootIndex ~= nil then
        loot = tonumber(lootIndex)
        if not loot or loot % 1 ~= 0 then return nil, 'Coleta invalida.' end
        point = location.loot and location.loot[loot]
        if not point or state.phase ~= 'active' or state.stage < #location.steps or state.taken[tostring(loot)] then
            return nil, 'Dinheiro indisponivel. Conclua as etapas anteriores.'
        end
        if state.lootReadyAt and now < state.lootReadyAt then return nil, 'Carga armada. Afaste-se e aguarde a detonacao.' end
        step = { label = 'Recolhendo dinheiro', seconds = Config.LootSeconds or 15 }
    else
        if state.phase == 'idle' then
            if now < state.cooldown or now < globalUntil then return nil, 'Local em recuperacao. Tente mais tarde.' end
            if pendingStart then return nil, 'Outro roubo esta sendo iniciado. Aguarde.' end
        end
        step = location.steps[state.stage+1]
        if not step then return nil, 'Procure os pontos de coleta.' end
        point = step.coords or location.coords
        if step.intimidate and Config.Bank and Config.RequireLivingTeller ~= false then
            local teller = population[id] and population[id][1]
            if not teller or not DoesEntityExist(teller) or GetEntityHealth(teller)<=0 then return nil, 'Nao ha bancario vivo para liberar o acesso.' end
        end
        if step.intimidate and GetSelectedPedWeapon(GetPlayerPed(src)) == joaat('WEAPON_UNARMED') then
            return nil, 'Voce precisa ameacar o banco com uma arma.'
        end
    end
    local range = step.radius or (Config.InteractDistance or 2.8)
    if not alive(src, point, range) then return nil, 'Aproxime-se do ponto da acao.' end
    locks[id] = src -- Antes de exports de inventario, que podem aguardar banco.
    local starting=state.phase=='idle'
    if starting then pendingStart=src end
    local ok, result, message = pcall(function()
        if starting and countPolice() < (location.police or Config.MinimumPolice or 0) then return nil, 'Policiais em servico insuficientes.' end
        if step.item then
            local count = exports.ob_inventory:GetItemCount(src, step.item)
            if (tonumber(count) or 0) < 1 then return nil, 'Item necessario: '..step.item end
        end
        if not alive(src, point, range) or userId(src) ~= uid then return nil, 'Acao interrompida.' end
        if step.item and step.consume ~= false then
            if exports.ob_inventory:RemoveItem(src, step.item, 1) ~= true then return nil, 'Nao foi possivel usar o item.' end
        end
        if state.phase == 'idle' then beginRobbery(id, location) end
        serial = serial+1
        local token = ('%s:%s:%s:%s'):format(src, uid, serial, GetGameTimer())
        local duration = math.max(1, tonumber(step.seconds) or 10)
        sessions[src] = { id=id, uid=uid, token=token, stage=state.stage, loot=loot, point=point,
            readyAt=os.time()+duration, expires=os.time()+duration+180, seconds=duration, range=range }
        return { token=token, seconds=duration, label=step.label, game=step.game, options=step.options,
            animation=step.animation, explosive=step.explosive, point=point }
    end)
    if starting then pendingStart=nil end
    if not ok or not result then
        locks[id] = nil
        if not ok then print(('[%s] begin falhou: %s'):format(resource, tostring(result))) end
        return nil, ok and message or 'Nao foi possivel iniciar a acao.'
    end
    return result
end

OR.Callback.register('begin', begin, {rateLimit={limit=8,window=10000}})
OR.Callback.register('finish', function(src, token, success)
    local session = sessions[src]
    if not session or token ~= session.token then return false, 'Acao invalida ou expirada.' end
    -- Invalida antes de qualquer await: token nunca paga duas vezes.
    sessions[src] = nil
    local id, state, location = session.id, stateFor(session.id), HeistLocations[session.id]
    local function release(ok, message) locks[id] = nil; return ok, message end
    if success ~= true then return release(false, 'Procedimento cancelado ou falhou. O item usado nao e devolvido.') end
    if not location or userId(src) ~= session.uid or os.time() < session.readyAt or os.time() > session.expires
        or state.phase ~= 'active' or state.stage ~= session.stage
        or not alive(src, session.point, session.range+1) then
        return release(false, 'Acao interrompida, fora de alcance ou tempo invalido.')
    end
    local ok, err = pcall(function()
        if session.loot then
            local key, point = tostring(session.loot), location.loot[session.loot]
            if state.taken[key] then error('Coleta ja realizada.') end
            local reward = point.reward or location.reward or Config.Reward
            local amount = math.random(reward.min, reward.max)
            local item = Config.RewardItem or 'black_money'
            if not exports.ob_inventory:CanCarryItem(src, item, amount) then error('Sem espaco para o dinheiro.') end
            if userId(src) ~= session.uid or not alive(src, session.point, (Config.InteractDistance or 2.8)+1) then error('Jogador indisponivel.') end
            state.taken[key] = true
            -- Cooldown ja foi persistido no inicio. Restart nao repoe este premio.
            local added, addError = exports.ob_inventory:AddItem(src, item, amount)
            if added ~= true then state.taken[key] = nil; error(addError or 'Inventario recusou o dinheiro.') end
            print(('[%s] coleta user_id=%s local=%s ponto=%s valor=%s'):format(resource, session.uid, id, key, amount))
            local total = 0
            for _ in pairs(state.taken) do total=total+1 end
            if total >= #location.loot then
                -- Mantem as portas abertas para a fuga; nao prende o grupo no cofre.
                if Config.Bank then
                    state.complete = true
                    state.endsAt = os.time() + (Config.EscapeSeconds or 180)
                else finishRobbery(id) end
            end
            notify(src, ('Voce recolheu %s em dinheiro sujo.'):format(amount), 'success')
        else
            if location.steps[state.stage+1].intimidate and Config.Bank and Config.RequireLivingTeller ~= false then
                local teller=population[id] and population[id][1]
                if not teller or not DoesEntityExist(teller) or GetEntityHealth(teller)<=0 then error('O bancario morreu antes de liberar a porta.') end
            end
            state.stage = state.stage+1
            local step = location.steps[state.stage]
            if step.explosive then
                local fuse=math.max(0,tonumber(step.fuseSeconds) or 0)
                if fuse>0 then
                    state.lootReadyAt=os.time()+fuse
                    local expires=state.endsAt
                    notify(src,('Carga armada! Afaste-se: detonacao em %s segundos.'):format(fuse),'error')
                    SetTimeout(fuse*1000,function()
                        if state.phase=='active' and state.endsAt==expires then TriggerClientEvent(resource..':blast',-1,step.coords or location.coords) end
                    end)
                else TriggerClientEvent(resource..':blast', -1, step.coords or location.coords) end
            end
        end
        broadcast()
    end)
    locks[id] = nil
    if not ok then return false, tostring(err) end
    return true, session.loot and 'Coleta concluida.' or 'Etapa concluida. Continue a acao.'
end, {rateLimit={limit=10,window=10000}})

OR.Callback.register('snapshot', function() return {locations=HeistLocations, states=states} end,
    {rateLimit={limit=4,window=10000}})

CreateThread(function()
    while true do
        Wait(1000)
        for src, session in pairs(sessions) do
            if os.time() > session.expires or not GetPlayerName(src) or not alive(src, session.point, session.range+4) then
                locks[session.id], sessions[src] = nil, nil
                TriggerClientEvent(resource..':cancel', src)
            end
        end
        for id, state in pairs(states) do
            if state.phase == 'active' and os.time() >= state.endsAt and not locks[id] then finishRobbery(id) end
        end
    end
end)

-- Peds criados no servidor: uma unica populacao compartilhada por todos.
CreateThread(function()
    while true do
        Wait(5000)
        if Config.Bank then
            for id, location in pairs(HeistLocations) do
                local nearby = false
                for _, value in ipairs(GetPlayers()) do
                    local src, ped = tonumber(value), GetPlayerPed(tonumber(value))
                    if ped ~= 0 and GetPlayerRoutingBucket(src) == 0 and distance(GetEntityCoords(ped),location.coords) < 110 then nearby=true; break end
                end
                if nearby and not population[id] then
                    population[id] = {}
                    local nets = {}
                    for _, spec in ipairs(location.npcs or {}) do
                        local p = spec.coords
                        local ped = CreatePed(4, joaat(spec.model or 'a_m_y_business_01'), p.x,p.y,p.z,p.w or 0,true,true)
                        if ped and ped ~= 0 then
                            SetEntityOrphanMode(ped, 2)
                            population[id][#population[id]+1] = ped
                            nets[#nets+1] = {netId=NetworkGetNetworkIdFromEntity(ped),teller=spec.teller==true,coords=p,walk=spec.walk}
                        end
                    end
                    stateFor(id).peds = nets
                    broadcast()
                elseif not nearby and population[id] and stateFor(id).phase == 'idle' then deletePopulation(id); broadcast() end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    local session = sessions[src]
    if session then locks[session.id] = nil end
    sessions[src] = nil
end)
AddEventHandler('onResourceStop', function(name)
    if name ~= resource then return end
    for id in pairs(population) do deletePopulation(id) end
end)
