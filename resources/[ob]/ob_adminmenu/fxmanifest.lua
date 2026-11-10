fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ob_adminmenu'
author 'OB Framework'
description 'Menu modular de administracao da OB Framework'
version '0.1.0'

-- ob_database e server_only. Declara-lo aqui faria o cliente recusar o
-- ob_adminmenu mesmo com o servidor tendo iniciado normalmente.
dependencies { 'ob_lib', 'ob_core', 'ob_admin' }

shared_scripts { '@ob_lib/import.lua', 'shared/offline_config.lua' }
server_scripts { '@ob_database/import.lua', 'server/main.lua', 'server/offline.lua' }
client_scripts { 'client/main.lua', 'client/shop_editor.lua' }

ui_page 'html/index.html'
files { 'html/index.html', 'html/styles.css', 'html/garage.css', 'html/offline.css', 'html/app.js', 'html/offline.js', 'html/shop_editor.js', 'html/shop_editor.css', 'data/object_names.txt' }
