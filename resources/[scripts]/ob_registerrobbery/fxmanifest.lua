fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'OB Framework'
description 'Roubo de registradoras - implementacao OB independente de QBCore'
version '1.0.0'
dependencies { 'ob_lib', 'ob_core', 'ob_inventory', 'ob_minigame' }
shared_scripts { '@ob_lib/import.lua', 'config.lua' }
server_scripts { 'server.lua', 'editor_server.lua' }
client_scripts { 'client.lua', 'editor_client.lua' }
ui_page 'html/index.html'
files { 'html/index.html', 'html/styles.css', 'html/app.js' }
