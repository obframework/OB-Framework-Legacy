fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'ob_admin'
author 'OB Framework'
description 'Painel e comandos administrativos da OB Framework'
version '0.1.0'

dependencies {
    'ob_lib',
    'ob_core',
    'ob_inventory',
}

shared_scripts {
    '@ob_lib/import.lua',
    'shared/config.lua',
}

server_scripts {
    '@ob_database/import.lua',
    'server/database.lua',
    'server/main.lua',
}

client_script 'client/main.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/styles.css',
    'html/app.js',
}
