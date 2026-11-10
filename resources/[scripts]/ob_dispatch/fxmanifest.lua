fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Orbis RP'
description 'Central configuravel de chamados para servicos da cidade'

shared_scripts {
    '@ob_lib/import.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua',
    'client/phone.lua'
}
server_script 'server/main.lua'

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/app.css',
    'ui/app.js',
    'phone/index.html',
    'phone/app.css',
    'phone/app.js',
    'phone/icon.svg'
}

dependencies {
    'ob_lib',
    'ob_core',
    'ob_notification',
    'ob_org',
    'ob_phone'
}
