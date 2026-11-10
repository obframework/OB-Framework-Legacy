fx_version 'cerulean'
game 'gta5'

lua54 'yes'

author 'OB Framework'
description 'Criador de personagem da OB Framework'
version '0.1.0'

dependency 'ob_core'
dependency 'ob_lib'

shared_scripts {
    '@ob_lib/import.lua',
    'config.lua'
}

client_scripts {
    'shared/constants.lua',
    'shared/tattoos.lua',
    'client/appearance.lua',
    'client/main.lua'
}

server_scripts {
    '@ob_database/import.lua',
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/styles.css',
    'html/app.js',
    'shared/catalog.json',
    'html/creator/**/*'
}
