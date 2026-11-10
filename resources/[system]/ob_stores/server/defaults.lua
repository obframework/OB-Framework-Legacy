local function place(id, label, kind, coords, heading, blip, price)
    return {
        id = id, label = label, title = label, kind = kind, coords = coords, heading = heading,
        radius = 1.65, camOffset = vector3(0.0, 2.6, 0.55), lookAtOffset = vector3(0.0, 0.0, 0.5),
        defaultSection = kind == 'clothing' and 'skinshop' or (kind == 'barber' and 'barbershop' or 'tattoos'),
        allowedSections = { kind == 'clothing' and 'skinshop' or (kind == 'barber' and 'barbershop' or 'tattoos') },
        blip = blip, price = price,
    }
end

OBStoreSeeds = {
    place('clothes_city', 'Loja de roupas', 'clothing', vector3(425.5579, -800.4226, 29.4911), 85.0, { sprite = 73, color = 3 }),
    place('clothes_sandy', 'Loja de roupas', 'clothing', vector3(1693.1613, 4828.6953, 42.0631), 98.0, { sprite = 73, color = 3 }),
    place('clothes_vespucci', 'Loja de roupas', 'clothing', vector3(-710.5551, -153.3039, 37.4151), 120.0, { sprite = 73, color = 3 }),
    place('clothes_harmony', 'Loja de roupas', 'clothing', vector3(75.3963, -1398.6367, 29.3762), 270.0, { sprite = 73, color = 3 }),
    place('clothes_grapeseed', 'Loja de roupas', 'clothing', vector3(1190.6594, 2710.1992, 38.2226), 180.0, { sprite = 73, color = 3 }),
    place('clothes_paleto', 'Loja de roupas', 'clothing', vector3(9.1575, 6516.4712, 31.8779), 45.0, { sprite = 73, color = 3 }),
    place('barber_city', 'Barbearia', 'barber', vector3(137.4557, -1708.3042, 29.2916), 140.0, { sprite = 71, color = 3 }),
    place('barber_vespucci', 'Barbearia', 'barber', vector3(-1282.7776, -1118.0452, 6.9901), 90.0, { sprite = 71, color = 3 }),
    place('barber_sandy', 'Barbearia', 'barber', vector3(1932.3799, 3730.5715, 32.8444), 210.0, { sprite = 71, color = 3 }),
    place('barber_paleto', 'Barbearia', 'barber', vector3(-278.7739, 6227.5698, 31.6956), 310.0, { sprite = 71, color = 3 }),
    place('tattoo_city', 'Tatuagens', 'tattoo', vector3(1323.1583, -1652.3914, 52.2753), 32.0, { sprite = 75, color = 3 }),
    place('tattoo_west', 'Tatuagens', 'tattoo', vector3(321.9311, 180.7149, 103.5865), 157.0, { sprite = 75, color = 3 }),
    place('tattoo_chumash', 'Tatuagens', 'tattoo', vector3(-3170.2424, 1075.3109, 20.8292), 244.0, { sprite = 75, color = 3 }),
    place('tattoo_sandy', 'Tatuagens', 'tattoo', vector3(1863.9537, 3747.3416, 33.0318), 4.0, { sprite = 75, color = 3 }),
    place('tattoo_paleto', 'Tatuagens', 'tattoo', vector3(-293.8554, 6200.5098, 31.4871), 189.0, { sprite = 75, color = 3 }),

    -- Demais balcoes dos estabelecimentos ja usados na base anterior.
    place('clothes_city_second', 'Loja de roupas', 'clothing', vector3(430.1119, -800.3768, 29.4911), 172.8, { sprite = 73, color = 3 }),
    place('clothes_sandy_second', 'Loja de roupas', 'clothing', vector3(1697.6389, 4829.1992, 42.0631), 183.9, { sprite = 73, color = 3 }),
    place('clothes_hawick', 'Loja de roupas', 'clothing', vector3(-1187.8978, -768.6928, 17.3254), 115.1, { sprite = 73, color = 3 }),
    place('clothes_hawick_second', 'Loja de roupas', 'clothing', vector3(-162.6910, -303.2542, 39.7333), 242.0, { sprite = 73, color = 3 }),
    place('clothes_harmony_second', 'Loja de roupas', 'clothing', vector3(70.8119, -1398.8197, 29.3762), 357.6, { sprite = 73, color = 3 }),
    place('clothes_vespucci_second', 'Loja de roupas', 'clothing', vector3(-827.4508, -1076.4863, 11.3281), 291.3, { sprite = 73, color = 3 }),
    place('clothes_vespucci_third', 'Loja de roupas', 'clothing', vector3(-829.7878, -1072.5917, 11.3281), 291.3, { sprite = 73, color = 3 }),
    place('clothes_rockford', 'Loja de roupas', 'clothing', vector3(-1450.9772, -236.5914, 49.8085), 46.8, { sprite = 73, color = 3 }),
    place('clothes_paleto_second', 'Loja de roupas', 'clothing', vector3(12.2292, 6513.1992, 31.8779), 130.1, { sprite = 73, color = 3 }),
    place('clothes_route68', 'Loja de roupas', 'clothing', vector3(617.5580, 2766.7002, 42.0881), 182.7, { sprite = 73, color = 3 }),
    place('clothes_grapeseed_second', 'Loja de roupas', 'clothing', vector3(1190.7889, 2714.7251, 38.2226), 262.1, { sprite = 73, color = 3 }),
    place('clothes_chumash', 'Loja de roupas', 'clothing', vector3(-3175.4429, 1041.8798, 20.8632), 335.8, { sprite = 73, color = 3 }),
    place('clothes_senora', 'Loja de roupas', 'clothing', vector3(-1105.8291, 2706.6921, 19.1078), 301.7, { sprite = 73, color = 3 }),
    place('clothes_senora_second', 'Loja de roupas', 'clothing', vector3(-1108.7914, 2710.1414, 19.1078), 301.7, { sprite = 73, color = 3 }),
    place('clothes_vinewood', 'Loja de roupas', 'clothing', vector3(121.1104, -225.8344, 54.5578), 334.2, { sprite = 73, color = 3 }),
    place('barber_vespucci_beach', 'Barbearia', 'barber', vector3(-1154.0198, -1425.3057, 4.9531), 21.5, { sprite = 71, color = 3 }),
    place('barber_grapeseed', 'Barbearia', 'barber', vector3(1212.1809, -473.5263, 66.2080), 338.0, { sprite = 71, color = 3 }),
    place('barber_vinewood', 'Barbearia', 'barber', vector3(-33.7181, -152.1232, 57.0765), 245.5, { sprite = 71, color = 3 }),
}
