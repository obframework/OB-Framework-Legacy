fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ob_weather'
author 'OB Framework'
description 'Clima e horario sincronizados da OB Framework'
version '1.0.0'

dependencies { 'ob_lib', 'ob_core', 'ob_admin', 'ob_notification' }

shared_scripts { '@ob_lib/import.lua', 'config.lua' }
client_script 'client/main.lua'
server_script 'server/main.lua'
