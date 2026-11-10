OBMechanicConfig = {
    TuningFree = false,
    Payment = {
        Account = 'money',
        DefaultPrice = 100,
        -- Em cada opcao voce pode usar:
        -- levelPrices = { [1] = 1000, [2] = 2000 } (nivel 1, nivel 2...)
        -- originalPrice = 100, enabledPrice = 100, disabledPrice = 100.
        -- Se um valor nao estiver configurado, sera usado price.
        -- Quando requirePermission estiver false, a oficina fica publica e
        -- acrescenta esta porcentagem em cada servico.
        PublicMarkupPercent = 10,
    },
    MarkerDistance = 35.0,
    InteractDistance = 3.2,
    Camera = {
        Enabled = true,
        FieldOfView = 45.0,
        MinDistance = 4.5,
        MaxDistance = 8.5,
        ManualSensitivity = 0.28,
    },
    Stations = {
        -- Cada ponto abre apenas o tipo de servico correspondente. Para criar
        -- novos boxes, reutilize category = 'aesthetic' ou 'performance'.
        {
            id = 'cypress_1', label = 'Benny s', category = 'aesthetic',
            coords = vec4(-211.0355, -1325.5306, 30.8904, 346.9397), color = { 31, 157, 255, 180 },
            requirePermission = true, permission = 'mechanic', requireDuty = false,
        },
        {
            id = 'redline_1', label = 'Los Santos Customs', category = 'performance',
            coords = vec4(-335.9108, -136.4628, 39.0096, 96.5664), color = { 52, 142, 255, 180 },
            requirePermission = true, permission = 'mechanic', requireDuty = false,
        },
    },
    Sections = {
        { id = 'performance', label = 'Performance', category = 'performance', options = {
            { key = 'engine', label = 'Motor', type = 'mod', index = 11, price = 100, levelPrices = { [1] = 100, [2] = 100, [3] = 100, [4] = 100 } },
            { key = 'brakes', label = 'Freios', type = 'mod', index = 12, price = 100, levelPrices = { [1] = 100, [2] = 100, [3] = 100 } },
            { key = 'transmission', label = 'Transmissao', type = 'mod', index = 13, price = 100, levelPrices = { [1] = 100, [2] = 100, [3] = 100, [4] = 100 } },
            { key = 'suspension', label = 'Suspensao', type = 'mod', index = 15, price = 100, levelPrices = { [1] = 100, [2] = 100, [3] = 100, [4] = 100 } },
            { key = 'armor', label = 'Blindagem', type = 'mod', index = 16, price = 100, levelPrices = { [1] = 100, [2] = 100, [3] = 100, [4] = 100, [5] = 100 } },
            { key = 'turbo', label = 'Turbo', type = 'toggle', index = 18, price = 100, enabledPrice = 100, disabledPrice = 100 },
        } },
        { id = 'body', label = 'Exterior', category = 'aesthetic', options = {
            { key = 'spoiler', label = 'Aerofolio', type = 'mod', index = 0, price = 100 },
            { key = 'front_bumper', label = 'Parachoque dianteiro', type = 'mod', index = 1, price = 100 },
            { key = 'rear_bumper', label = 'Parachoque traseiro', type = 'mod', index = 2, price = 100 },
            { key = 'side_skirt', label = 'Saia lateral', type = 'mod', index = 3, price = 100 },
            { key = 'exhaust', label = 'Escapamento', type = 'mod', index = 4, price = 100 },
            { key = 'grille', label = 'Grade', type = 'mod', index = 6, price = 100 },
            { key = 'hood', label = 'Capo', type = 'mod', index = 7, price = 100 },
            { key = 'roof', label = 'Teto', type = 'mod', index = 10, price = 100 },
            { key = 'livery', label = 'Estampa', type = 'mod', index = 48, price = 100 },
        } },
        -- Carros policiais e outros add-ons normalmente controlam giroflex,
        -- sirene visual, antenas e equipamentos pelos extras do veiculo. A NUI
        -- cria a lista conforme o modelo e permite somente uma configuracao.
        { id = 'equipment', label = 'Extras', category = 'aesthetic', options = {
            { key = 'extras', label = 'Configuracao de extras', type = 'extras', price = 100, exclusive = true },
        } },
        { id = 'wheels', label = 'Rodas', category = 'aesthetic', options = {
            { key = 'wheel_sport', label = 'Sport', type = 'wheel', wheelType = 0, index = 23, price = 100 },
            { key = 'wheel_muscle', label = 'Muscle', type = 'wheel', wheelType = 1, index = 23, price = 100 },
            { key = 'wheel_lowrider', label = 'Lowrider', type = 'wheel', wheelType = 2, index = 23, price = 100 },
            { key = 'wheel_suv', label = 'SUV', type = 'wheel', wheelType = 3, index = 23, price = 100 },
            { key = 'wheel_offroad', label = 'Offroad', type = 'wheel', wheelType = 4, index = 23, price = 100 },
            { key = 'wheel_tuner', label = 'Tuner', type = 'wheel', wheelType = 5, index = 23, price = 100 },
            { key = 'wheel_bike', label = 'Moto', type = 'wheel', wheelType = 6, index = 23, price = 100 },
            { key = 'wheel_highend', label = 'High End', type = 'wheel', wheelType = 7, index = 23, price = 100 },
            { key = 'wheel_bennys_original', label = 'Benny Original', type = 'wheel', wheelType = 8, index = 23, price = 100 },
            { key = 'wheel_bennys_bespoke', label = 'Benny Bespoke', type = 'wheel', wheelType = 9, index = 23, price = 100 },
            { key = 'wheel_openwheel', label = 'Open Wheel', type = 'wheel', wheelType = 10, index = 23, price = 100 },
            { key = 'wheel_street', label = 'Street', type = 'wheel', wheelType = 11, index = 23, price = 100 },
            { key = 'wheel_track', label = 'Track', type = 'wheel', wheelType = 12, index = 23, price = 100 },
        } },
        { id = 'visual', label = 'Visual', category = 'aesthetic', options = {
            { key = 'paint_type_primary', label = 'Tipo da pintura primaria', type = 'paint_type1', price = 100 },
            { key = 'primary', label = 'Cor primaria', type = 'color', price = 100 },
            { key = 'paint_type_secondary', label = 'Tipo da pintura secundaria', type = 'paint_type2', price = 100 },
            { key = 'secondary', label = 'Cor secundaria', type = 'color2', price = 100 },
            { key = 'pearlescent', label = 'Nacar', type = 'pearl', price = 100 },
            { key = 'wheel_color', label = 'Pintura das rodas', type = 'wheel_color', price = 100 },
            { key = 'window_tint', label = 'Pelicula', type = 'tint', price = 100 },
            { key = 'neon_enabled', label = 'Neon', type = 'neon_toggle', price = 100 },
            { key = 'neon', label = 'Cor do neon', type = 'neon', price = 100 },
            { key = 'xenon', label = 'Farol xenon', type = 'toggle', index = 22, price = 100 },
            { key = 'headlight_color', label = 'Cor do farol', type = 'headlight_color', price = 100 },
        } },
    }
}
