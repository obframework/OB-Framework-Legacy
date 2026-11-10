OBAnimationsConfig = {
    HandsUpKey = 'X',
    PointKey = 'B',
    MenuKey = 'F3',
    MenuCommand = 'emotes',

    Combat = {
        CrouchKey = 'LCONTROL',
        DisableCover = true,
        DisableFirearmMelee = true,
        ForceHoldAim = true,
        ReleaseAimWithMouse = true,
    },

    HandsUp = {
        dict = 'missminuteman_1ig_2',
        clip = 'handsup_base',
        flag = 49,
    },

    -- Uma entrada com dict/clip toca uma animacao. Uma entrada com steps toca
    -- varias animacoes em sequencia, permitindo criar combinacoes proprias.
    Emotes = {
        {
            id = 'dance_relaxed',
            label = 'Danca tranquila',
            category = 'Dancas',
            dict = 'anim@amb@nightclub@mini@dance@dance_solo@male@var_b@',
            clip = 'high_center',
            flag = 1,
        },
        {
            id = 'dance_party',
            label = 'Danca de festa',
            category = 'Dancas',
            dict = 'anim@amb@nightclub@dancers@podium_dancers@',
            clip = 'hi_dance_facedj_17_v2_male^5',
            flag = 1,
        },
        {
            id = 'dance_casual',
            label = 'Danca casual',
            category = 'Dancas',
            dict = 'anim@amb@nightclub@mini@dance@dance_solo@female@var_a@',
            clip = 'high_center',
            flag = 1,
        },
        {
            id = 'salute',
            label = 'Continencia',
            category = 'Gestos',
            dict = 'anim@mp_player_intuppersalute',
            clip = 'idle_a',
            flag = 49,
        },
        {
            id = 'wave',
            label = 'Acenar',
            category = 'Gestos',
            dict = 'anim@mp_player_intcelebrationmale@wave',
            clip = 'wave',
            flag = 49,
        },
        {
            id = 'thumbsup',
            label = 'Positivo',
            category = 'Gestos',
            dict = 'anim@mp_player_intcelebrationmale@thumbs_up',
            clip = 'thumbs_up',
            flag = 49,
        },
        {
            id = 'facepalm',
            label = 'Facepalm',
            category = 'Gestos',
            dict = 'anim@mp_player_intupperface_palm',
            clip = 'idle_a',
            flag = 49,
        },
        {
            id = 'crossarms',
            label = 'Bracos cruzados',
            category = 'Posturas',
            dict = 'amb@world_human_hang_out_street@female_arms_crossed@idle_a',
            clip = 'idle_a',
            flag = 49,
        },
        {
            id = 'lean',
            label = 'Descansar encostado',
            category = 'Posturas',
            dict = 'amb@world_human_leaning@male@wall@back@foot_up@idle_a',
            clip = 'idle_a',
            flag = 1,
        },
        {
            id = 'inspect',
            label = 'Observar e anotar',
            category = 'Sequencias',
            steps = {
                {
                    dict = 'amb@world_human_clipboard@male@idle_a',
                    clip = 'idle_c',
                    flag = 49,
                    duration = 2500,
                },
                {
                    dict = 'anim@mp_player_intcelebrationmale@thumbs_up',
                    clip = 'thumbs_up',
                    flag = 49,
                    duration = 1800,
                },
            },
        },
    },
}
