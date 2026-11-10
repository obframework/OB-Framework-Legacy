local resource = GetCurrentResourceName()
local locations, states, entities = {}, {}, {}
local opened, editorOpen, busy = false, false, false
local visualOverride = {}
local myTransaction
local machineInteraction

local function notify(message, kind)
    OR.Notify(message, kind or 'info')
end

local function requestModel(modelName)
    local model = joaat(modelName)
    if not IsModelInCdimage(model) then return nil end
    RequestModel(model)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(25) end
    return HasModelLoaded(model) and model or nil
end

local function requestAnim(dictionary)
    RequestAnimDict(dictionary)
    local deadline = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dictionary) and GetGameTimer() < deadline do Wait(25) end
    return HasAnimDictLoaded(dictionary)
end

local function machineStatus(id)
    return visualOverride[id] or (states[id] and states[id].status) or 'idle'
end

local function removeEntityTarget(key)
    if GetResourceState('ob_target') == 'started' then
        pcall(function() exports.ob_target:RemoveEntityOption(key) end)
    end
end

local function removeZoneTarget(key)
    if GetResourceState('ob_target') == 'started' then
        pcall(function() exports.ob_target:UnregisterZone(key) end)
    end
end

local function deleteEntry(id)
    local entry = entities[id]
    if not entry then return end
    removeEntityTarget(('ob_moneywash:ped:%s'):format(id))
    if entry.ped and DoesEntityExist(entry.ped) then DeleteEntity(entry.ped) end
    for machineId, machineEntry in pairs(entry.machines or {}) do
        removeZoneTarget(('ob_moneywash:machine:%s'):format(machineId))
        if machineEntry.object and DoesEntityExist(machineEntry.object) then DeleteEntity(machineEntry.object) end
    end
    entities[id] = nil
end

local function openInteraction(id)
    if opened or editorOpen or busy or IsNuiFocused() then return end
    busy = true
    CreateThread(function()
        local data, err = OR.Callback.awaitResource(resource, 'interaction', id)
        busy = false
        if not data then return notify(err or 'Lavagem indisponivel.', 'error') end
        opened = true
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'openWash', payload = data })
    end)
end

local function registerTargets(id)
    local entry, location = entities[id], locations[id]
    if not entry or not location or GetResourceState('ob_target') ~= 'started' then return end
    if entry.ped and DoesEntityExist(entry.ped) then
        exports.ob_target:RegisterEntity(('ob_moneywash:ped:%s'):format(id), entry.ped, {
            label = 'Falar sobre lavagem', icon = '$', distance = OBMoneyWash.InteractionDistance,
            action = function(entity) if entity == entry.ped then openInteraction(id) end end,
        })
    end
    for _, machine in ipairs(location.machines or {}) do
        if machine.action then
            local targetKey = ('ob_moneywash:machine:%s'):format(machine.id)
            removeZoneTarget(targetKey)
            exports.ob_target:RegisterSphereZone(targetKey, {
                coords = vector3(machine.action.x, machine.action.y, machine.action.z),
                radius = OBMoneyWash.MachineTargetRadius or 1.6,
                option = {
                    label = 'Usar maquina reservada', icon = '$',
                    distance = OBMoneyWash.MachineInteractionDistance or 1.35,
                    canInteract = function()
                        if not myTransaction
                            or tonumber(myTransaction.machineId) ~= tonumber(machine.id)
                            or (myTransaction.status ~= 'reserved' and myTransaction.status ~= 'ready') then
                            return false
                        end
                        local playerCoords = GetEntityCoords(PlayerPedId())
                        local actionCoords = vector3(machine.action.x, machine.action.y, machine.action.z)
                        return #(playerCoords - actionCoords) <= (OBMoneyWash.MachineInteractionDistance or 1.35)
                    end,
                    action = function()
                        if machineInteraction then machineInteraction(machine.id) end
                    end,
                },
            })
        end
    end
end

local function desiredMachineModel(machine)
    local status = machineStatus(machine.id)
    if status == 'open' or status == 'ready' then return machine.openModel end
    if status == 'processing' then return machine.spinModel end
    return machine.model
end

