Electrician = {}

Electrician.tutorial = { youtubeUrl = '', title = 'Tutorial do trabalho de eletricista' }

Electrician.group = {
    maxMembers = 2,
    inviteDistance = 18.0,
    inviteSeconds = 30,
}

Electrician.npc = {
    model = 's_m_m_dockwork_01',
    coords = vec4(741.7849, 137.6208, 80.6044, 237.5639),
    blip = { sprite = 354, color = 5, scale = 0.78, name = 'Eletricista' },
}

Electrician.vehicle = {
    model = 'utillitruck4',
    spawn = vec4(745.6130, 127.0730, 79.2862, 245.1660),
    platePrefix = 'ENERG',
    spawnClearRadius = 5.0,
    -- Os dois pontos sao calculados pelo tamanho real do modelo, um em cada lateral.
    sideMarkerGap = 0.45,
    sideMarkerY = 0.35,
    markerDrawDistance = 22.0,
    markerScale = 0.38,
}

Electrician.work = {
    servicesPerBatch = 5,
    interactionDistance = 2.4,
    serverDistance = 8.0,
    xpPerRepair = 30,
    payment = { min = 720, max = 980 },
    levelStep = 500,
    maxLevel = 10,
    paymentBonusPerLevel = 0.025,
    maxPaymentBonus = 0.225,
    minimumStepMs = 1800,
    sparkActivationDistance = 35.0,
    routeMarkerDistance = 45.0,
    stepTimeoutMs = 90000,
    sparkIntervalMs = 650,
    truckTaskDistance = 38.0,
}

-- Etapas compartilhadas: ambos podem executar, um de cada vez.
Electrician.steps = {
    { label = 'Abrir e isolar o painel', tool = 1 },
    { label = 'Reconectar os cabos', tool = 2 },
    { label = 'Regular e testar a tensao', tool = 3 },
}
Electrician.repairAnimation = { dict = 'mini@repair', clip = 'fixing_a_player' }

Electrician.tools = {
    [1] = {
        label = 'chave de fenda',
        model = 'prop_tool_screwdvr03',
        bone = 57005,
        offset = vec3(0.12, 0.02, -0.02),
        rotation = vec3(-90.0, 0.0, 10.0),
    },
    [2] = {
        label = 'alicate',
        model = 'prop_pliers_01',
        fallbackModel = 'prop_tool_pliers',
        bone = 57005,
        offset = vec3(0.11, 0.02, -0.01),
        rotation = vec3(-80.0, 0.0, 5.0),
    },
    [3] = {
        label = 'alicate de corte',
        model = 'prop_tool_pliers',
        fallbackModel = 'prop_pliers_01',
        bone = 57005,
        offset = vec3(0.11, 0.02, -0.01),
        rotation = vec3(-80.0, 0.0, 5.0),
    },
}

-- Minigames proprios em ui/repair.js: parafusos, cabos e tensao.

-- Posicoes reais extraidas dos YMAPs pelo CodeWalker em 2026-10-01.
-- Nao existe ponto obrigatorio para estacionar o caminhao. O GPS aponta para
-- search e o jogador pode parar onde for seguro.
-- search corresponde a origem EXATA do prop, nao a uma area aproximada.
-- Ainda requer teste no mapa customizado do servidor; nao cria props extras.
Electrician.tasks = {
    {
        -- CodeWalker: hw1_rd_strm_1.ymap; acesso: nodes496.ynd / 847.
        label = 'Caixa eletrica de Hawick', type = 'ground',
        search = vec3(327.4320, -115.6295, 66.9473), searchRadius = 2.0,
        models = { 'prop_elecbox_05a' }, zOffset = 0.75,
    },
    {
        -- CodeWalker: hw1_rd_strm_1.ymap; acesso: nodes496.ynd / 990.
        label = 'Caixa eletrica da Power Street', type = 'ground',
        search = vec3(476.9097, -37.1654, 78.7321), searchRadius = 2.0,
        models = { 'prop_elecbox_10' }, zOffset = 0.75,
    },
    {
        -- CodeWalker: id2_rd_strm_0.ymap; acesso: nodes465.ynd / 18.
        label = 'Caixa eletrica de La Mesa', type = 'ground',
        search = vec3(753.3926, -1019.8257, 25.4213), searchRadius = 2.0,
        models = { 'prop_elecbox_05a' }, zOffset = 0.75,
    },
    {
        -- CodeWalker: sc1_rd_strm_4.ymap; acesso: nodes432.ynd / 628.
        label = 'Caixa eletrica de Strawberry', type = 'ground',
        search = vec3(241.6609, -1305.3434, 28.4800), searchRadius = 2.0,
        models = { 'prop_elecbox_05a' }, zOffset = 0.75,
    },
    {
        -- CodeWalker: id2_rdb_critical_0.ymap; acesso: nodes466.ynd / 267.
        label = 'Poste de Mirror Park', type = 'aerial',
        search = vec3(1196.2573, -617.5300, 62.2351), searchRadius = 2.0,
        models = { 'prop_telegraph_01a' }, zOffset = 7.1,
    },
    {
        -- CodeWalker: id1_rd_critical_1.ymap; acesso: nodes402.ynd / 663.
        label = 'Poste de El Burro Heights', type = 'aerial',
        search = vec3(1218.0297, -1630.4416, 46.7307), searchRadius = 2.0,
        models = { 'prop_telegraph_01c' }, zOffset = 7.1,
    },
    {
        -- CodeWalker: sc1_rd_critical_2.ymap; acesso: nodes400.ynd / 217.
        label = 'Poste de Rancho', type = 'aerial',
        search = vec3(472.9486, -1909.3755, 24.0381), searchRadius = 2.0,
        models = { 'prop_telegraph_01c' }, zOffset = 7.1,
    },
}
