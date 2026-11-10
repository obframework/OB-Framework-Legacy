local resource = GetCurrentResourceName()
local calls, latestCall, gunshotPending, panelOpen, accepting = {}, nil, false, false, {}
local refreshCalls

local function streetAt(coords)
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = streetHash and streetHash ~= 0 and GetStreetNameFromHashKey(streetHash) or 'local desconhecido'
    if crossingHash and crossingHash ~= 0 then street = street .. ' / ' .. GetStreetNameFromHashKey(crossingHash) end
    return street
end

local function panelCalls()
    local result = {}
    for _, entry in pairs(calls) do
        local call = entry.data
        result[#result + 1] = {
            id = call.id, code = call.code, title = call.title, message = call.message,
            street = call.street, priority = call.priority, createdAt = call.createdAt,
            expiresAt = call.expiresAt, accepted = entry.accepted == true, exclusive = call.exclusive == true,
        }
    end
    table.sort(result, function(a, b) return a.id > b.id end)
    return result
end

local function updatePanel()
    if panelOpen then SendNUIMessage({ action = 'panel', visible = true, calls = panelCalls() }) end
end

local function closePanel()
    if not panelOpen then return end
    panelOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'panel', visible = false })
end

local function openPanel()
    if panelOpen or IsPauseMenuActive() then return end
    panelOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'panel', visible = true, calls = panelCalls() })
    if refreshCalls then CreateThread(refreshCalls) end
end

