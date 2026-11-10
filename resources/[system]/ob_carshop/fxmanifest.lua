fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ob_carshop'
author 'OB Framework'
description 'Concessionarias da OB Framework'
version '1.0.0'

-- ob_database e server_only, portanto entra somente pelo import do servidor
-- abaixo. Declara-lo como dependency faz o FiveM tentar resolve-lo tambem
-- no lado cliente e impede restart deste recurso.
dependencies { 'ob_lib', 'ob_core', 'ob_inventory', 'ob_admin', 'ob_vehiclekeys' }

shared_scripts { '@ob_lib/import.lua', 'shared/config.lua' }
server_scripts { '@ob_database/import.lua', 'server/main.lua' }
client_script 'client/main.lua'
ui_page 'html/index.html'
files { 'html/index.html', 'html/styles.css', 'html/app.js' }
