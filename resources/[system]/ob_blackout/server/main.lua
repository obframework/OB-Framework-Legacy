local STATE_KEY = 'ob:blackout'
local active = false
local override
local lastScheduleWindow
local automaticNightActive = false
local automaticRoll
local manualDisabledThisWindow = false
local manualRequests = {}
local lastReason = 'startup'
local lastChangedAt = os.time()

math.randomseed(os.time() + math.floor(GetGameTimer()))
math.random(); math.random(); math.random()

local function automaticConfig()
    return type(OBBlackoutConfig.Automatic) == 'table' and OBBlackoutConfig.Automatic or {}
end

local function manualConfig()
    return type(OBBlackoutConfig.Manual) == 'table' and OBBlackoutConfig.Manual or {}
end

local function itemsConfig()
    return type(OBBlackoutConfig.Items) == 'table' and OBBlackoutConfig.Items or {}
end

local function messages()
    return type(OBBlackoutConfig.Messages) == 'table' and OBBlackoutConfig.Messages or {}
end

local function integrations()
    return type(OBBlackoutConfig.Integrations) == 'table' and OBBlackoutConfig.Integrations or {}
end

local function notify(playerSource, message, kind)
    playerSource = tonumber(playerSource)
    if not playerSource or type(message) ~= 'string' or message == '' then return end
    TriggerClientEvent('ob_notification:client:notify', playerSource, message, kind or 'info')
end

local function fixedUserId(playerSource)
    local value = exports.ob_core:GetUserId(playerSource)
    return tonumber(value)
end

local function clock()
    if GetResourceState('ob_weather') ~= 'started' then return nil, nil end
    local ok, value = pcall(function() return exports.ob_weather:GetClock() end)
    if not ok or type(value) ~= 'table' then return nil, nil end
    local hour, minute = tonumber(value.hour), tonumber(value.minute)
    if not hour or not minute then return nil, nil end
    return math.floor(hour) % 24, math.floor(minute) % 60
end

local function minuteInsideWindow(minuteOfDay, startMinute, endMinute)
    if startMinute == endMinute then return true end
    if startMinute < endMinute then return minuteOfDay >= startMinute and minuteOfDay < endMinute end
    return minuteOfDay >= startMinute or minuteOfDay < endMinute
end

local function insideNightWindow(hour, minute)
    local config = automaticConfig()
    local startMinute = ((tonumber(config.startHour) or 19) % 24) * 60 + ((tonumber(config.startMinute) or 0) % 60)
    local endMinute = ((tonumber(config.endHour) or 6) % 24) * 60 + ((tonumber(config.endMinute) or 0) % 60)
    return minuteInsideWindow((hour * 60) + minute, startMinute, endMinute)
end

local function automaticChancePercent()
    return math.max(0.0, math.min(100.0, tonumber(automaticConfig().chancePercent) or 10.0))
end

local function insideAutomaticWindow(hour, minute)
    if automaticConfig().enabled == false then return false end
    return insideNightWindow(hour, minute)
end

local function modeName()
    if not override then return 'automatic' end
    return override.owner == 'admin' and 'admin' or 'manual'
end

local function statePayload(hour, minute)
    local integration = integrations()
    local scheduleWindow = hour ~= nil and insideNightWindow(hour, minute) or false
    return {
        active = active,
        reason = lastReason,
        mode = modeName(),
        automaticEnabled = automaticConfig().enabled ~= false,
        scheduled = scheduleWindow,
        automaticSelected = scheduleWindow and automaticNightActive or false,
        automaticChancePercent = automaticChancePercent(),
        automaticRoll = automaticRoll,
        manualDisabledThisWindow = scheduleWindow and manualDisabledThisWindow or false,
        hour = hour,
        minute = minute,
        changedAt = lastChangedAt,
        phoneDisabled = active and integration.disablePhone == true or false,
        radioLimited = active and integration.limitRadio == true or false,
        radioRange = tonumber(integration.radioRange) or 500.0,
    }
end

