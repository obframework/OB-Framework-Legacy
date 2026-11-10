local panelOpen = false
local panelMode
local selectedOrgId
local world = { duties = {}, routes = {}, chests = {} }
local routePeds = {}
local activeRoute
local routeBlip
local collecting = false
local dutyBusy = false
local chestBusy = false
local dutyBlips = {}

local function notify(message, kind)
    OR.Notify(message or 'Operacao concluida.', kind or 'info')
end

local function closePanel()
    panelOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function requestPanel(mode, orgId)
    return OR.Callback.await('panel', mode, orgId)
end

local function openPanel(mode, orgId)
    CreateThread(function()
        local data, message = requestPanel(mode, orgId)
        if not data then return notify(message or 'Painel indisponivel.', 'error') end
        panelOpen, panelMode, selectedOrgId = true, mode, tonumber(orgId)
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'open', data = data })
    end)
end

RegisterCommand(OBOrgConfig.Commands.legal or 'painel', function() openPanel('legal') end, false)
RegisterCommand(OBOrgConfig.Commands.illegal or 'tablet', function() openPanel('illegal') end, false)

RegisterNetEvent('ob_org:client:openPanel', function(mode)
    openPanel(mode == 'admin' and 'admin' or mode)
end)

RegisterNUICallback('close', function(_, callback) closePanel(); callback({ ok = true }) end)
RegisterNUICallback('selectOrganisation', function(data, callback)
    selectedOrgId = tonumber(data and data.orgId)
    local result, message = requestPanel('admin', selectedOrgId)
    callback({ ok = result ~= nil, data = result, message = message })
end)
RegisterNUICallback('refresh', function(_, callback)
    local result, message = requestPanel(panelMode, selectedOrgId)
    callback({ ok = result ~= nil, data = result, message = message })
end)
RegisterNUICallback('action', function(data, callback)
    data = type(data) == 'table' and data or {}
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local position = { x = coords.x, y = coords.y, z = coords.z, w = GetEntityHeading(ped) }
    local ok, message, extra = OR.Callback.await('action', data.name, data.payload or {}, position, panelMode)
    callback({ ok = ok == true, message = message, extra = extra })
    if ok == true then TriggerEvent('ob_org:client:refreshWorld') end
end)

local function drawText3d(coords, message)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    SetTextFont(4); SetTextScale(0.0, 0.34); SetTextCentre(true); SetTextOutline()
    SetTextColour(255, 255, 255, 235)
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(message); EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function removeRoutePeds()
    for _, ped in pairs(routePeds) do if DoesEntityExist(ped) then DeleteEntity(ped) end end
    routePeds = {}
end

local function spawnRoutePeds()
    removeRoutePeds()
    for _, route in ipairs(world.routes or {}) do
        local model = GetHashKey(route.model or 'g_m_y_mexgoon_01')
        if IsModelInCdimage(model) and IsModelValid(model) then
            RequestModel(model)
            local deadline = GetGameTimer() + 5000
            while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
            if HasModelLoaded(model) then
                local c = route.coords
                local ped = CreatePed(4, model, c.x, c.y, c.z - 1.0, c.w or 0.0, false, false)
                if ped and ped ~= 0 then
                    FreezeEntityPosition(ped, true); SetEntityInvincible(ped, true); SetBlockingOfNonTemporaryEvents(ped, true)
                    routePeds[tonumber(route.id)] = ped
                end
                SetModelAsNoLongerNeeded(model)
            end
        end
    end
end

local function refreshWorld()
    CreateThread(function()
        local data = OR.Callback.await('world')
        if type(data) ~= 'table' then return end
        world = data
        spawnRoutePeds()
    end)
end

RegisterNetEvent('ob_org:client:refreshWorld', refreshWorld)

