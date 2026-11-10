local open = false
local modules = {}
local entityLaser = false
local lastLaserCopy = ''
local laserHit, laserCoords, laserEntity = false, vector3(0.0, 0.0, 0.0), 0
local laserOrigin = vector3(0.0, 0.0, 0.0)
local nextLaserScan = 0
local laserModel = 0
local LASER_DISTANCE = 2.0
local laserScanErrorLogged = false

local knownArchetypes = {}
local function hashKey(value)
    return (tonumber(value) or 0) % 4294967296
end
for _, modelName in ipairs({
    'prop_traffic_01a', 'prop_traffic_01b', 'prop_traffic_01d',
    'prop_traffic_02a', 'prop_traffic_02b',
    'prop_traffic_03a', 'prop_traffic_03b',
    'prop_traffic_lightset_01',
}) do
    knownArchetypes[hashKey(joaat(modelName))] = modelName
end

CreateThread(function()
    local content = LoadResourceFile(GetCurrentResourceName(), 'data/object_names.txt')
    if not content then
        print('[ob_adminmenu] Catalogo de nomes de objetos indisponivel.')
        return
    end
    local count = 0
    for name in content:gmatch('[^\r\n]+') do
        name = name:match('^%s*(.-)%s*$')
        if name:match('^[%w_]+$') then
            local hash = hashKey(joaat(name))
            if not knownArchetypes[hash] then knownArchetypes[hash] = name end
            count = count + 1
            if count % 1000 == 0 then Wait(0) end
        end
    end
    print(('[ob_adminmenu] %d nomes de objetos carregados para o laser.'):format(count))
end)

local function round(value, decimals)
    local power = 10 ^ (decimals or 2)
    return math.floor((tonumber(value) or 0) * power + 0.5) / power
end

local function rotationToDirection(rotation)
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
    return vector3(-math.sin(yaw) * math.abs(math.cos(pitch)),
        math.cos(yaw) * math.abs(math.cos(pitch)), math.sin(pitch))
end

local function raycastEntity(origin, destination, ped)
    local handle = StartExpensiveSynchronousShapeTestLosProbe(
        origin.x, origin.y, origin.z, destination.x, destination.y, destination.z,
        -1, ped, 7
    )
    local _, hit, coords, _, entity = GetShapeTestResult(handle)
    if (hit == true or hit == 1) and entity and entity ~= 0 and DoesEntityExist(entity) then
        return entity, coords
    end
    return 0, nil
end

local function laserEndpoint(origin, direction, contact)
    if not contact then return origin + direction * 1.2 end
    local dx, dy, dz = contact.x - origin.x, contact.y - origin.y, contact.z - origin.z
    local length = math.sqrt(dx * dx + dy * dy + dz * dz)
    if length <= LASER_DISTANCE then return contact end
    local scale = LASER_DISTANCE / length
    return origin + vector3(dx * scale, dy * scale, dz * scale)
end

local function cameraPointNearPed(camera, direction, center, forward)
    -- Intersecao da mira da camera com uma esfera de 2 m ao redor do ped.
    -- Mantem a bolinha na mira real da terceira pessoa, sem alcancar o mapa todo.
    local offset = camera - center
    local b = offset.x * direction.x + offset.y * direction.y + offset.z * direction.z
    local c = offset.x * offset.x + offset.y * offset.y + offset.z * offset.z - LASER_DISTANCE ^ 2
    local discriminant = b * b - c
    if discriminant >= 0.0 then
        local distance = -b + math.sqrt(discriminant)
        if distance > 0.0 then
            local point = camera + direction * distance
            local relative = point - center
            if relative.x * forward.x + relative.y * forward.y >= 0.0 then return point end
        end
    end
    return center + forward * 1.2
end

