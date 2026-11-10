local isOpen = false
local noclipEnabled = false
local noclipEntity = 0
local noclipPed = 0
local noclipVehicle = 0
local wallEnabled = false
local wallMapEnabled = false
local wallMapBlips = {}

local function enableVehicleDamage(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    SetEntityInvincible(vehicle, false)
    SetEntityCanBeDamaged(vehicle, true)
    SetVehicleCanBeVisiblyDamaged(vehicle, true)
    SetVehicleEngineCanDegrade(vehicle, true)
end

local function setFocus(enabled)
    SetNuiFocus(enabled, enabled)
    SetNuiFocusKeepInput(false)
end

local function closePanel()
    if not isOpen then return end
    isOpen = false
    setFocus(false)
    SendNUIMessage({ action = 'close' })
end

local function refreshPanel()
    if not isOpen then return end

    local data, err = OR.Callback.await('listPlayers')
    if not data then
        OR.Notify(err or 'Nao foi possivel listar os jogadores.', 'error')
        return
    end

    SendNUIMessage({
        action = 'players',
        players = data.players or {},
        maxCharacterSlots = data.maxCharacterSlots or 1,
        permissions = data.permissions or {},
        roles = data.roles or {},
        role = data.role,
        roleLabel = data.roleLabel,
    })
end

-- Evento local: o criador assume o foco ao editar a propria aparencia.
AddEventHandler('ob_admin:client:closeForAppearance', closePanel)

local function openPanel()
    if isOpen then
        CreateThread(refreshPanel)
        return
    end

    if IsNuiFocused() then
        OR.Notify('Feche a interface atual antes de abrir o painel administrativo.', 'error')
        return
    end

    isOpen = true
    setFocus(true)
    SendNUIMessage({ action = 'open' })
    CreateThread(refreshPanel)
end

local function teleportTo(coords)
    if type(coords) ~= 'table' then return end

    local ped = PlayerPedId()
    local entity = ped
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
        entity = vehicle
    end

    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    SetEntityCoordsNoOffset(entity, coords.x, coords.y, coords.z, false, false, false, true)
    SetEntityHeading(entity, coords.heading or GetEntityHeading(entity))
end

local function healPlayer(revive)
    local ped = PlayerPedId()
    local vehicle, seat = GetVehiclePedIsIn(ped, false), nil
    if vehicle ~= 0 then
        for index = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
            if GetPedInVehicleSeat(vehicle, index) == ped then seat = index; break end
        end
    end
    if revive and IsEntityDead(ped) then
        local coords = GetEntityCoords(ped)
        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, GetEntityHeading(ped), 0, false, false)
        Wait(0)
        ped = PlayerPedId()
    end

    local maxHealth = GetEntityMaxHealth(ped)
    SetEntityHealth(ped, math.max(200, maxHealth))
    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)
    if vehicle == 0 then ClearPedTasksImmediately(ped)
    elseif seat ~= nil and DoesEntityExist(vehicle) and IsVehicleSeatFree(vehicle, seat) then SetPedIntoVehicle(ped, vehicle, seat) end
end

local function restorePlayer()
    healPlayer(true)
    local ped = PlayerPedId()
    SetPedArmour(ped, 100)
    RestorePlayerStamina(PlayerId(), 1.0)
end

local function fixVehicle()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        OR.Notify('Entre em um veiculo para restaura-lo.', 'error')
        return
    end

    SetVehicleFixed(vehicle)
    SetVehicleDeformationFixed(vehicle)
    SetVehicleUndriveable(vehicle, false)
    SetVehicleEngineHealth(vehicle, 1000.0)
    SetVehicleBodyHealth(vehicle, 1000.0)
    SetVehiclePetrolTankHealth(vehicle, 1000.0)
    SetVehicleDirtLevel(vehicle, 0.0)
    for wheel = 0, 7 do SetVehicleTyreFixed(vehicle, wheel) end
    if GetResourceState('ob_fuel') == 'started' then
        local called, restored, fuelError = pcall(function()
            return exports.ob_fuel:SetFuel(vehicle, 100.0)
        end)
        if not called or restored ~= true then
            OR.Notify(fuelError or 'O veiculo foi reparado, mas o combustivel nao foi sincronizado.', 'error')
        end
    else
        SetVehicleFuelLevel(vehicle, 100.0)
    end
    enableVehicleDamage(vehicle)
