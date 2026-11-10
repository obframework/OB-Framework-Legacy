local resource = GetCurrentResourceName()
local busy = false
local offerOption = resource .. ':sell'
local searchOption = resource .. ':search'
local salesPed
local recoveryPed
local pendingTheftUntil = 0

local function notify(message, kind) OR.Notify(message, kind or 'info') end
local function theftState(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) or not NetworkGetEntityIsNetworked(ped) then return nil end
    local ok, value = pcall(function() return Entity(ped).state.ob_drugselling_theft end)
    return ok and value or nil
end
local function servicePed(ped)
    if GetResourceState('ob_jobcenter') == 'started' then
        local ok, result = pcall(function() return exports.ob_jobcenter:IsServicePed(ped) end)
        if ok and result == true then return true end
    end
    if GetResourceState('ob_crafting') == 'started' then
        local ok, result = pcall(function() return exports.ob_crafting:IsServicePed(ped) end)
        if ok and result == true then return true end
    end
    if GetResourceState('ob_inventory') == 'started' then
        local ok, result = pcall(function() return exports.ob_inventory:IsServicePed(ped) end)
        if ok and result == true then return true end
    end
    if GetResourceState('ob_bank') == 'started' then
        local ok, result = pcall(function() return exports.ob_bank:IsServicePed(ped) end)
        if ok and result == true then return true end
    end
    if GetResourceState('ob_moneywash') == 'started' then
        local ok, result = pcall(function() return exports.ob_moneywash:IsServicePed(ped) end)
        if ok and result == true then return true end
    end
    return false
end
local function usablePed(ped)
    return ped and ped ~= 0 and DoesEntityExist(ped) and IsEntityAPed(ped) and not IsPedAPlayer(ped)
        and not IsEntityPositionFrozen(ped)
        and not servicePed(ped)
        and not IsPedDeadOrDying(ped, true) and not IsPedInAnyVehicle(ped, false)
        and not DrugSelling.blockedPedTypes[GetPedType(ped)] and not DrugSelling.blockedModels[GetEntityModel(ped)]
        and not theftState(ped)
end
local function deadStolenPed(ped)
    return ped and ped ~= 0 and DoesEntityExist(ped) and IsEntityAPed(ped) and not IsPedAPlayer(ped)
        and IsPedDeadOrDying(ped, true) and theftState(ped) ~= nil
end
local function networkPed(ped)
    if not NetworkGetEntityIsNetworked(ped) then
        NetworkRequestControlOfEntity(ped)
        local deadline = GetGameTimer() + 1000
        while not NetworkHasControlOfEntity(ped) and GetGameTimer() < deadline do Wait(0); NetworkRequestControlOfEntity(ped) end
        NetworkRegisterEntityAsNetworked(ped)
    end
    local netId = NetworkGetNetworkIdFromEntity(ped)
    if netId and netId > 0 then SetNetworkIdCanMigrate(netId, true); Wait(180); return netId end
end

local function holdPedForExchange(ped)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)
    ClearPedTasks(ped)
    TaskTurnPedToFaceEntity(PlayerPedId(), ped, 750)
    TaskTurnPedToFaceEntity(ped, PlayerPedId(), 750)
    Wait(700)
    FreezeEntityPosition(ped, true)
end

local function releasePed(ped)
    if not ped or not DoesEntityExist(ped) then return end
    FreezeEntityPosition(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, false)
    SetPedKeepTask(ped, false)
    TaskWanderStandard(ped, 10.0, 10)
end

local function preparationAnimation(ped)
    local dictionary = 'mp_arresting'
    local playerPed = PlayerPedId()
    RequestAnimDict(dictionary)
    local deadline = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dictionary) and GetGameTimer() < deadline do Wait(0) end
    if HasAnimDictLoaded(dictionary) then
        TaskPlayAnim(ped, dictionary, 'idle', 4.0, -4.0, 5500, 49, 0, false, false, false)
    end
    FreezeEntityPosition(playerPed, true)
    local completed = OR.Progress.Run({
        label = 'Negociando...', duration = 5000, canCancel = false,
        animation = { dict = dictionary, clip = 'idle', flag = 49 },
    })
    FreezeEntityPosition(playerPed, false)
    return completed
