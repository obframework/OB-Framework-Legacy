Lumberjack = {
    tutorial = { youtubeUrl = '', title = 'Tutorial do trabalho de lenhador' },
    -- A árvore continua rendendo madeira no inventário. O pagamento acontece
    -- apenas depois de carregar uma carga completa e descarregá-la na serraria.
    payment = { item = 'madeira', min = 1, max = 3 },
    economyIntegration = false,

    group = {
        maxMembers = 2,
        inviteDistance = 18.0,
        inviteSeconds = 30
    },

    -- Os pontos abaixo usam as arvores que ja existem no mapa. O cliente procura
    -- o tronco real mais proximo para corrigir pequenas diferencas de coordenada.
    worldProps = {
        searchRadius = 3.0,
        minTreeHeight = 3.0,
        cacheMs = 15000
    },

    truck = {
        model = 'mule3',
        spawn = vec4(-576.8314, 5329.3018, 70.2567, 342.7704),
        platePrefix = 'LENHA',
        -- O trabalhador carrega até 5 toras por vez; o caminhão leva a carga grande.
        maxWood = 30,
        carryMax = 5,
        loadBatch = 5,
        loadDistance = 6.0,
        spawnClearRadius = 4.0
    },

    sawmills = {
        {
            label = 'Serraria de Paleto',
            vehicleCoords = vec4(-684.1855, 5783.1704, 17.3310, 349.8727),
            interactionCoords = vec4(-689.1310, 5788.7124, 17.3310, 66.9709)
        },
        {
            label = 'Serraria do Leste',
            vehicleCoords = vec4(407.9882, 6628.8569, 28.2415, 29.5751),
            interactionCoords = vec4(411.5168, 6634.9390, 28.2430, 317.1230)
        },
        {
            label = 'Serraria de Paleto Norte',
            vehicleCoords = vec4(186.2549, 6395.0459, 31.3826, 116.3994),
            interactionCoords = vec4(179.9922, 6397.0645, 31.3499, 115.8350)
        }
    },

    sawmill = {
        -- Área de descarga ao lado da madeireira. Pode ser ajustada sem tocar no código.
        coords = vec3(-689.1310, 5788.7124, 17.3310),
        size = vec3(3.0, 3.0, 2.5),
        heading = 66.9709,
        vehicleDistance = 6.0,
        minLoadToDeliver = 30,
        -- Nível 1: aproximadamente 1.200 a 1.650 unidades monetárias por carga de 30.
        -- Nível 10: aproximadamente 3.900 a 5.360 pela mesma carga.
        paymentPerWood = { min = 40, max = 55 },
        blip = { sprite = 566, color = 47, scale = 0.75, name = 'Serraria - entrega de madeira' }
    },

    progress = {
        xpPerWood = 12,
        levelStep = 600,
        maxLevel = 10,
        paymentBonusPerLevel = 0.25,
        maxPaymentBonus = 2.25
    },

    start = vector3(-565.7485, 5325.9761, 73.5928),

    marker = {
        type = 20,
        scale = vec3(0.35, 0.35, 0.2),
        color = { r = 0, g = 150, b = 255, a = 140 },
        zOffset = -0.65,
        rotation = vec3(0.0, 0.0, 0.0)
    },

    npc = {
        model = 's_m_m_lathandy_01',
        coords = vec4(-565.7485, 5325.9761, 73.5928, 68.0312),
        blip = {
            sprite = 237,
            color = 25,
            scale = 0.8,
            name = 'Lenhador'
        }
    },
    
    weapons = { [GetHashKey('WEAPON_BATTLEAXE')] = true },
    
    trees = {
        vector4(-750.2374, 5487.6, 35.39636, 155.9055),
        vector4(-743.2352, 5484.343, 37.65417, 229.6063),
        vector4(-737.011, 5471.842, 39.42346, 195.5905),
        vector4(-735.455, 5494.365, 36.50842, 218.2677),
        vector4(-726.0923, 5498.163, 37.40149, 235.2756),
        vector4(-690.3297, 5525.104, 37.65417, 34.01575),
        vector4(-705.3626, 5488.497, 44.36047, 215.4331),
        vector4(-701.1693, 5490.382, 44.89966, 212.5984),
        vector4(-678.3165, 5528.98, 38.42932, 201.2598),
        vector4(-667.5428, 5498.558, 47.78101, 187.0866),
        vector4(-663.3362, 5497.134, 48.4718, 195.5905),
        vector4(-658.9319, 5525.499, 42.75977, 221.1024),
        vector4(-656.2549, 5536.352, 38.76636, 204.0945),
        vector4(-656.7297, 5532.132, 40.4176, 240.9449),
        vector4(-629.8681, 5533.78, 43.92236, 187.0866),
        vector4(-660.1318, 5490.198, 49.71863, 306.1417),
        vector4(-643.5692, 5461.477, 53.34143, 192.7559),
        vector4(-632.4396, 5466.514, 53.62781, 272.126),
        vector4(-627.9692, 5470.141, 53.45935, 42.51968),
        vector4(-625.2264, 5472.633, 53.4425, 45.35433),
        vector4(-653.1824, 5456.729, 51.82495, 238.1102),
        vector4(-639.5472, 5504.149, 51.28577, 283.4646),
        vector4(-634.7473, 5505.271, 51.21826, 311.811),
        vector4(-617.9868, 5488.325, 51.57214, 51.02362),
        vector4(-620.4923, 5498.321, 51.25208, 221.1024),
        vector4(-626.9275, 5527.292, 46.09595, 189.9213),
        vector4(-633.7055, 5562.725, 38.36194, 150.2362),
        vector4(-628.3253, 5563.925, 38.51355, 226.7717),
        vector4(-602.9275, 5564.136, 43.83813, 226.7717),
        vector4(-607.5428, 5547.745, 46.09595, 53.85827),
        vector4(-585.9824, 5546.268, 50.56116, 226.7717),
        vector4(-587.2615, 5542.167, 50.62854, 300.4724),
        vector4(-584.4659, 5568.989, 47.59558, 263.6221),
        vector4(-577.4637, 5527.846, 52.46521, 252.2835),
        vector4(-598.6285, 5474.136, 55.98682, 252.2835),
        vector4(-591.1385, 5495.13, 53.948, 272.126),
        vector4(-585.5472, 5491.701, 55.27917, 263.6221),
        vector4(-573.0989, 5508, 55.63293, 308.9764),
        vector4(-581.4198, 5471.499, 59.40735, 218.2677),
        vector4(-568.022, 5503.095, 57.31799, 280.6299),
        vector4(-556.4044, 5511.956, 59.67688, 286.2992),
        vector4(-577.6484, 5469.376, 60.3678, 167.2441),
        vector4(-555.4154, 5541.35, 59.49158, 280.6299),
    }
}
