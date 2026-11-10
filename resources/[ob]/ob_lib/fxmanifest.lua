fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'ob_lib'
author 'OB Framework'
description 'Primitivos sem dependencia externa para recursos OR'
version '0.3.0'

ui_page 'web/index.html'

-- Tambem empacota as APIs que os resources importam com @ob_lib/.
shared_scripts {
    'import.lua',
}
server_script 'server/main.lua'
client_script 'client/main.lua'

files {
    'currency.json',
    'locale.json',
    'locales/*.json',
    'imports/**/*.lua',
    'modules/heist/bank_scenes.lua',
    'web/currency.js',
    'web/nui.js',
    'web/theme.css',
    'web/index.html',
}
