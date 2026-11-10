ORAdminConfig = {
    VehicleSpawn = {
        -- O /car usa a posicao exata do jogador ou do veiculo em que ele esta.
        SpawnAtPlayerPosition = true,

        -- Se quem executar estiver no P1 (motorista), guarda/remove o veiculo
        -- atual antes de criar o novo. Passageiros nunca apagam o carro alheio.
        ReplaceCurrentVehicleForDriver = true,

        -- P2, P3, P4... recebem o novo carro temporariamente sem colisao para
        -- que ele consiga sair de dentro do veiculo compartilhado sem empurra-lo.
        PassengerGhostDurationMs = 6000,
    },

    -- Para criar outro cargo, adicione uma entrada aqui. O painel passara a
    -- exibi-lo automaticamente para o owner, sem ser preciso alterar a NUI.
    -- level define a hierarquia: so permite punir cargos de nivel inferior.
    -- Cargos customizados precisam de level positivo; owner e sempre o maior.
    Roles = {
        owner = {
            level = 100,
            label = 'Owner',
            permissions = { ['*'] = true },
        },
        admin = {
            level = 80,
            label = 'Admin',
            permissions = {
                ['panel.open'] = true,
                ['players.view'] = true,
                ['offline.players.view'] = true,
                ['offline.inventory.view'] = true,
                ['player.appearance'] = true,
                ['player.goto'] = true,
                ['player.bring'] = true,
                ['player.heal'] = true,
                ['player.revive'] = true,
                ['player.kick'] = true,
                ['account.ban'] = true,
                ['character.slots'] = true,
                ['character.delete'] = true,
                ['character.block'] = true,
                ['player.revive_full'] = true,
                ['vehicle.fix'] = true,
                ['vehicle.spawn'] = true,
                ['vehicle.delete'] = true,
                ['tools.noclip'] = true,
                ['tools.wall'] = true,
                ['tools.wallmap'] = true,
                ['world.weather'] = true,
                ['world.time'] = true,
                ['world.garages'] = true,
                ['world.shops'] = true,
                ['world.stores'] = true,
                ['world.doors'] = true,
                ['inventory.give'] = true,
            },
        },
        dev = {
            level = 60,
            label = 'Desenvolvedor',
            permissions = {
                ['panel.open'] = true,
                ['players.view'] = true,
                ['player.appearance'] = true,
                ['player.goto'] = true,
                ['player.bring'] = true,
                ['player.heal'] = true,
                ['player.revive'] = true,
                ['player.revive_full'] = true,
                ['vehicle.fix'] = true,
                ['vehicle.spawn'] = true,
                ['vehicle.delete'] = true,
                ['tools.noclip'] = true,
                ['tools.wall'] = true,
                ['tools.wallmap'] = true,
                ['world.weather'] = true,
                ['world.time'] = true,
                ['world.garages'] = true,
                ['world.shops'] = true,
                ['world.stores'] = true,
                ['world.doors'] = true,
            },
        },
        staff = {
            level = 40,
            label = 'Staff',
            permissions = {
                ['panel.open'] = true,
                ['players.view'] = true,
                ['player.appearance'] = true,
                ['player.goto'] = true,
                ['player.bring'] = true,
                ['player.heal'] = true,
                ['player.revive'] = true,
                ['player.kick'] = true,
                ['tools.wall'] = true,
                ['tools.wallmap'] = true,
            },
        },
        var = {
            level = 20,
            label = 'VAR',
            permissions = {
                ['panel.open'] = true,
                ['players.view'] = true,
                ['player.appearance'] = true,
                ['tools.wall'] = true,
                ['tools.wallmap'] = true,
            },
        },
    },
    DefaultRole = 'admin',
}
