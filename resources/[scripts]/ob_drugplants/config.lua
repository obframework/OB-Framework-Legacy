DrugPlants = {}

DrugPlants.interactDistance = 2.2
DrugPlants.maxPlantsPerPlayer = 8
DrugPlants.maxPlantsGlobal = 150
DrugPlants.minimumSpacing = 1.25
DrugPlants.syncIntervalSeconds = 30
DrugPlants.databaseTickSeconds = 30
DrugPlants.ownerOnly = true
DrugPlants.cleanupOrphanedProps = true

DrugPlants.uses = {
    pot = 5,
    wateringCan = 10,
}

DrugPlants.items = {
    pot = 'plant_pot',
    wateringCan = 'watering_can',
    fertilizer = 'plant_fertilizer',
}

-- O nome correto do prop nativo usa o conjunto Biker. O modelo antigo
-- prop_plant_pot_02a nao existe (a familia valida seria prop_pot_plant_*).
DrugPlants.emptyPotModel = 'bkr_prop_weed_bucket_open_01a'
DrugPlants.emptyPotFallbackModel = 'prop_pot_plant_02a'

DrugPlants.types = {
    weed = {
        label = 'Maconha',
        seedItem = 'weed_seed',
        harvestItem = 'weed_leaf',
        growMinutes = 5,
        fertilizedGrowMinutes = 3,
        yieldMin = 6,
        yieldMax = 12,
        seedReturnChance = 30,
        models = {
            { growth = 0, model = 'bkr_prop_weed_01_small_01c' },
            { growth = 34, model = 'bkr_prop_weed_01_small_01b' },
            { growth = 58, model = 'bkr_prop_weed_med_01b' },
            { growth = 82, model = 'bkr_prop_weed_lrg_01b' },
        },
    },
    coca = {
        label = 'Coca',
        seedItem = 'coca_seed',
        harvestItem = 'coca_leaf',
        growMinutes = 5,
        fertilizedGrowMinutes = 3,
        yieldMin = 5,
        yieldMax = 10,
        seedReturnChance = 25,
        -- GTA V não possui uma planta de coca nativa. As variantes abaixo
        -- diferenciam visualmente a coca sem exigir um mapa ou prop externo.
        models = {
            { growth = 0, model = 'bkr_prop_weed_01_small_01a' },
            { growth = 34, model = 'bkr_prop_weed_01_small_01c' },
            { growth = 58, model = 'bkr_prop_weed_med_01a' },
            { growth = 82, model = 'bkr_prop_weed_lrg_01a' },
        },
    },
}

DrugPlants.care = {
    initialWater = 45.0,
    initialNutrients = 55.0,
    waterPerUse = 38.0,
    nutrientsPerUse = 45.0,
    waterDecayPerHour = 14.0,
    nutrientDecayPerHour = 6.0,
    healthyWaterMin = 18.0,
    healthyWaterMax = 92.0,
    healthyNutrientsMin = 10.0,
    fertilizedNutrientsMin = 80.0,
    dryDamagePerHour = 16.0,
    floodedDamagePerHour = 7.0,
    starvedDamagePerHour = 6.0,
}

DrugPlants.durations = {
    place = 4500,
    plant = 5000,
    water = 5000,
    fertilize = 5000,
    harvest = 6500,
    remove = 3500,
}