local function spawnMachine(machine, entry, force)
    if not machine or not entry then return end
    entry.machines = entry.machines or {}
    local machineEntry = entry.machines[machine.id] or {}
    entry.machines[machine.id] = machineEntry
    local modelName = desiredMachineModel(machine)
    if not force and machineEntry.object and DoesEntityExist(machineEntry.object) and machineEntry.model == modelName then return end
    if machineEntry.object and DoesEntityExist(machineEntry.object) then DeleteEntity(machineEntry.object) end
    machineEntry.object = nil
    local model = requestModel(modelName)
    if not model then
        print(('[ob_moneywash] Modelo de maquina invalido: %s'):format(tostring(modelName)))
        return
    end
    local object = CreateObjectNoOffset(model, machine.x, machine.y, machine.z, false, false, false)
    if object and object ~= 0 then
        SetEntityHeading(object, machine.w)
        FreezeEntityPosition(object, true)
        SetEntityInvincible(object, true)
        SetEntityCollision(object, true, true)
        machineEntry.object, machineEntry.model = object, modelName
        if machineStatus(machine.id) == 'processing' then
            local animation = OBMoneyWash.MachineAnimation
            if requestAnim(animation.dictionary) then
                PlayEntityAnim(object, animation.clip, animation.dictionary, 8.0, true, true, false, 0.0, 0)
            end
        end
    end
    SetModelAsNoLongerNeeded(model)
end

