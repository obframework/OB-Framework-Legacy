fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'ob_hud'
author 'OB Framework'
description 'HUD propria da OB Framework'
version '0.1.0'

ui_page 'html/index.html'

shared_script 'config.lua'
client_script 'client/main.lua'

files {
    'html/index.html',
    'html/app.css',
    'html/app.js',
    'html/assets/logo.png',
    'html/assets/icons/*.svg',
}

dependencies {
    'ob_core',
    'ob_inventory',
}
