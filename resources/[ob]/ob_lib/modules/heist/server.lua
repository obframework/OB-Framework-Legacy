local resource = GetCurrentResourceName()
local cfg = HeistConfig
local states, reservations = {}, {}
local globalCooldownUntil, sequence = 0, 0

local function unix() return os.time() end
local function validPlayer(src)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and GetPlayerRoutingBucket(src) == 0 and GetEntityHealth(ped) > 100
end
local function near(src, coords, extra)
    return validPlayer(src) and #(GetEntityCoords(GetPlayerPed(src)) - vector3(coords.x, coords.y, coords.z)) <= (cfg.interactDistance + (extra or 1.0))
end
local function countItem(src, name) return tonumber(exports.ob_inventory:GetItemCount(src, name)) or 0 end
local function policeCount()
    if GetResourceState('ob_dispatch') ~= 'started' then return 0 end
    local ok, total = pcall(function() return exports.ob_dispatch:CountOnDuty('police') end)
    return ok and tonumber(total) or 0
end
local function isPolice(src)
    if GetResourceState('ob_org') ~= 'started' then return false end
    local ok, result = pcall(function() return exports.ob_org:HasPermission(src, 'police', true) end)
    return ok and result == true
end
local function publicStates()
    local result = {}
    for id, state in pairs(states) do
        result[id] = { phase=state.phase, active=state.active, cooldownUntil=state.cooldownUntil,
            failedUntil=state.failedUntil, closingAt=state.closingAt, looted=state.looted }
    end
    return result
end
local function sync(target) TriggerClientEvent(resource .. ':client:sync', target or -1, publicStates(), unix()) end
local function clearReservations(locationId)
    for token, pending in pairs(reservations) do if not locationId or pending.locationId == locationId then reservations[token] = nil end end
end
local function resetLocation(id, cooldown)
    local state = states[id]
    if not state then return end
    state.phase, state.active, state.startedAt, state.closingAt, state.failedUntil = 0, false, 0, 0, 0
    state.looted, state.locks = {}, {}
    if cooldown then state.cooldownUntil = math.max(state.cooldownUntil or 0, unix() + cfg.cooldownSeconds) end
    clearReservations(id)
end
local function allLooted(id)
    local location, state = cfg.locations[id], states[id]
    for index in ipairs(location.loot or {}) do if not state.looted[index] then return false end end
    return #(location.loot or {}) > 0
end
local function dispatch(id)
    if GetResourceState('ob_dispatch') ~= 'started' then return end
    local location = cfg.locations[id]
    pcall(function()
        exports.ob_dispatch:RegisterType(cfg.dispatchType, {
            code='10-90', title='Roubo a banco', groups={'police'}, priority=3,
            message='Alarme bancário acionado.', duration=300, radius=55.0,
            blip={sprite=161,colour=1,scale=1.0}, sound=true,
        })
        exports.ob_dispatch:CreateAlert(cfg.dispatchType, {
            coords=location.center, title='Roubo - '..location.label,
            message='O sistema de segurança detectou uma invasão.', priority=3, radius=55.0, duration=300,
        })
    end)
end
local function findEntry(location, kind, entryId)
    if kind == 'stage' then return location.actions and location.actions[entryId] end
    local index = math.floor(tonumber(entryId) or 0)
    return location.loot and location.loot[index], index
end

for id in pairs(cfg.locations) do
    states[id] = { phase=0, active=false, startedAt=0, cooldownUntil=0, failedUntil=0, closingAt=0, looted={}, locks={} }
end

OR.Callback.register('snapshot', function() return publicStates(), unix() end, {rateLimit={limit=8,window=10000}})

OR.Callback.register('begin', function(src, locationId, kind, entryId)
    locationId, kind = tostring(locationId or ''), tostring(kind or '')
    local location, state = cfg.locations[locationId], states[locationId]
    if not location or not state or (kind ~= 'stage' and kind ~= 'loot') then return false, 'Ação inválida.' end
    local entry, normalizedId = findEntry(location, kind, entryId)
    if not entry or not near(src, entry.coords) then return false, 'Você está longe do ponto de interação.' end
    if isPolice(src) then return false, 'Policiais em serviço não podem iniciar este roubo.' end
    local now, key = unix(), kind .. ':' .. tostring(normalizedId or entryId)
    if now < (state.cooldownUntil or 0) then return false, ('Banco em segurança por mais %s minuto(s).'):format(math.ceil((state.cooldownUntil-now)/60)) end
    if now < globalCooldownUntil and not state.active then return false, 'Outro banco foi assaltado recentemente.' end
    if now < (state.failedUntil or 0) then return false, 'O sistema está bloqueado após uma tentativa falha.' end
    if state.closingAt and state.closingAt > 0 then return false, 'O sistema já iniciou o fechamento de emergência.' end
    if kind == 'stage' then
        if state.phase ~= tonumber(entry.requires) then return false, 'Essa etapa não está disponível agora.' end
        if state.phase == 0 and policeCount() < cfg.minimumPolice then return false, ('São necessários %s policiais em serviço.'):format(cfg.minimumPolice) end
    else
        if state.phase < tonumber(entry.requires or 0) then return false, 'O cofre ainda não foi liberado.' end
        if state.looted[normalizedId] then return false, 'Esse ponto já foi esvaziado.' end
    end
    if state.locks[key] then return false, 'Outra pessoa já está usando este ponto.' end
    if entry.item and countItem(src, entry.item) < 1 then return false, 'Você não possui o equipamento necessário.' end
    sequence = sequence + 1
    local token = ('%s:%s:%s:%s'):format(resource, src, sequence, math.random(100000,999999))
    reservations[token] = {source=src,locationId=locationId,kind=kind,entryId=normalizedId or entryId,key=key,
        started=GetGameTimer(),expires=unix()+cfg.actionTimeoutSeconds}
    state.locks[key] = token
    return true, { token=token,label=entry.label,duration=entry.duration or (kind=='loot' and 7000 or 3500),
        game=entry.game,options=entry.options or {},kind=kind }
end, {rateLimit={limit=6,window=10000}})

