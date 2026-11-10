OBEvidenceConfig = {
    Permission = 'police',
    RequireDuty = true,

    EvidenceBagItem = 'empty_evidence_bag',
    CasingItem = 'casing_evidence',
    CasingProp = 'w_pi_singleshot_shell',
    CasingProps = {
        pistol = 'w_pi_singleshot_shell',
        smg = 'w_pi_singleshot_shell',
        rifle = 'w_pi_singleshot_shell',
        sniper = 'w_pi_singleshot_shell',
        mg = 'w_pi_singleshot_shell',
        shotgun = 'prop_sgun_casing',
    },
    CasingItems = {
        pistol = 'casing_pistol_evidence',
        smg = 'casing_smg_evidence',
        rifle = 'casing_rifle_evidence',
        shotgun = 'casing_shotgun_evidence',
        sniper = 'casing_sniper_evidence',
        mg = 'casing_mg_evidence',
    },
    ForensicKitItem = 'forensic_kit',
    ReportItem = 'forensic_report',
    FingerprintSampleItem = 'fingerprint_sample',
    FieldKits = {
        residue_test_kit = { kind = 'residue', label = 'Kit residual', retentionSeconds = 45 * 60 },
        chemical_test_kit = { kind = 'chemical', label = 'Kit quimico', contactSeconds = 60 * 60, useSeconds = 2 * 60 * 60 },
        fingerprint_collection_kit = { kind = 'fingerprint', label = 'Kit de digital' },
    },
    DrugLabels = {
        weed_bag = 'maconha',
        cocaine_bag = 'cocaina',
        meth_bag = 'metanfetamina',
    },

    CasingLifetimeSeconds = 45 * 60,
    ArchiveRetentionDays = 4,
    MaximumCasings = 250,
    -- Os estojos continuam logicos no servidor, mas cada jogador cria somente
    -- os props proximos. Isso evita centenas de entidades locais simultaneas.
    StreamCellSize = 40.0,
    PropStreamDistance = 45.0,
    MaximumRenderedCasings = 80,
    TargetStreamDistance = 12.0,
    MaximumTargetCasings = 24,
    ShotCooldownMs = 100,
    CollectDistance = 1.35,
    BulkCollectRadius = 2.0,
    BulkCollectMaximum = 12,
    AnalysisDistance = 2.5,

    -- Pontos provisórios de análise. Podem ser movidos sem alterar o restante
    -- do sistema de evidências.
    Labs = {
        { id = 'mission_row', label = 'Abrir laboratorio pericial', coords = vector3(459.7936, -989.5847, 24.9149) },
    },

    AmmoLabels = {
        pistol = 'calibre de pistola',
        smg = 'municao de submetralhadora',
        rifle = 'municao de fuzil',
        shotgun = 'cartucho de escopeta',
        sniper = 'municao de precisao',
        mg = 'municao de metralhadora',
        melee = 'sem municao',
    },
}
