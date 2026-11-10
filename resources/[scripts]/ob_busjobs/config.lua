Config = {}

Config.Debug = false
Config.UseTarget = true
Config.MoneyType = 'money'
Config.EconomyIntegration = false

-- Deixe false para ser um trabalho civil. Ative se somente quem tiver job "bus" puder trabalhar.
Config.Job = { requireJob = false, name = 'bus' }

Config.Boss = {
    pedModel = 's_m_m_gentransport',
    coords = vector4(445.56, -594.92, 28.5, 350.88),
    scenario = 'WORLD_HUMAN_CLIPBOARD',
    interactionDistance = 3.0,
    blip = { enabled = true, sprite = 513, color = 7, scale = 0.75, name = 'Central de Onibus' }
}

Config.Vehicle = {
    spawn = vector4(445.59, -588.06, 28.51, 269.4),
    warpIntoVehicle = true,
    fuel = 100.0,
    deleteOnShiftEnd = true,
    platePrefix = 'BUS'
}

-- Cada onibus libera a sua propria linha. requiredLevel libera o veiculo pelo nivel do motorista.
Config.Vehicles = {
    { model = 'bus', label = 'Onibus Urbano', image = 'vehicles/bus.png', seats = 16, rent = 100, requiredLevel = 1, fareMultiplier = 1.00, routeId = 'urbana' },
    { model = 'airbus', label = 'Airbus Metropolitano', image = 'vehicles/airbus.png', seats = 20, rent = 220, requiredLevel = 5, fareMultiplier = 1.20, routeId = 'metropolitana' },
    { model = 'coach', label = 'Coach Expresso', image = 'vehicles/coach.png', seats = 18, rent = 360, requiredLevel = 8, fareMultiplier = 1.45, routeId = 'expresso' }
}

Config.BusStyle = { primaryColor = 5, secondaryColor = 5, pearlColor = 5, wheelColor = 0, dirtLevel = 0.0 }

Config.Ride = {
    pickupDistance = 55.0,
    -- O circulo no chao e a propria area de interacao: 10 m de raio.
    -- Assim o E nao aparece fora da area que o motorista esta vendo.
    pickupStopDistance = 10.0,
    dropoffDistance = 55.0,
    dropoffStopDistance = 10.0,
    markerDrawDistance = 85.0,
    markerDiameter = 20.0,
    markerHeight = 0.95,
    instructionDuration = 12000,
    interactionMaxSpeedKmh = 8.0,
    passengerWarpDistance = 12.0,
    passengerBoardTimeoutMs = 1800,
    serverFinishMaxDistance = 85.0,
    minRideSeconds = 0,
    passengers = { min = 1, max = 1 },
    payout = { base = 160, distanceMultiplier = 0.50, min = 120, max = 2200 }
}

-- Onibus nao usa taximetro nem recebe chamadas pelo aplicativo de taxi.
Config.Meter = { enabled = false, requireAppCall = false }

-- Cada onibus recebe somente a sua linha.
Config.CityTabs = {
    { id = 'urbana', label = 'Linha Urbana', vehicleModel = 'bus', minLevel = 1, fareMultiplier = 1.00, xpMultiplier = 1.00 },
    { id = 'metropolitana', label = 'Linha Metropolitana', vehicleModel = 'airbus', minLevel = 5, fareMultiplier = 1.20, xpMultiplier = 1.20 },
    { id = 'expresso', label = 'Linha Expresso Norte', vehicleModel = 'coach', minLevel = 8, fareMultiplier = 1.45, xpMultiplier = 1.45 }
}

-- Mantido vazio somente para compatibilidade com instalacoes que chamavam a tabela antiga.
Config.CallPools = {}

Config.LevelUnlocks = {
    [5] = { 'Linha Metropolitana e Airbus Metropolitano' },
    [8] = { 'Linha Expresso Norte e Coach Expresso' }
}

Config.XP = { rideComplete = 130, levelStep = 850, maxLevel = 100 }
Config.UI = { command = 'bus', keybind = 'F6', callsCommand = 'busrotas', callsKeybind = 'O' }

-- Cole aqui o link normal do YouTube (watch?v=...) ou um link /embed/.
Config.Tutorial = { youtubeUrl = '', title = 'Tutorial do trabalho de onibus' }

Config.PedModels = {
    'a_m_m_business_01', 'a_f_y_business_04', 'a_m_y_beachvesp_01', 'a_f_y_tourist_01',
    'a_f_y_vinewood_01', 'a_m_y_hipster_01', 'a_f_y_hipster_02', 'a_m_m_soucent_02'
}
Config.PedBlacklistModels = {}
Config.CustomerNames = { 'Passageiros aguardando', 'Grupo de estudantes', 'Funcionarios da cidade', 'Turistas', 'Moradores locais', 'Passageiros da rodoviaria' }