OR.Callback.register('finish', function(src, token, success)
    local pending = reservations[tostring(token or '')]
    if not pending or pending.source ~= src then return false, 'Essa ação expirou.' end
    local location, state = cfg.locations[pending.locationId], states[pending.locationId]
    local entry, index = findEntry(location, pending.kind, pending.entryId)
    reservations[token] = nil
    if state and state.locks[pending.key] == token then state.locks[pending.key] = nil end
    if not entry or not state or unix() > pending.expires or not near(src, entry.coords, 1.5) then return false, 'A ação não é mais válida.' end
    if success ~= true then state.failedUntil = unix() + cfg.failedAttemptSeconds; sync(); return false, 'Falha na etapa; o sistema entrou em bloqueio temporário.' end
    if GetGameTimer() - pending.started < 1000 then return false, 'Conclusão rápida demais para ser aceita.' end
    if entry.item and countItem(src, entry.item) < 1 then return false, 'O equipamento não está mais no inventário.' end
    if pending.kind == 'stage' then
        if state.phase ~= tonumber(entry.requires) then return false, 'A etapa já mudou.' end
        if entry.consume and not exports.ob_inventory:RemoveItem(src, entry.item, 1) then return false, 'Não foi possível consumir o equipamento.' end
        local starting = state.phase == 0
        state.phase, state.active, state.startedAt = tonumber(entry.advances), true, state.startedAt > 0 and state.startedAt or unix()
        state.failedUntil = 0
        if starting then globalCooldownUntil = unix() + cfg.globalCooldownSeconds; dispatch(pending.locationId) end
        sync()
        return true, 'Etapa concluída. O próximo acesso foi liberado.'
    end
    if state.looted[index] then return false, 'Esse ponto já foi esvaziado.' end
    local reward, amount = entry.reward, math.random(entry.reward.min, entry.reward.max)
    local canCarry, carryError = exports.ob_inventory:CanCarryItem(src, reward.item, amount)
    if not canCarry then return false, carryError or 'Sem espaço para guardar a recompensa.' end
    local added, addError = exports.ob_inventory:AddItem(src, reward.item, amount)
    if not added then return false, addError or 'Não foi possível entregar a recompensa.' end
    state.looted[index] = true
    if allLooted(pending.locationId) then state.closingAt = unix() + cfg.escapeSeconds; state.cooldownUntil = unix() + cfg.cooldownSeconds end
    sync()
    return true, ('Você recolheu $%s em valores não declarados.'):format(amount)
end, {rateLimit={limit=8,window=10000}})

RegisterCommand(cfg.resetCommand, function(src, args)
    if src ~= 0 and not exports.ob_core:IsAdmin(src) then return end
    local id = tostring(args[1] or '')
    if id ~= '' and states[id] then resetLocation(id, false) else for locationId in pairs(states) do resetLocation(locationId, false) end end
    globalCooldownUntil = 0
    sync()
end, false)

CreateThread(function()
    while true do
        Wait(5000)
        local now, changed = unix(), false
        for token, pending in pairs(reservations) do
            if now > pending.expires or not GetPlayerName(pending.source) then
                local state = states[pending.locationId]
                if state and state.locks[pending.key] == token then state.locks[pending.key] = nil end
                reservations[token] = nil
            end
        end
        for id, state in pairs(states) do
            if state.active and ((state.closingAt or 0) > 0 and now >= state.closingAt or now-state.startedAt >= cfg.robberySeconds) then
                resetLocation(id, true); changed = true
            end
        end
        if changed then sync() end
    end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    for token, pending in pairs(reservations) do
        if pending.source == src then
            local state = states[pending.locationId]
            if state and state.locks[pending.key] == token then state.locks[pending.key] = nil end
            reservations[token] = nil
        end
    end
end)
