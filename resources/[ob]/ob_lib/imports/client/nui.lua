local NUI = OR.NUI
local resourceName = GetCurrentResourceName()
local open, forceCloseHandler = false, nil

local function coordinator(method, ...)
    if GetResourceState('ob_lib') ~= 'started' then return false end
    local arguments = table.pack(...)
    -- Export dinamico do Cfx espera o primeiro argumento reservado ao self,
    -- da mesma forma que a chamada comum exports.ob_lib:Nome(...).
    local ok, result = pcall(function() return exports.ob_lib[method](nil, table.unpack(arguments, 1, arguments.n)) end)
    return ok and result or false
end

function NUI.SetFocus(enabled, keepInput)
    enabled = enabled == true
    SetNuiFocus(enabled, enabled)
    SetNuiFocusKeepInput(enabled and keepInput == true)
end

function NUI.Send(data)
    if type(data) ~= 'table' then return false end
    SendNUIMessage(data)
    return true
end

function NUI.Open(data, options)
    options = type(options) == 'table' and options or {}
    coordinator('ClaimNui', resourceName, options.exclusive ~= false)
    open = true
    forceCloseHandler = type(options.onForceClose) == 'function' and options.onForceClose or nil
    NUI.SetFocus(options.focus ~= false, options.keepInput == true)
    local message = type(data) == 'table' and OR.Copy(data) or {}
    message.action = message.action or options.action or 'open'
    NUI.Send(message)
    return true
end

function NUI.Close(data)
    local message = type(data) == 'table' and OR.Copy(data) or {}
    message.action = message.action or 'close'
    NUI.Send(message)
    NUI.SetFocus(false, false)
    coordinator('ReleaseNui', resourceName)
    open, forceCloseHandler = false, nil
    return true
end

function NUI.Reset(sendClose)
    if sendClose ~= false then SendNUIMessage({ action = 'close', reset = true }) end
    NUI.SetFocus(false, false)
    coordinator('ReleaseNui', resourceName)
    open, forceCloseHandler = false, nil
end

function NUI.IsOpen()
    return open
end

function NUI.Register(name, callback)
    assert(type(name) == 'string' and name ~= '', 'NUI callback name must be a non-empty string')
    assert(type(callback) == 'function', 'NUI callback handler must be a function')
    RegisterNUICallback(name, function(data, reply)
        local replied = false
        local function respond(value)
            if replied then return end
            replied = true
            reply(value == nil and { ok = true } or value)
        end
        local ok, result = pcall(callback, type(data) == 'table' and data or {}, respond)
        if not ok then
            OR.Logger.error(('NUI callback %s falhou'):format(name), result)
            return respond({ ok = false, error = tostring(result) })
        end
        if not replied and result ~= nil then respond(result) end
    end)
end

RegisterNetEvent('ob_lib:client:nui:forceClose', function(owner, nextOwner)
    if owner ~= resourceName or not open then return end
    if forceCloseHandler then pcall(forceCloseHandler, nextOwner) end
    NUI.Reset(true)
end)

AddEventHandler('onResourceStop', function(stoppedResource)
    if stoppedResource == resourceName and open then NUI.Reset(false) end
end)
