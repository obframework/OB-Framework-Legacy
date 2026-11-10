local resource=GetCurrentResourceName()
local casings={}
local casingZones={}
local casingCells={}
local labZones={}
local lastShotAt=0
local selectedWeaponInfo
local selectedWeaponHash
local nextWeaponRefresh=0
local labOpen=false
local currentLab
local magnifierActive=false

local function isPolice()
    local organisation=LocalPlayer.state['ob:org']
    return type(organisation)=='table' and type(organisation.key)=='string'
        and organisation.key:lower()==tostring(OBEvidenceConfig.Permission or 'police'):lower()
        and (OBEvidenceConfig.RequireDuty==false or organisation.onDuty==true)
end

local function unregister(id)
    if GetResourceState('ob_target')=='started' then exports.ob_target:UnregisterZone(id) end
end

local function closeLab()
    if not labOpen then return end
    labOpen=false
    currentLab=nil
    SetNuiFocus(false,false)
    SendNUIMessage({action='close'})
end

local function refreshLab(open)
    if not currentLab then return end
    local data,message=OR.Callback.await('evidenceLabData',currentLab)
    if not data then
        if open then closeLab() end
        return OR.Notify(message or 'Laboratorio indisponivel.','error')
    end
    if open then labOpen=true;SetNuiFocus(true,true) end
    SendNUIMessage({action=open and 'open' or 'update',payload=data})
end

local function openLab(labId)
    if labOpen or not isPolice() or LocalPlayer.state['or:downed'] then return end
    currentLab=labId
    refreshLab(true)
end

local function nearestPlayer(maxDistance)
    local here=GetEntityCoords(PlayerPedId())
    local closest,closestDistance
    for _,player in ipairs(GetActivePlayers()) do
        if player~=PlayerId() then
            local ped=GetPlayerPed(player)
            if ped and ped~=0 and DoesEntityExist(ped) then
                local distance=#(here-GetEntityCoords(ped))
                if distance<=(maxDistance or 2.0) and (not closestDistance or distance<closestDistance) then
                    closest,closestDistance=GetPlayerServerId(player),distance
                end
            end
        end
    end
    return closest
end

local function casingCellKey(coords)
    local size=math.max(10.0,tonumber(OBEvidenceConfig.StreamCellSize) or 40.0)
    return ('%s:%s'):format(math.floor((coords.x+0.0)/size),math.floor((coords.y+0.0)/size))
end

local function indexCasing(casing)
    if type(casing)~='table' or type(casing.coords)~='table' then return end
    local id=tonumber(casing.id)
    if not id then return end
    casing.cellKey=casingCellKey(casing.coords)
    casingCells[casing.cellKey]=casingCells[casing.cellKey] or {}
    casingCells[casing.cellKey][id]=true
end

local function unindexCasing(casing,id)
    local key=type(casing)=='table' and casing.cellKey
    if not key or not casingCells[key] then return end
    casingCells[key][id]=nil
    if not next(casingCells[key]) then casingCells[key]=nil end
end

local function removeCasingTarget(entry)
    if not entry or not entry.targetRegistered then return end
    if GetResourceState('ob_target')=='started' and entry.entityOption then
        exports.ob_target:RemoveEntityOption(entry.entityOption)
    end
    entry.targetRegistered=false
end

local function registerCasingTarget(id,entry)
    if not entry or entry.targetRegistered or not entry.object or not DoesEntityExist(entry.object)
        or GetResourceState('ob_target')~='started' then return end
    exports.ob_target:RegisterEntity(entry.entityOption,entry.object,{
        label='Recolher estojos proximos',icon='E',distance=OBEvidenceConfig.CollectDistance or 1.35,
        canInteract=function() return isPolice() and magnifierActive end,
        action=function() TriggerServerEvent(resource..':server:collectCasing',id) end,
        screenRadius=0.022,minimumDot=0.992,
        targetPoint=function(entity)
            local point=GetEntityCoords(entity)
            return vector3(point.x,point.y,point.z+0.025)
        end,
    })
    entry.targetRegistered=true
