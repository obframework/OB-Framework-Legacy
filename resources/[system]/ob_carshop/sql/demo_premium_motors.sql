-- OB Framework / ob_carshop
-- Loja publica de teste, NPC e catalogo com estoque de 10 unidades por veiculo.
-- Execute este arquivo uma vez no banco orcore, depois reinicie ob_carshop.

INSERT INTO ob_carshops
    (label, shop_type, owner_user_id, access_json, delivery_json, test_json, blip_sprite, blip_color, blip_scale, blip_short_range, active)
SELECT
    'Premium Motors', 'public', NULL,
    '{"x":-56.4219,"y":-1099.1156,"z":26.4224,"w":30.7028}',
    '{"x":-888.5062,"y":-3207.2808,"z":13.9464,"w":55.2832}',
    '{"x":-47.8838,"y":-1097.4756,"z":26.4223,"w":70.0000}',
    225, 3, 0.82, 1, 1
WHERE NOT EXISTS (SELECT 1 FROM ob_carshops WHERE label = 'Premium Motors');

SET @ob_carshop_id := (SELECT id FROM ob_carshops WHERE label = 'Premium Motors' ORDER BY id DESC LIMIT 1);

INSERT INTO ob_carshop_vehicles (shop_id, model, label, category, price, stock, enabled) VALUES
(@ob_carshop_id, 'blista',       'Dinka Blista',          'Compacto',       18000, 10, 1),
(@ob_carshop_id, 'panto',        'Benefactor Panto',      'Compacto',       14500, 10, 1),
(@ob_carshop_id, 'asea',         'Declasse Asea',         'Sedan',          22000, 10, 1),
(@ob_carshop_id, 'sultan',       'Karin Sultan',          'Esportivo',      85000, 10, 1),
(@ob_carshop_id, 'kuruma',       'Karin Kuruma',          'Esportivo',     112000, 10, 1),
(@ob_carshop_id, 'buffalo',      'Bravado Buffalo',       'Esportivo',      72000, 10, 1),
(@ob_carshop_id, 'futo',         'Karin Futo',            'Compacto',       38000, 10, 1),
(@ob_carshop_id, 'dominator',    'Vapid Dominator',       'Muscle',         76000, 10, 1),
(@ob_carshop_id, 'elegy2',       'Annis Elegy RH8',       'Esportivo',      98000, 10, 1),
(@ob_carshop_id, 'jester',       'Dinka Jester',          'Esportivo',     145000, 10, 1),
(@ob_carshop_id, 'comet2',       'Pfister Comet',         'Esportivo',     125000, 10, 1),
(@ob_carshop_id, 'ninef',        'Obey 9F',               'Esportivo',     138000, 10, 1),
(@ob_carshop_id, 'massacro',     'Dewbauchee Massacro',   'Esportivo',     155000, 10, 1),
(@ob_carshop_id, 'carbonizzare', 'Grotti Carbonizzare',   'Esportivo',     170000, 10, 1),
(@ob_carshop_id, 'feltzer2',     'Benefactor Feltzer',    'Esportivo',     149000, 10, 1),
(@ob_carshop_id, 'turismo2',     'Grotti Turismo R',      'Super',         310000, 10, 1),
(@ob_carshop_id, 'adder',        'Truffade Adder',        'Super',         600000, 10, 1),
(@ob_carshop_id, 'entityxf',     'Overflod Entity XF',    'Super',         520000, 10, 1),
(@ob_carshop_id, 'zentorno',     'Pegassi Zentorno',      'Super',         490000, 10, 1),
(@ob_carshop_id, 'osiris',       'Pegassi Osiris',        'Super',         650000, 10, 1),
(@ob_carshop_id, 'xa21',         'Ocelot XA-21',          'Super',         710000, 10, 1),
(@ob_carshop_id, 'reaper',       'Pegassi Reaper',        'Super',         680000, 10, 1),
(@ob_carshop_id, 'pfister811',   'Pfister 811',           'Super',         750000, 10, 1),
(@ob_carshop_id, 'neon',         'Pfister Neon',          'Esportivo',     260000, 10, 1),
(@ob_carshop_id, 'baller',       'Gallivanter Baller',    'SUV',           110000, 10, 1),
(@ob_carshop_id, 'granger',      'Declasse Granger',      'SUV',            95000, 10, 1),
(@ob_carshop_id, 'dubsta',       'Benefactor Dubsta',     'SUV',           135000, 10, 1),
(@ob_carshop_id, 'mesa',         'Canis Mesa',            'SUV',            76000, 10, 1),
(@ob_carshop_id, 'bison',        'Bravado Bison',         'Utilitario',     70000, 10, 1),
(@ob_carshop_id, 'rumpo',        'Bravado Rumpo',         'Utilitario',     65000, 10, 1),
(@ob_carshop_id, 'bf400',        'Nagasaki BF400',        'Moto',           45000, 10, 1),
(@ob_carshop_id, 'bati',         'Pegassi Bati 801',      'Moto',           68000, 10, 1),
(@ob_carshop_id, 'akuma',        'Dinka Akuma',           'Moto',           57000, 10, 1),
(@ob_carshop_id, 'daemon',       'Western Daemon',        'Moto',           42000, 10, 1),
(@ob_carshop_id, 'double',       'Dinka Double-T',        'Moto',           64000, 10, 1),
(@ob_carshop_id, 'faggio',       'Pegassi Faggio',        'Moto',            9000, 10, 1),
(@ob_carshop_id, 'hakuchou',     'Shitzu Hakuchou',       'Moto',           90000, 10, 1),
(@ob_carshop_id, 'innovation',   'LCC Innovation',        'Moto',           88000, 10, 1),
(@ob_carshop_id, 'nemesis',      'Principe Nemesis',      'Moto',           30000, 10, 1),
(@ob_carshop_id, 'pcj',          'Shitzu PCJ 600',        'Moto',           26000, 10, 1)
ON DUPLICATE KEY UPDATE
    label = VALUES(label), category = VALUES(category), price = VALUES(price), stock = VALUES(stock), enabled = VALUES(enabled);
