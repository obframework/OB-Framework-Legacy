local cfg = IplConfig.CayoPerico
local loaded, active, blip = false, false, nil
local islandNative = SetIslandEnabled or SetIslandHopperEnabled
local mapNative = SetUseIslandMap or SetToggleMinimapHeistIsland

local function updateIsland(enabled)
    if loaded == enabled then return end
    islandNative('HeistIsland', enabled)
    loaded = enabled
    if not enabled then mapNative(false) end
end

CreateThread(function()
    if not cfg.enabled or GetGameBuildNumber() < 2189 then return end
    if not islandNative or not mapNative then
        print('[ob_ipl] Cayo Perico: natives de ilha indisponiveis neste artifact.')
        return
    end
    active = true
    if cfg.showBlip then
        blip = AddBlipForCoord(cfg.x, cfg.y, cfg.z)
        SetBlipSprite(blip, 455)
        SetBlipColour(blip, 3)
        SetBlipScale(blip, 0.85)
        SetBlipAsShortRange(blip, false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString('Cayo Perico')
        EndTextCommandSetBlipName(blip)
    end
    while active do
        local coords = GetEntityCoords(PlayerPedId())
        local dx, dy = coords.x-cfg.x, coords.y-cfg.y
        local radius = loaded and cfg.unloadRadius or cfg.loadRadius
        updateIsland(dx*dx+dy*dy <= radius*radius)
        Wait(500)
    end
end)

CreateThread(function()
    local islandMap = GetHashKey('h4_fake_islandx')
    local mapContext = GetHashKey('MAP_CanZoom')
    while true do
        local fullMap = active and cfg.showOnMap and IsPauseMenuActive()
            and (not PauseMenuIsContextActive or PauseMenuIsContextActive(mapContext))
        if active and cfg.showOnMap and loaded then
            -- Esta native precisa ser mantida a cada frame, nao so na chegada.
            mapNative(true)
        end
        if fullMap then
            -- Desenha a ilha no mapa de pausa, inclusive quando esta em LS.
            SetRadarAsExteriorThisFrame()
            SetRadarAsInteriorThisFrame(islandMap, 4700.0, -5145.0, 0, 0)
        end
        Wait((fullMap or (active and loaded and cfg.showOnMap)) and 0 or 250)
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    active = false
    if loaded then updateIsland(false) end
    if blip then RemoveBlip(blip) end
end)
