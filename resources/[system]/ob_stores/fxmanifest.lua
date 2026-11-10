fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ob_stores'
author 'OB Framework'
description 'Pontos de roupas, barbearia e tatuagem da OB Framework'
version '0.1.0'

dependencies { 'ob_core', 'ob_lib', 'ob_creator' }

shared_scripts {
    '@ob_lib/import.lua',
    'shared/config.lua'
}

client_script 'client/main.lua'
server_scripts { '@ob_database/import.lua', 'server/defaults.lua', 'server/editor.lua', 'server/main.lua' }

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/styles.css',
    'html/app.js',
}
