OBCarshopConfig = {
    InteractionDistance = 2.2,
    MarkerDrawDistance = 35.0,
    DeliveryClearRadius = 3.5,
    DefaultNpcModel = 'a_m_m_business_01',
    -- Garagem onde veiculos comprados ficam registrados.
    DefaultGarage = 'central',
    -- Cada imagem usa o nome tecnico do modelo: kuruma.png, bf400.png etc.
    -- Troque esta URL caso o catalogo de imagens seja movido.
    ImageBaseUrl = '/orbis/cars/',
    FallbackImage = 'carro.png',
    DefaultBlip = { sprite = 225, color = 3, scale = 0.82, shortRange = true },
    SuggestedVehicles = {
        { model = 'blista', label = 'Dinka Blista', category = 'Compacto', price = 18000 },
        { model = 'panto', label = 'Benefactor Panto', category = 'Compacto', price = 14500 },
        { model = 'asea', label = 'Declasse Asea', category = 'Sedan', price = 22000 },
        { model = 'fugitive', label = 'Cheval Fugitive', category = 'Sedan', price = 38000 },
        { model = 'sultan', label = 'Karin Sultan', category = 'Esportivo', price = 85000 },
        { model = 'buffalo', label = 'Bravado Buffalo', category = 'Esportivo', price = 72000 },
        { model = 'baller', label = 'Gallivanter Baller', category = 'SUV', price = 110000 },
        { model = 'mesa', label = 'Canis Mesa', category = 'SUV', price = 76000 },
        { model = 'rumpo', label = 'Bravado Rumpo', category = 'Utilitario', price = 65000 },
        { model = 'bison', label = 'Bravado Bison', category = 'Utilitario', price = 70000 },
    }
}
