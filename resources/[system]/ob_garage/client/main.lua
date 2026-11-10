local currentGarage, open, spawned, trackBlip = nil, false, {}, nil
local garageBlips, registeredGarageIds = {}, {}
local adminOpen, captureActive = false, false

local function notify(text, kind) OR.Notify(text, kind or 'info') end
local function enableVehicleDamage(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    SetEntityInvincible(vehicle, false)
    SetEntityCanBeDamaged(vehicle, true)
    SetVehicleCanBeVisiblyDamaged(vehicle, true)
    SetVehicleEngineCanDegrade(vehicle, true)
end
local function requestModel(model)
    local hash = joaat(model); if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return nil end
    RequestModel(hash); local timeout = GetGameTimer() + 8000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function roundDamageNumber(value)
    return math.floor((tonumber(value) or 0.0) * 1000.0) / 1000.0
end

local function deformationOffsets(vehicle)
    local minimum, maximum = GetModelDimensions(GetEntityModel(vehicle))
    local halfX = roundDamageNumber((maximum.x - minimum.x) * 0.5)
    local halfY = roundDamageNumber((maximum.y - minimum.y) * 0.5)
    local halfZ = roundDamageNumber((maximum.z - minimum.z) * 0.5)
    local offsets = {}

    -- Uma grade densa acompanha melhor para-choques, capô, laterais e teto de
    -- carros de tamanhos diferentes. A versão anterior tinha apenas 30 pontos
    -- e podia passar entre os amassados de veículos pequenos.
    local xSteps = { -1.0, -0.5, 0.0, 0.5, 1.0 }
    local ySteps = { 1.0, 0.75, 0.5, 0.25, 0.0, -0.25, -0.5, -0.75, -1.0 }
    local zSteps = { -1.0, 0.0, 1.0 }
    for _, yStep in ipairs(ySteps) do
        for _, xStep in ipairs(xSteps) do
            for _, zStep in ipairs(zSteps) do
                offsets[#offsets + 1] = {
                    x = roundDamageNumber(halfX * xStep),
                    y = roundDamageNumber(halfY * yStep),
                    z = roundDamageNumber(halfZ * zStep),
                }
            end
        end
    end
    return offsets
end

local function captureVisualDamage(vehicle)
    local damage = { version = 3, deformation = {}, windows = {}, doors = {} }

    for _, offset in ipairs(deformationOffsets(vehicle)) do
        local deformation = GetVehicleDeformationAtPos(vehicle, offset.x, offset.y, offset.z)
        local amount = roundDamageNumber(#deformation)
        if amount >= 0.01 then
            damage.deformation[#damage.deformation + 1] = {
                x = offset.x, y = offset.y, z = offset.z, damage = amount,
            }
        end
    end

    for window = 0, 7 do
        -- Janela abaixada tambem pode ser reportada como nao intacta. Levantar
        -- primeiro diferencia isso de um vidro realmente quebrado.
        RollUpWindow(vehicle, window)
        if not IsVehicleWindowIntact(vehicle, window) then
            damage.windows[tostring(window)] = true
        end
    end
    for door = 0, 5 do
        if GetIsDoorValid(vehicle, door) and IsVehicleDoorDamaged(vehicle, door) then
            damage.doors[tostring(door)] = true
        end
    end

    if not next(damage.deformation) and not next(damage.windows) and not next(damage.doors) then return nil end
    return damage
end

local function applyVisualDamage(vehicle, damage)
    if type(damage) ~= 'table' then return end

    local deformation = type(damage.deformation) == 'table' and damage.deformation or {}
    if next(deformation) then
        -- VehicleDeformation reference license:
        -- Copyright (c) 2021 Philipp Decker / Kiminaze.
        -- By acquiring a copy of this code snippet for the FiveM modification
        -- for Grand Theft Auto V, permission is granted to use and modify all
        -- parts, and to redistribute or sell resources created with it, as
        -- long as this license notice is included. This snippet is provided
        -- "as is" without warranty or liability for resulting damages.
        CreateThread(function()
            local minimum, maximum = GetModelDimensions(GetEntityModel(vehicle))
            local dx, dy, dz = maximum.x - minimum.x, maximum.y - minimum.y, maximum.z - minimum.z
            local damageMultiplier = math.sqrt(dx * dx + dy * dy + dz * dz) * 2.5
            local bodyHealth = GetVehicleBodyHealth(vehicle)
            local engineHealth = GetVehicleEngineHealth(vehicle)

            for _ = 1, 50 do
                if not DoesEntityExist(vehicle) then return end
                local pending = false
                for _, point in ipairs(deformation) do
                    local x = roundDamageNumber(point.x)
                    local y = roundDamageNumber(point.y)
                    local z = roundDamageNumber(point.z)
                    local target = math.max(0.0, tonumber(point.damage) or 0.0)
                    local current = #GetVehicleDeformationAtPos(vehicle, x, y, z)
                    if target >= 0.01 and current < target * 0.99 then
                        SetVehicleDamage(
                            vehicle,
                            x * 2.0, y * 2.0, z * 2.0,
                            roundDamageNumber(target * damageMultiplier),
                            1000.0,
                            true
                        )
                        pending = true
                    end
                end
                -- SetVehicleDamage também mexe na vida numérica. A garagem
                -- restaura aqui somente o formato visual que estava salvo.
                SetVehicleBodyHealth(vehicle, bodyHealth)
                SetVehicleEngineHealth(vehicle, engineHealth)
                if not pending then break end
                Wait(100)
            end
        end)
    end

    -- A primeira versao marcava janelas abaixadas ou inexistentes como
    -- quebradas. Ignoramos somente esse snapshot antigo; amassados continuam.
    if tonumber(damage.version) and tonumber(damage.version) >= 2 then
        for window, broken in pairs(type(damage.windows) == 'table' and damage.windows or {}) do
            if broken == true then RemoveVehicleWindow(vehicle, tonumber(window) or 0) end
        end
    end
    for door, broken in pairs(type(damage.doors) == 'table' and damage.doors or {}) do
        local doorIndex = tonumber(door)
        if broken == true and doorIndex and GetIsDoorValid(vehicle, doorIndex) then
            SetVehicleDoorBroken(vehicle, doorIndex, false)
        end
    end
end

local function props(vehicle)
    SetVehicleModKit(vehicle, 0)
    local primary, secondary = GetVehicleColours(vehicle)
    local pearlescent, wheel = GetVehicleExtraColours(vehicle)
    local customPrimaryR, customPrimaryG, customPrimaryB = GetVehicleCustomPrimaryColour(vehicle)
    local customSecondaryR, customSecondaryG, customSecondaryB = GetVehicleCustomSecondaryColour(vehicle)
    local paintType1, paintColor1, paintPearlescent1 = GetVehicleModColor_1(vehicle)
    local paintType2, paintColor2 = GetVehicleModColor_2(vehicle)
    local neonR, neonG, neonB = GetVehicleNeonLightsColour(vehicle)
    local data = {
        primary = primary,
        secondary = secondary,
        primaryCustom = GetIsVehiclePrimaryColourCustom(vehicle) == true,
        secondaryCustom = GetIsVehicleSecondaryColourCustom(vehicle) == true,
        primaryCustomColor = { customPrimaryR, customPrimaryG, customPrimaryB },
        secondaryCustomColor = { customSecondaryR, customSecondaryG, customSecondaryB },
        paintType1 = paintType1,
        paintColor1 = paintColor1,
        paintPearlescent1 = paintPearlescent1,
        paintType2 = paintType2,
        paintColor2 = paintColor2,
        pearlescent = pearlescent,
        wheel = wheel,
        livery = GetVehicleLivery(vehicle),
        wheelType = GetVehicleWheelType(vehicle),
        windowTint = GetVehicleWindowTint(vehicle),
        mods = {},
        toggles = {},
        neons = {},
        neonColor = { neonR, neonG, neonB },
        xenonColor = GetVehicleXenonLightsColor(vehicle),
        extras = {},
        visualDamage = captureVisualDamage(vehicle),
    }

    local smokeR, smokeG, smokeB = GetVehicleTyreSmokeColor(vehicle)
    data.tyreSmokeColor = { smokeR, smokeG, smokeB }
    for extra = 0, 20 do
        if DoesExtraExist(vehicle, extra) then
            data.extras[tostring(extra)] = IsVehicleExtraTurnedOn(vehicle, extra) == true
        end
    end

    -- Guarda todos os slots nativos, nao apenas os que a oficina atual exibe.
    -- Assim uma futura categoria de tuning tambem sobrevive a garagem.
    for index = 0, 49 do
        if GetNumVehicleMods(vehicle, index) > 0 then
            data.mods[tostring(index)] = {
                value = GetVehicleMod(vehicle, index),
                variation = GetVehicleModVariation(vehicle, index) == true,
            }
        end
    end

    for _, index in ipairs({ 17, 18, 19, 20, 21, 22 }) do
        data.toggles[tostring(index)] = IsToggleModOn(vehicle, index) == true
    end
    for side = 0, 3 do
        data.neons[tostring(side)] = IsVehicleNeonLightEnabled(vehicle, side) == true
    end

    -- Em alguns artifacts os getters nativos devolvem false logo depois da
    -- oficina aplicar cor customizada/neon/xenon. O servidor replica os flags
    -- confirmados pela oficina para que um salvamento posterior nao os apague.
    local visualFlags = Entity(vehicle).state['ob:visual_flags']
    if type(visualFlags) == 'table' then
        if type(visualFlags.primaryCustom) == 'boolean' then
            data.primaryCustom = visualFlags.primaryCustom
        end
        if type(visualFlags.secondaryCustom) == 'boolean' then
            data.secondaryCustom = visualFlags.secondaryCustom
        end
        if type(visualFlags.neonEnabled) == 'boolean' then
            for side = 0, 3 do data.neons[tostring(side)] = visualFlags.neonEnabled end
        end
        if type(visualFlags.xenonEnabled) == 'boolean' then
            data.toggles['22'] = visualFlags.xenonEnabled
        end
        if type(visualFlags.turboEnabled) == 'boolean' then
            data.toggles['18'] = visualFlags.turboEnabled
        end
    end
    -- Pneus furados por tiro nao recebem o marcador "removido". A oficina
    -- devolve os tres estados no cliente dono, antes de a entidade sumir.
    if GetResourceState('ob_mecanico') == 'started' then
        local ok, tyreState = pcall(function()
            return exports.ob_mecanico:GetVehicleTyreState(vehicle)
        end)
        if ok and type(tyreState) == 'table' then
            if type(tyreState.removedTyres) == 'table' and next(tyreState.removedTyres) then
                data.removedTyres = tyreState.removedTyres
            end
            if type(tyreState.tyreTypes) == 'table' and next(tyreState.tyreTypes) then
                data.tyreTypes = tyreState.tyreTypes
            end
            if type(tyreState.burstTyres) == 'table' and next(tyreState.burstTyres) then
                data.burstTyres = tyreState.burstTyres
            end
        end
    end

    return data
end

-- Usado apenas por ferramentas administrativas antes de remover um veiculo
-- proprio fora da vaga. Assim o banco recebe o mesmo conjunto de tuning que
-- seria salvo pela garagem normal.
exports('CaptureProperties', props)
local function apply(vehicle, p)
    if type(p) ~= 'table' then return end
    SetVehicleModKit(vehicle, 0)
    if p.wheelType ~= nil then SetVehicleWheelType(vehicle, tonumber(p.wheelType) or 0) end
    for index, saved in pairs(p.mods or {}) do
        local modIndex = tonumber(index)
        if modIndex then
            if type(saved) == 'table' then
                SetVehicleMod(vehicle, modIndex, tonumber(saved.value) or -1, saved.variation == true)
            else
                -- Compatibilidade com propriedades gravadas antes desta versao.
                SetVehicleMod(vehicle, modIndex, tonumber(saved) or -1, false)
            end
        end
    end
    for index, enabled in pairs(p.toggles or {}) do
        local modIndex = tonumber(index)
        if modIndex == 18 then
            -- O Enhanced pode ignorar a primeira aplicacao enquanto termina de
            -- carregar o mod kit. Reaplicar por alguns frames estabiliza o turbo.
            for _ = 1, 4 do
                ToggleVehicleMod(vehicle, modIndex, enabled == true)
                Wait(0)
            end
        elseif modIndex then
            ToggleVehicleMod(vehicle, modIndex, enabled == true)
        end
    end
    if p.livery ~= nil and tonumber(p.livery) and tonumber(p.livery) >= 0 then SetVehicleLivery(vehicle, tonumber(p.livery)) end
    for extra, enabled in pairs(type(p.extras) == 'table' and p.extras or {}) do
        local extraId = tonumber(extra)
        if extraId and DoesExtraExist(vehicle, extraId) then
            SetVehicleExtra(vehicle, extraId, enabled == true and 0 or 1)
        end
    end

    -- Aplicar o estado visual por ultimo. Alguns mods de carroceria/rodas
    -- redefinem pintura ou iluminacao quando sao instalados.
    if p.primary ~= nil or p.secondary ~= nil then
        local primary = tonumber(p.primary) or 0
        local secondary = tonumber(p.secondary) or primary
        SetVehicleColours(vehicle, primary, secondary)
        ClearVehicleCustomPrimaryColour(vehicle)
        ClearVehicleCustomSecondaryColour(vehicle)
        if p.paintType1 ~= nil then
            SetVehicleModColor_1(vehicle, tonumber(p.paintType1) or 0,
                tonumber(p.paintColor1) or primary,
                tonumber(p.paintPearlescent1) or tonumber(p.pearlescent) or 0)
        end
        if p.paintType2 ~= nil then
            SetVehicleModColor_2(vehicle, tonumber(p.paintType2) or 0,
                tonumber(p.paintColor2) or secondary)
        end
        local primaryCustom = p.primaryCustomColor
        if p.primaryCustom == true and type(primaryCustom) == 'table' then
            SetVehicleCustomPrimaryColour(vehicle,
                tonumber(primaryCustom[1] or primaryCustom['1']) or 0,
                tonumber(primaryCustom[2] or primaryCustom['2']) or 0,
                tonumber(primaryCustom[3] or primaryCustom['3']) or 0)
        end
        local secondaryCustom = p.secondaryCustomColor
        if p.secondaryCustom == true and type(secondaryCustom) == 'table' then
            SetVehicleCustomSecondaryColour(vehicle,
                tonumber(secondaryCustom[1] or secondaryCustom['1']) or 0,
                tonumber(secondaryCustom[2] or secondaryCustom['2']) or 0,
                tonumber(secondaryCustom[3] or secondaryCustom['3']) or 0)
        end
    end
    if p.pearlescent ~= nil then
        SetVehicleExtraColours(vehicle, tonumber(p.pearlescent) or 0, tonumber(p.wheel) or 0)
    end
    if p.windowTint ~= nil then SetVehicleWindowTint(vehicle, tonumber(p.windowTint) or -1) end
    for side = 0, 3 do
        local enabled = p.neons and (p.neons[side] == true or p.neons[tostring(side)] == true)
        SetVehicleNeonLightEnabled(vehicle, side, enabled == true)
    end
    local neon = p.neonColor
    if type(neon) == 'table' then
        SetVehicleNeonLightsColour(vehicle,
            tonumber(neon[1] or neon['1']) or 255,
            tonumber(neon[2] or neon['2']) or 255,
            tonumber(neon[3] or neon['3']) or 255)
    end
    if p.xenonColor ~= nil then
        SetVehicleXenonLightsColor(vehicle, tonumber(p.xenonColor) or -1)
    end
    local smoke = p.tyreSmokeColor
    if type(smoke) == 'table' then
        SetVehicleTyreSmokeColor(vehicle,
            tonumber(smoke[1] or smoke['1']) or 255,
            tonumber(smoke[2] or smoke['2']) or 255,
            tonumber(smoke[3] or smoke['3']) or 255)
    end
end

-- Permite que oficinas restaurem uma previa cancelada com o mesmo conjunto
-- completo de propriedades usado ao retirar o veiculo da garagem.
exports('ApplyProperties', apply)

local function isSpawnPointClear(spawn, radius)
    local point = vector3(spawn.x, spawn.y, spawn.z)
    radius = tonumber(radius) or 1.75
    -- IsAnyVehicleNearPoint com 3 metros pegava carros passando na rua e
    -- bloqueava a retirada mesmo sem haver nada dentro da vaga.
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) and #(GetEntityCoords(vehicle) - point) <= radius then
            return false
        end
    end
    return true
end

local function availableSpawn(place)
    local spawns = type(place and place.spawns) == 'table' and place.spawns or {}
    if #spawns == 0 and place and place.spawn then spawns = { place.spawn } end
    for index, point in ipairs(spawns) do
        if isSpawnPointClear(point, place.spawnClearRadius) then return index, point end
    end
end

local function applyLock(vehicle, locked)
    if not DoesEntityExist(vehicle) then return end
    SetVehicleDoorsLocked(vehicle, locked and 2 or 1)
end


local function closestVehicle(range)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return GetVehiclePedIsIn(ped, false) end
    local coords = GetEntityCoords(ped)
    local vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, range or 5.0, 0, 71)
    return vehicle ~= 0 and vehicle or nil
