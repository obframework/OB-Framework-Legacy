local resource = GetCurrentResourceName()
local callSequence, activeCalls, gunshotCooldown, phoneCooldown = 0, {}, {}, {}
local registeredTypes = {}

local function copyTable(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = copyTable(entry) end
    return result
end

local function typeConfig(typeId)
    return registeredTypes[typeId] or Dispatch.types[typeId]
end

local function hasGroup(src, group)
    if GetResourceState('ob_org') ~= 'started' then return false end
    local ok, allowed = pcall(function() return exports.ob_org:HasPermission(src, group, Dispatch.requireDuty ~= false) end)
    return ok and allowed == true
end

local function belongsToAny(src, groups)
    for _, group in ipairs(groups or {}) do if hasGroup(src, group) then return true end end
    return false
end

local function plainCoords(value)
    if type(value) ~= 'vector3' and type(value) ~= 'vector4' and type(value) ~= 'table' then return nil end
    local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
    if not x or not y or not z or x ~= x or y ~= y or z ~= z then return nil end
    if math.abs(x) > 10000 or math.abs(y) > 10000 or math.abs(z) > 5000 then return nil end
    return vector3(x, y, z)
end

local function actorCoords(actorSource, supplied, allowDowned)
    actorSource = tonumber(actorSource)
    local suppliedCoords = plainCoords(supplied)
    if not actorSource or not GetPlayerName(actorSource) then return suppliedCoords end
    local ped = GetPlayerPed(actorSource)
    if ped == 0 or (allowDowned ~= true and GetEntityHealth(ped) <= 100) then return nil end
    local actual = GetEntityCoords(ped)
    if suppliedCoords and #(actual - suppliedCoords) <= 75.0 then return suppliedCoords end
    return actual
end

local function offsetCoords(coords, definition)
    local minimum = math.max(0.0, tonumber(definition.offsetMin) or 0.0)
    local maximum = math.max(minimum, tonumber(definition.offsetMax) or minimum)
    if maximum <= 0.0 then return coords end
    local angle, distance = math.random() * math.pi * 2.0, minimum + math.random() * (maximum - minimum)
    return vector3(coords.x + math.cos(angle) * distance, coords.y + math.sin(angle) * distance, coords.z)
end

local function createAlert(typeId, payload)
    typeId, payload = tostring(typeId or ''), type(payload) == 'table' and payload or {}
    local definition = typeConfig(typeId)
    if type(definition) ~= 'table' or type(definition.groups) ~= 'table' or #definition.groups == 0 then
        return false, 'Tipo de chamado invalido.'
    end
    local coords = actorCoords(payload.actorSource, payload.coords, payload.allowDowned == true)
    if not coords then return false, 'Coordenadas do chamado invalidas.' end
    local shownCoords = offsetCoords(coords, definition)
    callSequence = callSequence + 1
    local now = os.time()
    local call = {
        id = callSequence, type = typeId, code = tostring(payload.code or definition.code or 'QRR'),
        title = tostring(payload.title or definition.title or 'Novo chamado'),
        message = tostring(payload.message or definition.message or 'Ocorrencia recebida.'),
        coords = { x = shownCoords.x, y = shownCoords.y, z = shownCoords.z },
        radius = math.max(0.0, tonumber(payload.radius) or tonumber(definition.radius) or 0.0),
        duration = math.max(5, math.floor(tonumber(payload.duration) or tonumber(definition.duration) or Dispatch.defaultDuration)),
        radiusOnly = payload.radiusOnly == true or (payload.radiusOnly == nil and definition.radiusOnly == true),
        priority = math.max(1, math.min(3, math.floor(tonumber(payload.priority) or tonumber(definition.priority) or 1))),
        groups = copyTable(definition.groups), blip = copyTable(definition.blip or {}),
        exclusive = payload.exclusive == true or (payload.exclusive == nil and definition.exclusive == true),
        sound = payload.sound ~= false and definition.sound ~= false, createdAt = now,
        expiresAt = now + math.max(5, math.floor(tonumber(payload.duration) or tonumber(definition.duration) or Dispatch.defaultDuration)),
        metadata = type(payload.metadata) == 'table' and payload.metadata or {},
    }
    activeCalls[call.id] = call
    local recipients = 0
    for _, value in ipairs(GetPlayers()) do
        local target = tonumber(value)
        if belongsToAny(target, call.groups) then TriggerClientEvent(resource .. ':client:alert', target, call); recipients = recipients + 1 end
    end
    print(('[ob_dispatch] chamado=%s tipo=%s destinatarios=%s'):format(call.id, typeId, recipients))
    return true, call.id, recipients
end

exports('CreateAlert', createAlert)
exports('RegisterType', function(typeId, definition)
    typeId = type(typeId) == 'string' and typeId:lower():gsub('[^%w_%-]', '') or ''
    if typeId == '' or type(definition) ~= 'table' or type(definition.groups) ~= 'table' or #definition.groups == 0 then return false end
    registeredTypes[typeId] = copyTable(definition)
    return true
end)
exports('CountOnDuty', function(group)
    local total = 0
    for _, value in ipairs(GetPlayers()) do if hasGroup(tonumber(value), tostring(group or '')) then total = total + 1 end end
    return total
end)
exports('GetActiveCalls', function()
    local result = {}
    for _, call in pairs(activeCalls) do result[#result + 1] = copyTable(call) end
    table.sort(result, function(a, b) return a.id > b.id end)
    return result
end)

OR.Callback.register('acceptCall', function(src, callId)
    src, callId = tonumber(src), math.floor(tonumber(callId) or 0)
    local call = activeCalls[callId]
    if not src or not GetPlayerName(src) or not call then return false, 'Essa ocorrencia nao esta mais disponivel.' end
    if not belongsToAny(src, call.groups) then return false, 'Voce nao esta autorizado ou nao esta em servico.' end
    if call.exclusive ~= true then return true, copyTable(call) end
    if call.claimedBy then return false, 'Outro profissional ja aceitou essa ocorrencia.' end

    call.claimedBy = src
    local accepted = copyTable(call)
    activeCalls[callId] = nil
    for _, value in ipairs(GetPlayers()) do
        local target = tonumber(value)
        if belongsToAny(target, call.groups) then TriggerClientEvent(resource .. ':client:remove', target, callId) end
    end
    local requester = tonumber(call.metadata and call.metadata.requesterSource)
    if requester and GetPlayerName(requester) then
        TriggerClientEvent('ob_phone:client:notification', requester,
            ('Seu chamado para %s foi aceito.'):format(call.type == 'phone_medical' and 'o atendimento medico' or 'a policia'), 'phone')
    end
    print(('[ob_dispatch] chamado=%s aceito_por=%s exclusivo=true'):format(callId, src))
    return true, accepted
end, { rateLimit = { limit = 8, window = 10000 } })

OR.Callback.register('activeCalls', function(src)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return {} end
    local result, now = {}, os.time()
    for _, call in pairs(activeCalls) do
        if belongsToAny(src, call.groups) then
            local entry = copyTable(call)
            entry.remaining = math.max(1, (tonumber(call.expiresAt) or now) - now)
            result[#result + 1] = entry
        end
    end
    table.sort(result, function(a, b) return a.id > b.id end)
    return result
end, { rateLimit = { limit = 4, window = 10000 } })

local function characterName(src)
    local ok, character = pcall(function() return exports.ob_core:GetCharacter(src) end)
    if ok and type(character) == 'table' then
        local name = (('%s %s'):format(tostring(character.firstname or ''), tostring(character.lastname or ''))):gsub('^%s+', ''):gsub('%s+$', '')
        if name ~= '' then return name:sub(1, 60) end
    end
    return tostring(GetPlayerName(src) or ('Cidadao %s'):format(src)):sub(1, 60)
end

local function cleanPhoneMessage(value)
    value = tostring(value or ''):gsub('[\r\n\t]+', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' then return 'Solicito atendimento na minha localizacao.' end
    return value:sub(1, 140)
end

OR.Callback.register('phoneRequest', function(src, service, description)
    src, service = tonumber(src), tostring(service or '')
    if not src or not GetPlayerName(src) or Player(src).state['or:loaded'] ~= true then return false, 'Personagem indisponivel.' end
    local typeId = service == 'police' and 'phone_police' or (service == 'ambulance' and 'phone_medical' or nil)
    if not typeId then return false, 'Servico invalido.' end
    local now = os.time()
    if (phoneCooldown[src] or 0) > now then
        return false, ('Aguarde %s segundos para enviar outro chamado.'):format(phoneCooldown[src] - now)
    end
    local userId = tonumber(exports.ob_core:GetUserId(src))
    if not userId then return false, 'Personagem indisponivel.' end
    for _, call in pairs(activeCalls) do
        if call.exclusive == true and tonumber(call.metadata and call.metadata.requesterUserId) == userId then
            return false, 'Voce ja possui um chamado aguardando atendimento.'
        end
    end
    local message = ('%s: %s'):format(characterName(src), cleanPhoneMessage(description))
    local ok, callId = createAlert(typeId, {
        actorSource = src, allowDowned = true, message = message,
        metadata = { origin = 'ob_phone', requesterSource = src, requesterUserId = userId },
    })
    if not ok then return false, callId or 'Nao foi possivel enviar o chamado.' end
    phoneCooldown[src] = now + math.max(5, math.floor(tonumber(Dispatch.phoneRequestCooldown) or 45))
    return true, ('Chamado #%s enviado. Aguarde no local.'):format(callId)
end, { rateLimit = { limit = 3, window = 30000 } })

AddEventHandler(resource .. ':server:createAlert', function(typeId, payload)
    if source and tonumber(source) and tonumber(source) > 0 then return end
    createAlert(typeId, payload)
end)

RegisterNetEvent(resource .. ':server:gunshot', function(reportedWeapon)
    local src = tonumber(source)
    local settings = Dispatch.gunshot or {}
    if settings.enabled ~= true or not src or not GetPlayerName(src) or Player(src).state['or:loaded'] ~= true then return end
    if Player(src).state['or:downed'] == true or belongsToAny(src, settings.ignoreOnDutyGroups) then return end
    local now = os.time()
    if (gunshotCooldown[src] or 0) > now then return end
    local ped = GetPlayerPed(src)
    if ped == 0 or GetEntityHealth(ped) <= 100 then return end
    local weapon = tonumber(reportedWeapon)
    if not weapon or weapon ~= weapon or weapon % 1 ~= 0 then return end
    if (settings.ignoredWeapons or {})[weapon] then return end
    local coords = GetEntityCoords(ped)
    for _, zone in ipairs(settings.ignoredZones or {}) do
        local center = plainCoords(zone.coords)
        if center and #(coords - center) <= (tonumber(zone.radius) or 0.0) then return end
    end
    if math.random(1, 100) > math.max(0, math.min(100, tonumber(settings.reportChance) or 100)) then return end
    gunshotCooldown[src] = now + math.max(1, math.floor(tonumber(settings.cooldownSeconds) or 25))
    createAlert('gunshot', { actorSource = src, coords = coords })
end)

CreateThread(function()
    while true do
        Wait(10000)
        local now = os.time()
        for id, call in pairs(activeCalls) do if now >= call.expiresAt then activeCalls[id] = nil end end
        for src, expires in pairs(gunshotCooldown) do if now >= expires or not GetPlayerName(src) then gunshotCooldown[src] = nil end end
        for src, expires in pairs(phoneCooldown) do if now >= expires or not GetPlayerName(src) then phoneCooldown[src] = nil end end
        local ids = {}
        for id in pairs(activeCalls) do ids[#ids + 1] = id end
        table.sort(ids)
        while #ids > Dispatch.maxActiveCalls do activeCalls[table.remove(ids, 1)] = nil end
    end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    gunshotCooldown[src] = nil
    phoneCooldown[src] = nil
end)
