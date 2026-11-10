Trucker = {}

Trucker.npc = {
    model = 's_m_m_trucker_01',
    coords = vec4(1208.6292, -3115.4504, 5.5403, 94.5940),
    scenario = 'WORLD_HUMAN_CLIPBOARD',
    blip = { sprite = 477, color = 5, scale = 0.78, name = 'Transportadora' },
}

Trucker.group = {
    maxMembers = 4,
    inviteDistance = 20.0,
    inviteSeconds = 30,
}

Trucker.progress = {
    maxLevel = 30,
    levelStep = 900,
    skillMax = 7,
    -- Um ponto por nivel apos o primeiro; no nivel 29 todas as quatro
    -- habilidades podem estar no maximo. O nivel 30 funciona como prestigio.
    pointsPerLevel = 1,
}

Trucker.skills = {
    distance = {
        label = 'Distancia',
        description = 'Aumenta o alcance maximo das ofertas. No grupo vale a media dos integrantes.',
        -- O indice zero permite iniciar o emprego antes de distribuir pontos.
        kilometers = { [0] = 2.0, 3.0, 5.0, 7.0, 9.0, 12.0, 16.0, 25.0 },
    },
    cargo = {
        label = 'Licencas de carga',
        description = 'Libera cargas especiais. Em grupo, somente a habilidade do lider e exigida.',
    },
    care = {
        label = 'Cuidado com a carga',
        description = 'Aumenta o bonus individual pela integridade da carreta.',
        bonusPerPoint = 0.025,
    },
    efficiency = {
        label = 'Eficiencia',
        description = 'Aumenta o pagamento e o XP individual.',
        moneyPerPoint = 0.02,
        xpPerPoint = 0.02,
    },
}

Trucker.depot = {
    truckSpawns = {
        vec4(1248.3528, -3135.4004, 5.7810, 276.9203),
        vec4(1248.9089, -3142.5271, 5.8196, 274.2104),
    },
    trailerSpawns = {
        vec4(1066.1355, -3185.3774, 5.9027, 359.8207),
        vec4(1062.6958, -3184.7854, 5.9015, 1.6156),
    },
    returnArea = {
        coords = vec3(1112.4523, -3142.2859, 5.9008),
        radius = 20.0,
        groundOffset = -0.30,
        markerType = 27, -- MarkerTypeHorizontalSplitArrowCircle
    },
    cargoCenter = vec3(1064.4, -3185.0, 5.9),
    truckClearRadius = 4.0,
    -- As duas vagas de carreta ficam lado a lado; um raio maior bloquearia
    -- indevidamente a segunda vaga mesmo sem colisao entre os modelos.
    trailerClearRadius = 2.25,
    -- Checagem por faixa: comprida no sentido da vaga e estreita nas laterais,
    -- para detectar um veiculo ainda saindo sem bloquear a vaga vizinha.
    slotSafety = {
        truck = { length = 16.0, width = 3.5, height = 5.0 },
        trailer = { length = 22.0, width = 3.5, height = 5.0 },
        reservationMs = 15000,
    },
    interactionDistance = 4.0,
    drawDistance = 120.0,
}

-- A porcentagem de cada cavalo pode ser alterada livremente. Nao precisa
-- somar exatamente 100: o servidor usa esses valores como pesos relativos.
Trucker.trucks = {
    { model = 'packer', label = 'MTL Packer', chance = 25 },
    { model = 'phantom', label = 'JoBuilt Phantom', chance = 35 },
    { model = 'hauler', label = 'JoBuilt Hauler', chance = 25 },
    { model = 'hauler2', label = 'JoBuilt Hauler Custom', chance = 15 },
}

-- chance controla com que frequencia o tipo aparece nas 40 ofertas.
-- requiredCargo e o numero de pontos de Licencas de carga exigido do lider.
Trucker.cargoTypes = {
    { id = 'container', model = 'docktrailer', label = 'Container portuario', chance = 20, requiredCargo = 0, multiplier = 1.00 },
    { id = 'general', model = 'trailers', label = 'Carga geral', chance = 20, requiredCargo = 0, multiplier = 1.00 },
    { id = 'logs', model = 'trailerlogs', label = 'Madeira', chance = 14, requiredCargo = 1, multiplier = 1.12 },
    { id = 'refrigerated', model = 'trailers2', label = 'Carga refrigerada', chance = 14, requiredCargo = 2, multiplier = 1.22 },
    { id = 'industrial', model = 'trailers3', label = 'Equipamentos industriais', chance = 12, requiredCargo = 3, multiplier = 1.32 },
    { id = 'retail', model = 'trailers4', label = 'Mercadorias de alto valor', chance = 11, requiredCargo = 4, multiplier = 1.45 },
    { id = 'fragile', model = 'tr4', label = 'Carga fragil especial', chance = 9, requiredCargo = 6, multiplier = 1.65 },
}

