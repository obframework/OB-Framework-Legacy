local injuryCache = {}
local dirtyInjuries = {}
local pendingInjuryTreatments = {}
local injuriesReady = false

local function settings()
    return type(ORHealthConfig.Injuries) == 'table' and ORHealthConfig.Injuries or {}
end

local function validSource(playerSource)
    playerSource = tonumber(playerSource)
    return playerSource and playerSource > 0 and GetPlayerName(playerSource) and playerSource or nil
end

local function userId(playerSource)
    playerSource = validSource(playerSource)
    if not playerSource then return nil end
    return tonumber(exports.ob_core:GetUserId(playerSource))
end

local function bodyPart(region)
    local parts = type(settings().BodyParts) == 'table' and settings().BodyParts or {}
    return type(region) == 'string' and parts[region] or nil
end

local function causeSettings(cause)
    local causes = type(settings().Causes) == 'table' and settings().Causes or {}
    return causes[cause] or causes.generic or { label = 'Ferimento', item = 'bandage', baseSeverity = 10 }
end

local function normalize(raw)
    local result = {}
    if type(raw) ~= 'table' then return result end
    local maximum = math.max(10, math.floor(tonumber(settings().MaximumSeverity) or 100))
    for region, injury in pairs(raw) do
        local part = bodyPart(region)
        if part and type(injury) == 'table' then
            local cause = type(injury.cause) == 'string' and injury.cause:lower() or 'generic'
            local causeData = causeSettings(cause)
            result[region] = {
                region = region,
                label = tostring(part.label or region):sub(1, 48),
                side = tostring(part.side or 'center'):sub(1, 12),
                cause = cause,
                causeLabel = tostring(causeData.label or cause):sub(1, 64),
                severity = math.max(1, math.min(maximum, math.floor(tonumber(injury.severity) or 1))),
                bone = math.floor(tonumber(injury.bone) or 0),
            }
        end
    end
    return result
end

local function publish(playerSource, injuries, persist)
    playerSource = validSource(playerSource)
    if not playerSource then return false end
    injuries = normalize(injuries)
    injuryCache[playerSource] = injuries
    Player(playerSource).state:set('ob:injuries', injuries, true)
    if persist ~= false then
        local id = userId(playerSource)
        if id then dirtyInjuries[id] = injuries end
    end
    return true
end

local function loadPlayer(playerSource)
    playerSource = validSource(playerSource)
    local id = playerSource and userId(playerSource)
    if not playerSource or not id or not injuriesReady then return end
    local raw = OR.Database.scalar.await('SELECT injuries FROM ob_health_injuries WHERE user_id=?', { id })
    local ok, decoded = type(raw) == 'string' and pcall(json.decode, raw)
    publish(playerSource, ok and decoded or {}, false)
end

local function clearInjuries(playerSource, region)
    playerSource = validSource(playerSource)
    if not playerSource then return false end
    local injuries = normalize(injuryCache[playerSource] or Player(playerSource).state['ob:injuries'])
    if type(region) == 'string' and region ~= '' then injuries[region] = nil else injuries = {} end
    return publish(playerSource, injuries, true)
end

local function injurySeverity(playerSource, region)
    local injuries = injuryCache[tonumber(playerSource)] or {}
    return injuries[region] and tonumber(injuries[region].severity) or 0
end

RegisterNetEvent('ob_health:server:reportInjury', function(region, cause, severity, bone)
    local playerSource = validSource(source)
    if not playerSource or settings().Enabled ~= true then return end
    if not OR.Security.rateLimit(playerSource, 'health:injury_report', 12, 10000) then return end
    region = type(region) == 'string' and region:lower() or ''
    cause = type(cause) == 'string' and cause:lower() or 'generic'
    if not bodyPart(region) then return end
    local causeData = causeSettings(cause)
    local increment = math.max(1, math.min(50, math.floor(tonumber(severity) or causeData.baseSeverity or 10)))
    local injuries = normalize(injuryCache[playerSource] or Player(playerSource).state['ob:injuries'])
    local previous = injuries[region]
    injuries[region] = {
        region = region,
        label = bodyPart(region).label,
        side = bodyPart(region).side,
        cause = cause,
        causeLabel = causeData.label,
        severity = math.min(tonumber(settings().MaximumSeverity) or 100, (previous and previous.severity or 0) + increment),
        bone = math.floor(tonumber(bone) or 0),
    }
    publish(playerSource, injuries, true)
end)

OR.Callback.register('emsBeginInjuryTreatment', function(source, targetSource, region)
    local target, validationError = exports.ob_health:ValidateEmsPatient(source, targetSource)
    if not target then return false, validationError end
    -- Lesoes podem ser tratadas antes da CPR. Isso nao reanima o paciente.
    region = type(region) == 'string' and region:lower() or ''
    local injury = (injuryCache[target] or {})[region]
    if not injury then return false, 'Essa lesao nao esta mais presente.' end
    local cause = causeSettings(injury.cause)
    if GetResourceState('ob_inventory') ~= 'started'
        or (tonumber(exports.ob_inventory:GetItemCount(source, cause.item)) or 0) < 1 then
        return false, ('Voce precisa de %s para tratar essa lesao.'):format(tostring(cause.item))
    end
    local duration = math.max(1500, math.floor((tonumber(settings().TreatmentBaseDuration) or 3000)
        + injury.severity * (tonumber(settings().TreatmentPerSeverityMs) or 80)))
    pendingInjuryTreatments[source] = {
        target = target, region = region, item = cause.item,
        readyAt = GetGameTimer() + duration - 400,
        expiresAt = GetGameTimer() + duration + 10000,
    }
    return true, duration, injury
end)

