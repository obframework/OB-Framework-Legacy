-- Catalogo editavel do modulo weapons. Armas explosivas, lancadores,
-- railgun e minigun ficam deliberadamente fora da lista padrao.
ORInventoryWeapons = { Weapons = {}, Components = {} }

local function weapon(itemName, label, weaponHash, ammoType, weight, components)
    ORInventoryWeapons.Weapons[itemName] = {
        label = label,
        weaponHash = weaponHash,
        ammoType = ammoType,
        weight = weight or 1500,
        components = components or {},
    }
end

local PI_FLASH, PI_SUPP = 'COMPONENT_AT_PI_FLSH', 'COMPONENT_AT_PI_SUPP_02'
local AR_FLASH, AR_SUPP = 'COMPONENT_AT_AR_FLSH', 'COMPONENT_AT_AR_SUPP_02'
local SR_SUPP = 'COMPONENT_AT_SR_SUPP'
local function attach(clip, extras)
    local result = extras or {}
    if clip then result.extended_mag = ('COMPONENT_%s_CLIP_02'):format(clip) end
    return result
end

-- Corpo a corpo.
weapon('weapon_knife', 'Faca', 'WEAPON_KNIFE', 'melee', 350)
weapon('weapon_nightstick', 'Cassetete', 'WEAPON_NIGHTSTICK', 'melee', 600)
weapon('weapon_hammer', 'Martelo', 'WEAPON_HAMMER', 'melee', 900)
weapon('weapon_bat', 'Taco de beisebol', 'WEAPON_BAT', 'melee', 900)
weapon('weapon_golfclub', 'Taco de golfe', 'WEAPON_GOLFCLUB', 'melee', 900)
weapon('weapon_crowbar', 'Pe de cabra', 'WEAPON_CROWBAR', 'melee', 1100)
weapon('weapon_bottle', 'Garrafa quebrada', 'WEAPON_BOTTLE', 'melee', 300)
weapon('weapon_dagger', 'Adaga', 'WEAPON_DAGGER', 'melee', 300)
weapon('weapon_hatchet', 'Machadinha', 'WEAPON_HATCHET', 'melee', 800)
weapon('weapon_knuckle', 'Soco ingles', 'WEAPON_KNUCKLE', 'melee', 250)
weapon('weapon_machete', 'Facao', 'WEAPON_MACHETE', 'melee', 900)
weapon('weapon_flashlight', 'Lanterna', 'WEAPON_FLASHLIGHT', 'melee', 400)
weapon('weapon_switchblade', 'Canivete', 'WEAPON_SWITCHBLADE', 'melee', 250)
weapon('weapon_battleaxe', 'Machado de batalha', 'WEAPON_BATTLEAXE', 'melee', 1500)
weapon('weapon_poolcue', 'Taco de sinuca', 'WEAPON_POOLCUE', 'melee', 800)
weapon('weapon_wrench', 'Chave inglesa', 'WEAPON_WRENCH', 'melee', 1000)
weapon('weapon_stone_hatchet', 'Machadinha de pedra', 'WEAPON_STONE_HATCHET', 'melee', 900)

