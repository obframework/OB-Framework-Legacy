fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Orbis RP'
description 'Sistema de fabricacao por bancadas'

shared_scripts {
    '@ob_lib/import.lua',
    'config.lua'
}

client_script 'client/main.lua'

server_scripts {
    '@ob_database/import.lua',
    'server/main.lua'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/app.css',
    'ui/app.js'
}

dependencies {
    'ob_lib',
    'ob_core',
    'ob_inventory',
    'ob_notification',
    'ob_org',
    'ob_target'
}
