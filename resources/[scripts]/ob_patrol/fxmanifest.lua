fx_version 'cerulean'
game 'gta5'

author 'Orbis Roleplay'
description 'Patrulhamento policial com rotas, limite de velocidade e ocorrencias dinamicas'

shared_scripts {
    '@ob_lib/import.lua',
    'config/patrol.lua'
}

client_scripts { 'client/main.lua' }
server_scripts {
    '@ob_database/import.lua',
    'server/main.lua'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/app.css',
    'ui/app.js'
}

dependencies {
    'ob_lib',
    'ob_core',
    'ob_inventory',
    'ob_org',
    'ob_admin',
    'ob_notification',
    'ob_target'
}

lua54 'yes'