local function spawnEntry(id)
    local location = locations[id]
    if not location or entities[id] then return end
    local entry = { machines = {} }
    entities[id] = entry
    local model = requestModel(location.ped.model)
    if model then
        local cfg = location.ped
        local ped = CreatePed(4, model, cfg.x, cfg.y, cfg.z - 1.0, cfg.w, false, false)
        if ped and ped ~= 0 then
            SetEntityInvincible(ped, true)
            FreezeEntityPosition(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            SetPedCanRagdoll(ped, false)
            TaskStartScenarioInPlace(ped, cfg.scenario or 'WORLD_HUMAN_CLIPBOARD', 0, true)
            entry.ped = ped
        end
        SetModelAsNoLongerNeeded(model)
    end
    for _, machine in ipairs(location.machines or {}) do spawnMachine(machine, entry, true) end
    registerTargets(id)
end

exports('IsServicePed', function(ped)
    for _, entry in pairs(entities) do if entry.ped == ped and DoesEntityExist(ped) then return true end end
    return false
end)

local function refreshMachine(machineId)
    for locationId, location in pairs(locations) do
        for _, machine in ipairs(location.machines or {}) do
            if tonumber(machine.id) == tonumber(machineId) and entities[locationId] then
                spawnMachine(machine, entities[locationId], false)
                registerTargets(locationId)
                return
            end
        end
    end
end

RegisterNetEvent('ob_moneywash:client:state', function(state)
    if type(state) ~= 'table' or not tonumber(state.machineId) then return end
    local id = tonumber(state.machineId)
    states[id] = state
    if myTransaction and tonumber(myTransaction.machineId) == id then
        if state.status == 'idle' then myTransaction = nil
        else
            myTransaction.status = state.status
            myTransaction.endsAt = state.endsAt or myTransaction.endsAt
            myTransaction.remainingSeconds = state.remainingSeconds
            if tonumber(state.transactionId) and tonumber(state.transactionId) > 0 then myTransaction.id = tonumber(state.transactionId) end
        end
    end
    refreshMachine(id)
    if opened then SendNUIMessage({ action = 'state', payload = state }) end
end)

local function setLocations(rows)
    local incoming = {}
    for _, location in ipairs(rows or {}) do
        location.id = tonumber(location.id)
        for _, machine in ipairs(location.machines or {}) do machine.id = tonumber(machine.id) end
        incoming[location.id] = location
    end
    for id in pairs(locations) do if not incoming[id] then deleteEntry(id) end end
    locations = incoming
end

RegisterNetEvent('ob_moneywash:client:bootstrap', setLocations)
RegisterNetEvent('ob_moneywash:client:locationSaved', function(location)
    if type(location) ~= 'table' or not tonumber(location.id) then return end
    location.id = tonumber(location.id)
    for _, machine in ipairs(location.machines or {}) do machine.id = tonumber(machine.id) end
    deleteEntry(location.id)
    locations[location.id] = location
    if editorOpen then SendNUIMessage({ action = 'editorSaved', payload = location }) end
end)
RegisterNetEvent('ob_moneywash:client:locationDeleted', function(rawId)
    local id = tonumber(rawId)
    local location = locations[id]
    for _, machine in ipairs(location and location.machines or {}) do states[machine.id] = nil end
    deleteEntry(id)
    locations[id] = nil
    if editorOpen then SendNUIMessage({ action = 'editorDeleted', id = id }) end
end)

local function closeUi()
    opened, editorOpen = false, false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function findMachine(machineId)
    for _, location in pairs(locations) do
        for _, machine in ipairs(location.machines or {}) do
            if tonumber(machine.id) == tonumber(machineId) then return machine, location end
        end
    end
end

local function positionForAction(machine)
    local ped = PlayerPedId()
    local action = machine.action
    TaskGoStraightToCoord(ped, action.x, action.y, action.z, 0.8, 5000, action.w, 0.15)
    local deadline = GetGameTimer() + 5200
    while GetGameTimer() < deadline and #(GetEntityCoords(ped) - vector3(action.x, action.y, action.z)) > 0.5 do Wait(50) end
    ClearPedTasks(ped)
    if #(GetEntityCoords(ped) - vector3(action.x, action.y, action.z)) > 0.65 then return false end
    TaskTurnPedToFaceCoord(ped, machine.x, machine.y, machine.z + 0.5, 700)
    Wait(750)
    ClearPedTasks(ped)
    return true
end

local function cashProp(ped)
    local model = requestModel(OBMoneyWash.HandMoneyProp or 'prop_money_bag_01')
    if not model then return nil end
    local object = CreateObject(model, 0.0, 0.0, 0.0, false, false, false)
    if object and object ~= 0 then
        AttachEntityToEntity(object, ped, GetPedBoneIndex(ped, 57005), 0.10, 0.00, -0.04, -85.0, 5.0, 10.0,
            true, true, false, true, 1, true)
    end
    SetModelAsNoLongerNeeded(model)
    return object
end

local function machineSequence(machine, collecting)
    local ped, id = PlayerPedId(), machine.id
    if not positionForAction(machine) then
        notify('Nao foi possivel chegar na posicao da animacao. Aproxime-se e tente novamente.', 'error')
        return false
    end
    FreezeEntityPosition(ped, true)
    visualOverride[id] = 'open'
    refreshMachine(id)
    local object = cashProp(ped)
    local dictionary, clip = 'mp_common', 'givetake1_a'
    if requestAnim(dictionary) then TaskPlayAnim(ped, dictionary, clip, 4.0, -4.0, 1900, 0, 0.0, false, false, false) end
    Wait(1850)
    ClearPedTasks(ped)
    if object and DoesEntityExist(object) then DeleteEntity(object) end
    FreezeEntityPosition(ped, false)
    visualOverride[id] = nil
    refreshMachine(id)
    return true
end

RegisterNUICallback('close', function(_, cb) closeUi(); cb({ ok = true }) end)

RegisterNUICallback('start', function(data, cb)
    if busy then return cb({ ok = false, error = 'Aguarde a operacao atual.' }) end
    local id = tonumber(data and data.locationId)
    local location = id and locations[id]
    if not location then return cb({ ok = false, error = 'Lavagem indisponivel.' }) end
    busy = true
    local transaction, err = OR.Callback.awaitResource(resource, 'start', id, data and data.amount)
    if not transaction then busy = false; return cb({ ok = false, error = err }) end
    myTransaction = transaction
    closeUi()
    busy = false
    notify(('Maquina reservada. Siga o marcador amarelo e use o target para colocar $%s.'):format(
        transaction.dirtyAmount), 'success')
    cb({ ok = true, transaction = transaction })
end)

machineInteraction = function(machineId)
    if busy or not myTransaction or tonumber(myTransaction.machineId) ~= tonumber(machineId) then return end
    local machine = findMachine(machineId)
    if not machine then return notify('Maquina indisponivel.', 'error') end
    local collecting = myTransaction.status == 'ready'
    if not collecting and myTransaction.status ~= 'reserved' then return end
    busy = true
    CreateThread(function()
        if not machineSequence(machine, collecting) then busy = false; return end
        if not collecting then
            local transaction, err = OR.Callback.awaitResource(resource, 'deposit', machineId)
            busy = false
            if not transaction then return notify(err or 'Nao foi possivel colocar o dinheiro.', 'error') end
            myTransaction = transaction
            return notify(('Dinheiro colocado. Comprovante %s; voce recebera $%s.'):format(
                transaction.receipt or ('#' .. transaction.id), transaction.cleanAmount), 'success')
        end
        local result, err = OR.Callback.awaitResource(resource, 'collect', machineId)
        busy = false
        if not result then return notify(err or 'Nao foi possivel retirar o dinheiro.', 'error') end
        myTransaction = nil
        if result.confirmed == false then
            notify(('O servidor nao confirmou o saldo de $%s. O caso foi bloqueado para revisao; guarde %s.'):format(
                result.amount, result.receipt or '-'), 'warning')
        else
            notify(('Voce recebeu $%s limpos. Taxa: $%s. Comprovante: %s.'):format(
                result.amount, result.commission, result.receipt or '-'), 'success')
        end
    end)
end

local function openEditor()
    if opened or editorOpen or busy or IsNuiFocused() then return end
    busy = true
    CreateThread(function()
        local data, err = OR.Callback.awaitResource(resource, 'adminData')
        busy = false
        if not data then return notify(err or 'Editor indisponivel.', 'error') end
        editorOpen = true
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'openEditor', payload = data })
    end)
