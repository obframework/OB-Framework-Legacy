Leiteiro = {}
Leiteiro.economyIntegration = false
Leiteiro.tutorial = { youtubeUrl = '', title = 'Tutorial do trabalho de leiteiro' }

Leiteiro.items = {
    bucket = 'balde',
    rawMilk = 'balde-leite'
}

Leiteiro.job = {
    startBuckets = 4,
    milkCooldownSeconds = 300,
    processTimeMs = 7000,
    milkTimeMs = 12000,
    deliveryTimeMs = 6000,
    rawMilkPerBox = 2,
    paymentPerBox = { min = 430, max = 610 },
    minBoxesToDeliver = 1
}

Leiteiro.group = {
    maxMembers = 2,
    inviteDistance = 18.0,
    inviteSeconds = 30
}

Leiteiro.progress = {
    xpPerBox = 18,
    levelStep = 500,
    maxLevel = 10,
    paymentBonusPerLevel = 0.025,
    maxPaymentBonus = 0.225,
    contract = {
        minimumLevel = 3,
        targetBoxes = { min = 8, max = 12 },
        completionBonus = 0.15
    }
}

Leiteiro.npc = {
    model = 'a_m_m_farmer_01',
    coords = vec4(2482.7590, 4696.1738, 33.9169, 38.3337),
    blip = {
        sprite = 141,
        color = 46,
        scale = 0.75,
        name = 'Leiteiro'
    }
}

Leiteiro.process = {
    coords = vec3(2485.1252, 4700.2861, 33.9455),
    -- A zona cobre a frente da maquina; o servidor ainda exige proximidade
    -- antes de permitir o envase.
    size = vec3(4.0, 4.0, 3.0),
    heading = 227.0257,
    machine = {
        model = 'prop_byard_machine02',
        coords = vec4(2485.1252, 4700.2861, 33.0, 227.0257)
    },
    label = 'Envasar leite'
}

Leiteiro.delivery = {
    coords = vec3(1705.7074, 4925.9517, 42.0637),
    locations = {
        vec3(1964.6068, 3747.6074, 32.3438),
        vec3(1705.7074, 4925.9517, 42.0637),
        vec3(542.0803, 2666.0879, 42.1565)
    },
    boxesPerStore = { min = 2, max = 4 },
    size = vec3(3.0, 3.0, 3.0),
    heading = 55.0,
    label = 'Entregar caixas de leite'
}

Leiteiro.vehicle = {
    model = 'boxville2',
    spawn = vec4(2489.5693, 4709.5898, 34.0368, 37.0164),
    platePrefix = 'LEITE',
    primaryColor = 111,
    secondaryColor = 111,
    maxBoxes = 80,
    loadDistance = 6.5,
    spawnClearRadius = 4.0
}

Leiteiro.props = {
    box = {
        model = 'prop_cs_cardbox_01',
        bone = 28422,
        offset = vec3(0.0, -0.04, -0.17),
        rotation = vec3(0.0, 0.0, 0.0)
    }
}

Leiteiro.cowModels = { 'a_c_cow' }

Leiteiro.cows = {
    vec4(2442.145, 4796.176, 34.65491, 280.6299),
    vec4(2442.923, 4794.514, 34.67175, 289.1339),
    vec4(2443.793, 4793.09, 34.6886, 297.6378),
    vec4(2458.035, 4779.771, 34.52014, 289.1339),
    vec4(2459.393, 4778.07, 34.5033, 294.8032),
    vec4(2460.461, 4776.778, 34.4696, 291.9685),
    vec4(2473.991, 4763.104, 34.30115, 300.4724),
    vec4(2475.099, 4761.864, 34.30115, 300.4724),
    vec4(2476.272, 4760.466, 34.30115, 300.4724),
    vec4(2491.938, 4762.998, 34.33484, 14.17323),
    vec4(2493.494, 4764.356, 34.36853, 17.00787),
    vec4(2494.576, 4765.596, 34.38538, 11.33858),
    vec4(2504.532, 4748.954, 34.30115, 107.7165),
    vec4(2503.49, 4750.286, 34.30115, 102.0472),
    vec4(2501.96, 4751.736, 34.30115, 104.8819),
    vec4(2515.029, 4737.007, 34.30115, 17.00787),
    vec4(2516.848, 4738.233, 34.30115, 19.84252),
    vec4(2518.365, 4739.71, 34.30115, 22.67716),
    vec4(2443.094, 4731.824, 34.2843, 107.7165),
    vec4(2440.958, 4732.971, 34.2843, 107.7165),
    vec4(2439.613, 4734.396, 34.2843, 104.8819),
    vec4(2421.547, 4762.154, 34.30115, 198.4252),
    vec4(2420.031, 4761.046, 34.30115, 201.2598),
    vec4(2418.58, 4759.741, 34.30115, 198.4252),
    vec4(2401.134, 4781.657, 34.70544, 65.19685),
    vec4(2399.38, 4780.207, 34.67175, 56.69291),
    vec4(2397.771, 4778.848, 34.62122, 62.36221)
}
