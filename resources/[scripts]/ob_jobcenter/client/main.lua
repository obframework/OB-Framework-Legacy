local resource = GetCurrentResourceName()
local npc, blip, opened, busy = nil, nil, false, false
local targetId = 'ob_jobcenter:attendant'

-- Identifica o atendente para recursos que interagem com pedestres comuns.
-- Isso impede, por exemplo, o ob_drugselling de registrar uma venda neste NPC.
exports('IsServicePed', function(ped)
    return ped ~= nil and ped ~= 0 and ped == npc and DoesEntityExist(npc)
end)

local function notify(message, kind)
    TriggerEvent('ob_notification:client:notify', message, kind or 'info', 7000)
end

local function closePanel()
    if opened then SetNuiFocus(false, false) end
    opened = false
    busy = false
    SendNUIMessage({ action = 'close' })
end

local function requestStatus()
    local ok, data, err = pcall(OR.Callback.await, 'status')
    if not ok or not data then return nil, ok and err or 'Central de Empregos indisponivel.' end
    return data
end

local function openPanel()
    if opened or busy or IsNuiFocused() then return end
    busy = true
    CreateThread(function()
        local data, err = requestStatus()
        busy = false
        if not data then return notify(err, 'error') end
        opened = true
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'open', title = OBJobCenterConfig.Name, data = data })
    end)
end

RegisterNetEvent('ob_jobcenter:client:open', openPanel)
RegisterCommand('empregos', openPanel, false)

local function registerTarget()
    if not npc or not DoesEntityExist(npc) or GetResourceState('ob_target') ~= 'started' then return end
    exports.ob_target:RegisterEntity(targetId, npc, {
        label = 'Consultar empregos',
        icon = '▣',
        event = 'ob_jobcenter:client:open',
        distance = tonumber(OBJobCenterConfig.Location.interactionDistance) or 3.0,
        canInteract = function(entity) return entity == npc and not opened and not busy end,
    })
end

AddEventHandler('ob_target:client:ready', registerTarget)

RegisterNUICallback('close', function(_, cb)
    closePanel()
    cb({ ok = true })
end)

RegisterNUICallback('refresh', function(_, cb)
    if not opened or busy then return cb({ ok = false, error = 'Aguarde a operacao atual.' }) end
    busy = true
    CreateThread(function()
        local data, err = requestStatus()
        busy = false
        cb(data and { ok = true, data = data } or { ok = false, error = err })
    end)
end)

for _, action in ipairs({ 'join', 'leave' }) do
    RegisterNUICallback(action, function(data, cb)
        if not opened or busy then return cb({ ok = false, error = 'Aguarde a operacao atual.' }) end
        busy = true
        CreateThread(function()
            local ok, success, message = pcall(OR.Callback.await, action, data and data.jobKey)
            busy = false
            if not ok then return cb({ ok = false, error = 'Falha ao contatar o servidor.' }) end
            notify(message or (success and 'Operacao concluida.' or 'Operacao recusada.'), success and 'success' or 'error')
            if not success then return cb({ ok = false, error = message }) end
            local refreshed, refreshError = requestStatus()
            cb({ ok = true, message = message, data = refreshed, error = refreshError })
        end)
    end)
end

local function createBlip()
    local cfg, coords = OBJobCenterConfig.Blip, OBJobCenterConfig.Location.coords
    if cfg.enabled ~= true or blip then return end
    blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, tonumber(cfg.sprite) or 407)
    SetBlipColour(blip, tonumber(cfg.colour) or 3)
    SetBlipScale(blip, tonumber(cfg.scale) or 0.75)
    SetBlipAsShortRange(blip, cfg.shortRange ~= false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(OBJobCenterConfig.Name)
    EndTextCommandSetBlipName(blip)
end

local function deleteNpc()
    if GetResourceState('ob_target') == 'started' then exports.ob_target:RemoveEntityOption(targetId) end
    if npc and DoesEntityExist(npc) then DeleteEntity(npc) end
    npc = nil
end

local function spawnNpc()
    if npc and DoesEntityExist(npc) then return end
    local cfg = OBJobCenterConfig.Location
    local model = joaat(cfg.npcModel)
    RequestModel(model)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(50) end
    if not HasModelLoaded(model) then return end
    npc = CreatePed(4, model, cfg.coords.x, cfg.coords.y, cfg.coords.z - 1.0, cfg.coords.w, false, false)
    if npc and npc ~= 0 then
        SetEntityInvincible(npc, true)
        FreezeEntityPosition(npc, true)
        SetBlockingOfNonTemporaryEvents(npc, true)
        SetPedCanRagdoll(npc, false)
        TaskStartScenarioInPlace(npc, cfg.scenario or 'WORLD_HUMAN_CLIPBOARD', 0, true)
        registerTarget()
    else
        npc = nil
    end
    SetModelAsNoLongerNeeded(model)
end

CreateThread(function()
    while LocalPlayer.state['or:loaded'] ~= true do Wait(250) end
    createBlip()
    local location = OBJobCenterConfig.Location
    while true do
        local distance = #(GetEntityCoords(PlayerPedId()) - vector3(location.coords.x, location.coords.y, location.coords.z))
        if distance <= (tonumber(location.spawnDistance) or 100.0) then
            spawnNpc()
        elseif npc then
            deleteNpc()
        end

        if distance <= (tonumber(location.interactionDistance) or 3.0)
            and GetResourceState('ob_target') ~= 'started' and not opened then
            OR.Help.Show('Pressione [E] para consultar empregos.')
            if IsControlJustReleased(0, 38) then openPanel() end
            Wait(0)
        else
            Wait(distance < 120.0 and 750 or 1500)
        end
    end
end)

AddEventHandler('onClientResourceStart', function(name)
    if name == 'ob_target' then Wait(500); registerTarget() end
end)

AddEventHandler('onClientResourceStop', function(name)
    if name ~= resource then return end
    closePanel()
    deleteNpc()
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
end)
