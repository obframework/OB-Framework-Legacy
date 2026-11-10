local escorts = {}
local restrainedPlayers = {}
local itemAttempts = {}
local searchRequests = {}
local searchAuthorizations = {}
local takedownCooldowns = {}
local activeTakedowns = {}
local databaseReady = false

local function validSource(value)
    value = tonumber(value)
    return value and value > 0 and GetPlayerName(value) and value or nil
end

local function notify(playerSource, message, kind)
    playerSource = validSource(playerSource)
    if playerSource then
        exports.ob_notification:Notify(playerSource, message, kind or 'info')
    end
end

local function userId(playerSource)
    -- Um export Lua pode retornar zero valores enquanto o core reinicia. A
    -- atribuicao normaliza esse caso para nil antes de chamar tonumber.
    local value = exports.ob_core:GetUserId(playerSource)
    return tonumber(value)
end

local function characterName(playerSource)
    return exports.ob_core:GetFullName(playerSource)
        or GetPlayerName(playerSource)
        or ('ID %s'):format(tostring(playerSource))
end

local function consentConfig()
    return type(OBPoliceConfig.ConsentSearch) == 'table' and OBPoliceConfig.ConsentSearch or {}
end

local function isPolice(playerSource)
    playerSource = validSource(playerSource)
    if not playerSource or GetResourceState('ob_org') ~= 'started' then return false end
    return exports.ob_org:HasPermission(
        playerSource,
        OBPoliceConfig.Permission or 'police',
        OBPoliceConfig.RequireDuty ~= false
    ) == true
end

local function isPoliceMember(playerSource)
    playerSource = validSource(playerSource)
    if not playerSource or GetResourceState('ob_org') ~= 'started' then return false end
    return exports.ob_org:HasPermission(
        playerSource,
        OBPoliceConfig.Permission or 'police',
        false
    ) == true
end

local function isRestrained(playerSource)
    playerSource = validSource(playerSource)
    return playerSource and restrainedPlayers[playerSource] == true or false
end

exports('IsRestrained', isRestrained)

local function playersAreClose(firstSource, secondSource, maximum)
    firstSource, secondSource = validSource(firstSource), validSource(secondSource)
    if not firstSource or not secondSource or firstSource == secondSource then return false end
    local firstPed, secondPed = GetPlayerPed(firstSource), GetPlayerPed(secondSource)
    if not firstPed or firstPed <= 0 or not secondPed or secondPed <= 0 then return false end
    return #(GetEntityCoords(firstPed) - GetEntityCoords(secondPed)) <= (tonumber(maximum) or 3.0)
end

-- GetEntityForwardVector e client-only e nao existe no runtime servidor.
-- Reconstroi o vetor frontal horizontal pelo heading, mantendo no servidor
-- a validacao de que o alvo realmente esta diante do policial.
local function entityForwardFromHeading(entity)
    local heading = tonumber(GetEntityHeading(entity))
    if not heading then return nil end
    local radians = math.rad(heading)
    return {
        x = -math.sin(radians),
        y = math.cos(radians),
    }
end

local function audit(action, officerSource, targetSource, detail)
    print(('[ob_police] %s officer_user_id=%s target_user_id=%s detail=%s'):format(
        action,
        userId(officerSource) or 'n/a',
        userId(targetSource) or 'n/a',
        tostring(detail or '-')
    ))
end

local function stopEscort(targetSource)
    targetSource = tonumber(targetSource)
    if not targetSource then return false end
    local officerSource = tonumber(escorts[targetSource])
    escorts[targetSource] = nil
    local state = validSource(targetSource) and Player(targetSource).state or nil
    if state then
        state:set('ob:escortedBy', nil, true)
        TriggerClientEvent('ob_police:client:escortChanged', targetSource, nil)
    end
    if validSource(officerSource) then
        TriggerClientEvent('ob_police:client:escortState', officerSource, nil)
    end
    return true
end

local function stopEscortsByOfficer(officerSource)
    officerSource = tonumber(officerSource)
    for targetSource, currentOfficer in pairs(escorts) do
        if tonumber(currentOfficer) == officerSource then stopEscort(targetSource) end
    end
end

exports('StopEscort', stopEscort)

local function restraintItems()
    return type(OBPoliceConfig.Items) == 'table' and OBPoliceConfig.Items or {}
end

local function isLockpickItem(itemName)
    local items = restraintItems()
    return type(items.Lockpicks) == 'table' and items.Lockpicks[itemName] == true
