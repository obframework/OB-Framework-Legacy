fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'ob_multichar'
author 'OB Framework'
description 'Selecao visual de personagens da OB Framework'
version '0.1.0'

dependencies {
    'ob_lib',
    'ob_core',
    'ob_creator',
}

shared_scripts {
    '@ob_lib/import.lua',
    'shared/config.lua',
}

client_script 'client/main.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/app.js',
    'html/styles.css',
}