end

RegisterNetEvent('ob_moneywash:client:openEditor', openEditor)
RegisterCommand(OBMoneyWash.Command or 'lavagemeditor', openEditor, false)

RegisterNUICallback('capture', function(data, cb)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local z = coords.z
    local heading = GetEntityHeading(ped)
    if data and data.kind == 'machine' then
        z = z + (tonumber(OBMoneyWash.MachineCaptureZOffset) or -1.0)
        heading = (heading + (tonumber(OBMoneyWash.MachineCaptureHeadingOffset) or 180.0)) % 360.0
    end
    cb({ ok = true, coords = { x = coords.x, y = coords.y, z = z, w = heading } })
end)

RegisterNUICallback('placeMachine', function(data, cb)
    local model = requestModel(data and data.model or OBMoneyWash.Default.machineModel)
    if not model then return cb({ ok = false, error = 'Modelo da maquina invalido.' }) end
    local ped = PlayerPedId()
    local pedCoords, heading = GetEntityCoords(ped), GetEntityHeading(ped)
    local raw = type(data.coords) == 'table' and data.coords or {}
    local x = tonumber(raw.x) or pedCoords.x
    local y = tonumber(raw.y) or pedCoords.y
    local z = tonumber(raw.z) or (pedCoords.z + (tonumber(OBMoneyWash.MachineCaptureZOffset) or -1.0))
    heading = tonumber(raw.w) or ((heading + (tonumber(OBMoneyWash.MachineCaptureHeadingOffset) or 180.0)) % 360.0)
    local preview = CreateObjectNoOffset(model, x, y, z, false, false, false)
    if not preview or preview == 0 then SetModelAsNoLongerNeeded(model); return cb({ ok = false, error = 'Nao foi possivel criar a previa.' }) end
    SetEntityAlpha(preview, 190, false)
    SetEntityCollision(preview, false, false)
    FreezeEntityPosition(preview, true)
    SetEntityHeading(preview, heading)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'placementVisibility', visible = false })
    notify('Setas cima/baixo movem; esquerda/direita giram; PageUp/PageDown ajustam altura; ENTER confirma; BACKSPACE cancela.', 'info')

    local confirmed = false
    while DoesEntityExist(preview) do
        DisableControlAction(0, 172, true); DisableControlAction(0, 173, true)
        DisableControlAction(0, 174, true); DisableControlAction(0, 175, true)
        DisableControlAction(0, 10, true); DisableControlAction(0, 11, true)
        DisableControlAction(0, 191, true); DisableControlAction(0, 194, true)
        local radians = math.rad(heading)
        local forwardX, forwardY = -math.sin(radians), math.cos(radians)
        if IsDisabledControlPressed(0, 172) then x, y = x + forwardX * 0.025, y + forwardY * 0.025 end
        if IsDisabledControlPressed(0, 173) then x, y = x - forwardX * 0.025, y - forwardY * 0.025 end
        if IsDisabledControlPressed(0, 174) then heading = (heading + 1.0) % 360.0 end
        if IsDisabledControlPressed(0, 175) then heading = (heading - 1.0) % 360.0 end
        if IsDisabledControlPressed(0, 10) then z = z + 0.015 end
        if IsDisabledControlPressed(0, 11) then z = z - 0.015 end
        SetEntityCoordsNoOffset(preview, x, y, z, false, false, false)
        SetEntityHeading(preview, heading)
        DrawMarker(0, x, y, z + 2.85, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            0.22, 0.22, 0.18, 255, 205, 35, 210, false, false, 2, false, nil, nil, false)
        if IsDisabledControlJustPressed(0, 191) then confirmed = true; break end
        if IsDisabledControlJustPressed(0, 194) then break end
        Wait(0)
    end
    if DoesEntityExist(preview) then DeleteEntity(preview) end
    SetModelAsNoLongerNeeded(model)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'placementVisibility', visible = true })
    if not confirmed then return cb({ ok = false, cancelled = true }) end
    cb({ ok = true, coords = { x = x, y = y, z = z, w = heading } })