OR.Callback.register('emsCancelInjuryTreatment', function(source)
    pendingInjuryTreatments[source] = nil
    return true
end)

OR.Callback.register('emsFinishInjuryTreatment', function(source, targetSource, region)
    local attempt = pendingInjuryTreatments[source]
    pendingInjuryTreatments[source] = nil
    if not attempt or attempt.target ~= tonumber(targetSource) or attempt.region ~= tostring(region or '')
        or GetGameTimer() < attempt.readyAt or GetGameTimer() > attempt.expiresAt then
        return false, 'Tratamento de lesao invalido ou interrompido.'
    end
    local target, validationError = exports.ob_health:ValidateEmsPatient(source, targetSource)
    if not target then return false, validationError end
    if not (injuryCache[target] or {})[attempt.region] then return false, 'Essa lesao ja foi tratada.' end
    local removed, removeError = exports.ob_inventory:RemoveItem(source, attempt.item, 1)
    if removed ~= true then return false, removeError or 'O material medico nao esta mais disponivel.' end
    local price = math.max(0, math.floor(tonumber(settings().TreatmentPrice) or 0))
    local paid, paymentError = exports.ob_health:ChargePatient(target, source, 'tratamento de lesao', price)
    if paid ~= true then
        exports.ob_inventory:AddItem(source, attempt.item, 1)
        return false, paymentError or 'Pagamento recusado.'
    end
    clearInjuries(target, attempt.region)
    if Player(target).state['or:downed'] ~= true then
        exports.ob_health:HealPlayer(target, tonumber(settings().TreatmentHeal) or 15)
    end
    return true, ('%s tratada com sucesso.'):format(tostring(bodyPart(attempt.region).label or 'Lesao'))
end)

AddEventHandler('ob_health:server:clearInjuries', function(playerSource, region)
    clearInjuries(playerSource, region)
end)

AddEventHandler('ob_core:server:playerLoaded', function(playerSource)
    CreateThread(function() Wait(500); loadPlayer(playerSource) end)
end)

AddEventHandler('ob_core:server:characterSelected', function(playerSource)
    injuryCache[tonumber(playerSource)] = nil
    CreateThread(function() Wait(500); loadPlayer(playerSource) end)
end)

AddEventHandler('playerDropped', function()
    local playerSource = tonumber(source)
    pendingInjuryTreatments[playerSource] = nil
    injuryCache[playerSource] = nil
end)

CreateThread(function()
    if not OR.Database.waitForReady(30000) then return end
    local created = OR.Database.query.await([[CREATE TABLE IF NOT EXISTS ob_health_injuries (
        user_id bigint unsigned NOT NULL,
        injuries longtext NOT NULL,
        updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
        PRIMARY KEY (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    if created == nil then return print('[ob_health] Nao foi possivel preparar a persistencia de lesoes.') end
    injuriesReady = true
    for _, playerSource in ipairs(GetPlayers()) do loadPlayer(tonumber(playerSource)) end
end)

CreateThread(function()
    while true do
        Wait(10000)
        if injuriesReady then
            local batch = dirtyInjuries
            dirtyInjuries = {}
            for id, injuries in pairs(batch) do
                local saved = OR.Database.query.await([[INSERT INTO ob_health_injuries (user_id,injuries) VALUES (?,?)
                    ON DUPLICATE KEY UPDATE injuries=VALUES(injuries),updated_at=current_timestamp()]], { id, json.encode(injuries) })
                if saved == nil then dirtyInjuries[id] = injuries end
            end
        end
        local now = GetGameTimer()
        for emsSource, attempt in pairs(pendingInjuryTreatments) do
            if not validSource(emsSource) or now > (attempt.expiresAt or 0) then pendingInjuryTreatments[emsSource] = nil end
        end
    end
end)

exports('GetInjuries', function(playerSource)
    return normalize(injuryCache[tonumber(playerSource)] or {})
end)

exports('ClearInjuries', clearInjuries)

exports('CanUseItem', function(playerSource, _, itemType)
    local threshold = tonumber(settings().HandBlockSeverity) or 60
    local right = injurySeverity(playerSource, 'right_hand')
    local left = injurySeverity(playerSource, 'left_hand')
    itemType = tostring(itemType or '')
    if right >= threshold and (itemType == 'weapon' or itemType == 'weapon_component' or itemType == 'weapon_ammo') then
        return false, 'Sua mao direita esta lesionada demais para usar armas.'
    end
    if math.max(left, right) >= threshold and (itemType:find('mechanic_', 1, true) == 1
        or itemType == 'blackout_control' or itemType == 'lockpick') then
        return false, 'Sua mao esta lesionada demais para usar esse item.'
    end
    return true
end)
