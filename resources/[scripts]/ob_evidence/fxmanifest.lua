fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'ob_evidence'
author 'OB Framework'
description 'Pericia balistica, digitais em armas e coleta de estojos'
version '0.1.0'

dependencies {
    'ob_lib',
    'ob_core',
    'ob_org',
    'ob_inventory',
    'ob_target',
    'ob_notification',
}

shared_scripts {
    '@ob_lib/import.lua',
    'shared/config.lua',
}

client_script 'client/main.lua'

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/app.css',
    'ui/scrollbar.css',
    'ui/app.js',
}

server_scripts {
    '@ob_database/import.lua',
    'server/main.lua',
}