end

local function requestDelete(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    NetworkRequestControlOfEntity(vehicle)
    local deadline = GetGameTimer() + 1200
    while not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < deadline do
        NetworkRequestControlOfEntity(vehicle)
        Wait(0)
    end
    if not NetworkHasControlOfEntity(vehicle) then return false end

    -- Carros tirados de uma garagem possuem esta state bag. Antes de apagar,
    -- devolvemos o registro para a garagem com todos os dados atuais. Veiculos
    -- de NPC e temporarios nao possuem a marca e continuam sendo so removidos.
    if Entity(vehicle).state['ob:registered_vehicle'] == true and GetResourceState('ob_garage') == 'started' then
        local properties = {}
        local captured, result = pcall(function()
            return exports.ob_garage:CaptureProperties(vehicle)
        end)
        if captured and type(result) == 'table' then properties = result end

        local stored = OR.Callback.awaitResource('ob_garage', 'ob_garage:server:adminStoreBeforeDelete',
            NetworkGetNetworkIdFromEntity(vehicle), {
                fuel = GetVehicleFuelLevel(vehicle),
                body = GetVehicleBodyHealth(vehicle),
                engine = GetVehicleEngineHealth(vehicle),
            }, properties)
        -- Nunca apaga um carro proprio se a garagem nao confirmou o salvamento.
        -- Isso evita exatamente o veiculo ficar marcado como fora sem existir.
        if stored ~= true then
            OR.Notify('Nao foi possivel guardar este veiculo na garagem.', 'error')
            return false
        end
    elseif GetResourceState('ob_vehiclekeys') == 'started' then
        local prepared, keyError = OR.Callback.awaitResource('ob_vehiclekeys', 'prepareAdminDelete', NetworkGetNetworkIdFromEntity(vehicle))
        if prepared ~= true then
            OR.Notify(keyError or 'Nao foi possivel finalizar as chaves do veiculo.', 'error')
            return false
        end
    end

    SetEntityAsMissionEntity(vehicle, true, true)
    DeleteEntity(vehicle)
    return not DoesEntityExist(vehicle)
end

local function closestStreamedVehicle(coords, radius)
    local closest, closestDistance = 0, radius + 0.001
    for _, candidate in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(candidate) then
            local distance = #(GetEntityCoords(candidate) - coords)
            if distance < closestDistance then
                closest, closestDistance = candidate, distance
            end
        end
    end
    return closest
end

local function deleteVehicle()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        vehicle = closestStreamedVehicle(GetEntityCoords(ped), 8.0)
    end
    if requestDelete(vehicle) then
        OR.Notify('Veiculo removido.', 'success')
    else
        OR.Notify('Nenhum veiculo proximo pode ser removido.', 'error')
    end
end

local function deleteVehiclesArea()
    local origin = GetEntityCoords(PlayerPedId())
    local removed = 0
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) and #(GetEntityCoords(vehicle) - origin) <= 500.0 then
            local driver = GetPedInVehicleSeat(vehicle, -1)
            if driver == 0 and requestDelete(vehicle) then removed = removed + 1 end
        end
    end
    OR.Notify(('%s veiculo(s) vazio(s) removido(s) em 500 metros.'):format(removed), removed > 0 and 'success' or 'info')
end

local function cameraDirection()
    local rotation = GetGameplayCamRot(2)
    local z = math.rad(rotation.z)
    local x = math.rad(rotation.x)
    local horizontal = math.abs(math.cos(x))
    return vector3(-math.sin(z) * horizontal, math.cos(z) * horizontal, math.sin(x))
end

local function setNoclipEntityState(entity, enabled)
    if entity == 0 or not DoesEntityExist(entity) then return end

    SetEntityCollision(entity, not enabled, true)
    SetEntityHasGravity(entity, not enabled)
    SetEntityInvincible(entity, enabled)
    SetEntityVisible(entity, not enabled, false)

    if enabled then
        SetEntityAlpha(entity, 0, false)
        SetEntityVelocity(entity, 0.0, 0.0, 0.0)
    else
        SetEntityCompletelyDisableCollision(entity, false, true)
        SetEntityCollision(entity, true, true)
        SetEntityHasGravity(entity, true)
        SetEntityDynamic(entity, true)
        SetEntityVisible(entity, true, false)
        SetEntityAlpha(entity, 255, false)
        ResetEntityAlpha(entity)
        SetEntityVelocity(entity, 0.0, 0.0, 0.0)
    end
