fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ob_economy'
author 'OB Framework'
description 'Tesouro e auditoria economica opcionais da OB Framework'
version '0.1.0'

dependencies { 'ob_lib', 'ob_core' }

shared_scripts {
    '@ob_lib/import.lua',
    'shared/config.lua',
}

server_scripts {
    '@ob_database/import.lua',
    'server/main.lua',
}

client_script 'client/main.lua'

ui_page 'html/index.html'
files {
    'html/index.html',
    'html/styles.css',
    'html/app.js',
}
