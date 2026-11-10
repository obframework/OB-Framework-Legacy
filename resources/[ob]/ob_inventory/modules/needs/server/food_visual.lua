-- Somente o servidor publica player state: compativel com sv_stateBagStrictMode.
-- Este evento replica APENAS o visual; nunca consome itens nem altera necessidades.
local active, serial = {}, 0
local function clear(src, entry)
    if active[src] ~= entry then return end
    active[src] = nil
    if entry.published and GetPlayerName(src) then Player(src).state:set('ob:foodVisual', nil, true) end
end

RegisterNetEvent('ob_inventory:server:foodVisual', function(name, token)
    local src = tonumber(source)
    if not src or not GetPlayerName(src) or type(token) ~= 'number'
        or token ~= token or token < 1 or token > 2147483647 or token % 1 ~= 0 then return end
    local current = active[src]
    if name == nil then
        if current and current.clientToken == token then clear(src, current) end
        return
    end
    if current or type(name) ~= 'string' or #name > 64 then return end
    local food = (ORInventoryNeedsConfig.Consumables or {})[name]
    local use = food and food.use
    if not use or type(use.prop) ~= 'table' then return end
    if not OR.Security.rateLimit(src, 'inventory:food_visual', 3, 5000) then return end
    local userId = exports.ob_core:GetUserId(src)
    if not userId then return end
    local entry = { clientToken = token, userId = userId }
    active[src] = entry -- Reserva antes do acesso ao inventario, que pode aguardar SQL.
    SetTimeout(math.max(500, math.min(30000, tonumber(use.duration) or 5000)) + 3000, function()
        clear(src, entry)
    end)
    local ok, amount = pcall(ORInventory.GetItemCount, src, name)
    if active[src] ~= entry then return end -- Cancelado/desconectado durante o await.
    if not ok or (tonumber(amount) or 0) < 1 or not GetPlayerName(src)
        or exports.ob_core:GetUserId(src) ~= userId then
        clear(src, entry)
        return
    end
    serial = serial + 1
    entry.published = true
    Player(src).state:set('ob:foodVisual', { name = name, token = serial }, true)
end)

AddEventHandler('playerDropped', function() active[tonumber(source)] = nil end)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() and resource ~= 'ob_foodprops' then return end
    for src, entry in pairs(active) do clear(src, entry) end
end)
