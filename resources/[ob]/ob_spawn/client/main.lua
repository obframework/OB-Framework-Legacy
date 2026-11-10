local locations = {
    legion = { label = 'Legion Square', description = 'Centro de Los Santos', coords = vec4(195.17, -933.77, 29.7, 144.5) },
    paleto = { label = 'Paleto Bay', description = 'Norte do mapa', coords = vec4(80.35, 6424.12, 31.67, 45.5) },
    motel = { label = 'Motels', description = 'Innocence Boulevard', coords = vec4(327.56, -205.08, 53.08, 163.5) },
}
local locationOrder = { 'paleto', 'motel', 'legion' }

local isOpen = false
local isOpening = false
local pendingLastCoords
local pendingOptions = {}

local function clearNuiFocus()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end

local function acquireSpawnFocus()
    clearNuiFocus()
    Wait(0)
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SetTimeout(150, function()
        if isOpen then
            SetNuiFocus(true, true)
            SetNuiFocusKeepInput(false)
        end
    end)
end

local function finishSpawn(coords)
    if not coords then return end

    clearNuiFocus()
    DoScreenFadeOut(200)
    while not IsScreenFadedOut() do Wait(0) end

    SendNUIMessage({ action = 'close' })
    isOpen = false
    pendingOptions = {}
    clearNuiFocus()

    local ped = PlayerPedId()
    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
    SetEntityHeading(ped, coords.w or coords.heading or 0.0)
    SetEntityVisible(ped, true, false)
    ResetEntityAlpha(ped)
    FreezeEntityPosition(ped, false)
    DisplayRadar(true)
    SetFollowPedCamViewMode(1)
    SetFollowVehicleCamViewMode(1)

    TriggerServerEvent('ob_spawn:server:markSpawned')
    DoScreenFadeIn(500)
    SetTimeout(1000, clearNuiFocus)
end

local function openSpawnMenu(knownLastCoords)
    if isOpen then return end

    pendingLastCoords = knownLastCoords
    local options = {}

    if pendingLastCoords then
        options[#options + 1] = {
            id = 'last',
            label = 'Ultima localizacao',
            description = 'Voltar para onde voce saiu',
            coords = { x = pendingLastCoords.x, y = pendingLastCoords.y },
            isLast = true,
        }
    end

    for _, id in ipairs(locationOrder) do
        local location = locations[id]
        options[#options + 1] = {
            id = id,
            label = location.label,
            description = location.description,
            coords = { x = location.coords.x, y = location.coords.y },
        }
    end

    isOpen = true
    pendingOptions = options
    SendNUIMessage({ action = 'open', options = options })
    acquireSpawnFocus()
    Wait(0)
    DoScreenFadeIn(250)
end

RegisterNUICallback('selectSpawn', function(data, callback)
    local id = type(data) == 'table' and data.id
    local coords

    if id == 'last' and pendingLastCoords then
        coords = pendingLastCoords
    elseif locations[id] then
        coords = locations[id].coords
    else
        OR.Notify('Local de spawn invalido.', 'error')
        callback({ ok = false })
        return
    end

    callback({ ok = true })
    CreateThread(function()
        Wait(0)
        finishSpawn(coords)
    end)
end)

RegisterNetEvent('ob_spawn:client:open', function(lastCoords)
    if isOpen or isOpening then return end
    isOpening = true

    CreateThread(function()
        local alreadySpawned = OR.Callback.await('alreadySpawned')
        if alreadySpawned == true and lastCoords then
            finishSpawn(lastCoords)
        else
            openSpawnMenu(lastCoords)
        end
        isOpening = false
    end)
end)

RegisterCommand('orfixspawn', function()
    if not isOpen then
        clearNuiFocus()
        return
    end

    SendNUIMessage({ action = 'open', options = pendingOptions })
    acquireSpawnFocus()
end, false)

RegisterCommand('orfixnui', clearNuiFocus, false)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    clearNuiFocus()
    SendNUIMessage({ action = 'close' })
    -- Se o restart ocorreu enquanto a chegada estava aberta, o estado de
    -- spawn ainda esta no ob_core. Reabrimos somente esse seletor, sem login
    -- e sem mexer em recursos ja iniciados.
    CreateThread(function()
        Wait(600)
        if LocalPlayer.state['or:loaded'] ~= true then return end
        for _ = 1, 4 do
            local alreadySpawned = OR.Callback.await('alreadySpawned')
            if alreadySpawned ~= nil then
                if alreadySpawned == false then
                    local lastCoords = OR.Callback.await('getLastLocation')
                    openSpawnMenu(lastCoords)
                end
                return
            end
            Wait(750)
        end
    end)
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    clearNuiFocus()
    SendNUIMessage({ action = 'close' })
end)
