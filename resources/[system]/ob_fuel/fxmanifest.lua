fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ob_fuel'
author 'OB Framework'
description 'Combustivel, quilometragem e manutencao da OB Framework'
version '0.1.0'

-- ob_bank e opcional aqui: se estiver parado, o posto cobra dinheiro fisico.
dependencies { 'ob_lib', 'ob_core', 'ob_inventory', 'ob_notification', 'ob_minigame', 'ob_target' }

shared_scripts { '@ob_lib/import.lua', 'shared/config.lua' }
client_script 'client/main.lua'
server_scripts { '@ob_database/import.lua', 'server/main.lua' }

ui_page 'html/index.html'
files { 'html/index.html', 'html/styles.css', 'html/app.js' }