end

local function actorCanUseItems(playerSource)
    playerSource = validSource(playerSource)
    if not playerSource then return false end
    local state = Player(playerSource).state
    return state['or:downed'] ~= true
        and state['or:restrained'] ~= true
        and state['ob:takedown'] ~= true
        and not isRestrained(playerSource)
end

local function closestTarget(playerSource, restrainedWanted, handsUpWanted)
    playerSource = validSource(playerSource)
    if not playerSource then return nil end
    local ped = GetPlayerPed(playerSource)
    if not ped or ped <= 0 then return nil end
    local coords = GetEntityCoords(ped)
    local maximum = tonumber(OBPoliceConfig.InteractionDistance) or 3.0
    local closest, closestDistance
    for _, candidateValue in ipairs(GetPlayers()) do
        local candidate = validSource(candidateValue)
        local handsMatch = candidate and (
            handsUpWanted == nil or Player(candidate).state['ob:handsUp'] == handsUpWanted
        )
        if candidate and candidate ~= playerSource and handsMatch
            and isRestrained(candidate) == restrainedWanted then
            local candidatePed = GetPlayerPed(candidate)
            if candidatePed and candidatePed > 0 then
                local distance = #(coords - GetEntityCoords(candidatePed))
                if distance <= maximum and (not closestDistance or distance < closestDistance) then
                    closest, closestDistance = candidate, distance
                end
            end
        end
    end
    return closest
end

local function exchangeItem(playerSource, removedItem, receivedItem, missingMessage)
    local count, countError = exports.ob_inventory:GetItemCount(playerSource, removedItem)
    if not count or count < 1 then return false, missingMessage or countError or 'Item necessario indisponivel.' end

    local removed, removeError = exports.ob_inventory:RemoveItem(playerSource, removedItem, 1)
    if not removed then return false, removeError or 'Nao foi possivel remover o item.' end
    local added, addError = exports.ob_inventory:AddItem(playerSource, receivedItem, 1)
    if added then return true end

    local restored, restoreError = exports.ob_inventory:AddItem(playerSource, removedItem, 1)
    if not restored then
        print(('[ob_police] CRITICO: falha ao restaurar %s para source=%s: %s'):format(
            removedItem, playerSource, tostring(restoreError)
        ))
    end
    return false, addError or 'Nao existe espaco para receber o novo item.'
end

local function persistRestrainedState(targetSource, enabled)
    local targetUserId = userId(targetSource)
    if not targetUserId then return false, 'Personagem ainda nao foi carregado.' end
    local deadline = GetGameTimer() + 5000
    while not databaseReady and GetGameTimer() < deadline do Wait(100) end
    if not databaseReady then return false, 'Tabela de algemas indisponivel.' end

    local result, errorMessage
    if enabled == true then
        result, errorMessage = OR.Database.update.await([[
            INSERT INTO ob_police_restraints (user_id, restrained)
            VALUES (?, 1)
            ON DUPLICATE KEY UPDATE restrained = 1, updated_at = CURRENT_TIMESTAMP
        ]], { targetUserId })
    else
        result, errorMessage = OR.Database.update.await(
            'DELETE FROM ob_police_restraints WHERE user_id = ?', { targetUserId }
        )
    end
    if result == nil then return false, errorMessage or 'Falha ao salvar estado da algema.' end
    return true
end

local function restoreRestrainedState(playerSource)
    playerSource = validSource(playerSource)
    if not playerSource then return end
    local expectedUserId = userId(playerSource)
    if not expectedUserId then return end

    local deadline = GetGameTimer() + 30000
    while not databaseReady and GetGameTimer() < deadline do Wait(100) end
    if not databaseReady then
        print(('[ob_police] Nao foi possivel restaurar algema do user_id=%s: banco indisponivel.'):format(expectedUserId))
        return
    end

    local stored, errorMessage = OR.Database.scalar.await(
        'SELECT restrained FROM ob_police_restraints WHERE user_id = ? LIMIT 1', { expectedUserId }
    )
    playerSource = validSource(playerSource)
    if not playerSource or userId(playerSource) ~= expectedUserId then return end
    if stored == nil and errorMessage then
        print(('[ob_police] Falha ao restaurar algema do user_id=%s: %s'):format(
            expectedUserId, tostring(errorMessage)
        ))
        return
    end

    local enabled = tonumber(stored) == 1 or stored == true
    restrainedPlayers[playerSource] = enabled and true or nil
    Player(playerSource).state:set('ob:restrained', enabled, true)
    Player(playerSource).state:set('ob:escortedBy', nil, true)
    TriggerClientEvent('ob_police:client:restoreRestrained', playerSource, enabled)
