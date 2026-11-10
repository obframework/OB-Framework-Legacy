local Config = OBVehicleFailureConfig or { enabled = false }

local activeVehicle
local originalHandling

local handlingFields = {
    { name = 'fCollisionDamageMult', config = 'collision' },
    { name = 'fDeformationDamageMult', config = 'deformation' },
    { name = 'fEngineDamageMult', config = 'engine' },
    { name = 'fWeaponDamageMult', config = 'weapon' },
}

local function validVehicle(vehicle)
    return vehicle and vehicle ~= 0 and DoesEntityExist(vehicle)
end

local function isManagedVehicle(vehicle)
    if not validVehicle(vehicle) then return false end
    local ignoredClasses = type(Config.ignoredClasses) == 'table' and Config.ignoredClasses or {}
    return ignoredClasses[GetVehicleClass(vehicle)] ~= true
end

local function restoreHandling()
    if validVehicle(activeVehicle) and type(originalHandling) == 'table' then
        for field, value in pairs(originalHandling) do
            SetVehicleHandlingFloat(activeVehicle, 'CHandlingData', field, value)
        end
    end

    activeVehicle = nil
    originalHandling = nil
end

local function configureNativeDamage(vehicle)
    SetEntityInvincible(vehicle, false)
    SetEntityCanBeDamaged(vehicle, true)
    SetVehicleCanBeVisiblyDamaged(vehicle, true)
    SetVehicleEngineCanDegrade(vehicle, true)
    SetVehicleTyresCanBurst(vehicle, true)
    SetVehicleCanBreak(vehicle, true)

    -- Estes natives apenas devolvem o comportamento original do GTA. Nenhum
    -- efeito de particula e criado ou mantido por este recurso.
    if type(SetDisableVehicleEngineFires) == 'function' then
        SetDisableVehicleEngineFires(vehicle, false)
    end
    if type(SetDisableVehiclePetrolTankFires) == 'function' then
        SetDisableVehiclePetrolTankFires(vehicle, false)
    end
    if type(SetDisableVehiclePetrolTankDamage) == 'function' then
        SetDisableVehiclePetrolTankDamage(vehicle, false)
    end
    if type(SetVehicleCanLeakOil) == 'function' then
        SetVehicleCanLeakOil(vehicle, true)
    end
    if type(SetVehicleCanLeakPetrol) == 'function' then
        SetVehicleCanLeakPetrol(vehicle, true)
    end
end

local function applyHandling(vehicle)
    restoreHandling()

    activeVehicle = vehicle
    originalHandling = {}

    local classMultipliers = type(Config.classMultiplier) == 'table' and Config.classMultiplier or {}
    local handling = type(Config.handling) == 'table' and Config.handling or {}
    local minimums = type(handling.minimum) == 'table' and handling.minimum or {}
    local classScale = math.max(0.0, tonumber(classMultipliers[GetVehicleClass(vehicle)]) or 1.0)
    local maximum = math.max(0.0, tonumber(handling.maximum) or 10.0)

    for _, data in ipairs(handlingFields) do
        local original = GetVehicleHandlingFloat(vehicle, 'CHandlingData', data.name)
        local multiplier = math.max(0.0, tonumber(handling[data.config]) or 1.0)
        local minimum = math.max(0.0, tonumber(minimums[data.config]) or 0.0)
        originalHandling[data.name] = original
        SetVehicleHandlingFloat(
            vehicle,
            'CHandlingData',
            data.name,
            math.min(maximum, math.max(minimum, original * multiplier * classScale))
        )
    end

    configureNativeDamage(vehicle)
end

CreateThread(function()
    while true do
        local wait = math.max(50, tonumber(Config.healthyPollInterval) or 200)
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local isDriver = vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped

        if Config.enabled == true and isDriver and isManagedVehicle(vehicle) then
            if activeVehicle ~= vehicle then
                applyHandling(vehicle)
            end

            if GetVehicleEngineHealth(vehicle) <= (tonumber(Config.engineShutdownHealth) or 0.0) then
                -- Somente o estado destruido exige verificacao por frame. Isso
                -- impede que acelerador/freio ou outro native reative o motor.
                wait = 0
                SetVehicleUndriveable(vehicle, true)
                SetVehicleEngineOn(vehicle, false, true, true)
                DisableControlAction(0, 71, true)
                DisableControlAction(0, 72, true)
            end
        elseif activeVehicle then
            restoreHandling()
        end

        Wait(wait)
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        restoreHandling()
    end
end)
