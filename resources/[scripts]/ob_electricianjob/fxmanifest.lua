fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'OB Framework'
description 'Trabalho cooperativo de eletricista'

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
    'ui/app.js',
    'ui/repair.js',
    'ui/repair.css'
}

dependencies {
    'ob_lib',
    'ob_core',
    'ob_inventory',
    'ob_notification',
    'ob_target',
    'ob_vehiclekeys',
    'utillitruck4'
}
