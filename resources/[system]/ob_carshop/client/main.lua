local shops, blips, npcs = {}, {}, {}
local activeTestDrive = nil
local imageConfig = { baseUrl = OBCarshopConfig.ImageBaseUrl, fallback = OBCarshopConfig.FallbackImage }
local uiOpen, uiMode, activeShop = false, nil, nil

local function notify(message, kind) OR.Notify(message, kind or 'inform') end

local function removeBlips()
    for id, blip in pairs(blips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
        blips[id] = nil
    end
end

local function removeNpcs()
    for id, ped in pairs(npcs) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
        npcs[id] = nil
    end
end

local function spawnNpc(shop)
    if not shop.access or (npcs[shop.id] and DoesEntityExist(npcs[shop.id])) then return end
    local model = joaat(shop.npcModel or OBCarshopConfig.DefaultNpcModel)
    RequestModel(model)
    local deadline = GetGameTimer() + 8000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(model) then return end
    local point = shop.access
    local heading = point.w or 0.0
    -- O marcador e o local onde o jogador para. O atendente fica atras dele,
    -- evitando que ambos ocupem o mesmo ponto.
    local radians = math.rad(heading)
    local npcX = point.x + math.sin(radians) * 0.9
    local npcY = point.y - math.cos(radians) * 0.9
    RequestCollisionAtCoord(npcX, npcY, point.z)
    local foundGround, groundZ = GetGroundZFor_3dCoord(npcX, npcY, point.z + 3.0, false)
    local ped = CreatePed(4, model, npcX, npcY, foundGround and groundZ or (point.z - 1.0), heading, false, false)
    SetEntityInvincible(ped, true); FreezeEntityPosition(ped, true); SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false); SetEntityAsMissionEntity(ped, true, true)
    npcs[shop.id] = ped
    SetModelAsNoLongerNeeded(model)
end

local function drawTestTimer(seconds)
    local minutes, remaining = math.floor(seconds / 60), seconds % 60
    DrawRect(0.135, 0.50, 0.235, 0.072, 2, 28, 58, 218)
    DrawRect(0.135, 0.468, 0.235, 0.004, 22, 171, 238, 230)
    SetTextFont(4); SetTextScale(0.0, 0.34); SetTextColour(234, 249, 255, 255); SetTextCentre(true)
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName('TEST-DRIVE'); EndTextCommandDisplayText(0.135, 0.479)
    SetTextFont(4); SetTextScale(0.0, 0.43); SetTextColour(101, 214, 255, 255); SetTextCentre(true)
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(('%02d:%02d'):format(minutes, remaining)); EndTextCommandDisplayText(0.135, 0.501)
    SetTextFont(4); SetTextScale(0.0, 0.23); SetTextColour(180, 215, 230, 255); SetTextCentre(true)
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName('Sair do veiculo encerra o teste'); EndTextCommandDisplayText(0.135, 0.522)
end

local function finishTestDrive(message)
    local session = activeTestDrive
    if not session then return end
    activeTestDrive = nil
    local ped = PlayerPedId()
    TriggerServerEvent('ob_carshop:server:finishTestDrive', session.netId)
    if session.returnPoint and DoesEntityExist(ped) then
        SetEntityCoords(ped, session.returnPoint.x, session.returnPoint.y, session.returnPoint.z, false, false, false, false)
        SetEntityHeading(ped, session.returnPoint.w or 0.0)
    end
    if message then notify(message, 'inform') end
end

local function renderBlips(entries)
    removeBlips()
    removeNpcs()
    for _, shop in ipairs(entries or {}) do
        if shop.access then
            local blip = AddBlipForCoord(shop.access.x + 0.0, shop.access.y + 0.0, shop.access.z + 0.0)
            SetBlipSprite(blip, shop.blip.sprite or 225); SetBlipColour(blip, shop.blip.color or 3); SetBlipScale(blip, shop.blip.scale or .82)
            SetBlipAsShortRange(blip, shop.blip.shortRange ~= false)
            BeginTextCommandSetBlipName('STRING'); AddTextComponentString(shop.label); EndTextCommandSetBlipName(blip)
            blips[shop.id] = blip
            CreateThread(function() spawnNpc(shop) end)
        end
    end
