ORInventoryNeedsConfig = {
    TickInterval = 60000,
    HungerLossPerTick = 0.20,
    ThirstLossPerTick = 0.35,
    SaveInterval = 300000,
    DefaultHunger = 100,
    DefaultThirst = 100,
    DefaultStress = 0,

    -- CADASTRO DE COMIDAS E BEBIDAS
    -- Cadastre o item completo somente aqui; nao precisa repetir em data/items.lua.
    -- A chave (ex.: coxinha_molho) e o codigo usado nas lojas e no /giveitem.
    -- weight: gramas. effects: pontos recuperados de hunger/fome e thirst/sede.
    -- stress negativo reduz estresse. Os valores finais ficam entre 0 e 100.
    -- use.duration: milissegundos. use.prop e opcional.
    -- Para adicionar outro alimento, copie um bloco e troque o codigo/nome.
    -- Depois de editar: restart ob_inventory. Isso nao cadastra o item em lojas.
    Consumables = {
        water = {
            label = 'Agua', weight = 500, maxStack = 10, maxCarry = 10, icon = 'W',
            effects = { thirst = 25 },
            use = {
                label = 'Bebendo agua...', duration = 2500,
                animation = { dict = 'mp_player_intdrink', clip = 'loop_bottle', flag = 49 },
            },
        },
        bread = {
            label = 'Pao', weight = 250, maxStack = 10, maxCarry = 10, icon = 'P',
            effects = { hunger = 25 },
            use = {
                label = 'Comendo pao...', duration = 2500,
                animation = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger', flag = 49 },
            },
        },
        coxinha_molho = {
            label = 'Coxinha com molho', description = 'Coxinha crocante acompanhada de molho de pimenta.',
            weight = 300, maxStack = 10, maxCarry = 10, icon = 'C',
            effects = { hunger = 35 },
            use = {
                label = 'Comendo coxinha...', duration = 5000,
                animation = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger', flag = 49 },
                -- Mao esquerda, acompanhando a animacao de comer.
                prop = { model = 'ob_prop_coxinha', bone = 18905,
                    position = { x = 0.13, y = 0.05, z = 0.02 },
                    rotation = { x = -50.0, y = 16.0, z = 60.0 } },
            },
        },
        cooked_meal = {
            label = 'Refeicao preparada', description = 'Prato completo preparado em uma cozinha industrial.',
            weight = 450, maxStack = 5, icon = 'RP', effects = { hunger = 48, thirst = 4, stress = -3 },
            use = { label = 'Comendo a refeicao...', duration = 6500,
                animation = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger', flag = 49 } },
        },
        burger = {
            label = 'Hamburguer artesanal', description = 'Hamburguer montado com ingredientes frescos.',
            weight = 350, maxStack = 8, icon = 'HB', effects = { hunger = 40, stress = -2 },
            use = { label = 'Comendo hamburguer...', duration = 4500,
                animation = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger', flag = 49 } },
        },
    },
}
