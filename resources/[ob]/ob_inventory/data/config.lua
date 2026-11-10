ORInventoryConfig = {
    Slots = 30,
    MaxWeight = 20000, -- gramas: capacidade inicial de 20 kg
    MaxBackpackWeight = 50000, -- limite absoluto de 50 kg
    BackpackUpgrade = 10000, -- uma mochila adiciona 10 kg
    BackpackSlotUpgrade = 10, -- uma mochila adiciona 10 slots
    MaxBackpacks = 3,
    -- Caminho reservado para imagens locais declaradas manualmente nos itens.
    ItemImagePath = 'assets/items',
    -- Icones remotos: por padrao, nome do item + .png. Alguns arquivos do
    -- diretorio publico usam outro nome; os aliases abaixo corrigem isso.
    -- LocalFallback deve ficar false enquanto a pasta local nao possuir um PNG
    -- para cada item. Assim um icone ausente deixa somente a letra, sem fazer a
    -- NUI tentar abrir dezenas de arquivos inexistentes.
    ItemImages = {
        BaseUrl = '/orbis/icons/',
        Extension = '.png',
        Preload = false, -- evita requisitar todo o catalogo e gerar 404 em massa
        LocalFallback = false,
        LocalPath = 'assets/items',
        Aliases = {
            medkit = 'medikit',
            mochila = 'backpack1',
            repair_kit = 'repairkit',
            tyre_kit = 'tirekit',
            advancedrepairkit = 'advancedkit',
            vehicle_oil = 'engine_oil',
            spark_plugs = 'engine_sparkplug',
            heist_laptop = 'laptop',
            heist_drill = 'drill',
            handcuff_key = 'handcuffkey',
            bank_card = 'card_bank',
            balde = 'mopbucket',
            bread = 'WEAPON_BREAD',
        },
    },
    -- Duracao em dias reais (24h), mesmo quando o jogador esta offline.
    -- Em qualquer item de items.lua, use `durability = 0` para nunca vencer
    -- ou `durability = 3` para ele vencer em tres dias.
    Durability = {
        DefaultDays = 7,
        WeaponDays = 7,
        WeaponOverrides = {}, -- Ex.: weapon_pistol = 14,
        NonDurableItems = { phone = true, bank_card = true },
        NonDurableTypes = { currency = true, weapon_ammo = true },
    },
    -- APOSTROPHE corresponde a aspa simples (').
    OpenControl = 'APOSTROPHE',
    QuickUse = {
        -- Botao direito usa sempre uma unidade. Ctrl + botao direito usa o
        -- maximo somente para os tipos/itens liberados abaixo.
        CtrlMaximumTypes = {
            weapon_ammo = true,
        },
        CtrlMaximumItems = {
            -- Exemplo para consumir toda a pilha de um item consumivel:
            -- water = true,
        },
    },
    Transfer = {
        -- Jogadores precisam estar proximos para trocar itens.
        Distance = 3.0,
    },
    Ground = {
        DisplayDistance = 100.0,
        InteractDistance = 2.0,
        ExpireMs = 10 * 60 * 1000,
        CleanupInterval = 30000,
    },
}
