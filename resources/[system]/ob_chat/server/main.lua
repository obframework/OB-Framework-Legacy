local function clean(value, maximum)
    value = tostring(value or '')
        :gsub('[\r\n]+', ' ')
        :gsub('~', '')
        :gsub('%^%d', '')
        :gsub('%s+', ' ')
        :gsub('^%s+', '')
        :gsub('%s+$', '')
    return value:sub(1, maximum or 220)
end

local function organisationState(source)
    local state = Player(tonumber(source)).state['ob:org']
    return type(state) == 'table' and state or nil
end

local function departmentMember(source, requireDuty)
    local org = organisationState(source)
    if not org or OBChatConfig.DepartmentKeys[tostring(org.key or ''):lower()] ~= true then return nil end
    if requireDuty and org.onDuty ~= true then return nil end
    return org
end

local function allowedSuggestion(source, suggestion)
    local org = organisationState(source)
    if suggestion.requireDuty == true and (not org or org.onDuty ~= true) then return false end
    if suggestion.department == true then return departmentMember(source, suggestion.requireDuty == true) ~= nil end
    if suggestion.organisationType then
        return org ~= nil and org.type == suggestion.organisationType
    end
    if type(suggestion.organisationKeys) == 'table' then
        return org ~= nil and suggestion.organisationKeys[tostring(org.key or ''):lower()] == true
    end
    return true
end

OR.Callback.register('suggestions', function(source)
    local result = {}
    for _, suggestion in ipairs(OBChatConfig.Suggestions or {}) do
        if allowedSuggestion(source, suggestion) then
            result[#result + 1] = {
                command = suggestion.command,
                arguments = suggestion.arguments,
                description = suggestion.description,
            }
        end
    end
    return result
end)

OR.Callback.register('nearbyIds', function(source, candidates)
    source = tonumber(source)
    if not source or source <= 0 or type(candidates) ~= 'table' then return {} end
    if not OR.Security.rateLimit(source, 'chat:nearby_ids', 4, 5000) then return {} end
    local sourcePed = GetPlayerPed(source)
    if sourcePed == 0 then return {} end
    local origin, bucket = GetEntityCoords(sourcePed), GetPlayerRoutingBucket(source)
    local found, seen = {}, {}
    for index = 1, math.min(#candidates, 32) do
        local target = tonumber(candidates[index])
        if target and target > 0 and target ~= source and not seen[target] and GetPlayerName(target)
            and GetPlayerRoutingBucket(target) == bucket then
            seen[target] = true
            local targetPed = GetPlayerPed(target)
            if targetPed ~= 0 then
                local coords = GetEntityCoords(targetPed)
                local dx, dy, dz = origin.x - coords.x, origin.y - coords.y, origin.z - coords.z
                local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
                if distance <= 2.25 then
                    local userId = exports.ob_core:GetUserId(target)
                    if userId then
                        found[#found + 1] = {
                            id = tonumber(userId),
                            name = clean(exports.ob_core:GetFullName(target) or GetPlayerName(target), 80),
                            distance = distance,
                        }
                    end
                end
            end
        end
    end
    table.sort(found, function(a, b)
        if a.distance == b.distance then return a.id < b.id end
        return a.distance < b.distance
    end)
    for _, entry in ipairs(found) do entry.distance = nil end
    return found
end)

local function reply(source, message, kind)
    TriggerClientEvent('ob_chat:client:addMessage', source, {
        channel = 'SISTEMA',
        message = message,
        colour = kind == 'error' and { 255, 91, 116 } or { 78, 210, 255 },
    })
end

RegisterCommand(OBChatConfig.DepartmentCommand or 'pd', function(source, args)
    source = tonumber(source)
    if not source or source <= 0 then return end
    if not OR.Security.rateLimit(source, 'chat:department', 5, 10000) then
        return reply(source, 'Aguarde um instante antes de enviar outra mensagem.', 'error')
    end

    local senderOrg = departmentMember(source, true)
    if not senderOrg then
        return reply(source, 'O /pd e exclusivo para servicos publicos em servico.', 'error')
    end

    local message = clean(table.concat(args or {}, ' '), OBChatConfig.MaxDepartmentMessageLength)
    if message == '' then return reply(source, ('Uso: /%s [mensagem]'):format(OBChatConfig.DepartmentCommand or 'pd'), 'error') end

    local author = clean(exports.ob_core:GetFullName(source) or GetPlayerName(source) or 'Desconhecido', 80)
    local department = clean(senderOrg.label or senderOrg.key or 'Servico publico', 80)
    local rank = clean(senderOrg.rankLabel or '', 60)
    for _, player in ipairs(GetPlayers()) do
        local target = tonumber(player)
        if target and departmentMember(target, true) then
            TriggerClientEvent('ob_chat:client:addMessage', target, {
                channel = OBChatConfig.DepartmentLabel or 'SERVICOS PUBLICOS',
                author = author,
                department = department,
                rank = rank,
                message = message,
                colour = OBChatConfig.DepartmentColour,
            })
        end
    end
end, false)
