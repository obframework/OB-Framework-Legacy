fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ob_blackout'
author 'OB Framework'
description 'Controle sincronizado de energia da cidade'
version '1.0.0'

dependencies { 'ob_lib', 'ob_core', 'ob_inventory', 'ob_admin', 'ob_notification', 'ob_weather', 'ob_minigame' }

shared_scripts { '@ob_lib/import.lua', 'config.lua' }
server_script 'server/main.lua'
client_script 'client/main.lua'