-- Cada linha percorre as paradas em sequencia. Em cada ponto um passageiro entra,
-- desce na proxima parada e a linha recomeca automaticamente ao chegar ao fim.
Config.Routes = {
    urbana = {
        stops = {
            vector4(303.92, -766.28, 29.31, 256.12), vector4(114.26, -781.23, 31.41, 157.4),
            vector4(-505.95, 23.29, 44.78, 185.54), vector4(-694.55, -4.33, 38.26, 198.11),
            vector4(-931.47, -123.26, 37.76, 208.75), vector4(-1528.4, -464.87, 35.41, 216.19),
            vector4(-1474.82, -633.75, 30.64, 33.81), vector4(-681.81, -378.59, 34.27, 338.15),
            vector4(-1169.42, -1474.56, 4.38, 303.66), vector4(-691.55, -670.43, 30.88, 0.05),
            vector4(-504.54, -670.74, 33.09, 359.55), vector4(-176.25, -819.69, 31.09, 249.15),
            vector4(356.8, -1067.24, 29.56, 358.5), vector4(788.07, -775.43, 26.42, 89.13),
            vector4(-110.73, -1686.69, 29.31, 232.34), vector4(-1026.65, -2736.74, 20.17, 331.14),
            vector4(-138.05, -1992.4, 22.81, 357.71), vector4(956.88, 124.86, 80.99, 50.44),
            vector4(-557.27, -848.82, 27.67, 7.73), vector4(432.23, -641.2, 28.72, 92.29)
        }
    },
    metropolitana = {
        stops = {
            vector4(114.39, -781.56, 31.41, 157.07), vector4(-110.73, -1686.69, 29.31, 232.34),
            vector4(-1026.65, -2736.74, 20.17, 331.14), vector4(-138.05, -1992.4, 22.81, 357.71),
            vector4(357.38, -1067.11, 29.56, 356.5), vector4(788.22, -775.09, 26.43, 88.7),
            vector4(956.88, 124.86, 80.99, 50.44), vector4(1279.02, 2693.0, 37.61, 180.19),
            vector4(1904.35, 3745.13, 32.37, 30.63), vector4(1681.28, 4828.05, 42.05, 93.05),
            vector4(1634.95, 6425.32, 27.92, 166.19), vector4(-216.92, 6175.77, 31.2, 226.68),
            vector4(-1533.09, 4994.2, 62.15, 228.94), vector4(-2241.53, 4311.27, 47.96, 240.63),
            vector4(-3125.69, 1125.79, 20.61, 264.6), vector4(-1730.9, -707.79, 10.09, 323.87),
            vector4(-1169.94, -1474.87, 4.38, 303.04), vector4(-557.27, -848.82, 27.67, 7.73),
            vector4(-249.28, -886.85, 30.6, 340.17), vector4(432.23, -641.2, 28.72, 92.29)
        }
    },
    expresso = {
        stops = {
            vector4(1634.95, 6425.32, 27.92, 166.19), vector4(-216.92, 6175.77, 31.2, 226.68),
            vector4(-1533.09, 4994.2, 62.15, 228.94), vector4(-2241.53, 4311.27, 47.96, 240.63),
            vector4(-3125.69, 1125.79, 20.61, 264.6), vector4(-1730.9, -707.79, 10.09, 323.87),
            vector4(-1169.94, -1474.87, 4.38, 303.04), vector4(-557.27, -848.82, 27.67, 7.73),
            vector4(-249.28, -886.85, 30.6, 340.17), vector4(432.23, -641.2, 28.72, 92.29),
            vector4(1279.02, 2693.0, 37.61, 180.19), vector4(1681.28, 4828.05, 42.05, 93.05),
            vector4(1904.35, 3745.13, 32.37, 30.63), vector4(956.88, 124.86, 80.99, 50.44),
            vector4(788.22, -775.09, 26.43, 88.7), vector4(357.38, -1067.11, 29.56, 356.5),
            vector4(-138.05, -1992.4, 22.81, 357.71), vector4(-1026.65, -2736.74, 20.17, 331.14),
            vector4(-110.73, -1686.69, 29.31, 232.34), vector4(114.39, -781.56, 31.41, 157.07)
        }
    }
}

Config.Text = {
    interaction = '[E] Central de Onibus', noSpace = 'Sem vaga para spawn do onibus.',
    vehicleAlready = 'Voce ja esta em turno com um onibus.', shiftStarted = 'Turno iniciado. Escolha uma rota.',
    shiftStopped = 'Turno finalizado.', rideDeclined = 'Rota recusada. Escolha outra rota.',
    rideAccepted = 'Linha selecionada. Va ate a primeira parada.', pickupHint = '[E] Pare o onibus para embarcar passageiro',
    dropHint = '[E] Pare o onibus para desembarcar passageiro', rideDone = 'Parada concluida. A proxima ja foi marcada.',
    notInTaxi = 'Voce precisa estar no onibus do turno.', noSeat = 'Nao ha assentos livres no onibus.',
    noActiveRide = 'Voce nao tem rota ativa.', offerTitle = 'Nova rota de onibus', offerAccept = 'Iniciar rota',
    offerDecline = 'Recusar', menuStart = 'Iniciar turno', menuStop = 'Finalizar turno',
    menuPanel = 'Abrir painel', menuHelp = 'Como funciona',
    help = 'Escolha um onibus, inicie o turno e selecione uma linha com O. Em cada parada, use E para embarcar e desembarcar passageiros. A linha se repete ate voce escolher outra.'
}
