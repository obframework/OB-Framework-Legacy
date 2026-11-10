fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ob_mdt'
author 'OB Framework'
description 'MDT policial e jurídico integrado à OB Framework'
version '0.1.0'

dependencies {
    'ob_lib',
    'ob_core',
    'ob_admin',
    'ob_org',
    'ob_prison',
    'ob_notification',
}

ui_page 'html/index.html'

shared_scripts {
    '@ob_lib/import.lua',
    'shared/config.lua',
    'shared/crimes.lua',
}

client_script 'client/main.lua'

server_scripts {
    -- O import resolve o ob_database normalmente. Nao declarar o banco como
    -- dependency: nesta instalacao o FXServer falha no restart isolado.
    '@ob_database/import.lua',
    'server/main.lua',
}

files {
    'html/index.html',
    'html/styles.css',
    'html/app.js',
}
