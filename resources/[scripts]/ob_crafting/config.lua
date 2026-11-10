Crafting = {}

Crafting.interactDistance = 2.5
Crafting.visualStreamDistance = 80.0
Crafting.visualDespawnDistance = 110.0
Crafting.maxBatch = 5
Crafting.levelStep = 500
Crafting.maxLevel = 20
Crafting.cancelRefund = 1.0
Crafting.failureRefund = 0.35

-- Coordenadas iniciais, separadas para facilitar a troca depois.
Crafting.stations = {
    kitchen = {
        label = 'Cozinha industrial', category = 'food', mode = 'public',
        coords = vector3(-1195.54, -897.37, 13.98), radius = 1.3, icon = '🍳',
        visual = { type = 'ped', model = 's_m_y_chef_01', heading = 34.0 },
    },
    workshop = {
        label = 'Oficina de montagem', category = 'utility', mode = 'public',
        coords = vector3(1171.8085, 2637.3948, 36.8003), radius = 1.5, icon = '🔧',
        visual = { type = 'ped', model = 'mp_m_waremech_01', heading = 284.2326, placeOnGround = true },
    },
    gunsmith = {
        label = 'Bancada de armeiro', category = 'weapons', mode = 'public',
        coords = vector3(1554.2639, -2174.3721, 77.3760), radius = 1.3, icon = '🔩',
        visual = { type = 'prop', model = 'gr_prop_gr_lathe_01c', heading = 80.0, placeOnGround = true },
    },
    laboratory = {
        label = 'Laboratorio clandestino', category = 'drugs', mode = 'public',
        coords = vector3(1390.5160, 3609.0625, 37.9419), radius = 1.3, icon = '🧪',
        visual = { type = 'ped', model = 'mp_f_cocaine_01', heading = 207.7, placeOnGround = true },
    },

    -- Modelo pronto para copiar. Troque enabled, grupo, coordenadas e receitas.
    private_example = {
        enabled = false, label = 'Bancada privada', category = 'weapons', mode = 'private',
        groups = { 'police' }, requireDuty = true,
        coords = vector3(0.0, 0.0, 0.0), radius = 1.3, icon = '🔩',
        visual = { type = 'prop', model = 'gr_prop_gr_lathe_01b', heading = 0.0, placeOnGround = true },
    },
}

