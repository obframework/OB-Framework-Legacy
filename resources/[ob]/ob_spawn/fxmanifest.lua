fx_version 'cerulean'
game 'gta5'

name 'ob_spawn'
description 'Seletor de spawn da OB Framework'
lua54 'yes'

shared_script '@ob_lib/import.lua'

client_script 'client/main.lua'

server_script 'server/main.lua'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/mapa.jpg',
}

dependencies {
    'ob_lib',
    'ob_core',
}
