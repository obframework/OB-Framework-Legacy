fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ob_prison'
author 'OB Framework'
description 'Prisão persistente, trabalhos e fuga validados pelo servidor'
version '0.1.0'

dependencies {
    'ob_lib',
    'ob_core',
    'ob_inventory',
    'ob_org',
    'ob_admin',
    'ob_notification',
    'ob_minigame',
}

shared_scripts {
    '@ob_lib/import.lua',
    'shared/config.lua',
}

client_script 'client/main.lua'

server_scripts {
    -- O banco e resolvido pelo import. A dependency explicita impede o
    -- restart isolado nesta instalacao do FXServer.
    '@ob_database/import.lua',
    'server/main.lua',
}
