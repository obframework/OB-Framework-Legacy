ORCoreConfig = {
    FrameworkName = 'OB Framework',
    CharacterSlots = 4,
    DefaultCharacterSlots = 1,
    MinimumAge = 18,
    -- Regra-base do servidor: cura passiva nativa do GTA fica desativada.
    DisableGtaHealthRecharge = true,
    -- A selecao de arma passa a ser responsabilidade do inventario da OB.
    DisableGtaWeaponWheel = true,
    -- Impede a camera cinematografica automatica quando o jogador fica parado,
    -- tanto a pe quanto dentro de um veiculo.
    DisableGtaIdleCamera = true,
    -- Permite dano entre jogadores. O GTA/FiveM trata jogadores como aliados
    -- enquanto friendly fire e ataque a aliados nao forem habilitados.
    EnablePvP = true,
    -- Comandos administrativos gratuitos, independentes da mecanica/garagem.
    VehicleTuning = {
        enabled = true,
        permission = 'or.admin', -- ACE; IsAdmin do core tambem tem acesso.
        adminPermission = 'vehicle.fix', -- Integra cargos se ob_admin estiver iniciado.
        cooldownMs = 2000,
    },
    PositionSaveInterval = 60000,
    SelectorBucketOffset = 20000,
    SelectorSpawn = { x = 195.17, y = -933.77, z = 29.7, heading = 144.5 },
    Progress = {
        DefaultDuration = 2500,
    },
    -- Mensagens de acao locais, usadas pelo comando /me. O servidor controla
    -- o texto e os clientes apenas desenham as mensagens recebidas.
    Me = {
        Duration = 10000,
        Distance = 20.0,
        MaxMessages = 3,
        MaxLength = 140,
    },
    -- Estado profissional basico do personagem. Fica no metadata para que os
    -- primeiros empregos civis possam funcionar sem depender de Qbox/QBCore
    -- nem criar uma tabela por emprego. Organizacoes e cargos dinamicos podem
    -- virar um modulo proprio quando o painel de organizacoes existir.
    Jobs = {
        Default = {
            name = 'unemployed',
            label = 'Desempregado',
            grade = 0,
            onDuty = false,
        },
        Definitions = {
            unemployed = { label = 'Desempregado', maxGrade = 0 },
            lumberjack = { label = 'Lenhador', maxGrade = 10 },
            leiteiro = { label = 'Leiteiro', maxGrade = 10 },
            garbage = { label = 'Lixeiro', maxGrade = 10 },
            bus = { label = 'Motorista de onibus', maxGrade = 10 },
            taxi = { label = 'Taxista', maxGrade = 10 },
            police = { label = 'Policia', maxGrade = 10 },
        },
    },
}