end

local function stopNoclip()
    noclipEnabled = false
    setNoclipEntityState(noclipVehicle, false)
    setNoclipEntityState(noclipPed, false)

    local currentPed = PlayerPedId()
    local currentVehicle = GetVehiclePedIsIn(currentPed, false)
    setNoclipEntityState(currentVehicle, false)
    setNoclipEntityState(currentPed, false)

    if currentPed ~= 0 and DoesEntityExist(currentPed) then
        SetPedCanRagdoll(currentPed, true)
        SetPedCanRagdollFromPlayerImpact(currentPed, true)
    end

    noclipEntity = 0
    noclipPed = 0
    noclipVehicle = 0
end

local function toggleNoclip()
    if noclipEnabled then
        stopNoclip()
        OR.Notify('Noclip desativado.', 'info')
        return
    end

    noclipEnabled = true
    OR.Notify('Noclip ativado. W/A/S/D move, Q sobe, Z desce e Shift acelera.', 'info')
    CreateThread(function()
        while noclipEnabled do
            Wait(0)
            if not noclipEnabled then break end
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            local isDriver = vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped
            local currentVehicle = isDriver and vehicle or 0
            local entity = currentVehicle ~= 0 and currentVehicle or ped

            if noclipPed ~= ped then
                setNoclipEntityState(noclipPed, false)
                noclipPed = ped
            end
            if noclipVehicle ~= currentVehicle then
                setNoclipEntityState(noclipVehicle, false)
                noclipVehicle = currentVehicle
            end

            noclipEntity = entity
            setNoclipEntityState(noclipPed, true)
            setNoclipEntityState(noclipVehicle, true)
            SetPedCanRagdoll(noclipPed, false)
            SetPedCanRagdollFromPlayerImpact(noclipPed, false)
            SetEntityVelocity(entity, 0.0, 0.0, 0.0)

            local direction = cameraDirection()
            local right = vector3(direction.y, -direction.x, 0.0)
            local movement = vector3(0.0, 0.0, 0.0)
            local speed = IsDisabledControlPressed(0, 21) and 4.5 or 1.35
            if IsDisabledControlPressed(0, 32) then movement = movement + direction end
            if IsDisabledControlPressed(0, 33) then movement = movement - direction end
            if IsDisabledControlPressed(0, 34) then movement = movement - right end
            if IsDisabledControlPressed(0, 35) then movement = movement + right end
            if IsDisabledControlPressed(0, 44) then movement = movement + vector3(0.0, 0.0, 1.0) end
            if IsDisabledControlPressed(0, 20) then movement = movement - vector3(0.0, 0.0, 1.0) end

            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)
            DisableControlAction(0, 32, true)
            DisableControlAction(0, 33, true)
            DisableControlAction(0, 34, true)
            DisableControlAction(0, 35, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 20, true)

            if #(movement) > 0.0 then
                local coords = GetEntityCoords(entity)
                SetEntityCoordsNoOffset(entity, coords.x + movement.x * speed, coords.y + movement.y * speed, coords.z + movement.z * speed, false, false, false, true)
                SetEntityHeading(entity, GetGameplayCamRot(2).z)
            end
        end
    end)
end

local function drawWallText(x, y, text)
    SetTextScale(0.31, 0.31)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(235, 247, 255, 230)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function toggleWall()
    wallEnabled = not wallEnabled
    OR.Notify(wallEnabled and 'Wall ativado.' or 'Wall desativado.', 'info')
    if not wallEnabled then return end

    CreateThread(function()
        while wallEnabled do
            Wait(0)
            local localPed = PlayerPedId()
            local localCoords = GetEntityCoords(localPed)
            for _, player in ipairs(GetActivePlayers()) do
                if player ~= PlayerId() then
                    local ped = GetPlayerPed(player)
                    if ped ~= 0 and DoesEntityExist(ped) then
                        local coords = GetEntityCoords(ped)
                        local distance = #(localCoords - coords)
                        if distance <= 350.0 then
                            local visible, screenX, screenY = World3dToScreen2d(coords.x, coords.y, coords.z + 1.15)
                            if visible then
                                local health = math.max(0, GetEntityHealth(ped) - 100)
                                local armor = math.max(0, GetPedArmour(ped))
                                local alive = not IsEntityDead(ped) and health > 0
                                local name = GetPlayerName(player) or 'Desconhecido'
                                local serverId = GetPlayerServerId(player)
                                local state = alive and 'VIVO' or 'MORTO'
                                drawWallText(screenX, screenY, ('[%s] %s\nHP: %s | Colete: %s | %s'):format(serverId, name, health, armor, state))
                            end
                        end
                    end
                end
            end
        end
    end)