end

local function setRestrained(targetSource, enabled, actorSource, action)
    targetSource = validSource(targetSource)
    if not targetSource then return false end
    if enabled ~= true then stopEscort(targetSource) end
    restrainedPlayers[targetSource] = enabled == true and true or nil
    Player(targetSource).state:set('ob:restrained', enabled == true, true)
    TriggerClientEvent('ob_police:client:cuffFeedback', targetSource, enabled == true)
    local persisted, persistenceError = persistRestrainedState(targetSource, enabled == true)
    if not persisted then
        print(('[ob_police] Falha ao persistir algema do user_id=%s: %s'):format(
            userId(targetSource) or 'n/a', tostring(persistenceError)
        ))
    end
    audit(action or (enabled and 'CUFF' or 'UNCUFF'), actorSource, targetSource)
    return true
end

local function performRestraintItem(actorSource, targetSource, itemName)
    actorSource, targetSource = validSource(actorSource), validSource(targetSource)
    if not actorSource or not targetSource or not actorCanUseItems(actorSource) then
        return false, 'Voce nao pode usar esse item nesse estado.'
    end
    if not playersAreClose(actorSource, targetSource, OBPoliceConfig.InteractionDistance) then
        return false, 'Aproxime-se da pessoa.'
    end
    if Player(targetSource).state['ob:takedown'] == true then
        return false, 'Aguarde a derrubada terminar.'
    end

    local items = restraintItems()
    if itemName == (items.Handcuffs or 'handcuffs') then
        if isRestrained(targetSource) then return false, 'Essa pessoa ja esta algemada.' end
        if not isPolice(actorSource) and Player(targetSource).state['ob:handsUp'] ~= true then
            return false, 'Civis so podem algemar uma pessoa com as maos levantadas.'
        end
        local exchanged, exchangeError = exchangeItem(
            actorSource, itemName, items.Key or 'handcuff_key', 'Voce nao possui uma algema.'
        )
        if not exchanged then return false, exchangeError end
        setRestrained(targetSource, true, actorSource, 'CUFF_ITEM')
        return true, 'Pessoa algemada. A chave foi colocada na sua mochila.'
    end

    if itemName == (items.Key or 'handcuff_key') then
        if not isRestrained(targetSource) then return false, 'Essa pessoa nao esta algemada.' end
        local exchanged, exchangeError = exchangeItem(
            actorSource, itemName, items.Handcuffs or 'handcuffs', 'Voce nao possui uma chave de algema.'
        )
        if not exchanged then return false, exchangeError end
        setRestrained(targetSource, false, actorSource, 'UNCUFF_KEY')
        return true, 'Pessoa desalgemada. A algema voltou para sua mochila.'
    end

    return false, 'Item de algema invalido.'
end

local itemUseSequence = 0
local function beginItemUse(playerSource, itemName, slot)
    playerSource = validSource(playerSource)
    itemName = type(itemName) == 'string' and itemName:lower() or ''
    local items = restraintItems()
    local handcuffs = items.Handcuffs or 'handcuffs'
    local key = items.Key or 'handcuff_key'
    local lockpick = isLockpickItem(itemName)
    local handled = itemName == handcuffs or itemName == key or lockpick
    if not handled then return false, 'Item nao pertence ao sistema de algemas.', false end
    if not actorCanUseItems(playerSource) then return false, 'Voce nao pode usar esse item nesse estado.', true end
    local now = GetGameTimer()
    if itemAttempts[playerSource] and itemAttempts[playerSource].expiresAt <= now then itemAttempts[playerSource] = nil end
    if itemAttempts[playerSource] then return false, 'Voce ja esta usando um item de algema.', true end

    local civilianHandcuff = itemName == handcuffs and not isPolice(playerSource)
    local targetSource = closestTarget(
        playerSource,
        itemName ~= handcuffs,
        civilianHandcuff and true or nil
    )
    if not targetSource then
        if lockpick then return false, nil, false end
        return false, itemName == handcuffs
            and (civilianHandcuff
                and 'Nenhuma pessoa com as maos levantadas esta proxima.'
                or 'Nenhuma pessoa proxima para algemar.')
            or 'Nenhuma pessoa algemada proxima.', true
    end

    itemUseSequence = itemUseSequence + 1
    itemAttempts[playerSource] = {
        itemName = itemName,
        slot = slot,
        token = ('%s:%s'):format(now, itemUseSequence),
        targetSource = targetSource,
        startedAt = now,
        expiresAt = now + math.max(5000, tonumber(OBPoliceConfig.Lockpick and OBPoliceConfig.Lockpick.TimeoutMs) or 25000),
    }
    if lockpick and GetResourceState('ob_dispatch') == 'started' then
        local ped = GetPlayerPed(playerSource)
        local coords = ped ~= 0 and GetEntityCoords(ped) or nil
        local ok, dispatchError = pcall(function()
            exports.ob_dispatch:CreateAlert('lockpick_restraint', {
                actorSource = playerSource,
                coords = coords,
                metadata = { origin = 'ob_police', targetSource = targetSource },
            })
        end)
        if not ok then print('[ob_police] Falha ao enviar chamado de lockpick: ' .. tostring(dispatchError)) end
    end
    TriggerClientEvent('ob_police:client:useRestraintItem', playerSource, itemName, targetSource, itemAttempts[playerSource].token)
    return true, lockpick and 'Arrombamento da algema iniciado.' or 'Uso do item iniciado.', true