end

local function removeCasingZone(id)
    local entry=casingZones[id]
    if not entry then return end
    removeCasingTarget(entry)
    if entry.object and DoesEntityExist(entry.object) then
        SetEntityAsMissionEntity(entry.object,true,true)
        DeleteObject(entry.object)
        if DoesEntityExist(entry.object) then DeleteEntity(entry.object) end
    end
    casingZones[id]=nil
end

local function registerCasingZone(casing)
    local id=tonumber(casing and casing.id)
    if not id or type(casing.coords)~='table' then return end
    local current=casingZones[id]
    if current and (current.creating or (current.object and DoesEntityExist(current.object))) then return end
    if current then removeCasingZone(id) end
    local coords=vector3(casing.coords.x+0.0,casing.coords.y+0.0,casing.coords.z+0.0)
    local entityOption=('%s:casing_entity:%s'):format(resource,id)
    casingZones[id]={entityOption=entityOption,creating=true,targetRegistered=false}

    CreateThread(function()
        local propName=(OBEvidenceConfig.CasingProps or {})[casing.ammoType]
            or OBEvidenceConfig.CasingProp or 'w_pi_singleshot_shell'
        local model=joaat(propName)
        if not IsModelInCdimage(model) or not IsModelValid(model) then return end
        RequestModel(model)
        local deadline=GetGameTimer()+5000
        while not HasModelLoaded(model) and GetGameTimer()<deadline do Wait(0) end
        if not HasModelLoaded(model) or not casings[id] or not casingZones[id] then SetModelAsNoLongerNeeded(model);return end
        local object=CreateObjectNoOffset(model,coords.x,coords.y,coords.z+0.035,false,false,false)
        SetModelAsNoLongerNeeded(model)
        if not object or object==0 or not DoesEntityExist(object) then return end
        SetEntityRotation(object,82.0,0.0,(id*47)%360,2,true)
        PlaceObjectOnGroundProperly(object)
        FreezeEntityPosition(object,true)
        SetEntityCollision(object,false,false)
        SetEntityLodDist(object,60)
        if not casingZones[id] then DeleteObject(object);return end
        casingZones[id].object=object
        casingZones[id].creating=false
    end)
end

