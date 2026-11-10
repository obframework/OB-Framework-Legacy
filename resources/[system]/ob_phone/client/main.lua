local open, phoneBattery, trackingBlip, trackingPlate, phoneProp = false, 100, nil, nil, nil
local callState, opening, propGeneration = nil, false, 0
local callStartedAt, openGeneration = nil, 0
local inputMode = 'phone'
local cameraInputActive = false
local videoFreeLookCallId = nil
local movementReleaseUntil = 0
local phoneVisualPublished, remotePhoneProps = false, {}
local cameraVisualActive = false
local activePhoneSlot = nil
local deviceUsable = false

local function publishPhoneVisual(active)
    active = active == true
    if phoneVisualPublished == active then return end
    phoneVisualPublished = active
    TriggerServerEvent('ob_phone:server:phoneVisual', active)
end

local function getAppCatalog()
    local ok, apps = pcall(function()
        return exports.ob_phone:GetApps()
    end)
    return ok and type(apps) == 'table' and apps or {}
end

local function clearPhoneProp(keepVisual)
    propGeneration = propGeneration + 1
    if phoneProp and DoesEntityExist(phoneProp) then
        DetachEntity(phoneProp, true, true)
        SetEntityAsMissionEntity(phoneProp, true, true)
        DeleteObject(phoneProp)
        DeleteEntity(phoneProp)
    end
    phoneProp = nil
    ClearPedSecondaryTask(PlayerPedId())
    if not keepVisual then publishPhoneVisual(false) end
end

