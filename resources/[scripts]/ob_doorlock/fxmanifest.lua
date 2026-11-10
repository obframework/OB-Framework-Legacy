fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ob_doorlock'
author 'OB Framework'
description 'Trancas persistentes com grupos reutilizaveis e editor no jogo'
version '0.2.1'

-- Native lock audio adapted from ox_doorlock (GPL-3.0-or-later).
-- See OX_DOORLOCK_LICENSE in this resource.

dependencies {
    'ob_lib',
    'ob_core',
    'ob_admin',
    'ob_org',
    'ob_notification',
}

shared_scripts {
    '@ob_lib/import.lua',
    'shared/config.lua',
}

server_scripts {
    '@ob_database/import.lua',
    'server/main.lua',
}

client_script 'client/main.lua'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/styles.css',
    'web/app.js',
    'audio/data/oxdoorlock_sounds.dat54.rel',
    'audio/dlc_oxdoorlock/oxdoorlock.awc',
}

data_file 'AUDIO_WAVEPACK' 'audio/dlc_oxdoorlock'
data_file 'AUDIO_SOUNDDATA' 'audio/data/oxdoorlock_sounds.dat'