-- chance e porcentagem. O servidor faz todos os sorteios e validacoes.
Crafting.recipes = {
    cooked_meal = {
        label = 'Refeicao preparada', category = 'food', station = 'kitchen', level = 1,
        ingredients = { raw_meat = 1, seasoning = 1, cooking_oil = 1 },
        output = { item = 'cooked_meal', amount = 1 }, duration = 9000, chance = 100, xp = 55,
        steps = { 'Preparando ingredientes', 'Cozinhando', 'Montando o prato' },
    },
    burger = {
        label = 'Hamburguer artesanal', category = 'food', station = 'kitchen', level = 2,
        ingredients = { bread = 1, raw_meat = 1, lettuce = 1, cheese = 1 },
        output = { item = 'burger', amount = 1 }, duration = 11000, chance = 96, xp = 70,
        steps = { 'Temperando a carne', 'Grelhando', 'Montando o lanche' },
    },
    steel_ingot = {
        label = 'Lingote de aco', category = 'utility', station = 'workshop', level = 1,
        ingredients = { metal_scrap = 4 }, output = { item = 'steel_ingot', amount = 1 },
        duration = 7500, chance = 100, xp = 35, steps = { 'Separando sucata', 'Fundindo metal' },
    },
    repairkit = {
        label = 'Kit de reparo', category = 'utility', station = 'workshop', level = 2,
        ingredients = { steel_ingot = 2, polymer = 2, electrical_parts = 1 },
        output = { item = 'repairkit', amount = 1 }, duration = 12000, chance = 94, xp = 80,
        steps = { 'Separando componentes', 'Montando o kit', 'Testando ferramentas' },
    },
    lockpick = {
        label = 'Lockpick', category = 'utility', station = 'workshop', level = 3,
        ingredients = { steel_ingot = 1, metal_scrap = 2 }, output = { item = 'lockpick', amount = 1 },
        duration = 9000, chance = 90, xp = 65, steps = { 'Cortando metal', 'Ajustando a lamina' },
    },
    pistol_ammo = {
        label = 'Municao de pistola (12)', category = 'weapons', station = 'gunsmith', level = 3,
        ingredients = { brass = 12, gunpowder = 2 }, output = { item = 'ammo_pistol', amount = 12 },
        duration = 13000, chance = 92, xp = 100, steps = { 'Prensando estojos', 'Dosando polvora', 'Inspecionando lote' },
    },
    sns_pistol = {
        label = 'Pistola compacta', category = 'weapons', station = 'gunsmith', level = 7,
        blueprint = true, ingredients = { weapon_parts = 3, steel_ingot = 4, polymer = 3 },
        output = { item = 'weapon_snspistol', amount = 1 }, duration = 26000, chance = 78, xp = 260,
        steps = { 'Usinando o ferrolho', 'Montando o mecanismo', 'Calibrando a arma' },
    },
    weed_bag = {
        label = 'Porcao de maconha', category = 'drugs', station = 'laboratory', level = 1,
        ingredients = { weed_leaf = 3, empty_bag = 1 }, output = { item = 'weed_bag', amount = 1 },
        duration = 8000, chance = 97, xp = 55, steps = { 'Selecionando material', 'Pesando', 'Embalando' },
    },
    coca_paste = {
        label = 'Pasta de coca', category = 'drugs', station = 'laboratory', level = 2,
        ingredients = { coca_leaf = 4, chemical_solvent = 1 }, output = { item = 'coca_paste', amount = 1 },
        duration = 12000, chance = 92, xp = 85, steps = { 'Macerando folhas', 'Misturando solvente', 'Filtrando a pasta' },
    },
    cocaine_bag = {
        label = 'Porcao de cocaina', category = 'drugs', station = 'laboratory', level = 4,
        ingredients = { coca_paste = 2, chemical_solvent = 1, empty_bag = 1 },
        output = { item = 'cocaine_bag', amount = 1 }, duration = 15000, chance = 86, xp = 130,
        steps = { 'Filtrando a pasta', 'Secando o composto', 'Pesando e embalando' },
    },
    meth_bag = {
        label = 'Porcao de metanfetamina', category = 'drugs', station = 'laboratory', level = 6,
        blueprint = true, ingredients = { chemical_solvent = 2, lab_reagent = 2, empty_bag = 1 },
        output = { item = 'meth_bag', amount = 1 }, duration = 22000, chance = 76, xp = 210,
        steps = { 'Misturando reagentes', 'Cristalizando', 'Pesando e embalando' },
    },
}

Crafting.categoryLabels = { food = 'Culinaria', utility = 'Utilitarios', weapons = 'Armeiro', drugs = 'Laboratorio' }
Crafting.itemLabels = {
    bread = 'Pao', raw_meat = 'Carne crua', seasoning = 'Tempero', cooking_oil = 'Oleo de cozinha',
    lettuce = 'Alface', cheese = 'Queijo', metal_scrap = 'Sucata metalica', steel_ingot = 'Lingote de aco',
    polymer = 'Polimero industrial', electrical_parts = 'Componentes eletricos', weapon_parts = 'Pecas de armamento',
    brass = 'Estojos de latao', gunpowder = 'Polvora', plant_material = 'Materia vegetal', empty_bag = 'Embalagem vazia',
    weed_leaf = 'Folha de maconha', coca_leaf = 'Folha de coca',
    coca_paste = 'Pasta de coca', chemical_solvent = 'Solvente quimico', lab_reagent = 'Reagente de laboratorio',
}