local function showPhoneProp()
    clearPhoneProp(true)
    local generation = propGeneration
    local ped, model = PlayerPedId(), joaat('prop_npc_phone_02')
    RequestModel(model)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(model) or generation ~= propGeneration then publishPhoneVisual(false); return end
    phoneProp = CreateObject(model, 0.0, 0.0, 0.0, false, false, false)
    SetEntityCollision(phoneProp, false, false)
    AttachEntityToEntity(phoneProp, ped, GetPedBoneIndex(ped, 28422), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    local dictionary = cameraVisualActive and 'cellphone@self' or 'cellphone@'
    RequestAnimDict(dictionary)
    while not HasAnimDictLoaded(dictionary) and GetGameTimer() < deadline do Wait(0) end
    local anim = cameraVisualActive and 'selfie'
        or callState and callState.phase == 'active' and callState.video ~= true and not callState.speaker
            and 'cellphone_call_listen_base' or 'cellphone_text_read_base'
    if HasAnimDictLoaded(dictionary) and generation == propGeneration then
        TaskPlayAnim(ped, dictionary, anim, 4.0, -4.0, -1, 49, 1.0, false, false, false)
    end
    SetModelAsNoLongerNeeded(model)
    publishPhoneVisual(true)
end

AddEventHandler('ob_phone:client:cameraVisual', function(active)
    cameraVisualActive = active == true
    if active == true then
        if open then showPhoneProp() end
    elseif open then
        showPhoneProp()
    end
end)

local function removeRemotePhone(serverId)
    local entry = remotePhoneProps[serverId]
    if not entry then return end
    entry.cancelled = true
    if entry.object and DoesEntityExist(entry.object) then DeleteEntity(entry.object) end
    remotePhoneProps[serverId] = nil
end

local function createRemotePhone(serverId, ped, token)
    removeRemotePhone(serverId)
    local entry = { ped = ped, token = token, cancelled = false }
    remotePhoneProps[serverId] = entry
    CreateThread(function()
        local model = joaat('prop_npc_phone_02')
        RequestModel(model)
        local deadline = GetGameTimer() + 4000
        while not entry.cancelled and not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
        if entry.cancelled or not HasModelLoaded(model) or not DoesEntityExist(ped) then SetModelAsNoLongerNeeded(model); return end
        local coords = GetEntityCoords(ped)
        local object = CreateObjectNoOffset(model, coords.x, coords.y, coords.z, false, false, false)
        entry.object = object
        SetModelAsNoLongerNeeded(model)
        if object == 0 or not DoesEntityExist(object) then return end
        SetEntityAsMissionEntity(object, true, true)
        SetEntityCollision(object, false, false)
        AttachEntityToEntity(object, ped, GetPedBoneIndex(ped, 28422), 0.0, 0.0, 0.0,
            0.0, 0.0, 0.0, false, false, false, true, 2, true)
    end)
end

CreateThread(function()
    while true do
        local seen, origin = {}, GetEntityCoords(PlayerPedId())
        for _, player in ipairs(GetActivePlayers()) do
            if player ~= PlayerId() then
                local serverId, ped = GetPlayerServerId(player), GetPlayerPed(player)
                local visual = Player(serverId).state['ob:phoneVisual']
                if type(visual) == 'table' and type(visual.token) == 'number'
                    and DoesEntityExist(ped) and #(GetEntityCoords(ped) - origin) <= 75.0 then
                    seen[serverId] = true
                    local entry = remotePhoneProps[serverId]
                    if not entry or entry.ped ~= ped or entry.token ~= visual.token then
                        createRemotePhone(serverId, ped, visual.token)
                    end
                end
            end
        end
        for serverId in pairs(remotePhoneProps) do if not seen[serverId] then removeRemotePhone(serverId) end end
        Wait(400)
    end
end)

local function setPhoneInputMode(mode)
    if not open then return end
    local previousMode = inputMode
    inputMode = mode == 'game' and 'game' or mode == 'typing' and 'typing' or 'phone'
    if inputMode == 'game' then
        if previousMode ~= 'game' then movementReleaseUntil = GetGameTimer() + 250 end
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
    else
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(inputMode == 'phone')
    end
    TriggerEvent('ob_phone:client:videoCallFreeLook', inputMode == 'game')
end

local function close()
    TriggerEvent('ob_phone:client:cameraStop')
    open = false
    openGeneration = openGeneration + 1
    opening = false
    deviceUsable = false
    inputMode = 'phone'
    movementReleaseUntil = 0
    cameraInputActive = false
    videoFreeLookCallId = nil
    TriggerEvent('ob_phone:client:videoCallFreeLook', false)
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
    if callState and callState.phase == 'active' then showPhoneProp() else clearPhoneProp() end
end

local function getData()
    local ok, data = OR.Callback.await('data')
    if ok and type(data) == 'table' then phoneBattery = tonumber(data.battery) or phoneBattery end
    return ok, data
end

local function openPhone(skipItemCheck, requestedSlot)
    if open or opening then return end
    if LocalPlayer.state['or:downed'] == true
        or LocalPlayer.state['or:restrained'] == true
        or LocalPlayer.state['ob:restrained'] == true then return end
    opening = true
    openGeneration = openGeneration + 1
    local requestGeneration = openGeneration
    activePhoneSlot = math.floor(tonumber(requestedSlot) or 0) > 0 and math.floor(tonumber(requestedSlot)) or activePhoneSlot
    if not activePhoneSlot then
        local hasPhone, phoneItem = OR.Callback.awaitResource('ob_inventory', 'phoneItem')
        if requestGeneration ~= openGeneration then return end
        if hasPhone == true and type(phoneItem) == 'table' then
            activePhoneSlot = tonumber(phoneItem.slot)
        else
            -- Permite abrir durante um rolling restart em que o cliente novo
            -- ainda conversa com a versao anterior do inventario.
            local legacyHasPhone = OR.Callback.awaitResource('ob_inventory', 'hasPhone')
            if requestGeneration ~= openGeneration then return end
            if legacyHasPhone ~= true then opening = false; return OR.Notify('Voce precisa de um celular na mochila.', 'error') end
        end
    end
    local deviceOk, device = OR.Callback.await('deviceOpen', activePhoneSlot)
    if requestGeneration ~= openGeneration then return end
    if not deviceOk then opening = false; return OR.Notify(device or 'Celular indisponivel.', 'error') end
    local ok, data = true, { battery = phoneBattery }
    if device.authorized == true and tonumber(device.signal) > 0 then ok, data = getData() end
    opening = false
    if not ok then return OR.Notify(data or 'Celular indisponivel.', 'error') end
    if device.authorized == true and phoneBattery <= 0 then return OR.Notify('A bateria do celular acabou. Use um powerbank.', 'error') end
    open = true
    if callState and callStartedAt then callState.elapsed = math.max(0, math.floor((GetGameTimer() - callStartedAt) / 1000)) end
    data.call = callState
    data.device = device
    deviceUsable = device.valid == true and device.authorized == true and tonumber(device.signal) > 0
    data.defaults = {case = OBPhoneConfig.DefaultCase, wallpaper = OBPhoneConfig.DefaultWallpaper}
    local garageImages = OBPhoneConfig.GarageImages or {}
    data.publicConfig = {
        garageImageBaseUrl = garageImages.BaseUrl or '',
        garageImageFallback = garageImages.Fallback or 'carro.png',
        apps = OBPhoneConfig.Apps or {},
        videoIceServers = OBPhoneConfig.VideoIceServers or {},
    }
    data.appCatalog = getAppCatalog()
    inputMode = 'phone'
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    SendNUIMessage({ action = 'open', data = data })
    if callState and callState.phase == 'active' then
        videoFreeLookCallId = callState.id
        setPhoneInputMode('game')
        SendNUIMessage({ action = 'inputFocus', mode = 'game' })
    end
    showPhoneProp()
end

-- Mantem direcao, acelerador e freio funcionando com o telefone aberto.
-- Apenas combate e troca de arma ficam bloqueados enquanto o cursor esta na NUI.
CreateThread(function()
    while true do
        if open then
            DisablePlayerFiring(PlayerId(), true)
            for _, control in ipairs({24,25,37,44,45,140,141,142,257,263,264}) do
                DisableControlAction(0, control, true)
            end
            if inputMode == 'game' and GetGameTimer() < movementReleaseUntil then
                -- Limpa o ultimo estado do teclado ao devolver o foco ao GTA.
                for _, control in ipairs({30,31,32,33,34,35,59,60,71,72}) do
                    DisableControlAction(0, control, true)
                end
            end
            if inputMode == 'phone' and not cameraInputActive then
                DisableControlAction(0, 1, true)
                DisableControlAction(0, 2, true)
            elseif inputMode == 'game' and IsDisabledControlJustPressed(0, 25) then
                setPhoneInputMode('phone')
                SendNUIMessage({ action = 'inputFocus', mode = 'phone' })
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

AddEventHandler('ob_phone:client:cameraInput', function(active)
    cameraInputActive = active == true
end)

CreateThread(function()
    while true do
        Wait(60000)
        if open and not callState and phoneBattery > 0 then
            phoneBattery = math.max(0, phoneBattery - 1)
            OR.Callback.await('saveBattery', phoneBattery)
            SendNUIMessage({ action = 'battery', battery = phoneBattery })
            if phoneBattery == 0 then
                close()
                OR.Notify('A bateria do celular acabou.', 'error')
            end
        end
    end
end)

CreateThread(function()
    while true do
        if open then
            local ok, device = OR.Callback.await('deviceSignal')
            if ok and type(device) == 'table' then
                local usable = device.valid == true and device.authorized == true and tonumber(device.signal) > 0
                SendNUIMessage({ action = 'deviceState', device = device })
                if usable and not deviceUsable then
                    local dataOk, fresh = getData()
                    if dataOk then
                        fresh.device = device
                        fresh.call = callState
                        fresh.defaults = {case = OBPhoneConfig.DefaultCase, wallpaper = OBPhoneConfig.DefaultWallpaper}
                        local garageImages = OBPhoneConfig.GarageImages or {}
                        fresh.publicConfig = {garageImageBaseUrl=garageImages.BaseUrl or '',garageImageFallback=garageImages.Fallback or 'carro.png',apps=OBPhoneConfig.Apps or {},videoIceServers=OBPhoneConfig.VideoIceServers or {}}
                        fresh.appCatalog = getAppCatalog()
                        SendNUIMessage({ action = 'authorized', data = fresh })
                    end
                end
                deviceUsable = usable
            end
            Wait(5000)
        else
            Wait(1000)
        end
    end
end)

CreateThread(function()
    while true do
        if trackingBlip and trackingPlate then
            local found
            for _, vehicle in ipairs(GetGamePool('CVehicle')) do
                if DoesEntityExist(vehicle) and (GetVehicleNumberPlateText(vehicle) or ''):gsub('%s+$', '') == trackingPlate then
                    found = vehicle
                    break
                end
            end
            if found then
                SetBlipCoords(trackingBlip, GetEntityCoords(found))
                SetBlipAlpha(trackingBlip, 255)
            else
                SetBlipAlpha(trackingBlip, 80)
            end
            Wait(1000)
        else
            Wait(1500)
        end
    end
end)

RegisterCommand('phone', function() if open then close() else openPhone(false) end end, false)
RegisterKeyMapping('phone', 'Abrir ou fechar celular', 'keyboard', 'K')
RegisterNetEvent('ob_phone:client:open', function(slot) openPhone(true, slot) end)
RegisterNetEvent('ob_phone:client:forceClose', close)
RegisterNetEvent('ob_phone:client:charge', function(slot)
    local ok, result = OR.Callback.await('charge', slot)
    if ok then
        phoneBattery = tonumber(type(result) == 'table' and result.battery) or phoneBattery
        SendNUIMessage({ action = 'battery', battery = phoneBattery })
    else
        OR.Notify(result or 'Voce nao possui powerbank.', 'error')
    end
end)
RegisterNetEvent('ob_phone:client:chargingProgress', function(battery)
    phoneBattery = math.max(0, math.min(100, math.floor(tonumber(battery) or phoneBattery)))
    SendNUIMessage({ action = 'battery', battery = phoneBattery })
end)
RegisterNetEvent('ob_phone:client:useSimChip', function(slot)
    if not open then openPhone(false) end
    if open then SendNUIMessage({ action = 'simPrompt', slot = tonumber(slot) }) end
end)
RegisterNetEvent('ob_phone:client:notification', function(text, kind)
    SendNUIMessage({ action = 'notification', text = text, kind = kind or 'phone' })
end)
RegisterNetEvent('ob_phone:client:shareRequest', function(request)
    if type(request) ~= 'table' then return end
    if not open then
        CreateThread(function() OR.Callback.await('shareNumberResponse', request.token, false) end)
        return
    end
    SendNUIMessage({action = 'shareRequest', request = request})
end)
RegisterNetEvent('ob_phone:client:callState', function(state)
    if type(state) ~= 'table' then return end
    callState = state.phase ~= 'ended' and state or nil
    callStartedAt = callState and state.phase == 'active' and (GetGameTimer() - (tonumber(state.elapsed) or 0) * 1000) or nil
    SendNUIMessage({action = 'callState', call = state})
    if open and callState and callState.phase == 'active' and videoFreeLookCallId ~= callState.id then
        videoFreeLookCallId = callState.id
        setPhoneInputMode('game')
        SendNUIMessage({action = 'inputFocus', mode = 'game'})
    elseif open and not callState and videoFreeLookCallId ~= nil then
        videoFreeLookCallId = nil
        setPhoneInputMode('phone')
        SendNUIMessage({action = 'inputFocus', mode = 'phone'})
    end
    if open or (callState and callState.phase == 'active') then showPhoneProp() else clearPhoneProp() end
end)
RegisterNetEvent('ob_phone:client:videoSignal', function(callId, payload)
    SendNUIMessage({action = 'videoSignal', callId = callId, payload = payload})
end)
RegisterNetEvent('ob_phone:client:battery', function(value)
    phoneBattery = tonumber(value) or 0
    SendNUIMessage({action = 'battery', battery = phoneBattery})
    if phoneBattery <= 0 and open then close() end
end)

RegisterNUICallback('close', function(_, cb) close(); cb({ ok = true }) end)
RegisterNUICallback('inputFocus', function(d, cb)
    setPhoneInputMode(type(d) == 'table' and d.mode or 'phone')
    cb({ ok = true })
end)
RegisterNUICallback('refresh', function(_, cb) local ok, data = getData(); cb({ ok = ok, data = data }) end)
RegisterNUICallback('message', function(d, cb) local ok, message = OR.Callback.await('sendMessage', d.to, d.body, d.messageType, d); cb({ ok = ok, message = message }) end)
RegisterNUICallback('post', function(d, cb) local ok, message = OR.Callback.await('post', d.body, d.mediaId); cb({ ok = ok, message = message }) end)
RegisterNUICallback('username', function(d, cb) local ok, message = OR.Callback.await('setUsername', d.username, d.name); cb({ ok = ok, message = message }) end)
RegisterNUICallback('contact', function(d, cb) local ok, message = OR.Callback.await('saveContact', d.number, d.name); cb({ ok = ok, message = message }) end)
RegisterNUICallback('setAppInstalled', function(d, cb)
    local ok, message = OR.Callback.await('setAppInstalled', d.appId, d.installed == true)
    cb({ ok = ok, message = message })
end)
RegisterNUICallback('transfer', function(d, cb) local ok, message = OR.Callback.await('transfer', d.id, d.amount); cb({ ok = ok, message = message }) end)
RegisterNUICallback('bank', function(_, cb) local ok, data = OR.Callback.await('bankData'); cb({ ok = ok, data = data }) end)
RegisterNUICallback('payFine', function(d, cb) local ok, message = OR.Callback.await('payPhoneFine', d.id); cb({ ok = ok, message = message }) end)
RegisterNUICallback('garage', function(_, cb) local ok, data = OR.Callback.await('garageData'); cb({ ok = ok, data = data }) end)
RegisterNUICallback('obgramAction', function(d, cb) local ok, result = OR.Callback.await('obgramAction', d.action, d); cb({ ok = ok, data = ok and result or nil, message = ok and nil or result }) end)
RegisterNUICallback('darkchat', function(d, cb) local ok, result = OR.Callback.await('darkchat', d.action, d); cb({ ok = ok, data = ok and result or nil, message = ok and nil or result }) end)
RegisterNUICallback('phoneSettings', function(d, cb) local ok, result = OR.Callback.await('phoneSettings', d.action, d); cb({ ok = ok, data = ok and result or nil, message = type(result)=='string' and result or nil }) end)
RegisterNUICallback('deviceAuth', function(d, cb)
    local ok, result, state = OR.Callback.await('deviceAuth', d.action, d)
    local device = type(result) == 'table' and result or type(state) == 'table' and state or nil
    if ok and device and device.authorized then
        local dataOk, fresh = getData()
        if dataOk then
            fresh.device = device
            fresh.call = callState
            fresh.defaults = {case = OBPhoneConfig.DefaultCase, wallpaper = OBPhoneConfig.DefaultWallpaper}
            local garageImages = OBPhoneConfig.GarageImages or {}
            fresh.publicConfig = {garageImageBaseUrl=garageImages.BaseUrl or '',garageImageFallback=garageImages.Fallback or 'carro.png',apps=OBPhoneConfig.Apps or {},videoIceServers=OBPhoneConfig.VideoIceServers or {}}
            fresh.appCatalog = getAppCatalog()
            SendNUIMessage({ action = 'authorized', data = fresh })
            deviceUsable = tonumber(device.signal) > 0 and device.valid == true
        end
    elseif device then SendNUIMessage({ action = 'deviceState', device = device }) end
    cb({ ok = ok, data = device or (ok and result or nil), message = type(result)=='string' and result or nil })
end)
RegisterNUICallback('messageGroups', function(d, cb) local ok, result = OR.Callback.await('messageGroups', d.action, d); cb({ ok = ok, data = ok and result or nil, message = ok and nil or result }) end)
RegisterNUICallback('sendLocation', function(d, cb)
    local coords = GetEntityCoords(PlayerPedId())
    d.location = ('%.3f,%.3f'):format(coords.x, coords.y)
    local ok, result
    if d.kind == 'dark' then ok, result = OR.Callback.await('darkchat', 'send', d)
    elseif d.kind == 'group' then ok, result = OR.Callback.await('messageGroups', 'send', d)
    else ok, result = OR.Callback.await('sendMessage', d.to, '', 'location', d) end
    cb({ok=ok,data=ok and result or nil,message=ok and nil or result})
end)
RegisterNUICallback('setWaypoint', function(d, cb)
    local x,y=tostring(d.location or ''):match('^(-?%d+%.?%d*),(-?%d+%.?%d*)$')
    x,y=tonumber(x),tonumber(y)
    if not x or not y then return cb({ok=false,message='Localizacao invalida.'}) end
    SetNewWaypoint(x+0.0,y+0.0)
    OR.Notify('Localizacao marcada no mapa.','success')
    cb({ok=true})
end)
RegisterNUICallback('mediaList', function(_, cb) local ok, result = OR.Callback.await('mediaList'); cb({ ok = ok, data = ok and result or nil, message = ok and nil or result }) end)
RegisterNUICallback('mediaDelete', function(d, cb) local ok, result = OR.Callback.await('mediaDelete', d.id); cb({ ok = ok, message = result }) end)
RegisterNUICallback('mediaRequestUpload', function(d, cb) local ok, result = OR.Callback.await('mediaRequestUpload', d.mediaType); cb({ ok = ok, data = ok and result or nil, message = ok and nil or result }) end)
RegisterNUICallback('mediaCompleteUpload', function(d, cb) local ok, result = OR.Callback.await('mediaCompleteUpload', d.requestId, d.remoteId, d.url, d.mediaType, d.variantForMediaId); cb({ ok = ok, data = ok and result or nil, message = ok and nil or result }) end)
RegisterNUICallback('call', function(d, cb)
    local ok, message = OR.Callback.await('dial', d.number, d.mode)
    cb({ok = ok, message = message})
end)
RegisterNUICallback('videoSignal', function(d, cb)
    if type(d) == 'table' then TriggerServerEvent('ob_phone:server:videoSignal', d.callId, d.payload) end
    cb({ok = true})
end)
RegisterNUICallback('callAction', function(d, cb)
    local ok, message = OR.Callback.await('callAction', d.action, d.value)
    cb({ok = ok, message = message})
end)
RegisterNUICallback('callHistory', function(_, cb)
    local ok, data = OR.Callback.await('callHistory'); cb({ok = ok, data = data})
end)
RegisterNUICallback('nearbyContacts', function(_, cb)
    local here, targets = GetEntityCoords(PlayerPedId()), {}
    local distance = tonumber(OBPhoneConfig.ShareDistance) or 3.0
    for _, id in ipairs(GetActivePlayers()) do
        if id ~= PlayerId() then
            local ped, serverId = GetPlayerPed(id), GetPlayerServerId(id)
            local visual = Player(serverId).state['ob:phoneVisual']
            if ped and ped > 0 and type(visual) == 'table' and #(GetEntityCoords(ped) - here) <= distance then
                targets[#targets + 1] = serverId
            end
        end
    end
    local ok, result = OR.Callback.await('nearbyContacts', targets)
    cb({ ok = ok, data = ok and result or nil, message = ok and nil or result })
end)
RegisterNUICallback('shareNumber', function(data, cb)
    local player, distance = -1, 999.0
    local maximumDistance = tonumber(OBPhoneConfig.ShareDistance) or 3.0
    local here = GetEntityCoords(PlayerPedId())
    for _, id in ipairs(GetActivePlayers()) do
        if id ~= PlayerId() then
            local d = #(GetEntityCoords(GetPlayerPed(id)) - here)
            local requested = tonumber(data.target)
            if (not requested or GetPlayerServerId(id) == requested) and d < distance then player, distance = id, d end
        end
    end
    if player == -1 or distance > maximumDistance then return cb({ ok = false, message = ('Aproxime-se a menos de %.0f metros da pessoa.'):format(maximumDistance) }) end
    TriggerServerEvent('ob_phone:server:shareNumber', GetPlayerServerId(player), data.contactName, data.contactNumber)
    cb({ ok = true, message = 'Numero compartilhado.' })
end)
RegisterNUICallback('shareNumberResponse', function(data, cb)
    local ok, message = OR.Callback.await('shareNumberResponse', data.token, data.accepted == true)
    cb({ok = ok, message = message})
end)
RegisterNUICallback('track', function(d, cb)
    local ok, result = OR.Callback.await('trackVehicle', d.id)
    if not ok then return cb({ok=false,message=result}) end
    trackingPlate = tostring(result.plate or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if trackingBlip then RemoveBlip(trackingBlip) end
    trackingBlip = AddBlipForCoord(result.x+0.0,result.y+0.0,result.z+0.0)
    local class=GetVehicleClassFromName(joaat(tostring(result.model or'')))
    local sprites={[8]=348,[13]=226,[14]=427,[15]=422,[16]=423,[10]=477,[11]=477,[12]=477,[20]=477}
    SetBlipSprite(trackingBlip,sprites[class] or 225);SetBlipColour(trackingBlip,3);SetBlipScale(trackingBlip,0.8)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString('Veiculo rastreado: ' .. trackingPlate); EndTextCommandSetBlipName(trackingBlip)
    local trackedPlate, trackedBlip = trackingPlate, trackingBlip
    local duration=math.max(1,tonumber(result.duration) or 30)
    SetTimeout(duration*1000, function()
        if trackingPlate == trackedPlate and trackingBlip == trackedBlip then
            if DoesBlipExist(trackedBlip) then RemoveBlip(trackedBlip) end
            trackingBlip, trackingPlate = nil, nil
            OR.Notify('Rastreamento encerrado.', 'info')
        end
    end)
    OR.Notify(('Rastreador ativado por %d segundos para %s.'):format(duration,trackingPlate), 'success')
    cb({ ok = true })
end)
AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    callState = nil; close(); if trackingBlip then RemoveBlip(trackingBlip) end
    for serverId in pairs(remotePhoneProps) do removeRemotePhone(serverId) end
end)