-- Pistolas.
weapon('weapon_pistol', 'Pistola', 'WEAPON_PISTOL', 'pistol', 900, attach('PISTOL', { flashlight = PI_FLASH, suppressor = PI_SUPP }))
weapon('weapon_combatpistol', 'Pistola de combate', 'WEAPON_COMBATPISTOL', 'pistol', 950, attach('COMBATPISTOL', { flashlight = PI_FLASH, suppressor = 'COMPONENT_AT_PI_SUPP' }))
weapon('weapon_appistol', 'Pistola AP', 'WEAPON_APPISTOL', 'pistol', 1000, attach('APPISTOL', { flashlight = PI_FLASH, suppressor = 'COMPONENT_AT_PI_SUPP' }))
weapon('weapon_pistol50', 'Pistola .50', 'WEAPON_PISTOL50', 'pistol', 1200, attach('PISTOL50', { flashlight = PI_FLASH, suppressor = PI_SUPP }))
weapon('weapon_snspistol', 'Pistola SNS', 'WEAPON_SNSPISTOL', 'pistol', 650, attach('SNSPISTOL'))
weapon('weapon_heavypistol', 'Pistola pesada', 'WEAPON_HEAVYPISTOL', 'pistol', 1250, attach('HEAVYPISTOL', { flashlight = PI_FLASH, suppressor = PI_SUPP }))
weapon('weapon_vintagepistol', 'Pistola vintage', 'WEAPON_VINTAGEPISTOL', 'pistol', 800, attach('VINTAGEPISTOL', { suppressor = 'COMPONENT_AT_PI_SUPP' }))
weapon('weapon_marksmanpistol', 'Pistola de precisao', 'WEAPON_MARKSMANPISTOL', 'pistol', 1000)
weapon('weapon_revolver', 'Revolver pesado', 'WEAPON_REVOLVER', 'pistol', 1300)
weapon('weapon_doubleaction', 'Revolver Double Action', 'WEAPON_DOUBLEACTION', 'pistol', 1100)
weapon('weapon_ceramicpistol', 'Pistola ceramica', 'WEAPON_CERAMICPISTOL', 'pistol', 700, attach('CERAMICPISTOL', { suppressor = 'COMPONENT_CERAMICPISTOL_SUPP' }))
weapon('weapon_navyrevolver', 'Revolver Navy', 'WEAPON_NAVYREVOLVER', 'pistol', 1250)
weapon('weapon_gadgetpistol', 'Pistola Perico', 'WEAPON_GADGETPISTOL', 'pistol', 900)
weapon('weapon_stungun', 'Taser', 'WEAPON_STUNGUN', 'pistol', 700)
weapon('weapon_flaregun', 'Pistola sinalizadora', 'WEAPON_FLAREGUN', 'pistol', 800)
weapon('weapon_pistol_mk2', 'Pistola Mk II', 'WEAPON_PISTOL_MK2', 'pistol', 1050, attach('PISTOL_MK2', { flashlight = PI_FLASH, suppressor = PI_SUPP }))
weapon('weapon_revolver_mk2', 'Revolver Mk II', 'WEAPON_REVOLVER_MK2', 'pistol', 1400)
weapon('weapon_snspistol_mk2', 'Pistola SNS Mk II', 'WEAPON_SNSPISTOL_MK2', 'pistol', 700, attach('SNSPISTOL_MK2', { flashlight = PI_FLASH }))
weapon('weapon_pistolxm3', 'Pistola WM 29', 'WEAPON_PISTOLXM3', 'pistol', 1050, attach('PISTOLXM3', { suppressor = 'COMPONENT_PISTOLXM3_SUPP' }))

-- SMGs e submetralhadoras.
weapon('weapon_microsmg', 'Micro SMG', 'WEAPON_MICROSMG', 'smg', 1600, attach('MICROSMG', { flashlight = PI_FLASH, suppressor = AR_SUPP, scope_small = 'COMPONENT_AT_SCOPE_MACRO' }))
weapon('weapon_smg', 'SMG', 'WEAPON_SMG', 'smg', 1900, attach('SMG', { flashlight = AR_FLASH, suppressor = 'COMPONENT_AT_PI_SUPP', scope_small = 'COMPONENT_AT_SCOPE_MACRO_02' }))
weapon('weapon_assaultsmg', 'SMG de assalto', 'WEAPON_ASSAULTSMG', 'smg', 2200, attach('ASSAULTSMG', { flashlight = AR_FLASH, suppressor = AR_SUPP, scope_small = 'COMPONENT_AT_SCOPE_MACRO' }))
weapon('weapon_combatpdw', 'PDW de combate', 'WEAPON_COMBATPDW', 'smg', 2200, attach('COMBATPDW', { flashlight = AR_FLASH, grip = 'COMPONENT_AT_AR_AFGRIP', scope_small = 'COMPONENT_AT_SCOPE_SMALL' }))
weapon('weapon_machinepistol', 'Pistola automatica', 'WEAPON_MACHINEPISTOL', 'smg', 1150, attach('MACHINEPISTOL'))
weapon('weapon_minismg', 'Mini SMG', 'WEAPON_MINISMG', 'smg', 1400, attach('MINISMG'))
weapon('weapon_smg_mk2', 'SMG Mk II', 'WEAPON_SMG_MK2', 'smg', 2100, attach('SMG_MK2', { flashlight = AR_FLASH, suppressor = AR_SUPP, scope_small = 'COMPONENT_AT_SCOPE_MACRO_02_MK2' }))
weapon('weapon_tacticalsmg', 'SMG tatica', 'WEAPON_TACTICALSMG', 'smg', 2100, attach('TACTICALSMG', { flashlight = AR_FLASH, suppressor = AR_SUPP }))

