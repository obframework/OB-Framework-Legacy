fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ob_garage'
author 'OB Framework'
description 'Garagem de veiculos da OB Framework'
version '1.0.0'

-- ob_database ja inicia antes de [system] no server.cfg; ele e importado no
-- servidor abaixo e nao pode ser uma dependencia direta neste artefato.
dependencies { 'ob_lib', 'ob_core', 'ob_inventory', 'ob_org', 'ob_target', 'ob_notification', 'ob_vehiclekeys' }

shared_scripts { '@ob_lib/import.lua', 'shared/config.lua' }
client_script 'client/main.lua'
server_scripts { '@ob_database/import.lua', 'server/editor.lua', 'server/main.lua' }

ui_page 'web/index.html'
files { 'web/index.html', 'web/style.css', 'web/app.js', 'web/images/*' }
