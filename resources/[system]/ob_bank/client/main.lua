local peds, blips, uiOpen, registeredAtms, registeredAtmZones, branchZones = {}, {}, false, {}, {}, {}

exports('IsServicePed', function(ped)
    for _, branchPed in pairs(peds) do
        if branchPed == ped then return true end
    end
    return false
end)

local function closeUi()
    uiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function openBank(branch)
    if uiOpen then return end
    local ok, data = OR.Callback.await('getAccount')
    if not ok then return OR.Notify(data or 'Nao foi possivel abrir o banco.', 'error') end
    uiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = { account = data, branch = branch == true } })
end

RegisterNetEvent('ob_bank:client:openAtm', function() openBank(false) end)
RegisterNetEvent('ob_bank:client:openBranch', function() openBank(true) end)

local function registerAtms()
    for _, modelName in ipairs(BankConfig.AtmModels) do
        exports.ob_target:AddEntityOption('ob_bank:atm:' .. modelName, {
            model = joaat(modelName), entityType = 3, distance = 1.7,
            label = 'Usar caixa eletronico', icon = '$', event = 'ob_bank:client:openAtm',
        })
    end
    for index, branch in ipairs(BankConfig.Branches) do
        local zoneId = 'ob_bank:branch:' .. index
        branchZones[zoneId] = true
        exports.ob_target:RegisterSphereZone(zoneId, {
            coords = branch.coords, radius = 1.25,
            option = { label = 'Acessar atendimento bancario', icon = '$', distance = 2.0, event = 'ob_bank:client:openBranch' },
        })
    end
end

-- Props de mapa podem nao aparecer no raycast do Enhanced. Ao registrar cada
-- handle local, o ob_target tambem os consulta diretamente, igual aos NPCs.
local function registerLoadedAtms()
    local models = {}
    for _, modelName in ipairs(BankConfig.AtmModels) do models[joaat(modelName)] = true end
    local function registerObject(object)
        if not object or object == 0 or registeredAtms[object] then return end
        registeredAtms[object] = true
        exports.ob_target:RegisterEntity('ob_bank:atm:entity:' .. object, object, {
            label = 'Usar caixa eletronico', icon = '$', distance = 2.0,
            event = 'ob_bank:client:openAtm',
        })
        local zoneId = 'ob_bank:atm:zone:' .. object
        local coords = GetEntityCoords(object)
        registeredAtmZones[zoneId] = true
        exports.ob_target:RegisterSphereZone(zoneId, {
            coords = coords, radius = 1.45,
            option = { label = 'Usar caixa eletronico', icon = '$', event = 'ob_bank:client:openAtm' },
        })
    end
    -- Evite GetGamePool('CObject'): builds do Enhanced podem encerrar dentro
    -- da enumeracao. A busca local abaixo roda periodicamente e registra o
    -- caixa proximo por handle e por zona.
    local playerCoords = GetEntityCoords(PlayerPedId())
    for model in pairs(models) do
        registerObject(GetClosestObjectOfType(playerCoords.x, playerCoords.y, playerCoords.z, 45.0, model, false, false, false))
    end
end

local function registerBranches()
    for index, branch in ipairs(BankConfig.Branches) do
        local c = branch.coords
        if branch.blip then
            local blip = AddBlipForCoord(c.x, c.y, c.z)
            SetBlipSprite(blip, 108); SetBlipColour(blip, 2); SetBlipScale(blip, 0.7); SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING'); AddTextComponentString(branch.label); EndTextCommandSetBlipName(blip)
            blips[index] = blip
        end
    end
    registerAtms()
end

RegisterNUICallback('action', function(data, cb)
    local action, value = data and data.action, data and data.value
    local callback = action == 'deposit' and 'deposit' or action == 'withdraw' and 'withdraw'
        or action == 'card' and 'issueCard' or action == 'resetPin' and 'resetPin'
        or action == 'fine' and 'payFine'
    if not callback then cb({ ok = false, message = 'Acao invalida.' }) return end
    local ok, message
    if callback == 'payFine' then ok, message = OR.Callback.await(callback, value)
    elseif callback == 'deposit' then ok, message = OR.Callback.await(callback, value, data and data.pin)
    elseif callback == 'withdraw' then ok, message = OR.Callback.await(callback, value, data and data.pin)
    else ok, message = OR.Callback.await(callback, data and data.pin) end
    local accountOk, account = OR.Callback.await('getAccount')
    cb({ ok = ok == true, message = message, account = accountOk and account or nil })
end)
RegisterNUICallback('close', function(_, cb) closeUi(); cb({ ok = true }) end)

CreateThread(function()
    -- Nao depende de state bag de personagem: se ela nao for publicada por
    -- algum motivo, os ATMs e os gerentes ainda precisam existir.
    Wait(1000)
    registerBranches()
end)
CreateThread(function()
    Wait(1200)
    while true do
        registerLoadedAtms()
        Wait(2000)
    end
end)
AddEventHandler('ob_target:client:ready', function()
    registeredAtms = {}
    registeredAtmZones = {}
    branchZones = {}
    registerAtms()
    registerLoadedAtms()
end)
AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    closeUi()
    for zoneId in pairs(branchZones) do exports.ob_target:UnregisterZone(zoneId) end
    for zoneId in pairs(registeredAtmZones) do exports.ob_target:UnregisterZone(zoneId) end
    for _, ped in pairs(peds) do if DoesEntityExist(ped) then DeletePed(ped) end end
    for _, blip in pairs(blips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
end)