local function publish(reason, announce)
    local hour, minute = clock()
    lastReason = reason or lastReason
    lastChangedAt = os.time()
    local payload = statePayload(hour, minute)
    GlobalState[STATE_KEY] = payload
    TriggerClientEvent('ob_blackout:client:apply', -1, payload)
    TriggerEvent('ob_blackout:server:changed', payload)

    local notification = type(OBBlackoutConfig.Notifications) == 'table' and OBBlackoutConfig.Notifications or {}
    if announce == true and notification.announceChanges ~= false then
        TriggerClientEvent('ob_notification:client:notify', -1,
            active and (notification.blackout or 'A energia da cidade foi interrompida.')
                or (notification.restored or 'A energia da cidade foi restabelecida.'),
            active and 'warning' or 'success')
    end
end

local function setActive(nextState, reason, announce, forcePublish)
    nextState = nextState == true
    if active == nextState and forcePublish ~= true then return false end
    local changed = active ~= nextState
    active = nextState
    publish(reason, changed and announce)
    return changed
end

local function reconcile(reason, announce)
    local hour, minute = clock()
    if hour == nil then return false, 'Horario sincronizado indisponivel.' end
    local scheduleWindow = insideNightWindow(hour, minute)
    local automaticWindow = insideAutomaticWindow(hour, minute)
    local enteringWindow = scheduleWindow and lastScheduleWindow ~= true
    local scheduleChanged = lastScheduleWindow ~= nil and scheduleWindow ~= lastScheduleWindow

    if enteringWindow then
        automaticRoll = math.random(1, 10000) / 100.0
        automaticNightActive = automaticConfig().enabled ~= false and automaticRoll <= automaticChancePercent()
    elseif not scheduleWindow then
        automaticNightActive = false
        automaticRoll = nil
        manualDisabledThisWindow = false
    end

    local overrideCleared = false
    if scheduleChanged and override and override.clearAtBoundary == true then
        override = nil
        overrideCleared = true
    end
    lastScheduleWindow = scheduleWindow
    local desired = override and override.active == true or (not override and automaticWindow and automaticNightActive)
    local stateReason = reason or (override and override.owner or 'automatic')
    local forcePublish = stateReason ~= 'automatic' or overrideCleared or scheduleChanged or enteringWindow
    setActive(desired, stateReason, announce, forcePublish)
    return true
end

local function adminStatus(playerSource)
    if not exports.ob_admin:HasPermission(playerSource, 'world.time') then
        return nil, 'Sem permissao para controlar a energia.'
    end
    local hour, minute = clock()
    if hour == nil then return nil, 'O horario do ob_weather esta indisponivel.' end
    return statePayload(hour, minute)
end

local function setAdminMode(playerSource, action)
    if not exports.ob_admin:HasPermission(playerSource, 'world.time') then
        return nil, 'Sem permissao para controlar a energia.'
    end
    if not OR.Security.rateLimit(playerSource, 'blackout:admin', 4, 10000) then
        return nil, 'Aguarde um instante antes de alterar novamente.'
    end

    if action == 'off' then
        override = { active = true, owner = 'admin', clearAtBoundary = false }
    elseif action == 'on' then
        override = { active = false, owner = 'admin', clearAtBoundary = false }
    elseif action == 'auto' then
        override = nil
    else
        return nil, 'Acao de energia invalida.'
    end

    local actorUserId = fixedUserId(playerSource)
    local ok, errorMessage = reconcile(('admin:%s:%s'):format(actorUserId or playerSource, action), true)
    if not ok then return nil, errorMessage end
    print(('[ob_blackout] ID fixo %s alterou o modo da energia para %s.'):format(actorUserId or 'desconhecido', action))
    return adminStatus(playerSource)
end

OR.Callback.register('adminStatus', adminStatus)
OR.Callback.register('adminSet', setAdminMode)

local function actionItem(action)
    local config = itemsConfig()
    if action == 'disable' then return tostring(config.disable or 'blackout_disruptor') end
    if action == 'restore' then return tostring(config.restore or 'blackout_toolbox') end
end

local function actionPoint(action)
    local config = manualConfig()
    if action == 'disable' then return type(config.disablePoint) == 'table' and config.disablePoint or nil end
    if action == 'restore' then return type(config.restorePoint) == 'table' and config.restorePoint or nil end
end

