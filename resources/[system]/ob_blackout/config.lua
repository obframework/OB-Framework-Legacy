OBBlackoutConfig = {
    Automatic = {
        enabled = true,
        startHour = 21,
        startMinute = 0,
        endHour = 6,
        endMinute = 0,
        -- Uma unica decisao e sorteada ao entrar no periodo noturno. Com 10,
        -- em media apenas uma de cada dez noites tera apagao automatico.
        chancePercent = 10,
        checkIntervalMs = 2000,
    },
    Manual = {
        enabled = true,
        -- O item so inicia o procedimento no ponto correspondente. A distancia
        -- e conferida novamente no servidor quando o minigame termina.
        requireNearPointForItems = true,
        requireNightWindowForDisable = true,
        oneDisablePerNight = true,
        clearAtNextScheduleBoundary = true,
        requestTimeoutMs = 90000,
        minimumCompletionMs = 2500,
        interactionCooldownMs = 3000,
        drawDistance = 22.0,

        disablePoint = {
            coords = vec3(724.5807, 134.2914, 80.9564),
            heading = 66.9552,
            interactDistance = 2.2,
            marker = { type = 2, scale = vec3(0.24, 0.24, 0.18), color = { 255, 103, 44, 190 } },
        },
        restorePoint = {
            coords = vec3(713.01, 161.07, 81.10),
            heading = 239.88,
            interactDistance = 3.0,
            -- O primeiro modelo existe no Enhanced. O fallback preserva o
            -- ponto funcional em artifacts Legacy que nao possuem esse prop.
            objectModel = 'reh_prop_reh_b_computer_04a',
            fallbackObjectModel = 'prop_elecbox_12',
            objectCoords = vec3(713.9, 160.55, 79.75),
            objectHeading = 239.88,
            marker = { type = 2, scale = vec3(0.24, 0.24, 0.18), color = { 57, 221, 173, 190 } },
        },
    },
    Items = {
        disable = 'blackout_disruptor',
        restore = 'blackout_toolbox',
        consumeDisableOnSuccess = true,
        consumeRestoreOnSuccess = true,
    },
    Minigames = {
        disable = {
            title = 'INVASAO DA REDE ELETRICA',
            bars = 6,
            timeSeconds = 40,
            maxMistakes = 3,
            speed = 1.15,
            tolerance = 0.070,
        },
        restore = {
            title = 'RECALIBRAR CIRCUITOS',
            rows = 3,
            maxMultiplier = 5,
            timeSeconds = 45,
            maxAttempts = 4,
        },
    },
    Animations = {
        disable = {
            dict = 'amb@world_human_stand_mobile@male@text@base',
            clip = 'base',
            flag = 49,
            propModel = 'prop_cs_tablet',
            bone = 60309,
            offset = vec3(0.03, 0.002, -0.01),
            rotation = vec3(10.0, 160.0, 0.0),
        },
        restore = {
            dict = 'mini@repair',
            clip = 'fixing_a_ped',
            flag = 1,
        },
    },
    Notifications = {
        announceChanges = true,
        blackout = 'A energia da cidade foi interrompida.',
        restored = 'A energia da cidade foi restabelecida.',
    },
    Messages = {
        alreadyActive = 'A energia ja esta desligada.',
        alreadyRestored = 'A energia ja esta ligada.',
        alreadyUsedTonight = 'Esta noite ja houve uma invasao da rede eletrica.',
        notInWindow = 'O terminal de invasao so responde entre 19:00 e 06:00.',
        needDisableItem = 'Voce precisa de um Disruptor de Rede.',
        needRestoreItem = 'Voce precisa de uma Caixa de Ferramentas Eletrica.',
        needBeNearDisable = 'Va ate o terminal de invasao para usar o disruptor.',
        needBeNearRestore = 'Va ate o painel eletrico para usar a caixa de ferramentas.',
        minigameFailed = 'O procedimento falhou. O item nao foi consumido.',
        requestExpired = 'O procedimento expirou. Tente novamente.',
        unavailable = 'O sistema de energia esta indisponivel.',
    },
    Integrations = {
        -- Reservado para o futuro ob_phone e sistema de radio. O estado e os
        -- eventos ja sao publicados, mas nenhum recurso e bloqueado agora.
        disablePhone = false,
        limitRadio = false,
        radioRange = 500.0,
    },

    WorldEffects = {
        -- No Enhanced alguns semaforos continuam com a textura acesa mesmo
        -- durante SetArtificialLightsState. Estes modelos recebem tambem o
        -- desligamento de luz por entidade enquanto estiverem carregados.
        disableTrafficLights = true,
        trafficLightScanRadius = 220.0,
        trafficLightScanIntervalMs = 1500,
        trafficLightModels = {
            'prop_traffic_01a', 'prop_traffic_01b', 'prop_traffic_01d',
            'prop_traffic_02a', 'prop_traffic_02b',
            'prop_traffic_03a', 'prop_traffic_03b',
            'prop_traffic_lightset_01',
        },
        -- Fallback pelos hashes vistos no Enhanced. Eles correspondem a
        -- prop_traffic_01d, prop_traffic_03b e prop_traffic_03a.
        trafficLightHashes = { -655644382, 589548997, 865627822 },

        -- Afeta somente veiculos/peds de populacao ambiente sob controle deste
        -- cliente. Veiculos de jogadores, jobs e outros resources sao ignorados.
        npcDriversIgnoreLights = true,
        npcDriverScanRadius = 180.0,
        npcDriverScanIntervalMs = 1500,
        npcDriverStyle = 786475,
        npcDriverCruiseSpeed = 14.0,
        npcDriverAggressiveness = 0.35,
        normalNpcDriverStyle = 786603,

        -- A busca de pedestres usa amostras espaciais, nao GetGamePool('CPed'),
        -- para manter compatibilidade com Legacy e Enhanced.
        alertPedestrians = true,
        pedestrianScanIntervalMs = 650,
        pedestrianSearchRadius = 18.0,
        pedestrianAttentionDurationMs = 2800,
        pedestrianSeeingRange = 45.0,
        pedestrianHearingRange = 45.0,
        pedestrianFlashlightChance = 0.18,
    },
}
