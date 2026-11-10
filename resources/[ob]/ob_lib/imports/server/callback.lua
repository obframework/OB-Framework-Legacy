local resourceName = GetCurrentResourceName()
local callbacks, callbackLocks, pending, sequence = {}, {}, {}, 0
local callbackQueues = {}
local requestEvent = ('ob_lib:server:callback:%s'):format(resourceName)
local responseEvent = ('ob_lib:client:callback:%s'):format(resourceName)
local clientRequestEvent = ('ob_lib:client:request:%s'):format(resourceName)
local serverResponseEvent = ('ob_lib:server:response:%s'):format(resourceName)

local function response(playerSource, requestId, ok, values)
    TriggerClientEvent(responseEvent, playerSource, requestId, ok, values or { n = 0 })
end

function OR.Callback.register(name, callback, options)
    assert(type(name) == 'string' and name ~= '', 'callback name must be a non-empty string')
    assert(type(callback) == 'function', 'callback handler must be a function')
    callbacks[name] = { handler = callback, options = type(options) == 'table' and options or {} }
end

function OR.Callback.unregister(name)
    if type(name) ~= 'string' or not callbacks[name] then return false end
    callbacks[name] = nil
    return true
end

print(('[ob_lib] Callback servidor registrado para %s (%s).'):format(resourceName, requestEvent))