end

exports('BeginItemUse', beginItemUse)

RegisterNetEvent('ob_police:server:itemUseResult', function(success, token)
    local playerSource = validSource(source)
    if not playerSource then return end
    local attempt = itemAttempts[playerSource]
    if not attempt or attempt.token ~= token then return end
    itemAttempts[playerSource] = nil
    if not attempt or attempt.expiresAt < GetGameTimer() then return end

    local targetSource = validSource(attempt.targetSource)
    if not targetSource or not actorCanUseItems(playerSource)
        or not playersAreClose(playerSource, targetSource, OBPoliceConfig.InteractionDistance) then
        return notify(playerSource, 'A pessoa se afastou antes da acao terminar.', 'error')
    end

    if not isLockpickItem(attempt.itemName) then
        if success ~= true then return notify(playerSource, 'Nao foi possivel alcancar a pessoa.', 'error') end
        local completed, actionMessage = performRestraintItem(playerSource, targetSource, attempt.itemName)
        return notify(playerSource, actionMessage, completed and 'success' or 'error')
    end

    if not isRestrained(targetSource) then return notify(playerSource, 'Essa pessoa nao esta mais algemada.', 'error') end

    local lockpickConfig = type(OBPoliceConfig.Lockpick) == 'table' and OBPoliceConfig.Lockpick or {}
    local elapsed = GetGameTimer() - attempt.startedAt
    if success == true and elapsed < math.max(1000, tonumber(lockpickConfig.MinimumSuccessMs) or 1000) then
        audit('LOCKPICK_REJECT_FAST', playerSource, targetSource, ('elapsed_ms=%s'):format(elapsed))
        return notify(playerSource, 'Resultado da lockpick recusado.', 'error')
    end

    local used, remaining = exports.ob_inventory:ConsumeLockpickUse(playerSource, attempt.itemName, attempt.slot)
    if not used then return notify(playerSource, remaining, 'error') end
    local wear = remaining > 0 and (' Restam %s usos.'):format(remaining) or ' A lockpick quebrou.'
    if success ~= true then
        local broke = remaining == 0
        audit('LOCKPICK_FAIL', playerSource, targetSource, broke and 'broke=true' or 'broke=false')
        notify(targetSource, 'Alguem tentou arrombar sua algema.', 'warning')
        return notify(playerSource, 'Voce falhou ao arrombar a algema.' .. wear, 'error')
    end

    setRestrained(targetSource, false, playerSource, 'UNCUFF_LOCKPICK')
    notify(targetSource, 'Sua algema foi arrombada.', 'warning')
    notify(playerSource, 'Algema arrombada.' .. wear, 'success')
end)

