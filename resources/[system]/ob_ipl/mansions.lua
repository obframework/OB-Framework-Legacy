-- Nomes dos conjuntos/IDs conferidos no bob74_ipl 2.6.0 (licenca em LICENSE.bob74).
-- Os IPLs carregam a estrutura; os entity sets montam o interior visivel.
local cfg = IplConfig.Mansions
local styles = {
    cali = {'set_style_cali','set_elev_cali','set_art_coastal','set_trophy_planter','set_shelving_planter'},
    loft = {'set_style_loft','set_elev_loft','set_art_loft','set_loft_trophy_planter','set_loft_shelving_planter'},
    holly = {'set_style_holly','set_elev_holly','set_art_regency','set_reg_shelving_planter','set_reg_trophy_planter'},
}
local wallpapers = {'rustic','deco','coastal','subtle','safari','popart'}
local applied, pinned = {}, {}

local function belongsToLocation(interior, location)
    if not interior or interior == 0 or not IsValidInterior(interior) then return false end
    local coords = GetInteriorLocationAndNamehash(interior)
    if not coords then return false end
    local dx, dy = coords.x - location.x, coords.y - location.y
    return dx*dx + dy*dy < 125.0*125.0 and math.abs(coords.z-location.z) < 100.0
end

local function configure(interior, basement)
    if applied[interior] then return end
    if not pinned[interior] then
        PinInteriorInMemory(interior)
        pinned[interior] = true
    end
    if not IsInteriorReady(interior) then return end
    if basement then
        DeactivateInteriorEntitySet(interior, 'set_vault_door_closed')
        ActivateInteriorEntitySet(interior, 'set_vault_door_open')
        ActivateInteriorEntitySet(interior, 'set_elev_std')
        for index=1,3 do DeactivateInteriorEntitySet(interior, ('set_base_ai_tablets_%02d'):format(index)) end
        ActivateInteriorEntitySet(interior, 'set_base_ai_tablets_03')
    else
        for _, names in pairs(styles) do
            for _, name in ipairs(names) do DeactivateInteriorEntitySet(interior, name) end
        end
        for _, name in ipairs(styles[cfg.style] or styles.cali) do ActivateInteriorEntitySet(interior, name) end
        local wallpaper = 'deco'
        for _, name in ipairs(wallpapers) do
            DeactivateInteriorEntitySet(interior, 'set_wallpaper_'..name)
            if name == cfg.wallpaper then wallpaper = name end
        end
        ActivateInteriorEntitySet(interior, 'set_wallpaper_'..wallpaper)
        DeactivateInteriorEntitySet(interior, 'set_style_cali_tint')
        if cfg.style == 'cali' or not styles[cfg.style] then
            ActivateInteriorEntitySet(interior, 'set_style_cali_tint')
            SetInteriorEntitySetColor(interior, 'set_style_cali_tint', math.max(0, math.min(3, tonumber(cfg.tint) or 0)))
        end
        for index=1,3 do DeactivateInteriorEntitySet(interior, ('set_ai_tablets_%02d'):format(index)) end
        ActivateInteriorEntitySet(interior, 'set_ai_tablets_03')
    end
    RefreshInterior(interior)
    applied[interior] = true
end

CreateThread(function()
    if not cfg.enabled or GetGameBuildNumber() < cfg.minimumBuild then return end
    Wait(2000)
    while true do
        for _, location in ipairs(cfg.locations) do
            -- IDs variam entre builds; so aceitar o ID se pertencer a esta mansao.
            local interior = location.interiorId
            if not belongsToLocation(interior, location) then
                interior = GetInteriorAtCoords(location.x, location.y, location.z)
            end
            if belongsToLocation(interior, location) then configure(interior, false) end
            if belongsToLocation(location.basementId, location) then configure(location.basementId, true) end
        end
        Wait(3000) -- tambem tenta novamente se a celula nao existia durante o startup
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for interior in pairs(pinned) do UnpinInterior(interior) end
end)