local function cameraLaser(ped, pedCoords)
    local forward = GetEntityForwardVector(ped)
    local cameraDirection = rotationToDirection(GetGameplayCamRot(2))
    local horizontal = math.sqrt(cameraDirection.x ^ 2 + cameraDirection.y ^ 2)
    local cameraInFront = horizontal > 0.001
        and (cameraDirection.x * forward.x + cameraDirection.y * forward.y) / horizontal >= 0.35
    local direction = cameraInFront and cameraDirection or forward
    local origin = pedCoords + vector3(0.0, 0.0, 0.8)
    local camera = GetGameplayCamCoord()
    local endpoint = cameraInFront and cameraPointNearPed(camera, cameraDirection, origin, forward)
        or origin + forward * 1.2
    if not cameraInFront then return origin, endpoint, 0 end

    local function nearbyInFront(entity, contact)
        if entity == 0 or not contact then return false end
        local dx, dy, dz = contact.x - pedCoords.x, contact.y - pedCoords.y, contact.z - pedCoords.z
        local distance2 = dx * dx + dy * dy + dz * dz
        local horizontalDistance = math.sqrt(dx * dx + dy * dy)
        return distance2 <= 9.0 and dx * forward.x + dy * forward.y >= horizontalDistance * 0.25
    end

    -- Primeiro a mira da camera, como no laser original. O filtro do ped
    -- impede selecionar objetos ao lado/atras ou muito longe.
    local entity, contact = raycastEntity(camera, camera + cameraDirection * 12.0, ped)
    if nearbyInFront(entity, contact) then return origin, laserEndpoint(origin, direction, contact), entity end

    -- A camera em terceira pessoa pode passar por cima de um prop colado.
    -- Este segundo raio usa a mesma direcao do mouse, partindo do ped.
    entity, contact = raycastEntity(origin - direction * 0.3, origin + direction * 2.5, ped)
    if nearbyInFront(entity, contact) then return origin, laserEndpoint(origin, direction, contact), entity end
    return origin, endpoint, 0
end

local function entityTypeName(entity)
    if IsEntityAVehicle(entity) then return 'Veiculo' end
    if IsEntityAPed(entity) then return IsPedAPlayer(entity) and 'Jogador' or 'Ped' end
    if IsEntityAnObject(entity) then return 'Prop / objeto' end
    return 'Entidade'
end

local function archetypeName(entity, model)
    local ok, value = pcall(function() return GetEntityArchetypeName(entity) end)
    if ok and type(value) == 'string' and value ~= '' then return value end
    local knownName = knownArchetypes[hashKey(model)]
    if knownName then return knownName end
    if IsEntityAVehicle(entity) then
        local display = GetDisplayNameFromVehicleModel(model)
        if display and display ~= '' and display ~= 'CARNOTFOUND' then return display:lower() end
    end
    return 'nome indisponivel'
end

local function drawBoundingBox(entity, model)
    local minimum, maximum = GetModelDimensions(model)
    local points = {
        GetOffsetFromEntityInWorldCoords(entity, minimum.x, minimum.y, minimum.z),
        GetOffsetFromEntityInWorldCoords(entity, maximum.x, minimum.y, minimum.z),
        GetOffsetFromEntityInWorldCoords(entity, maximum.x, maximum.y, minimum.z),
        GetOffsetFromEntityInWorldCoords(entity, minimum.x, maximum.y, minimum.z),
        GetOffsetFromEntityInWorldCoords(entity, minimum.x, minimum.y, maximum.z),
        GetOffsetFromEntityInWorldCoords(entity, maximum.x, minimum.y, maximum.z),
        GetOffsetFromEntityInWorldCoords(entity, maximum.x, maximum.y, maximum.z),
        GetOffsetFromEntityInWorldCoords(entity, minimum.x, maximum.y, maximum.z),
    }
    local edges = { {1,2},{2,3},{3,4},{4,1},{5,6},{6,7},{7,8},{8,5},{1,5},{2,6},{3,7},{4,8} }
    for index = 1, #edges do
        local a, b = points[edges[index][1]], points[edges[index][2]]
        DrawLine(a.x, a.y, a.z, b.x, b.y, b.z, 71, 205, 255, 230)
    end
