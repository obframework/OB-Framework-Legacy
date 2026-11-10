OBMdtConfig = {
    Commands = {
        Police = 'mdt',
        Lawyer = 'adv',
    },
    Permissions = {
        Police = 'police',
        Lawyer = 'lawyer',
        Clear = 'mdt.clear',
        Audit = 'mdt.audit',
    },
    RequirePoliceDuty = true,
    RequireLawyerDuty = false,
    AllowAdminAccess = true,
    AllowAdminClear = true,
    -- Por padrao, policiais em servico e advogados com acesso ao MDT podem
    -- limpar fichas e consultar o historico. Defina false para exigir apenas
    -- as permissoes externas mdt.clear e mdt.audit do cargo.
    AllowPoliceClear = true,
    AllowLawyerClear = true,
    AllowPoliceAudit = true,
    AllowLawyerAudit = true,
    MaximumMonths = 240,
    MaximumFine = 10000000,
    MaximumSuspectsPerRecord = 8,
    SearchLimit = 30,
    HistoryLimit = 100,
}
