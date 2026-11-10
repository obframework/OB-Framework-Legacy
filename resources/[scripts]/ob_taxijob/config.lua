Config = {}

Config.Debug = false
Config.UseTarget = true
Config.MoneyType = 'money'
Config.EconomyIntegration = false

Config.Job = {
    requireJob = false,
    name = 'taxi'
}

Config.Boss = {
    pedModel = 'cs_manuel',
    coords = vector4(896.22, -177.72, 74.7, 232.65),
    scenario = 'WORLD_HUMAN_CLIPBOARD',
    interactionDistance = 3.0,
    blip = {
        enabled = true,
        sprite = 198,
        color = 5,
        scale = 0.75,
        name = 'Central de Táxi'
    }
}

Config.Vehicle = {
    model = 'taxi',
    spawn = vector4(900.15, -180.67, 73.87, 243.76),
    warpIntoVehicle = true,
    fuel = 100.0,
    deleteOnShiftEnd = true,
    platePrefix = 'TXI'
}

Config.Vehicles = {
    { model = 'taxi', label = 'Táxi', image = 'vehicles/taxi.png', seats = 4, rent = 25, requiredLevel = 1, fareMultiplier = 1.00 },
    { model = 'asterope', label = 'Asterope', image = 'vehicles/asterope.png', seats = 4, rent = 30, requiredLevel = 1, fareMultiplier = 1.02 },
    { model = 'premier', label = 'Premier', image = 'vehicles/premier.png', seats = 4, rent = 34, requiredLevel = 1, fareMultiplier = 1.04 },
    { model = 'washington', label = 'Washington', image = 'vehicles/washington.png', seats = 4, rent = 38, requiredLevel = 2, fareMultiplier = 1.07 },
    { model = 'fugitive', label = 'Fugitive', image = 'vehicles/fugitive.png', seats = 4, rent = 42, requiredLevel = 2, fareMultiplier = 1.10 },
    { model = 'tailgater', label = 'Tailgater', image = 'vehicles/tailgater.png', seats = 4, rent = 48, requiredLevel = 3, fareMultiplier = 1.14 },
     { model = 'windsor2', label = 'windsor2', image = 'vehicles/windsor2.png', seats = 4, rent = 54, requiredLevel = 4, fareMultiplier = 1.18 },
    { model = 'baller', label = 'Baller', image = 'vehicles/baller.png', seats = 4, rent = 62, requiredLevel = 5, fareMultiplier = 1.22 },
    { model = 'schafter2', label = 'Schafter', image = 'vehicles/schafter2.png', seats = 4, rent = 72, requiredLevel = 6, fareMultiplier = 1.28 },
    { model = 'superd', label = 'Super Diamond', image = 'vehicles/superd.png', seats = 4, rent = 85, requiredLevel = 7, fareMultiplier = 1.35 }
}

Config.TaxiStyle = {
    primaryColor = 88,
    secondaryColor = 64,
    pearlColor = 88,
    wheelColor = 64,
    dirtLevel = 0.0
}

-- Cole aqui o link normal do YouTube (watch?v=...) ou um link /embed/.
Config.Tutorial = { youtubeUrl = '', title = 'Tutorial do trabalho de taxi' }

Config.Ride = {
    pickupDistance = 40.0,
    pickupStopDistance = 10.0,
    dropoffDistance = 45.0,
    dropoffStopDistance = 11.0,
    serverFinishMaxDistance = 70.0,
    minRideSeconds = 18,
    callsPerCity = 8,
    passengers = {
        min = 1,
        max = 2
    },
    payout = {
        base = 120,
        distanceMultiplier = 0.40,
        min = 90,
        max = 1600
    }
}

Config.Meter = {
    enabled = true,
    requireAppCall = true,
    baseFare = 25,
    perKm = 35,
    perMinute = 6,
    minChargeDistance = 200.0,
    maxFare = 5000,
    confirmTimeout = 25
}

