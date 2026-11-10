local Config = ORControlConfig

local function hashSet(names)
    local result = {}
    for _, name in ipairs(names or {}) do result[GetHashKey(name)] = true end
    return result
end

local GangPedModels = hashSet(Config.Ai.gangPedModels)

local function applyGangModelSuppression(state)
    for modelHash in pairs(GangPedModels) do
        SetPedModelIsSuppressed(modelHash, state)
    end
end

local function applyStaticAmbientSettings()
    local density = Config.Density
    SetNumberOfParkedVehicles(math.max(0, math.floor(density.parkedVehicleCount or 0)))
    SetGarbageTrucks(density.garbageTrucks == true)
    SetRandomBoats(density.randomBoats == true)
    SetCreateRandomCops(density.randomCops == true)
    SetCreateRandomCopsOnScenarios(density.randomCopsOnScenarios == true)
    SetCreateRandomCopsNotOnScenarios(density.randomCopsNotOnScenarios == true)

    if Config.Audio.scene and Config.Audio.scene ~= '' then StartAudioScene(Config.Audio.scene) end
    if Config.Audio.flag and Config.Audio.flag ~= '' then SetAudioFlag(Config.Audio.flag, true) end
    if Config.Audio.disableVehicleRadio == true then
        SetUserRadioControlEnabled(false)
        SetFrontendRadioActive(false)
        SetRadioToStationName('OFF')
    end
end

local function disableCurrentVehicleRadio()
    if Config.Audio.disableVehicleRadio ~= true then return end
    SetUserRadioControlEnabled(false)
    SetFrontendRadioActive(false)
    SetRadioToStationName('OFF')

    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle and vehicle ~= 0 then
        SetVehRadioStation(vehicle, 'OFF')
        SetVehicleRadioEnabled(vehicle, false)
    end
end

local function applyDispatchSettings()
    for service, enabled in pairs(Config.Dispatch.services or {}) do
        EnableDispatchService(tonumber(service), enabled == true)
    end
end

local function applyDensityThisFrame()
    local density = Config.Density
    SetRandomVehicleDensityMultiplierThisFrame(density.randomVehicle or 0.0)
    SetParkedVehicleDensityMultiplierThisFrame(density.parkedVehicle or 0.0)
    SetVehicleDensityMultiplierThisFrame(density.vehicle or 0.0)
    SetPedDensityMultiplierThisFrame(density.ped or 0.0)
    SetScenarioPedDensityMultiplierThisFrame(density.scenarioPed or 0.0, density.scenarioPedInterior or 0.0)
    DisableVehicleDistantlights(density.disableVehicleDistantLights == true)
    DistantCopCarSirens(density.copCarSirens == true)
end

local function clearAmbientVehiclesNearPlayer(coords)
    local density = Config.Density
    if density.clearExistingAmbientVehicles ~= true then return end

    -- Opcao explicitamente opt-in. Nunca use isso como controle comum de densidade.
    ClearAreaOfVehicles(coords.x, coords.y, coords.z, density.clearExistingVehicleRadius or 120.0, false, false, false, false, false)
end

local function suppressVehicleGeneratorsNearPlayer(coords)
    local density = Config.Density
    if density.suppressVehicleGenerators ~= true then return end

    local range = math.max(1.0, tonumber(density.generatorCleanupRange) or 500.0)
    RemoveVehiclesFromGeneratorsInArea(
        coords.x - range, coords.y - range, coords.z - range,
        coords.x + range, coords.y + range, coords.z + range
    )
    SetAllVehicleGeneratorsActiveInArea(
        coords.x - range, coords.y - range, coords.z - range,
        coords.x + range, coords.y + range, coords.z + range,
        false, false
    )
end

local function configureTrains()
    local trains = Config.Trains
    for _, track in ipairs(trains.tracks or {}) do
        SwitchTrainTrack(track, true)
        SetTrainTrackSpawnFrequency(track, trains.spawnFrequency or 120000)
    end
    SetRandomTrains(true)
end

AddEventHandler('populationPedCreating', function(_, _, _, model)
    if Config.Ai.disableGangPeds and model and GangPedModels[model] then CancelEvent() end
end)

CreateThread(function()
    applyStaticAmbientSettings()
    applyDispatchSettings()
    if Config.Trains.enabled then configureTrains() end
    applyGangModelSuppression(Config.Ai.disableGangPeds == true)

    local lastGeneratorCleanup = 0
    local lastVehicleClear = 0
    local lastDispatchRefresh = 0
    local lastVehicleRadioCheck = 0

    while true do
        local now = GetGameTimer()
        local playerCoords = GetEntityCoords(PlayerPedId())

        if Config.Density.enabled then
            applyDensityThisFrame()
            if now - lastGeneratorCleanup >= (Config.Density.generatorCleanupInterval or 10000) then
                suppressVehicleGeneratorsNearPlayer(playerCoords)
                lastGeneratorCleanup = now
            end
            if now - lastVehicleClear >= (Config.Density.clearExistingVehicleInterval or 10000) then
                clearAmbientVehiclesNearPlayer(playerCoords)
                lastVehicleClear = now
            end
        end

        if now - lastDispatchRefresh >= (Config.Dispatch.refreshInterval or 10000) then
            applyDispatchSettings()
            lastDispatchRefresh = now
        end
        if Config.Audio.disableVehicleRadio == true
            and now - lastVehicleRadioCheck >= (Config.Audio.vehicleRadioCheckInterval or 500) then
            disableCurrentVehicleRadio()
            lastVehicleRadioCheck = now
        end
        Wait(0)
    end
end)

CreateThread(function()
    while true do
        if Config.Wanted.disabled then
            SetMaxWantedLevel(0)
            ClearPlayerWantedLevel(PlayerId())
        end
        Wait(Config.Wanted.refreshInterval or 1000)
    end
end)

CreateThread(function()
    while true do
        applyGangModelSuppression(Config.Ai.disableGangPeds == true)
        Wait(10000)
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    applyGangModelSuppression(false)
    if Config.Audio.scene and Config.Audio.scene ~= '' then StopAudioScene(Config.Audio.scene) end
    if Config.Audio.flag and Config.Audio.flag ~= '' then SetAudioFlag(Config.Audio.flag, false) end
    if Config.Audio.disableVehicleRadio == true then
        SetUserRadioControlEnabled(true)
        local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
        if vehicle and vehicle ~= 0 then SetVehicleRadioEnabled(vehicle, true) end
    end
end)