end

local function disableEntityLaser()
    entityLaser = false
    laserHit, laserEntity, laserModel = false, 0, 0
    lastLaserCopy = ''
    SendNUIMessage({ action = 'laser', show = false })
end

local function enableEntityLaser()
    if entityLaser then return disableEntityLaser() end
    local allowed, errorMessage = OR.Callback.awaitResource('ob_adminmenu', 'authorizeTool', 'entity_laser')
    if not allowed then return OR.Notify(errorMessage or 'Sem permissao para usar o laser.', 'error') end
    entityLaser = true
    laserScanErrorLogged = false
    local ped = PlayerPedId()
    laserOrigin = GetEntityCoords(ped) + vector3(0.0, 0.0, 0.8)
    laserCoords = laserOrigin + GetEntityForwardVector(ped) * 1.2
    laserHit, laserEntity, laserModel, nextLaserScan = false, 0, 0, 0
    OR.Notify('Mira ativada. A bolinha marca o ponto; C copia e ESC fecha.', 'info')
end

local function closeMenu()
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
end

local function openMenu()
    if open or IsNuiFocused() or OBShopEditorActive then return end
    if entityLaser then disableEntityLaser() end
    local data, err = OR.Callback.awaitResource('ob_adminmenu', 'getMenu')
    if not data then return OR.Notify(err or 'Nao foi possivel abrir o menu.', 'error') end
    open = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'open', modules = data.modules or modules })
end

RegisterNUICallback('close', function(_, cb) closeMenu(); cb({ ok = true }) end)
RegisterNUICallback('action', function(data, cb)
    local id = data and data.id
    if id == 'register_editor' then
        closeMenu()
        TriggerEvent('ob_registerrobbery:editor')
    elseif id == 'panel' then
        closeMenu()
        TriggerServerEvent('ob_admin:server:requestOpen')
    elseif id == 'offline_players' then
        SendNUIMessage({ action = 'offlineOpen' })
    elseif id == 'org_admin' then
        closeMenu()
        TriggerServerEvent('ob_adminmenu:server:openOrg')
    elseif id == 'inventory_shop_editor' or id == 'appearance_store_editor' then
        closeMenu()
        TriggerEvent('ob_adminmenu:client:shopEditor', id == 'inventory_shop_editor' and 'inventory' or 'stores')
    elseif id == 'moneywash_editor' then
        closeMenu()
        TriggerEvent('ob_moneywash:client:openEditor')
    elseif id == 'doorlock_editor' then
        closeMenu()
        TriggerEvent('ob_doorlock:client:openEditor')
    elseif id == 'wallmap' then
        closeMenu()
        TriggerServerEvent('ob_admin:server:utility', 'wallmap')
    elseif id == 'heist_editor' then
        closeMenu()
        TriggerEvent('ob_editor:client:open','heist')
    elseif id == 'editor' then
        closeMenu()
        TriggerEvent('ob_editor:client:open')
    elseif id == 'carshop' then
        closeMenu()
        CreateThread(function()
            Wait(100)
            TriggerEvent('ob_carshop:client:openAdmin')
        end)
    elseif id == 'feedback' then
        closeMenu()
        CreateThread(function()
            Wait(100)
            TriggerEvent('ob_feedback:client:openAdmin')
        end)
    elseif id == 'entity_laser' then
        closeMenu()
        enableEntityLaser()
    elseif id == 'garage_admin' then
        SendNUIMessage({ action = 'garageOpen' })
    elseif id == 'garage_editor' then
        closeMenu()
        CreateThread(function()
            Wait(100)
            TriggerEvent('ob_garage:client:openAdmin')
        end)
    elseif id == 'blackout_admin' then
        SendNUIMessage({ action = 'blackoutOpen' })
    end
    cb({ ok = true })
end)