Config.CityTabs = {
    { id = 'los_santos', label = 'Los Santos', minLevel = 1, fareMultiplier = 1.00, xpMultiplier = 1.00 },
    { id = 'sandy_shores', label = 'Sandy Shores', minLevel = 3, fareMultiplier = 1.08, xpMultiplier = 1.10 },
    { id = 'paleto_bay', label = 'Paleto Bay', minLevel = 6, fareMultiplier = 1.20, xpMultiplier = 1.25 }
}

Config.CallPools = {
    { id = 'local', label = 'Moradores locais', minLevel = 1, fareMin = 55, fareMax = 105, xpMin = 55, xpMax = 95 },
    { id = 'commuters', label = 'Trabalhadores em trânsito', minLevel = 3, fareMin = 85, fareMax = 150, xpMin = 80, xpMax = 140 },
    { id = 'executive', label = 'Clientes executivos', minLevel = 6, fareMin = 135, fareMax = 240, xpMin = 140, xpMax = 230 },
    { id = 'premium', label = 'Clientes premium', minLevel = 8, fareMin = 190, fareMax = 300, xpMin = 185, xpMax = 290 },
    { id = 'vip', label = 'Clientes VIP', minLevel = 9, fareMin = 230, fareMax = 360, xpMin = 225, xpMax = 340 },
    { id = 'elite', label = 'Clientes de elite', minLevel = 10, fareMin = 280, fareMax = 430, xpMin = 270, xpMax = 420 }
}

Config.LevelUnlocks = {
    [8] = {
        'Liberar categoria: Clientes premium'
    },
    [9] = {
        'Liberar categoria: Clientes VIP'
    },
    [10] = {
        'Liberar categoria: Clientes de elite'
    }
}

Config.XP = {
    rideComplete = 120,
    levelStep = 800,
    maxLevel = 100
}

Config.UI = {
    command = 'taxi',
    keybind = 'F6',
    callsCommand = 'taxicalls',
    callsKeybind = 'O'
}

Config.PedModels = {
    'a_m_m_business_01',
    'a_m_y_business_02',
    'a_f_y_business_04',
    'a_m_y_beachvesp_01',
    'a_f_y_tourist_01',
    'a_f_y_vinewood_01',
    'a_m_y_vinewood_01',
    'a_f_y_hipster_02',
    'a_m_y_hipster_01',
    'a_m_m_bevhills_02',
    'a_f_m_bevhills_01',
    'a_m_m_soucent_02',
    'a_f_y_eastsa_03',
    'a_m_y_stwhi_02',
    'a_f_y_genhot_01'
}

Config.PedBlacklistModels = {
    'u_m_y_abner'
}

Config.CustomerNames = {
    'Ramon Silva',
    'Lucas Almeida',
    'Ana Souza',
    'Julia Santos',
    'Carlos Lima',
    'Pedro Nunes',
    'Mariana Rocha',
    'Joao Costa',
    'Gabriel Rezende',
    'Fernanda Araujo',
    'Roberto Moura',
    'Larissa Duarte',
    'Thiago Paes',
    'Bianca Teixeira'
}

