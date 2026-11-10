fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ob_documents'
author 'OB Framework'
description 'Documentos pessoais e habilitacoes da OB Framework'
version '1.0.0'

dependencies { 'ob_core', 'ob_inventory' }
shared_script 'config.lua'
server_scripts { '@ob_database/import.lua', 'server/main.lua' }
