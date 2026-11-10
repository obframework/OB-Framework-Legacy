local Validate = OR.Validate

function Validate.Number(value, minimum, maximum, integer)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    if integer == true then value = math.floor(value) end
    minimum, maximum = tonumber(minimum), tonumber(maximum)
    if minimum and value < minimum then return nil end
    if maximum and value > maximum then return nil end
    return value
end

function Validate.String(value, maximumLength, allowEmpty)
    if type(value) ~= 'string' then return nil end
    if allowEmpty ~= true and value == '' then return nil end
    maximumLength = math.max(1, math.floor(tonumber(maximumLength) or 65535))
    if #value > maximumLength then return nil end
    return value
end

function Validate.Coords(value)
    if type(value) ~= 'table' and type(value) ~= 'vector3' and type(value) ~= 'vector4' then return nil end
    local x = Validate.Number(value.x or value[1], -200000.0, 200000.0)
    local y = Validate.Number(value.y or value[2], -200000.0, 200000.0)
    local z = Validate.Number(value.z or value[3], -200000.0, 200000.0)
    if not x or not y or not z then return nil end
    return vector3(x, y, z)
end

function Validate.Payload(value, options)
    options = type(options) == 'table' and options or {}
    local maxDepth = math.max(1, math.floor(tonumber(options.maxDepth) or 8))
    local maxNodes = math.max(16, math.floor(tonumber(options.maxNodes) or 2500))
    local maxStringBytes = math.max(256, math.floor(tonumber(options.maxStringBytes) or 131072))
    local nodes, stringBytes, visited = 0, 0, {}

    local function walk(entry, depth)
        local entryType = type(entry)
        nodes = nodes + 1
        if nodes > maxNodes then return false, 'payload possui elementos demais' end
        if entryType == 'string' then
            stringBytes = stringBytes + #entry
            if stringBytes > maxStringBytes then return false, 'payload de texto muito grande' end
            return true
        end
        if entryType == 'number' then
            return entry == entry and entry ~= math.huge and entry ~= -math.huge, 'numero invalido'
        end
        if entryType ~= 'table' then
            return entryType ~= 'function' and entryType ~= 'thread' and entryType ~= 'userdata', 'tipo de payload invalido'
        end
        if depth >= maxDepth then return false, 'payload muito profundo' end
        if visited[entry] then return false, 'payload circular' end
        visited[entry] = true
        for entryKey, entryValue in pairs(entry) do
            local keyOk, keyError = walk(entryKey, depth + 1)
            if not keyOk then visited[entry] = nil return false, keyError end
            local valueOk, valueError = walk(entryValue, depth + 1)
            if not valueOk then visited[entry] = nil return false, valueError end
        end
        visited[entry] = nil
        return true
    end

    return walk(value, 0)
end

function Validate.Source(playerSource)
    if not IsDuplicityVersion() then return nil end
    playerSource = Validate.Number(playerSource, 1, 65535, true)
    return playerSource and GetPlayerName(playerSource) and playerSource or nil
end

function Validate.NetId(netId)
    netId = Validate.Number(netId, 1, 2147483647, true)
    if not netId then return nil end
    if NetworkDoesEntityExistWithNetworkId and not NetworkDoesEntityExistWithNetworkId(netId) then return nil end
    return netId
end

function Validate.EntityOwner(playerSource, entity)
    playerSource = Validate.Source(playerSource)
    entity = Validate.Number(entity, 1, 2147483647, true)
    if not playerSource or not entity or not DoesEntityExist(entity) then return false end
    return NetworkGetEntityOwner(entity) == playerSource
end

Validate.number = Validate.Number
Validate.string = Validate.String
Validate.coords = Validate.Coords
Validate.payload = Validate.Payload
Validate.source = Validate.Source
Validate.netId = Validate.NetId
Validate.entityOwner = Validate.EntityOwner
