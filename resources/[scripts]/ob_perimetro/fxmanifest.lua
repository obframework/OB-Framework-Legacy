fx_version 'cerulean'
game 'gta5'
author 'OB Framework'
description 'Perimetros policiais com autorizacao no servidor'
version '1.0.0'
dependency 'ob_lib'
shared_scripts { '@ob_lib/import.lua', 'config.lua' }
server_script 'server.lua'
client_script 'client.lua'
ui_page 'html/index.html'
files { 'html/index.html', 'html/style.css', 'html/app.js' }
