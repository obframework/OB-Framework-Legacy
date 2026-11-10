local opened,busy,exam,npc,npcBlip,route = false,false,nil,nil,nil,nil
local version=0
local function notify(text,kind) TriggerEvent('ob_notification:client:notify',text,kind or 'info',7000) end
local function close()
    version=version+1
    if opened then SetNuiFocus(false,false) end
    opened=false;SendNUIMessage({action='close'})
end
local function clearRoute()
    if route and DoesBlipExist(route) then RemoveBlip(route) end
    route=nil
end
local function pointRoute()
    clearRoute()
    if not exam then return end
    local point=OBLicenca.Categories[exam.category].checkpoints[exam.index]
    if not point then return end
    route=AddBlipForCoord(point.coords.x,point.coords.y,point.coords.z)
    SetBlipSprite(route,1);SetBlipColour(route,3);SetBlipRoute(route,true);SetBlipRouteColour(route,3)
end
local function open(mode,id)
    if busy or opened or exam or IsNuiFocused() then return end
    busy=true;local token=version
    CreateThread(function()
        local ok,data,err=pcall(OR.Callback.await,mode=='inspect' and 'inspect' or 'status',id)
        busy=false
        if not ok or not data then return notify(ok and err or 'Centro de licencas indisponivel.','error') end
        if token~=version or IsNuiFocused() then return end
        opened=true;SetNuiFocus(true,true)
        SendNUIMessage({action='open',mode=mode,data=data})
    end)
end
RegisterCommand('licenca',function() open('school') end,false)
RegisterCommand('verlicenca',function(_,args)
    local id=tonumber(args[1]);if not id then return notify('Uso: /verlicenca ID do personagem proximo.','error') end
    open('inspect',id)
end,false)
RegisterCommand('cancelarprova',function()
    CreateThread(function()
        local ok,err=OR.Callback.await('cancel')
        if not ok then notify(err or 'Nao foi possivel cancelar.','error') end
        close()
    end)
end,false)
AddEventHandler('ob_licenca:client:instructor',function() open('school') end)
AddEventHandler('ob_licenca:client:inspect',function(target)
    target=tonumber(target)
    if target then open('inspect',Player(target).state['or:userId']) end
end)
RegisterNetEvent('ob_licenca:client:toggleDriverDocument',function(data)
    if source~=65535 or type(data)~='table' then return end
    if opened then close();return end
    if busy or exam or IsNuiFocused() then return notify('Feche a tela atual para consultar a CNH.','error') end
    opened=true;SetNuiFocus(true,true)
    SendNUIMessage({action='open',mode='driver',data=data})
end)

local function registerTargets()
    if GetResourceState('ob_target')~='started' then return end
    if npc and DoesEntityExist(npc) then
        exports.ob_target:AddEntityOption('ob_licenca:instructor',{entity=npc,label='Licenças',icon='CNH',
            event='ob_licenca:client:instructor',distance=2.5})
    end
    exports.ob_target:AddPlayerOption('ob_licenca:inspect',{label='Consultar documentos',icon='ID',
        event='ob_licenca:client:inspect',distance=OBLicenca.InspectDistance,canInteract=function()
            local org=LocalPlayer.state['ob:org']
            return type(org)=='table' and org.key==OBLicenca.PolicePermission and org.onDuty==true
                and LocalPlayer.state['or:downed']~=true and not exam
        end})
end
AddEventHandler('ob_target:client:ready',registerTargets)

local function startDrive(data)
    close()
    local c=OBLicenca.Categories[data.category]
    exam={category=data.category,index=1,errors=0,endsAt=GetGameTimer()+data.seconds*1000}
    local current=exam
    DoScreenFadeOut(300);Wait(350)
    local ped=PlayerPedId()
    SetEntityCoords(ped,c.spawn.x,c.spawn.y,c.spawn.z,false,false,false,false)
    RequestCollisionAtCoord(c.spawn.x,c.spawn.y,c.spawn.z)
    local deadline=GetGameTimer()+10000
    while exam==current and not NetworkDoesEntityExistWithNetworkId(data.netId) and GetGameTimer()<deadline do Wait(100) end
    if exam~=current then DoScreenFadeIn(300);return end
    local vehicle=NetworkGetEntityFromNetworkId(data.netId)
    if vehicle==0 or not DoesEntityExist(vehicle) then
        DoScreenFadeIn(300);OR.Callback.await('cancel');return notify('O veiculo da prova nao carregou.','error')
    end
    TaskWarpPedIntoVehicle(ped,vehicle,-1)
    local seatDeadline=GetGameTimer()+2000
    while GetPedInVehicleSeat(vehicle,-1)~=ped and GetGameTimer()<seatDeadline do Wait(50) end
    SetVehicleFuelLevel(vehicle,100.0)
    DoScreenFadeIn(300)
    pointRoute()
    notify('Siga os pontos azuis. Respeite o limite exibido. /cancelarprova para desistir.','info')
    -- Integra a chave/ignicao real, inclusive quando a chave e fisica.
    local ok=OR.Callback.awaitResource('ob_vehiclekeys','ignition',data.netId,true)
    if not ok then notify('Use Z para ligar o veiculo com a chave da autoescola.','info') end
end