RegisterNUICallback('garageVehicles', function(data, cb)
    local result, errorMessage = OR.Callback.awaitResource('ob_adminmenu', 'garageVehicles', data and data.userId)
    cb({ ok = result ~= nil, data = result, error = errorMessage })
end)

RegisterNUICallback('garageGiveVehicle', function(data, cb)
    local model = type(data) == 'table' and tostring(data.model or ''):lower() or ''
    local hash = joaat(model)
    if model == '' or not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        return cb({ ok = false, error = 'Esse modelo de veiculo nao existe neste cliente.' })
    end
    local result, message = OR.Callback.awaitResource('ob_adminmenu', 'garageGiveVehicle', data)
    cb({ ok = result ~= nil, data = result, message = result and message or nil, error = result and nil or message })
end)

RegisterNUICallback('garageRemoveVehicle', function(data, cb)
    local result, message = OR.Callback.awaitResource('ob_adminmenu', 'garageRemoveVehicle', data)
    cb({ ok = result == true, message = result and message or nil, error = result and nil or message })
end)

RegisterNUICallback('laserCopied', function(_, cb)
    OR.Notify('Dados da entidade copiados.', 'success')
    cb({ ok = true })
end)

RegisterNUICallback('blackoutStatus', function(_, cb)
    if GetResourceState('ob_blackout') ~= 'started' then
        return cb({ ok = false, error = 'O sistema de energia esta indisponivel.' })
    end
    local result, errorMessage = OR.Callback.awaitResource('ob_blackout', 'adminStatus')
    cb({ ok = result ~= nil, data = result, error = errorMessage })
end)

RegisterNUICallback('blackoutSet', function(data, cb)
    if GetResourceState('ob_blackout') ~= 'started' then
        return cb({ ok = false, error = 'O sistema de energia esta indisponivel.' })
    end
    local result, errorMessage = OR.Callback.awaitResource('ob_blackout', 'adminSet', data and data.action)
    cb({ ok = result ~= nil, data = result, error = errorMessage })
end)

local function offlineCallback(name, data, cb)
    local result, message = OR.Callback.awaitResource('ob_adminmenu', name, data)
    cb({ ok = result ~= nil, data = result, message = result and message or nil, error = result and nil or message })
end

RegisterNUICallback('offlineBootstrap', function(_, cb) offlineCallback('offlineBootstrap', nil, cb) end)
RegisterNUICallback('offlineSearch', function(data, cb) offlineCallback('offlineSearch', data and data.query, cb) end)
RegisterNUICallback('offlineDetails', function(data, cb) offlineCallback('offlineDetails', data and data.userId, cb) end)
RegisterNUICallback('offlineSetRole', function(data, cb) offlineCallback('offlineSetRole', data, cb) end)
RegisterNUICallback('offlineBan', function(data, cb) offlineCallback('offlineBan', data, cb) end)
RegisterNUICallback('offlineUnban', function(data, cb) offlineCallback('offlineUnban', data and data.userId, cb) end)
RegisterNUICallback('offlineDeleteCharacter', function(data, cb) offlineCallback('offlineDeleteCharacter', data, cb) end)
RegisterNUICallback('offlineDeleteAccount', function(data, cb) offlineCallback('offlineDeleteAccount', data, cb) end)
RegisterNUICallback('offlineWipeStatus', function(_, cb) offlineCallback('offlineWipeStatus', nil, cb) end)
RegisterNUICallback('offlineWipe', function(data, cb) offlineCallback('offlineWipe', data, cb) end)

RegisterCommand('obadminmenu', openMenu, false)
RegisterKeyMapping('obadminmenu', 'Abrir menu administrativo OB', 'keyboard', 'F11')