end

local function exchangeAnimation(ped)
    RequestAnimDict('mp_common')
    local deadline = GetGameTimer() + 2000
    while not HasAnimDictLoaded('mp_common') and GetGameTimer() < deadline do Wait(0) end
    if HasAnimDictLoaded('mp_common') then
        TaskPlayAnim(PlayerPedId(), 'mp_common', 'givetake1_a', 4.0, -4.0, 1300, 49, 0, false, false, false)
        TaskPlayAnim(ped, 'mp_common', 'givetake1_b', 4.0, -4.0, 1300, 49, 0, false, false, false)
        Wait(1250)
    end
end

local function recoverAnimation()
    local dictionaries = {
        'amb@medic@standing@kneel@enter',
        'amb@medic@standing@kneel@base',
        'amb@medic@standing@kneel@exit',
    }
    for _, dictionary in ipairs(dictionaries) do RequestAnimDict(dictionary) end
    local deadline = GetGameTimer() + 2500
    while GetGameTimer() < deadline do
        local loaded = true
        for _, dictionary in ipairs(dictionaries) do
            if not HasAnimDictLoaded(dictionary) then loaded = false break end
        end
        if loaded then break end
        Wait(0)
    end
    if HasAnimDictLoaded(dictionaries[1]) then
        TaskPlayAnim(PlayerPedId(), dictionaries[1], 'enter', 4.0, -4.0, 1050, 0, 0, false, false, false)
        Wait(950)
    end
    local done = OR.Progress.Run({ label = 'Recuperando a mercadoria...', duration = 3500, canCancel = true,
        animation = { dict = dictionaries[2], clip = 'base', flag = 1 } })
    if HasAnimDictLoaded(dictionaries[3]) then
        TaskPlayAnim(PlayerPedId(), dictionaries[3], 'exit', 4.0, -4.0, 1200, 0, 0, false, false, false)
        Wait(1050)
    end
    return done
end

local function sellToPed(ped)
    if busy or pendingTheftUntil > GetGameTimer() or not usablePed(ped) or LocalPlayer.state['or:downed'] then return end
    busy = true
    local netId = networkPed(ped)
    if not netId then notify('Nao foi possivel abordar esta pessoa.', 'error'); busy = false return end
    holdPedForExchange(ped)
    local offer, message = OR.Callback.await('offer', netId)
    if not offer then
        releasePed(ped)
        notify(message or 'Nao foi possivel fazer a negociacao.', 'error')
        busy = false
        return
    end
    if offer.refused then
        releasePed(ped)
        busy = false
        return
    end
    if not preparationAnimation(ped) then
        OR.Callback.await('cancelOffer', offer.token)
        releasePed(ped)
        busy = false
        return
    end
    exchangeAnimation(ped)
    local ok, result = OR.Callback.await('accept', offer.token, netId)
    if not ok then
        releasePed(ped)
        notify(result or 'A negociacao falhou.', 'error')
        busy = false
        return
    end
    if result.stolen then
        pendingTheftUntil = GetGameTimer() + (math.max(1, tonumber(result.recoverySeconds) or DrugSelling.theftRecoverySeconds) * 1000)
        SetEntityAsMissionEntity(ped, true, false)
        FreezeEntityPosition(ped, false)
        SetBlockingOfNonTemporaryEvents(ped, false)
        SetPedKeepTask(ped, true)
        TaskSmartFleePed(ped, PlayerPedId(), 350.0, -1, false, false)
        notify(result.message, 'error')
    else
        releasePed(ped)
    end
    busy = false
end

