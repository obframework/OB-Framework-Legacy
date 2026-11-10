local resource = GetCurrentResourceName()
local locations, states, objects, doors, zones = Config.Locations, {}, {}, {}, {}
local busy, cancelled, token, lastShot = false, false, nil, 0
local npcTasks, nextWalk, frightened, alertBlips = {}, {}, {}, {}
local function pos(p) return vector3(p.x,p.y,p.z) end
local function notify(text, kind) OR.Notify(text, kind or 'info') end
local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return end
    RequestModel(hash)
    local deadline = GetGameTimer()+4000
    while not HasModelLoaded(hash) and GetGameTimer()<deadline do Wait(0) end
    if HasModelLoaded(hash) then return hash end
end
local function walk(ped,p)
    TaskFollowNavMeshToCoord(ped,p.x,p.y,p.z,0.8,25000,0.4,false,p.w or 0.0)
end
local function stateFor(id) return states[id] or {phase='idle',stage=0,taken={}} end
local function actionPoint(id)
    local location, state = locations[id], stateFor(id)
    if not location then return end
    local step = location.steps[(state.stage or 0)+1]
    if step then return step.coords or location.coords, step.label end
end
local function run(id, loot)
    if busy or IsNuiFocused() or LocalPlayer.state['or:downed'] or IsPedInAnyVehicle(PlayerPedId(),false) then return end
    busy, cancelled = true, false
    local ok, errorMessage = pcall(function()
        local data, message = OR.Callback.await('begin', id, loot)
        if not data then notify(message or 'Acao indisponivel.','error'); return end
        token = data.token
        local started = GetGameTimer()
        local success = true
        if data.game then
            if GetResourceState('ob_minigame') ~= 'started' then
                notify('Sistema de minigames indisponivel.','error'); success=false
            else
                local opts = data.options or {}
                opts.title = data.label
                if data.game == 'DataCrack' then success = exports.ob_minigame:DataCrack(opts)
                elseif data.game == 'Circuit' then success = exports.ob_minigame:Circuit(opts)
                elseif data.game == 'Keypress' then success = exports.ob_minigame:Keypress(opts)
                else success=false end
            end
        end
        if success and not cancelled then
            -- O minigame conta no tempo, mas nunca permite terminar antes do servidor.
            local remaining = math.max(500,data.seconds*1000-(GetGameTimer()-started)+1000)
            local animation=data.animation
            if not animation then
                animation=data.game and {dict='anim@heists@ornate_bank@hack',clip='hack_loop',flag=49}
                    or {dict='anim@heists@ornate_bank@grab_cash',clip='grab',flag=49}
            end
            success = OR.Progress.Run({ label=data.label, duration=remaining, canCancel=true,
                animation=animation })
        end
        local completed, message = OR.Callback.await('finish',token,success == true and not cancelled)
        token = nil
        if message then notify(message,completed and 'success' or 'error') end
    end)
    if not ok then
        if token then pcall(function() OR.Callback.await('finish',token,false) end) end
        print(('[%s] acao: %s'):format(resource,tostring(errorMessage)))
        notify('Acao interrompida.','error')
    end
    token, busy = nil, false
end

local function removeZones()
    if GetResourceState('ob_target') == 'started' then
        for _, key in ipairs(zones) do exports.ob_target:UnregisterZone(key) end
    end
    zones = {}
