local opened = false
local busy = false

local function send(action, payload)
    payload = payload or {}
    payload.action = action
    SendNUIMessage(payload)
end

local function closeChat()
    if not opened then return end
    opened = false
    busy = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    send('close')
end

local function openChat()
    if opened or busy or IsNuiFocused() or IsPauseMenuActive() then return end
    if LocalPlayer.state['or:loaded'] ~= true then return end
    busy = true
    CreateThread(function()
        local ok, suggestions = pcall(OR.Callback.await, 'suggestions')
        busy = false
        if not ok then suggestions = {} end
        if IsNuiFocused() or IsPauseMenuActive() then return end
        opened = true
        if type(SetNuiZIndex) == 'function' then SetNuiZIndex(10) end
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false)
        send('open', { suggestions = suggestions or {} })
    end)
end

RegisterCommand('+ob_command_chat', openChat, false)
RegisterCommand('-ob_command_chat', function() end, false)
RegisterKeyMapping('+ob_command_chat', 'Abrir chat de comandos', 'keyboard', OBChatConfig.OpenKey or 'T')

RegisterNUICallback('close', function(_, callback)
    closeChat()
    callback({ ok = true })
end)

RegisterNUICallback('submit', function(data, callback)
    if not opened or type(data) ~= 'table' then return callback({ ok = false, error = 'Chat fechado.' }) end
    local value = tostring(data.value or '')
        :gsub('[\r\n]+', ' ')
        :gsub('^%s+', '')
        :gsub('%s+$', '')
        :sub(1, tonumber(OBChatConfig.MaxCommandLength) or 300)
    if value:sub(1, 1) ~= '/' then
        return callback({ ok = false, error = 'Este chat aceita somente comandos iniciados por /.' })
    end
    local commandLine = value:sub(2):gsub('^%s+', '')
    local command = commandLine:match('^([%w_%-]+)')
    if not command or command == '' or command:sub(1, 1) == '-' then
        return callback({ ok = false, error = 'Comando invalido.' })
    end
    closeChat()
    ExecuteCommand(commandLine)
    callback({ ok = true })
end)

local function addMessage(payload)
    if type(payload) ~= 'table' then return end
    send('message', { message = payload, lifetime = OBChatConfig.MessageLifetimeMs, maximum = OBChatConfig.MaximumMessages })
end

local idBusy = false
RegisterCommand('id', function()
    if idBusy or LocalPlayer.state['or:loaded'] ~= true then return end
    local origin, candidates = GetEntityCoords(PlayerPedId()), {}
    for _, playerIndex in ipairs(GetActivePlayers()) do
        if playerIndex ~= PlayerId() then
            local ped = GetPlayerPed(playerIndex)
            if ped and ped > 0 and DoesEntityExist(ped) and #(GetEntityCoords(ped) - origin) <= 2.0 then
                candidates[#candidates + 1] = GetPlayerServerId(playerIndex)
            end
        end
    end
    idBusy = true
    CreateThread(function()
        local ok, result = pcall(OR.Callback.await, 'nearbyIds', candidates)
        idBusy = false
        if not ok or type(result) ~= 'table' then
            return addMessage({ channel = 'SISTEMA', message = 'Nao foi possivel consultar os IDs proximos.', colour = { 255, 91, 116 } })
        end
        if #result == 0 then
            return addMessage({ channel = 'SISTEMA', message = 'Nenhuma pessoa encontrada em um raio de 2 metros.', colour = { 255, 190, 74 } })
        end
        local entries = {}
        for _, person in ipairs(result) do
            entries[#entries + 1] = ('%s (ID %s)'):format(tostring(person.name or 'Pessoa'), tostring(person.id or '?'))
        end
        addMessage({ channel = 'PESSOAS PROXIMAS', message = table.concat(entries, ', '), colour = { 78, 210, 255 } })
    end)
end, false)

RegisterNetEvent('ob_chat:client:addMessage', addMessage)

RegisterNetEvent('chat:addMessage', function(payload)
    if type(payload) ~= 'table' then return end
    local args = type(payload.args) == 'table' and payload.args or {}
    local parts = {}
    for index = 2, #args do
        parts[#parts + 1] = tostring(args[index])
    end
    addMessage({
        channel = tostring(args[1] or payload.channel or 'SISTEMA'),
        message = #parts > 0 and table.concat(parts, ' ') or tostring(payload.message or ''),
        colour = payload.color or payload.colour,
    })
end)

RegisterNetEvent('chat:clear', function() send('clear') end)

RegisterNetEvent('chatMessage', function(author, colour, message)
    addMessage({ author = author, message = message, colour = colour })
end)

exports('AddMessage', addMessage)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then closeChat() end
end)
