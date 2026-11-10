Config = {}

Config.Debug = false
Config.EconomyIntegration = false -- A economia sera conectada quando o modulo proprio existir.
-- Evita decoracoes de cabelo/barba antigas serem reaplicadas a cada update de
-- aparencia. O fade pode ser escolhido no criador, sem um decal automatico.
Config.AutomaticFade = false
Config.RCoreTattoosCompatibility = false
-- O teste de streaming confirmou que o ped freemode basico nao era a causa
-- do crash. Personalizacao completa volta a ser aplicada, sempre passando
-- pelas validacoes de indice/cor/textura em appearance.lua.
Config.EnhancedAppearanceSafeTest = false
-- O FiveM possui um crash nativo conhecido quando SET_PED_HEAD_BLEND_DATA e
-- seguido por uma variacao do componente 1 (mascara). No Enhanced isso pode
-- derrubar tanto o dono do ped quanto outro cliente que recebe a atualizacao.
-- Enquanto a correcao nao estiver comprovada no cliente, mantenha mascaras
-- desativadas para nunca publicar essa combinacao instavel.
Config.EnhancedMaskCrashWorkaround = true
Config.ImageBaseUrl = "/orbis/" -- Pode trocar para IP/Dominio do servidor. Deixe vazio para usar NUI local.
Config.ImageProxy = false -- desativado (puxa direto do web server)
Config.ImageProxyCacheLimit = 0
-- A loja sempre lista as variacoes que existem no ped atual. O catalogo
-- continua sendo usado para tatuagens e imagens quando elas estiverem locais.
Config.UseLiveVariations = true
Config.Camera = {
    rotateSpeed = 2.0,
    zoomStep = 3.0,
    fovMin = 40.0,
    fovMax = 80.0
}

Config.FocusPresets = {
    full = { dist = 4.8, z = 0.55 },
    head = { dist = 0.85, z = 0.65 },
    torso = { dist = 1.8, z = 0.4 },
    arms = { dist = 2.1, z = 0.35 },
    legs = { dist = 2.4, z = -0.1 },
    feet = { dist = 2.3, z = -0.4 }
}


-- Modo "Criador de Personagem"
Config.Creator = {
    enabled = true,
    title = 'Criador de Personagem',
    defaultSection = 'creator',
    allowedSections = { 'creator' }, -- edite aqui se quiser esconder/mostrar secoes (ex: {'creator','skinshop'})
    imageBaseUrl = Config.ImageBaseUrl, -- usa a base global (link remoto)
    -- Onde o jogador cria o personagem (deixe nil para usar a posicao atual)
    -- Local aberto do GTA V para nao depender de MLO/interior externo. -75.1422, -818.9819, 326.1755, 338.8607
    spawn = { coords = vec4(-75.1422, -818.9819, 326.1755, 338.8607) },
    -- Onde o jogador aparece depois da criacao
    arrival = { coords = vec4(-1037.7, -2737.8, 20.2, 330.0) }, -- aeroporto
    -- Personagem novo chega diretamente no aeroporto. Ative somente se quiser
    -- que a criacao abra o seletor do ob_spawn antes de entrar na cidade.
    spawnSelectionAfterCreation = false,
    -- Camera base do criador:
    -- camOffset.y POSITIVO = camera na frente do personagem
    -- camOffset.y NEGATIVO = camera atras do personagem
    camOffset = vector3(0.0, 2.8, 0.6),
    lookAtOffset = vector3(0.0, 0.0, 0.65),
    intro = {
        enabled = false,
        mode = 'plane',
        duration = 8000,
        planeModel = 'luxor2',
        planeStart = vec4(-3000.0, -3000.0, 900.0, 60.0),
        planeEnd = vec4(-1037.0, -2737.0, 160.0, 60.0),
        camFollow = { back = 220.0, up = 60.0, side = 0.0 },
        camFov = 55.0,
        tennis = {
            enabled = false,
            duration = 4000,
            pedModels = { 'a_m_y_ktown_02', 'a_f_y_bevhills_02' },
            coords = {
                vec4(-1205.5, -1570.4, 4.6, 210.0),
                vec4(-1201.0, -1564.0, 4.6, 30.0)
            },
            cam = {
                pos = vec3(-1209.5, -1568.5, 6.5),
                lookAt = vec3(-1203.5, -1567.0, 5.2)
            }
        }
    },
    parents = {
        mothers = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21},
        fathers = {22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45},
        defaultMother = 0,
        defaultFather = 22
    },
    Validation = {
        minAge = 18,
        requireName = true,
        requireSurname = true,
        requireBirthdate = true,
        blacklist = {
           names = {"admin", "policia", "staff", "viado", "gay", "rolas", "pau", "taco", "dorolas", "puta", "putinha", "pauzao", "mae","sistema", "governo", "bandido"},
		   surnames = {"admin", "policia", "staff", "viado", "gay", "rolas", "pau", "taco", "dorolas", "puta", "putinha", "pauzao", "mae","sistema", "governo", "bandido"}
        },
        messages = {
            missingName = 'Preencha nome e sobrenome.',
            missingBirthdate = 'Informe a data de nascimento.',
            underage = 'Voce precisa ter 18 anos ou mais.',
            blacklisted = 'Nome ou sobrenome nao permitido.',
            confirmTitle = 'Confirmar cadastro',
            confirmBody = 'Confirma os dados abaixo?',
            confirmYes = 'Sim',
            confirmNo = 'Nao',
            invalidBirthdate = 'Data de nascimento invalida.'
        }
    },
    defaultOutfit = {
        male = {
            components = {
                { component = 3, drawable = 15, texture = 0 },   -- arms
                { component = 8, drawable = 15, texture = 0 },   -- undershirt
                { component = 11, drawable = 15, texture = 0 },  -- torso
                { component = 4, drawable = 61, texture = 0 },   -- pants
                { component = 6, drawable = 34, texture = 0 }    -- shoes
            },
            props = {}
        },
        female = {
            components = {
                { component = 3, drawable = 15, texture = 0 },   -- arms
                { component = 8, drawable = 14, texture = 0 },   -- undershirt
                -- Texturas usadas pelo preview nativo do Qbox: roupa completa,
                -- em vez do visual base de roupa intima do freemode.
                { component = 11, drawable = 15, texture = 3 },  -- torso
                { component = 4, drawable = 15, texture = 3 },   -- pants
                { component = 6, drawable = 35, texture = 0 }    -- shoes
            },
            props = {}
        }
    }
}