end
local function rebuildTargets()
    removeZones()
    if GetResourceState('ob_target') ~= 'started' then return end
    for id, location in pairs(locations) do
        local p, label = actionPoint(id)
        local function add(suffix,coords,text,loot)
            local key = resource..':'..id..':'..suffix
            exports.ob_target:RegisterSphereZone(key,{coords=coords,radius=1.2,option={
                label=text,distance=Config.InteractDistance or 2.8,action=function() run(id,loot) end}})
            zones[#zones+1] = key
        end
        if p then add('step',p,label) end
        local state = stateFor(id)
        if state.phase == 'active' and state.stage >= #location.steps then
            for index, point in ipairs(location.loot) do
                if not state.taken[tostring(index)] then add('loot'..index,point,'Recolher dinheiro',index) end
            end
        end
    end
end
RegisterNetEvent(resource..':sync',function(newLocations,newStates)
    if source ~= 65535 then return end
    locations,states = newLocations,newStates
    rebuildTargets()
end)
RegisterNetEvent(resource..':cancel',function()
    if source ~= 65535 then return end
    cancelled = true
    if busy and GetResourceState('ob_minigame') == 'started' then exports.ob_minigame:Cancel() end
end)
RegisterNetEvent(resource..':alert',function(label,coords,seconds)
    if source ~= 65535 then return end
    notify('Alarme de roubo: '..label,'error')
    local blip = AddBlipForCoord(coords.x,coords.y,coords.z)
    SetBlipSprite(blip,161); SetBlipColour(blip,1); SetBlipScale(blip,1.2)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString('Roubo: '..label); EndTextCommandSetBlipName(blip)
    alertBlips[blip]=true
    SetTimeout((seconds or 180)*1000,function() if DoesBlipExist(blip) then RemoveBlip(blip) end; alertBlips[blip]=nil end)
end)
RegisterNetEvent(resource..':blast',function(point)
    if source ~= 65535 or #(GetEntityCoords(PlayerPedId())-pos(point)) > 120 then return end
    -- Efeito local sem dano duplicado entre clientes nem destruicao do mapa.
    AddExplosion(point.x,point.y,point.z,2,0.0,true,false,0.5,true)
end)

CreateThread(function()
    Wait(1200)
    local snapshot = OR.Callback.await('snapshot')
    if snapshot then locations,states=snapshot.locations,snapshot.states; rebuildTargets() end
end)
AddEventHandler('onClientResourceStart',function(name)
    if name == 'ob_target' then rebuildTargets() end
end)

-- Interacao por E continua disponivel caso o target seja removido.
CreateThread(function()
    while true do
        local delay, ped = 750, PlayerPedId()
        local coords = GetEntityCoords(ped)
        if not busy and not IsNuiFocused() then
            local nearest, nearestLoot, nearestLabel, closest = nil,nil,nil,Config.InteractDistance or 2.8
            for id, location in pairs(locations) do
                local distance = #(coords-pos(location.coords))
                if distance < (location.radius or 35)+10 then
                    delay = 0
                    local state = stateFor(id)
                    if Config.Bank and state.phase == 'idle' and IsPedShooting(ped)
                        and distance < (location.radius or 20) and GetGameTimer()-lastShot>10000 then
                        lastShot=GetGameTimer(); CreateThread(function() run(id) end)
                    end
                    local point,label = actionPoint(id)
                    if point and #(coords-pos(point))<closest then nearest,nearestLoot,nearestLabel,closest=id,nil,label,#(coords-pos(point)) end
                    if state.phase=='active' and state.stage>=#location.steps then
                        for index,p in ipairs(location.loot) do
                            local dist = #(coords-pos(p))
                            if not state.taken[tostring(index)] and dist<closest then nearest,nearestLoot,nearestLabel,closest=id,index,'Recolher dinheiro',dist end
                        end
                    end
                end
            end
            if nearest then
                OR.Help.Show('[E] '..nearestLabel)
                if IsControlJustReleased(0,38) then
                    local id,loot=nearest,nearestLoot
                    CreateThread(function() run(id,loot) end)
                end
            end
        end
        Wait(delay)
    end
end)

local function object(key,model,coords,heading)
    if objects[key] and DoesEntityExist(objects[key]) then
        local entity=objects[key]
        if #(GetEntityCoords(entity)-pos(coords))>0.01 then SetEntityCoordsNoOffset(entity,coords.x,coords.y,coords.z,false,false,false) end
        SetEntityHeading(entity,heading or coords.w or 0)
        return
    end
    local hash = loadModel(model)
    if not hash then return end
    local entity=CreateObjectNoOffset(hash,coords.x,coords.y,coords.z,false,false,false)
    SetEntityHeading(entity,heading or coords.w or 0)
    FreezeEntityPosition(entity,true)
    SetEntityCollision(entity,false,false)
    objects[key]=entity
    SetModelAsNoLongerNeeded(hash)
end
local function deleteObject(key)
    if objects[key] and DoesEntityExist(objects[key]) then DeleteEntity(objects[key]) end
    objects[key]=nil
end
CreateThread(function()
    while true do
        Wait(750)
        local playerCoords, wanted = GetEntityCoords(PlayerPedId()), {}
        for id, location in pairs(locations) do
            local state=stateFor(id)
            if #(playerCoords-pos(location.coords))<85 then
                if location.prop then
                    local key=id..':register'; wanted[key]=true
                    object(key,location.prop,location.coords,location.coords.w)
                end
                if state.phase=='active' and state.stage>=#location.steps then
                    for index,point in ipairs(location.loot) do
                        local key=id..':loot:'..index
                        if not state.taken[tostring(index)] then
                            wanted[key]=true
                            object(key,point.model or 'hei_prop_hei_cash_trolly_01',point,point.w)
                        end
                    end
                end
                for index,door in ipairs(location.doors or {}) do
                    local hash=joaat(resource..':'..id..':door:'..index)
                    local open=state.phase=='active' and state.stage >= door.after
                    if door.heading then
                        local entity=GetClosestObjectOfType(door.coords.x,door.coords.y,door.coords.z,2.0,joaat(door.model),false,false,false)
                        if entity~=0 then
                            FreezeEntityPosition(entity,true)
                            SetEntityHeading(entity,open and door.openHeading or door.heading)
                            doors[hash]={entity=entity,config=door}
                        end
                    else
                        if not IsDoorRegisteredWithSystem(hash) then
                            AddDoorToSystem(hash,joaat(door.model),door.coords.x,door.coords.y,door.coords.z,false,false,false)
                        end
                        DoorSystemSetDoorState(hash,open and 0 or 1,false,true)
                        DoorSystemSetOpenRatio(hash,open and (door.ratio or 1.0) or 0.0,false,true)
                        doors[hash]={config=door}
                    end
                end
            end
        end
        for key in pairs(objects) do if not wanted[key] then deleteObject(key) end end
    end
end)

-- Somente o controlador de cada NPC em rede aplica tarefas. Clientes tardios
-- recebem os mesmos netIds e a mesma fase, sem gerar atendentes duplicados.
CreateThread(function()
    while true do
        Wait(1800)
        for id,location in pairs(locations) do
            local state=stateFor(id)
            if #(GetEntityCoords(PlayerPedId())-pos(location.coords))<100 then
                for _,spec in ipairs(state.peds or {}) do
                    if NetworkDoesEntityExistWithNetworkId(spec.netId) then
                        local ped=NetToPed(spec.netId)
                        if ped~=0 and not IsEntityDead(ped) and NetworkHasControlOfEntity(ped) then
                            local taskKey=('%s:%s:%s'):format(state.phase,state.stage,spec.teller and 'teller' or 'customer')
                            SetBlockingOfNonTemporaryEvents(ped,true)
                            if npcTasks[ped]~=taskKey then
                                npcTasks[ped]=taskKey
                                ClearPedTasks(ped)
                                if state.phase=='active' then
                                    if spec.teller and state.stage==0 then
                                        TaskHandsUp(ped,4000,PlayerPedId(),-1,true)
                                        local bankId, tellerPed=id,ped
                                        SetTimeout(4000,function()
                                            local current=stateFor(bankId)
                                            if current.phase=='active' and current.stage==0 and DoesEntityExist(tellerPed)
                                                and not IsEntityDead(tellerPed) and NetworkHasControlOfEntity(tellerPed) and location.tellerDoor then
                                                local p=location.tellerDoor
                                                walk(tellerPed,p)
                                            end
                                        end)
                                    elseif spec.teller and location.tellerDoor then
                                        local p=location.tellerDoor
                                        walk(ped,p)
                                    else TaskCower(ped,-1) end
                                elseif spec.walk then
                                    local p=spec.walk
                                    walk(ped,p)
                                else TaskStartScenarioInPlace(ped,'WORLD_HUMAN_CLIPBOARD',0,true) end
                            elseif state.phase=='idle' and spec.walk and GetScriptTaskStatus(ped,joaat('SCRIPT_TASK_FOLLOW_NAV_MESH_TO_COORD'))==7 then
                                if not nextWalk[ped] then nextWalk[ped]=GetGameTimer()+math.random(8000,18000) end
                                if GetGameTimer()>=nextWalk[ped] then
                                    local target=#(GetEntityCoords(ped)-pos(spec.walk))<2 and spec.coords or spec.walk
                                    walk(ped,target)
                                    nextWalk[ped]=nil
                                end
                            end
                        end
                    end
                end
                if state.phase=='active' and Config.Bank then
                    for _,ped in ipairs(GetGamePool('CPed')) do
                        if not IsPedAPlayer(ped) and not IsEntityAMissionEntity(ped) and not IsPedInAnyVehicle(ped,false)
                            and not IsEntityDead(ped) and #(GetEntityCoords(ped)-pos(location.coords))<(location.panicRadius or 12)
                            and math.abs(GetEntityCoords(ped).z-location.coords.z)<3 and NetworkHasControlOfEntity(ped) then
                            if not frightened[ped] then frightened[ped]=id; TaskCower(ped,-1) end
                        end
                    end
                end
            end
        end
        for ped,id in pairs(frightened) do
            if not DoesEntityExist(ped) then frightened[ped]=nil
            elseif stateFor(id).phase~='active' then ClearPedTasks(ped); TaskWanderStandard(ped,10.0,10); frightened[ped]=nil end
        end
        for ped in pairs(npcTasks) do if not DoesEntityExist(ped) then npcTasks[ped],nextWalk[ped]=nil,nil end end
    end
end)

AddEventHandler('onClientResourceStop',function(name)
    if name~=resource then return end
    removeZones()
    if busy and GetResourceState('ob_minigame')=='started' then exports.ob_minigame:Cancel() end
    for key in pairs(objects) do deleteObject(key) end
    for hash,data in pairs(doors) do
        if data.entity and DoesEntityExist(data.entity) then
            SetEntityHeading(data.entity,data.config.heading); FreezeEntityPosition(data.entity,false)
        elseif IsDoorRegisteredWithSystem(hash) then DoorSystemSetDoorState(hash,0,false,true); RemoveDoorFromSystem(hash) end
    end
    for ped in pairs(frightened) do if DoesEntityExist(ped) then ClearPedTasks(ped) end end
    for blip in pairs(alertBlips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
end)
