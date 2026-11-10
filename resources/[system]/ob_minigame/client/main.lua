local active
local precisionActive
local dataCrackActive
local circuitActive
local wireActive

local function hasActiveMinigame()
    return active ~= nil or precisionActive ~= nil or dataCrackActive ~= nil or circuitActive ~= nil or wireActive ~= nil
end

local function finish(success, reason)
    if not active then return end
    local pending = active
    active = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    pending:resolve(success == true, reason)
end

local function keypress(options)
    if hasActiveMinigame() then return false, 'Ja existe um minigame em andamento.' end
    options = type(options) == 'table' and options or {}
    local promiseResult = promise.new()
    active = promiseResult
    -- Libera a NUI/promessa mesmo se a pagina nao devolver a conclusao.
    SetTimeout(math.max(5000, math.min(180000, tonumber(options.timeoutMs) or 120000)), function()
        if active == promiseResult then finish(false, 'tempo_esgotado') end
    end)

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'startKeypress',
        options = {
            title = options.title or 'ACAO',
            key = options.key or 'E',
            steps = math.max(1, math.floor(tonumber(options.steps) or 3)),
            speed = math.max(0.1, tonumber(options.speed) or 1.0),
            tolerance = math.max(0.03, math.min(0.35, tonumber(options.tolerance) or 0.14)),
        }
    })

    local success, reason = Citizen.Await(promiseResult)
    return success == true, reason
end

exports('Keypress', keypress)

local function finishPrecision(success)
    if not precisionActive then return end
    local pending = precisionActive
    precisionActive = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closePrecision' })
    pending:resolve(success == true)
end

-- Barra horizontal reutilizavel. Hoje usada pelo pneu, mas pode ser chamada
-- por qualquer recurso com exports.ob_minigame:PrecisionBar({ steps = 3 }).
local function precisionBar(options)
    if hasActiveMinigame() then return false, 'Ja existe um minigame em andamento.' end
    options = type(options) == 'table' and options or {}
    precisionActive = promise.new()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'startPrecision', steps = math.max(1, math.floor(tonumber(options.steps) or 3)) })
    local success = Citizen.Await(precisionActive)
    return success == true
end

exports('PrecisionBar', precisionBar)

local function finishDataCrack(success, reason)
    if not dataCrackActive then return end
    local pending = dataCrackActive
    dataCrackActive = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeDataCrack' })
    pending:resolve(success == true, reason)
end

local function dataCrack(options)
    if hasActiveMinigame() then return false, 'Ja existe um minigame em andamento.' end
    options = type(options) == 'table' and options or {}
    dataCrackActive = promise.new()
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'startDataCrack',
        options = {
            title = options.title or 'INVASAO DA REDE',
            bars = math.max(3, math.min(10, math.floor(tonumber(options.bars) or 6))),
            timeSeconds = math.max(10, math.min(180, math.floor(tonumber(options.timeSeconds) or 40))),
            maxMistakes = math.max(0, math.min(10, math.floor(tonumber(options.maxMistakes) or 3))),
            speed = math.max(0.35, math.min(2.5, tonumber(options.speed) or 1.0)),
            tolerance = math.max(0.035, math.min(0.16, tonumber(options.tolerance) or 0.075)),
        }
    })
    local success, reason = Citizen.Await(dataCrackActive)
    return success == true, reason
end

exports('DataCrack', dataCrack)

local function finishCircuit(success, reason)
    if not circuitActive then return end
    local pending = circuitActive
    circuitActive = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeCircuit' })
    pending:resolve(success == true, reason)
end

local function circuit(options)
    if hasActiveMinigame() then return false, 'Ja existe um minigame em andamento.' end
    options = type(options) == 'table' and options or {}
    circuitActive = promise.new()
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'startCircuit',
        options = {
            title = options.title or 'RECALIBRAR REDE',
            adjustCurrent = options.adjustCurrent == true,
            rows = math.max(3, math.min(5, math.floor(tonumber(options.rows) or 3))),
            maxMultiplier = math.max(3, math.min(9, math.floor(tonumber(options.maxMultiplier) or 5))),
            timeSeconds = math.max(10, math.min(180, math.floor(tonumber(options.timeSeconds) or 45))),
            maxAttempts = math.max(1, math.min(10, math.floor(tonumber(options.maxAttempts) or 4))),
        }
    })
    local success, reason = Citizen.Await(circuitActive)
    return success == true, reason
end

exports('Circuit', circuit)

local function finishWire(success, reason)
    if not wireActive then return end
    local pending = wireActive
    wireActive = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeWire' })
    pending:resolve(success == true, reason)
end

-- Liga os cabos na ordem exibida. Criado para manutencoes eletricas, mas
-- mantido generico para outros recursos usarem o mesmo painel.
local function wireSequence(options)
    if hasActiveMinigame() then return false, 'Ja existe um minigame em andamento.' end
    options = type(options) == 'table' and options or {}
    wireActive = promise.new()
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'startWire',
        options = {
            title = options.title or 'LIGAR CABOS',
            wires = math.max(3, math.min(8, math.floor(tonumber(options.wires) or 5))),
            timeSeconds = math.max(8, math.min(120, math.floor(tonumber(options.timeSeconds) or 30))),
            maxMistakes = math.max(0, math.min(5, math.floor(tonumber(options.maxMistakes) or 2))),
        }
    })
    local success, reason = Citizen.Await(wireActive)
    return success == true, reason
end

exports('WireSequence', wireSequence)

local function cancelActive()
    finish(false, 'cancelado')
    finishPrecision(false)
    finishDataCrack(false, 'cancelado')
    finishCircuit(false, 'cancelado')
    finishWire(false, 'cancelado')
end

exports('Cancel', cancelActive)
RegisterNetEvent('ob_minigame:client:cancel', cancelActive)

RegisterNUICallback('complete', function(data, callback)
    finish(data and data.success == true, data and data.reason)
    callback({ ok = true })
end)

RegisterNUICallback('precisionComplete', function(data, callback)
    finishPrecision(data and data.success == true)
    callback({ ok = true })
end)

RegisterNUICallback('dataCrackComplete', function(data, callback)
    finishDataCrack(data and data.success == true, data and data.reason)
    callback({ ok = true })
end)

RegisterNUICallback('circuitComplete', function(data, callback)
    finishCircuit(data and data.success == true, data and data.reason)
    callback({ ok = true })
end)

RegisterNUICallback('wireComplete', function(data, callback)
    finishWire(data and data.success == true, data and data.reason)
    callback({ ok = true })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        cancelActive()
    end
end)