end


local function trackVehicle(coords)
    if trackBlip and DoesBlipExist(trackBlip) then RemoveBlip(trackBlip) end
    trackBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(trackBlip, 225)
    SetBlipColour(trackBlip, 3)
    SetBlipScale(trackBlip, 0.9)
    SetBlipRoute(trackBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Veiculo rastreado')
    EndTextCommandSetBlipName(trackBlip)
    OR.Notify('Localizacao do veiculo exibida por 15 segundos.', 'success')
    CreateThread(function()
        local thisBlip = trackBlip
        Wait(15000)
        if thisBlip and DoesBlipExist(thisBlip) then RemoveBlip(thisBlip) end
        if trackBlip == thisBlip then trackBlip = nil end
    end)
end

local function refresh()
    local ok, vehicles = OR.Callback.await('ob_garage:server:list', currentGarage)
    SendNUIMessage({ action = 'vehicles', vehicles = ok and vehicles or {} })
    if not ok then notify(vehicles or 'Falha ao carregar veiculos.', 'error') end
    return ok == true
end
local function close()
    open = false; adminOpen = false; captureActive = false
    OR.Help.Hide()
    SetNuiFocus(false, false); SendNUIMessage({ action = 'close' })
end
local function openGarage(id)
    if open then return end
    local place = GarageConfig.garages[id]
    if not place then return notify('Garagem indisponivel.', 'error') end
    currentGarage = id
    local ok, vehicles = OR.Callback.await('ob_garage:server:list', currentGarage)
    if not ok then return notify(vehicles or 'Nao foi possivel abrir esta garagem.', 'error') end
    open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', title = place.label, imageConfig = GarageConfig.Images })
    SendNUIMessage({ action = 'vehicles', vehicles = vehicles or {} })
end
local function storeVehicle(nearby)
    local place, ped = GarageConfig.garages[currentGarage], PlayerPedId()
    if not place then return notify('Garagem indisponivel.', 'error') end
    local storePoint = place.storeCoords or place.coords
    local veh
    if nearby then
        veh = GetClosestVehicle(storePoint.x, storePoint.y, storePoint.z, place.storeDistance, 0, 71)
    else
        veh = GetVehiclePedIsIn(ped, false)
        if veh == 0 then veh = GetVehiclePedIsIn(ped, true) end
    end
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        return notify(nearby and 'Traga seu veiculo para a vaga.' or 'Entre no seu veiculo antes de guardar.', 'error')
    end
    local driver = GetPedInVehicleSeat(veh, -1)
    if driver ~= 0 and driver ~= ped then return notify('O veiculo esta sendo dirigido por outra pessoa.', 'error') end
    if #(GetEntityCoords(veh) - storePoint) > (tonumber(place.storeDistance) or 16.0) then
        return notify('Leve seu veiculo ate o ponto de guardar.', 'error')
    end
    TriggerServerEvent('ob_garage:server:store', currentGarage, NetworkGetNetworkIdFromEntity(veh), { fuel = GetVehicleFuelLevel(veh), body = GetVehicleBodyHealth(veh), engine = GetVehicleEngineHealth(veh) }, props(veh))
end

local function createBlip(id, place)
    local data = place.blip
    if not data then return end
    local blip = AddBlipForCoord(place.coords.x, place.coords.y, place.coords.z)
    SetBlipSprite(blip, data.sprite or 357)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, data.scale or 0.8)
    SetBlipColour(blip, data.color or 3)
    -- Mostra somente quando o jogador esta proximo, inclusive no minimapa.
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    -- Legenda independente do nome de identificacao usado nos paineis.
    local label = type(data.label) == 'string' and data.label:match('^%s*(.-)%s*$') or ''
    AddTextComponentString(label ~= '' and label or 'Garagem')
    EndTextCommandSetBlipName(blip)
    garageBlips[id] = blip
