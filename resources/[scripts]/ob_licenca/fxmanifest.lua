fx_version 'cerulean'
game 'gta5'
author 'OB Framework'
description 'Centro de habilitacao e consulta policial de documentos'
version '1.0.0'
-- ob_database e server_only: o cliente nao pode recebe-lo como dependency.
-- A importacao abaixo permanece no servidor; server.cfg inicia o banco antes.
dependencies { 'ob_lib', 'ob_core', 'ob_inventory' }
shared_scripts { '@ob_lib/import.lua', 'config.lua' }
server_scripts { '@ob_database/import.lua', 'server/questions.lua', 'server/main.lua' }
client_script 'client/main.lua'
ui_page 'html/index.html'
files { 'html/index.html', 'html/style.css', 'html/app.js' }
