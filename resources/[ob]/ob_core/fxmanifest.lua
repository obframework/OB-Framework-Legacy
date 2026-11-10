fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'ob_core'
author 'OB Framework'
description 'Nucleo de jogadores, personagens, permissoes e persistencia da OB Framework'
version '0.2.0'

dependencies {
    'ob_lib',
}

shared_scripts {
    '@ob_lib/import.lua',
    'shared/config.lua',
}

server_scripts {
    '@ob_database/import.lua',
    'server/database.lua',
    'server/players.lua',
    'server/access.lua',
    'server/main.lua',
    'server/vehicle_tuning.lua',
    'server/vehicles.lua',
}

client_scripts {
    'client/objects.lua',
    'client/main.lua',
    'client/vehicle_tuning.lua',
    'client/vehicles.lua',
}

ui_page 'html/index.html'
files { 'html/index.html', 'html/styles.css', 'html/app.js' }