end

local function clearGarageWorld()
    if GetResourceState('ob_target') == 'started' then
        for id in pairs(registeredGarageIds) do
            exports.ob_target:UnregisterZone('ob_garage_open_' .. id)
            exports.ob_target:UnregisterZone('ob_garage_store_' .. id)
        end
    end
    registeredGarageIds = {}
    for id, blip in pairs(garageBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
        garageBlips[id] = nil
    end
end

local function registerGarageTargets()
    if GetResourceState('ob_target') ~= 'started' then return end
    for id, place in pairs(GarageConfig.garages) do
        if registeredGarageIds[id] then
            exports.ob_target:UnregisterZone('ob_garage_open_' .. id)
            exports.ob_target:UnregisterZone('ob_garage_store_' .. id)
        end
        exports.ob_target:RegisterBoxZone('ob_garage_open_' .. id, {
            coords = place.coords, size = place.size, rotation = 0.0,
            option = { icon = 'fa-solid fa-warehouse', label = 'Abrir garagem', action = function() openGarage(id) end }
        })
        exports.ob_target:RegisterBoxZone('ob_garage_store_' .. id, {
            coords = place.storeCoords or place.coords, size = place.storeSize or place.size, rotation = 0.0,
            option = { icon = 'fa-solid fa-square-parking', label = 'Guardar meu veiculo', action = function()
                currentGarage = id
                storeVehicle(false)
            end }
        })
        registeredGarageIds[id] = true
    end
end


local function vector3From(raw, fallback)
    raw = raw or fallback
    if not raw or tonumber(raw.x) == nil or tonumber(raw.y) == nil or tonumber(raw.z) == nil then
        return vector3(0.0, 0.0, 0.0)
    end
    return vector3(tonumber(raw.x) or 0.0, tonumber(raw.y) or 0.0, tonumber(raw.z) or 0.0)
end

local function applyGarageDefinitions(definitions)
    clearGarageWorld()
    local nextGarages = {}
    for id, raw in pairs(type(definitions) == 'table' and definitions or {}) do
        if type(raw) == 'table' then
            local rawSpawns = type(raw.spawns) == 'table' and raw.spawns or {}
            local place = raw
            place.coords = vector3From(raw.coords)
            place.size = vector3From(raw.size, { x = 4.0, y = 4.0, z = 3.0 })
            place.storeCoords = vector3From(raw.storeCoords, raw.coords)
            place.storeSize = vector3From(raw.storeSize, { x = 7.0, y = 7.0, z = 3.0 })
            place.spawns = {}
            for _, point in ipairs(rawSpawns) do
                place.spawns[#place.spawns + 1] = vector4(
                    tonumber(point.x) or 0.0, tonumber(point.y) or 0.0,
                    tonumber(point.z) or 0.0, tonumber(point.w or point.heading) or 0.0)
            end
            place.spawn = place.spawns[1]
            if place.spawn then nextGarages[tostring(id)] = place end
        end
    end
    GarageConfig.garages = nextGarages
    for id, place in pairs(nextGarages) do createBlip(id, place) end
    if LocalPlayer.state['or:loaded'] == true then registerGarageTargets() end
end

RegisterNetEvent('ob_garage:client:syncGarages', applyGarageDefinitions)
RegisterNUICallback('close', function(_, cb) close(); cb('ok') end)
RegisterNUICallback('refresh', function(_, cb) refresh(); cb('ok') end)
RegisterNUICallback('store', function(_, cb) storeVehicle(false); cb('ok') end)
RegisterNUICallback('storeNearby', function(_, cb) storeVehicle(true); cb('ok') end)
RegisterNUICallback('take', function(data, cb)
    local place = GarageConfig.garages[currentGarage]
    local spawnIndex = place and availableSpawn(place)
    if not place or not spawnIndex then
        notify('Todas as vagas de saida estao ocupadas.', 'error')
        return cb('fail')
    end
    local ok, vehicle = OR.Callback.await('ob_garage:server:take', data.id, currentGarage, spawnIndex)
    if not ok then notify(vehicle or 'Veiculo indisponivel.', 'error'); return cb('fail') end
    local veh = OR.Entity.AwaitNetwork(vehicle.netId, 10000)
    if not veh then
        TriggerServerEvent('ob_garage:server:return', vehicle.id)
        notify('O veiculo foi criado, mas nao chegou ao seu cliente.', 'error')
        return cb('fail')
    end
    local savedBody = tonumber(vehicle.body) or 1000.0
    local savedEngine = tonumber(vehicle.engine) or 1000.0
    SetVehicleNumberPlateText(veh, vehicle.plate)
    SetVehicleFuelLevel(veh, tonumber(vehicle.fuel) or 100.0)
    SetVehicleBodyHealth(veh, savedBody)
    SetVehicleEngineHealth(veh, savedEngine)
    apply(veh, vehicle.properties)
    -- Nao use SetVehicleFixed durante o spawn: no Enhanced ele pode deixar a
    -- degradacao mecanica desativada. Um carro novo ja nasce sem deformacao.
    enableVehicleDamage(veh)
    SetVehicleOnGroundProperly(veh)
    if GetResourceState('ob_mecanico') == 'started' and vehicle.properties then
        if vehicle.properties.tyreTypes then
            exports.ob_mecanico:ApplySavedTyreTypes(veh, vehicle.properties.tyreTypes)
        end
        if vehicle.properties.burstTyres then
            exports.ob_mecanico:ApplySavedBurstTyres(veh, vehicle.properties.burstTyres)
        end
        if vehicle.properties.removedTyres then
            exports.ob_mecanico:ApplySavedTyres(veh, vehicle.properties.removedTyres)
        end
    end
    applyLock(veh, true); SetPedIntoVehicle(PlayerPedId(), veh, -1)
    local controlDeadline = GetGameTimer() + 2000
    while not NetworkHasControlOfEntity(veh) and GetGameTimer() < controlDeadline do
        NetworkRequestControlOfEntity(veh)
        Wait(0)
    end
    -- A entidade e criada pelo servidor. No Enhanced, a carroceria so aceita
    -- deformacao de forma confiavel depois que o motorista recebe o controle.
    SetVehicleBodyHealth(veh, savedBody)
    SetVehicleEngineHealth(veh, savedEngine)
    Wait(350)
    local savedVisualDamage = type(vehicle.properties) == 'table' and vehicle.properties.visualDamage or nil
    applyVisualDamage(veh, savedVisualDamage)
    spawned[vehicle.id] = veh; close(); cb('ok')
end)

RegisterNUICallback('acquire', function(data, cb)
    cb({ ok = true })
    CreateThread(function()
        local place = GarageConfig.garages[currentGarage]
        local spawnIndex
        if place and place.vehicleType == 'free' then
            spawnIndex = availableSpawn(place)
            if not spawnIndex then return notify('Todas as vagas de saida estao ocupadas.', 'error') end
        end
        local ok, result = OR.Callback.await('ob_garage:server:acquire', currentGarage, data and data.model, spawnIndex)
        if not ok then return notify(result or 'Nao foi possivel adquirir o veiculo.', 'error') end
        if type(result) == 'table' and result.temporary == true then
            local veh = OR.Entity.AwaitNetwork(result.netId, 10000)
            if not veh then
                TriggerServerEvent('ob_garage:server:releaseTemporary', result.netId)
                return notify('O veiculo foi criado, mas nao chegou ao seu cliente.', 'error')
            end
            SetVehicleNumberPlateText(veh, result.plate)
            SetVehicleFuelLevel(veh, tonumber(result.fuel) or 100.0)
            SetVehicleBodyHealth(veh, tonumber(result.body) or 1000.0)
            SetVehicleEngineHealth(veh, tonumber(result.engine) or 1000.0)
            apply(veh, result.properties)
            enableVehicleDamage(veh)
            SetVehicleOnGroundProperly(veh)
            applyLock(veh, true)
            SetPedIntoVehicle(PlayerPedId(), veh, -1)
            close()
            return notify(('%s retirado para uso temporario.'):format(result.label or 'Veiculo gratuito'), 'success')
        end
        notify(result or 'Veiculo adquirido.', 'success')
        if open then refresh() end
    end)
end)

RegisterNUICallback('payTax', function(data, cb)
    cb({ ok = true })
    CreateThread(function()
        local ok, message = OR.Callback.await('ob_garage:server:payTax', data and data.id, currentGarage)
        notify(message or (ok and 'IPVA pago.' or 'Nao foi possivel pagar o IPVA.'), ok and 'success' or 'error')
        if ok and open then refresh() end
    end)
end)

RegisterNUICallback('track', function(data, cb)
    cb({ ok = true })
    CreateThread(function()
        local ok, coords = OR.Callback.await('ob_garage:server:track', data and data.id)
        if not ok then return notify(coords or 'Nao foi possivel rastrear o veiculo.', 'error') end
        trackVehicle(coords)
    end)
end)

local function openGarageAdmin()
    if open or captureActive or IsNuiFocused() then return end
    CreateThread(function()
        local data, errorMessage = OR.Callback.awaitResource('ob_garage', 'adminData')
        if not data then return notify(errorMessage or 'Sem permissao para abrir o editor de garagens.', 'error') end
        currentGarage, adminOpen, open = nil, true, true
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false)
        SendNUIMessage({ action = 'openAdmin', data = data })
    end)