end)

RegisterNUICallback('adminSave', function(data, cb)
    local saved, message = OR.Callback.awaitResource(resource, 'adminSave', data)
    cb(saved and { ok = true, data = saved, message = message } or { ok = false, error = message })
end)

RegisterNUICallback('adminDelete', function(data, cb)
    local ok, message = OR.Callback.awaitResource(resource, 'adminDelete', data and data.id)
    cb({ ok = ok == true, message = ok and message or nil, error = ok and nil or message })
end)

RegisterNUICallback('adminTeleport', function(data, cb)
    local coords, err = OR.Callback.awaitResource(resource, 'adminTeleport', data and data.id)
    if coords then SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z, false, false, false) end
    cb({ ok = coords ~= nil, error = err })
end)

RegisterNUICallback('adminLogs', function(data, cb)
    local result, err = OR.Callback.awaitResource(resource, 'adminLogs', data or {})
    cb(result and { ok = true, data = result } or { ok = false, error = err })
end)

RegisterNUICallback('adminLogDetails', function(data, cb)
    local result, err = OR.Callback.awaitResource(resource, 'adminLogDetails', data and data.id)
    cb(result and { ok = true, data = result } or { ok = false, error = err })
end)

AddEventHandler('ob_target:client:ready', function()
    for id in pairs(entities) do registerTargets(id) end
end)

CreateThread(function()
    while LocalPlayer.state['or:loaded'] ~= true do Wait(250) end
    local data, err = OR.Callback.awaitResource(resource, 'locations')
    if not data then return print(('[ob_moneywash] Falha ao carregar locais: %s'):format(tostring(err))) end
    setLocations(data.locations)
    for _, state in ipairs(data.states or {}) do states[tonumber(state.machineId)] = state end
    myTransaction = data.transaction
    while true do
        local coords = GetEntityCoords(PlayerPedId())
        for id, location in pairs(locations) do
            local distance = #(coords - vector3(location.ped.x, location.ped.y, location.ped.z))
            if distance <= OBMoneyWash.StreamInDistance then
                if not entities[id] then spawnEntry(id) end
            elseif distance >= OBMoneyWash.StreamOutDistance then
                deleteEntry(id)
            end
        end
        Wait(1000)
    end
end)

CreateThread(function()
    while true do
        local wait = 500
        local playerCoords = GetEntityCoords(PlayerPedId())
        for _, location in pairs(locations) do
            for _, machine in ipairs(location.machines or {}) do
                local distance = #(playerCoords - vector3(machine.x, machine.y, machine.z))
                if distance <= 35.0 then
                    local state = states[machine.id]
                    local assigned = myTransaction and tonumber(myTransaction.machineId) == tonumber(machine.id)
                    local occupied = state and state.status and state.status ~= 'idle'
                    if assigned or occupied then
                        wait = 0
                        local red, green, blue = assigned and 255 or 220, assigned and 195 or 45, assigned and 25 or 55
                        local markerZ = math.max(machine.z + 2.85, (machine.action and machine.action.z or machine.z) + 1.85)
                        DrawMarker(0, machine.x, machine.y, markerZ, 0.0, 0.0, 0.0,
                            0.0, 0.0, 0.0, 0.24, 0.24, 0.2, red, green, blue, 210,
                            false, false, 2, false, nil, nil, false)
                    end
                end
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onClientResourceStop', function(name)
    if name ~= resource then return end
    closeUi()
    for id in pairs(entities) do deleteEntry(id) end
end)

