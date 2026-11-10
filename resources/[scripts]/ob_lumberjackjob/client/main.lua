local state={active=false,tree=nil,loaded=0,maxWood=0,vehicle=0,vehicleNetId=nil,routeBlip=0,panelOpen=false,sawmill=nil,returning=false}
local group={members={},isLeader=true,maxMembers=2}
local npcPed,npcBlip,sawmillZones=nil,nil,{}
local treeCache={}

local function notify(message,typ)OR.Notify(message,typ or'info')end
local function removeRoute()if state.routeBlip~=0 and DoesBlipExist(state.routeBlip)then RemoveBlip(state.routeBlip)end;state.routeBlip=0 end
local function setRoute(coords,name)
 removeRoute();state.routeBlip=AddBlipForCoord(coords.x,coords.y,coords.z);SetBlipSprite(state.routeBlip,280);SetBlipScale(state.routeBlip,0.8);SetBlipColour(state.routeBlip,2);SetBlipRoute(state.routeBlip,true);SetBlipRouteColour(state.routeBlip,2)
 BeginTextCommandSetBlipName('STRING');AddTextComponentString(name);EndTextCommandSetBlipName(state.routeBlip)
end
local function treePoint(index)
 local raw=index and Lumberjack.trees[index];if not raw then return nil end
 local cached=treeCache[index];if cached and cached.expires>GetGameTimer()then return cached.coords end
 local cfg=Lumberjack.worldProps or{};local radius=cfg.searchRadius or 3.0;local minHeight=cfg.minTreeHeight or 3.0;local closest,distance=nil,radius+0.001
 for _,object in ipairs(GetGamePool('CObject'))do
  if DoesEntityExist(object)then local coords=GetEntityCoords(object);local current=#(coords-raw.xyz)
   if current<distance then local minBounds,maxBounds=GetModelDimensions(GetEntityModel(object));if minBounds and maxBounds and(maxBounds.z-minBounds.z)>=minHeight then closest=coords;distance=current end end
  end
 end
 local coords=closest or raw.xyz;treeCache[index]={coords=coords,expires=GetGameTimer()+(closest and(cfg.cacheMs or 15000)or 2000)};return coords
end
local function routeTree()local coords=treePoint(state.tree);if coords then setRoute(coords,'Arvore para cortar')end end
local function getSawmill()return Lumberjack.sawmills and Lumberjack.sawmills[state.sawmill]end
local function routeSawmill()local sawmill=getSawmill();if sawmill then setRoute(sawmill.vehicleCoords.xyz,sawmill.label)end end
local function routeReturn()setRoute(Lumberjack.truck.spawn.xyz,'Devolver caminhão')end
local function updateRoute()if not state.active then removeRoute()elseif state.returning then routeReturn()elseif state.loaded>=(Lumberjack.sawmill.minLoadToDeliver or state.maxWood)then routeSawmill()else routeTree()end end
local function progress(label,duration,animation)return OR.Progress.Run({duration=duration,label=label,canCancel=true,disable={move=true,car=true,combat=true},anim=animation})end
local function text2d(text)SetTextFont(4);SetTextScale(0.38,0.38);SetTextOutline();SetTextEntry('STRING');AddTextComponentString(text);DrawText(0.40,0.93)end
local function drawCheckpoint(coords,radius,color)DrawMarker(1,coords.x,coords.y,coords.z-0.98,0.0,0.0,0.0,0.0,0.0,0.0,radius,radius,0.70,color.r,color.g,color.b,color.a,false,false,2,false,nil,nil,false)end
local function clearTruck()exports.ob_target:RemoveEntityOption('orbis_lumberjack_load');state.vehicle=0;state.vehicleNetId=nil end

local function loadWood()
 if not progress('Carregando madeira no caminhão...',2800,{dict='anim@heists@narcotics@trash',clip='throw_b',flag=1})then return end
 local ok,amount,loaded,maximum=OR.Callback.await('orbis-lumberjack:server:loadTruck');if not ok then return notify(amount or'Nao foi possivel carregar.','error')end
 state.loaded,state.maxWood=loaded,maximum;notify(('%s madeiras carregadas. Carga: %s/%s.'):format(amount,loaded,maximum),'success');updateRoute();TriggerEvent('orbis-lumberjack:client:refreshPanel')
