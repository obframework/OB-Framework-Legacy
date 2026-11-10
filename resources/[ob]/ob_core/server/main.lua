math.randomseed(os.time() + GetGameTimer())
local clientSessionsReady = {}
local clientSessionRequests = {}

OR.Callback.register('listCharacters', function(source)
    return ORCore.ListCharacters(source)
end)

OR.Callback.register('selectCharacter', function(source, userId)
    return ORCore.SelectCharacter(source, userId)
end)

OR.Callback.register('createCharacter', function(source, payload)
    return ORCore.CreateCharacter(source, payload)
end)

RegisterNetEvent('ob_core:server:clientReady', function()
    local source = source
    CreateThread(function()
        if clientSessionsReady[source] then
            TriggerClientEvent('ob_core:client:sessionReady', source)
            return
        end
        if clientSessionRequests[source] then return end
        clientSessionRequests[source] = true

        if not Database.waitForReady(15000) then
            clientSessionRequests[source] = nil
            TriggerClientEvent('ob_core:client:databaseUnavailable', source, Database.error or 'O banco de dados nao respondeu.')
            return
        end

        local session, err = ORCore.EnsureSession(source)
        if not session then
            clientSessionRequests[source] = nil
            print(('[ob_core] Nao foi possivel preparar a sessao de %s: %s'):format(source, err or 'erro desconhecido'))
            TriggerClientEvent('ob_core:client:databaseUnavailable', source, err or 'Nao foi possivel preparar sua sessao.')
            return
        end

        clientSessionsReady[source] = true
        clientSessionRequests[source] = nil
        TriggerClientEvent('ob_core:client:sessionReady', source)
        if session.spawned then return end

        ORCore.SetSelectionInstance(source)
        print(('[ob_core] Seletor de personagem enviado para %s.'):format(source))
        TriggerClientEvent('ob_core:client:openSelector', source)
    end)
end)

-- Comando de rede interno. O evento `ob_core:server:playerSpawned` é emitido
-- localmente pelo core para que outros recursos acompanhem a entrada na
-- cidade; não pode compartilhar o mesmo nome deste handler de rede.
RegisterNetEvent('ob_core:server:markSpawned', function()
    ORCore.MarkSpawned(source)
end)

local function sanitizeMeText(value)
    if type(value) ~= 'string' then return '' end
    local maxLength = math.max(1, math.floor(tonumber((ORCoreConfig.Me or {}).MaxLength) or 140))
    value = value:gsub('[\r\n]+', ' '):gsub('~', ''):gsub('%s+', ' ')
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    return value:sub(1, maxLength)
end

RegisterCommand('me', function(source, args)
    if source <= 0 then
        print('[ob_core] Use /me dentro do servidor.')
        return
    end
    if not ORCore.HasSpawned(source) or not ORCore.GetUserId(source) then return end

    local message = sanitizeMeText(table.concat(args or {}, ' '))
    if message == '' then
        TriggerClientEvent('ob_notification:client:notify', source, 'Uso: /me [acao]', 'info')
        return
    end

    TriggerClientEvent('ob_core:client:showMe', -1, source, ORCore.GetFullName(source) or GetPlayerName(source) or 'Pessoa', message)
end, false)

AddEventHandler('playerJoining', function()
    ORCore.SetSelectionInstance(source)
end)

AddEventHandler('playerDropped', function()
    -- Eventos abaixo podem aguardar banco. Preserve o source antes disso.
    local playerSource = tonumber(source)
    if not playerSource then return end

    local player = ORCore.GetPlayer(playerSource)
    if player then
        TriggerEvent('ob_core:server:playerUnloading', playerSource, player.character)
    end
    ORCore.SavePosition(playerSource)
    ORCore.Players[playerSource] = nil
    clientSessionsReady[playerSource] = nil
    clientSessionRequests[playerSource] = nil
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, source in ipairs(GetPlayers()) do
        ORCore.SetSelectionInstance(tonumber(source))
    end
end)

CreateThread(function()
    while true do
        Wait(ORCoreConfig.PositionSaveInterval)
        if Database.ready then
            for source, player in pairs(ORCore.Players) do
                if player.spawned and GetPlayerName(source) then
                    ORCore.SavePosition(source)
                end
            end
        end
    end
end)
