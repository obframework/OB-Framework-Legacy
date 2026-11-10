local securityBuckets = {}

function OR.Security.rateLimit(playerSource, key, limit, windowMs)
    playerSource = OR.Validate.Source(playerSource)
    key = type(key) == 'string' and key:sub(1, 96) or ''
    limit = math.max(1, math.floor(tonumber(limit) or 1))
    windowMs = math.max(250, math.floor(tonumber(windowMs) or 1000))
    if not playerSource or key == '' then return false, windowMs end

    local now = GetGameTimer()
    securityBuckets[playerSource] = securityBuckets[playerSource] or {}
    local bucket = securityBuckets[playerSource][key]
    if not bucket or now < bucket.startedAt or now - bucket.startedAt >= windowMs then
        securityBuckets[playerSource][key] = { startedAt = now, count = 1 }
        return true, 0
    end
    if bucket.count >= limit then return false, math.max(0, windowMs - (now - bucket.startedAt)) end
    bucket.count = bucket.count + 1
    return true, 0
end

OR.Security.validatePayload = OR.Validate.Payload

AddEventHandler('playerDropped', function()
    securityBuckets[tonumber(source)] = nil
end)