end

local function closeUi()
    uiOpen, uiMode, activeShop = false, nil, nil
    SetNuiFocus(false, false); SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
end

local function openShop(shop)
    if uiOpen or IsNuiFocused() then return end
    local data, err = OR.Callback.awaitResource('ob_carshop', 'openShop', shop.id)
    if not data then return notify(err or 'Nao foi possivel abrir a concessionaria.', 'error') end
    uiOpen, uiMode, activeShop = true, 'shop', shop
    SetNuiFocus(true, true); SetNuiFocusKeepInput(false)
    data.images = imageConfig
    SendNUIMessage({ action = 'openShop', data = data })
end

local function openAdmin()
    -- O ob_adminmenu fecha sua NUI e dispara este evento no mesmo frame.
    -- IsNuiFocused ainda pode responder true naquele instante e bloqueava o
    -- editor, apesar de o cartao ser clicado corretamente.
    if uiOpen then return end
    local data, err = OR.Callback.awaitResource('ob_carshop', 'adminData')
    if not data then return notify(err or 'Sem permissao administrativa.', 'error') end
    uiOpen, uiMode = true, 'admin'
    SetNuiFocus(true, true); SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'openAdmin', data = data })
end

RegisterNetEvent('ob_carshop:client:openAdmin', openAdmin)
RegisterCommand('obcarshopadmin', openAdmin, false)
RegisterNetEvent('ob_carshop:client:notify', notify)
RegisterNetEvent('ob_carshop:client:syncShops', function(entries)
    shops = entries or {}
    renderBlips(shops)
end)
RegisterNetEvent('ob_carshop:client:refreshAdmin', function()
    if uiOpen and uiMode == 'admin' then
        local data = OR.Callback.awaitResource('ob_carshop', 'adminData')
        if data then SendNUIMessage({ action = 'adminData', data = data }) end
    end
end)

