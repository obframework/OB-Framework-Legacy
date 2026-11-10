Dispatch = {}

Dispatch.maxActiveCalls = 40
Dispatch.defaultDuration = 90
Dispatch.cardDuration = 20
Dispatch.acceptKey = 'Y'
Dispatch.declineKey = 'N'
Dispatch.panelKey = 'F2'
Dispatch.requireDuty = true
Dispatch.phoneRequestCooldown = 45

-- Para criar um novo tipo, copie um bloco e altere grupos/aparencia.
-- Depois, outro recurso chama: exports.ob_dispatch:CreateAlert('tipo', dados)
Dispatch.types = {
    drug_sale = {
        code = '10-31', title = 'Venda de drogas', groups = { 'police' }, priority = 2,
        message = 'Denuncia de comercializacao de entorpecentes.',
        duration = 120, radius = 40.0, offsetMin = 12.0, offsetMax = 25.0, radiusOnly = true,
        blip = { sprite = 51, colour = 1, scale = 0.9 }, sound = true,
    },
    gunshot = {
        code = '10-71', title = 'Disparos de arma de fogo', groups = { 'police' }, priority = 3,
        message = 'Moradores relataram disparos de arma de fogo.',
        duration = 75, radius = 70.0, offsetMin = 10.0, offsetMax = 32.0,
        blip = { sprite = 313, colour = 1, scale = 1.0 }, sound = true,
    },
    lockpick_vehicle = {
        code = '10-66', title = 'Arrombamento de veiculo', groups = { 'police' }, priority = 2,
        message = 'Possivel tentativa de arrombamento de veiculo.',
        duration = 75, radius = 55.0, offsetMin = 8.0, offsetMax = 24.0,
        blip = { sprite = 225, colour = 5, scale = 0.9 }, sound = true,
    },
    lockpick_restraint = {
        code = '10-66', title = 'Arrombamento de algema', groups = { 'police' }, priority = 3,
        message = 'Possivel tentativa de romper uma algema.',
        duration = 75, radius = 45.0, offsetMin = 5.0, offsetMax = 18.0,
        blip = { sprite = 161, colour = 5, scale = 0.9 }, sound = true,
    },
    medical_emergency = {
        code = 'QRR', title = 'Emergencia medica', groups = { 'ambulance' }, priority = 3,
        message = 'Solicitacao de atendimento medico.', duration = 120, radius = 25.0,
        blip = { sprite = 153, colour = 1, scale = 1.0 }, sound = true,
    },
    traffic_accident = {
        code = '10-50', title = 'Acidente de transito', groups = { 'police', 'ambulance' }, priority = 2,
        message = 'Acidente com possiveis feridos.', duration = 120, radius = 35.0,
        blip = { sprite = 380, colour = 47, scale = 0.9 }, sound = true,
    },
    phone_police = {
        code = '190', title = 'Solicitacao policial', groups = { 'police' }, priority = 2,
        message = 'Cidadao solicitando atendimento policial pelo celular.',
        duration = 300, radius = 0.0, offsetMin = 0.0, offsetMax = 0.0, exclusive = true,
        blip = { sprite = 280, colour = 3, scale = 0.9 }, sound = true,
    },
    phone_medical = {
        code = '192', title = 'Solicitacao medica', groups = { 'ambulance' }, priority = 3,
        message = 'Cidadao solicitando atendimento medico pelo celular.',
        duration = 300, radius = 0.0, offsetMin = 0.0, offsetMax = 0.0, exclusive = true,
        blip = { sprite = 153, colour = 1, scale = 0.95 }, sound = true,
    },
}

Dispatch.gunshot = {
    enabled = true,
    cooldownSeconds = 25,
    reportChance = 100,
    ignoreOnDutyGroups = { 'police' },
    ignoredWeapons = {
        [joaat('WEAPON_UNARMED')] = true,
        [joaat('WEAPON_STUNGUN')] = true,
        [joaat('WEAPON_STUNGUN_MP')] = true,
        [joaat('WEAPON_FIREEXTINGUISHER')] = true,
        [joaat('WEAPON_PETROLCAN')] = true,
    },
    -- Exemplo: { coords = vector3(x, y, z), radius = 80.0 }
    ignoredZones = {},
}
