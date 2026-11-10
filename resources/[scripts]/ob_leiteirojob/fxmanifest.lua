fx_version 'cerulean'
game 'gta5'

author 'OB Framework'
description 'Leiteiro para OB Framework'

shared_scripts {
    '@ob_lib/import.lua',
    'config/*.lua'
}

client_scripts {
    'client/*.lua'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/app.css',
    'ui/app.js'
}

server_scripts {
    '@ob_database/import.lua',
    'server/*.lua'
}

dependencies {
    'ob_lib',
    'ob_core',
    'ob_inventory',
    'ob_notification',
    'ob_target',
    'ob_vehiclekeys'
}

lua54 'yes'
