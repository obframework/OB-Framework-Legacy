fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'ob_notification'
author 'OB Framework'
description 'Notificacoes padrao da OB Framework'
version '0.1.0'

dependency 'ob_lib'
shared_script '@ob_lib/import.lua'
client_script 'client/main.lua'
server_script 'server/main.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/styles.css',
    'html/app.js',
}
