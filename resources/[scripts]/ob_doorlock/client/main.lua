local groups, doors = {}, {}
local registered = {}
local closestDoor
local editorOpen = false
local capturing = false
local helpVisible = false

local function notify(message, kind)
    if OR and OR.Notify then OR.Notify(message, kind or 'info') end
end

local function indexPayload(payload)
    local nextGroups, nextDoors = {}, {}
    for _, group in ipairs(type(payload) == 'table' and payload.groups or {}) do nextGroups[tonumber(group.id)] = group end
    for _, door in ipairs(type(payload) == 'table' and payload.doors or {}) do nextDoors[tonumber(door.id)] = door end
    return nextGroups, nextDoors
end

local function doorHash(doorId, leafIndex)
    return joaat(('ob_doorlock:%s:%s'):format(doorId, leafIndex))
end

local function removeRegistered()
    for hash,entry in pairs(registered) do
        if entry.registered and IsDoorRegisteredWithSystem(hash) then
            DoorSystemSetDoorState(hash,4,false,false)
            DoorSystemSetDoorState(hash,0,false,false)
            RemoveDoorFromSystem(hash)
        end
    end
    registered = {}
end

local function modelSize(model)
    local minimum,maximum=GetModelDimensions(model)
    return maximum.x-minimum.x,maximum.y-minimum.y,maximum.z-minimum.z
end

local function isDoorShape(model)
    local width,depth,height=modelSize(model)
    local thickness=math.min(math.abs(width),math.abs(depth))
    local span=math.max(math.abs(width),math.abs(depth))
    return height >= (tonumber(OBDoorlock.MinimumDoorHeight) or 0.75)
        and height <= (tonumber(OBDoorlock.MaximumDoorHeight) or 6.0)
        and span >= 0.35 and span <= 8.0
        and thickness <= (tonumber(OBDoorlock.MaximumDoorThickness) or 0.65)
end

local function hasDoorArchetypeName(name)
    name=tostring(name or ''):lower()
    return name:find('door',1,true)~=nil
        or name:find('gate',1,true)~=nil
        or name:find('shutter',1,true)~=nil
        or name:find('garage',1,true)~=nil
        or name:find('hatch',1,true)~=nil
        or name:find('portcullis',1,true)~=nil
end

local function entityClaimed(entity,exceptHash)
    for otherHash,other in pairs(registered) do
        if otherHash~=exceptHash and other.entity==entity then return true end
    end
    return false
end

local function findLeafEntity(leaf,hash)
    local target=leaf.coords
    local best,bestDistance
    for _,entity in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(entity) and GetEntityModel(entity)==tonumber(leaf.model) and not entityClaimed(entity,hash) then
            local coords=GetEntityCoords(entity)
            local distance=#(coords-vector3(target.x,target.y,target.z))
            if distance <= 1.0 and (not bestDistance or distance<bestDistance) then
                best,bestDistance=entity,distance
            end
        end
    end
    return best or 0
end

local function setRegisteredState(hash,locked)
    if not IsDoorRegisteredWithSystem(hash) then return end
    DoorSystemSetDoorState(hash,locked and 1 or 0,false,false)
end

local function visualCenter(entity, model, fallback)
    if entity and entity~=0 and DoesEntityExist(entity) then
        local minimum,maximum=GetModelDimensions(model)
        return GetOffsetFromEntityInWorldCoords(entity,
            (minimum.x+maximum.x)*0.5,(minimum.y+maximum.y)*0.5,(minimum.z+maximum.z)*0.5)
    end
    local center=fallback.center or fallback.coords
    return vector3(center.x,center.y,center.z)
end

local function bindLeaf(door,index,leaf)
    local hash=doorHash(door.id,index)
    local entry=registered[hash]
    if not entry then
        entry={doorId=door.id,leafIndex=index,registered=false}
        registered[hash]=entry
    end
    local entity=entry.entity
    if not entity or not DoesEntityExist(entity) then
        local coords=leaf.coords
        entity=findLeafEntity(leaf,hash)
        if entity==0 then return end
        entry.entity=entity
    end
    if not entry.registered or not IsDoorRegisteredWithSystem(hash) then
        local coords=leaf.coords
        AddDoorToSystem(hash,tonumber(leaf.model),coords.x,coords.y,coords.z,false,false,false)
        DoorSystemSetDoorState(hash,4,false,false)
        DoorSystemSetDoorState(hash,door.locked and 1 or 0,false,false)
        DoorSystemSetAutomaticRate(hash,10.0,false,false)
        entry.registered=true
    end
    -- Always derive the icon from the current entity matrix. Old captures stored the
    -- mouse hit position, which made the icon drift or appear on the wrong side.
    leaf.visualCenter=visualCenter(entity,tonumber(leaf.model),leaf)
