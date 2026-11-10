OBOrgConfig = {
    Commands = {
        legal = 'painel',
        illegal = 'tablet',
        admin = 'adminorg',
    },

    -- Regra global, sem precisar configurar cada organizacao em arquivo.
    BlacklistDays = 4,
    -- Salarios sao definidos por cargo no adminorg, pagos no banco somente
    -- para membros de organizacoes legais que estiverem em servico.
    PayrollIntervalMinutes = 30,

    Limits = {
        organisations = 200,
        membersDefault = 250,
        ranksPerOrganisation = 20,
        goalsPerOrganisation = 20,
        routesPerOrganisation = 20,
        pointsPerRoute = 100,
        rewardsPerRoute = 20,
        maxSalary = 100000,
        maxRewardAmount = 1000,
        chestsPerOrganisation = 20,
        chestSlots = 200,
        chestWeightKg = 100000,
    },

    Interaction = {
        key = 38, -- E
        cancelKey = 168, -- F7
        drawDistance = 15.0,
        useDistance = 2.0,
        collectDuration = 3000,
    },

    -- Apenas limites tecnicos. Nome, icone, cor e visibilidade de cada
    -- organizacao legal sao editados no /adminorg e persistidos no banco.
    DutyBlips = {
        enabled = true,
        updateInterval = 1500,
        showSelf = true,
        default = {
            sprite = 1,
            scale = 0.75,
            colour = 3,
            helicopterSprite = 422,
        },
    },
}