-- Escopetas.
weapon('weapon_pumpshotgun', 'Escopeta Pump', 'WEAPON_PUMPSHOTGUN', 'shotgun', 2800, attach('PUMPSHOTGUN', { flashlight = AR_FLASH, suppressor = SR_SUPP }))
weapon('weapon_sawnoffshotgun', 'Escopeta Cano Serrado', 'WEAPON_SAWNOFFSHOTGUN', 'shotgun', 1900, attach('SAWNOFFSHOTGUN'))
weapon('weapon_assaultshotgun', 'Escopeta de assalto', 'WEAPON_ASSAULTSHOTGUN', 'shotgun', 3300, attach('ASSAULTSHOTGUN', { flashlight = AR_FLASH, grip = 'COMPONENT_AT_AR_AFGRIP' }))
weapon('weapon_bullpupshotgun', 'Escopeta Bullpup', 'WEAPON_BULLPUPSHOTGUN', 'shotgun', 3100, attach('BULLPUPSHOTGUN', { flashlight = AR_FLASH, grip = 'COMPONENT_AT_AR_AFGRIP' }))
weapon('weapon_heavyshotgun', 'Escopeta pesada', 'WEAPON_HEAVYSHOTGUN', 'shotgun', 3700, attach('HEAVYSHOTGUN', { flashlight = AR_FLASH, grip = 'COMPONENT_AT_AR_AFGRIP' }))
weapon('weapon_dbshotgun', 'Escopeta dupla', 'WEAPON_DBSHOTGUN', 'shotgun', 2800)
weapon('weapon_autoshotgun', 'Escopeta automatica', 'WEAPON_AUTOSHOTGUN', 'shotgun', 3400)
weapon('weapon_combatshotgun', 'Escopeta de combate', 'WEAPON_COMBATSHOTGUN', 'shotgun', 3500, attach('COMBATSHOTGUN', { flashlight = AR_FLASH, suppressor = SR_SUPP }))
weapon('weapon_pumpshotgun_mk2', 'Escopeta Pump Mk II', 'WEAPON_PUMPSHOTGUN_MK2', 'shotgun', 3000, attach('PUMPSHOTGUN_MK2', { flashlight = AR_FLASH, suppressor = SR_SUPP }))

