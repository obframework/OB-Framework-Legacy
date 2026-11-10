local resource, cfg = GetCurrentResourceName(), HeistConfig
local states, zones, doors, busy = {}, {}, {}, false
local eventsRegistered, serverUnix, serverTimer = false, 0, 0

local function notify(message, kind) OR.Notify(message, kind or 'info') end
local function stateFor(id) return states[id] or {phase=0,looted={}} end
local function coords3(value) return vector3(value.x, value.y, value.z) end
local function approximateUnix()
    return serverUnix + math.floor((GetGameTimer() - serverTimer) / 1000)
end
local function runGame(name, options)
    if not name then return true end
    if name == 'DataCrack' then return exports.ob_minigame:DataCrack(options) end
    if name == 'Circuit' then return exports.ob_minigame:Circuit(options) end
    if name == 'Keypress' then return exports.ob_minigame:Keypress(options) end
    if name == 'PrecisionBar' then return exports.ob_minigame:PrecisionBar(options) end
    if name == 'WireSequence' then return exports.ob_minigame:WireSequence(options) end
    return false
end
local function perform(locationId, kind, entryId)
    if busy or LocalPlayer.state['or:downed'] or IsPedInAnyVehicle(PlayerPedId(), false) then return end
    busy = true
    local ok, data = OR.Callback.await('begin', locationId, kind, entryId)
    if not ok then busy=false; return notify(data or 'Ação indisponível.', 'error') end
    local completed = OR.Progress.Run({label=data.label,duration=data.duration,canCancel=true,
        animation={dict=kind=='loot' and 'anim@heists@ornate_bank@grab_cash' or 'anim@heists@prison_heiststation@cop_reactions',
            clip=kind=='loot' and 'grab' or 'cop_b_idle',flag=49}})
    if completed then completed = runGame(data.game, data.options) == true end
    local finished, message = OR.Callback.await('finish', data.token, completed == true)
    busy = false
    notify(message or (finished and 'Etapa concluída.' or 'A etapa falhou.'), finished and 'success' or 'error')
end
local function registerZone(id, coords, label, canInteract, eventName)
    exports.ob_target:RegisterSphereZone(id, {coords=coords3(coords),radius=0.85,option={
        label=label,icon='B',distance=cfg.interactDistance,event=eventName,canInteract=canInteract,
    }})
    zones[#zones+1] = id
end
local function setupTargets()
    for _, id in ipairs(zones) do exports.ob_target:UnregisterZone(id) end
    zones = {}
    for locationId, location in pairs(cfg.locations) do
        for actionId, action in pairs(location.actions or {}) do
            local eventName = ('%s:client:action:%s:%s'):format(resource,locationId,actionId)
            if not eventsRegistered then RegisterNetEvent(eventName, function() perform(locationId,'stage',actionId) end) end
            registerZone(eventName,action.coords,action.label,function()
                local state=stateFor(locationId)
                return not busy and state.phase==action.requires and (state.failedUntil or 0)<=approximateUnix() and (state.closingAt or 0)==0
            end,eventName)
        end
        for index, loot in ipairs(location.loot or {}) do
            local eventName = ('%s:client:loot:%s:%s'):format(resource,locationId,index)
            if not eventsRegistered then RegisterNetEvent(eventName, function() perform(locationId,'loot',index) end) end
            registerZone(eventName,loot.coords,loot.label,function()
                local state=stateFor(locationId)
                return not busy and state.phase>=loot.requires and not (state.looted or {})[index] and (state.closingAt or 0)==0
            end,eventName)
        end
    end
    eventsRegistered = true
end
local function registerDoors()
    for locationId, location in pairs(cfg.locations) do
        doors[locationId] = {}
        for index, door in ipairs(location.doors or {}) do
            local entry = {config=door,hash=joaat(('%s:%s:%s'):format(resource,locationId,index))}
            if door.manual ~= true then
                local model=joaat(door.model)
                if not IsDoorRegisteredWithSystem(entry.hash) then AddDoorToSystem(entry.hash,model,door.coords.x,door.coords.y,door.coords.z,false,false,false) end
            end
            doors[locationId][index]=entry
        end
    end
end
local function applyDoors()
    for locationId, entries in pairs(doors) do
        local phase=stateFor(locationId).phase or 0
        for _, entry in ipairs(entries) do
            local door, open = entry.config, phase >= entry.config.openPhase
            if door.manual then
                local entity=GetClosestObjectOfType(door.coords.x,door.coords.y,door.coords.z,2.0,joaat(door.model),false,false,false)
                if entity~=0 then FreezeEntityPosition(entity,true); SetEntityHeading(entity,open and door.openHeading or door.closedHeading) end
            elseif IsDoorRegisteredWithSystem(entry.hash) then
                DoorSystemSetDoorState(entry.hash,open and 0 or 1,false,true)
                DoorSystemSetOpenRatio(entry.hash,open and (door.ratio or 1.0) or 0.0,false,true)
            end
        end
    end
end
local function requestSnapshot()
    local snapshot, now = OR.Callback.await('snapshot')
    if type(snapshot)=='table' then states=snapshot; serverUnix=tonumber(now) or serverUnix; serverTimer=GetGameTimer(); applyDoors() end
end

RegisterNetEvent(resource..':client:sync',function(snapshot, now)
    if source~=65535 or type(snapshot)~='table' then return end
    states=snapshot
    serverUnix=tonumber(now) or serverUnix
    serverTimer=GetGameTimer()
    applyDoors()
end)

AddEventHandler('ob_target:client:ready',function()
    setupTargets()
end)

AddEventHandler('onClientResourceStart',function(name)
    if name~=resource then return end
    Wait(800)
    registerDoors()
    setupTargets()
    requestSnapshot()
end)

CreateThread(function()
    while true do Wait(1500); applyDoors() end
end)

CreateThread(function()
    while true do Wait(15000); requestSnapshot() end
end)

AddEventHandler('onResourceStop',function(name)
    if name~=resource then return end
    exports.ob_minigame:Cancel()
    for _,id in ipairs(zones) do if GetResourceState('ob_target')=='started' then exports.ob_target:UnregisterZone(id) end end
    for _,entries in pairs(doors) do for _,entry in ipairs(entries) do
        if entry.config.manual~=true and IsDoorRegisteredWithSystem(entry.hash) then DoorSystemSetDoorState(entry.hash,0,false,true); RemoveDoorFromSystem(entry.hash) end
    end end
end)
