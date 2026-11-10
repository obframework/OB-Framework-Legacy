fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ob_chat'
author 'OB Framework'
description 'Chat de comandos e comunicacao de departamentos da OB Framework'
version '0.1.0'

shared_scripts {
    '@ob_lib/import.lua',
    'config.lua',
}

client_script 'client/main.lua'
server_script 'server/main.lua'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/styles.css',
    'web/app.js',
}

dependencies {
    'ob_lib',
    'ob_core',
    'ob_org',
}