Config.Routes = {
    los_santos = {
        pickup = {
            vector4(1131.52, -855.23, 53.57, 3.32),
            vector4(1231.03, -1305.17, 34.96, 257.42),
            vector4(1259.85, -1737.57, 50.02, 207.62),
            vector4(913.23, -2192.32, 30.49, 263.16),
            vector4(286.35, -2025.17, 19.34, 55.87),
            vector4(327.74, -1767.18, 28.94, 221.99),
            vector4(-83.01, -1580.73, 31.04, 320.82),
            vector4(-538.01, -944.62, 23.89, 91.11),
            vector4(-682.04, -1118.52, 14.63, 308.25),
            vector4(-1060.89, -271.33, 37.93, 201.75),
            vector4(-1282.44, -425.21, 34.66, 295.85),
            vector4(-1450.86, -678.43, 26.45, 301.22)
        },
        dropoff = {
            vector4(-569.59, -1084.78, 22.33, 161.06),
            vector4(-239.38, -990.13, 29.29, 245.29),
            vector4(-317.79, -297.73, 30.93, 149.98),
            vector4(-78.58, 271.89, 101.15, 172.07),
            vector4(-481.53, 117.88, 63.91, 354.24),
            vector4(-1200.08, -273.57, 37.79, 254.29),
            vector4(922.03, 46.71, 81.11, 34.44),
            vector4(1151.62, -330.86, 69.2, 279.13),
            vector4(110.95, -1088.25, 29.2, 342.52),
            vector4(-173.12, -1666.73, 33.33, 132.14),
            vector4(-1248.91, -1455.74, 4.35, 125.83),
            vector4(156.25, -1467.02, 29.14, 247.89)
        }
    },
    sandy_shores = {
        pickup = {
            vector4(1707.99, 3779.86, 34.74, 129.79),
            vector4(1737.53, 3326.81, 41.22, 188.09),
            vector4(1961.41, 3740.62, 32.34, 120.88),
            vector4(1365.76, 3609.09, 34.95, 200.13),
            vector4(1838.24, 3907.14, 33.47, 225.77),
            vector4(1541.07, 3781.91, 34.53, 95.12)
        },
        dropoff = {
            vector4(1881.33, 3688.58, 33.79, 209.11),
            vector4(2036.47, 3184.34, 45.18, 254.00),
            vector4(1527.59, 3183.48, 40.65, 109.24),
            vector4(1388.86, 3620.14, 34.89, 20.51),
            vector4(1695.11, 4925.72, 42.06, 139.26),
            vector4(1117.28, 2647.02, 38.14, 176.02)
        }
    },
    paleto_bay = {
        pickup = {
            vector4(-43.52, 6631.64, 31.08, 225.72),
            vector4(-307.57, 6221.61, 31.49, 133.11),
            vector4(-214.25, 6444.40, 31.30, 57.72),
            vector4(-99.71, 6473.27, 31.62, 127.80),
            vector4(-356.28, 6079.64, 31.49, 311.42),
            vector4(-149.41, 6322.67, 31.58, 42.18)
        },
        dropoff = {
            vector4(-257.93, 6348.62, 32.42, 319.21),
            vector4(-49.56, 6514.38, 31.49, 134.08),
            vector4(-133.28, 6394.78, 31.49, 88.47),
            vector4(-441.31, 6144.58, 31.48, 167.84),
            vector4(-4.83, 6628.80, 31.09, 13.52),
            vector4(-228.95, 6125.24, 31.51, 42.93)
        }
    }
}

Config.Text = {
    interaction = '[E] Taxi',
    noSpace = 'Sem vaga para spawn do taxi.',
    vehicleAlready = 'Voce ja esta em turno com um taxi.',
    shiftStarted = 'Turno iniciado. Aguarde chamadas de corrida.',
    shiftStopped = 'Turno finalizado.',
    rideDeclined = 'Corrida recusada. Aguarde a proxima chamada.',
    rideAccepted = 'Corrida aceita. Va buscar o cliente.',
    pickupHint = 'Pare o taxi para o cliente entrar.',
    dropHint = 'Leve o cliente ao destino e pare o taxi.',
    rideDone = 'Corrida concluida com sucesso.',
    notInTaxi = 'Voce precisa estar no taxi do turno.',
    noSeat = 'Nao ha assento livre para o cliente.',
    noActiveRide = 'Voce nao tem corrida ativa.',
    offerTitle = 'Nova corrida de taxi',
    offerAccept = 'Aceitar',
    offerDecline = 'Recusar',
    menuStart = 'Iniciar turno',
    menuStop = 'Finalizar turno',
    menuPanel = 'Abrir painel',
    menuHelp = 'Como funciona',
    help = 'Escolha um veiculo, inicie turno, aceite chamadas e leve o cliente ao destino para ganhar dinheiro e XP.'
}
