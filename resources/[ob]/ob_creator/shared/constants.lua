constants = {}
constants.PED_COMPONENTS_IDS = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11}
constants.PED_PROPS_IDS = {0, 1, 2, 6, 7}

constants.FACE_FEATURES = {
    "noseWidth",
    "nosePeakHigh",
    "nosePeakSize",
    "noseBoneHigh",
    "nosePeakLowering",
    "noseBoneTwist",
    "eyeBrownHigh",
    "eyeBrownForward",
    "cheeksBoneHigh",
    "cheeksBoneWidth",
    "cheeksWidth",
    "eyesOpening",
    "lipsThickness",
    "jawBoneWidth",
    "jawBoneBackSize",
    "chinBoneLowering",
    "chinBoneLenght",
    "chinBoneSize",
    "chinHole",
    "neckThickness",
}

constants.HEAD_OVERLAYS = {
    "blemishes",
    "beard",
    "eyebrows",
    "ageing",
    "makeUp",
    "blush",
    "complexion",
    "sunDamage",
    "lipstick",
    "moleAndFreckles",
    "chestHair",
    "bodyBlemishes",
}

-- Thanks to rootcause for the eye colors names and hair decorations hashes.
constants.EYE_COLORS = {
    "Green",
    "Emerald",
    "Light Blue",
    "Ocean Blue",
    "Light Brown",
    "Dark Brown",
    "Hazel",
    "Dark Gray",
    "Light Gray",
    "Pink",
    "Yellow",
    "Purple",
    "Blackout",
    "Shades of Gray",
    "Tequila Sunrise",
    "Atomic",
    "Warp",
    "ECola",
    "Space Ranger",
    "Ying Yang",
    "Bullseye",
    "Lizard",
    "Dragon",
    "Extra Terrestrial",
    "Goat",
    "Smiley",
    "Possessed",
    "Demon",
    "Infected",
    "Alien",
    "Undead",
    "Zombie",
}