local function nearActionPoint(playerSource, action)
    if manualConfig().requireNearPointForItems == false then return true end
    local point = actionPoint(action)
    local coords = point and point.coords
    if not coords or tonumber(coords.x) == nil or tonumber(coords.y) == nil or tonumber(coords.z) == nil then
        return false
    end
    local ped = GetPlayerPed(playerSource)
    if not ped or ped <= 0 or not DoesEntityExist(ped) then return false end
    local playerCoords = GetEntityCoords(ped)
    local pointCoords = vector3(tonumber(coords.x) + 0.0, tonumber(coords.y) + 0.0, tonumber(coords.z) + 0.0)
    return #(playerCoords - pointCoords) <= math.max(1.0, tonumber(point.interactDistance) or 2.5) + 1.25
end

local function manualPrecheck(playerSource, action, requirePoint)
    local config = manualConfig()
    local text = messages()
    if config.enabled == false then return false, text.unavailable or 'O sistema de energia esta indisponivel.' end
    if action ~= 'disable' and action ~= 'restore' then return false, 'Procedimento de energia invalido.' end
    if not GetPlayerName(playerSource) then return false, 'Personagem indisponivel.' end
    if action == 'disable' and active then return false, text.alreadyActive or 'A energia ja esta desligada.' end
    if action == 'restore' and not active then return false, text.alreadyRestored or 'A energia ja esta ligada.' end

    if action == 'disable' and config.requireNightWindowForDisable ~= false then
        local hour, minute = clock()
        if hour == nil or not insideNightWindow(hour, minute) then
            return false, text.notInWindow or 'O terminal nao pode ser usado neste horario.'
        end
    end
    if action == 'disable' and config.oneDisablePerNight ~= false and manualDisabledThisWindow then
        return false, text.alreadyUsedTonight or 'Esta noite ja houve uma invasao da rede eletrica.'
    end
    if requirePoint ~= false and not nearActionPoint(playerSource, action) then
        return false, action == 'disable'
            and (text.needBeNearDisable or 'Va ate o terminal de invasao.')
            or (text.needBeNearRestore or 'Va ate o painel eletrico.')
    end

    if GetResourceState('ob_inventory') ~= 'started' then return false, 'Inventario indisponivel.' end
    local itemName = actionItem(action)
    local count, countError = exports.ob_inventory:GetItemCount(playerSource, itemName)
    if tonumber(count) == nil then return false, countError or 'Nao foi possivel verificar o item.' end
    if tonumber(count) < 1 then
        return false, action == 'disable'
            and (text.needDisableItem or 'Voce precisa de um Disruptor de Rede.')
            or (text.needRestoreItem or 'Voce precisa de uma Caixa de Ferramentas Eletrica.')
    end
    return true, nil, itemName
end

local function beginManual(playerSource, action, requirePoint)
    playerSource = tonumber(playerSource)
    action = tostring(action or ''):lower()
    if not playerSource then return false, 'Personagem indisponivel.' end
    if not OR.Security.rateLimit(playerSource, 'blackout:manual', 3, 10000) then
        return false, 'Aguarde um instante antes de tentar novamente.'
    end

    local existing = manualRequests[playerSource]
    if existing and GetGameTimer() <= existing.expiresAt then
        return false, 'Voce ja iniciou um procedimento de energia.'
    end
    manualRequests[playerSource] = nil

    local allowed, errorMessage = manualPrecheck(playerSource, action, requirePoint)
    if not allowed then return false, errorMessage end

    local timeout = math.max(15000, math.floor(tonumber(manualConfig().requestTimeoutMs) or 90000))
    local token = ('%s:%s:%s'):format(playerSource, GetGameTimer(), math.random(100000, 999999))
    manualRequests[playerSource] = {
        action = action,
        token = token,
        requirePoint = requirePoint ~= false,
        startedAt = GetGameTimer(),
        expiresAt = GetGameTimer() + timeout,
    }
    TriggerClientEvent('ob_blackout:client:startManual', playerSource, action, token)
    return true, '', false
end

RegisterNetEvent('ob_blackout:server:beginManual', function(action)
    local playerSource = tonumber(source)
    if not playerSource then return end
    local ok, errorMessage = beginManual(playerSource, action, true)
    if not ok then notify(playerSource, errorMessage or 'Nao foi possivel iniciar o procedimento.', 'error') end
end)

