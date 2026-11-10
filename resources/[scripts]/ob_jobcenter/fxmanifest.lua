fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ob_jobcenter'
author 'OB Framework'
description 'Central provisoria de empregos legais integrada ao ob_org'
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
    'ob_notification',
    'ob_target',
}
