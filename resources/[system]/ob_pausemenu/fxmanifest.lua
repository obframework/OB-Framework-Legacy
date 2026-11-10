fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'ob_pausemenu'
author 'OB Framework'
description 'Menu de pausa personalizado da OB Framework'
version '0.1.0'

ui_page 'web/index.html'

shared_script 'config.lua'
client_script 'client/main.lua'
server_script 'server/main.lua'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/assets/logo.png',
    'web/assets/mapa.jpg',
    'web/assets/atlas_calibrado.jpg',
    'web/assets/blips/*'
}

dependencies {
    'ob_core'
}