Trucker.offers = {
    count = 40,
    refreshSeconds = 120,
    minimumPerDistanceGroup = 5,
    roadDistanceFactor = 1.18,
    payPerKm = 1150,
    minimumPay = 1200,
    xpPerKm = 95,
    minimumXp = 120,
}

Trucker.payment = {
    groupBonusPerExtraMember = 0.08,
    maxGroupBonus = 0.24,
    perfectCargoBonus = 0.25,
    -- A carreta so e perdida quando a integridade realmente chega a zero.
    destroyedBodyHealth = 0.0,
    -- O body health nativo cai de forma muito agressiva em carretas. Somente
    -- 20% dessa perda vira dano de carga (uma queda bruta de 49 vira 9,8%).
    damageToIntegrity = 0.20,
    minimumDeliverySeconds = 45,
}

-- Os pontos ficam separados por faixa para facilitar a manutencao. A distancia
-- final da oferta e calculada pelo servidor a partir do patio de cargas.
Trucker.distanceGroups = {
    short = {
        label = 'Curta',
        locations = {
            { label = 'Terminal de Elysian Island', coords = vec3(1191.21, -3254.81, 7.10) },
            { label = 'Armazem de Cypress Flats', coords = vec3(1028.18, -2514.35, 28.30) },
            { label = 'Deposito de La Mesa', coords = vec3(814.42, -2135.15, 29.29) },
            { label = 'Patio de Rancho', coords = vec3(491.02, -1974.32, 24.90) },
            { label = 'Carga do Aeroporto', coords = vec3(-1027.35, -2730.37, 13.76) },
            { label = 'Centro de distribuicao', coords = vec3(1213.45, -1262.31, 35.23) },
        },
    },
    medium = {
        label = 'Media',
        locations = {
            { label = 'Casino', coords = vec3(974.03, 3.90, 81.04) },
            { label = 'Posto da Route 15', coords = vec3(2551.89, 438.54, 108.45) },
            { label = 'Usina Palmer-Taylor', coords = vec3(2790.15, 1408.84, 24.44) },
            { label = 'Rex Diner', coords = vec3(2525.09, 2625.93, 37.94) },
            { label = 'Cimento Harmony', coords = vec3(302.30, 2833.88, 43.45) },
            { label = 'Reciclagem Cat-Claw', coords = vec3(2327.29, 3138.91, 48.17) },
        },
    },
    long = {
        label = 'Longa',
        locations = {
            { label = 'Chumash Plaza', coords = vec3(-3169.63, 1102.37, 20.74) },
            { label = 'Fort Zancudo', coords = vec3(-1664.99, 3121.59, 31.72) },
            { label = 'Humane Labs', coords = vec3(3640.62, 3766.41, 28.52) },
            { label = 'YouTool', coords = vec3(2672.65, 3517.07, 52.71) },
            { label = 'Union Grain', coords = vec3(2895.51, 4381.80, 50.38) },
            { label = 'Ace Liquor', coords = vec3(1374.99, 3611.88, 34.89) },
        },
    },
    extreme = {
        label = 'Muito longa',
        locations = {
            { label = 'Wonderama Grapeseed', coords = vec3(1714.21, 4807.46, 41.80) },
            { label = 'Mercado de Paleto Bay', coords = vec3(-360.20, 6073.27, 31.50) },
            { label = 'Fabrica Cluckin Bell', coords = vec3(31.54, 6287.21, 31.24) },
            { label = 'Floresta de Paleto', coords = vec3(-802.16, 5409.08, 33.86) },
            { label = 'Hotel Jetty', coords = vec3(-2030.78, -262.44, 23.39) },
            { label = 'Clube Pacific Bluffs', coords = vec3(-2962.85, 60.93, 11.61) },
        },
    },
}

Trucker.distanceGroupOrder = { 'short', 'medium', 'long', 'extreme' }

Trucker.delivery = {
    checkpointType = 47,
    radius = 14.0,
    groundOffset = -0.30,
    serverRadius = 22.0,
    truckRadius = 45.0,
}

Trucker.tutorial = {
    youtubeUrl = '',
    title = 'Tutorial do trabalho de caminhoneiro',
}
