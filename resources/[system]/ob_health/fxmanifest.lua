fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'ob_health'
author 'OB Framework'
description 'Estados de morte, reanimacao e primeiros socorros da OB Framework'
version '0.1.0'

dependencies {
    'ob_lib',
    'ob_core',
    'ob_org',
    'ob_target',
    'ob_inventory',
}

shared_scripts {
    '@ob_lib/import.lua',
    'shared/config.lua',
}

server_scripts {
    '@ob_database/import.lua',
    'server/main.lua',
    'server/injuries.lua',
    'server/stretcher.lua',
    'server/npc.lua',
}

client_scripts {
    'client/main.lua',
    'client/injuries.lua',
    'client/stretcher.lua',
    'client/npc.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/styles.css',
    'html/app.js',
}