local function clearDutyBlips()
    for source, blip in pairs(dutyBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
        dutyBlips[source] = nil
    end
end

local function dutyBlipProfile(data)
    local fallback = type((OBOrgConfig.DutyBlips or {}).default) == 'table'
        and OBOrgConfig.DutyBlips.default or {}
    local profile = type(data.blip) == 'table' and data.blip or {}
    return {
        sprite = tonumber(profile.sprite) or tonumber(fallback.sprite) or 1,
        scale = tonumber(profile.scale) or tonumber(fallback.scale) or 0.75,
        colour = tonumber(profile.colour) or tonumber(fallback.colour) or 3,
        helicopterSprite = tonumber(profile.helicopterSprite)
            or tonumber(fallback.helicopterSprite) or 422,
        label = tostring(profile.label or data.orgLabel or data.orgKey or 'Servico'),
    }
end

RegisterNetEvent('ob_org:client:updateDutyBlips', function(players)
    if type(players) ~= 'table' then players = {} end
    local present = {}
    for _, data in ipairs(players) do
        local serverId = tonumber(data.source)
        local coords = type(data.coords) == 'table' and data.coords or nil
        if serverId and coords and tonumber(coords.x) and tonumber(coords.y) and tonumber(coords.z) then
            present[serverId] = true
            local blip = dutyBlips[serverId]
            if not blip or not DoesBlipExist(blip) then
                blip = AddBlipForCoord(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
                dutyBlips[serverId] = blip
            else
                SetBlipCoords(blip, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
            end

            local profile = dutyBlipProfile(data)
            local sprite = profile.sprite
            local playerIndex = GetPlayerFromServerId(serverId)
            if playerIndex and playerIndex ~= -1 then
                local ped = GetPlayerPed(playerIndex)
                if ped and ped ~= 0 and IsPedInAnyHeli(ped) then
                    sprite = profile.helicopterSprite
                end
            end
            SetBlipSprite(blip, sprite)
            SetBlipScale(blip, profile.scale + 0.0)
            SetBlipColour(blip, profile.colour)
            SetBlipDisplay(blip, 4)
            SetBlipAsShortRange(blip, false)
            SetBlipHighDetail(blip, true)
            SetBlipRotation(blip, math.floor(tonumber(data.heading) or 0.0))
            ShowHeadingIndicatorOnBlip(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(profile.label)
            EndTextCommandSetBlipName(blip)
        end
    end

    for serverId, blip in pairs(dutyBlips) do
        if not present[serverId] then
            if DoesBlipExist(blip) then RemoveBlip(blip) end
            dutyBlips[serverId] = nil
        end
    end
end)

local function setRouteBlip(point)
    if routeBlip then RemoveBlip(routeBlip); routeBlip = nil end
    if not point then return end
    routeBlip = AddBlipForCoord(point.x, point.y, point.z)
    SetBlipSprite(routeBlip, 1); SetBlipColour(routeBlip, 3); SetBlipScale(routeBlip, 0.8)
    SetBlipRoute(routeBlip, true); SetBlipRouteColour(routeBlip, 3)
end

local function cancelRoute(showMessage)
    activeRoute, collecting = nil, false
    TriggerServerEvent('ob_org:server:cancelRoute')
    if routeBlip then RemoveBlip(routeBlip); routeBlip = nil end
    if showMessage then notify('Rota cancelada.', 'info') end
end

RegisterNetEvent('ob_org:client:routeRemoved', function(routeId)
    if activeRoute and tonumber(activeRoute.routeId) == tonumber(routeId) then
        cancelRoute(false)
        notify('A rota ativa foi removida pela administracao.', 'error')
    end
end)

RegisterNetEvent('ob_org:client:organisationRemoved', function()
    if activeRoute then cancelRoute(false) end
    notify('A sua organizacao foi excluida pela administracao.', 'error')
    refreshWorld()
end)

local function startRoute(routeId)
    if activeRoute then return notify('Voce ja possui uma rota ativa.', 'error') end
    CreateThread(function()
        local ok, message, route = OR.Callback.await('startRoute', routeId)
        if not ok or type(route) ~= 'table' then return notify(message, 'error') end
        activeRoute = route
        setRouteBlip(route.point)
        notify(message, 'success')
    end)
end

local function openChest(chestId)
    if chestBusy then return end
    chestBusy = true
    CreateThread(function()
        local ok, response = OR.Callback.await('openChest', chestId)
        if not ok or type(response) ~= 'table' then
            notify(response or 'Bau indisponivel.', 'error')
        else
            TriggerEvent('ob_inventory:client:openContainer', response)
        end
        chestBusy = false
    end)
end

local function loadModel(model)
    RequestModel(model); local deadline=GetGameTimer()+5000
    while not HasModelLoaded(model) and GetGameTimer()<deadline do Wait(0) end
    return HasModelLoaded(model)
end

local function collectPoint()
    if collecting or not activeRoute then return end
    collecting = true
    CreateThread(function()
        local ped=PlayerPedId();local dictionary='anim@heists@box_carry@';local object
        RequestAnimDict(dictionary);local deadline=GetGameTimer()+5000
        while not HasAnimDictLoaded(dictionary) and GetGameTimer()<deadline do Wait(0) end
        local model=GetHashKey('prop_cs_cardbox_01')
        if loadModel(model) then
            object=CreateObject(model,0.0,0.0,0.0,false,false,false)
            AttachEntityToEntity(object,ped,GetPedBoneIndex(ped,28422),0.01,-0.02,-0.02,0.0,0.0,0.0,true,true,false,true,1,true)
        end
        FreezeEntityPosition(ped,true)
        if HasAnimDictLoaded(dictionary) then TaskPlayAnim(ped,dictionary,'idle',8.0,-8.0,-1,49,0,false,false,false) end
        Wait(tonumber(activeRoute.collectDuration) or OBOrgConfig.Interaction.collectDuration)
        ClearPedTasks(ped);FreezeEntityPosition(ped,false)
        if object and DoesEntityExist(object) then DeleteEntity(object) end
        if not activeRoute then collecting=false;return end
        local ok,message,nextRoute=OR.Callback.await('collectRoute',activeRoute.routeId,activeRoute.index)
        if ok and type(nextRoute)=='table' then
            activeRoute=nextRoute;setRouteBlip(nextRoute.point)
            notify(nextRoute.completed and ('Rota concluida. Recompensa: '..message) or ('Coleta: '..message),'success')
        else
            notify(message or 'Nao foi possivel concluir a coleta.','error')
        end
        collecting=false
    end)
end

CreateThread(function()
    while true do
        local waitTime=1000
        if LocalPlayer.state['or:loaded']==true and not panelOpen then
            local coords=GetEntityCoords(PlayerPedId())
            if not activeRoute then
                for _,duty in ipairs(world.duties or {}) do
                    local target=vector3(duty.coords.x,duty.coords.y,duty.coords.z);local distance=#(coords-target)
                    if distance<OBOrgConfig.Interaction.drawDistance then
                        waitTime=0;DrawMarker(2,target.x,target.y,target.z+0.15,0,0,0,0,0,0,0.25,0.25,0.25,0,150,255,190,false,true,2,false)
                        if distance<OBOrgConfig.Interaction.useDistance then
                            drawText3d(target+vector3(0,0,0.35),duty.onDuty and '[E] Encerrar ponto' or '[E] Bater ponto')
                            if not dutyBusy and IsControlJustPressed(0,OBOrgConfig.Interaction.key) then
                                dutyBusy=true
                                CreateThread(function()
                                    local ok,message,onDuty=OR.Callback.await('toggleDuty',duty.orgId);notify(message,ok and 'success' or 'error')
                                    if ok then duty.onDuty=onDuty end
                                    dutyBusy=false
                                end)
                            end
                        end
                    end
                end
                for _,route in ipairs(world.routes or {}) do
                    local ped=routePeds[tonumber(route.id)]
                    if ped and DoesEntityExist(ped) then
                        local target=GetEntityCoords(ped);local distance=#(coords-target)
                        if distance<8.0 then waitTime=0 end
                        if distance<OBOrgConfig.Interaction.useDistance then
                            if IsControlJustPressed(0,OBOrgConfig.Interaction.key) then startRoute(route.id) end
                        end
                    end
                end
                for _,chest in ipairs(world.chests or {}) do
                    local target=vector3(chest.coords.x,chest.coords.y,chest.coords.z);local distance=#(coords-target)
                    if distance<OBOrgConfig.Interaction.drawDistance then
                        waitTime=0
                        local red,green,blue=40,170,255
                        if chest.mode=='discard' then red,green,blue=235,75,75 end
                        DrawMarker(2,target.x,target.y,target.z+0.15,0,0,0,0,0,0,0.28,0.28,0.28,red,green,blue,190,false,true,2,false)
                        if distance<OBOrgConfig.Interaction.useDistance then
                            drawText3d(target+vector3(0,0,0.35),('[E] %s'):format(chest.label))
                            if not chestBusy and IsControlJustPressed(0,OBOrgConfig.Interaction.key) then openChest(chest.id) end
                        end
                    end
                end
            else
                waitTime=0
                local point=activeRoute.point;local target=vector3(point.x,point.y,point.z);local distance=#(coords-target)
                if distance<OBOrgConfig.Interaction.drawDistance then DrawMarker(2,target.x,target.y,target.z+0.2,0,0,0,0,0,0,0.3,0.3,0.3,0,150,255,190,false,true,2,false) end
                if distance<OBOrgConfig.Interaction.useDistance and not collecting then
                    drawText3d(target+vector3(0,0,0.35),'[E] Coletar')
                    if IsControlJustPressed(0,OBOrgConfig.Interaction.key) then collectPoint() end
                end
                SetTextFont(4);SetTextScale(0.0,0.38);SetTextCentre(true);SetTextOutline();BeginTextCommandDisplayText('STRING')
                AddTextComponentSubstringPlayerName(('Rota %s/%s - F7 para cancelar'):format(activeRoute.index,activeRoute.total));EndTextCommandDisplayText(0.5,0.94)
                if IsControlJustPressed(0,OBOrgConfig.Interaction.cancelKey) then cancelRoute(true) end
            end
        end
        Wait(waitTime)
    end
end)

CreateThread(function()
    while LocalPlayer.state['or:loaded']~=true do Wait(500) end
    refreshWorld()
end)

AddEventHandler('ob_core:client:characterSelected',function()
    if activeRoute then cancelRoute(false) end
    clearDutyBlips()
    Wait(500)
    refreshWorld()
end)
AddEventHandler('onClientResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    closePanel();removeRoutePeds();clearDutyBlips();if routeBlip then RemoveBlip(routeBlip) end
end)

exports('Open',openPanel)
