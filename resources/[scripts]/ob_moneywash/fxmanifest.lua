fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ob_moneywash'
author 'OB Framework'
description 'Lavagem de dinheiro persistente com maquinas, editor e validacao no servidor'
version '1.0.0'

shared_scripts {
    '@ob_lib/import.lua',
    'shared/config.lua',
}

client_script 'client/main.lua'
server_scripts {
    '@ob_database/import.lua',
    'server/main.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/styles.css',
    'web/scrollbars.css',
    'web/coordinate-editor.css',
    'web/app.js',
}

dependencies {
    'ob_lib',
    'ob_core',
    'ob_inventory',
    'ob_notification',
    'ob_target',
}

