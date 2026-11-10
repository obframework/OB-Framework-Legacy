local resource = GetCurrentResourceName()
local plants, entities, zones = {}, {}, {}
local busy, placing = false, false

local function notify(message, kind)
    OR.Notify(message, kind or 'info')
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(tostring(model or ''))
    if hash == 0 or not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function modelForPlant(plant)
    if not plant.kind then return DrugPlants.emptyPotModel end
    local settings = DrugPlants.types[plant.kind]
    if not settings then return DrugPlants.emptyPotModel end
    local selected = settings.models[1].model
    for _, stage in ipairs(settings.models) do
        if (tonumber(plant.growth) or 0) >= stage.growth then selected = stage.model end
    end
    return selected
end

local function targetLabel(plant)
    if not plant.kind then return 'Recolher vaso vazio' end
    if (tonumber(plant.health) or 0) <= 0 then return 'Remover planta morta' end
    if (tonumber(plant.growth) or 0) >= 100 then return 'Colher ' .. (DrugPlants.types[plant.kind].label or 'planta') end
    return ('Ver crescimento (%d%%)'):format(math.floor((tonumber(plant.growth) or 0) + 0.5))
end

local function clearPlant(id)
    local zoneId = zones[id]
    if zoneId and GetResourceState('ob_target') == 'started' then
        exports.ob_target:RemoveEntityOption(zoneId)
    end
    zones[id] = nil
    local entity = entities[id]
    if entity and DoesEntityExist(entity) then DeleteEntity(entity) end
    entities[id] = nil
end

local function clearAllPlants()
    local ids = {}
    for id in pairs(entities) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do clearPlant(id) end
end

local function cleanupOrphanedProps(rows)
    if not DrugPlants.cleanupOrphanedProps then return end
    local modelHashes = {
        [joaat(DrugPlants.emptyPotModel)] = true,
        [joaat(DrugPlants.emptyPotFallbackModel)] = true,
    }
    for _, settings in pairs(DrugPlants.types) do
        for _, stage in ipairs(settings.models or {}) do modelHashes[joaat(stage.model)] = true end
    end
    local active = {}
    for _, row in pairs(rows or {}) do
        local x, y, z = tonumber(row.x), tonumber(row.y), tonumber(row.z)
        if x and y and z then active[#active + 1] = vector3(x, y, z) end
    end
    local removed = 0
    for _, entity in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(entity) and IsEntityAMissionEntity(entity) and modelHashes[GetEntityModel(entity)] then
            local coords, represented = GetEntityCoords(entity), false
            for _, savedCoords in ipairs(active) do
                if #(coords - savedCoords) <= 1.5 then represented = true break end
            end
            if not represented then
                SetEntityAsMissionEntity(entity, true, true)
                DeleteEntity(entity)
                if not DoesEntityExist(entity) then removed = removed + 1 end
            end
        end
    end
    if removed > 0 then print(('[ob_drugplants] %s prop(s) órfão(s) removido(s).'):format(removed)) end
end

local function progress(label, duration, dict, clip)
    return OR.Progress.Run({
        label = label,
        duration = duration,
        canCancel = true,
        animation = { dict = dict or 'amb@world_human_gardener_plant@male@base', clip = clip or 'base', flag = 49 },
    })
end

local function interactPlant(id)
    if busy then return end
    local plant = plants[id]
    if not plant then return end
    local action = 'inspect'
    local duration, label = 0, nil
    if not plant.kind then
        action, duration, label = 'remove', DrugPlants.durations.remove, 'Recolhendo vaso'
    elseif (tonumber(plant.health) or 0) <= 0 then
        action, duration, label = 'remove', DrugPlants.durations.remove, 'Limpando planta morta'
    elseif (tonumber(plant.growth) or 0) >= 100 then
        action, duration, label = 'harvest', DrugPlants.durations.harvest, 'Colhendo planta'
    end
    if action ~= 'inspect' then
        busy = true
        local completed = progress(label, duration, 'amb@prop_human_bum_bin@base', 'base')
        if not completed then busy = false return end
    end
    local ok, message = OR.Callback.await('interact', id, action)
    busy = false
    notify(message or (ok and 'Ação concluída.' or 'Não foi possível cuidar desta planta.'), ok and 'success' or 'error')
end

local function spawnPlant(plant)
    local hash = loadModel(modelForPlant(plant))
    if not hash and not plant.kind then hash = loadModel(DrugPlants.emptyPotFallbackModel) end
    if not hash then
        print(('[ob_drugplants] Modelo inválido para a planta %s.'):format(tostring(plant.id)))
        return
    end
    local entity = CreateObjectNoOffset(hash, plant.x + 0.0, plant.y + 0.0, plant.z + 0.0, false, false, false)
    SetEntityHeading(entity, tonumber(plant.heading) or 0.0)
    PlaceObjectOnGroundProperly(entity)
    FreezeEntityPosition(entity, true)
    SetEntityCollision(entity, true, true)
    SetEntityAsMissionEntity(entity, true, true)
    entities[plant.id] = entity
    SetModelAsNoLongerNeeded(hash)

    if GetResourceState('ob_target') == 'started' then
        local zoneId = resource .. ':plant:' .. plant.id
        exports.ob_target:RegisterEntity(zoneId, entity, {
            label = targetLabel(plant),
            icon = '🌱',
            distance = DrugPlants.interactDistance,
            canInteract = function()
                return not busy and not placing and not LocalPlayer.state['or:downed'] and not IsPedInAnyVehicle(PlayerPedId(), false)
            end,
            action = function() interactPlant(plant.id) end,
        })
        zones[plant.id] = zoneId
    end
end

local function rebuildPlants(rows)
    clearAllPlants()
    plants = {}
    for _, row in pairs(rows or {}) do
        row.id = tonumber(row.id)
        row.x, row.y, row.z = tonumber(row.x), tonumber(row.y), tonumber(row.z)
        row.growth, row.water = tonumber(row.growth), tonumber(row.water)
        row.nutrients, row.health = tonumber(row.nutrients), tonumber(row.health)
        if row.id and row.x and row.y and row.z then
            plants[row.id] = row
            spawnPlant(row)
        end
    end
end

local function nearestPlant(maxDistance)
    local coords, selected, selectedDistance = GetEntityCoords(PlayerPedId()), nil, maxDistance or DrugPlants.interactDistance
    for id, plant in pairs(plants) do
        local distance = #(coords - vector3(plant.x, plant.y, plant.z))
        if distance <= selectedDistance then selected, selectedDistance = id, distance end
    end
    return selected
end

local function placementPosition(distance)
    local ped = PlayerPedId()
    local origin, forward = GetEntityCoords(ped), GetEntityForwardVector(ped)
    local x, y = origin.x + forward.x * distance, origin.y + forward.y * distance
    local found, ground = GetGroundZFor_3dCoord(x, y, origin.z + 2.0, false)
    return vector3(x, y, found and ground or origin.z - 1.0)
end

local function placePot(slot)
    if busy or placing then return end
    if IsPedInAnyVehicle(PlayerPedId(), false) or LocalPlayer.state['or:downed'] then
        return notify('Saia do veículo e fique em pé para posicionar o vaso.', 'error')
    end
    local hash = loadModel(DrugPlants.emptyPotModel)
    if not hash then hash = loadModel(DrugPlants.emptyPotFallbackModel) end
    if not hash then return notify('O modelo do vaso não está disponível.', 'error') end
    placing = true
    local heading, coords = GetEntityHeading(PlayerPedId()), placementPosition(1.6)
    local preview = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)
    SetEntityAlpha(preview, 180, false)
    SetEntityCollision(preview, false, false)
    FreezeEntityPosition(preview, true)
    SetModelAsNoLongerNeeded(hash)
    notify('Setas giram o vaso. E confirma e Backspace cancela.', 'info')

    local confirmed = false
    while placing do
        Wait(0)
        coords = placementPosition(1.6)
        SetEntityCoordsNoOffset(preview, coords.x, coords.y, coords.z, false, false, false)
        SetEntityHeading(preview, heading)
        DrawMarker(0, coords.x, coords.y, coords.z + 0.75, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0,
            0.18, 0.18, 0.18, 30, 200, 110, 150, false, false, 2, false, nil, nil, false)
        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        if IsControlPressed(0, 174) then heading = heading + 1.5 end
        if IsControlPressed(0, 175) then heading = heading - 1.5 end
        if IsControlJustPressed(0, 38) then confirmed, placing = true, false end
        if IsControlJustPressed(0, 177) then placing = false end
    end
    if DoesEntityExist(preview) then DeleteEntity(preview) end
    if not confirmed then return end
    busy = true
    if not progress('Posicionando vaso', DrugPlants.durations.place) then busy = false return end
    local ok, message = OR.Callback.await('place', { x = coords.x, y = coords.y, z = coords.z, heading = heading, slot = slot })
    busy = false
    notify(message or (ok and 'Vaso posicionado.' or 'Não foi possível posicionar o vaso.'), ok and 'success' or 'error')
