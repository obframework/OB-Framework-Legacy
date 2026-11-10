fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'ob_diagnostics'
author 'OB Framework'
description 'Diagnostico persistente de desconexoes e crashes de cliente'
version '0.1.0'

dependencies {
    'ob_core',
}

shared_script 'config.lua'

client_script 'client/main.lua'

server_scripts {
    '@ob_database/import.lua',
    'server/main.lua',
}
