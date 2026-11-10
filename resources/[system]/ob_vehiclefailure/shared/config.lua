OBVehicleFailureConfig = {
    enabled = true,

    -- O recurso apenas reforca o handling original de cada veiculo. Motor,
    -- fumaca, fogo, vazamentos e deformacao continuam sendo produzidos pelo GTA.
    handling = {
        collision = 2.00,
        deformation = 2.75,
        engine = 1.75,
        weapon = 1.50,
        maximum = 10.0,
        minimum = {
            collision = 1.00,
            deformation = 1.00,
            engine = 1.00,
            weapon = 1.00,
        },
    },

    -- Classes sem uma mecanica de dano rodoviario compativel.
    ignoredClasses = {
        [13] = true, -- bicicletas
        [14] = true, -- barcos
        [15] = true, -- helicopteros
        [16] = true, -- avioes
        [21] = true, -- trens
    },

    -- Permite balancear uma classe sem substituir o handling proprio do modelo.
    -- Uma classe ausente utiliza 1.0.
    classMultiplier = {
        [8] = 0.85,  -- motocicletas
        [18] = 0.85, -- emergencia
        [19] = 0.65, -- militar
    },

    engineShutdownHealth = 0.0,
    healthyPollInterval = 200,
}
