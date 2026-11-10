fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'OB Framework'
description 'Assaltos a estabelecimentos - implementacao OB independente de QBCore'
version '1.0.0'
dependencies { 'ob_lib', 'ob_core', 'ob_inventory', 'ob_minigame' }
shared_scripts { '@ob_lib/import.lua', 'config.lua' }
server_script 'server.lua'
client_script 'client.lua'