RegisterNetEvent('ob_police:server:toggleEscort', function()
    local officerSource = validSource(source)
    if not officerSource then return end
    if not OR.Security.rateLimit(officerSource, 'police:escort', 6, 10000) then return end
    -- H e uma tecla comum. Civis sao ignorados silenciosamente; membros da
    -- Policia fora de servico recebem a explicacao. A autorizacao e do servidor.
    if not isPolice(officerSource) then
        if isPoliceMember(officerSource) then
            notify(officerSource, 'Voce precisa estar em servico na Policia.', 'error')
        end
        return
    end

    for currentTarget, currentOfficer in pairs(escorts) do
        if tonumber(currentOfficer) == officerSource then
            stopEscort(currentTarget)
            notify(officerSource, 'Escolta encerrada.', 'success')
            return audit('ESCORT_STOP', officerSource, currentTarget)
        end
    end

    local targetSource = closestTarget(officerSource, true)
    if not targetSource then return notify(officerSource, 'Nenhuma pessoa algemada proxima.', 'error') end

    if escorts[targetSource] then return notify(officerSource, 'Essa pessoa ja esta sendo escoltada.', 'error') end

    escorts[targetSource] = officerSource
    Player(targetSource).state:set('ob:escortedBy', officerSource, true)
    TriggerClientEvent('ob_police:client:escortChanged', targetSource, officerSource)
    TriggerClientEvent('ob_police:client:escortState', officerSource, targetSource)
    notify(officerSource, 'Escolta iniciada.', 'success')
    audit('ESCORT_START', officerSource, targetSource)
end)

local function playerInTakedown(playerSource)
    if activeTakedowns[playerSource] then return true end
    for _, officerSource in pairs(activeTakedowns) do
        if officerSource == playerSource then return true end
    end
    return false
end

RegisterNetEvent('ob_police:server:requestTakedown', function(targetSource)
    local officerSource = validSource(source)
    targetSource = validSource(targetSource)
    if not officerSource or not targetSource or officerSource == targetSource then return end
    if not OR.Security.rateLimit(officerSource, 'police:takedown', 3, 10000) then
        return notify(officerSource, 'Aguarde antes de tentar outra derrubada.', 'error')
    end
    if not isPolice(officerSource) then
        return notify(officerSource, 'Voce precisa estar em servico na Policia.', 'error')
    end

    local now = GetGameTimer()
    if (takedownCooldowns[officerSource] or 0) > now then
        return notify(officerSource, 'Aguarde o tempo da derrubada.', 'error')
    end
    if playerInTakedown(officerSource) or playerInTakedown(targetSource) then
        return notify(officerSource, 'Um dos jogadores ja esta em outra derrubada.', 'error')
    end

    local officerState, targetState = Player(officerSource).state, Player(targetSource).state
    if officerState['or:downed'] == true or officerState['ob:restrained'] == true
        or targetState['or:downed'] == true or isRestrained(targetSource) then
        return notify(officerSource, 'Nao e possivel derrubar essa pessoa nesse estado.', 'error')
    end

    local config = OBPoliceConfig.Takedown or {}
    local maximum = tonumber(config.Distance) or 1.10
    if not playersAreClose(officerSource, targetSource, maximum) then
        return notify(officerSource, 'Aproxime-se da pessoa para derruba-la.', 'error')
    end
    local officerPed, targetPed = GetPlayerPed(officerSource), GetPlayerPed(targetSource)
    if officerPed <= 0 or targetPed <= 0
        or GetVehiclePedIsIn(officerPed, false) ~= 0
        or GetVehiclePedIsIn(targetPed, false) ~= 0 then
        return notify(officerSource, 'A derrubada nao pode ser feita dentro de veiculos.', 'error')
    end

    local officerCoords = GetEntityCoords(officerPed)
    local targetCoords = GetEntityCoords(targetPed)
    local offsetX = targetCoords.x - officerCoords.x
    local offsetY = targetCoords.y - officerCoords.y
    local horizontalDistance = math.sqrt(offsetX * offsetX + offsetY * offsetY)
    local forward = entityForwardFromHeading(officerPed)
    local directionDot = forward and horizontalDistance > 0.05 and (
        forward.x * offsetX + forward.y * offsetY
    ) / horizontalDistance or -1.0
    if directionDot < (tonumber(config.MinimumForwardDot) or 0.80) then
        return notify(officerSource, 'A pessoa precisa estar bem a sua frente.', 'error')
    end
    if config.RequireSprint ~= false
        and GetEntitySpeed(officerPed) < (tonumber(config.MinimumSpeed) or 2.5) then
        return notify(officerSource, 'Voce precisa estar correndo para derrubar.', 'error')
    end

    local cooldown = math.max(1500, tonumber(config.CooldownMs) or 10000)
    local animationDuration = math.max(1200, tonumber(config.AnimationDurationMs) or 3000)
    local ragdollDuration = math.max(1000, tonumber(config.RagdollMs) or 3500)
    takedownCooldowns[officerSource] = now + cooldown
    activeTakedowns[targetSource] = officerSource
    Player(officerSource).state:set('ob:takedown', true, true)
    Player(targetSource).state:set('ob:takedown', true, true)
    TriggerClientEvent('ob_police:client:takedownAttacker', officerSource, targetSource)
    TriggerClientEvent('ob_police:client:takedownVictim', targetSource, officerSource)
    audit('TAKEDOWN', officerSource, targetSource)

    SetTimeout(animationDuration + ragdollDuration + 750, function()
        if activeTakedowns[targetSource] ~= officerSource then return end
        activeTakedowns[targetSource] = nil
        local currentOfficer = validSource(officerSource)
        local currentTarget = validSource(targetSource)
        if currentOfficer then Player(currentOfficer).state:set('ob:takedown', false, true) end
        if currentTarget then Player(currentTarget).state:set('ob:takedown', false, true) end
    end)
end)

