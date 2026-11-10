fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ob_radiumenu'
author 'OB Framework'
description 'Menu radial de acoes rapidas'
version '0.1.0'

dependencies { 'ob_core', 'ob_lib', 'ob_creator', 'ob_health' }

shared_script '@ob_lib/import.lua'
client_script 'client/main.lua'
server_scripts { '@ob_database/import.lua', 'server/main.lua' }

ui_page 'html/index.html'
files { 'html/index.html', 'html/styles.css', 'html/app.js' }
