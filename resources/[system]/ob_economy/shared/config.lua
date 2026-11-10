OBEconomyConfig = {}

-- active: controla pagamentos e o Tesouro.
-- monitor: apenas registra o que aconteceria e deixa o script chamador cobrar.
-- disabled: todas as chamadas retornam ao pagamento antigo, sem registrar.
OBEconomyConfig.Mode = 'monitor'
OBEconomyConfig.Command = 'economia'
OBEconomyConfig.AdminPermission = 'economy.manage'
OBEconomyConfig.DefaultAccount = 'city_treasury'
OBEconomyConfig.Currency = 'USD'

OBEconomyConfig.Payment = {
    TryCardFirst = true,
    AllowCash = true,
    CashAccount = 'money',
}

-- InitialBalance so e usado na primeira criacao da conta. Reiniciar o recurso
-- ou mudar esse valor nao sobrescreve um saldo que ja existe no banco.
OBEconomyConfig.Accounts = {
    city_treasury = {
        label = 'Tesouro Municipal',
        kind = 'treasury',
        initialBalance = 1000000,
        allowNegative = false,
    },
    police = {
        label = 'Policia',
        kind = 'department',
        initialBalance = 0,
        allowNegative = false,
    },
    ambulance = {
        label = 'Hospital',
        kind = 'department',
        initialBalance = 0,
        allowNegative = false,
    },
    mechanic = {
        label = 'Mecanicas',
        kind = 'department',
        initialBalance = 0,
        allowNegative = false,
    },
}

OBEconomyConfig.Panel = {
    RecentEntries = 80,
    MaximumEntries = 200,
    MaximumAdjustment = 100000000,
}
