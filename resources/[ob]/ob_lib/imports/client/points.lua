local Points = OR.Points
local points, sequence, running, helpVisible = {}, 0, false, false

local function invoke(point, name, ...)
    local callback = point[name]
    if type(callback) ~= 'function' then return nil end
    local result = table.pack(pcall(callback, point, ...))
    if not result[1] then
        OR.Logger.error(('point %s/%s falhou'):format(point.id, name), result[2])
        return nil
    end
    return table.unpack(result, 2, result.n)
end

function Points.DrawMarker(point)
    local marker = point.marker
    if marker == false then return end
    marker = type(marker) == 'table' and marker or {}
    local coords = point.coords
    local color = marker.color or { 31, 157, 255, 180 }
    local scale = marker.scale or { 1.0, 1.0, 0.25 }
    DrawMarker(marker.type or 1,
        coords.x, coords.y, coords.z + (tonumber(marker.zOffset) or -0.95),
        0.0, 0.0, 0.0, 0.0, 0.0, tonumber(marker.heading) or 0.0,
        tonumber(scale.x or scale[1]) or 1.0, tonumber(scale.y or scale[2]) or 1.0, tonumber(scale.z or scale[3]) or 0.25,
        tonumber(color.r or color[1]) or 31, tonumber(color.g or color[2]) or 157,
        tonumber(color.b or color[3]) or 255, tonumber(color.a or color[4]) or 180,
        marker.bob == true, marker.faceCamera == true, 2, marker.rotate == true, nil, nil, false)
end

local function startThread()
    if running then return end
    running = true
    CreateThread(function()
        while next(points) do
            local playerCoords = GetEntityCoords(PlayerPedId())
            local sleep, interaction = 1000, nil
            for _, point in pairs(points) do
                local distance = #(playerCoords - point.coords)
                local inside = point.enabled and distance <= point.distance
                if inside and not point.inside then point.inside = true; invoke(point, 'onEnter', distance) end
                if not inside and point.inside then point.inside = false; invoke(point, 'onExit', distance) end
                if inside then
                    sleep = 0
                    if point.marker ~= false then Points.DrawMarker(point) end
                    invoke(point, 'nearby', distance)
                    local canInteract = type(point.canInteract) ~= 'function' or invoke(point, 'canInteract', distance) == true
                    if canInteract and distance <= point.interactDistance and (not interaction or distance < interaction.distance) then
                        interaction = { point = point, distance = distance }
                    end
                elseif distance <= point.distance * 2.0 then
                    sleep = math.min(sleep, 200)
                end
            end

            if interaction then
                local point = interaction.point
                if point.label and OR.Help then OR.Help.Show(point.label); helpVisible = true end
                if IsControlJustReleased(0, point.control) then invoke(point, 'onInteract', interaction.distance) end
            elseif helpVisible and OR.Help then
                OR.Help.Hide()
                helpVisible = false
            end
            Wait(sleep)
        end
        if helpVisible and OR.Help then OR.Help.Hide() end
        helpVisible, running = false, false
    end)
end

function Points.Create(data)
    assert(type(data) == 'table', 'point data must be a table')
    local coords = OR.Validate.Coords(data.coords)
    assert(coords, 'point coords must be valid')
    sequence = sequence + 1
    local point = {
        id = tostring(data.id or ('point_%s'):format(sequence)),
        coords = coords,
        distance = math.max(1.0, tonumber(data.distance) or 25.0),
        interactDistance = math.max(0.25, tonumber(data.interactDistance) or 2.0),
        control = math.floor(tonumber(data.control) or 38),
        label = data.label,
        marker = data.marker,
        onEnter = data.onEnter,
        onExit = data.onExit,
        nearby = data.nearby,
        onInteract = data.onInteract,
        canInteract = data.canInteract,
        enabled = data.enabled ~= false,
        inside = false,
    }
    function point:remove() return Points.Remove(self.id) end
    function point:setEnabled(value) self.enabled = value == true return self.enabled end
    function point:update(values)
        values = type(values) == 'table' and values or {}
        if values.coords then self.coords = assert(OR.Validate.Coords(values.coords), 'point coords must be valid') end
        if values.distance ~= nil then self.distance = math.max(1.0, tonumber(values.distance) or self.distance) end
        if values.interactDistance ~= nil then self.interactDistance = math.max(0.25, tonumber(values.interactDistance) or self.interactDistance) end
        if values.control ~= nil then self.control = math.floor(tonumber(values.control) or self.control) end
        if values.enabled ~= nil then self.enabled = values.enabled == true end
        for _, key in ipairs({ 'label', 'marker', 'onEnter', 'onExit', 'nearby', 'onInteract', 'canInteract' }) do
            if values[key] ~= nil then self[key] = values[key] end
        end
        return self
    end
    if points[point.id] then Points.Remove(point.id) end
    points[point.id] = point
    startThread()
    return point
end

function Points.Get(id) return points[tostring(id)] end

function Points.Remove(id)
    id = tostring(id)
    local point = points[id]
    if not point then return false end
    if point.inside then invoke(point, 'onExit', math.huge) end
    points[id] = nil
    return true
end

function Points.Clear()
    local ids = {}
    for id in pairs(points) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do Points.Remove(id) end
end

AddEventHandler('onResourceStop', function(stoppedResource)
    if stoppedResource == GetCurrentResourceName() then Points.Clear() end
end)
