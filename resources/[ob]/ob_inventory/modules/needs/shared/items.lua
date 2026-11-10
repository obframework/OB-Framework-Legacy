-- Carregado no cliente e servidor antes dos modulos e das lojas.
-- O cadastro editavel fica exclusivamente em data/needs.lua.
for name, config in pairs(ORInventoryNeedsConfig.Consumables or {}) do
    if type(name) ~= 'string' or not name:match('^[a-z0-9_%-]+$') or type(config) ~= 'table' then
        print(('[ob_inventory] Consumivel invalido em data/needs.lua: %s'):format(tostring(name)))
    elseif ORInventoryItems[name] then
        -- Nao sobrescrever armas, materiais ou itens registrados por outro modulo.
        print(('[ob_inventory] Item duplicado: %s. Mantenha o cadastro da comida somente em data/needs.lua.'):format(name))
    else
        local definition = {}
        for key, value in pairs(config) do definition[key] = value end
        definition.type = 'consumable'
        definition.label = definition.label or name
        definition.weight = definition.weight or 0
        definition.maxStack = definition.maxStack or 10
        ORInventoryItems[name] = definition
    end
end
