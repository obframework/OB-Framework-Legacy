fx_version 'cerulean'
game 'gta5'

name 'ob_police'
author 'OB Framework'
description 'Acoes policiais validadas pelo servidor'
version '0.1.0'

dependencies {
    'ob_lib',
    'ob_core',
    'ob_org',
    'ob_inventory',
    'ob_target',
    'ob_minigame',
    'ob_notification',
    'ob_animations',
}

shared_scripts {
    '@ob_lib/import.lua',
    'shared/config.lua',
}

client_script 'client/main.lua'
server_scripts {
    '@ob_database/import.lua',
    'server/main.lua',
}