end

local function clearWallMap()
    for source, blip in pairs(wallMapBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
        wallMapBlips[source] = nil
    end
end

local function syncWallMap()
    local data = OR.Callback.await('getWallMapPlayers')
    if type(data) ~= 'table' then return end

    local admins = {}
    for index = 1, #data do
        local entry = data[index]
        admins[tonumber(entry.source)] = entry.isAdmin == true
    end

    local seen = {}
    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() then
            local source = GetPlayerServerId(player)
            local ped = GetPlayerPed(player)
            if source and source > 0 and ped ~= 0 and DoesEntityExist(ped) then
                seen[source] = true
                local blip = wallMapBlips[source]
                if not blip or not DoesBlipExist(blip) then
                    blip = AddBlipForEntity(ped)
                    wallMapBlips[source] = blip
                    SetBlipSprite(blip, 1)
                    SetBlipScale(blip, 0.78)
                    SetBlipAsShortRange(blip, false)
                    ShowHeadingIndicatorOnBlip(blip, true)
                end
                SetBlipColour(blip, admins[source] and 1 or 0)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentString(('[%s] %s'):format(source, GetPlayerName(player) or 'Jogador'))
                EndTextCommandSetBlipName(blip)
            end
        end
    end

    for source, blip in pairs(wallMapBlips) do
        if not seen[source] then
            if DoesBlipExist(blip) then RemoveBlip(blip) end
            wallMapBlips[source] = nil
        end
    end
end

local function toggleWallMap()
    wallMapEnabled = not wallMapEnabled
    if not wallMapEnabled then
        clearWallMap()
        OR.Notify('Wallmap desativado.', 'info')
        return
    end

    OR.Notify('Wallmap ativado: administradores em vermelho e jogadores em preto.', 'info')
    CreateThread(function()
        while wallMapEnabled do
            syncWallMap()
            Wait(1250)
        end
    end)
end

-- Mantem o comando antigo inerte para atalhos F10 ja salvos pelo FiveM.
-- O painel agora e aberto exclusivamente pela opcao do menu F11.
RegisterCommand('oradmin', function() end, false)

RegisterCommand('orid', function()
    TriggerServerEvent('ob_admin:server:requestCharacterId')
end, false)

RegisterCommand('oradmin_add', function(_, args)
    TriggerServerEvent('ob_admin:server:grantCharacterAdmin', args[1])
end, false)

RegisterCommand('oradmin_remove', function(_, args)
    TriggerServerEvent('ob_admin:server:revokeCharacterAdmin', args[1])
end, false)

RegisterCommand('revive', function(_, args)
    TriggerServerEvent('ob_admin:server:executeByUserId', 'revive_full', args[1])
end, false)

RegisterCommand('fix', function(_, args)
    TriggerServerEvent('ob_admin:server:executeByUserId', 'fix_vehicle', args[1])
end, false)

RegisterCommand('car', function(_, args)
    TriggerServerEvent('ob_admin:server:utility', 'car', args[1])
end, false)

RegisterCommand('dv', function()
    TriggerServerEvent('ob_admin:server:utility', 'dv')
end, false)

RegisterCommand('dvarea', function()
    TriggerServerEvent('ob_admin:server:utility', 'dvarea')
end, false)

RegisterCommand('noclip', function()
    TriggerServerEvent('ob_admin:server:utility', 'noclip')
end, false)

RegisterCommand('wall', function()
    TriggerServerEvent('ob_admin:server:utility', 'wall')
end, false)

RegisterCommand('wallmap', function()
    TriggerServerEvent('ob_admin:server:utility', 'wallmap')
end, false)


RegisterNetEvent('ob_admin:client:open', openPanel)

RegisterNetEvent('ob_admin:client:notify', function(message, notificationType)
    OR.Notify(message, notificationType)
end)

RegisterNetEvent('ob_admin:client:actionResult', function()
    if isOpen then CreateThread(refreshPanel) end
end)

RegisterNetEvent('ob_admin:client:teleport', teleportTo)
RegisterNetEvent('ob_admin:client:heal', healPlayer)
RegisterNetEvent('ob_admin:client:restore', restorePlayer)
RegisterNetEvent('ob_admin:client:fixVehicle', fixVehicle)
RegisterNetEvent('ob_admin:client:deleteVehicle', deleteVehicle)
RegisterNetEvent('ob_admin:client:deleteVehiclesArea', deleteVehiclesArea)
RegisterNetEvent('ob_admin:client:replaceVehicleForSpawn', function(token, expectedNetId, model)
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(expectedNetId) or 0)
    local ped = PlayerPedId()
    local isExpectedDriver = vehicle ~= 0 and DoesEntityExist(vehicle)
        and GetPedInVehicleSeat(vehicle, -1) == ped
    local modelHash = joaat(tostring(model or ''))
    local validModel = IsModelInCdimage(modelHash) and IsModelAVehicle(modelHash)
    if not validModel then
        OR.Notify('Esse modelo de veiculo nao existe.', 'error')
    end
    local deleted = validModel and isExpectedDriver and requestDelete(vehicle) or false
    TriggerServerEvent('ob_admin:server:completeVehicleReplacement', token, deleted == true)
end)

