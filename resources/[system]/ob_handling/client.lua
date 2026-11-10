local session, visible, busy = nil, false, false
local fields = {}
for _, field in ipairs(HandlingEditor.Fields) do fields[field.key] = field end

local function read(vehicle, field)
    if field.type == 'vector' then
        local v = GetVehicleHandlingVector(vehicle, 'CHandlingData', field.key)
        return { x=v.x, y=v.y, z=v.z }
    end
    if field.type == 'int' then return GetVehicleHandlingInt(vehicle, 'CHandlingData', field.key) end
    return GetVehicleHandlingFloat(vehicle, 'CHandlingData', field.key)
end

local function write(vehicle, field, value)
    if field.type == 'vector' then
        SetVehicleHandlingVector(vehicle, 'CHandlingData', field.key, vector3(value.x, value.y, value.z))
    elseif field.type == 'int' then
        SetVehicleHandlingInt(vehicle, 'CHandlingData', field.key, value)
    else
        SetVehicleHandlingFloat(vehicle, 'CHandlingData', field.key, value)
    end
end

local function sameVehicle(s)
    return s and DoesEntityExist(s.vehicle) and GetEntityModel(s.vehicle) == s.model
        and Entity(s.vehicle).state.obHandlingSession == s.tag
end

local function driver(s)
    return sameVehicle(s) and GetVehiclePedIsIn(PlayerPedId(), false) == s.vehicle
        and GetPedInVehicleSeat(s.vehicle, -1) == PlayerPedId() and NetworkHasControlOfEntity(s.vehicle)
end

local function hide()
    visible = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action='hide' })
end

local function restore(s)
    if not sameVehicle(s) then return end
    for key, applied in pairs(s.changed) do
        -- Nao sobrescreve uma atualizacao posterior de outro recurso (ex.: dano do core).
        local ok, current = pcall(read, s.vehicle, fields[key])
        local matches = ok
        if ok and type(applied) == 'table' then
            for _, axis in ipairs({'x','y','z'}) do
                if math.abs(current[axis] - applied[axis]) > 0.00001 then matches = false end
            end
        elseif ok then matches = math.abs(current - applied) <= 0.00001 end
        if matches then pcall(write, s.vehicle, fields[key], s.original[key]) end
    end
    s.changed = {}
end

local function payload()
    local values = {}
    for _, f in ipairs(HandlingEditor.Fields) do values[f.key] = read(session.vehicle, f) end
    return { action='open', tag=session.tag, name=session.name, fields=HandlingEditor.Fields,
        values=values, original=session.original, command=HandlingEditor.Command }
end

local function openEditor()
    if busy or visible or IsNuiFocused() then return end
    busy = true
    local ok, allowed = pcall(OR.Callback.await, 'access')
    busy = false
    if not ok or not allowed then return OR.Notify('Sem permissao para editar handling.', 'error') end
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped or not IsThisModelACar(GetEntityModel(vehicle)) then
        return OR.Notify('Entre no banco do motorista de um automovel para testar.', 'error')
    end
    if not NetworkHasControlOfEntity(vehicle) then return OR.Notify('Aguarde o controle do veiculo e tente novamente.', 'error') end
    if session and (session.vehicle ~= vehicle or not sameVehicle(session)) then restore(session); session = nil end
    if not session then
        local tag = ('%s:%s'):format(GetPlayerServerId(PlayerId()), GetGameTimer())
        session = { vehicle=vehicle, model=GetEntityModel(vehicle), original={}, changed={}, tag=tag,
            name=GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)) }
        Entity(vehicle).state:set('obHandlingSession', tag, false)
        for _, f in ipairs(HandlingEditor.Fields) do session.original[f.key] = read(vehicle, f) end
    end
    visible = true
    SetNuiFocus(true, true)
    SendNUIMessage(payload())
end

RegisterCommand(HandlingEditor.Command, openEditor, false)

local function numberInRange(value, field)
    return type(value) == 'number' and value == value and value >= field.min and value <= field.max
        and (field.type ~= 'int' or value % 1 == 0)
end

RegisterNUICallback('apply', function(data, cb)
    if busy or not visible or not driver(session) then return cb({ error='Volte ao banco do motorista e reabra o editor.' }) end
    local field = type(data) == 'table' and fields[data.key]
    if not field then return cb({ error='Campo invalido.' }) end
    local value = data.value
    if field.type == 'vector' then
        if type(value) ~= 'table' then return cb({ error='Vetor invalido.' }) end
        for _, axis in ipairs({'x','y','z'}) do
            if not numberInRange(value[axis], field) then return cb({ error='Valor fora dos limites.' }) end
        end
    elseif not numberInRange(value, field) then return cb({ error='Valor fora dos limites.' }) end
    busy = true
    local current = session
    local ok, allowed = pcall(OR.Callback.await, 'access')
    busy = false
    if not ok or not allowed then restore(current); hide(); return cb({ error='Permissao indisponivel ou revogada.' }) end
    if session ~= current or not visible or not driver(current) then return cb({ error='O veiculo de teste mudou.' }) end
    -- Valida relacoes antes de chamar a native. Nao altera campos desconhecidos ou flags.
    if field.key == 'fTractionCurveMin' and value >= read(current.vehicle, fields.fTractionCurveMax)
        or field.key == 'fTractionCurveMax' and value <= read(current.vehicle, fields.fTractionCurveMin) then
        return cb({ error='Aderencia maxima deve ser maior que a minima.' })
    end
    local success = pcall(write, current.vehicle, field, value)
    if not success then return cb({ error='Nao foi possivel aplicar este campo.' }) end
    local actual = read(current.vehicle, field)
    current.changed[field.key] = actual
    cb({ value=actual })
end)

RegisterNUICallback('restore', function(_, cb)
    if busy or not driver(session) then return cb({ error='Aguarde a aplicacao e permaneça no carro.' }) end
    restore(session)
    cb(payload())
end)

RegisterNUICallback('drive', function(_, cb)
    if busy then return cb({ error='Aguarde a aplicacao.' }) end
    hide()
    OR.Notify(('Teste o carro. /%s reabre os ajustes. Ao sair do carro, os valores serao restaurados.'):format(HandlingEditor.Command), 'info')
    cb({ ok=true })
end)

RegisterNUICallback('close', function(_, cb)
    restore(session)
    hide()
    session = nil
    cb({ ok=true })
end)

CreateThread(function()
    while true do
        Wait(500)
        if session and (not driver(session) or IsEntityDead(PlayerPedId())) then
            restore(session)
            session = nil
            hide()
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    restore(session)
    if visible then SetNuiFocus(false, false) end
end)
