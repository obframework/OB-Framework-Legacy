local npcSessions = {}

local function config()
    return type(ORHealthConfig.NPC) == 'table' and ORHealthConfig.NPC or {}
end

local function validSource(playerSource)
    playerSource = tonumber(playerSource)
    return playerSource and playerSource > 0 and GetPlayerName(playerSource) and playerSource or nil
end

local function notify(playerSource, message, kind)
    playerSource = validSource(playerSource)
    if playerSource then
        TriggerClientEvent('ob_notification:client:notify', playerSource, message, kind or 'inform')
    end
end

local function emsOnDuty()
    local cfg = config()
    if cfg.DisableWhenEmsOnDuty ~= true or GetResourceState('ob_org') ~= 'started' then return 0 end
    local total = 0
    for _, playerSource in ipairs(GetPlayers()) do
        playerSource = tonumber(playerSource)
        local ok, allowed = pcall(function()
            return exports.ob_health:HasEmsAccess(playerSource)
        end)
        if ok and allowed == true then total = total + 1 end
    end
    return total
end

local function npcAvailable()
    local cfg = config()
    if cfg.Enabled ~= true then return false, 'Atendimento por NPC desativado.' end
    local minimum = math.max(1, math.floor(tonumber(cfg.MinimumEmsOnDuty) or 1))
    if cfg.DisableWhenEmsOnDuty == true and emsOnDuty() >= minimum then
        return false, 'Ha profissionais do EMS em servico. Solicite atendimento aos jogadores.'
    end
    return true
end

local function closeToPoint(playerSource, point, maximum)
    local ped = GetPlayerPed(playerSource)
    if ped <= 0 or type(point) ~= 'table' then return false end
    local position = GetEntityCoords(ped)
    local dx, dy, dz = position.x - point.x, position.y - point.y, position.z - point.z
    maximum = tonumber(maximum) or 4.0
    return (dx * dx) + (dy * dy) + (dz * dz) <= maximum * maximum
end

local function chargeAndRecover(playerSource, service, price, revive)
    local paid, paymentError = exports.ob_health:ChargePatient(playerSource, playerSource, service, price)
    if paid ~= true then return false, paymentError or 'Pagamento recusado.' end
    exports.ob_health:ClearInjuries(playerSource)
    local ok, medicalError
    if revive then
        ok, medicalError = exports.ob_health:RevivePlayer(playerSource, 0, ORHealthConfig.ReviveHealth, false)
    else
        ok, medicalError = exports.ob_health:HealPlayer(playerSource, ORHealthConfig.MaxHealth)
    end
    if not ok then return false, medicalError or 'Nao foi possivel concluir o atendimento.' end
    return true
end

OR.Callback.register('npcClinicBegin', function(source)
    local playerSource = validSource(source)
    local clinic = type(config().Clinic) == 'table' and config().Clinic or {}
    if not playerSource or clinic.Enabled ~= true then return false, 'Atendimento automatico indisponivel.' end
    if Player(playerSource).state['or:downed'] == true then return false, 'Pacientes incapacitados devem solicitar socorro.' end
    local available, availabilityError = npcAvailable()
    if not available then return false, availabilityError end
    if not closeToPoint(playerSource, clinic.Ped, 5.0) then return false, 'Aproxime-se do atendente.' end
    if npcSessions[playerSource] then return false, 'Voce ja possui um atendimento em andamento.' end
    local duration = math.max(3000, math.floor(tonumber(clinic.Duration) or 15000))
    local token = ('clinic:%s:%s:%s'):format(playerSource, os.time(), math.random(100000, 999999))
    npcSessions[playerSource] = {
        kind = 'clinic', token = token,
        readyAt = GetGameTimer() + duration - 500,
        expiresAt = GetGameTimer() + duration + 15000,
    }
    return true, { token = token, duration = duration, bed = clinic.Bed, exit = clinic.Exit }
end)

OR.Callback.register('npcClinicCancel', function(source, token)
    local session = npcSessions[tonumber(source)]
    if session and session.kind == 'clinic' and session.token == token then npcSessions[tonumber(source)] = nil end
    return true
end)

OR.Callback.register('npcClinicFinish', function(source, token)
    local playerSource = validSource(source)
    local session = playerSource and npcSessions[playerSource]
    if not session or session.kind ~= 'clinic' or session.token ~= token
        or GetGameTimer() < session.readyAt or GetGameTimer() > session.expiresAt then
        return false, 'Atendimento automatico invalido ou interrompido.'
    end
    npcSessions[playerSource] = nil
    local clinic = type(config().Clinic) == 'table' and config().Clinic or {}
    local price = math.max(0, math.floor(tonumber(clinic.Price) or 0))
    local ok, medicalError = chargeAndRecover(playerSource, 'atendimento automatico', price, false)
    if not ok then return false, medicalError end
    return true, ('Tratamento concluido. Valor: %s.'):format(OR.FormatMoney(price))
end)

