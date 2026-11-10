OBFiscal = {
    OwnerCommand = 'fiscal',
    PoliceCommand = 'fiscalpolicia',
    DirtyAccount = 'black_money',
    PolicePermission = 'police',
    PoliceRequireDuty = true,

    MinimumDeposit = 1000,
    MaximumDeposit = 1000000,
    DeclarationTaxPercent = 20,
    EconomyAccount = 'city_treasury',
    BaseDailyCapacity = 15000,
    SalesCoverRate = 0.35,
    MaximumDailyCapacity = 500000,

    FlagRiskScore = 45,
    DispatchRiskScore = 75,
    ManagerDistance = 5.0,
    RecentDeclarations = 30,
    PoliceRows = 100,

    Dispatch = {
        Type = 'fiscal_suspicion',
        Code = '10-90F',
        Title = 'Alerta de inteligencia financeira',
        Message = 'Movimentacao empresarial incompativel com o faturamento declarado.',
        Duration = 180,
        Radius = 90.0,
    },
}
