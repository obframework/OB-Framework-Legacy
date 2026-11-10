ORControlConfig = {
    Density = {
        enabled = true,
        ped = 1.5,
        scenarioPed = 1.0,
        scenarioPedInterior = 0.0,
        vehicle = 0.6,
        randomVehicle = 0.2,
        parkedVehicle = 0.0,
        parkedVehicleCount = 0,
        disableVehicleDistantLights = true,
        garbageTrucks = false,
        randomBoats = false,
        randomCops = false,
        randomCopsOnScenarios = false,
        randomCopsNotOnScenarios = false,
        copCarSirens = false,

        -- Remove apenas geradores de veiculos ambientas perto do jogador.
        -- Um raio de 9.999 m repetido constantemente causa trabalho inutil.
        suppressVehicleGenerators = true,
        generatorCleanupRange = 500.0,
        generatorCleanupInterval = 10000,

        -- Deixe desligado: limpar veiculos existentes pode apagar veiculos de
        -- jogadores ou de outros recursos. As densidades ja impedem novos NPCs.
        clearExistingAmbientVehicles = false,
        clearExistingVehicleRadius = 120.0,
        clearExistingVehicleInterval = 10000,
    },

    Ai = {
        -- O Enhanced pode encerrar dentro de iteradores/pools globais de peds.
        -- A supressao abaixo usa modelo + populationPedCreating, sem enumerar CPed.
        disableGangPeds = true,
        gangPedModels = {
            'g_m_y_ballaeast_01', 'g_m_y_ballaorig_01', 'g_m_y_ballasout_01',
            'g_m_y_famca_01', 'g_m_y_famdnf_01', 'g_m_y_famfob_01',
            'g_m_y_lost_01', 'g_m_y_lost_02', 'g_m_y_lost_03',
            'g_m_y_mexgang_01', 'g_m_y_mexgoon_01', 'g_m_y_mexgoon_02',
            'g_m_y_mexgoon_03', 'g_m_y_salvaboss_01', 'g_m_y_salvagoon_01',
            'g_m_y_salvagoon_02', 'g_m_y_salvagoon_03',
        },
    },

    Wanted = {
        disabled = true,
        refreshInterval = 1000,
    },

    Trains = {
        enabled = true,
        spawnFrequency = 120000,
        tracks = { 0, 3 },
    },

    Dispatch = {
        refreshInterval = 10000,
        services = { [4] = false, [5] = false, [6] = true },
    },

    Audio = {
        scene = 'CHARACTER_CHANGE_IN_SKY_SCENE',
        flag = 'PoliceScannerDisabled',
        disableVehicleRadio = true,
        vehicleRadioCheckInterval = 500,
    },
}
