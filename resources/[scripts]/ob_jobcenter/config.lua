OBJobCenterConfig = {
    Name = 'Central de Empregos',

    Location = {
        coords = vec4(-265.06, -963.67, 31.22, 205.0),
        npcModel = 'a_f_y_business_02',
        scenario = 'WORLD_HUMAN_CLIPBOARD',
        spawnDistance = 100.0,
        interactionDistance = 3.0,
    },

    Blip = {
        enabled = true,
        sprite = 407,
        colour = 3,
        scale = 0.75,
        shortRange = true,
    },

    -- A chave precisa ser igual ao nome interno criado no /adminorg.
    -- Organizacoes inexistentes, ilegais ou desativadas nunca podem contratar.
    Jobs = {
        {
            key = 'police',
            fallbackLabel = 'Policia',
            description = 'Atendimento de ocorrencias e seguranca publica.',
            tag = 'SEGURANCA',
        },
        {
            key = 'ambulance',
            fallbackLabel = 'Medico',
            description = 'Resgate, estabilizacao e atendimento hospitalar.',
            tag = 'SAUDE',
        },
        {
            key = 'mechanic',
            fallbackLabel = 'Mecanico',
            description = 'Manutencao, reparo e suporte automotivo.',
            tag = 'SERVICOS',
        },
    },

    MinimumStaySeconds = 24 * 60 * 60,
    LeaveBlacklistSeconds = 60 * 60,

    Rules = {
        'Ao entrar, voce recebe sempre o cargo inicial definido pela organizacao.',
        'O vinculo deve ser mantido por no minimo 24 horas antes de uma saida voluntaria.',
        'Depois de sair, existe uma espera de 1 hora para ingressar em outra organizacao.',
        'Cada personagem pode fazer parte de apenas uma organizacao por vez.',
        'Respeite a hierarquia, os protocolos internos e utilize os recursos do trabalho apenas em servico.',
        'Abuso de cargo ou equipamentos pode resultar em remocao e bloqueio administrativo maior.',
    },
}
