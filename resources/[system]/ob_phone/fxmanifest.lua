fx_version 'cerulean'
game 'gta5'
lua54 'yes'
name 'ob_phone'
author 'OB Framework'
description 'Celular OB: aplicativos, chamadas de voz e video, viva-voz e bateria'
version '3.19.0'
dependencies { 'ob_lib', 'ob_core', 'ob_inventory', 'ob_notification', 'ob_target' }
shared_script '@ob_lib/import.lua'
shared_script 'config.lua'
client_scripts { 'client/apps.lua', 'client/camera.lua', 'client/main.lua' }
server_scripts { '@ob_database/import.lua', 'server_config.lua', 'server/device.lua', 'server/main.lua', 'server/media.lua', 'server/calls.lua' }
ui_page 'web/index.html'
files { 'web/index.html', 'web/style.css', 'web/media.js', 'web/video-call.js', 'web/app.js', 'web/js/**/*.js', 'web/assets/**/*' }
