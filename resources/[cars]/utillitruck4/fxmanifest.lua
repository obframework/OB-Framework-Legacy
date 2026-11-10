fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ob_utillitruck'
author 'BigSmoKe07, PNWParksFan; adaptacao OB Framework'
description 'Caminhao utilitario com cesta funcional (utillitruck4)'
version '1.0.3-ob.1'

files {
    'data/vehicles.meta',
    'data/carcols.meta',
    'data/carvariations.meta',
}

data_file 'VEHICLE_METADATA_FILE' 'data/vehicles.meta'
data_file 'CARCOLS_FILE' 'data/carcols.meta'
data_file 'VEHICLE_VARIATION_FILE' 'data/carvariations.meta'

client_script 'client.lua'
server_script 'server.lua'
