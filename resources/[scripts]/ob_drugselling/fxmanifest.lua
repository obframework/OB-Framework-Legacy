fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Orbis RP'
description 'Venda de drogas para NPCs com denuncia policial'

shared_scripts {
    '@ob_lib/import.lua',
    'config.lua'
}

client_script 'client/main.lua'
server_script 'server/main.lua'

dependencies {
    'ob_lib',
    'ob_core',
    'ob_inventory',
    'ob_notification',
    'ob_target',
    'ob_org',
    'ob_dispatch'
}