exports('RegisterModule', function(entry)
    if type(entry) ~= 'table' or not entry.id or not entry.label then return false end
    modules[#modules + 1] = entry
    return true
end)

CreateThread(function()
    while true do
        if not entityLaser then
            Wait(400)
        else
            Wait(0)
            DisableControlAction(0, 26, true)
            local now = GetGameTimer()
            if now >= nextLaserScan then
                nextLaserScan = now + 100
                local ped = PlayerPedId()
                local pedCoords = GetEntityCoords(ped)
                local ok, origin, endpoint, entity = pcall(cameraLaser, ped, pedCoords)
                if ok then
                    laserOrigin, laserCoords, laserEntity = origin, endpoint, entity
                else
                    local forward = GetEntityForwardVector(ped)
                    laserOrigin = pedCoords + vector3(0.0, 0.0, 1.0)
                    laserCoords = laserOrigin + forward * LASER_DISTANCE
                    laserEntity = 0
                    if not laserScanErrorLogged then
                        print(('[ob_adminmenu] Laser: falha ao consultar objeto proximo: %s'):format(tostring(origin)))
                        laserScanErrorLogged = true
                    end
                end
                laserHit, laserModel = laserEntity ~= 0, 0
                local payload = {
                    type = 'Sem alvo', name = 'Nenhum objeto proximo', hash = '-',
                }
                if laserHit and laserEntity ~= 0 and DoesEntityExist(laserEntity) then
                    -- Nativos de entidade podem falhar se o alvo sair do streaming
                    -- entre o resultado do raycast e a leitura dos seus dados.
                    local ok, entityPayload, model = pcall(function()
                        local targetCoords = GetEntityCoords(laserEntity)
                        local rotation = GetEntityRotation(laserEntity, 2)
                        local targetModel = GetEntityModel(laserEntity)
                        local data = {
                            type = entityTypeName(laserEntity), name = archetypeName(laserEntity, targetModel), hash = targetModel,
                            netId = NetworkGetEntityIsNetworked(laserEntity) and NetworkGetNetworkIdFromEntity(laserEntity) or 0,
                            heading = round(GetEntityHeading(laserEntity), 3),
                            coords = ('%.4f, %.4f, %.4f'):format(targetCoords.x, targetCoords.y, targetCoords.z),
                            rotation = ('%.3f, %.3f, %.3f'):format(rotation.x, rotation.y, rotation.z),
                        }
                        if IsEntityAVehicle(laserEntity) then
                            data.plate = GetVehicleNumberPlateText(laserEntity):gsub('^%s+', ''):gsub('%s+$', '')
                            data.engine = round(GetVehicleEngineHealth(laserEntity), 1)
                            data.body = round(GetVehicleBodyHealth(laserEntity), 1)
                            data.fuel = round(GetVehicleFuelLevel(laserEntity), 1)
                        elseif IsEntityAPed(laserEntity) and IsPedAPlayer(laserEntity) then
                            local player = NetworkGetPlayerIndexFromPed(laserEntity)
                            data.sessionId = player ~= -1 and GetPlayerServerId(player) or nil
                        end
                        return data, targetModel
                    end)
                    if ok then
                        payload, laserModel = entityPayload, model
                        lastLaserCopy = json.encode(payload)
                    else
                        laserHit, laserEntity = false, 0
                    end
                end
                if laserEntity == 0 or laserModel == 0 then
                    lastLaserCopy = ''
                end
                SendNUIMessage({ action = 'laser', show = true, data = payload })
            end

            if laserCoords then
                DrawMarker(28, laserCoords.x, laserCoords.y, laserCoords.z,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    0.11, 0.11, 0.11, 71, 205, 255, laserHit and 240 or 170,
                    false, false, 2, false, nil, nil, false)
            end
            if laserHit and laserEntity ~= 0 and laserModel ~= 0 and DoesEntityExist(laserEntity) then
                pcall(drawBoundingBox, laserEntity, laserModel)
            end

            if IsDisabledControlJustReleased(0, 26) and lastLaserCopy ~= '' then
                SendNUIMessage({ action = 'laserCopy', text = lastLaserCopy })
            end
            if IsControlJustReleased(0, 200) or IsControlJustReleased(0, 177) then disableEntityLaser() end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
end)