end
local function registerTruckTarget()
 if state.vehicle==0 or not DoesEntityExist(state.vehicle)or GetResourceState('ob_target')~='started'then return end
 exports.ob_target:RemoveEntityOption('orbis_lumberjack_load')
 exports.ob_target:RegisterEntity('orbis_lumberjack_load',state.vehicle,{icon='fa-solid fa-tree',label='Carregar madeira',distance=3.0,canInteract=function()return state.active and not state.returning and state.loaded<state.maxWood end,action=loadWood})
end
local function resolveTruck(netId)
 netId=tonumber(netId);if not netId or netId<=0 then clearTruck();return end
 if state.vehicleNetId==netId and state.vehicle~=0 and DoesEntityExist(state.vehicle)then registerTruckTarget();return end
 clearTruck();state.vehicleNetId=netId
 CreateThread(function()
  local vehicle=OR.Entity.AwaitNetwork(netId,10000);if state.vehicleNetId~=netId then return end
  if not vehicle or vehicle==0 then return notify('O caminhao do grupo nao sincronizou.','error')end
  state.vehicle=vehicle;SetEntityAsMissionEntity(vehicle,true,false);registerTruckTarget()
 end)
end
local function applyJob(data)
 data=data or{};state.active=data.active==true;state.tree=data.tree;state.loaded=tonumber(data.loaded)or 0;state.maxWood=tonumber(data.maxWood)or Lumberjack.truck.maxWood;state.sawmill=data.sawmill;state.returning=data.returning==true
 if state.active then resolveTruck(data.vehicleNetId);updateRoute()else removeRoute();clearTruck()end
 if state.panelOpen then TriggerEvent('orbis-lumberjack:client:refreshPanel')end
end
local function createTruck()
 local spawn=Lumberjack.truck.spawn
 for _,vehicle in ipairs(GetGamePool('CVehicle'))do if #(GetEntityCoords(vehicle)-spawn.xyz)<(Lumberjack.truck.spawnClearRadius or 4.0)then notify('A vaga do caminhao esta ocupada.','error');return false end end
 local ok,result=OR.Callback.await('orbis-lumberjack:server:spawnVehicle');if not ok or type(result)~='table'then notify(result or'Nao foi possivel criar o caminhao.','error');return false end
 state.vehicleNetId=result.netId;local vehicle=OR.Entity.AwaitNetwork(result.netId,10000);if not vehicle then notify('O caminhao criado nao sincronizou.','error');return false end
 state.vehicle=vehicle;SetEntityAsMissionEntity(vehicle,true,false);SetVehicleOnGroundProperly(vehicle);SetVehicleNumberPlateText(vehicle,result.plate);SetVehicleFuelLevel(vehicle,100.0);TriggerEvent('vehiclekeys:client:SetOwner',GetVehicleNumberPlateText(vehicle));registerTruckTarget();return true
end
local function startJob()
 local ok,data=OR.Callback.await('orbis-lumberjack:server:startJob');if not ok then return notify(data or'Nao foi possivel iniciar o servico.','error')end
 applyJob(data);if createTruck()then notify('Trabalho da dupla iniciado. Corte madeira e carregue o caminhão.','success')end
end
local function stopJob()
 local ok,message=OR.Callback.await('orbis-lumberjack:server:stopJob');if not ok then return notify(message or'Nao foi possivel finalizar.','error')end
 notify('Servico finalizado.','inform')
end
local function getNearbyPlayers()
 local nearby,myCoords={},GetEntityCoords(PlayerPedId())
 for _,player in ipairs(GetActivePlayers())do if player~=PlayerId()then local ped=GetPlayerPed(player);if ped~=0 and #(myCoords-GetEntityCoords(ped))<=(Lumberjack.group.inviteDistance or 18.0)then nearby[#nearby+1]={id=GetPlayerServerId(player),name=GetPlayerName(player)or('ID %s'):format(GetPlayerServerId(player))}end end end
 return nearby
end
local function refreshPanel(open)
 local data=OR.Callback.await('orbis-lumberjack:server:getPanelData');if not data then return end
 data.tutorial=Lumberjack.tutorial;data.nearby=getNearbyPlayers();group=data.group or group
 if open then state.panelOpen=true;SetNuiFocus(true,true);SendNUIMessage({action='open',payload=data})elseif state.panelOpen then SendNUIMessage({action='update',payload=data})end