constants.HAIR_DECORATIONS = {
    male = {
        [0] = { GetHashKey('mpbeach_overlays'), GetHashKey('FM_Hair_Fuzz') },
        [1] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_001') },
        [2] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_002') },
        [3] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_003') },
        [4] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_004') },
        [5] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_005') },
        [6] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_006') },
        [7] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_007') },
        [8] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_008') },
        [9] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_009') },
        [10] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_013') },
        [11] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_002') },
        [12] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_011') },
        [13] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_012') },
        [14] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_014') },
        [15] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_015') },
        [16] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGBea_M_Hair_000') },
        [17] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGBea_M_Hair_001') },
        [18] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGBus_M_Hair_000') },
        [19] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGBus_M_Hair_001') },
        [20] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGHip_M_Hair_000') },
        [21] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGHip_M_Hair_001') },
        [22] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGInd_M_Hair_000') },
        [24] = { GetHashKey('mplowrider_overlays'), GetHashKey('LR_M_Hair_000') },
        [25] = { GetHashKey('mplowrider_overlays'), GetHashKey('LR_M_Hair_001') },
        [26] = { GetHashKey('mplowrider_overlays'), GetHashKey('LR_M_Hair_002') },
        [27] = { GetHashKey('mplowrider_overlays'), GetHashKey('LR_M_Hair_003') },
        [28] = { GetHashKey('mplowrider2_overlays'), GetHashKey('LR_M_Hair_004') },
        [29] = { GetHashKey('mplowrider2_overlays'), GetHashKey('LR_M_Hair_005') },
        [30] = { GetHashKey('mplowrider2_overlays'), GetHashKey('LR_M_Hair_006') },
        [31] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_000_M') },
        [32] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_001_M') },
        [33] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_002_M') },
        [34] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_003_M') },
        [35] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_004_M') },
        [36] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_005_M') },
        [37] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_001') },
        [38] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_002') },
        [39] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_003') },
        [40] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_004') },
        [41] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_005') },
        [42] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_006') },
        [43] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_007') },
        [44] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_008') },
        [45] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_009') },
        [46] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_013') },
        [47] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_002') },
        [48] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_011') },
        [49] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_012') },
        [50] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_014') },
        [51] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_015') },
        [52] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGBea_M_Hair_000') },
        [53] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGBea_M_Hair_001') },
        [54] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGBus_M_Hair_000') },
        [55] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGBus_M_Hair_001') },
        [56] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGHip_M_Hair_000') },
        [57] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGHip_M_Hair_001') },
        [58] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGInd_M_Hair_000') },
        [59] = { GetHashKey('mplowrider_overlays'), GetHashKey('LR_M_Hair_000') },
        [60] = { GetHashKey('mplowrider_overlays'), GetHashKey('LR_M_Hair_001') },
        [61] = { GetHashKey('mplowrider_overlays'), GetHashKey('LR_M_Hair_002') },
        [62] = { GetHashKey('mplowrider_overlays'), GetHashKey('LR_M_Hair_003') },
        [63] = { GetHashKey('mplowrider2_overlays'), GetHashKey('LR_M_Hair_004') },
        [64] = { GetHashKey('mplowrider2_overlays'), GetHashKey('LR_M_Hair_005') },
        [65] = { GetHashKey('mplowrider2_overlays'), GetHashKey('LR_M_Hair_006') },
        [66] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_000_M') },
        [67] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_001_M') },
        [68] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_002_M') },
        [69] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_003_M') },
        [70] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_004_M') },
        [71] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_005_M') },
        [72] = { GetHashKey('mpgunrunning_overlays'), GetHashKey('MP_Gunrunning_Hair_M_000_M') },
        [73] = { GetHashKey('mpgunrunning_overlays'), GetHashKey('MP_Gunrunning_Hair_M_001_M') },
        [74] = { GetHashKey('mpVinewood_overlays'), GetHashKey('MP_Vinewood_Hair_M_000_M') },
        [75] = { GetHashKey('mptuner_overlays'), GetHashKey('MP_Tuner_Hair_001_M') },
        [76] = { GetHashKey('mpsecurity_overlays'), GetHashKey('MP_Security_Hair_001_M') },
    },

    female = {
        [0] = { GetHashKey('mpbeach_overlays'), GetHashKey('FM_Hair_Fuzz') },
        [1] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_001') },
        [2] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_002') },
        [3] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_003') },
        [4] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_004') },
        [5] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_005') },
        [6] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_006') },
        [7] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_007') },
        [8] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_008') },
        [9] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_009') },
        [10] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_010') },
        [11] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_011') },
        [12] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_012') },
        [13] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_013') },
        [14] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_014') },
        [15] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_015') },
        [16] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGBea_F_Hair_000') },
        [17] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGBea_F_Hair_001') },
        [18] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_007') },
        [19] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGBus_F_Hair_000') },
        [20] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGBus_F_Hair_001') },
        [21] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGBea_F_Hair_001') },
        [22] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGHip_F_Hair_000') },
        [23] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGInd_F_Hair_000') },
        [25] = { GetHashKey('mplowrider_overlays'), GetHashKey('LR_F_Hair_000') },
        [26] = { GetHashKey('mplowrider_overlays'), GetHashKey('LR_F_Hair_001') },
        [27] = { GetHashKey('mplowrider_overlays'), GetHashKey('LR_F_Hair_002') },
        [28] = { GetHashKey('mplowrider2_overlays'), GetHashKey('LR_F_Hair_003') },
        [29] = { GetHashKey('mplowrider2_overlays'), GetHashKey('LR_F_Hair_003') },
        [30] = { GetHashKey('mplowrider2_overlays'), GetHashKey('LR_F_Hair_004') },
        [31] = { GetHashKey('mplowrider2_overlays'), GetHashKey('LR_F_Hair_006') },
        [32] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_000_F') },
        [33] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_001_F') },
        [34] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_002_F') },
        [35] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_003_F') },
        [36] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_003') },
        [37] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_006_F') },
        [38] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_004_F') },
        [39] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_001') },
        [40] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_002') },
        [41] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_003') },
        [42] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_004') },
        [43] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_005') },
        [44] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_006') },
        [45] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_007') },
        [46] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_008') },
        [47] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_009') },
        [48] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_010') },
        [49] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_011') },
        [50] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_012') },
        [51] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_013') },
        [52] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_014') },
        [53] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_M_Hair_015') },
        [54] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGBea_F_Hair_000') },
        [55] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGBea_F_Hair_001') },
        [56] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_007') },
        [57] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGBus_F_Hair_000') },
        [58] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGBus_F_Hair_001') },
        [59] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGBea_F_Hair_001') },
        [60] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGHip_F_Hair_000') },
        [61] = { GetHashKey('multiplayer_overlays'), GetHashKey('NGInd_F_Hair_000') },
        [62] = { GetHashKey('mplowrider_overlays'), GetHashKey('LR_F_Hair_000') },
        [63] = { GetHashKey('mplowrider_overlays'), GetHashKey('LR_F_Hair_001') },
        [64] = { GetHashKey('mplowrider_overlays'), GetHashKey('LR_F_Hair_002') },
        [65] = { GetHashKey('mplowrider2_overlays'), GetHashKey('LR_F_Hair_003') },
        [66] = { GetHashKey('mplowrider2_overlays'), GetHashKey('LR_F_Hair_003') },
        [67] = { GetHashKey('mplowrider2_overlays'), GetHashKey('LR_F_Hair_004') },
        [68] = { GetHashKey('mplowrider2_overlays'), GetHashKey('LR_F_Hair_006') },
        [69] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_000_F') },
        [70] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_001_F') },
        [71] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_002_F') },
        [72] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_003_F') },
        [73] = { GetHashKey('multiplayer_overlays'), GetHashKey('NG_F_Hair_003') },
        [74] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_006_F') },
        [75] = { GetHashKey('mpbiker_overlays'), GetHashKey('MP_Biker_Hair_004_F') },
        [76] = { GetHashKey('mpgunrunning_overlays'), GetHashKey('MP_Gunrunning_Hair_F_000_F') },
        [77] = { GetHashKey('mpgunrunning_overlays'), GetHashKey('MP_Gunrunning_Hair_F_001_F') },
        [78] = { GetHashKey('mpVinewood_overlays'), GetHashKey('MP_Vinewood_Hair_F_000_F') },
        [79] = { GetHashKey('mptuner_overlays'), GetHashKey('MP_Tuner_Hair_000_F') },
        [80] = { GetHashKey('mpsecurity_overlays'), GetHashKey('MP_Security_Hair_000_F') },
    },
}