local function requestMobileNpc(playerSource)
    playerSource = validSource(playerSource)
    local mobile = type(config().Mobile) == 'table' and config().Mobile or {}
    if not playerSource or mobile.Enabled ~= true then return false, 'Socorro automatico indisponivel.' end
    if not OR.Security.rateLimit(playerSource, 'health:npc_rescue', 2, 15000) then
        return false, 'Aguarde antes de solicitar novamente.'
    end
    local available, availabilityError = npcAvailable()
    if not available then return false, availabilityError end
    if npcSessions[playerSource] then return false, 'Um atendimento ja esta a caminho ou em andamento.' end

    local death = exports.ob_health:GetDownedInfo(playerSource)
    if type(death) ~= 'table' then return false, 'Voce nao esta incapacitado.' end
    local waited = os.time() - (tonumber(death.startedAt) or os.time())
    local requiredWait = math.max(0, math.floor(tonumber(mobile.WaitAfterDeathSeconds) or 60))
    if waited < requiredWait then
        return false, ('Aguarde mais %d segundo(s) antes de chamar o socorro automatico.'):format(requiredWait - waited)
    end
    local deathInfo = type(death.death) == 'table' and death.death or {}
    local category = tostring(deathInfo.category or 'accident'):lower()
    local allowed = type(mobile.AllowedDeathCategories) == 'table' and mobile.AllowedDeathCategories or {}
    if mobile.BlockPlayerFirearmDeaths == true and deathInfo.playerCaused == true and category == 'firearm' then
        return false, 'O socorro automatico nao atende mortes por disparo de outro jogador.'
    end
    if allowed[category] ~= true then
        return false, 'A causa dessa incapacitacao exige atendimento de um EMS jogador.'
    end

    local token = ('mobile:%s:%s:%s'):format(playerSource, os.time(), math.random(100000, 999999))
    npcSessions[playerSource] = {
        kind = 'mobile', token = token, status = 'dispatched',
        expiresAt = GetGameTimer() + math.max(90000, (tonumber(mobile.DriveTimeoutMs) or 35000) + 60000),
    }
    TriggerClientEvent('ob_health:client:startMobileNpc', playerSource, token, mobile)
    return true, 'Uma ambulancia foi acionada e esta a caminho.'
end

local mobileCommand = tostring((type(config().Mobile) == 'table' and config().Mobile.Command) or 'socorro')
RegisterCommand(mobileCommand, function(source)
    local playerSource = validSource(source)
    if not playerSource then return end
    local ok, message = requestMobileNpc(playerSource)
    notify(playerSource, message, ok and 'success' or 'error')
end, false)

RegisterNetEvent('ob_health:server:requestNpcRescue', function()
    local playerSource = validSource(source)
    if not playerSource then return end
    local ok, message = requestMobileNpc(playerSource)
    notify(playerSource, message, ok and 'success' or 'error')
end)

OR.Callback.register('npcMobileArrived', function(source, token)
    local playerSource = validSource(source)
    local session = playerSource and npcSessions[playerSource]
    if not session or session.kind ~= 'mobile' or session.token ~= token or session.status ~= 'dispatched' then
        return false, 'Chamado automatico invalido.'
    end
    if not exports.ob_health:GetDownedInfo(playerSource) then
        npcSessions[playerSource] = nil
        return false, 'O paciente nao esta mais incapacitado.'
    end
    local duration = math.max(3000, math.floor(tonumber(config().Mobile.TreatmentDuration) or 15000))
    session.status = 'treating'
    session.readyAt = GetGameTimer() + duration - 500
    session.expiresAt = GetGameTimer() + duration + 20000
    return true, duration
end)

OR.Callback.register('npcMobileCancel', function(source, token)
    local session = npcSessions[tonumber(source)]
    if session and session.kind == 'mobile' and session.token == token then npcSessions[tonumber(source)] = nil end
    return true
end)

OR.Callback.register('npcMobileFinish', function(source, token)
    local playerSource = validSource(source)
    local session = playerSource and npcSessions[playerSource]
    if not session or session.kind ~= 'mobile' or session.token ~= token or session.status ~= 'treating'
        or GetGameTimer() < session.readyAt or GetGameTimer() > session.expiresAt then
        return false, 'Atendimento automatico invalido ou interrompido.'
    end
    if not exports.ob_health:GetDownedInfo(playerSource) then
        npcSessions[playerSource] = nil
        return false, 'O paciente ja foi reanimado.'
    end
    npcSessions[playerSource] = nil
    local price = math.max(0, math.floor(tonumber(config().Mobile.Price) or 0))
    local ok, medicalError = chargeAndRecover(playerSource, 'socorro automatico', price, true)
    if not ok then return false, medicalError end
    return true, ('Socorro concluido. Valor: %s.'):format(OR.FormatMoney(price))
end)

AddEventHandler('playerDropped', function()
    npcSessions[tonumber(source)] = nil
end)

CreateThread(function()
    while true do
        Wait(10000)
        local now = GetGameTimer()
        for playerSource, session in pairs(npcSessions) do
            if not validSource(playerSource) or now > (tonumber(session.expiresAt) or 0) then
                npcSessions[playerSource] = nil
            end
        end
    end
end)
