local replicatedBurstTyres = {}
local nextCollisionBurstAt = 0

local wheelBones = {
    { name = 'wheel_lf', index = 0 },
    { name = 'wheel_rf', index = 1 },
    { name = 'wheel_lm1', index = 2 },
    { name = 'wheel_rm1', index = 3 },
    { name = 'wheel_lr', index = 4 },
    { name = 'wheel_rr', index = 5 },
    { name = 'wheel_lm2', index = 45 },
    { name = 'wheel_rm2', index = 47 },
}

-- Materiais duros de parede e madeira. Metais, vidros, plasticos, placas e
-- postes metalicos ficam deliberadamente fora desta lista.
local punctureMaterials = {
    [0x46CA81E8] = true, -- Concrete
    [0xBF59B491] = true, -- ConcreteDusty
    [0xC72165D6] = true, -- BreezeBlock
    [0xCDEB5023] = true, -- Rock
    [0xF8902AC8] = true, -- RockMossy
    [0x2D9C1E0D] = true, -- Stone
    [0x61B1F936] = true, -- Brick
    [0x73EF7697] = true, -- Marble
    [0x23500534] = true, -- SandstoneSolid
    [0x7209440E] = true, -- SandstoneBrittle
    [0xDDC7963F] = true, -- PlasterSolid
    [0xF0FC7AFE] = true, -- PlasterBrittle
    [0x8DD4EBB9] = true, -- TreeBark
    [0xE82A6F1C] = true, -- WoodSolidSmall
    [0x2114B37D] = true, -- WoodSolidMedium
    [0x309F8BB7] = true, -- WoodSolidLarge
    [0x0789C7AB] = true, -- WoodSolidPolished
    [0x76D9AC2F] = true, -- WoodHollowSmall
    [0xEA3746BD] = true, -- WoodHollowMedium
    [0xC8D738E7] = true, -- WoodHollowLarge
    [0x981E5200] = true, -- WoodHighDensity
}

local function burst(vehicle, wheel)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    wheel = math.floor(tonumber(wheel) or -1)
    if wheel < 0 then return false end
    if not IsVehicleTyreBurst(vehicle, wheel, false) then
        SetVehicleTyreBurst(vehicle, wheel, true, 1000.0)
        local netId = NetworkGetNetworkIdFromEntity(vehicle)
        if netId > 0 then TriggerServerEvent('ob_pneu:server:setBurstState', netId, wheel, true) end
        return true
    end
    return false
end

exports('BurstTyre', burst)
exports('RepairTyre', function(vehicle, wheel)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    wheel = math.floor(tonumber(wheel) or -1)
    if wheel < 0 then return false end
    SetVehicleTyreFixed(vehicle, wheel)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId > 0 then TriggerServerEvent('ob_pneu:server:setBurstState', netId, wheel, false) end
    return true
end)

RegisterNetEvent('ob_pneu:client:syncBurstState', function(netId, state)
    netId = math.floor(tonumber(netId) or 0)
    local vehicle = netId > 0 and NetworkGetEntityFromNetworkId(netId) or 0
    if not DoesEntityExist(vehicle) then return end
    state = type(state) == 'table' and state or {}
    local previous = replicatedBurstTyres[netId] or {}
    for wheel in pairs(previous) do
        if state[tostring(wheel)] ~= true then SetVehicleTyreFixed(vehicle, tonumber(wheel)) end
    end
    for wheel, isBurst in pairs(state) do
        local index = tonumber(wheel)
        if isBurst == true and index then SetVehicleTyreBurst(vehicle, index, true, 1000.0) end
    end
    replicatedBurstTyres[netId] = state
end)

CreateThread(function()
    Wait(1200)
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        local netId = NetworkGetNetworkIdFromEntity(vehicle)
        local state = Entity(vehicle).state['ob:pneu_burst']
        if netId > 0 and type(state) == 'table' then TriggerEvent('ob_pneu:client:syncBurstState', netId, state) end
    end
end)

local function randomExistingWheel(vehicle)
    local available = {}
    for _, wheel in ipairs(wheelBones) do
        if GetEntityBoneIndexByName(vehicle, wheel.name) ~= -1
            and not IsVehicleTyreBurst(vehicle, wheel.index, false) then
            available[#available + 1] = wheel.index
        end
    end
    if #available == 0 then return nil end
    return available[math.random(1, #available)]
end

local function normalizeHash(value)
    value = tonumber(value) or 0
    return value < 0 and value + 4294967296 or value
end

local function collisionCounterpart(vehicle, victim, attacker)
    victim, attacker = tonumber(victim) or 0, tonumber(attacker) or 0
    if victim == vehicle then return attacker end
    if attacker == vehicle then return victim end
end

local function handleCollisionDamage(victim, attacker)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then return end

    local counterpart = collisionCounterpart(vehicle, victim, attacker)
    if counterpart == nil then return end
    local counterpartType = counterpart ~= 0 and GetEntityType(counterpart) or 0
    if counterpartType ~= 0 and counterpartType ~= 3 then return end

    local material = normalizeHash(GetLastMaterialHitByEntity(vehicle))
    if not punctureMaterials[material] then return end
    local normal = GetCollisionNormalOfLastHitForEntity(vehicle)
    -- Parede/poste produz normal predominantemente lateral. Isso impede que o
    -- corpo do carro tocando o chao seja tratado como impacto perfurante.
    if normal and math.abs(tonumber(normal.z) or 0.0) > 0.60 then return end

    -- Mantem a regra anterior: apenas impactos acima de 28 m/s e 16% de
    -- chance. O cooldown evita varios eventos para a mesma colisao.
    if GetEntitySpeed(vehicle) <= 28.0 then return end
    local now = GetGameTimer()
    if now < nextCollisionBurstAt then return end
    nextCollisionBurstAt = now + 1500

    if math.random(1, 100) > 16 then return end
    local wheel = randomExistingWheel(vehicle)
    if wheel then burst(vehicle, wheel) end
end

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or type(args) ~= 'table' then return end
    handleCollisionDamage(args[1], args[2])
end)

-- O evento normalizado pela Cfx funciona como apoio entre builds do jogo e
-- passa as mesmas entidades na ordem vitima/agressor. O cooldown deduplica os
-- casos em que os dois eventos sao emitidos para o mesmo impacto.
AddEventHandler('entityDamaged', function(victim, attacker)
    handleCollisionDamage(victim, attacker)
end)
