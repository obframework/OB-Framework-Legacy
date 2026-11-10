local function validSource(playerSource)
    playerSource = tonumber(playerSource)
    return playerSource and playerSource > 0 and GetPlayerName(playerSource) and playerSource or nil
end

local validWheels = { [0]=true,[1]=true,[2]=true,[3]=true,[4]=true,[5]=true,[45]=true,[47]=true }

RegisterNetEvent('ob_pneu:server:setBurstState', function(netId, wheel, burst)
    local playerSource = validSource(source)
    netId, wheel = math.floor(tonumber(netId) or 0), math.floor(tonumber(wheel) or -1)
    local vehicle = netId > 0 and NetworkGetEntityFromNetworkId(netId) or 0
    local ped = playerSource and GetPlayerPed(playerSource) or 0
    if not playerSource or not validWheels[wheel] or not DoesEntityExist(vehicle) or ped <= 0 or #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > 14.0 then return end
    if not OR.Security.rateLimit(playerSource, 'tyre:burst_state', 6, 10000) then return end
    -- Estouro por colisao nasce apenas no cliente do motorista. Reparos ainda
    -- podem vir do mecanico proximo, mas um jogador a pe nao pode estourar o
    -- pneu de terceiros disparando o evento manualmente.
    if burst == true and GetPedInVehicleSeat(vehicle, -1) ~= ped then return end

    local current = Entity(vehicle).state['ob:pneu_burst']
    local snapshot = {}
    for index, state in pairs(type(current) == 'table' and current or {}) do snapshot[index] = state end
    snapshot[tostring(wheel)] = burst == true and true or nil
    Entity(vehicle).state:set('ob:pneu_burst', next(snapshot) and snapshot or nil, true)
    TriggerClientEvent('ob_pneu:client:syncBurstState', -1, netId, snapshot)
end)
