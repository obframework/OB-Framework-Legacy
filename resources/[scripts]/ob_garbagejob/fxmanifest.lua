fx_version 'cerulean'
game 'gta5'

description 'Lixeiro para OB Framework'
version '1.0.0'

shared_scripts {
	'@ob_lib/import.lua',
	'config/shared.lua',
}

client_scripts {
	'config/client.lua',
	'client/main.lua'
}

server_scripts {
    '@ob_database/import.lua',
    'config/server.lua',
    'server/main.lua'
}

ui_page 'ui/index.html'

files {
	'locales/*.json',
	'ui/index.html',
	'ui/app.css',
	'ui/app.js',
}

dependencies {
    'ob_lib',
    'ob_core',
    'ob_inventory',
    'ob_notification',
    'ob_target',
    'ob_vehiclekeys'
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'