RegisterNUICallback('close', function(_, cb) closeUi(); cb({ ok = true }) end)
RegisterNUICallback('buy', function(data, cb)
    if uiMode ~= 'shop' or not activeShop then return cb({ ok = false }) end
    -- buyVehicle devolve: sucesso, dadosDoVeiculo, mensagem. O primeiro valor
    -- e booleano; tratar ele como a tabela causava result.model/plate falhar.
    local ok, result, message = OR.Callback.awaitResource('ob_carshop', 'buyVehicle', activeShop.id, data and data.vehicleId)
    if ok ~= true or type(result) ~= 'table' then
        local errorMessage = type(result) == 'string' and result or message or 'Compra recusada.'
        notify(errorMessage, 'error')
        return cb({ ok = false, error = errorMessage })
    end
    if tonumber(result.netId) then
        local vehicle = OR.Entity.AwaitNetwork(result.netId, 10000)
        if vehicle then
            SetVehicleNumberPlateText(vehicle, result.plate)
            SetVehicleFuelLevel(vehicle, tonumber(result.fuel) or 100.0)
            SetVehicleEngineOn(vehicle, true, true, false)
            SetPedIntoVehicle(PlayerPedId(), vehicle, -1)
        else
            notify('Compra registrada, mas a entrega nao sincronizou. O veiculo esta na garagem.', 'warning')
        end
    end
    SendNUIMessage({ action = 'cash', cash = result.cash }); notify(message or 'Veiculo entregue.', 'success'); cb({ ok = true })
end)
RegisterNUICallback('test', function(data, cb)
    if uiMode ~= 'shop' or not activeShop then return cb({ ok = false }) end
    local result, err = OR.Callback.awaitResource('ob_carshop', 'testVehicle', activeShop.id, data and data.vehicleId)
    if not result then notify(err or 'Teste indisponivel.', 'error'); return cb({ ok = false, error = err }) end
    if activeTestDrive then finishTestDrive() end
    if result.point then
        RequestCollisionAtCoord(result.point.x, result.point.y, result.point.z)
        SetEntityCoordsNoOffset(PlayerPedId(), result.point.x, result.point.y, result.point.z + 0.5, false, false, false)
        SetEntityHeading(PlayerPedId(), result.point.w or 0.0)
    end
    local vehicle = OR.Entity.AwaitNetwork(result.netId, 10000)
    if not vehicle then
        TriggerServerEvent('ob_carshop:server:finishTestDrive', result.netId)
        notify('O veiculo de teste nao sincronizou.', 'error')
        return cb({ ok = false })
    end
    SetVehicleNumberPlateText(vehicle, result.plate or 'TESTE OB')
    SetVehicleFuelLevel(vehicle, 100.0)
    SetPedIntoVehicle(PlayerPedId(), vehicle, -1)
    activeTestDrive = { vehicle = vehicle, netId = result.netId, returnPoint = result.returnPoint, expiresAt = GetGameTimer() + ((tonumber(result.duration) or 90) * 1000) }
    closeUi(); notify(('Teste de %s iniciado.'):format(result.label), 'inform'); cb({ ok = true })
end)
RegisterNUICallback('createShop', function(data, cb) TriggerServerEvent('ob_carshop:server:createShop', data); cb({ ok = true }) end)
RegisterNUICallback('setPoint', function(data, cb) TriggerServerEvent('ob_carshop:server:setPoint', data); cb({ ok = true }) end)
RegisterNUICallback('saveVehicle', function(data, cb) TriggerServerEvent('ob_carshop:server:saveVehicle', data); cb({ ok = true }) end)
RegisterNUICallback('deleteVehicle', function(data, cb) TriggerServerEvent('ob_carshop:server:deleteVehicle', data); cb({ ok = true }) end)
RegisterNUICallback('deleteShop', function(data, cb) TriggerServerEvent('ob_carshop:server:deleteShop', data and data.shopId); cb({ ok = true }) end)

CreateThread(function()
    while LocalPlayer.state['or:loaded'] ~= true do Wait(500) end
    local data = OR.Callback.awaitResource('ob_carshop', 'shops')
    if data then shops = data; renderBlips(shops) end
    local models = OR.Callback.awaitResource('ob_carshop', 'imageModels')
    if models then SendNUIMessage({ action = 'preloadImages', images = imageConfig, models = models }) end
    while true do
        local wait = 1000
        local coords = GetEntityCoords(PlayerPedId())
        for _, shop in ipairs(shops) do
            local point = shop.access
            if point then
                local distance = #(coords - vector3(point.x, point.y, point.z))
                if distance < OBCarshopConfig.MarkerDrawDistance then
                    wait = 0
                    DrawMarker(1, point.x, point.y, point.z - .98, 0,0,0,0,0,0, 1.15,1.15,.35, 0,138,235,130, false,true,2,false,nil,nil,false)
                    if distance <= OBCarshopConfig.InteractionDistance and not uiOpen then
                        OR.Help.Show(('[E] Abrir %s'):format(shop.label))
                        if IsControlJustReleased(0, 38) then openShop(shop) end
                    end
                end
            end
        end
        Wait(wait)
    end
end)

CreateThread(function()
    while true do
        local session = activeTestDrive
        if not session then
            Wait(500)
        else
            Wait(0)
            local seconds = math.max(0, math.ceil((session.expiresAt - GetGameTimer()) / 1000))
            drawTestTimer(seconds)
            if seconds <= 0 then
                finishTestDrive('Tempo do test-drive encerrado.')
            elseif not DoesEntityExist(session.vehicle) or GetVehiclePedIsIn(PlayerPedId(), false) ~= session.vehicle then
                finishTestDrive('Teste encerrado. Voce saiu do veiculo.')
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        if activeTestDrive then finishTestDrive() end
        removeBlips(); removeNpcs(); closeUi()
    end
end)
