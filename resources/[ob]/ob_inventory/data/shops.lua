ORInventoryShops = {
    DevelopmentFree = false,
    Editor = { Enabled = true, Permission = 'world.shops', MaxLocations = 200, MaxItems = 150 },
    Streaming = {
        SpawnDistance = 90.0,
        DespawnDistance = 120.0,
        UpdateInterval = 1000,
    },
    Business = {
        Enabled = true,
        PurchasableGroups = { convenience = true },
        MaxStoresPerOwner = 3,
        DefaultPurchasePrice = 2500000,
        DefaultInitialStock = 50,
        DefaultMaximumStock = 500,
        WholesaleRate = 0.45,
        TaxRate = 0.15,
        ResaleRate = 0.70,
        ManagementDistance = 4.0,
        DeliveryTimeoutMinutes = 20,
        EconomyAccount = 'city_treasury',
        Delivery = {
            Vehicle = 'mule3', Driver = 's_m_m_trucker_01', Loader = 's_m_m_dockwork_01',
            Manager = 'a_m_m_business_01', DriveSpeed = 16.0, DriveStyle = 786475,
            SpawnMinDistance = 500.0, SpawnMaxDistance = 2000.0,
            SpawnSearchDistances = { 650.0, 1000.0, 1400.0, 1800.0 }, SpawnClearRadius = 7.0,
            NpcFeeRate = 0.08, PickupDiscountRate = 0.10,
            PickupDepots = {
                { id='city', label='Centro de Distribuicao - Cidade', coords={ x=63.7, y=-1728.7, z=28.6, w=50.0 } },
                { id='north', label='Centro de Distribuicao - Norte', coords={ x=161.5, y=6636.2, z=30.5, w=135.8 } },
            },
            CargoModel = 'prop_cs_cardbox_01',
        },
    },
    -- Cadastros carregados do banco; exemplos iniciais em modules/shops/server/defaults.lua.
    Groups = {},
    Shops = {},
}
