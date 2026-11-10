local state = { imprisoned = false, remainingSeconds = 0, escapeStage = 0 }
local servicePeds = {}
local trackerBlips = {}
local busy = false
local outsideSince

local function notify(message, kind)
    OR.Notify(message or 'Operação concluída.', kind or 'info')
end

local function coordsOf(entry)
    return vector3(entry.x + 0.0, entry.y + 0.0, entry.z + 0.0)
end

local function teleport(entry)
    if type(entry) ~= 'table' then return end
    local ped = PlayerPedId()
    if not ped or ped <= 0 or not DoesEntityExist(ped) then return end
    RequestCollisionAtCoord(entry.x + 0.0, entry.y + 0.0, entry.z + 0.0)
    SetEntityCoordsNoOffset(ped, entry.x + 0.0, entry.y + 0.0, entry.z + 0.0, false, false, false)
    SetEntityHeading(ped, entry.w or 0.0)
end

local function setState(payload)
    payload = type(payload) == 'table' and payload or { imprisoned = false }
    state.imprisoned = payload.imprisoned == true
    state.sentenceId = tonumber(payload.sentenceId)
    state.totalSeconds = tonumber(payload.totalSeconds) or 0
    state.remainingSeconds = tonumber(payload.remainingSeconds) or 0
    state.remainingMonths = tonumber(payload.remainingMonths) or 0
    state.reason = payload.reason or ''
    state.activeService = payload.activeService
    state.currentPoint = tonumber(payload.currentPoint)
    state.completedServices = tonumber(payload.completedServices) or 0
    state.escapeStage = tonumber(payload.escapeStage) or 0
    if not state.imprisoned then outsideSince = nil end
end

local function drawText3D(entry, text)
    SetDrawOrigin(entry.x + 0.0, entry.y + 0.0, entry.z + 1.0, 0)
    SetTextScale(0.31, 0.31)
    SetTextFont(4)
    SetTextCentre(true)
    SetTextColour(240, 248, 255, 225)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function drawHud()
    local total = math.max(0, math.floor(state.remainingSeconds or 0))
    local minutes, seconds = math.floor(total / 60), total % 60
    SetTextFont(4)
    SetTextScale(0.38, 0.38)
    SetTextColour(235, 245, 255, 230)
    SetTextOutline()
    SetTextRightJustify(true)
    SetTextWrap(0.72, 0.965)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(('PRISÃO  %02d:%02d'):format(minutes, seconds))
    EndTextCommandDisplayText(0.965, 0.09)
end

local function safeClearTasks(ped)
    if ped and ped == PlayerPedId() and ped > 0 and DoesEntityExist(ped) then
        ClearPedTasks(ped)
    end
end

local function requestStatus()
    local payload, errorMessage = OR.Callback.await('status')
    if not payload then return false, errorMessage end
    setState(payload)
    return true
end

RegisterNetEvent('ob_prison:client:jailed', function(payload)
    setState(payload and payload.sentence)
    teleport(payload and payload.entry)
    notify(('Você foi preso. Pena: %s mês(es).'):format(state.remainingMonths), 'error')
end)

RegisterNetEvent('ob_prison:client:restore', function(payload)
    setState(payload and payload.sentence)
    if payload and payload.teleport then teleport(payload.entry) end
    if state.imprisoned then notify('Sua pena ativa foi restaurada.', 'warning') end
end)

RegisterNetEvent('ob_prison:client:update', function(payload)
    setState(payload)
end)

RegisterNetEvent('ob_prison:client:released', function(payload)
    setState({ imprisoned = false })
    teleport(payload and payload.coords)
    notify(payload and payload.message or 'Você foi liberado.', payload and payload.escaped and 'warning' or 'success')
end)

RegisterNetEvent('ob_prison:client:returnToPrison', function(entry)
    teleport(entry)
    outsideSince = nil
    notify('Você saiu do perímetro sem concluir a fuga e foi trazido de volta.', 'error')
end)

local function removeTracker(userId)
    userId = tonumber(userId)
    local blip = userId and trackerBlips[userId]
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
    trackerBlips[userId] = nil
