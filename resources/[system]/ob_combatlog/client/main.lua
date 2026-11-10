local markers = {}

local function cleanText(value, maximum)
    local text = tostring(value or ''):gsub('[\r\n~]', ' ')
    return text:sub(1, maximum or 120)
end

local function addMarker(data)
    if type(data) ~= 'table' or type(data.coords) ~= 'table' then return end
    local x, y, z = tonumber(data.coords.x), tonumber(data.coords.y), tonumber(data.coords.z)
    if not x or not y or not z then return end

    -- `os` nao existe no runtime Lua do cliente FiveM. O servidor calcula
    -- este valor e o cliente somente converte para seu relogio local.
    local remaining = math.max(0, tonumber(data.remainingSeconds) or 0)
    if remaining <= 0 then return end
    local id = tostring(data.id or ('%s:%s'):format(data.userId or '?', data.expiresAt or GetGameTimer()))
    markers[id] = {
        id = id,
        coords = vector3(x, y, z + (tonumber(OBCombatLogConfig.HeightOffset) or 0.25)),
        name = cleanText(data.name, 64),
        userId = tonumber(data.userId),
        reason = cleanText(data.reason, 120),
        status = data.status and cleanText(data.status, 100) or nil,
        time = cleanText(data.time, 32),
        expiresAt = GetGameTimer() + math.floor(remaining * 1000),
    }

    local count, oldestId, oldestExpiry = 0, nil, math.huge
    for markerId, marker in pairs(markers) do
        count = count + 1
        if marker.expiresAt < oldestExpiry then oldestId, oldestExpiry = markerId, marker.expiresAt end
    end
    local maximum = math.max(1, math.floor(tonumber(OBCombatLogConfig.MaximumMarkers) or 50))
    if count > maximum and oldestId then markers[oldestId] = nil end
end

RegisterNetEvent('ob_combatlog:client:playerLeft', addMarker)

RegisterNetEvent('ob_combatlog:client:syncMarkers', function(entries)
    if type(entries) ~= 'table' then return end
    for _, data in ipairs(entries) do addMarker(data) end
end)

local function drawLine(x, y, text, red, green, blue, scale)
    SetTextFont(4)
    SetTextScale(0.0, scale)
    SetTextCentre(true)
    SetTextColour(red, green, blue, 245)
    SetTextOutline()
    SetTextDropShadow()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function drawMarker(marker, distance)
    local visible, screenX, screenY = World3dToScreen2d(marker.coords.x, marker.coords.y, marker.coords.z)
    if not visible then return end
    local scale = math.max(0.26, math.min(0.38, 0.42 - (distance * 0.004)))
    local lineHeight = scale * 0.065
    local lines = {
        { 'DESCONEXAO', 240, 48, 56 },
        { ('Nome: %s'):format(marker.name ~= '' and marker.name or 'Desconhecido'), 245, 245, 245 },
        { ('ID: %s'):format(marker.userId or 'n/a'), 245, 245, 245 },
        { ('Motivo: %s'):format(marker.reason ~= '' and marker.reason or 'Nao informado'), 245, 245, 245 },
        { ('Horario: %s'):format(marker.time ~= '' and marker.time or 'n/a'), 205, 220, 230 },
    }
    if marker.status then lines[#lines + 1] = { marker.status, 255, 190, 92 } end
    local startY = screenY - ((#lines - 1) * lineHeight * 0.5)
    for index, line in ipairs(lines) do
        drawLine(screenX, startY + ((index - 1) * lineHeight), line[1], line[2], line[3], line[4], scale)
    end
end

CreateThread(function()
    while true do
        local waitTime = 500
        local now = GetGameTimer()
        local playerCoords = GetEntityCoords(PlayerPedId())
        local drawDistance = tonumber(OBCombatLogConfig.DrawDistance) or 35.0
        for id, marker in pairs(markers) do
            if marker.expiresAt <= now then
                markers[id] = nil
            else
                local distance = #(playerCoords - marker.coords)
                if distance <= drawDistance then
                    waitTime = 0
                    drawMarker(marker, distance)
                end
            end
        end
        Wait(waitTime)
    end
end)

CreateThread(function()
    while LocalPlayer.state['or:loaded'] ~= true do Wait(500) end
    TriggerServerEvent('ob_combatlog:server:requestMarkers')
    local interval = math.max(500, math.floor(tonumber(OBCombatLogConfig.PositionUpdateMs) or 2000))
    while true do
        local coords = GetEntityCoords(PlayerPedId())
        TriggerServerEvent('ob_combatlog:server:updatePosition', { x = coords.x, y = coords.y, z = coords.z })
        Wait(interval)
    end
end)