end

RegisterNetEvent('ob_garage:client:openAdmin', openGarageAdmin)
RegisterCommand('obgarageeditor', openGarageAdmin, false)

RegisterNUICallback('adminRefresh', function(_, cb)
    local data, errorMessage = OR.Callback.awaitResource('ob_garage', 'adminData')
    cb({ ok = data ~= nil, data = data, error = errorMessage })
end)

RegisterNUICallback('adminSave', function(data, cb)
    for _, vehicle in ipairs(type(data) == 'table' and type(data.vehicles) == 'table' and data.vehicles or {}) do
        local model = tostring(vehicle.model or ''):lower()
        local hash = joaat(model)
        if model == '' or not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
            return cb({ ok = false, error = ('O modelo %s nao existe neste cliente.'):format(model ~= '' and model or '(vazio)') })
        end
    end
    local result, message = OR.Callback.awaitResource('ob_garage', 'adminSaveGarage', data)
    cb({ ok = result ~= nil, data = result, message = result and message or nil, error = result and nil or message })
end)

RegisterNUICallback('adminDelete', function(data, cb)
    local result, message = OR.Callback.awaitResource('ob_garage', 'adminDeleteGarage', data and data.id)
    cb({ ok = result == true, message = result and message or nil, error = result and nil or message })
end)

