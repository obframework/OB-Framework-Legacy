OBPoliceConfig = {
    -- Chave da organizacao/permissao criada no adminorg.
    Permission = 'police',
    RequireDuty = true,

    InteractionDistance = 3.0,
    EscortBreakDistance = 12.0,
    EscortKey = 'H',

    ConsentSearch = {
        RequestTimeoutSeconds = 15,
        ViewTimeoutSeconds = 120,
    },

    Takedown = {
        -- Exige corrida + pulo + Shift + E. A janela curta deixa apertar E
        -- durante o pulo sem transformar a derrubada em uma acao de longe.
        Distance = 1.10,
        MinimumSpeed = 2.5,
        MinimumForwardDot = 0.80,
        RequireSprint = true,
        SprintWindowMs = 850,
        RequireJump = true,
        JumpWindowMs = 650,
        CooldownMs = 15000,
        RagdollMs = 3500,
        AnimationDurationMs = 3000,
        Animation = {
            dict = 'missmic2ig_11',
            attacker = 'mic_2_ig_11_intro_goon',
            victim = 'mic_2_ig_11_intro_p_one',
        },
    },

    Items = {
        Handcuffs = 'handcuffs',
        Key = 'handcuff_key',
        Lockpicks = {
            lockpick = true,
            advanced_lockpick = true,
        },
    },

    Lockpick = {
        TimeoutMs = 25000,
        MinimumSuccessMs = 1000,
        -- Usos por ferramenta definidos em ob_inventory/data/items.lua (maxUses).
        Difficulty = {
            lockpick = { steps = 7, speed = 2.35, tolerance = 0.065 },
            advanced_lockpick = { steps = 6, speed = 2.05, tolerance = 0.08 },
        },
    },

    CuffAnimation = {
        dict = 'mp_arresting',
        clip = 'idle',
        flag = 49,
    },

    CuffActionAnimation = {
        dict = 'mp_arresting',
        clip = 'a_uncuff',
        duration = 1300,
        flag = 49,
    },

    -- Modelo nativo do GTA: funciona sem depender do stream de outro recurso.
    CuffProp = {
        enabled = true,
        model = 'p_cs_cuffs_02_s',
        bone = 18905, -- SKEL_L_Hand
        position = { x = 0.0, y = 0.07, z = 0.03 },
        rotation = { x = 10.0, y = 115.0, z = -65.0 },
    },

    EscortOfficerAnimation = {
        dict = 'amb@world_human_drinking@coffee@female@base',
        clip = 'base',
        flag = 50,
    },
}
