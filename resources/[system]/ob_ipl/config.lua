IplConfig = {
    -- Remove somente populacao ambiente nos interiores abaixo (nao NPCs de scripts).
    DisableInteriorAmbientPeds = true,
    Mansions = {
        enabled = true,
        minimumBuild = 3717,
        style = 'cali', -- cali, loft ou holly (bob74_ipl)
        tint = 0, -- 0 creme, 1 menta, 2 lavanda, 3 salmao
        wallpaper = 'deco',
        locations = {
            {label='Vinewood Residence', x=543.852, y=712.754, z=201.0, interiorId=304385, basementId=304641},
            {label='Richman Villa', x=-1630.434, y=470.852, z=128.0, interiorId=302593, basementId=303105},
            {label='Tongva Estate', x=-2601.712, y=1874.826, z=166.0, interiorId=303617, basementId=303873},
        },
    },
    CayoPerico = {
        enabled = true,
        showOnMap = true,
        showBlip = false,
        -- Streaming automatico ao chegar de barco/aviao ou por teleporte.
        x = 4840.571, y = -5174.425, z = 2.0,
        loadRadius = 2250.0,
        unloadRadius = 2500.0,
    },
    -- Interiores originais na superficie, sem teleporte para shells subterraneos.
    -- Desative o local correspondente se instalar um MLO que o substitua.
    SurfaceInteriors = {
        slaughterhouse = {
            enabled = true,
            label = 'Galinheiro / abatedouro Cluckin Bell',
            interiorPoint = { x = -107.0, y = 6204.0, z = 31.0 },
            -- Paleto Bay: -146.3837, 6161.5, 30.2062
            ipls = {
                'CS1_02_cf_onmission1', 'CS1_02_cf_onmission2',
                'CS1_02_cf_onmission3', 'CS1_02_cf_onmission4'
            }
        },
        garmentFactory = {
            enabled = true,
            label = 'Fabrica de roupas / Darnell Bros',
            interiorPoint = { x = 707.0, y = -966.0, z = 30.4 },
            -- La Mesa: 716.84, -962.05, 31.59
            ipls = { 'id2_14_during_door', 'id2_14_during1' }
        },
        -- Sugestoes opcionais para RP. Ative somente se quiser esses locais.
        grapeseedFarm = {
            enabled = true,
            label = 'Fazenda de Grapeseed',
            interiorPoint = { x = 2447.9, y = 4973.4, z = 47.7 },
            -- 2447.9, 4973.4, 47.7
            ipls = { 'farm', 'farmint', 'farm_lod', 'farm_props', 'des_farmhouse' }
        },
        lifeinvader = {
            enabled = true,
            label = 'Recepcao da Lifeinvader',
            interiorPoint = { x = -1082.0, y = -260.0, z = 37.8 },
            -- -1047.9, -233.0, 39.0
            ipls = { 'facelobby' }
        }
    }
}