local function removeCall(id)
    local entry = calls[id]
    if not entry then return end
    for _, blip in ipairs(entry.blips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
    calls[id] = nil
    if latestCall and latestCall.id == id then latestCall = nil end
    SendNUIMessage({ action = 'remove', id = id })
    updatePanel()
end

local function routeCall(id)
    local entry = calls[tonumber(id)]
    if not entry then return false end
    local call = entry.data
    SetNewWaypoint(call.coords.x + 0.0, call.coords.y + 0.0)
    entry.accepted = true
    SendNUIMessage({ action = 'accepted', id = call.id })
    updatePanel()
    return true
end

local function acceptCall(id)
    id = tonumber(id)
    local entry = id and calls[id]
    if not entry or accepting[id] then return false end
    if entry.data.exclusive ~= true then return routeCall(id) end
    accepting[id] = true
    CreateThread(function()
        local ok, result = OR.Callback.await('acceptCall', id)
        accepting[id] = nil
        if not ok or type(result) ~= 'table' or type(result.coords) ~= 'table' then
            removeCall(id)
            OR.Notify(tostring(result or 'Essa ocorrencia ja foi aceita.'), 'error')
            return
        end
        SetNewWaypoint(result.coords.x + 0.0, result.coords.y + 0.0)
        removeCall(id)
        OR.Notify(('%s aceita. Rota marcada no GPS.'):format(result.title or 'Ocorrencia'), 'success')
    end)
    return true
end

local function storeCall(call, showAlert)
    if type(call) ~= 'table' or type(call.coords) ~= 'table' then return false end
    removeCall(call.id)
    call.street = streetAt(call.coords)
    local blips = {}
    if (tonumber(call.radius) or 0) > 0 then
        local radius = AddBlipForRadius(call.coords.x, call.coords.y, call.coords.z, call.radius + 0.0)
        SetBlipColour(radius, tonumber(call.blip and call.blip.colour) or 1)
        SetBlipAlpha(radius, 95)
        blips[#blips + 1] = radius
    end
    if call.radiusOnly ~= true then
        local point = AddBlipForCoord(call.coords.x, call.coords.y, call.coords.z)
        SetBlipSprite(point, tonumber(call.blip and call.blip.sprite) or 161)
        SetBlipColour(point, tonumber(call.blip and call.blip.colour) or 1)
        SetBlipScale(point, tonumber(call.blip and call.blip.scale) or 0.9)
        SetBlipFlashes(point, call.priority >= 3)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(('%s - %s'):format(call.code, call.title))
        EndTextCommandSetBlipName(point)
        blips[#blips + 1] = point
    end
    calls[call.id] = { data = call, blips = blips, accepted = false }
    if showAlert then
        latestCall = call
        SendNUIMessage({ action = 'alert', call = call, cardDuration = Dispatch.cardDuration })
    end
    updatePanel()
    if showAlert and call.sound then PlaySoundFrontend(-1, 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET', true) end
    -- A biblioteca os nao esta disponivel no runtime cliente do FiveM.
    -- Alertas novos usam a duracao completa; a sincronizacao envia o restante.
    local remaining = math.max(1, math.floor(tonumber(call.remaining) or tonumber(call.duration) or Dispatch.defaultDuration))
    SetTimeout(remaining * 1000, function() removeCall(call.id) end)
    return true
end

RegisterNetEvent(resource .. ':client:alert', function(call)
    if source ~= 65535 then return end
    storeCall(call, true)
end)

refreshCalls = function()
    local result = OR.Callback.await('activeCalls')
    if type(result) ~= 'table' then return end
    local active = {}
    for _, call in ipairs(result) do
        local id = tonumber(call.id)
        if id then
            active[id] = true
            if not calls[id] then storeCall(call, false) end
        end
    end
    local stale = {}
    for id in pairs(calls) do if not active[id] then stale[#stale + 1] = id end end
    for _, id in ipairs(stale) do removeCall(id) end
    updatePanel()
end

RegisterNetEvent(resource .. ':client:remove', function(id)
    if source ~= 65535 then return end
    removeCall(tonumber(id))
end)

RegisterCommand('+ob_dispatch_accept', function()
    if not latestCall or not calls[latestCall.id] or IsNuiFocused() or IsPauseMenuActive() then return end
    acceptCall(latestCall.id)
end, false)
RegisterCommand('-ob_dispatch_accept', function() end, false)
RegisterKeyMapping('+ob_dispatch_accept', 'Aceitar ultimo chamado', 'keyboard', Dispatch.acceptKey or 'Y')

RegisterCommand('+ob_dispatch_decline', function()
    if not latestCall or not calls[latestCall.id] or IsNuiFocused() or IsPauseMenuActive() then return end
    SendNUIMessage({ action = 'declined', id = latestCall.id })
    latestCall = nil
end, false)
RegisterCommand('-ob_dispatch_decline', function() end, false)
RegisterKeyMapping('+ob_dispatch_decline', 'Recusar ultimo chamado', 'keyboard', Dispatch.declineKey or 'N')

RegisterCommand('+ob_dispatch_panel', function()
    if panelOpen then closePanel() else openPanel() end
end, false)
RegisterCommand('-ob_dispatch_panel', function() end, false)
RegisterKeyMapping('+ob_dispatch_panel', 'Abrir central de ocorrencias', 'keyboard', Dispatch.panelKey or 'F2')

RegisterNUICallback('close', function(_, callback)
    closePanel()
    callback({ ok = true })
end)

RegisterNUICallback('route', function(data, callback)
    local ok = type(data) == 'table' and acceptCall(data.id)
    callback({ ok = ok == true })
end)

CreateThread(function()
    while true do
        local delay, ped = 350, PlayerPedId()
        if Dispatch.gunshot and Dispatch.gunshot.enabled and LocalPlayer.state['or:loaded'] == true
            and LocalPlayer.state['or:downed'] ~= true and not IsNuiFocused() then
            if IsPedArmed(ped, 4) and IsPedShooting(ped) and not gunshotPending then
                gunshotPending = true
                TriggerServerEvent(resource .. ':server:gunshot', GetSelectedPedWeapon(ped))
                SetTimeout(1200, function() gunshotPending = false end)
            end
            delay = 80
        end
        Wait(delay)
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= resource then return end
    for id in pairs(calls) do removeCall(id) end
    panelOpen = false
    SetNuiFocus(false, false)
end)