constants.DATA_CLOTHES = {
    head = {
        animations = {
            on = {
                dict = "mp_masks@standard_car@ds@",
                anim = "put_on_mask",
                move = 51,
                duration = 600
            },
            off = {
                dict = "missheist_agency2ahelmet",
                anim = "take_off_helmet_stand",
                move = 51,
                duration = 1200
            }
        },
        components = {
            male = {
                {1, 0}
            },
            female = {
                {1, 0}
            }
        },
        props = {
            male = {
                {0, -1}
            },
            female = {}
        }
    },
    body = {
        animations = {
            on = {
                dict = "clothingtie",
                anim = "try_tie_negative_a",
                move = 51,
                duration = 1200
            },
            off = {
                dict = "clothingtie",
                anim = "try_tie_negative_a",
                move = 51,
                duration = 1200
            }
        },
        components = {
            male = {
                {11, 252},
                {3, 15},
                {8, 15},
                {10, 0},
                {5, 0}
            },
            female = {
                {11, 15},
                {8, 14},
                {3, 15},
                {10, 0},
                {5, 0}
            }
        },
        props = {
            male = {},
            female = {}
        }
    },
    bottom = {
        animations = {
            on = {
                dict = "re@construction",
                anim = "out_of_breath",
                move = 51,
                duration = 1300
            },
            off = {
                dict = "re@construction",
                anim = "out_of_breath",
                move = 51,
                duration = 1300
            }
        },
        components = {
            male = {
                {4, 61},
                {6, 34}
            },
            female = {
                {4, 15},
                {6, 35}
            }
        },
        props = {
            male = {},
            female = {}
        }
    }
}

constants.CAMERAS = {
    default = {
        vec3(0, 2.2, 0.2),
        vec3(0, 0, -0.05),
    },
    head = {
        vec3(0, 0.9, 0.65),
        vec3(0, 0, 0.6),
    },
    body = {
        vec3(0, 1.2, 0.2),
        vec3(0, 0, 0.2),
    },
    bottom = {
        vec3(0, 0.98, -0.7),
        vec3(0, 0, -0.9),
    },
}

constants.OFFSETS = {
    default = vec2(1.5, -1),
    head = vec2(0.7, -0.45),
    body = vec2(1.2, -0.45),
    bottom = vec2(0.7, -0.45),
}