end

RegisterNetEvent('ob_prison:client:updateTracker', function(payload)
    local userId = payload and tonumber(payload.userId)
    local coords = payload and payload.coords
    if not userId or type(coords) ~= 'table' then return end
    local blip = trackerBlips[userId]
    if not blip or not DoesBlipExist(blip) then
        blip = AddBlipForCoord(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
        trackerBlips[userId] = blip
        SetBlipSprite(blip, 161)
        SetBlipColour(blip, 1)
        SetBlipScale(blip, 0.9)
        SetBlipAsShortRange(blip, false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(('Fugitivo: %s (ID %s)'):format(payload.name or 'Desconhecido', userId))
        EndTextCommandSetBlipName(blip)
        notify(('Rastreador de fuga ativo: %s.'):format(payload.name or ('ID ' .. userId)), 'warning')
    else
        SetBlipCoords(blip, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    end
end)

RegisterNetEvent('ob_prison:client:stopTracker', removeTracker)

local function spawnServicePeds()
    for serviceId, service in pairs(OBPrisonConfig.Services or {}) do
        local npc = service.npc
        if npc and not servicePeds[serviceId] then
            local model = joaat(npc.model or 's_m_m_prisguard_01')
            if OR.Model.Load(model, 8000) then
                local ped = CreatePed(4, model, npc.x + 0.0, npc.y + 0.0, npc.z - 1.0, npc.w or 0.0, false, false)
                if ped and ped > 0 then
                    SetEntityInvincible(ped, true)
                    FreezeEntityPosition(ped, true)
                    SetBlockingOfNonTemporaryEvents(ped, true)
                    servicePeds[serviceId] = ped
                end
                SetModelAsNoLongerNeeded(model)
            end
        end
    end
end

local function runServicePoint()
    if busy then return end
    busy = true
    local action, errorMessage = OR.Callback.await('beginServicePoint')
    if not action then busy = false return notify(errorMessage or 'Não foi possível iniciar o trabalho.', 'error') end
    local ped = PlayerPedId()
    if action.scenario then TaskStartScenarioInPlace(ped, action.scenario, 0, true) end
    local completed = OR.Progress.Run({ label = action.label or 'Trabalhando...', duration = action.durationMs or 7000 })
    safeClearTasks(ped)
    if not completed then
        OR.Callback.await('abortServicePoint', action.token)
        busy = false
        return notify('Trabalho cancelado.', 'error')
    end
    local ok, message, updated = OR.Callback.await('finishServicePoint', action.token)
    if type(updated) == 'table' then setState(updated) end
    busy = false
    notify(message or 'Trabalho concluído.', ok and 'success' or 'error')
end

local function runEscapeStage()
    if busy then return end
    busy = true
    local action, errorMessage = OR.Callback.await('beginEscapeStage')
    if not action then busy = false return notify(errorMessage or 'Não foi possível iniciar a fuga.', 'error') end
    local startedAt = GetGameTimer()
    local succeeded = false
    if GetResourceState('ob_minigame') == 'started' then
        succeeded = exports.ob_minigame:Keypress(action.minigame or {}) == true
    else
        notify('Minigame da fuga indisponível.', 'error')
    end
    if succeeded then
        local remaining = math.max(0, (tonumber(action.minimumMs) or 4000) - (GetGameTimer() - startedAt))
        if remaining > 0 then Wait(remaining) end
    end
    local ok, message, updated = OR.Callback.await('finishEscapeStage', action.token, succeeded)
    if type(updated) == 'table' then setState(updated) end
    busy = false
    notify(message or 'Etapa encerrada.', ok and 'success' or 'error')
end

CreateThread(function()
    while LocalPlayer.state['or:loaded'] ~= true do Wait(500) end
    spawnServicePeds()
    Wait(1000)
    requestStatus()
end)

RegisterNetEvent('ob_core:client:playerSpawned', function()
    Wait(1000)
    spawnServicePeds()
    requestStatus()
end)

CreateThread(function()
    while true do
        if not state.imprisoned then
            Wait(1000)
        else
            local sleep = 0
            local ped = PlayerPedId()
            local position = GetEntityCoords(ped)
            drawHud()

            for serviceId, service in pairs(OBPrisonConfig.Services or {}) do
                local npc = service.npc
                local distance = #(position - coordsOf(npc))
                if distance < 15.0 then sleep = 0 end
                if distance <= (OBPrisonConfig.Service.InteractDistance or 2.0) then
                    if not state.activeService then
                        drawText3D(npc, ('[E] %s'):format(service.label))
                        if IsControlJustReleased(0, 38) and not busy then
                            local ok, message, updated = OR.Callback.await('startService', serviceId)
                            if type(updated) == 'table' then setState(updated) end
                            notify(message, ok and 'success' or 'error')
                        end
                    elseif state.activeService == serviceId then
                        drawText3D(npc, 'Trabalho ativo · F7 cancela')
                    end
                end
            end

            local activeService = state.activeService and OBPrisonConfig.Services[state.activeService]
            local point = activeService and activeService.points[state.currentPoint or 0]
            if point then
                local distance = #(position - coordsOf(point))
                if distance < 30.0 then
                    sleep = 0
                    DrawMarker(1, point.x, point.y, point.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        1.4, 1.4, 0.65, 31, 169, 255, 150, false, false, 2, false, nil, nil, false)
                    if distance <= (OBPrisonConfig.Service.InteractDistance or 2.0) then
                        drawText3D(point, ('[E] %s'):format(activeService.label))
                        if IsControlJustReleased(0, 38) then runServicePoint() end
                    end
                end
                if IsControlJustReleased(0, 168) and not busy then
                    local ok, message = OR.Callback.await('cancelService')
                    if ok then state.activeService, state.currentPoint = nil, nil end
                    notify(message, ok and 'success' or 'error')
                end
            end

            local escapeIndex = math.max(1, state.escapeStage or 0)
            local escapeStage = OBPrisonConfig.Escape.Stages[escapeIndex]
            if escapeStage then
                local distance = #(position - coordsOf(escapeStage.coords))
                if distance < 25.0 then
                    sleep = 0
                    DrawMarker(1, escapeStage.coords.x, escapeStage.coords.y, escapeStage.coords.z - 1.0,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.1, 1.1, 0.5,
                        220, 65, 80, 140, false, false, 2, false, nil, nil, false)
                    if distance <= 2.0 then
                        local prefix = state.escapeStage == 0 and ('Requer: ' .. (OBPrisonConfig.Escape.Item or 'chave')) or ('Etapa ' .. escapeIndex)
                        drawText3D(escapeStage.coords, ('[E] %s · %s'):format(escapeStage.label, prefix))
                        if IsControlJustReleased(0, 38) then runEscapeStage() end
                    end
                end
            end

            local boundary = OBPrisonConfig.Boundary
            local boundaryDistance = #(position - coordsOf(boundary.center))
            if boundaryDistance > (boundary.radius or 200.0) then
                outsideSince = outsideSince or GetGameTimer()
                local remaining = math.max(0, math.ceil(((boundary.graceSeconds or 5) * 1000 - (GetGameTimer() - outsideSince)) / 1000))
                OR.Help.Show(('Retorne ao perímetro da prisão em %ss.'):format(remaining))
                if remaining <= 0 then
                    TriggerServerEvent('ob_prison:server:boundaryViolation')
                    outsideSince = GetGameTimer() + 10000
                end
            else
                if outsideSince then OR.Help.Hide() end
                outsideSince = nil
            end
            Wait(sleep)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        if state.imprisoned and state.remainingSeconds > 0 then
            state.remainingSeconds = math.max(0, state.remainingSeconds - 1)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    OR.Help.Hide()
    if GetResourceState('ob_minigame') == 'started' then exports.ob_minigame:Cancel() end
    for _, ped in pairs(servicePeds) do
        if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    for userId in pairs(trackerBlips) do removeTracker(userId) end
end)