RegisterNUICallback('close',function(_,cb)
    close();cb({ok=true})
    CreateThread(function() OR.Callback.await('cancel') end)
end)
for _,action in ipairs({'theory','answers','practical','status','document'}) do
    RegisterNUICallback(action,function(data,cb)
        if not opened or busy then return cb({ok=false,error='Aguarde a operacao atual.'}) end
        busy=true
        local token=version
        CreateThread(function()
            local payload=action=='answers' and data.answers or action=='document' and data.kind or data.category
            local ok,result,err=pcall(OR.Callback.await,action,payload)
            busy=false
            if token~=version or not opened then
                cb({ok=false,error='Menu fechado.'})
                if action=='practical' and ok and result then OR.Callback.await('cancel') end
                return
            end
            if ok and result then
                cb({ok=true,data=result})
                if action=='practical' then startDrive(result) end
            else cb({ok=false,error=ok and err or 'Falha ao contatar o servidor.'}) end
        end)
    end)
end
RegisterNetEvent('ob_licenca:client:progress',function(index,errors)
    if source~=65535 or not exam then return end
    exam.index=index;exam.errors=errors;pointRoute()
end)
RegisterNetEvent('ob_licenca:client:finish',function()
    if source~=65535 then return end
    exam=nil;clearRoute();SendNUIMessage({action='hud',visible=false});DoScreenFadeIn(300)
end)
RegisterNetEvent('ob_licenca:client:expired',function()
    if source~=65535 then return end
    close();notify('O tempo da prova teorica acabou.','error')
end)

CreateThread(function()
    local c=OBLicenca.Npc.coords
    npcBlip=AddBlipForCoord(c.x,c.y,c.z)
    SetBlipSprite(npcBlip,498);SetBlipColour(npcBlip,3);SetBlipScale(npcBlip,0.75);SetBlipAsShortRange(npcBlip,true)
    BeginTextCommandSetBlipName('STRING');AddTextComponentSubstringPlayerName('Centro de Licencas');EndTextCommandSetBlipName(npcBlip)
    while true do
        local near=#(GetEntityCoords(PlayerPedId())-vector3(c.x,c.y,c.z))<100
        if near and not npc then
            local model=joaat(OBLicenca.Npc.model);RequestModel(model)
            local deadline=GetGameTimer()+5000
            while not HasModelLoaded(model) and GetGameTimer()<deadline do Wait(50) end
            if HasModelLoaded(model) then
                npc=CreatePed(4,model,c.x,c.y,c.z-1.0,c.w,false,false)
                if npc~=0 then
                    SetEntityInvincible(npc,true);FreezeEntityPosition(npc,true);SetBlockingOfNonTemporaryEvents(npc,true)
                    TaskStartScenarioInPlace(npc,'WORLD_HUMAN_CLIPBOARD',0,true);registerTargets()
                else npc=nil end
                SetModelAsNoLongerNeeded(model)
            end
        elseif not near and npc then
            if GetResourceState('ob_target')=='started' then exports.ob_target:RemoveEntityOption('ob_licenca:instructor') end
            DeleteEntity(npc);npc=nil
        end
        Wait(1500)
    end
end)
CreateThread(function()
    Wait(500);registerTargets()
    while true do
        if exam then
            local c=OBLicenca.Categories[exam.category];local p=c.checkpoints[exam.index]
            local coords=GetEntityCoords(PlayerPedId())
            if p and #(coords-p.coords)<(c.airborne and 800 or 150) then
                local size=c.airborne and 14.0 or (c.serverType=='boat' and 12.0 or 5.0)
                DrawMarker(c.airborne and 6 or 1,p.coords.x,p.coords.y,p.coords.z,0.0,0.0,0.0,0.0,0.0,0.0,
                    size,size,c.airborne and size or 1.2,40,190,255,180,false,c.airborne==true,2,false,nil,nil,false)
            end
            DisableControlAction(0,75,true)
            Wait(0)
        else Wait(500) end
    end
end)
CreateThread(function()
    while true do
        if exam then
            local c=OBLicenca.Categories[exam.category];local p=c.checkpoints[exam.index]
            SendNUIMessage({action='hud',visible=true,index=exam.index,total=#c.checkpoints,errors=exam.errors,
                maxErrors=c.maxErrors,limit=p and p.speedLimit,seconds=math.max(0,math.ceil((exam.endsAt-GetGameTimer())/1000))})
        elseif GetResourceState('ob_target')~='started' then
            local c=OBLicenca.Npc.coords
            if #(GetEntityCoords(PlayerPedId())-vector3(c.x,c.y,c.z))<2.5 and not opened then
                OR.Help.Show('Use /licenca para falar com o instrutor.')
            end
        end
        Wait(500)
    end
end)
AddEventHandler('onClientResourceStop',function(name)
    if name~=GetCurrentResourceName() then return end
    close();clearRoute();DoScreenFadeIn(0)
    if npc then DeleteEntity(npc) end
    if npcBlip then RemoveBlip(npcBlip) end
    if GetResourceState('ob_target')=='started' then
        exports.ob_target:RemoveEntityOption('ob_licenca:instructor');exports.ob_target:RemovePlayerOption('ob_licenca:inspect')
    end
end)
