fx_version 'cerulean'
game 'gta5'

name 'ob_drugplants'
author 'OB Framework'
description 'Cultivo persistente de plantas e integração com o ob_crafting'
version '1.0.0'

shared_scripts {
    '@ob_lib/import.lua',
    'config.lua',
}

client_script 'client/main.lua'

server_scripts {
    '@ob_database/import.lua',
    'server/main.lua',
}

dependencies {
    'ob_lib',
    'ob_core',
    'ob_inventory',
    'ob_notification',
    'ob_target',
}