RegisterNetEvent('ob_admin:client:enterSpawnedVehicle', function(netId, ghostDurationMs, previousNetId)
    local deadline = GetGameTimer() + 8000
    local vehicle = 0
    repeat
        vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
        if vehicle ~= 0 and DoesEntityExist(vehicle) then break end
        Wait(50)
    until GetGameTimer() >= deadline

    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return OR.Notify('O veiculo foi criado, mas ainda nao chegou ao seu cliente.', 'error')
    end
    ghostDurationMs = math.max(0, math.min(30000, tonumber(ghostDurationMs) or 0))
    if ghostDurationMs > 0 then
        SetNetworkVehicleAsGhost(vehicle, true)
        SetEntityInvincible(vehicle, true)
    end
    SetVehicleOnGroundProperly(vehicle)
    SetPedIntoVehicle(PlayerPedId(), vehicle, -1)
    SetVehicleEngineOn(vehicle, true, true, false)

    if ghostDurationMs > 0 then
        CreateThread(function()
            local oldVehicle = NetworkGetEntityFromNetworkId(tonumber(previousNetId) or 0)
            local deadline = GetGameTimer() + ghostDurationMs
            while DoesEntityExist(vehicle) and GetGameTimer() < deadline do
                if oldVehicle ~= 0 and DoesEntityExist(oldVehicle) then
                    SetEntityNoCollisionEntity(vehicle, oldVehicle, true)
                end
                Wait(0)
            end
            if DoesEntityExist(vehicle) then
                SetNetworkVehicleAsGhost(vehicle, false)
                enableVehicleDamage(vehicle)
            end
        end)
    end
end)
RegisterNetEvent('ob_admin:client:toggleNoclip', toggleNoclip)
RegisterNetEvent('ob_admin:client:toggleWall', toggleWall)
RegisterNetEvent('ob_admin:client:toggleWallMap', toggleWallMap)

RegisterNUICallback('close', function(_, callback)
    closePanel()
    callback({ ok = true })
end)

RegisterNUICallback('refresh', function(_, callback)
    CreateThread(refreshPanel)
    callback({ ok = true })
end)

RegisterNUICallback('action', function(data, callback)
    if isOpen and type(data) == 'table' then
        TriggerServerEvent('ob_admin:server:execute', data.action, data.target, data.value)
    end
    callback({ ok = true })
end)

RegisterNUICallback('setRole', function(data, callback)
    if isOpen and type(data) == 'table' then
        TriggerServerEvent('ob_admin:server:setRole', data.target, data.role)
    end
    callback({ ok = true })
end)

RegisterNUICallback('utility', function(data, callback)
    if isOpen and type(data) == 'table' then
        TriggerServerEvent('ob_admin:server:utility', data.action, data.value)
    end
    callback({ ok = true })
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    -- O painel nunca deve capturar mouse/teclado apos um restart isolado.
    setFocus(false)
    SendNUIMessage({ action = 'close' })
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        closePanel()
        stopNoclip()
        clearWallMap()
    end
end)
