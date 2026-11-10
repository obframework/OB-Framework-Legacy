local resourceName = GetCurrentResourceName()
local pending, registeredResponses, clientCallbacks, sequence = {}, {}, {}, 0
local clientRequestEvent = ('ob_lib:client:request:%s'):format(resourceName)
local serverResponseEvent = ('ob_lib:server:response:%s'):format(resourceName)

local function registerResponseEvent(targetResource)
    local responseEvent = ('ob_lib:client:callback:%s'):format(targetResource)
    if registeredResponses[responseEvent] then return end
    registeredResponses[responseEvent] = true
    RegisterNetEvent(responseEvent, function(requestId, ok, values)
        local request = pending[requestId]
        if not request then return end
        pending[requestId] = nil
        values = type(values) == 'table' and values or { n = 0 }
        if ok ~= true then
            print(('[ob_lib] Callback de %s falhou em %s: %s'):format(targetResource, resourceName, tostring(values[1])))
        end
        request.promise:resolve({ ok = ok == true, values = values })
    end)
end

local function newServerRequest(targetResource, name, options, args)
    assert(type(targetResource) == 'string' and targetResource ~= '', 'target resource must be a non-empty string')
    assert(type(name) == 'string' and name ~= '', 'callback name must be a non-empty string')
    options = type(options) == 'table' and options or {}
    sequence = sequence + 1
    local requestId = ('%s:%s:%s:%s'):format(resourceName, targetResource, GetGameTimer(), sequence)
    local requestPromise = promise.new()
    local request = { id = requestId, promise = requestPromise }
    pending[requestId] = request

    function request:cancel(reason)
        if pending[self.id] ~= self then return false end
        pending[self.id] = nil
        self.promise:resolve({ ok = false, values = { n = 1, reason or 'Callback cancelada.' } })
        return true
    end

    function request:await()
        local result = Citizen.Await(self.promise)
        if not result.ok then return nil, result.values and result.values[1] or 'Falha no callback do servidor.' end
        return table.unpack(result.values, 1, result.values.n or #result.values)
    end

    registerResponseEvent(targetResource)
    TriggerServerEvent(('ob_lib:server:callback:%s'):format(targetResource), name, requestId, args)
    SetTimeout(math.max(250, math.floor(tonumber(options.timeout) or 15000)), function()
        if pending[requestId] == request then request:cancel('Tempo esgotado ao contactar o servidor.') end
    end)
    return request
end

function OR.Callback.requestResource(targetResource, name, ...)
    return newServerRequest(targetResource, name, nil, table.pack(...))
end

function OR.Callback.requestResourceWithOptions(targetResource, name, options, ...)
    return newServerRequest(targetResource, name, options, table.pack(...))
end

function OR.Callback.awaitResource(targetResource, name, ...)
    return OR.Callback.requestResource(targetResource, name, ...):await()
end

function OR.Callback.awaitResourceWithOptions(targetResource, name, options, ...)
    return OR.Callback.requestResourceWithOptions(targetResource, name, options, ...):await()
end

function OR.Callback.request(name, ...)
    return OR.Callback.requestResource(resourceName, name, ...)
end

function OR.Callback.await(name, ...)
    return OR.Callback.awaitResource(resourceName, name, ...)
end

function OR.Callback.cancel(requestId, reason)
    local request = pending[tostring(requestId)]
    return request and request:cancel(reason) or false
end

function OR.Callback.registerClient(name, callback, options)
    assert(type(name) == 'string' and name ~= '', 'callback name must be a non-empty string')
    assert(type(callback) == 'function', 'callback handler must be a function')
    clientCallbacks[name] = { handler = callback, options = type(options) == 'table' and options or {} }
end

function OR.Callback.unregisterClient(name)
    if type(name) ~= 'string' or not clientCallbacks[name] then return false end
    clientCallbacks[name] = nil
    return true
end

RegisterNetEvent(clientRequestEvent, function(callbackName, requestId, args)
    if type(callbackName) ~= 'string' or callbackName == '' or #callbackName > 96
        or type(requestId) ~= 'string' or requestId == '' or #requestId > 160 then return end
    local entry = clientCallbacks[callbackName]
    if not entry then
        return TriggerServerEvent(serverResponseEvent, requestId, false, { n = 1, ('Callback cliente nao registrada: %s'):format(callbackName) })
    end
    args = type(args) == 'table' and args or { n = 0 }
    local payloadOk, payloadError = OR.Validate.Payload(args, entry.options.payload)
    if not payloadOk then
        return TriggerServerEvent(serverResponseEvent, requestId, false, { n = 1, payloadError })
    end
    if type(entry.options.validate) == 'function' then
        local valid = table.pack(pcall(entry.options.validate, table.unpack(args, 1, args.n or #args)))
        if not valid[1] or valid[2] ~= true then
            return TriggerServerEvent(serverResponseEvent, requestId, false, { n = 1, tostring(valid[3] or valid[2] or 'Solicitacao recusada.') })
        end
    end
    local results = table.pack(pcall(entry.handler, table.unpack(args, 1, args.n or #args)))
    local ok, values = results[1], { n = math.max(0, results.n - 1) }
    for index = 2, results.n do values[index - 1] = results[index] end
    TriggerServerEvent(serverResponseEvent, requestId, ok, values)
end)

AddEventHandler('onResourceStop', function(stoppedResource)
    if stoppedResource ~= resourceName then return end
    local cancelled = {}
    for requestId in pairs(pending) do cancelled[#cancelled + 1] = requestId end
    for _, requestId in ipairs(cancelled) do pending[requestId]:cancel('Resource encerrado.') end
end)
