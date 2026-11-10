Patrol = {
    command = 'patrulha',
    leaveCommand = 'patrulhasair',
    speedLimitKmh = 60.0,
    policePermission = 'police',
    requireDuty = true,
    staffPermission = 'panel.open',

    npc = {
        model = 's_m_y_cop_01',
        coords = vec4(441.1396, -995.5607, 30.6896, 8.8421),
        targetDistance = 3.0,
        startDistance = 30.0,
    },

    group = {
        maxMembers = 4,
        inviteDistance = 18.0,
        inviteSeconds = 30,
    },

    allowedVehicles = {
        police3 = 'Police Interceptor',
        policeb2 = 'Police Motorcycle',
    },

    checkpoint = {
        type = 47,
        radius = 7.0,
        serverTolerance = 13.0,
        color = { r = 0, g = 145, b = 255, a = 170 },
        iconColor = 3,
    },

    payment = {
        item = 'money',
        checkpoint = { min = 100, max = 250 },
    },

    -- Estas rotas sao sementes. Na primeira inicializacao elas sao copiadas
    -- para o banco e depois todo o gerenciamento acontece pelo painel.
    routes = {
        south = {
            {
                id = 'south_central', label = 'Centro e Mission Row',
                points = {
                    vec3(438.95, -981.58, 30.69), vec3(307.10, -760.84, 29.31),
                    vec3(87.96, -1002.25, 29.40), vec3(-292.35, -987.54, 31.08),
                    vec3(-552.14, -851.19, 27.76), vec3(-322.06, -648.91, 32.35),
                    vec3(76.47, -676.82, 31.72), vec3(304.69, -851.44, 29.25),
                }
            },
            {
                id = 'south_davis_port', label = 'Davis e Porto',
                points = {
                    vec3(367.52, -1601.76, 29.29), vec3(110.18, -1772.80, 29.21),
                    vec3(-148.02, -2014.47, 22.88), vec3(-301.79, -2696.40, 6.00),
                    vec3(145.96, -3030.63, 7.04), vec3(716.23, -2992.23, 6.02),
                    vec3(929.84, -2523.29, 28.31), vec3(653.89, -1817.55, 25.62),
                }
            },
            {
                id = 'south_vespucci', label = 'Vespucci e Del Perro',
                points = {
                    vec3(-1091.70, -807.16, 19.28), vec3(-1294.45, -568.79, 30.57),
                    vec3(-1428.13, -286.09, 46.20), vec3(-1575.88, -526.27, 35.06),
                    vec3(-1449.84, -872.77, 10.17), vec3(-1220.72, -1127.34, 7.64),
                    vec3(-929.31, -1198.44, 4.95), vec3(-758.50, -1046.06, 12.39),
                }
            },
        },
        north = {
            {
                id = 'north_sandy', label = 'Sandy Shores',
                points = {
                    vec3(1854.92, 3675.58, 33.72), vec3(1698.22, 3595.19, 35.47),
                    vec3(1448.93, 3602.26, 34.86), vec3(1535.89, 3778.32, 34.51),
                    vec3(1708.31, 3847.44, 34.93), vec3(1953.63, 3743.17, 32.29),
                }
            },
            {
                id = 'north_paleto', label = 'Paleto Bay',
                points = {
                    vec3(-447.35, 6012.65, 31.72), vec3(-277.21, 6174.82, 31.50),
                    vec3(-113.85, 6324.26, 31.58), vec3(137.26, 6558.75, 31.82),
                    vec3(49.72, 6643.16, 31.69), vec3(-223.43, 6434.72, 31.20),
                    vec3(-363.49, 6217.31, 31.49),
                }
            },
            {
                id = 'north_highway', label = 'Rodovia Norte',
                points = {
                    vec3(2570.10, 3077.49, 43.07), vec3(2702.94, 3456.63, 55.77),
                    vec3(2482.54, 4097.71, 38.12), vec3(1966.94, 4642.28, 40.79),
                    vec3(1694.65, 4876.21, 42.04), vec3(1304.10, 5662.41, 54.32),
                    vec3(558.63, 6553.24, 27.99), vec3(151.01, 6586.62, 31.84),
                }
            },
        },
    },

    creator = {
        panelCommand = 'patrulharotas',
        startCommand = 'patrulhacriar',
        pointCommand = 'patrulhaponto',
        saveCommand = 'patrulhasalvar',
        cancelCommand = 'patrulhacancelar',
        minimumPoints = 3,
        maximumPoints = 80,
    },

    tacticalAI = {
        decisionIntervalMs = 4500,
        stuckCheckMs = 3500,
        stuckDistance = 1.25,
        surrenderHealth = 135,
        coverDistance = 38.0,
        flankDistance = 14.0,
        fleeDistance = 190.0,
    },
}