end
RegisterNetEvent('orbis-lumberjack:client:refreshPanel',function()refreshPanel(false)end)
RegisterNetEvent('orbis-lumberjack:client:groupUpdated',function(payload)group=payload or group;refreshPanel(false)end)
RegisterNetEvent('orbis-lumberjack:client:jobSync',applyJob)
RegisterNetEvent('orbis-lumberjack:client:jobFinished',function(reason)applyJob({active=false});if reason then notify(reason,'inform')end end)
RegisterNetEvent('orbis-lumberjack:client:reward',function(data)
 notify(('Servico concluido: %s | +%s XP'):format(OR.FormatMoney(data.payment),data.xp),'success');if data.leveledUp then notify(('Voce alcancou o nivel %s!'):format(data.level),'success')end
end)
RegisterNetEvent('orbis-lumberjack:client:groupInvite',function(invite)
 CreateThread(function()local answer=OR.Dialog.Confirm({header='Dupla de Lenhadores',content=('%s convidou voce para trabalhar em dupla.'):format(invite.name),centered=true,cancel=true,labels={confirm='Entrar',cancel='Recusar'}});local ok,message=OR.Callback.await('orbis-lumberjack:server:answerInvite',answer);if message then notify(message,ok and'success'or'error')end;refreshPanel(false)end)
end)
local function closePanel()state.panelOpen=false;SetNuiFocus(false,false);SendNUIMessage({action='close'})end
RegisterNetEvent('orbis-lumberjack:client:openPanel',function()refreshPanel(true)end)
local function registerNpcTarget()if GetResourceState('ob_target')=='started'and npcPed and DoesEntityExist(npcPed)then exports.ob_target:RegisterEntity('orbis_lumberjack_npc',npcPed,{label='Falar com o responsavel',icon='fa-solid fa-tree',event='orbis-lumberjack:client:openPanel',distance=3.0,canInteract=function(entity)return entity==npcPed end})end end

CreateThread(function()
 while LocalPlayer.state['or:loaded']~=true do Wait(250)end
 local cfg=Lumberjack.npc;local model=joaat(cfg.model);RequestModel(model);local timeout=GetGameTimer()+7000;while not HasModelLoaded(model)and GetGameTimer()<timeout do Wait(10)end
 if HasModelLoaded(model)then npcPed=CreatePed(4,model,cfg.coords.x,cfg.coords.y,cfg.coords.z-1.0,cfg.coords.w,false,true);if npcPed~=0 and DoesEntityExist(npcPed)then SetEntityAsMissionEntity(npcPed,true,true);FreezeEntityPosition(npcPed,true);SetEntityInvincible(npcPed,true);SetBlockingOfNonTemporaryEvents(npcPed,true);registerNpcTarget()end;SetModelAsNoLongerNeeded(model)else print('[ob_lumberjackjob] Nao foi possivel carregar o modelo do NPC.')end
 npcBlip=AddBlipForCoord(cfg.coords.x,cfg.coords.y,cfg.coords.z);SetBlipSprite(npcBlip,cfg.blip.sprite);SetBlipDisplay(npcBlip,4);SetBlipColour(npcBlip,cfg.blip.color);SetBlipScale(npcBlip,cfg.blip.scale);SetBlipAsShortRange(npcBlip,true);BeginTextCommandSetBlipName('STRING');AddTextComponentString(cfg.blip.name);EndTextCommandSetBlipName(npcBlip)
 for index,sawmill in ipairs(Lumberjack.sawmills or{})do local zoneId=('orbis_lumberjack_unload_%s'):format(index);sawmillZones[index]=zoneId
  exports.ob_target:RegisterBoxZone(zoneId,{coords=sawmill.interactionCoords.xyz,size=Lumberjack.sawmill.size,rotation=sawmill.interactionCoords.w,option={label='Confirmar descarga de madeira',icon='fa-solid fa-warehouse',canInteract=function()return state.active and state.sawmill==index and state.loaded>=(Lumberjack.sawmill.minLoadToDeliver or state.maxWood)end,action=function()
   if not progress('Confirmando descarga...',4500,{dict='amb@prop_human_bum_bin@base',clip='base'})then return end;local ok,message=OR.Callback.await('orbis-lumberjack:server:deliverLoad');if not ok then return notify(message or'Nao foi possivel descarregar.','error')end;notify('Madeira descarregada. Devolva o caminhão ao pátio para concluir e receber.','success')
  end}})
 end
 local status=OR.Callback.await('orbis-lumberjack:server:getStatus');if status then applyJob(status)end
end)
AddEventHandler('ob_target:client:ready',function()registerNpcTarget();registerTruckTarget()end)

