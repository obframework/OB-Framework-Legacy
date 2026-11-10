fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'ob_inventory'
author 'OB Framework'
description 'Inventario proprio da OB Framework'
version '0.1.0'

dependencies {
    'ob_lib',
    'ob_core',
    'ob_notification',
    'ob_target',
}

shared_scripts {
    '@ob_lib/import.lua',
    'data/config.lua',
    'data/items.lua',
    'data/money.lua',
    'data/needs.lua',
    'data/shops.lua',
    'data/weapons.lua',
    'modules/needs/shared/items.lua',
}

server_scripts {
    '@ob_database/import.lua',
    'modules/needs/server/main.lua',
    'modules/weapons/server/main.lua',
    'modules/inventory/server/main.lua',
    'modules/money/server/main.lua',
    'modules/shops/server/defaults.lua',
    'modules/shops/server/editor.lua',
    'modules/shops/server/business.lua',
    'modules/shops/server/main.lua',
}

client_scripts {
    'modules/needs/client/main.lua',
    'modules/weapons/client/main.lua',
    'modules/inventory/client/main.lua',
    'modules/shops/client/main.lua',
    'modules/shops/client/business.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/styles.css',
    'html/app.js',
    'html/assets/items/*',
}