RegisterNUICallback('adminTeleport', function(data, cb)
    if not adminOpen or captureActive then return cb({ ok = false, error = 'Editor indisponivel.' }) end
    local coords, err = OR.Callback.awaitResource('ob_garage', 'adminTeleport', data.id, data.kind, data.index)
    if not coords then return cb({ ok = false, error = err }) end
    close()
    TriggerEvent('ob_admin:client:teleport', coords)
    cb({ ok = true })
end)

RegisterNUICallback('adminCapture', function(data, cb)
    if not adminOpen or captureActive then return cb({ ok = false, error = 'Captura indisponivel.' }) end
    local kind = type(data) == 'table' and tostring(data.kind or '') or ''
    local slotIndex = type(data) == 'table' and math.floor(tonumber(data.index) or 0) or 0
    if kind ~= 'open' and kind ~= 'store' and kind ~= 'spawn' then
        return cb({ ok = false, error = 'Tipo de ponto invalido.' })
    end
    captureActive = true
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'captureStart', kind = kind, index = slotIndex })
    cb({ ok = true })
    CreateThread(function()
        while captureActive and adminOpen do
            local ped = PlayerPedId()
            local entity = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or ped
            local coords = GetEntityCoords(entity)
            DisableControlAction(0, 177, true)
            DisableControlAction(0, 200, true)
            DrawMarker(28, coords.x, coords.y, coords.z + 0.25, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                0.35, 0.35, 0.35, 40, 181, 255, 210, false, false, 2, false, nil, nil, false)
            OR.Help.Show('[E] Capturar posicao  |  [ESC] Cancelar')
            if IsControlJustReleased(0, 38) then
                captureActive = false
                OR.Help.Hide()
                SetNuiFocus(true, true)
                SendNUIMessage({
                    action = 'captureResult', kind = kind, index = slotIndex,
                    point = { x = coords.x, y = coords.y, z = coords.z, w = GetEntityHeading(entity) },
                })
                break
            end
            if IsDisabledControlJustReleased(0, 200) or IsDisabledControlJustReleased(0, 177) then
                captureActive = false
                OR.Help.Hide()
                SetNuiFocus(true, true)
                SendNUIMessage({ action = 'captureResult', kind = kind, index = slotIndex, cancelled = true })
                break
            end
            Wait(0)
        end
    end)
