OBPrisonConfig = {
    Commands = {
        Jail = 'prender',
        Release = 'soltar',
    },
    AdminPermission = 'panel.open',
    PolicePermission = 'police',
    RequirePoliceDuty = true,

    -- Um mês do MDT equivale a este total de segundos reais.
    SecondsPerMonth = 60,
    CountTimeOffline = false,
    SaveIntervalSeconds = 15,
    MaximumMonths = 240,

    Entry = { x = 1691.84, y = 2592.43, z = 45.56, w = 91.11 },
    Release = { x = 1847.78, y = 2586.05, z = 45.67, w = 89.0 },
    Boundary = {
        center = { x = 1690.6445, y = 2572.5474, z = 45.5648 },
        radius = 200.0,
        graceSeconds = 5,
    },

    Service = {
        InteractDistance = 2.0,
        ValidationDistance = 3.0,
        ServicesPerMonth = 2,
        RewardItems = false,
    },
    Services = {
        sweep_yard = {
            label = 'Varrer o pátio',
            npc = { model = 's_m_m_prisguard_01', x = 1705.3442, y = 2520.7244, z = 45.5648, w = 141.0 },
            durationMs = 8000,
            scenario = 'WORLD_HUMAN_JANITOR',
            points = {
                { x = 1703.2382, y = 2523.9495, z = 45.5883 },
                { x = 1669.0344, y = 2509.0833, z = 45.5648 },
                { x = 1623.4146, y = 2543.3003, z = 45.5648 },
                { x = 1641.4001, y = 2561.5347, z = 45.5648 },
                { x = 1665.5660, y = 2538.9768, z = 45.5648 },
                { x = 1693.1176, y = 2478.5190, z = 45.5649 },
            },
        },
        clean_tables = {
            label = 'Limpar as mesas',
            npc = { model = 's_m_m_prisguard_01', x = 1713.0676, y = 2550.3845, z = 45.5648, w = 266.0 },
            durationMs = 7000,
            scenario = 'WORLD_HUMAN_MAID_CLEAN',
            points = {
                { x = 1714.2494, y = 2554.3337, z = 45.5648 },
                { x = 1712.6649, y = 2553.5090, z = 45.5648 },
                { x = 1707.5710, y = 2550.4690, z = 45.5648 },
                { x = 1705.1205, y = 2553.6353, z = 45.5648 },
                { x = 1706.8521, y = 2553.2026, z = 45.5648 },
            },
        },
        fix_power = {
            label = 'Ajustar a energia',
            npc = { model = 's_m_m_prisguard_01', x = 1667.0562, y = 2501.3127, z = 45.5649, w = 91.0 },
            durationMs = 10000,
            scenario = 'WORLD_HUMAN_WELDING',
            points = {
                { x = 1663.8999, y = 2502.5798, z = 45.5649 },
                { x = 1627.0433, y = 2539.4165, z = 45.5649 },
                { x = 1760.5743, y = 2541.4587, z = 45.5649 },
            },
        },
    },

    Escape = {
        Item = 'prison_key',
        RequiredPolice = 0,
        TrackerSeconds = 300,
        CooldownSeconds = 300,
        ValidationDistance = 3.0,
        Stages = {
            {
                label = 'Destravar o painel de manutenção',
                coords = { x = 1665.9482, y = 2723.9407, z = 45.5649 },
                minDurationMs = 4500,
                minigame = { title = 'PAINEL DE SEGURANÇA', key = 'E', steps = 7, speed = 1.8, tolerance = 0.08 },
            },
            {
                label = 'Desativar a alimentação da cerca',
                coords = { x = 1627.16, y = 2538.74, z = 45.56 },
                minDurationMs = 5000,
                minigame = { title = 'REDE ELÉTRICA', key = 'E', steps = 8, speed = 2.0, tolerance = 0.07 },
            },
            {
                label = 'Abrir a passagem externa',
                coords = { x = 1760.42, y = 2513.08, z = 45.56 },
                minDurationMs = 5500,
                minigame = { title = 'TRAVA EXTERNA', key = 'E', steps = 9, speed = 2.15, tolerance = 0.065 },
            },
        },
        Exit = { x = 1831.4475, y = 2471.8306, z = 45.5754, w = 237.2819 },
    },
}
