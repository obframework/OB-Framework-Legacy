local lastRequest = {}

local function attempt(callback)
    local ok, result = pcall(callback)
    return ok and result or nil
end

local function buildProfile(source)
    local data = attempt(function() return exports.ob_core:GetPlayerData(source) end) or {}
    local character = type(data.character) == 'table' and data.character or {}
    local job = attempt(function() return exports.ob_core:GetJob(source) end) or {}
    local name = attempt(function() return exports.ob_core:GetFullName(source) end)

    if type(name) ~= 'string' or name == '' then
        name = GetPlayerName(source) or 'Cidadao'
    end

    local cash = 0
    local bank = 0
    if OBPauseMenuConfig.ShowCash ~= false and GetResourceState('ob_inventory') == 'started' then
        cash = tonumber(attempt(function() return exports.ob_inventory:GetMoney(source, 'money') end)) or 0
    end
    if OBPauseMenuConfig.ShowBank ~= false and GetResourceState('ob_bank') == 'started' then
        bank = tonumber(attempt(function() return exports.ob_bank:GetBalance(source) end)) or 0
    end

    return {
        serverId = source,
        userId = tonumber(character.userId) or 0,
        name = name,
        firstname = character.firstname or '',
        lastname = character.lastname or '',
        birthdate = character.birthdate or '',
        nationality = character.nationality or '',
        job = {
            name = job.name or 'unemployed',
            label = job.label or 'Desempregado',
            grade = tonumber(job.grade) or 0,
            onDuty = job.onDuty == true,
        },
        money = { cash = cash, bank = bank },
        online = #GetPlayers(),
        maxPlayers = GetConvarInt('sv_maxclients', 64),
    }
end

RegisterNetEvent('ob_pausemenu:server:requestProfile', function()
    local source = source
    local now = GetGameTimer()
    if lastRequest[source] and now - lastRequest[source] < 400 then return end
    lastRequest[source] = now
    TriggerClientEvent('ob_pausemenu:client:profile', source, buildProfile(source))
end)

RegisterNetEvent('ob_pausemenu:server:disconnect', function()
    local source = source
    DropPlayer(source, 'Voce saiu da cidade pelo menu da OB Framework.')
end)

AddEventHandler('playerDropped', function()
    lastRequest[source] = nil
end)
