local areas, nextId, sessions = {}, 0, {}

local function rows()
    local result = {}
    for _, area in pairs(areas) do result[#result + 1] = area end
    table.sort(result, function(a,b) return a.id < b.id end)
    return result
end

local function broadcast(message)
    TriggerClientEvent('ob_perimetro:client:sync', -1, rows())
    if message then TriggerClientEvent('ob_notification:client:notify', -1, message, 'info', 8000) end
end

local function authorize(src)
    if not GetPlayerName(src) or GetResourceState('ob_core') ~= 'started'
        or GetResourceState('ob_org') ~= 'started' then return nil, 'Servico policial indisponivel.' end
    if not OR.Security.rateLimit(src, 'perimetro:manage', 5, 10000) then return nil, 'Aguarde antes de tentar novamente.' end
    local userId = exports.ob_core:GetUserId(src)
    if not userId then return nil, 'Personagem indisponivel.' end
    local license, session = GetPlayerIdentifierByType(src, 'license'), sessions[src]
    -- HasPermission consulta o banco e pode ceder a execucao.
    local ok, allowed = pcall(function()
        return exports.ob_org:HasPermission(src, OBPerimetro.Permission, OBPerimetro.RequireDuty)
    end)
    if not ok or allowed ~= true then return nil, 'Somente policiais em servico podem gerenciar perimetros.' end
    if not GetPlayerName(src) or sessions[src] ~= session or GetPlayerIdentifierByType(src, 'license') ~= license
        or exports.ob_core:GetUserId(src) ~= userId then return nil, 'Sessao alterada. Tente novamente.' end
    if GetPlayerRoutingBucket(src) ~= 0 then return nil, 'Volte para a cidade para gerenciar perimetros.' end
    local state = Player(src).state
    if state['or:loaded'] ~= true or state['or:downed'] == true or state['ob:restrained'] == true then
        return nil, 'Nao e possivel fazer isso no estado atual.'
    end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) or GetEntityHealth(ped) <= 0 then return nil, 'Personagem indisponivel.' end
    return userId, nil, GetEntityCoords(ped)
end

local function bounded(value, minimum, maximum)
    if type(value) ~= 'number' and type(value) ~= 'string' then return nil end
    local number = tonumber(value)
    if not number or number ~= number or number < minimum or number > maximum then return nil end
    return math.floor(number)
end

OR.Callback.register('menu', function(src)
    local actor, err = authorize(src)
    if not actor then return nil, err end
    return { areas = rows() }
end)

OR.Callback.register('create', function(src, data)
    local actor, err, coords = authorize(src)
    if not actor then return nil, err end
    if type(data) ~= 'table' or type(data.name) ~= 'string' or #data.name > 64 then return nil, 'Nome invalido (ate 64 bytes).' end
    local name = data.name:gsub('%c', ''):match('^%s*(.-)%s*$')
    if #name < 3 then return nil, 'Informe um nome com pelo menos 3 caracteres.' end
    local radius = bounded(data.radius, OBPerimetro.MinRadius, OBPerimetro.MaxRadius)
    local minutes = bounded(data.minutes, OBPerimetro.MinMinutes, OBPerimetro.MaxMinutes)
    if not radius or not minutes then return nil, 'Raio ou duracao fora dos limites permitidos.' end
    local count = 0
    for _, area in pairs(areas) do
        count = count + 1
        if area.name:lower() == name:lower() then return nil, 'Ja existe um perimetro com esse nome.' end
    end
    if count >= OBPerimetro.MaxActive then return nil, 'Limite de perimetros ativos atingido.' end
    nextId = nextId + 1
    local area = { id = nextId, name = name, radius = radius,
        center = { x = coords.x, y = coords.y, z = coords.z }, expiresAt = os.time() + minutes * 60 }
    areas[area.id] = area
    SetTimeout(minutes * 60000, function()
        if areas[area.id] ~= area then return end
        areas[area.id] = nil
        broadcast(('Perimetro "%s" liberado: prazo encerrado.'):format(area.name))
        print(('[ob_perimetro] EXPIRED id=%s'):format(area.id))
    end)
    broadcast(('A policia interditou o perimetro "%s" por %s minutos. Evite a area sinalizada.'):format(name, minutes))
    print(('[ob_perimetro] CREATE user_id=%s id=%s name=%s radius=%s minutes=%s'):format(actor, area.id, name, radius, minutes))
    return { areas = rows() }
end)

OR.Callback.register('remove', function(src, id)
    local actor, err = authorize(src)
    if not actor then return nil, err end
    id = bounded(id, 1, nextId)
    local area = id and areas[id]
    if not area then return nil, 'Esse perimetro ja foi liberado.' end
    areas[id] = nil
    broadcast(('A policia liberou o perimetro "%s".'):format(area.name))
    print(('[ob_perimetro] REMOVE user_id=%s id=%s'):format(actor, id))
    return { areas = rows() }
end)

RegisterNetEvent('ob_perimetro:server:requestSync', function()
    local src = source
    if OR.Security.rateLimit(src, 'perimetro:sync', 2, 10000) then
        TriggerClientEvent('ob_perimetro:client:sync', src, rows())
    end
end)
AddEventHandler('playerDropped', function() sessions[source] = (sessions[source] or 0) + 1 end)