RegisterNetEvent(requestEvent, function(callbackName, requestId, args)
    if type(callbackName) ~= 'string' or callbackName == '' or #callbackName > 96
        or type(requestId) ~= 'string' or requestId == '' or #requestId > 160 then return end

    local playerSource = OR.Validate.Source(source)
    if not playerSource then return end
    local entry = callbacks[callbackName]
    if not entry then
        return response(playerSource, requestId, false, { n = 1, ('Callback nao registrada: %s'):format(callbackName) })
    end

    local options = entry.options
    local totalAllowed, totalRetry = OR.Security.rateLimit(playerSource, '__callbacks_total', 80, 10000)
    local rate = type(options.rateLimit) == 'table' and options.rateLimit or {}
    local endpointAllowed, endpointRetry = OR.Security.rateLimit(playerSource, ('callback:%s'):format(callbackName), rate.limit or 25, rate.window or 10000)
    if not totalAllowed or not endpointAllowed then
        return response(playerSource, requestId, false, {
            n = 1,
            ('Muitas solicitacoes. Aguarde %d ms.'):format(math.max(totalRetry or 0, endpointRetry or 0)),
        })
    end

    args = type(args) == 'table' and args or { n = 0 }
    local payloadOk, payloadError = OR.Validate.Payload(args, options.payload)
    if not payloadOk then
        return response(playerSource, requestId, false, { n = 1, ('Solicitacao recusada: %s.'):format(payloadError) })
    end

    if type(options.validate) == 'function' then
        local validateResult = table.pack(pcall(options.validate, playerSource, table.unpack(args, 1, args.n or #args)))
        if not validateResult[1] or validateResult[2] ~= true then
            return response(playerSource, requestId, false, { n = 1, tostring(validateResult[3] or validateResult[2] or 'Solicitacao recusada.') })
        end
    end

    local lock
    if options.concurrent ~= true then
        -- Serializa rajadas normais (abrir/atualizar/salvar), sem executar duas
        -- mutacoes juntas nem liberar uma operacao ainda ativa por timeout.
        local queue = callbackQueues[playerSource]
        if not queue then queue = {}; callbackQueues[playerSource] = queue end
        if #queue >= 12 then
            return response(playerSource, requestId, false, { n = 1, 'Muitas acoes pendentes. Aguarde um instante.' })
        end
        lock = { name = callbackName, id = requestId, startedAt = GetGameTimer() }
        queue[#queue + 1] = lock
        local deadline = GetGameTimer() + 10000
        while callbackQueues[playerSource] == queue and (callbackLocks[playerSource] or queue[1] ~= lock) do
            if GetGameTimer() >= deadline then
                for index, queued in ipairs(queue) do if queued == lock then table.remove(queue, index); break end end
                local active = callbackLocks[playerSource]
                print(('[ob_lib] Fila lenta em %s: sessao=%s ativo=%s aguardando=%s'):format(
                    resourceName, playerSource, active and active.name or '?', callbackName))
                return response(playerSource, requestId, false, { n = 1, 'O servidor demorou para concluir a acao anterior. Tente novamente.' })
            end
            Wait(10)
        end
        -- Desconexao troca a fila; nunca executar a acao na sessao reutilizada.
        if callbackQueues[playerSource] ~= queue or not OR.Validate.Source(playerSource) then return end
        table.remove(queue, 1)
        callbackLocks[playerSource] = lock
    end
    local results = table.pack(pcall(entry.handler, playerSource, table.unpack(args, 1, args.n or #args)))
    if lock and callbackLocks[playerSource] ~= lock then return end
    if lock then callbackLocks[playerSource] = nil end
    local ok, values = results[1], { n = math.max(0, results.n - 1) }
    for index = 2, results.n do values[index - 1] = results[index] end
    if not ok then print(('[ob_lib] callback %s em %s falhou: %s'):format(callbackName, resourceName, tostring(values[1]))) end
    response(playerSource, requestId, ok, values)
end)

local function newClientRequest(playerSource, name, options, args)
    playerSource = OR.Validate.Source(playerSource)
    if not playerSource then return nil, 'player source must be online' end
    assert(type(name) == 'string' and name ~= '', 'callback name must be a non-empty string')
    options = type(options) == 'table' and options or {}
    sequence = sequence + 1
    local requestId = ('%s:%s:%s:%s'):format(resourceName, playerSource, GetGameTimer(), sequence)
    local requestPromise = promise.new()
    local request = { id = requestId, source = playerSource, promise = requestPromise }
    pending[requestId] = request

    function request:cancel(reason)
        if pending[self.id] ~= self then return false end
        pending[self.id] = nil
        self.promise:resolve({ ok = false, values = { n = 1, reason or 'Callback cancelada.' } })
        return true
    end

    function request:await()
        local result = Citizen.Await(self.promise)
        if not result.ok then return nil, result.values and result.values[1] or 'Falha no callback do cliente.' end
        return table.unpack(result.values, 1, result.values.n or #result.values)
    end

    TriggerClientEvent(clientRequestEvent, playerSource, name, requestId, args)
    SetTimeout(math.max(250, math.floor(tonumber(options.timeout) or 15000)), function()
        if pending[requestId] == request then request:cancel('Tempo esgotado ao contactar o cliente.') end
    end)
    return request
end

function OR.Callback.requestClient(playerSource, name, ...)
    return newClientRequest(playerSource, name, nil, table.pack(...))
end

function OR.Callback.requestClientWithOptions(playerSource, name, options, ...)
    return newClientRequest(playerSource, name, options, table.pack(...))
end

function OR.Callback.awaitClient(playerSource, name, ...)
    local request, requestError = OR.Callback.requestClient(playerSource, name, ...)
    if not request then return nil, requestError end
    return request:await()
end

function OR.Callback.awaitClientWithOptions(playerSource, name, options, ...)
    local request, requestError = OR.Callback.requestClientWithOptions(playerSource, name, options, ...)
    if not request then return nil, requestError end
    return request:await()
end

function OR.Callback.cancel(requestId, reason)
    local request = pending[tostring(requestId)]
    return request and request:cancel(reason) or false
end

RegisterNetEvent(serverResponseEvent, function(requestId, ok, values)
    local playerSource = OR.Validate.Source(source)
    local request = pending[requestId]
    if not playerSource or not request or request.source ~= playerSource then return end
    pending[requestId] = nil
    values = type(values) == 'table' and values or { n = 0 }
    local payloadOk = OR.Validate.Payload(values)
    request.promise:resolve({ ok = ok == true and payloadOk == true, values = payloadOk and values or { n = 1, 'Resposta invalida do cliente.' } })
end)

AddEventHandler('playerDropped', function()
    local playerSource = tonumber(source)
    callbackLocks[playerSource] = nil
    callbackQueues[playerSource] = nil
    local cancelled = {}
    for requestId, request in pairs(pending) do
        if request.source == playerSource then cancelled[#cancelled + 1] = requestId end
    end
    for _, requestId in ipairs(cancelled) do pending[requestId]:cancel('Jogador desconectado.') end
end)