-- Fuzis e rifles.
weapon('weapon_assaultrifle', 'Rifle de assalto', 'WEAPON_ASSAULTRIFLE', 'rifle', 3400, attach('ASSAULTRIFLE', { flashlight = AR_FLASH, suppressor = AR_SUPP, grip = 'COMPONENT_AT_AR_AFGRIP', scope_small = 'COMPONENT_AT_SCOPE_MACRO' }))
weapon('weapon_carbinerifle', 'Carabina', 'WEAPON_CARBINERIFLE', 'rifle', 3300, attach('CARBINERIFLE', { flashlight = AR_FLASH, suppressor = AR_SUPP, grip = 'COMPONENT_AT_AR_AFGRIP', scope_medium = 'COMPONENT_AT_SCOPE_MEDIUM' }))
weapon('weapon_advancedrifle', 'Rifle avancado', 'WEAPON_ADVANCEDRIFLE', 'rifle', 3200, attach('ADVANCEDRIFLE', { flashlight = AR_FLASH, suppressor = AR_SUPP, scope_small = 'COMPONENT_AT_SCOPE_SMALL' }))
weapon('weapon_specialcarbine', 'Carabina especial', 'WEAPON_SPECIALCARBINE', 'rifle', 3300, attach('SPECIALCARBINE', { flashlight = AR_FLASH, suppressor = AR_SUPP, grip = 'COMPONENT_AT_AR_AFGRIP', scope_medium = 'COMPONENT_AT_SCOPE_MEDIUM' }))
weapon('weapon_bullpuprifle', 'Rifle Bullpup', 'WEAPON_BULLPUPRIFLE', 'rifle', 3200, attach('BULLPUPRIFLE', { flashlight = AR_FLASH, suppressor = 'COMPONENT_AT_AR_SUPP', grip = 'COMPONENT_AT_AR_AFGRIP', scope_small = 'COMPONENT_AT_SCOPE_SMALL' }))
weapon('weapon_compactrifle', 'Rifle compacto', 'WEAPON_COMPACTRIFLE', 'rifle', 2700)
weapon('weapon_militaryrifle', 'Rifle militar', 'WEAPON_MILITARYRIFLE', 'rifle', 3500, attach('MILITARYRIFLE', { flashlight = AR_FLASH, suppressor = 'COMPONENT_AT_AR_SUPP', scope_small = 'COMPONENT_AT_SCOPE_SMALL' }))
weapon('weapon_heavyrifle', 'Rifle pesado', 'WEAPON_HEAVYRIFLE', 'rifle', 3900, attach('HEAVYRIFLE', { flashlight = AR_FLASH, suppressor = 'COMPONENT_AT_AR_SUPP', grip = 'COMPONENT_AT_AR_AFGRIP', scope_medium = 'COMPONENT_AT_SCOPE_MEDIUM' }))
weapon('weapon_tacticalrifle', 'Carabina de servico', 'WEAPON_TACTICALRIFLE', 'rifle', 3300, attach('TACTICALRIFLE', { flashlight = 'COMPONENT_AT_AR_FLSH_REH', suppressor = AR_SUPP, grip = 'COMPONENT_AT_AR_AFGRIP' }))
weapon('weapon_battlerifle', 'Rifle de batalha', 'WEAPON_BATTLERIFLE', 'rifle', 3900, attach('BATTLERIFLE', { suppressor = 'COMPONENT_AT_AR_SUPP' }))
weapon('weapon_assaultrifle_mk2', 'Rifle de assalto Mk II', 'WEAPON_ASSAULTRIFLE_MK2', 'rifle', 3600, attach('ASSAULTRIFLE_MK2', { flashlight = AR_FLASH, suppressor = AR_SUPP, grip = 'COMPONENT_AT_AR_AFGRIP_02', scope_small = 'COMPONENT_AT_SCOPE_MACRO_MK2' }))
weapon('weapon_carbinerifle_mk2', 'Carabina Mk II', 'WEAPON_CARBINERIFLE_MK2', 'rifle', 3500, attach('CARBINERIFLE_MK2', { flashlight = AR_FLASH, suppressor = AR_SUPP, grip = 'COMPONENT_AT_AR_AFGRIP_02', scope_medium = 'COMPONENT_AT_SCOPE_MEDIUM_MK2' }))
weapon('weapon_specialcarbine_mk2', 'Carabina especial Mk II', 'WEAPON_SPECIALCARBINE_MK2', 'rifle', 3500, attach('SPECIALCARBINE_MK2', { flashlight = AR_FLASH, suppressor = AR_SUPP, grip = 'COMPONENT_AT_AR_AFGRIP_02', scope_small = 'COMPONENT_AT_SCOPE_MACRO_MK2' }))
weapon('weapon_bullpuprifle_mk2', 'Rifle Bullpup Mk II', 'WEAPON_BULLPUPRIFLE_MK2', 'rifle', 3400, attach('BULLPUPRIFLE_MK2', { flashlight = AR_FLASH, suppressor = 'COMPONENT_AT_AR_SUPP', grip = 'COMPONENT_AT_AR_AFGRIP_02', scope_small = 'COMPONENT_AT_SCOPE_SMALL_MK2' }))

-- Metralhadoras que nao sao minigun.
weapon('weapon_mg', 'Metralhadora', 'WEAPON_MG', 'mg', 5500, attach('MG', { scope_small = 'COMPONENT_AT_SCOPE_SMALL_02' }))
weapon('weapon_combatmg', 'Metralhadora de combate', 'WEAPON_COMBATMG', 'mg', 6000, attach('COMBATMG', { grip = 'COMPONENT_AT_AR_AFGRIP', scope_medium = 'COMPONENT_AT_SCOPE_MEDIUM' }))
weapon('weapon_gusenberg', 'Gusenberg', 'WEAPON_GUSENBERG', 'mg', 5000, attach('GUSENBERG'))
weapon('weapon_combatmg_mk2', 'Metralhadora de combate Mk II', 'WEAPON_COMBATMG_MK2', 'mg', 6200, attach('COMBATMG_MK2', { grip = 'COMPONENT_AT_AR_AFGRIP_02', scope_medium = 'COMPONENT_AT_SCOPE_MEDIUM_MK2' }))

