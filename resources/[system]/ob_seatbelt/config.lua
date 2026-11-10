OBSeatbeltConfig = {
    Key = 'G',
    EjectSpeedKmh = 80.0,
    -- Velocidade apos a colisao precisa cair pelo menos 45% para caracterizar impacto.
    ImpactSpeedDrop = 0.55,
    -- Motos, bicicletas, barcos e aeronaves nao possuem cinto.
    ExcludedVehicleClasses = {
        [8] = true, [13] = true, [14] = true, [15] = true, [16] = true, [21] = true,
    },
}