RegisterNetEvent('ob_police:server:requestSearchConsent', function(targetSource)
    local requesterSource = validSource(source)
    targetSource = validSource(targetSource)
    if not requesterSource or not targetSource or requesterSource == targetSource then return end
    if not OR.Security.rateLimit(requesterSource, 'police:search_request', 3, 15000) then
        return notify(requesterSource, 'Aguarde antes de enviar outro pedido.', 'error')
    end
    if isPolice(requesterSource) then
        return notify(requesterSource, 'A revista consentida e destinada a civis. Em servico, use a revista policial.', 'error')
    end
    if not actorCanUseItems(requesterSource) then
        return notify(requesterSource, 'Voce nao pode pedir uma revista nesse estado.', 'error')
    end
    local targetState = Player(targetSource).state
    if targetState['or:downed'] == true or targetState['ob:takedown'] == true
        or isRestrained(targetSource)
        or targetState['ob:handsUp'] ~= true then
        return notify(requesterSource, 'A pessoa precisa estar com as maos levantadas.', 'error')
    end
    if not playersAreClose(requesterSource, targetSource, OBPoliceConfig.InteractionDistance) then
        return notify(requesterSource, 'Aproxime-se da pessoa.', 'error')
    end

    local timeout = math.max(5, tonumber(consentConfig().RequestTimeoutSeconds) or 15)
    local current = searchRequests[targetSource]
    if current and current.expiresAt > GetGameTimer() then
        return notify(requesterSource, 'Essa pessoa ja possui um pedido de revista pendente.', 'error')
    end
    searchRequests[targetSource] = {
        requesterSource = requesterSource,
        expiresAt = GetGameTimer() + (timeout * 1000),
    }
    TriggerClientEvent(
        'ob_police:client:searchConsentRequest', targetSource,
        requesterSource, characterName(requesterSource), timeout
    )
    notify(requesterSource, 'Pedido enviado. Aguarde a resposta.', 'info')
end)

RegisterNetEvent('ob_police:server:answerSearchConsent', function(requesterSource, accepted)
    local targetSource = validSource(source)
    requesterSource = validSource(requesterSource)
    if not targetSource or not requesterSource then return end
    if not OR.Security.rateLimit(targetSource, 'police:search_answer', 4, 10000) then return end

    local request = searchRequests[targetSource]
    searchRequests[targetSource] = nil
    if not request or request.requesterSource ~= requesterSource
        or request.expiresAt < GetGameTimer() then
        return notify(targetSource, 'Esse pedido de revista nao esta mais valido.', 'error')
    end
    if not playersAreClose(requesterSource, targetSource, OBPoliceConfig.InteractionDistance) then
        notify(requesterSource, 'A pessoa se afastou antes de responder.', 'error')
        return notify(targetSource, 'O pedido foi cancelado porque voces se afastaram.', 'error')
    end
    if isPolice(requesterSource) or not actorCanUseItems(requesterSource)
        or isRestrained(targetSource) or Player(targetSource).state['or:downed'] == true
        or Player(targetSource).state['ob:handsUp'] ~= true then
        notify(requesterSource, 'O pedido foi cancelado porque o estado de um dos jogadores mudou.', 'error')
        return notify(targetSource, 'O pedido de revista foi cancelado.', 'error')
    end
    if accepted ~= true then
        notify(requesterSource, ('%s recusou mostrar a mochila.'):format(characterName(targetSource)), 'error')
        return notify(targetSource, 'Pedido recusado.', 'info')
    end

    local viewSeconds = math.max(15, tonumber(consentConfig().ViewTimeoutSeconds) or 120)
    searchAuthorizations[requesterSource] = {
        targetSource = targetSource,
        expiresAt = GetGameTimer() + (viewSeconds * 1000),
    }
    notify(targetSource, 'Voce permitiu apenas a visualizacao da sua mochila.', 'success')
    notify(requesterSource, 'Pedido aceito. A mochila sera aberta somente para leitura.', 'success')
    TriggerClientEvent('ob_police:client:openConsentInventory', requesterSource, targetSource)
    audit('CONSENT_SEARCH_ACCEPT', requesterSource, targetSource)
end)