end

local function applyDoor(door)
    if not door or not door.enabled then return end
    local group = groups[tonumber(door.groupId)]
    if not group or not group.enabled then return end
    for index, leaf in ipairs(door.leaves or {}) do
        local hash = doorHash(door.id, index)
        registered[hash] = { doorId=door.id, leafIndex=index, registered=false }
        bindLeaf(door,index,leaf)
    end
end

local function applyPayload(payload)
    removeRegistered()
    groups, doors = indexPayload(payload)
    for _, door in pairs(doors) do applyDoor(door) end
end

RegisterNetEvent('ob_doorlock:client:sync', applyPayload)

RegisterNetEvent('ob_doorlock:client:state', function(rawId, locked, actor)
    local door = doors[tonumber(rawId)]
    if not door then return end
    door.locked = locked == true
    for index,leaf in ipairs(door.leaves or {}) do
        bindLeaf(door,index,leaf)
        local entry=registered[doorHash(door.id,index)]
        if entry and entry.registered then
            setRegisteredState(doorHash(door.id,index),door.locked)
        end
    end
    if door.locked then
        CreateThread(function()
            while door.locked do
                local closed=true
                for index in ipairs(door.leaves or {}) do
                    local hash=doorHash(door.id,index)
                    if registered[hash] and registered[hash].registered and not IsDoorClosed(hash) then
                        closed=false
                        break
                    end
                end
                if closed then return end
                Wait(0)
            end
        end)
    end
    if OBDoorlock.NativeAudio~=false then
        local px,py,pz,count=0.0,0.0,0.0,0
        for _,leaf in ipairs(door.leaves or {}) do
            local point=leaf.visualCenter or leaf.center or leaf.coords
            if point then px=px+point.x;py=py+point.y;pz=pz+point.z;count=count+1 end
        end
        if count>0 then
            local soundCoords=vector3(px/count,py/count,pz/count)
            if #(GetEntityCoords(PlayerPedId())-soundCoords)<20.0 then
                RequestScriptAudioBank('dlc_oxdoorlock/oxdoorlock',false)
                local soundId=GetSoundId()
                PlaySoundFromCoord(soundId,'door_bolt',soundCoords.x,soundCoords.y,soundCoords.z,'DLC_OXDOORLOCK_SET',false,0,false)
                ReleaseSoundId(soundId)
                ReleaseNamedScriptAudioBank('dlc_oxdoorlock/oxdoorlock')
            end
        end
    end
    if actor == GetPlayerServerId(PlayerId()) then
        notify(door.locked and 'Porta trancada.' or 'Porta destrancada.', 'success')
    end
end)