CreateThread(function()
 while true do
  if not state.active then Wait(800)else
   local ped=PlayerPedId();local coords=GetEntityCoords(ped);text2d(('~y~Lenhador~w~ | Carga: ~g~%s/%s~w~ madeiras'):format(state.loaded,state.maxWood));local tree=treePoint(state.tree)
   if tree and state.loaded<state.maxWood and #(coords-tree)<180.0 and not IsPedInAnyVehicle(ped)then
    DrawMarker(1,tree.x,tree.y,tree.z-0.95,0,0,0,0,0,0,2.2,2.2,1.25,255,166,0,115,false,false,2,false);DrawMarker(2,tree.x,tree.y,tree.z+0.25,0,0,0,0,0,0,0.55,0.55,0.55,255,200,45,210,false,false,2,false)
    if #(coords-tree)<1.4 and Lumberjack.weapons[GetSelectedPedWeapon(ped)]then OR.Help.Show('[E] Cortar arvore');if IsControlJustReleased(0,38)then OR.Help.Hide();TaskTurnPedToFaceCoord(ped,tree.x,tree.y,tree.z,350);Wait(350)
      if progress('Cortando arvore...',2800,{dict='melee@hatchet@streamed_core',clip='plyr_front_takedown_b'})then local ok,amount,nextTree=OR.Callback.await('orbis-lumberjack:server:cutTree',state.tree);if ok then state.tree=nextTree;routeTree();notify(('%s madeiras coletadas. Leve-as ao caminhao.'):format(amount),'success')else notify(amount or'Esta arvore ja foi usada pela dupla.','error')end end
     end
    else OR.Help.Hide()end
   else OR.Help.Hide()end;Wait(0)
  end
 end
end)
CreateThread(function()
 while true do if not state.active then Wait(800)else local sawmill=getSawmill();if state.loaded>=(Lumberjack.sawmill.minLoadToDeliver or state.maxWood)and sawmill then drawCheckpoint(sawmill.vehicleCoords,5.0,{r=255,g=166,b=0,a=115});drawCheckpoint(sawmill.interactionCoords,1.5,{r=60,g=210,b=120,a=160})end;if state.returning then drawCheckpoint(Lumberjack.truck.spawn,5.0,{r=60,g=210,b=120,a=135})end;Wait(0)end end
end)
CreateThread(function()
 while true do
  if state.active and state.returning and state.vehicle~=0 and DoesEntityExist(state.vehicle)then local ped=PlayerPedId();if #(GetEntityCoords(state.vehicle)-Lumberjack.truck.spawn.xyz)<=7.0 and #(GetEntityCoords(ped)-Lumberjack.truck.spawn.xyz)<=9.0 then OR.Help.Show('[E] Devolver caminhão e concluir serviço');if IsControlJustReleased(0,38)then OR.Help.Hide();local ok,message=OR.Callback.await('orbis-lumberjack:server:returnTruck');if not ok then notify(message or'Não foi possível devolver o caminhão.','error')end end else OR.Help.Hide()end;Wait(0)else Wait(500)end
 end
end)
RegisterNUICallback('close',function(_,cb)closePanel();cb('ok')end)
RegisterNUICallback('start',function(_,cb)startJob();cb('ok')end)
RegisterNUICallback('stop',function(_,cb)stopJob();closePanel();cb('ok')end)
RegisterNUICallback('invite',function(data,cb)local ok,message=OR.Callback.await('orbis-lumberjack:server:inviteMember',data and data.id);if message then notify(message,ok and'success'or'error')end;refreshPanel(false);cb(ok and'ok'or'fail')end)
RegisterNUICallback('leaveGroup',function(_,cb)local ok,message=OR.Callback.await('orbis-lumberjack:server:leaveGroup');if message then notify(message,ok and'success'or'error')end;refreshPanel(false);cb(ok and'ok'or'fail')end)
AddEventHandler('onClientResourceStop',function(resource)if resource~=GetCurrentResourceName()then return end;removeRoute();clearTruck();exports.ob_target:RemoveEntityOption('orbis_lumberjack_npc');for _,zoneId in ipairs(sawmillZones)do exports.ob_target:UnregisterZone(zoneId)end;if npcPed and DoesEntityExist(npcPed)then DeleteEntity(npcPed)end end)