local function canSearch(officerSource, targetSource)
    officerSource, targetSource = validSource(officerSource), validSource(targetSource)
    if not officerSource or not targetSource then return false, 'Jogador indisponivel.' end
    if not isPolice(officerSource) then return false, 'Voce precisa estar em servico na Policia.' end
    if not isRestrained(targetSource) then return false, 'A pessoa precisa estar algemada para ser revistada.' end
    if not playersAreClose(officerSource, targetSource, OBPoliceConfig.InteractionDistance) then
        return false, 'Aproxime-se da pessoa.'
    end
    return true
end

local function searchPayload(targetSource)
    local inventory, inventoryError = exports.ob_inventory:GetInventory(targetSource)
    if not inventory then return nil, inventoryError or 'Inventario indisponivel.' end
    return {
        target = {
            source = targetSource,
            userId = userId(targetSource),
            name = exports.ob_core:GetFullName(targetSource) or GetPlayerName(targetSource) or 'Desconhecido',
        },
        inventory = inventory,
    }
end

OR.Callback.register('search', function(officerSource, targetSource)
    local allowed, permissionError = canSearch(officerSource, targetSource)
    if not allowed then return nil, permissionError end
    audit('SEARCH', officerSource, targetSource)
    return searchPayload(tonumber(targetSource))
end)

OR.Callback.register('consentSearch', function(requesterSource, targetSource)
    requesterSource, targetSource = validSource(requesterSource), validSource(targetSource)
    if not requesterSource or not targetSource then return nil, 'Jogador indisponivel.' end
    local authorization = searchAuthorizations[requesterSource]
    if not authorization or authorization.targetSource ~= targetSource
        or authorization.expiresAt < GetGameTimer() then
        return nil, 'A permissao para visualizar essa mochila expirou.'
    end
    if isPolice(requesterSource) or not actorCanUseItems(requesterSource) or isRestrained(targetSource)
        or Player(targetSource).state['or:downed'] == true
        or Player(targetSource).state['ob:handsUp'] ~= true then
        return nil, 'A revista consentida nao esta disponivel nesse estado.'
    end
    if not playersAreClose(requesterSource, targetSource, OBPoliceConfig.InteractionDistance) then
        return nil, 'Aproxime-se da pessoa.'
    end
    audit('CONSENT_SEARCH_VIEW', requesterSource, targetSource)
    return searchPayload(targetSource)
end)

OR.Callback.register('seize', function(officerSource, targetSource, slot, amount, targetSlot)
    if not OR.Security.rateLimit(officerSource, 'police:seize', 20, 10000) then
        return nil, 'Muitas apreensoes em pouco tempo.'
    end
    local allowed, permissionError = canSearch(officerSource, targetSource)
    if not allowed then return nil, permissionError end
    targetSource = tonumber(targetSource)
    slot = math.floor(tonumber(slot) or 0)
    amount = math.floor(tonumber(amount) or 0)
    targetSlot = math.floor(tonumber(targetSlot) or 0)
    if slot < 1 or amount < 1 or targetSlot < 1 then return nil, 'Item, quantidade ou slot invalido.' end

    local before, beforeError = exports.ob_inventory:GetInventory(targetSource)
    local item = before and before.items and (before.items[tostring(slot)] or before.items[slot]) or nil
    if not item or amount > (tonumber(item.amount) or 0) then return nil, beforeError or 'Item indisponivel.' end

    local transferred, response, transferMessage = exports.ob_inventory:TransferItemBySlot(
        targetSource, officerSource, slot, amount, true, targetSlot
    )
    if not transferred then return nil, response or transferMessage or 'Nao foi possivel apreender o item.' end

    audit('SEIZE', officerSource, targetSource, ('%sx %s slot=%s'):format(amount, item.name, slot))
    notify(targetSource, ('A Policia apreendeu %sx %s.'):format(amount, item.label or item.name), 'warning')
    local payload, payloadError = searchPayload(targetSource)
    if not payload then return nil, payloadError end
    payload.officerInventory = exports.ob_inventory:GetInventory(officerSource)
    return payload, ('%sx %s apreendido.'):format(amount, item.label or item.name)
end)

