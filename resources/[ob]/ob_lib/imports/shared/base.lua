OR = OR or {}
OR.Callback = OR.Callback or {}
OR.Security = OR.Security or {}
OR.Validate = OR.Validate or {}
OR.Streaming = OR.Streaming or {}
OR.Entity = OR.Entity or {}
OR.NUI = OR.NUI or {}
OR.Input = OR.Input or {}
OR.Cache = OR.Cache or {}
OR.Points = OR.Points or {}
OR.Logger = OR.Logger or {}
OR.Model = OR.Model or {}
OR.Progress = OR.Progress or {}
OR.Help = OR.Help or {}
OR.Dialog = OR.Dialog or {}

OR.ResourceName = GetCurrentResourceName()
OR.IsServer = IsDuplicityVersion()
OR.Version = '0.2.0'

function OR.WaitUntil(callback, timeout, interval)
    assert(type(callback) == 'function', 'callback must be a function')
    local deadline = GetGameTimer() + math.max(0, math.floor(tonumber(timeout) or 5000))
    interval = math.max(0, math.floor(tonumber(interval) or 0))
    repeat
        local value = callback()
        if value then return value end
        Wait(interval)
    until GetGameTimer() > deadline
    return nil
end

function OR.Copy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, entry in pairs(value) do copy[OR.Copy(key, seen)] = OR.Copy(entry, seen) end
    return copy
end
