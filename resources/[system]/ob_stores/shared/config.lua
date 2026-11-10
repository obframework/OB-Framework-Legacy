OBStoresConfig = {}

OBStoresConfig.Blips = true
-- A framework continua funcionando com a economia desligada. Quando Enabled
-- for true, cada categoria alterada e cobrada conforme o tipo da loja.
OBStoresConfig.Economy = {
    Enabled = true,
    Currency = 'USD',
    TryCardFirst = true,
    AllowCash = true,
    -- Cada categoria alterada e cobrada uma vez. Textura/cor da mesma peca
    -- nao soma uma segunda cobranca.
    ItemPrices = {
        clothing = 500,
        barber = 300,
        tattoo = 250,
    },
}
OBStoresConfig.Marker = {
    distance = 30.0,
    type = 27,
    scale = vector3(1.70, 1.70, 0.50),
    color = { 31, 157, 255, 185 },
}

-- Catalogo dos tipos e categorias que o editor pode oferecer em cada local.
-- A aplicacao da aparencia continua sendo feita pelo ob_creator.
OBStoresConfig.Ui = {
    clothing = {
        sections = {
            { id = 'skinshop', label = 'Roupas', categories = {
                { id = 'tops', label = 'Jaquetas', kind = 'component', component = 11, focus = 'torso', icon = 'nui://ob_creator/skinshop/menu/{gender}/torsos.png' },
                { id = 'torsos', label = 'Bracos', kind = 'component', component = 3, focus = 'torso', icon = 'nui://ob_creator/skinshop/menu/{gender}/torsos.png' },
                { id = 'legs', label = 'Calcas', kind = 'component', component = 4, focus = 'legs', icon = 'nui://ob_creator/skinshop/menu/{gender}/legs.png' },
                { id = 'shoes', label = 'Sapatos', kind = 'component', component = 6, focus = 'feet', icon = 'nui://ob_creator/skinshop/menu/{gender}/shoes.png' },
                { id = 'undershirts', label = 'Camisas', kind = 'component', component = 8, focus = 'torso', icon = 'nui://ob_creator/skinshop/menu/{gender}/undershirts.png' },
                -- Mascaras (componente 1) ficam ocultas enquanto o workaround
                -- Config.EnhancedMaskCrashWorkaround do ob_creator estiver
                -- ativo. FiveM: citizenfx/fivem#4037.
                { id = 'bags', label = 'Bolsas', kind = 'component', component = 5, focus = 'torso', icon = 'nui://ob_creator/skinshop/menu/{gender}/bags.png' },
                { id = 'bodyArmors', label = 'Colete', kind = 'component', component = 9, focus = 'torso', icon = 'nui://ob_creator/skinshop/menu/{gender}/bodyArmors.png' },
                { id = 'hats', label = 'Chapeus', kind = 'prop', prop = 0, focus = 'head', icon = 'nui://ob_creator/skinshop/menu/{gender}/hats.png' },
                { id = 'glasses', label = 'Oculos', kind = 'prop', prop = 1, focus = 'head', icon = 'nui://ob_creator/skinshop/menu/{gender}/glasses.png' },
                { id = 'watches', label = 'Relogios', kind = 'prop', prop = 6, focus = 'arms', icon = 'nui://ob_creator/skinshop/menu/{gender}/watches.png' },
            } }
        }
    },
    barber = {
        sections = {
            { id = 'barbershop', label = 'Barbearia', categories = {
                { id = 'hair', label = 'Cabelo', kind = 'hair', focus = 'head', imgFolder = 'hair', icon = 'nui://ob_creator/creator/{gender}/menu/hair.png' },
                { id = 'eyebrows', label = 'Sobrancelha', kind = 'overlay', overlay = 'eyebrows', focus = 'head', imgFolder = 'eyebrows', icon = 'nui://ob_creator/creator/{gender}/menu/eyebrows.png' },
                { id = 'eyes', label = 'Olhos', kind = 'eyeColor', focus = 'head', imgFolder = 'eyes', icon = 'nui://ob_creator/creator/{gender}/menu/eyes.png' },
                { id = 'makeup', label = 'Maquiagem', kind = 'overlay', overlay = 'makeUp', focus = 'head', imgFolder = 'makeup', icon = 'nui://ob_creator/creator/{gender}/menu/makeup.png' },
                { id = 'blush', label = 'Blush', kind = 'overlay', overlay = 'blush', focus = 'head', imgFolder = 'blush', icon = 'nui://ob_creator/creator/{gender}/menu/blush.png' },
                { id = 'lipstick', label = 'Batom', kind = 'overlay', overlay = 'lipstick', focus = 'head', imgFolder = 'lipstick', icon = 'nui://ob_creator/creator/{gender}/menu/lipstick.png' },
                { id = 'facialHair', label = 'Barba', kind = 'overlay', overlay = 'beard', focus = 'head', imgFolder = 'facialHair', icon = 'nui://ob_creator/creator/{gender}/menu/facialHair.png' },
            } }
        }
    },
    tattoo = {
        sections = {
            { id = 'tattoos', label = 'Tatuagens', categories = {
                { id = 'tat_head', label = 'Cabeca', kind = 'tattoo', zone = 'ZONE_HEAD', focus = 'head' },
                { id = 'tat_torso', label = 'Torso', kind = 'tattoo', zone = 'ZONE_TORSO', focus = 'torso' },
                { id = 'tat_left_arm', label = 'Braco esquerdo', kind = 'tattoo', zone = 'ZONE_LEFT_ARM', focus = 'arms' },
                { id = 'tat_right_arm', label = 'Braco direito', kind = 'tattoo', zone = 'ZONE_RIGHT_ARM', focus = 'arms' },
                { id = 'tat_left_leg', label = 'Perna esquerda', kind = 'tattoo', zone = 'ZONE_LEFT_LEG', focus = 'legs' },
                { id = 'tat_right_leg', label = 'Perna direita', kind = 'tattoo', zone = 'ZONE_RIGHT_LEG', focus = 'legs' },
            } }
        }
    }
}

OBStoresConfig.Editor = { Enabled = true, Permission = 'world.stores', MaxLocations = 200 }
-- Preenchido pelo banco. Os exemplos de server/defaults.lua sao importados
-- uma unica vez; editar/remover pelo F11 nao e desfeito ao reiniciar.
OBStoresConfig.Locations = {}