local function searchPed(ped)
    if busy or not deadStolenPed(ped) then return end
    busy = true
    local netId = NetworkGetNetworkIdFromEntity(ped)
    local theftToken = theftState(ped)
    local done = recoverAnimation()
    if done then
        local ok, message = OR.Callback.await('recover', netId, theftToken)
        if ok then pendingTheftUntil = 0 end
        notify(message or (ok and 'Mercadoria recuperada.' or 'Nada foi encontrado.'), ok and 'success' or 'error')
    end
    busy = false
end

RegisterNetEvent(resource .. ':client:sell', function(ped) sellToPed(ped) end)
RegisterNetEvent(resource .. ':client:search', function(ped) searchPed(ped) end)

local function registerTargets()
    if GetResourceState('ob_target') ~= 'started' then return end
    exports.ob_target:RemoveEntityOption(offerOption)
    exports.ob_target:RemoveEntityOption(searchOption)
    salesPed = nil
    recoveryPed = nil
end

local function setRecoveryPed(ped)
    if ped == recoveryPed and (not ped or DoesEntityExist(ped)) then return end
    if GetResourceState('ob_target') == 'started' then exports.ob_target:RemoveEntityOption(searchOption) end
    recoveryPed = ped
    if not ped or GetResourceState('ob_target') ~= 'started' then return end
    local registered, registerError = exports.ob_target:RegisterEntity(searchOption, ped, {
        label = 'Recuperar mercadoria', icon = 'R', distance = DrugSelling.interactDistance,
        event = resource .. ':client:search',
    })
    if not registered then
        recoveryPed = nil
        print('[ob_drugselling] Falha ao registrar corpo no target: ' .. tostring(registerError))
    end
end

local function setSalesPed(ped)
    if ped == salesPed and (not ped or DoesEntityExist(ped)) then return end
    if GetResourceState('ob_target') == 'started' then exports.ob_target:RemoveEntityOption(offerOption) end
    salesPed = ped
    if not ped or GetResourceState('ob_target') ~= 'started' then return end
    local registered, registerError = exports.ob_target:RegisterEntity(offerOption, ped, {
        label = 'Oferecer mercadoria', icon = 'D', distance = DrugSelling.interactDistance,
        event = resource .. ':client:sell',
    })
    if not registered then
        salesPed = nil
        print('[ob_drugselling] Falha ao registrar pedestre no target: ' .. tostring(registerError))
    end
end

CreateThread(function()
    while true do
        Wait(500)
        local selected, closest = nil, 5.0
        local body, bodyDistance = nil, 5.0
        if GetResourceState('ob_target') == 'started' and not busy
            and LocalPlayer.state['or:loaded'] == true and LocalPlayer.state['or:downed'] ~= true then
            local playerPed, coords = PlayerPedId(), GetEntityCoords(PlayerPedId())
            for _, ped in ipairs(GetGamePool('CPed')) do
                if ped ~= playerPed and deadStolenPed(ped) then
                    local distance = #(coords - GetEntityCoords(ped))
                    if distance < bodyDistance then body, bodyDistance = ped, distance end
                elseif pendingTheftUntil <= GetGameTimer() and ped ~= playerPed then
                    local distance = #(coords - GetEntityCoords(ped))
                    if distance < closest and usablePed(ped) then selected, closest = ped, distance end
                end
            end
        end
        setSalesPed(selected)
        setRecoveryPed(body)
    end
end)

AddEventHandler('ob_target:client:ready', registerTargets)
AddEventHandler('onClientResourceStart', function(name) if name == resource or name == 'ob_target' then Wait(500); registerTargets() end end)
AddEventHandler('onResourceStop', function(name)
    if name ~= resource then return end
    FreezeEntityPosition(PlayerPedId(), false)
    if salesPed and DoesEntityExist(salesPed) then FreezeEntityPosition(salesPed, false) end
    if recoveryPed and DoesEntityExist(recoveryPed) then FreezeEntityPosition(recoveryPed, false) end
    if GetResourceState('ob_target') == 'started' then
        exports.ob_target:RemoveEntityOption(offerOption); exports.ob_target:RemoveEntityOption(searchOption)
    end
    salesPed = nil
    recoveryPed = nil
end)
