fx_version 'cerulean'
game 'gta5'
lua54 'yes'
name 'ob_vehiclekeys'
description 'Chaves independentes, reservas e lockpick da OB Framework'
dependencies { 'ob_lib', 'ob_core', 'ob_inventory', 'ob_notification' }
shared_scripts { '@ob_lib/import.lua', 'shared/config.lua' }
server_scripts { '@ob_database/import.lua', 'server/main.lua', 'server/ignition.lua' }
client_script 'client/main.lua'
