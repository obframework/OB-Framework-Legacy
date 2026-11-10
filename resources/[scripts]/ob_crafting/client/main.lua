local resource = GetCurrentResourceName()
local zones, visuals, visualSpawning, openStation, crafting = {}, {}, {}, nil, false

local function notify(message, kind) OR.Notify(message, kind or 'info') end

local function closePanel()
    openStation = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function openPanel(stationId)
    if crafting or LocalPlayer.state['or:downed'] or IsPedInAnyVehicle(PlayerPedId(), false) then return end
    local data, message = OR.Callback.await('panel', stationId)
    if not data then return notify(message or 'Bancada indisponivel.', 'error') end
    openStation = stationId
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', payload = data })
end

local function clearTargets()
    if GetResourceState('ob_target') == 'started' then
        for _, id in ipairs(zones) do exports.ob_target:UnregisterZone(id) end
    end
    zones = {}
end

local function clearVisuals()
    for _, entity in pairs(visuals) do
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
    visuals = {}
end

local function clearVisual(stationId)
    local entity = visuals[stationId]
    if entity and DoesEntityExist(entity) then DeleteEntity(entity) end
    visuals[stationId] = nil
end

exports('IsServicePed', function(ped)
    if not ped or ped == 0 then return false end
    for _, entity in pairs(visuals) do
        if entity == ped and DoesEntityExist(entity) and IsEntityAPed(entity) then return true end
    end
    return false
end)

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(tostring(model or ''))
    if hash == 0 or not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function spawnVisual(stationId, station)
    if visualSpawning[stationId] or (visuals[stationId] and DoesEntityExist(visuals[stationId])) then return end
    local settings = station.visual
    if type(settings) ~= 'table' or not settings.model then return end
    visualSpawning[stationId] = true
    local hash = loadModel(settings.model)
    if not hash then
        print(('[ob_crafting] Modelo visual invalido: %s'):format(tostring(settings.model)))
        visualSpawning[stationId] = nil
        return
    end
    local coords = settings.coords or station.coords
    local heading = tonumber(settings.heading) or 0.0
    local collisionDeadline = GetGameTimer() + 4000
    local groundReady = false
    repeat
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        RequestAdditionalCollisionAtCoord(coords.x, coords.y, coords.z)
        groundReady = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 5.0, false)
        if not groundReady then Wait(100) end
    until groundReady or GetGameTimer() >= collisionDeadline

    if #(GetEntityCoords(PlayerPedId()) - coords) > (Crafting.visualDespawnDistance or 110.0) then
        SetModelAsNoLongerNeeded(hash)
        visualSpawning[stationId] = nil
        return
    end
    local entity
    if settings.type == 'ped' then
        if not IsModelAPed(hash) then
            print(('[ob_crafting] Modelo nao e um ped: %s'):format(tostring(settings.model)))
        else
            entity = CreatePed(4, hash, coords.x, coords.y, coords.z, heading, false, false)
            SetBlockingOfNonTemporaryEvents(entity, true)
            SetEntityInvincible(entity, true)
            SetPedCanRagdoll(entity, false)
        end
    else
        entity = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)
        SetEntityHeading(entity, heading)
        if settings.placeOnGround == true then PlaceObjectOnGroundProperly(entity) end
        SetEntityCollision(entity, settings.collision ~= false, true)
    end
    if entity and entity ~= 0 then
        FreezeEntityPosition(entity, true)
        SetEntityAsMissionEntity(entity, true, true)
        visuals[stationId] = entity
    end
    SetModelAsNoLongerNeeded(hash)
    visualSpawning[stationId] = nil
end

local function rebuildTargets()
    clearTargets()
    clearVisuals()
    local targetReady = GetResourceState('ob_target') == 'started'
    for stationId, station in pairs(Crafting.stations) do
        if station.enabled ~= false then
            if targetReady then
                local id = resource .. ':' .. stationId
                exports.ob_target:RegisterSphereZone(id, {
                    coords = station.coords,
                    radius = station.radius or 1.2,
                    option = {
                        label = 'Usar ' .. station.label,
                        icon = station.icon or '🔧',
                        distance = Crafting.interactDistance,
                        canInteract = function()
                            return not crafting and not LocalPlayer.state['or:downed'] and not IsPedInAnyVehicle(PlayerPedId(), false)
                        end,
                        action = function() openPanel(stationId) end,
                    }
                })
                zones[#zones + 1] = id
            end
        end
    end
end


CreateThread(function()
    while true do
        local playerCoords = GetEntityCoords(PlayerPedId())
        for stationId, station in pairs(Crafting.stations) do
            local settings = station.enabled ~= false and station.visual or nil
            if type(settings) == 'table' and settings.model then
                local coords = settings.coords or station.coords
                local distance = #(playerCoords - coords)
                local entity = visuals[stationId]
                if entity and not DoesEntityExist(entity) then visuals[stationId] = nil end
                if distance <= (Crafting.visualStreamDistance or 80.0) then
                    if not visuals[stationId] and not visualSpawning[stationId] then
                        CreateThread(function() spawnVisual(stationId, station) end)
                    end
                elseif distance >= (Crafting.visualDespawnDistance or 110.0) then
                    clearVisual(stationId)
                end
            else
                clearVisual(stationId)
            end
        end
        Wait(1000)
    end
end)

RegisterNUICallback('close', function(_, cb) closePanel(); cb(true) end)

RegisterNUICallback('refresh', function(_, cb)
    local data, message = OR.Callback.await('panel', openStation)
    cb(data or { error = message or 'Nao foi possivel atualizar.' })
end)

RegisterNUICallback('craft', function(data, cb)
    if crafting then return cb({ ok = false, message = 'Ja existe uma fabricacao em andamento.' }) end
    local stationId = openStation
    local result, message = OR.Callback.await('begin', stationId, data and data.recipe, data and data.amount)
    if not result then return cb({ ok = false, message = message or 'Nao foi possivel iniciar.' }) end
    cb({ ok = true })
    closePanel()
    crafting = true
    local completed = true
    local steps = result.steps or { result.label }
    local duration = math.max(1000, math.floor((result.duration or 3000) / math.max(1, #steps)))
    for _, step in ipairs(steps) do
        if not OR.Progress.Run({
            label = step,
            duration = duration,
            canCancel = true,
            animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 },
        }) then completed = false break end
    end
    local ok, finalMessage = OR.Callback.await('finish', result.token, completed)
    crafting = false
    notify(finalMessage or (ok and 'Fabricacao concluida.' or 'Fabricacao interrompida.'), ok and 'success' or 'error')
end)

RegisterNetEvent(resource .. ':client:blueprint', function(message)
    if source ~= 65535 then return end
    notify(message, 'success')
end)

AddEventHandler('ob_target:client:ready', rebuildTargets)
AddEventHandler('onClientResourceStart', function(name)
    if name == resource or name == 'ob_target' then Wait(500); rebuildTargets() end
end)
AddEventHandler('onResourceStop', function(name)
    if name ~= resource then return end
    closePanel()
    clearTargets()
    clearVisuals()
end)