end)

RegisterNetEvent('ob_garage:client:stored', function(netId, temporary)
    local veh = NetworkGetEntityFromNetworkId(netId); if veh and veh ~= 0 then DeleteVehicle(veh) end
    notify(temporary and 'Veiculo gratuito devolvido.' or 'Veiculo guardado.', 'success'); if open then refresh() end
end)
CreateThread(function()
    local loaded = false
    while not loaded do
        local ok, definitions = OR.Callback.await('ob_garage:server:definitions')
        if ok and type(definitions) == 'table' then
            applyGarageDefinitions(definitions)
            loaded = true
        else
            Wait(1000)
        end
    end
    while LocalPlayer.state['or:loaded'] ~= true do Wait(250) end
    registerGarageTargets()
end)

AddEventHandler('ob_target:client:ready', registerGarageTargets)

RegisterCommand('garagem', function()
    if GarageConfig.garages.central then openGarage('central') end
end, false)


CreateThread(function()
    local garageHelp = false
    while true do
        local wait, coords, nearOpen = 1000, GetEntityCoords(PlayerPedId()), false
        local ped = PlayerPedId()
        local driving = GetVehiclePedIsIn(ped, false)
        local storeGarage, storeDistance
        for id, place in pairs(GarageConfig.garages) do
            local distance = #(coords - (place.storeCoords or place.coords))
            if driving ~= 0 and GetPedInVehicleSeat(driving, -1) == ped
                and distance <= (tonumber(place.storeDistance) or 16.0)
                and (not storeDistance or distance < storeDistance) then
                storeGarage, storeDistance = id, distance
            end
            if #(coords - place.coords) < 30.0 then
                wait = 0
                -- Icone de garagem baixo e uma base discreta na vaga.
                DrawMarker(25, place.coords.x, place.coords.y, place.coords.z - 0.98, 0.0,0.0,0.0,0.0,0.0,0.0, 1.15,1.15,0.25, 40,145,255,220,false,true,2,false,nil,nil,false)
                DrawMarker(36, place.coords.x, place.coords.y, place.coords.z + 0.37, 0.0,0.0,0.0,0.0,0.0,0.0, 0.60, 0.60, 0.60, 40,145,255,130,false,false,2,false,nil,nil,false)
                if driving == 0 and not open and not IsNuiFocused() and #(coords - place.coords) < 2.5 then
                    nearOpen = true
                    OR.Help.Show('[E] Abrir garagem')
                    if IsControlJustReleased(0, 38) then openGarage(id) end
                end
            end
        end
        if storeGarage and not open and not captureActive and not IsNuiFocused() then
            wait, nearOpen = 0, true
            OR.Help.Show('[E] Guardar meu veiculo')
            if IsControlJustReleased(0, 38) then
                currentGarage = storeGarage
                storeVehicle(false)
            end
        end
        if garageHelp and not nearOpen then OR.Help.Hide() end
        garageHelp = nearOpen
        Wait(wait)
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    open, adminOpen, captureActive = false, false, false
    OR.Help.Hide()
    SetNuiFocus(false, false)
    clearGarageWorld()
    if trackBlip and DoesBlipExist(trackBlip) then RemoveBlip(trackBlip) end
end)