Config.CreatorUi = {
    title = 'Criador de Personagem',
    sections = {
        {
            id = 'creator',
            label = 'Aparencia',
            categories = {
                { id = 'hair', label = 'Cabelo', kind = 'hair', imgFolder = 'hair', icon = 'nui://ob_creator/creator/{gender}/menu/hair.png', focus = 'head' },
                { id = 'eyebrows', label = 'Sobrancelha', kind = 'overlay', overlay = 'eyebrows', imgFolder = 'eyebrows', icon = 'nui://ob_creator/creator/{gender}/menu/eyebrows.png', focus = 'head' },
                { id = 'eyes', label = 'Olhos', kind = 'eyeColor', imgFolder = 'eyes', icon = 'nui://ob_creator/creator/{gender}/menu/eyes.png', focus = 'head' },
                { id = 'makeup', label = 'Maquiagem', kind = 'overlay', overlay = 'makeUp', imgFolder = 'makeup', icon = 'nui://ob_creator/creator/{gender}/menu/makeup.png', focus = 'head' },
                { id = 'blush', label = 'Blush', kind = 'overlay', overlay = 'blush', imgFolder = 'blush', icon = 'nui://ob_creator/creator/{gender}/menu/blush.png', focus = 'head' },
                { id = 'lipstick', label = 'Batom', kind = 'overlay', overlay = 'lipstick', imgFolder = 'lipstick', icon = 'nui://ob_creator/creator/{gender}/menu/lipstick.png', focus = 'head' },
                { id = 'facialHair', label = 'Barba', kind = 'overlay', overlay = 'beard', imgFolder = 'facialHair', icon = 'nui://ob_creator/creator/{gender}/menu/facialHair.png', focus = 'head' },
                { id = 'chestHair', label = 'Peito', kind = 'overlay', overlay = 'chestHair', imgFolder = 'chestHair', icon = 'nui://ob_creator/creator/{gender}/menu/chestHair.png', focus = 'torso' }
            }
        }
    }
}

Config.CreatorFaceFeatures = {
    { id = 'noseWidth', label = 'Largura do nariz' },
    { id = 'nosePeakHigh', label = 'Altura do nariz' },
    { id = 'nosePeakSize', label = 'Comprimento do nariz' },
    { id = 'noseBoneHigh', label = 'Ponte do nariz' },
    { id = 'nosePeakLowering', label = 'Ponta do nariz' },
    { id = 'noseBoneTwist', label = 'Desvio do nariz' },
    { id = 'eyeBrownHigh', label = 'Altura da sobrancelha' },
    { id = 'eyeBrownForward', label = 'Profundidade da sobrancelha' },
    { id = 'cheeksBoneHigh', label = 'Altura das bochechas' },
    { id = 'cheeksBoneWidth', label = 'Largura das bochechas' },
    { id = 'cheeksWidth', label = 'Volume das bochechas' },
    { id = 'eyesOpening', label = 'Abertura dos olhos' },
    { id = 'lipsThickness', label = 'Espessura dos labios' },
    { id = 'jawBoneWidth', label = 'Largura do maxilar' },
    { id = 'jawBoneBackSize', label = 'Comprimento do maxilar' },
    { id = 'chinBoneLowering', label = 'Altura do queixo' },
    { id = 'chinBoneLenght', label = 'Comprimento do queixo' },
    { id = 'chinBoneSize', label = 'Largura do queixo' },
    { id = 'chinHole', label = 'Fenda do queixo' },
    { id = 'neckThickness', label = 'Espessura do pescoco' },
}

-- Mantem compatibilidade com o client.lua (usa o layout do criador)
Config.Ui = Config.CreatorUi