local function center(door)
    local leaves = door.leaves or {}
    if #leaves == 0 then return nil end
    local x, y, z = 0.0, 0.0, 0.0
    for index, leaf in ipairs(leaves) do
        local entry=registered[doorHash(door.id,index)]
        if entry and entry.entity and DoesEntityExist(entry.entity) then
            leaf.visualCenter=visualCenter(entry.entity,tonumber(leaf.model),leaf)
        end
        local coords=leaf.visualCenter or leaf.center or leaf.coords
        x=x+coords.x;y=y+coords.y;z=z+coords.z
    end
    return vector3(x/#leaves,y/#leaves,z/#leaves)
end

local function findClosest()
    local origin = GetEntityCoords(PlayerPedId())
    local best, bestDistance
    for _, door in pairs(doors) do
        local group = groups[tonumber(door.groupId)]
        if door.enabled and group and group.enabled then
            local pivot=center(door)
            if pivot and #(origin-pivot)<80.0 then
                for index,leaf in ipairs(door.leaves or {}) do bindLeaf(door,index,leaf) end
            end
            local coords = center(door)
            local distance = coords and #(origin-coords) or math.huge
            if not bestDistance or distance < bestDistance then best,bestDistance=door,distance end
        end
    end
    closestDoor = best and {door=best,distance=bestDistance,coords=center(best)} or nil
end

CreateThread(function()
    RequestStreamedTextureDict('mpsafecracking',true)
    while true do
        if LocalPlayer.state['or:loaded'] == true then findClosest() end
        Wait(math.max(100, math.floor(tonumber(OBDoorlock.ScanIntervalMs) or 250)))
    end
end)

CreateThread(function()
    while true do
        local current = closestDoor
        local group = current and groups[tonumber(current.door.groupId)]
        local liveCenter=current and center(current.door) or nil
        if current and liveCenter then current.coords=liveCenter end
        local distance = liveCenter and #(GetEntityCoords(PlayerPedId())-liveCenter) or math.huge
        local interactDistance = group and tonumber(group.interactionDistance) or 2.0
        if current and distance <= math.max(interactDistance, tonumber(OBDoorlock.DrawDistance) or 12.0) then
            if HasStreamedTextureDictLoaded('mpsafecracking') then
                local ratio=GetAspectRatio(true)
                for index,leaf in ipairs(current.door.leaves or {}) do
                    local entry=registered[doorHash(current.door.id,index)]
                    local icon=entry and entry.entity and DoesEntityExist(entry.entity)
                        and visualCenter(entry.entity,tonumber(leaf.model),leaf) or leaf.visualCenter
                    if icon then
                        SetDrawOrigin(icon.x,icon.y,icon.z)
                        DrawSprite('mpsafecracking',current.door.locked and 'lock_closed' or 'lock_open',0.0,0.0,0.018,0.018*ratio,0.0,255,255,255,100)
                        ClearDrawOrigin()
                    end
                end
            end
            if distance <= interactDistance and not editorOpen and not capturing then
                OR.Help.Show(('Pressione ~INPUT_CONTEXT~ para %s ~b~%s~s~'):format(
                    current.door.locked and 'destrancar' or 'trancar', current.door.label))
                helpVisible = true
                if IsControlJustReleased(0,38) then
                    OR.Help.Hide();helpVisible=false
                    TriggerServerEvent('ob_doorlock:server:toggle',current.door.id)
                end
            elseif helpVisible then OR.Help.Hide();helpVisible=false end
            Wait(0)
        else
            if helpVisible then OR.Help.Hide();helpVisible=false end
            Wait(200)
        end
    end
end)

local function rotationToDirection(rotation)
    local pitch,yaw=math.rad(rotation.x),math.rad(rotation.z)
    return vector3(-math.sin(yaw)*math.abs(math.cos(pitch)),math.cos(yaw)*math.abs(math.cos(pitch)),math.sin(pitch))
end

local function captureRay()
    local origin=GetFinalRenderedCamCoord();local direction=rotationToDirection(GetFinalRenderedCamRot(2))
    local destination=origin+direction*15.0
    local handle=StartShapeTestLosProbe(origin.x,origin.y,origin.z,destination.x,destination.y,destination.z,17,PlayerPedId(),4)
    while true do
        local status,hit,coords,_,_,entity=GetShapeTestResultIncludingMaterial(handle)
        if status~=1 then return (hit==1 or hit==true) and entity or 0,coords,hit==1 or hit==true end
        Wait(0)
    end
end

local function capturedLeaf(entity,hitCoords)
    if not entity or entity==0 or not DoesEntityExist(entity) or GetEntityType(entity)~=3 then return nil end
    local coords=GetEntityCoords(entity)
    local ok,name=pcall(GetEntityArchetypeName,entity)
    local model=GetEntityModel(entity)
    if not isDoorShape(model) or not hasDoorArchetypeName(ok and name or '') then return nil end
    local middle=visualCenter(entity,model,{coords=coords})
    local offset=GetOffsetFromEntityGivenWorldCoords(entity,middle.x,middle.y,middle.z)
    return {model=model,name=ok and name or '',coords={x=coords.x,y=coords.y,z=coords.z,heading=GetEntityHeading(entity)},center={x=middle.x,y=middle.y,z=middle.z},offset={x=offset.x,y=offset.y,z=offset.z}}
end

-- Preview is read-only. Like ox_doorlock, normalize only on the confirmation
-- edge; registering/removing a physical controller every frame damages the
-- selection workflow and can overlap an already managed door.
local function confirmCapturedLeaf(entity)
    local leaf=capturedLeaf(entity)
    if not leaf then return nil end
    if entityClaimed(entity) then
        notify('Esta folha ja possui uma tranca. Edite o cadastro existente.','error')
        return nil
    end
    local coords=leaf.coords
    local tempHash=joaat('ob_doorlock:capture')
    AddDoorToSystem(tempHash,leaf.model,coords.x,coords.y,coords.z,false,false,false)
    DoorSystemSetDoorState(tempHash,4,false,false)
    local result=capturedLeaf(entity)
    RemoveDoorFromSystem(tempHash)
    return result
end


local function setEditorFocus(enabled)
    SetNuiFocus(enabled,enabled)
    SetNuiFocusKeepInput(false)
end

local function closeEditor()
    editorOpen,capturing=false,false
    setEditorFocus(false)
    SendNUIMessage({action='close'})
end

local function openEditor()
    if editorOpen or capturing or IsNuiFocused() then return end
    CreateThread(function()
        local data,err=OR.Callback.awaitResource('ob_doorlock','editorData')
        if not data then return notify(err or 'Editor de portas indisponivel.','error') end
        editorOpen=true;setEditorFocus(true);SendNUIMessage({action='open',data=data})
    end)
end

RegisterCommand(OBDoorlock.EditorCommand or 'portaseditor',openEditor,false)
RegisterNetEvent('ob_doorlock:client:openEditor',openEditor)

RegisterNUICallback('close',function(_,cb)closeEditor();cb({ok=true})end)
RegisterNUICallback('refresh',function(_,cb)
    local data,err=OR.Callback.awaitResource('ob_doorlock','editorData')
    cb({ok=data~=nil,data=data,error=err})
end)
RegisterNUICallback('save',function(data,cb)
    local result,message=OR.Callback.awaitResource('ob_doorlock','editorSave',data)
    cb({ok=result~=nil,data=result,message=result and message or nil,error=result and nil or message})
end)
RegisterNUICallback('delete',function(data,cb)
    local result,message=OR.Callback.awaitResource('ob_doorlock','editorDelete',data)
    cb({ok=result==true,message=result and message or nil,error=result and nil or message})
end)
RegisterNUICallback('capture',function(data,cb)
    if not editorOpen or capturing then return cb({ok=false,error='Captura indisponivel.'}) end
    local slot=math.max(1,math.min(2,math.floor(tonumber(data and data.slot) or 1)))
    capturing=true;setEditorFocus(false);SendNUIMessage({action='captureMode',active=true});cb({ok=true})
    CreateThread(function()
        local selected,outlinedEntity
        while capturing and editorOpen do
            local entity,hitCoords,hit=captureRay()
            local leaf=capturedLeaf(entity,hitCoords)
            if entity~=outlinedEntity then
                if outlinedEntity and DoesEntityExist(outlinedEntity) then SetEntityDrawOutline(outlinedEntity,false) end
                outlinedEntity=leaf and entity or nil
                if outlinedEntity then SetEntityDrawOutline(outlinedEntity,true) end
            end
            if leaf then
                local minimum,maximum=GetModelDimensions(leaf.model)
                local points={
                    GetOffsetFromEntityInWorldCoords(entity,minimum.x,minimum.y,minimum.z),GetOffsetFromEntityInWorldCoords(entity,maximum.x,minimum.y,minimum.z),
                    GetOffsetFromEntityInWorldCoords(entity,maximum.x,maximum.y,minimum.z),GetOffsetFromEntityInWorldCoords(entity,minimum.x,maximum.y,minimum.z),
                    GetOffsetFromEntityInWorldCoords(entity,minimum.x,minimum.y,maximum.z),GetOffsetFromEntityInWorldCoords(entity,maximum.x,minimum.y,maximum.z),
                    GetOffsetFromEntityInWorldCoords(entity,maximum.x,maximum.y,maximum.z),GetOffsetFromEntityInWorldCoords(entity,minimum.x,maximum.y,maximum.z),
                }
                local edges={{1,2},{2,3},{3,4},{4,1},{5,6},{6,7},{7,8},{8,5},{1,5},{2,6},{3,7},{4,8}}
                for _,edge in ipairs(edges)do local a,b=points[edge[1]],points[edge[2]];DrawLine(a.x,a.y,a.z,b.x,b.y,b.z,38,194,255,240)end
                selected=leaf
            else selected=nil end
            if hit and hitCoords then DrawMarker(28,hitCoords.x,hitCoords.y,hitCoords.z,0.0,0.0,0.0,0.0,0.0,0.0,0.10,0.10,0.10,selected and 49 or 255,selected and 215 or 80,255,220,false,true,2,false,nil,nil,false)end
            OR.Help.Show('Feche a porta e mire onde o cadeado deve aparecer  |  [E] capturar  |  [ESC] cancelar')
            if IsControlJustReleased(0,38) and selected then
                local confirmed=confirmCapturedLeaf(entity)
                if confirmed then
                    capturing=false;setEditorFocus(true);SendNUIMessage({action='captureResult',slot=slot,leaf=confirmed})
                end
            elseif IsControlJustReleased(0,177) or IsControlJustReleased(0,200) then
                capturing=false;setEditorFocus(true);SendNUIMessage({action='captureMode',active=false})
            end
            Wait(0)
        end
        OR.Help.Hide()
        if outlinedEntity and DoesEntityExist(outlinedEntity) then SetEntityDrawOutline(outlinedEntity,false) end
    end)
end)

CreateThread(function()
    while LocalPlayer.state['or:loaded']~=true do Wait(500) end
    while true do
        local data=OR.Callback.awaitResource('ob_doorlock','bootstrap')
        if data then applyPayload(data);break end
        Wait(1500)
    end
end)

AddEventHandler('onClientResourceStop',function(resource)
    if resource~=GetCurrentResourceName()then return end
    if helpVisible then OR.Help.Hide() end
    closeEditor();removeRegistered()
end)
