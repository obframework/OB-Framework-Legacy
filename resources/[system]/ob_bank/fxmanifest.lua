fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ob_bank'
author 'OB Framework'
description 'Banco, cartoes e ATMs da OB Framework'
version '1.0.0'

-- ob_database e carregado pelo import abaixo. Nao declarar como dependency:
-- o FiveM desta base nao resolve essa dependencia em restart isolado.
dependencies { 'ob_lib', 'ob_core', 'ob_inventory', 'ob_target', 'ob_notification' }

shared_scripts { '@ob_lib/import.lua', 'shared/config.lua' }
client_script 'client/main.lua'
server_scripts { '@ob_database/import.lua', 'server/main.lua' }

ui_page 'web/index.html'
files { 'web/index.html', 'web/style.css', 'web/fines.css', 'web/app.js' }
