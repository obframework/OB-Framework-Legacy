DrugSelling = {}

DrugSelling.interactDistance = 2.4
DrugSelling.offerSeconds = 12
DrugSelling.pedCooldownSeconds = 180
DrugSelling.theftRecoverySeconds = 60
DrugSelling.minimumStealChance = 8
DrugSelling.maximumStealChance = 18
DrugSelling.refuseChance = 16
DrugSelling.normalReportChance = 12
DrugSelling.policeBonusPerOfficer = 0.06
DrugSelling.maximumPoliceBonus = 0.36
DrugSelling.varietyBonusPerExtraDrug = 0.10
DrugSelling.maximumVarietyBonus = 0.30
DrugSelling.paymentItem = 'black_money'

DrugSelling.drugs = {
    weed_bag = { label = 'Maconha', minPrice = 115, maxPrice = 165 },
    cocaine_bag = { label = 'Cocaina', minPrice = 260, maxPrice = 360 },
    meth_bag = { label = 'Metanfetamina', minPrice = 320, maxPrice = 440 },
}

-- Animais, policiais, medicos e peds de servico nao recebem a opcao.
DrugSelling.blockedPedTypes = { [6] = true, [27] = true, [28] = true, [29] = true }
DrugSelling.blockedModels = {
    [joaat('s_m_y_cop_01')] = true, [joaat('s_f_y_cop_01')] = true, [joaat('s_m_y_hwaycop_01')] = true,
    [joaat('s_m_y_sheriff_01')] = true, [joaat('s_f_y_sheriff_01')] = true, [joaat('s_m_m_paramedic_01')] = true,
}
