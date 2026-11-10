fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'OB Framework'
description 'Emprego de onibus da OB Framework'
version '2.0.0'

shared_scripts {
    '@ob_lib/import.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@ob_database/import.lua',
    'server/main.lua'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/app.css',
    'ui/app.js',
    'ui/vehicles/*.svg',
    'ui/vehicles/*.png',
    'ui/vehicles/*.jpg',
    'ui/vehicles/*.jpeg',
    'ui/vehicles/*.webp'
}

dependencies {
    'ob_lib',
    'ob_core',
    'ob_inventory',
    'ob_notification',
    'ob_target',
    'ob_vehiclekeys'
}