RegisterNetEvent('ob_blackout:server:finishManual', function(token, minigameSuccess)
    local playerSource = tonumber(source)
    if not playerSource then return end
    local request = manualRequests[playerSource]
    if not request or tostring(token or '') ~= request.token or GetGameTimer() > request.expiresAt then
        manualRequests[playerSource] = nil
        return notify(playerSource, messages().requestExpired or 'O procedimento expirou. Tente novamente.', 'error')
    end
    manualRequests[playerSource] = nil
    local minimumCompletion = math.max(1000, math.floor(tonumber(manualConfig().minimumCompletionMs) or 2500))
    if minigameSuccess == true and GetGameTimer() - request.startedAt < minimumCompletion then
        return notify(playerSource, 'Procedimento recusado por conclusao invalida.', 'error')
    end
    if minigameSuccess ~= true then
        return notify(playerSource, messages().minigameFailed or 'O procedimento falhou. O item nao foi consumido.', 'error')
    end

    local allowed, errorMessage, itemName = manualPrecheck(playerSource, request.action, request.requirePoint)
    if not allowed then return notify(playerSource, errorMessage or 'O procedimento nao pode mais ser concluido.', 'error') end

    local itemSettings = itemsConfig()
    local consume = request.action == 'disable'
        and itemSettings.consumeDisableOnSuccess ~= false
        or request.action == 'restore' and itemSettings.consumeRestoreOnSuccess ~= false
    if consume then
        local removed, removeError = exports.ob_inventory:RemoveItem(playerSource, itemName, 1)
        if removed ~= true then return notify(playerSource, removeError or 'Nao foi possivel consumir o item.', 'error') end
    end

    local previousOverride = override
    local previousManualDisabled = manualDisabledThisWindow
    override = {
        active = request.action == 'disable',
        owner = 'manual',
        clearAtBoundary = manualConfig().clearAtNextScheduleBoundary ~= false,
    }
    if request.action == 'disable' then manualDisabledThisWindow = true end

    local userId = fixedUserId(playerSource)
    local ok, reconcileError = reconcile(('manual:%s:%s'):format(userId or playerSource, request.action), true)
    if not ok then
        override = previousOverride
        manualDisabledThisWindow = previousManualDisabled
        if consume then
            local refunded, refundError = exports.ob_inventory:AddItem(playerSource, itemName, 1)
            if refunded ~= true then
                print(('[ob_blackout] CRITICO: nao foi possivel devolver %s ao ID fixo %s: %s'):format(
                    itemName, userId or 'desconhecido', tostring(refundError)
                ))
            end
        end
        return notify(playerSource, reconcileError or 'Nao foi possivel alterar a energia.', 'error')
    end

    print(('[ob_blackout] ID fixo %s concluiu %s com %s; blackout=%s.'):format(
        userId or 'desconhecido', request.action, itemName, tostring(active)
    ))
end)

local function useItem(playerSource, itemName)
    itemName = tostring(itemName or ''):lower()
    local action
    if itemName == actionItem('disable'):lower() then action = 'disable' end
    if itemName == actionItem('restore'):lower() then action = 'restore' end
    if not action then return false, 'Item de energia invalido.', false end
    return beginManual(playerSource, action, manualConfig().requireNearPointForItems ~= false)
end

exports('UseItem', useItem)
exports('IsActive', function() return active end)
exports('GetState', function()
    local hour, minute = clock()
    return statePayload(hour, minute)
end)

AddEventHandler('playerDropped', function()
    local playerSource = tonumber(source)
    if playerSource then manualRequests[playerSource] = nil end
end)

CreateThread(function()
    Wait(500)
    local ok, errorMessage = reconcile('startup', false)
    if not ok then print(('[ob_blackout] %s'):format(errorMessage or 'Falha ao sincronizar horario.')) end

    while true do
        Wait(math.max(500, math.floor(tonumber(automaticConfig().checkIntervalMs) or 2000)))
        reconcile('automatic', true)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    GlobalState[STATE_KEY] = { active = false, reason = 'resource_stop', mode = 'automatic' }
    TriggerClientEvent('ob_blackout:client:apply', -1, { active = false, reason = 'resource_stop', mode = 'automatic' })
end)
