VehicleKeysConfig = {
    -- true: autorizacao virtual, nunca entrega item (garagem ou lockpick).
    -- false: chave fisica; fica na ignicao ao ligar e volta ao desligar.
    virtual = false,
    KeyItem = 'vehiclekey',
    LockKey = 'L',
    EngineKey = 'Z',
    -- Mantem a ignicao manual, mas nao exibe dicas permanentes ao entrar no veiculo.
    ShowIgnitionHints = false,
    -- A reserva de carro proprio persiste sem alterar a chave nem o dono original.
    Lockpick = { Enabled = true, DurationMs = 35000, AlarmChance = 30 },
}
