GarageConfig = {
    -- Carros pessoais podem ser retirados em qualquer garagem pessoal.
    SharedPersonalGarages = true,
    Tax = {
        Enabled = true,
        -- A primeira cobranca vence este numero de dias depois da compra.
        BillingIntervalDays = 7,
        -- O veiculo e removido quando completar este numero de dias em atraso.
        DeleteAfterOverdueDays = 14,
        PersonalRatePercent = 15.0,
        ServiceRatePercent = 5.0,
        CleanupIntervalMinutes = 30,
        MinimumCharge = 1,
    },
    Images = {
        -- Cada modelo procura: <base>/<modelo>.png
        BaseUrl = '/orbis/cars/',
        Extension = '.png',
        Default = 'carro.png',
        Preload = true,
    },
    Editor = {
        Enabled = true,
        AdminPermission = 'world.garages',
        ProtectedGarage = 'central',
        MaxGarages = 100,
        MaxSpawnPoints = 20,
        MaxCatalogVehicles = 100,
        MaxSpawnDistance = 150.0,
        Defaults = {
            OpenSize = { x = 4.0, y = 4.0, z = 3.0 },
            StoreSize = { x = 7.0, y = 7.0, z = 3.0 },
            StoreDistance = 16.0,
            SpawnClearRadius = 1.75,
            Blip = { sprite = 357, color = 3, scale = 0.82 },
        },
    },

    -- Preenchido pelo servidor a partir da tabela ob_garage_definitions.
    -- Garagens novas devem ser criadas pelo editor do F11.
    garages = {},
}