end

local function useCareItem(itemName, slot)
    if busy or placing then return end
    local id = nearestPlant(DrugPlants.interactDistance)
    if not id then return notify('Não há um vaso seu perto o bastante.', 'error') end
    local plant = plants[id]
    if (itemName == 'weed_seed' or itemName == 'coca_seed') and plant.kind then
        return notify('Esse vaso já possui uma planta.', 'error')
    end
    if itemName ~= 'weed_seed' and itemName ~= 'coca_seed' and not plant.kind then
        return notify('Plante uma semente antes de cuidar do vaso.', 'error')
    end
    local label, duration, dict, clip = 'Cuidando da planta', 5000, nil, nil
    if itemName == DrugPlants.items.wateringCan then
        label, duration, dict, clip = 'Regando planta', DrugPlants.durations.water, 'timetable@gardener@filling_can', 'gar_ig_5_filling_can'
    elseif itemName == DrugPlants.items.fertilizer then
        label, duration = 'Aplicando fertilizante', DrugPlants.durations.fertilize
    else
        label, duration = 'Plantando semente', DrugPlants.durations.plant
    end
    busy = true
    local completed = progress(label, duration, dict, clip)
    if not completed then busy = false return end
    local ok, message = OR.Callback.await('applyItem', id, itemName, slot)
    busy = false
    notify(message or (ok and 'Planta cuidada.' or 'Não foi possível cuidar da planta.'), ok and 'success' or 'error')
end

RegisterNetEvent(resource .. ':client:useItem', function(itemName, slot)
    if source ~= 65535 then return end
    if itemName == DrugPlants.items.pot then placePot(slot) else useCareItem(itemName, slot) end
end)

RegisterNetEvent(resource .. ':client:sync', function(rows)
    if source ~= 65535 then return end
    rebuildPlants(rows)
end)

AddEventHandler('ob_target:client:ready', function() rebuildPlants(plants) end)

AddEventHandler('onClientResourceStart', function(name)
    if name == resource then
        Wait(750)
        local rows = OR.Callback.await('list')
        cleanupOrphanedProps(rows or {})
        rebuildPlants(rows or {})
    elseif name == 'ob_target' then
        Wait(500)
        rebuildPlants(plants)
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= resource then return end
    placing = false
    clearAllPlants()
end)

