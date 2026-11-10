fx_version 'cerulean'
game 'gta5'

name 'ob_animations'
author 'OB Framework'
description 'Animacoes, gestos e emotes da OB Framework'
version '0.1.0'

dependencies {
    'ob_lib',
    'ob_core',
    'ob_notification',
}

shared_scripts {
    '@ob_lib/import.lua',
    'shared/config.lua',
}

client_scripts {
    'client/main.lua',
    'client/combat.lua',
}
server_script 'server/main.lua'

ui_page 'html/index.html'
files {
    'html/index.html',
    'html/styles.css',
    'html/app.js',
}