AddEventHandler('ob_core:server:playerLoaded', function(playerSource)
    playerSource = validSource(playerSource)
    if not playerSource then return end
    escorts[playerSource] = nil
    restrainedPlayers[playerSource] = nil
    Player(playerSource).state:set('ob:restrained', false, true)
    Player(playerSource).state:set('ob:escortedBy', nil, true)
    Player(playerSource).state:set('ob:takedown', false, true)
    CreateThread(function() restoreRestrainedState(playerSource) end)
end)

AddEventHandler('playerDropped', function()
    local playerSource = tonumber(source)
    itemAttempts[playerSource] = nil
    takedownCooldowns[playerSource] = nil
    if activeTakedowns[playerSource] then
        local officerSource = validSource(activeTakedowns[playerSource])
        activeTakedowns[playerSource] = nil
        if officerSource then Player(officerSource).state:set('ob:takedown', false, true) end
    end
    for targetSource, officerSource in pairs(activeTakedowns) do
        if officerSource == playerSource then
            activeTakedowns[targetSource] = nil
            local target = validSource(targetSource)
            if target then Player(target).state:set('ob:takedown', false, true) end
        end
    end
    searchRequests[playerSource] = nil
    searchAuthorizations[playerSource] = nil
    for targetSource, request in pairs(searchRequests) do
        if request.requesterSource == playerSource then searchRequests[targetSource] = nil end
    end
    for requesterSource, authorization in pairs(searchAuthorizations) do
        if authorization.targetSource == playerSource then searchAuthorizations[requesterSource] = nil end
    end
    restrainedPlayers[playerSource] = nil
    stopEscort(playerSource)
    stopEscortsByOfficer(playerSource)
end)

CreateThread(function()
    while true do
        Wait(1000)
        for targetSource, officerSource in pairs(escorts) do
            local target = validSource(targetSource)
            local officer = validSource(officerSource)
            local maximum = tonumber(OBPoliceConfig.EscortBreakDistance) or 12.0
            if not target or not officer or not isRestrained(target) or not isPolice(officer)
                or not playersAreClose(officer, target, maximum) then
                stopEscort(targetSource)
            end
        end
        local now = GetGameTimer()
        for targetSource, request in pairs(searchRequests) do
            if request.expiresAt <= now then searchRequests[targetSource] = nil end
        end
        for requesterSource, authorization in pairs(searchAuthorizations) do
            if authorization.expiresAt <= now then searchAuthorizations[requesterSource] = nil end
        end
    end
end)

CreateThread(function()
    if not OR.Database.waitForReady(30000) then
        return print('[ob_police] Banco indisponivel; algemas persistentes nao foram iniciadas.')
    end
    local created, errorMessage = OR.Database.query.await([[
        CREATE TABLE IF NOT EXISTS ob_police_restraints (
            user_id BIGINT UNSIGNED NOT NULL,
            restrained TINYINT(1) NOT NULL DEFAULT 1,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (user_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    if created == nil then
        return print(('[ob_police] Falha ao criar tabela de algemas: %s'):format(tostring(errorMessage)))
    end
    databaseReady = true

    for _, playerValue in ipairs(GetPlayers()) do
        local playerSource = validSource(playerValue)
        if playerSource then
            local capturedSource = playerSource
            restrainedPlayers[playerSource] = nil
            Player(playerSource).state:set('ob:restrained', false, true)
            Player(playerSource).state:set('ob:escortedBy', nil, true)
            Player(playerSource).state:set('ob:takedown', false, true)
            CreateThread(function() restoreRestrainedState(capturedSource) end)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, playerSource in ipairs(GetPlayers()) do
        playerSource = tonumber(playerSource)
        restrainedPlayers[playerSource] = nil
        Player(playerSource).state:set('ob:restrained', false, true)
        Player(playerSource).state:set('ob:escortedBy', nil, true)
        Player(playerSource).state:set('ob:takedown', false, true)
    end
end)
