Citizen.CreateThread(function()
    LoadMpDlcMaps()
    Wait(1000)

    -- A base da roda-gigante e do mapa original; a estrutura animada depende
    -- destes IPLs (incluindo o LOD para distancia).
    RequestIpl('ferris_finale_anim')
    RequestIpl('ferris_finale_anim_lod')

    -- Interiores de superficie configuraveis, disponiveis no jogo base.
    for _, location in pairs(IplConfig.SurfaceInteriors) do
        if location.enabled then
            for _, ipl in ipairs(location.ipls) do
                RequestIpl(ipl)
            end
        end
    end

    -- ==========================================
    -- 1. CARREGA AS MANSÕES E TERRENO NOVO
    -- ==========================================
    -- A Safehouse in the Hills (mp2025_02).
    -- O restante da framework funciona em qualquer build. Estas mansoes so
    -- existem a partir do build 3717; no Legacy mais antigo o recurso inicia
    -- normalmente e apenas deixa este mapa opcional desativado.
    if IplConfig.Mansions.enabled and GetGameBuildNumber() >= IplConfig.Mansions.minimumBuild then
    -- A remocao destes grupos apagava partes da superficie/rua vizinha.
    RequestIpl('ch3_04_ext_grp')
    RequestIpl('ch3_04_ext_grp_lod')
    RequestIpl('ch3_04_ext_grp_longdue')
    -- Nao usamos IsDlcPresent aqui: no Enhanced ele pode retornar falso mesmo
    -- com os mapas da atualizacao disponiveis, deixando apenas a colisao interna.
    local mansionIpls = {
        'm25_2_legacy_fixes', 'm25_2_knoway_sign', 'm25_2_mansion_props',

        -- Richman Villa: a, b, c e d sao andares distintos.
        'm25_2_ch1_06e_mansion_interior_a', 'm25_2_ch1_06e_mansion_interior_b',
        'm25_2_ch1_06e_mansion_interior_c', 'm25_2_ch1_06e_mansion_interior_d',
        'hei_ch1_06e_mansion_shared', 'hei_ch1_06f_mansion_shared',
        'hei_ch1_06e_mansion_private',
        'hei_ch1_06e_mansion_player_bounds', 'hei_ch1_06e_mansion_furniture',
        'hei_ch1_06e_mansion_shutters', 'hei_ch1_06e_mansion_firepit',
        'hei_ch1_06e_mansion_railings_p', 'hei_ch1_roads_mansion',
        'm25_2_mansion_gym', 'm25_2_dog_house',

        -- The Vinewood Residence.
        'm25_2_ch2_04_mansion_interior_a', 'm25_2_ch2_04_mansion_interior_b',
        'm25_2_ch2_04_mansion_interior_c', 'apa_ch2_04_mansion_shared',
        'apa_ch2_04_mansion_private', 'apa_ch2_04_mansion_player_bounds',
        'apa_ch2_04_mansion_furniture', 'apa_ch2_04_mansion_shutters',
        'apa_ch2_04_mansion_firepit', 'apa_ch2_04_mansion_railings_p',
        'm25_2_east_mansion_gym', 'm25_2_east_dog_house',

        -- Tongva Estate.
        'm25_2_ch1_09_mansion_interior_a', 'm25_2_ch1_09_mansion_interior_b',
        'm25_2_ch1_09_mansion_interior_c', 'hei_ch1_09_mansion_shared',
        'hei_ch1_09_mansion_private', 'hei_ch1_09_mansion_player_bounds',
        'hei_ch1_09_mansion_furniture', 'hei_ch1_09_mansion_shutters',
        'hei_ch1_09_mansion_firepit', 'hei_ch1_09_mansion_railings_p',
        'm25_2_tongva_mansion_gym', 'm25_2_tongva_dog_house'
    }

    -- Cada mansion possui um modo generico (interior invisivel) e um privado
    -- (interior renderizado). O privado acima e o unico que deve permanecer.
    local mansionIplsToRemove = {
        'hei_ch1_06e_mansion_original', 'hei_ch1_06f_mansion_original',
        'hei_ch1_06e_props_original', 'hei_ch1_roads_original',
        'apa_ch2_04_mansion_original', 'apa_ch2_04_props_original', 'apa_ch2_04_mansion_grass',
        'hei_ch1_09_mansion_original', 'hei_ch1_09_props_original',
        'hei_ch1_06e_mansion_generic', 'apa_ch2_04_mansion_generic', 'hei_ch1_09_mansion_generic'
    }

    for _, ipl in ipairs(mansionIplsToRemove) do RemoveIpl(ipl) end
    for _, ipl in ipairs(mansionIpls) do RequestIpl(ipl) end

    -- mansions.lua aplica os entity sets quando o interior estiver pronto.
    end

    -- Somente os vidros externos superiores do Diamond Casino.
    RequestIpl('hei_dlc_windows_casino')

    -- ==========================================
    -- 2. OUTROS LOCAIS (Seus IPLs anteriores)
    -- ==========================================
    RequestIpl("post_hiest_tunnel") 
    RequestIpl("ch3_12_tunnel")
    RequestIpl("v_tunnel_hole")
    RequestIpl("v_michael")
    RequestIpl("v_franklin")
    RequestIpl("v_lester")
    RequestIpl("TrevorsTrailerTrash")
    RequestIpl("apa_v_mp_h_01_a") 
    RequestIpl("apa_v_mp_h_06_a") 
    RequestIpl("heist_yacht2")
    RequestIpl("heist_yacht2_gadd")
    RequestIpl("shr_int") 

    EnableInteriorProp(GetInteriorAtCoords(-38.32, -1098.92, 27.31), "csr_before_crash") 
end)
