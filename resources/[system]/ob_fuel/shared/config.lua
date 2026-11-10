OBFuelConfig = {
    Tick = 1000,
    -- A quilometragem e calculada pelo motorista, mas e enviada ao servidor
    -- neste intervalo (alem de ao sair/trocar de veiculo).
    SaveInterval = 60000,
    -- Consumo de gameplay em litros por 100 km. Com as capacidades abaixo,
    -- equivale a cerca de 1,2%/km na gasolina e 1%/km no diesel.
    ConsumptionPer100Km = { gasoline = 80.0, diesel = 180.0 },
    PumpDistance = 3.0,
    VehiclePumpDistance = 6.0,
    InteractionDistance = 2.0,
    RefillPerSecond = 2.0,
    -- Um tanque abaixo desta saude esta furado/inseguro. O posto recusa o
    -- abastecimento ate o reparo, evitando cobrar por combustivel vazando.
    MinimumTankHealthToRefuel = 650.0,
    Types = {
        gasoline = { label = 'Gasolina', price = 7, capacity = 65 },
        diesel = { label = 'Diesel', price = 9, capacity = 180 },
    },
    -- Caminhoes, onibus e veiculos de trabalho usam diesel. Barcos e aeronaves
    -- usam gasolina, como definido para a OB Framework.
    DieselClasses = { [10] = true, [11] = true, [12] = true, [17] = true, [19] = true, [20] = true },
    PumpModels = { `prop_gas_pump_old2`, `prop_gas_pump_1a`, `prop_vintage_pump`, `prop_gas_pump_old3`, `prop_gas_pump_1c`, `prop_gas_pump_1b`, `prop_gas_pump_1d` },
    Maintenance = { oilKm = 500, brakesKm = 700, plugsKm = 900, damagePerTick = 3.0 },
    -- Combustivel errado nao explode o motor de uma vez: ele contamina o
    -- tanque, reduz a saude gradualmente e pode causar falhas ao dirigir.
    Misfuel = { damagePerKm = 16.0, stallChancePerKm = 0.12, warningCooldown = 15000 },
}
