fx_version 'cerulean'
game 'gta5'
lua54 'yes'
name 'ob_mecanico'
description 'Oficina, tuning e reparos de veiculos da OB Framework'
version '0.1.0'
dependencies { 'ob_lib', 'ob_core', 'ob_inventory', 'ob_minigame', 'ob_target' }
shared_scripts { '@ob_lib/import.lua', 'shared/config.lua' }
client_script 'client/main.lua'
server_script 'server/main.lua'

ui_page 'html/index.html'
files { 'html/index.html', 'html/styles.css', 'html/app.js' }
