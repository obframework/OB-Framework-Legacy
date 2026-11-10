fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ob_starterkit'
author 'OB Framework'
description 'Kit inicial entregue uma unica vez ao criar o personagem'
version '1.0.0'

shared_scripts {
    '@ob_lib/import.lua',
    'config.lua',
}

server_scripts {
    '@ob_database/import.lua',
    'server/main.lua',
}

dependencies {
    'ob_lib',
    'ob_core',
    'ob_inventory',
    'ob_phone',
    'ob_notification',
}
