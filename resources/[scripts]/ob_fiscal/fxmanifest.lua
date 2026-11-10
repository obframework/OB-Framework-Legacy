fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ob_fiscal'
author 'OB Framework'
description 'Declaracoes fiscais, lavagem empresarial e investigacao financeira opcional'
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
    'web/app.js',
}

dependencies {
    'ob_lib',
    'ob_core',
    'ob_notification',
}
