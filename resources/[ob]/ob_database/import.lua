if not IsDuplicityVersion() then return end

OR = OR or {}
OR.Database = OR.Database or {}

local resourceName = GetCurrentResourceName()
local connected = false
local connectionError = 'A conexao com o banco ainda nao foi inicializada.'
local pending = {}
local sequence = 0

AddEventHandler(('ob_database:server:ready:%s'):format(resourceName), function(isReady, errorMessage)
    connected = isReady == true
    connectionError = connected and nil or (errorMessage or 'A conexao com o banco falhou.')
end)

AddEventHandler(('ob_database:server:response:%s'):format(resourceName), function(requestId, ok, result, errorMessage)
    local request = pending[requestId]
    if not request then return end

    pending[requestId] = nil
    request:resolve({ ok = ok == true, result = result, error = errorMessage })
end)

local function subscribe()
    TriggerEvent('ob_database:server:subscribe', resourceName)
end

CreateThread(subscribe)

-- O driver mantém a lista de inscritos em memória. Se apenas o recurso
-- ob_database reiniciar durante desenvolvimento, cada importador se registra
-- novamente e recebe o novo estado da conexão sem exigir restart do core.
AddEventHandler('onResourceStart', function(startedResource)
    if startedResource == 'ob_database' then subscribe() end
end)

AddEventHandler('onResourceStop', function(stoppedResource)
    if stoppedResource == 'ob_database' then
        connected = false
        connectionError = 'O recurso ob_database foi reiniciado.'
    end
end)

local function request(kind, statement, parameters)
    if kind == 'transaction' then
        if type(statement) ~= 'table' or #statement == 0 then
            return nil, 'Transacao SQL invalida.'
        end
    elseif type(statement) ~= 'string' or statement == '' then
        return nil, 'Consulta SQL invalida.'
    end

    sequence = sequence + 1
    local requestId = ('%s:%s:%s'):format(resourceName, GetGameTimer(), sequence)
    local promiseResult = promise.new()
    pending[requestId] = promiseResult

    TriggerEvent('ob_database:server:request', resourceName, requestId, kind, statement, parameters or {})

    SetTimeout(20000, function()
        if pending[requestId] then
            pending[requestId] = nil
            promiseResult:resolve({ ok = false, error = 'Tempo esgotado na consulta SQL.' })
        end
    end)

    local response = Citizen.Await(promiseResult)
    if not response.ok then
        return nil, response.error or 'Falha na consulta SQL.'
    end
    return response.result
end

function OR.Database.isReady()
    return connected
end

function OR.Database.getError()
    return connectionError
end

function OR.Database.waitForReady(timeout)
    local deadline = GetGameTimer() + (timeout or 0)
    while not connected and GetGameTimer() < deadline do
        Wait(100)
    end
    return connected
end

OR.Database.query = OR.Database.query or {}
OR.Database.single = OR.Database.single or {}
OR.Database.scalar = OR.Database.scalar or {}
OR.Database.insert = OR.Database.insert or {}
OR.Database.update = OR.Database.update or {}
OR.Database.transaction = OR.Database.transaction or {}

function OR.Database.query.await(statement, parameters)
    return request('query', statement, parameters)
end

function OR.Database.single.await(statement, parameters)
    return request('single', statement, parameters)
end

function OR.Database.scalar.await(statement, parameters)
    return request('scalar', statement, parameters)
end

function OR.Database.insert.await(statement, parameters)
    return request('insert', statement, parameters)
end

function OR.Database.update.await(statement, parameters)
    return request('update', statement, parameters)
end

-- Executa todas as entradas na mesma conexao e desfaz tudo se uma falhar.
-- Cada entrada aceita: kind, statement, parameters e expectAffectedMin.
function OR.Database.transaction.await(statements)
    return request('transaction', statements, {})
end
