fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ob_org'
author 'OB Framework'
description 'Organizacoes legais e ilegais dinamicas da OB Framework'
version '0.1.0'

dependencies {
    'ob_lib',
    'ob_core',
    'ob_inventory',
    'ob_admin',
}

shared_scripts {
    '@ob_lib/import.lua',
    'shared/config.lua',
}

server_scripts {
    -- A base resolve o banco pelo import. Nao declarar ob_database como
    -- dependency: o FXServer desta instalacao falha no restart isolado.
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
