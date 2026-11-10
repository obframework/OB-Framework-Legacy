local lastUse = {}

local function notify(playerSource, message)
    TriggerClientEvent('ob_core:client:tuningNotice', playerSource, message)
end

local function allowed(playerSource, config)
    if ORCore.IsAdmin(playerSource) then return true end
    if ORCore.HasPermission(playerSource, config.permission or 'or.admin') then return true end
    -- Integracao opcional: remover ob_admin nao remove os comandos nem o ACE.
    if GetResourceState('ob_admin') == 'started' then
        local ok, permitted = pcall(function()
            return exports.ob_admin:HasPermission(playerSource, config.adminPermission or 'vehicle.fix')
        end)
        return ok and permitted == true
    end
    return false
end

local function tune(playerSource, visual)
    playerSource = tonumber(playerSource)
    if not playerSource or playerSource <= 0 then
        print('[ob_core] Use tuning/tuning2 dentro do jogo, dirigindo um veiculo.')
        return
    end
    local config = ORCoreConfig.VehicleTuning or {}
    if config.enabled == false then return notify(playerSource, 'Comandos de tuning desativados.') end
    if not allowed(playerSource, config) then return notify(playerSource, 'Sem permissao para usar este comando.') end

    local now = GetGameTimer()
    if lastUse[playerSource] and now - lastUse[playerSource] < (tonumber(config.cooldownMs) or 2000) then return end
    local ped = GetPlayerPed(playerSource)
    local vehicle = ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then
        return notify(playerSource, 'Voce precisa estar dirigindo o veiculo.')
    end
    lastUse[playerSource] = now
    TriggerClientEvent('ob_core:client:applyTuning', playerSource, NetworkGetNetworkIdFromEntity(vehicle), visual == true)
end

RegisterCommand('tuning', function(playerSource) tune(playerSource, false) end, false)
RegisterCommand('tuning2', function(playerSource) tune(playerSource, true) end, false)

AddEventHandler('playerDropped', function()
    lastUse[tonumber(source)] = nil
end)
