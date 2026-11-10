OBMoneyWash = {
    Command = 'lavagemeditor',
    AdminPermission = 'world.shops',
    DirtyAccount = 'black_money',
    CleanAccount = 'money',
    Default = {
        label = 'Lavagem de dinheiro',
        commissionPercent = 40,
        durationSeconds = 60,
        minimumAmount = 100,
        maximumAmount = 1000000,
        pedModel = 's_m_m_highsec_01',
        pedScenario = 'WORLD_HUMAN_CLIPBOARD',
        machineModel = 'bkr_prop_prtmachine_dryer',
        machineOpenModel = 'bkr_prop_prtmachine_dryer_op',
        machineSpinModel = 'bkr_prop_prtmachine_dryer_spin',
    },
    InteractionDistance = 2.4,
    -- A zona acompanha o ponto da animacao. O raio facilita localizar o alvo,
    -- enquanto a distancia de interacao continua curta.
    MachineTargetRadius = 1.6,
    MachineInteractionDistance = 1.35,
    ServerDistanceTolerance = 4.5,
    MachineServerDistanceTolerance = 2.0,
    StreamInDistance = 90.0,
    StreamOutDistance = 115.0,
    ReservationSeconds = 120,
    -- Ajustes aplicados apenas ao botao de captura da maquina.
    -- Depois da captura, X/Y/Z/rotacao podem ser digitados no editor.
    MachineCaptureZOffset = -1.0,
    MachineCaptureHeadingOffset = 180.0,
    HandMoneyProp = 'prop_money_bag_01',
    MachineAnimation = {
        dictionary = 'bkr_mp_biker_printingmachines',
        clip = 'bkr_prop_prtmachine_dryer_spin',
    },
}

