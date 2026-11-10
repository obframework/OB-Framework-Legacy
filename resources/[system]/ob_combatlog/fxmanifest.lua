fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ob_combatlog'
author 'OB Framework'
description 'Avisos de saida e combat log'
version '1.0.0'

dependencies { 'ob_core', 'ob_lib' }

shared_scripts {
    '@ob_lib/import.lua',
    'config.lua',
}
client_script 'client/main.lua'
server_script 'server/main.lua'