-- Rifles de precisao.
weapon('weapon_sniperrifle', 'Rifle sniper', 'WEAPON_SNIPERRIFLE', 'sniper', 4800, attach('SNIPERRIFLE', { scope_large = 'COMPONENT_AT_SCOPE_LARGE', suppressor = SR_SUPP }))
weapon('weapon_heavysniper', 'Sniper pesado', 'WEAPON_HEAVYSNIPER', 'sniper', 6000, attach('HEAVYSNIPER', { scope_large = 'COMPONENT_AT_SCOPE_LARGE' }))
weapon('weapon_marksmanrifle', 'Rifle de atirador', 'WEAPON_MARKSMANRIFLE', 'sniper', 4300, attach('MARKSMANRIFLE', { flashlight = AR_FLASH, grip = 'COMPONENT_AT_AR_AFGRIP', scope_medium = 'COMPONENT_AT_SCOPE_LARGE_FIXED_ZOOM', suppressor = 'COMPONENT_AT_AR_SUPP' }))
weapon('weapon_precisionrifle', 'Rifle de precisao', 'WEAPON_PRECISIONRIFLE', 'sniper', 5100)
weapon('weapon_musket', 'Mosquete', 'WEAPON_MUSKET', 'sniper', 4200)
weapon('weapon_heavysniper_mk2', 'Sniper pesado Mk II', 'WEAPON_HEAVYSNIPER_MK2', 'sniper', 6200, attach('HEAVYSNIPER_MK2', { scope_large = 'COMPONENT_AT_SCOPE_LARGE_MK2', suppressor = 'COMPONENT_AT_SR_SUPP_03' }))
weapon('weapon_marksmanrifle_mk2', 'Rifle de atirador Mk II', 'WEAPON_MARKSMANRIFLE_MK2', 'sniper', 4500, attach('MARKSMANRIFLE_MK2', { flashlight = AR_FLASH, grip = 'COMPONENT_AT_AR_AFGRIP_02', scope_medium = 'COMPONENT_AT_SCOPE_MEDIUM_MK2', suppressor = AR_SUPP }))

ORInventoryWeapons.Components = {
    weapon_component_flashlight = { label = 'Lanterna tatica', key = 'flashlight', weight = 150, icon = 'L' },
    weapon_component_suppressor = { label = 'Supressor', key = 'suppressor', weight = 350, icon = 'S' },
    weapon_component_grip = { label = 'Empunhadura', key = 'grip', weight = 250, icon = 'G' },
    weapon_component_scope_small = { label = 'Mira curta', key = 'scope_small', weight = 300, icon = 'M' },
    weapon_component_scope_medium = { label = 'Mira media', key = 'scope_medium', weight = 450, icon = 'M' },
    weapon_component_scope_large = { label = 'Mira longa', key = 'scope_large', weight = 650, icon = 'M' },
    weapon_component_extended_mag = { label = 'Pente estendido', key = 'extended_mag', weight = 250, icon = 'P' },
}

ORInventoryWeapons.Ammo = {
    -- Cada unidade e uma bala, nao uma caixa/pente inteiro. O maxStack limita
    -- apenas a pilha no inventario; a capacidade real e definida pela arma.
    ammo_pistol = { label = 'Municao de pistola', ammoType = 'pistol', weight = 10, maxStack = 300, icon = '9' },
    ammo_smg = { label = 'Municao de submetralhadora', ammoType = 'smg', weight = 9, maxStack = 300, icon = 'S' },
    ammo_shotgun = { label = 'Cartuchos de escopeta', ammoType = 'shotgun', weight = 33, maxStack = 300, icon = '12' },
    ammo_rifle = { label = 'Municao de fuzil', ammoType = 'rifle', weight = 12, maxStack = 300, icon = 'R' },
    ammo_mg = { label = 'Municao de metralhadora', ammoType = 'mg', weight = 13, maxStack = 300, icon = 'M' },
    ammo_sniper = { label = 'Municao de sniper', ammoType = 'sniper', weight = 42, maxStack = 300, icon = 'S' },
}

for itemName, definition in pairs(ORInventoryWeapons.Weapons) do
    ORInventoryItems[itemName] = { label = definition.label, description = definition.label, durability = definition.durability, weight = definition.weight, maxStack = 1, icon = 'W', type = 'weapon' }
end
for itemName, definition in pairs(ORInventoryWeapons.Components) do
    ORInventoryItems[itemName] = { label = definition.label, weight = definition.weight, maxStack = 5, icon = definition.icon, type = 'weapon_component' }
end
for itemName, definition in pairs(ORInventoryWeapons.Ammo) do
    ORInventoryItems[itemName] = { label = definition.label, weight = definition.weight, maxStack = definition.maxStack or 300, icon = definition.icon, type = 'weapon_ammo' }
end