local function streamCasings()
    local ped=PlayerPedId()
    if not ped or ped==0 then return end
    local here=GetEntityCoords(ped)
    local cellSize=math.max(10.0,tonumber(OBEvidenceConfig.StreamCellSize) or 40.0)
    local renderDistance=math.max(10.0,tonumber(OBEvidenceConfig.PropStreamDistance) or 45.0)
    local targetDistance=math.min(renderDistance,math.max(2.0,tonumber(OBEvidenceConfig.TargetStreamDistance) or 12.0))
    local cellRadius=math.ceil(renderDistance/cellSize)
    local centerX,centerY=math.floor(here.x/cellSize),math.floor(here.y/cellSize)
    local candidates={}
    for x=centerX-cellRadius,centerX+cellRadius do
        for y=centerY-cellRadius,centerY+cellRadius do
            local bucket=casingCells[('%s:%s'):format(x,y)]
            if bucket then
                for id in pairs(bucket) do
                    local casing=casings[id]
                    if casing then
                        local dx,dy=here.x-casing.coords.x,here.y-casing.coords.y
                        local distanceSquared=dx*dx+dy*dy
                        if distanceSquared<=renderDistance*renderDistance then
                            candidates[#candidates+1]={id=id,casing=casing,distanceSquared=distanceSquared}
                        end
                    end
                end
            end
        end
    end
    table.sort(candidates,function(a,b)return a.distanceSquared<b.distanceSquared end)
    local wanted={}
    local renderMaximum=math.max(10,math.floor(tonumber(OBEvidenceConfig.MaximumRenderedCasings) or 80))
    for index=1,math.min(#candidates,renderMaximum) do
        local candidate=candidates[index]
        wanted[candidate.id]=true
        registerCasingZone(candidate.casing)
    end
    for id in pairs(casingZones) do if not wanted[id] then removeCasingZone(id) end end

    local targetMaximum=math.max(1,math.floor(tonumber(OBEvidenceConfig.MaximumTargetCasings) or 24))
    local targets=0
    for _,candidate in ipairs(candidates) do
        local visual=casingZones[candidate.id]
        local enabled=magnifierActive and isPolice() and candidate.distanceSquared<=targetDistance*targetDistance and targets<targetMaximum
        if enabled then targets=targets+1;registerCasingTarget(candidate.id,visual)
        else removeCasingTarget(visual) end
    end
end

local function rebuildTargets()
    for _,zone in pairs(labZones) do unregister(zone) end
    labZones={}
    if GetResourceState('ob_target')~='started' or not isPolice() then return end
    for _,lab in ipairs(OBEvidenceConfig.Labs or {}) do
        local zone=('%s:lab:%s'):format(resource,lab.id)
        exports.ob_target:RegisterSphereZone(zone,{coords=lab.coords,radius=1.15,option={
            label=lab.label or 'Analisar evidencia',icon='A',distance=OBEvidenceConfig.AnalysisDistance or 2.5,
            canInteract=function() return isPolice() end,
            action=function() openLab(lab.id) end,
        }})
        labZones[lab.id]=zone
    end
end

RegisterNetEvent(resource..':client:snapshot',function(entries)
    for id in pairs(casingZones) do removeCasingZone(id) end
    casings={}
    casingCells={}
    for _,entry in ipairs(type(entries)=='table' and entries or {}) do
        local id=tonumber(entry.id)
        if id then casings[id]=entry;indexCasing(entry) end
    end
    rebuildTargets()
    streamCasings()
end)

RegisterNetEvent(resource..':client:addCasing',function(entry)
    if type(entry)~='table' or not tonumber(entry.id) then return end
    local id=tonumber(entry.id)
    if casings[id] then unindexCasing(casings[id],id) end
    casings[id]=entry;indexCasing(entry)
end)

RegisterNetEvent(resource..':client:removeCasing',function(id)
    id=tonumber(id);if not id then return end
    unindexCasing(casings[id],id);casings[id]=nil;removeCasingZone(id)
end)

RegisterNetEvent(resource..':client:scanWeapon',function()
    OR.Notify('Use o computador do laboratorio para selecionar a arma sem equipa-la.','info')
end)

RegisterNetEvent(resource..':client:useFieldKit',function(itemName,slot,label)
    local target=nearestPlayer(2.0)
    if not target then return OR.Notify('Nenhuma pessoa encontrada em ate 2 metros.','error') end
    local completed=OR.Progress.Run({
        label=label or 'Coletando amostra...',duration=4500,canCancel=true,
        animation={dict='missheistdockssetup1clipboard@base',clip='base',flag=49},
    })
    if completed then TriggerServerEvent(resource..':server:useFieldKit',itemName,slot,target) end
end)

RegisterNetEvent(resource..':client:toggleMagnifier',function(enabled)
    magnifierActive=enabled==true
    streamCasings()
    OR.Notify(magnifierActive and 'Lupa equipada. Marcadores e coleta pericial liberados.'
        or 'Lupa guardada. Os estojos continuam visiveis, mas nao podem ser coletados.',magnifierActive and 'success' or 'info')
end)

RegisterNetEvent(resource..':client:refreshLab',function()
    if labOpen then refreshLab(false) end
end)

RegisterNUICallback('close',function(_,cb) closeLab();cb('ok') end)
RegisterNUICallback('refresh',function(_,cb) refreshLab(false);cb('ok') end)
RegisterNUICallback('analyzeCasing',function(_,cb)
    if currentLab then TriggerServerEvent(resource..':server:analyzeCasing',currentLab) end
    cb('ok')
end)
RegisterNUICallback('analyzeFingerprint',function(_,cb)
    if currentLab then TriggerServerEvent(resource..':server:analyzeFingerprint',currentLab) end
    cb('ok')
end)
RegisterNUICallback('scanWeapon',function(data,cb)
    local slot=math.floor(tonumber(data and data.slot) or 0)
    local itemName=type(data)=='table' and tostring(data.itemName or '') or ''
    if slot<1 or itemName=='' then OR.Notify('Selecione uma arma guardada no inventario.','error')
    elseif currentLab then TriggerServerEvent(resource..':server:scanWeapon',slot,itemName,currentLab) end
    cb('ok')
end)

AddEventHandler('ob_target:client:ready',function()
    Wait(250)
    TriggerServerEvent(resource..':server:requestSnapshot')
    rebuildTargets()
end)

AddEventHandler('onClientResourceStart',function(name)
    if name==resource then
        Wait(750);rebuildTargets();TriggerServerEvent(resource..':server:requestSnapshot')
    elseif name=='ob_target' then
        Wait(500)
        for _,entry in pairs(casingZones) do entry.targetRegistered=false end
        rebuildTargets();streamCasings()
    end
end)

AddEventHandler('onClientResourceStop',function(name)
    if name~=resource then return end
    closeLab()
    for id in pairs(casingZones) do removeCasingZone(id) end
    for _,zone in pairs(labZones) do unregister(zone) end
end)

CreateThread(function()
    while true do
        local wait=350
        local ped=PlayerPedId()
        local now=GetGameTimer()
        local hash=GetSelectedPedWeapon(ped)
        if hash~=selectedWeaponHash or now>=nextWeaponRefresh then
            selectedWeaponHash=hash
            selectedWeaponInfo=exports.ob_inventory:GetSelectedWeaponInfo()
            nextWeaponRefresh=now+1000
        end
        local info=selectedWeaponInfo
        if info and tonumber(info.slot) then
            wait=0
            if IsPedShooting(ped) and now-lastShotAt>=(OBEvidenceConfig.ShotCooldownMs or 100) then
                lastShotAt=now
                local point=GetOffsetFromEntityInWorldCoords(ped,0.35,0.05,-0.9)
                local found,ground=GetGroundZFor_3dCoord(point.x,point.y,point.z+1.5,false)
                TriggerServerEvent(resource..':server:shot',info.slot,info.itemName,{x=point.x,y=point.y,z=found and ground+0.02 or point.z})
            end
        end
        Wait(wait)
    end
end)

CreateThread(function()
    local previous=isPolice()
    while true do
        Wait(1500)
        local current=isPolice()
        if current~=previous then
            previous=current
            if current then TriggerServerEvent(resource..':server:requestSnapshot') else magnifierActive=false;TriggerServerEvent(resource..':server:disableMagnifier');closeLab();rebuildTargets() end
        end
    end
end)

AddStateBagChangeHandler('ob:org',nil,function(bagName)
    if bagName~=('player:%s'):format(GetPlayerServerId(PlayerId())) then return end
    SetTimeout(150,function()
        if isPolice() then TriggerServerEvent(resource..':server:requestSnapshot') else magnifierActive=false;TriggerServerEvent(resource..':server:disableMagnifier');closeLab();rebuildTargets() end
    end)
end)

CreateThread(function()
    while true do
        streamCasings()
        Wait(magnifierActive and 350 or 1000)
    end
end)

CreateThread(function()
    while true do
        local wait=750
        if isPolice() and magnifierActive then
            local here=GetEntityCoords(PlayerPedId())
            for id in pairs(casingZones) do
                local entry=casings[id]
                local coords=entry and vector3(entry.coords.x+0.0,entry.coords.y+0.0,entry.coords.z+0.0)
                if coords and #(here-coords)<18.0 then
                    wait=0
                    DrawMarker(2,coords.x,coords.y,coords.z+0.04,0.0,0.0,0.0,0.0,180.0,0.0,0.08,0.08,0.08,255,185,35,180,false,false,2,false,nil,nil,false)
                end
            end
        end
        Wait(wait)
    end
end)
