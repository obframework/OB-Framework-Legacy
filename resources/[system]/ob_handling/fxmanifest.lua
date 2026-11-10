fx_version 'cerulean'
game 'gta5'
author 'OB Framework'
description 'Editor de handling por veiculo, com teste local e exportacao XML'
version '1.0.0'
dependencies { 'ob_lib', 'ob_admin' }
shared_scripts { '@ob_lib/import.lua', 'config.lua' }
client_script 'client.lua'
server_script 'server.lua'
ui_page 'html/index.html'
files { 'html/index.html', 'html/style.css', 'html/xml.js', 'html/app.js' }
