local sessions,groups,memberGroup,pendingInvites={},{},{},{}
local databaseReady=false

local function getUserId(src)return exports.ob_core:GetUserId(src)end
local function getLeader(src)return memberGroup[src]or src end
local function getGroup(src,create)
 local leader=getLeader(src);local group=groups[leader]
 if not group and create then group={leader=leader,members={[leader]=true}};groups[leader]=group;memberGroup[leader]=leader end
 return leader,group
end
local function groupSources(leader)
 local group,result=groups[leader],{}
 if not group then return getUserId(leader)and{leader}or{}end
 for member in pairs(group.members)do if getUserId(member)then result[#result+1]=member else group.members[member]=nil;memberGroup[member]=nil end end
 table.sort(result);return result
end
local function groupPayload(src)
 local leader,group=getGroup(src,false);local members={}
 if group then for _,member in ipairs(groupSources(leader))do members[#members+1]={id=member,name=GetPlayerName(member)or('ID %s'):format(member),leader=member==leader}end
 else members[1]={id=src,name=GetPlayerName(src)or('ID %s'):format(src),leader=true}end
 return{leader=leader,isLeader=src==leader,maxMembers=Lumberjack.group.maxMembers or 2,members=members}
end
local function broadcastGroup(leader)for _,member in ipairs(groupSources(leader))do TriggerClientEvent('orbis-lumberjack:client:groupUpdated',member,groupPayload(member))end end
local function getSession(src)local leader=getLeader(src);return sessions[leader],leader end
local function sessionPayload(session)
 if not session then return{active=false}end
 return{active=true,tree=session.tree,loaded=session.loaded,maxWood=Lumberjack.truck.maxWood,sawmill=session.sawmill,returning=session.returning==true,vehicleNetId=session.vehicle}
end
local function broadcastSession(leader)local payload=sessionPayload(sessions[leader]);for _,member in ipairs(groupSources(leader))do TriggerClientEvent('orbis-lumberjack:client:jobSync',member,payload)end end
local function vehicleEntity(netId)
 netId=tonumber(netId);if not netId or netId<=0 then return nil end
 local entity=NetworkGetEntityFromNetworkId(netId);return entity~=0 and DoesEntityExist(entity)and entity or nil
end
local function deleteSessionVehicle(leader,session,detached)if session and session.vehicle then if detached then exports.ob_core:DeleteTemporaryVehicleDetached(leader,session.vehicle)else exports.ob_core:DeleteTemporaryVehicle(leader,session.vehicle)end;session.vehicle=nil end end
local function finishSession(leader,reason,detached)
 local session=sessions[leader];if not session then return end
 deleteSessionVehicle(leader,session,detached);sessions[leader]=nil
 for _,member in ipairs(groupSources(leader))do TriggerClientEvent('orbis-lumberjack:client:jobFinished',member,reason)end
end

local function characterIdColumnType()
 local deadline=GetGameTimer()+30000
 repeat local columnType=exports.ob_core:GetCharacterIdColumnType();if columnType then return columnType end;Wait(100)until GetGameTimer()>=deadline
end
local progressSchema=[[
CREATE TABLE IF NOT EXISTS ob_lumberjack_progress (
 user_id %s NOT NULL PRIMARY KEY,xp INT NOT NULL DEFAULT 0,level INT NOT NULL DEFAULT 1,
 loads_completed INT NOT NULL DEFAULT 0,total_earned INT NOT NULL DEFAULT 0,
 updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
 CONSTRAINT fk_ob_lumberjack_progress_character FOREIGN KEY (user_id) REFERENCES ob_characters(user_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]]
local function getLevel(xp)local p=Lumberjack.progress;return math.min(math.floor((tonumber(xp)or 0)/p.levelStep)+1,p.maxLevel)end
local function ensureProgress(userId)
 userId=tonumber(userId);if not databaseReady or not userId then return nil end
 OR.Database.update.await('INSERT IGNORE INTO ob_lumberjack_progress (user_id) VALUES (?)',{userId})
 local row=OR.Database.single.await('SELECT * FROM ob_lumberjack_progress WHERE user_id = ?',{userId});if not row then return nil end
 local level=getLevel(row.xp);if tonumber(row.level)~=level then row.level=level;OR.Database.update.await('UPDATE ob_lumberjack_progress SET level = ? WHERE user_id = ?',{level,userId})end
 return row
end
local function newTree(last)local tree=math.random(#Lumberjack.trees);while #Lumberjack.trees>1 and tree==last do tree=math.random(#Lumberjack.trees)end;return tree end
local function near(src,coords,distance)local ped=GetPlayerPed(src);return ped and ped~=0 and #(GetEntityCoords(ped)-coords)<=distance end
local function getSawmill(index)return Lumberjack.sawmills and Lumberjack.sawmills[tonumber(index)or 0]end
local function leaderboard(userId,row)
 local rows=OR.Database.query.await([[SELECT l.user_id,l.xp,l.loads_completed,c.firstname,c.lastname FROM ob_lumberjack_progress AS l LEFT JOIN ob_characters AS c ON c.user_id=l.user_id ORDER BY l.xp DESC,l.loads_completed DESC,l.user_id ASC LIMIT 10]])or{}
 local list={};for rank,entry in ipairs(rows)do list[#list+1]={rank=rank,name=((entry.firstname or'')..' '..(entry.lastname or'')):gsub('^%s*(.-)%s*$','%1'),xp=tonumber(entry.xp)or 0,loads=tonumber(entry.loads_completed)or 0}end
 local higher=OR.Database.scalar.await([[SELECT COUNT(*) FROM ob_lumberjack_progress WHERE xp > ? OR (xp = ? AND loads_completed > ?) OR (xp = ? AND loads_completed = ? AND user_id < ?)]],{row.xp or 0,row.xp or 0,row.loads_completed or 0,row.xp or 0,row.loads_completed or 0,userId})
 return{list=list,myRank=(tonumber(higher)or 0)+1,myValue=tonumber(row.xp)or 0}
end
local function panelData(src)
 local userId=getUserId(src);local row=ensureProgress(userId);if not row then return nil end
 local session=getSession(src);local level=tonumber(row.level)or 1;local base=(level-1)*Lumberjack.progress.levelStep
 return{progress={level=level,xp=tonumber(row.xp)or 0,xpInLevel=(tonumber(row.xp)or 0)-base,xpRequired=Lumberjack.progress.levelStep,completed=tonumber(row.loads_completed)or 0,totalEarned=tonumber(row.total_earned)or 0,paymentBonus=math.floor(math.min((level-1)*Lumberjack.progress.paymentBonusPerLevel,Lumberjack.progress.maxPaymentBonus)*100),paymentBonusStep=Lumberjack.progress.paymentBonusPerLevel*100},work=sessionPayload(session),group=groupPayload(src),leaderboard=leaderboard(userId,row)}
end

OR.Callback.register('orbis-lumberjack:server:getPanelData',function(src)return panelData(src)end)
OR.Callback.register('orbis-lumberjack:server:getStatus',function(src)local session=getSession(src);local payload=sessionPayload(session);payload.progress=ensureProgress(getUserId(src));return payload end)
OR.Callback.register('orbis-lumberjack:server:startJob',function(src)
 local leader=getLeader(src);if src~=leader then return false,'Somente o lider pode iniciar o trabalho da dupla.'end
 if sessions[leader]then return false,'O trabalho da dupla ja foi iniciado.'end
 local members=groupSources(leader);for _,member in ipairs(members)do if not ensureProgress(getUserId(member))then return false,'Um integrante esta com o personagem ou banco indisponivel.'end end
 local sawmill=math.random(#Lumberjack.sawmills);sessions[leader]={tree=newTree(),vehicle=nil,loaded=0,sawmill=sawmill}
 broadcastSession(leader);broadcastGroup(leader);return true,sessionPayload(sessions[leader])
end)
OR.Callback.register('orbis-lumberjack:server:spawnVehicle',function(src)
 local session,leader=getSession(src);if src~=leader then return false,'Somente o lider pode retirar o caminhao.'end
 if not session then return false,'Inicie o servico primeiro.'end;if vehicleEntity(session.vehicle)then return false,'Voce ja retirou o caminhao.'end
 local spawned,result=exports.ob_core:SpawnTemporaryVehicle(src,Lumberjack.truck.model,Lumberjack.truck.spawn,{platePrefix=Lumberjack.truck.platePrefix or'LENHA',fuel=100.0,clearRadius=Lumberjack.truck.spawnClearRadius or 4.0,maxDistance=100.0,serverSetterType='automobile'})
 if not spawned then return false,result end;session.vehicle=result.netId
 for _,member in ipairs(groupSources(leader))do if member~=leader then exports.ob_vehiclekeys:GiveSpareKey(member,result.netId)end end
 broadcastSession(leader);return true,result
end)
OR.Callback.register('orbis-lumberjack:server:cutTree',function(src,treeIndex)
 local allowed,retry=OR.Security.rateLimit(src,'lumberjack:cut_tree',1,2500);if not allowed then return false,('Aguarde %.1f segundos.'):format((retry or 1000)/1000)end
 local session,leader=getSession(src);treeIndex=tonumber(treeIndex);local tree=treeIndex and Lumberjack.trees[treeIndex]
 if not session or treeIndex~=session.tree or not tree or not near(src,tree.xyz,8.0)or session.returning then return false end
 if session.loaded>=Lumberjack.truck.maxWood then return false,'O caminhao ja esta cheio.'end
 local carried=exports.ob_inventory:GetItemCount(src,Lumberjack.payment.item)or 0;local available=math.max(0,Lumberjack.truck.carryMax-carried)
 if available<1 then return false,'Leve a madeira ate o caminhao.'end
 local amount=math.min(math.random(Lumberjack.payment.min,Lumberjack.payment.max),available);local canCarry,carryError=exports.ob_inventory:CanCarryItem(src,Lumberjack.payment.item,amount)
 if not canCarry then return false,carryError or'Sem espaco na mochila.'end;local added,addError=exports.ob_inventory:AddItem(src,Lumberjack.payment.item,amount);if not added then return false,addError end
 session.tree=newTree(treeIndex);broadcastSession(leader);return true,amount,session.tree
end)
OR.Callback.register('orbis-lumberjack:server:loadTruck',function(src)
 if not OR.Security.rateLimit(src,'lumberjack:load_truck',1,1000)then return false,'Aguarde para carregar novamente.'end
 local session,leader=getSession(src);if not session or not session.vehicle then return false,'Pegue o caminhao primeiro.'end;if session.returning then return false,'A carga ja foi descarregada.'end
 local vehicle=vehicleEntity(session.vehicle);if not vehicle or not near(src,GetEntityCoords(vehicle),(Lumberjack.truck.loadDistance or 6.0)+2.0)then return false,'Chegue mais perto do caminhao.'end
 local available=exports.ob_inventory:GetItemCount(src,Lumberjack.payment.item)or 0;local amount=math.min(available,Lumberjack.truck.maxWood-session.loaded,Lumberjack.truck.loadBatch or 5)
 if amount<1 then return false,'Corte madeira antes de carregar o caminhao.'end;local removed,err=exports.ob_inventory:RemoveItem(src,Lumberjack.payment.item,amount);if not removed then return false,err end
 session.loaded=session.loaded+amount;broadcastSession(leader);return true,amount,session.loaded,Lumberjack.truck.maxWood
end)
OR.Callback.register('orbis-lumberjack:server:deliverLoad',function(src)
 if not OR.Security.rateLimit(src,'lumberjack:deliver_load',1,5000)then return false,'Aguarde para descarregar novamente.'end
 local session,leader=getSession(src);local sawmill=session and getSawmill(session.sawmill);local minimum=Lumberjack.sawmill.minLoadToDeliver or Lumberjack.truck.maxWood
 if not session or not sawmill or not session.vehicle or session.loaded<minimum or session.returning then return false,'Carga invalida.'end
 local vehicle=vehicleEntity(session.vehicle);if not vehicle or #(GetEntityCoords(vehicle)-sawmill.vehicleCoords.xyz)>(Lumberjack.sawmill.vehicleDistance or 6.0)then return false,'Estacione o caminhao na area de descarga.'end
 if not near(src,sawmill.interactionCoords.xyz,5.0)then return false,'Chegue ao ponto de descarga.'end
 local base=0;for _=1,session.loaded do base=base+math.random(Lumberjack.sawmill.paymentPerWood.min,Lumberjack.sawmill.paymentPerWood.max)end
 session.pendingBase=base;session.pendingXp=session.loaded*Lumberjack.progress.xpPerWood;session.loaded=0;session.returning=true;broadcastSession(leader);return true
end)
OR.Callback.register('orbis-lumberjack:server:returnTruck',function(src)
 local session,leader=getSession(src);if not session or not session.returning or not session.vehicle then return false,'Nenhuma entrega aguardando devolucao.'end
 local vehicle=vehicleEntity(session.vehicle);if not vehicle or #(GetEntityCoords(vehicle)-Lumberjack.truck.spawn.xyz)>7.0 or not near(src,Lumberjack.truck.spawn.xyz,9.0)then return false,'Estacione o caminhao no patio.'end
 local members=groupSources(leader);local share=math.floor(math.max(0,session.pendingBase or 0)/math.max(1,#members));local xp=math.max(0,session.pendingXp or 0);local rewards={}
 for _,member in ipairs(members)do local userId=getUserId(member);local row=ensureProgress(userId);if not row then return false,'Progresso de um integrante indisponivel.'end
  local bonus=math.min(((tonumber(row.level)or 1)-1)*Lumberjack.progress.paymentBonusPerLevel,Lumberjack.progress.maxPaymentBonus);local payment=math.floor(share*(1+bonus))
  local canCarry,err=exports.ob_inventory:CanCarryItem(member,'money',payment);if not canCarry then return false,err or('Sem espaco no inventario de %s.'):format(GetPlayerName(member)or member)end
  rewards[#rewards+1]={source=member,userId=userId,row=row,payment=payment}
 end
 for _,reward in ipairs(rewards)do local paid,err=exports.ob_inventory:AddItem(reward.source,'money',reward.payment);if not paid then return false,err or'Nao foi possivel pagar a dupla.'end
  local newXp=(tonumber(reward.row.xp)or 0)+xp;local newLevel=getLevel(newXp);OR.Database.update.await('UPDATE ob_lumberjack_progress SET xp = ?, level = ?, loads_completed = loads_completed + 1, total_earned = total_earned + ? WHERE user_id = ?',{newXp,newLevel,reward.payment,reward.userId})
  TriggerClientEvent('orbis-lumberjack:client:reward',reward.source,{payment=reward.payment,xp=xp,level=newLevel,leveledUp=newLevel>(tonumber(reward.row.level)or 1)})
 end
 deleteSessionVehicle(leader,session);sessions[leader]=nil;broadcastSession(leader);return true
end)
OR.Callback.register('orbis-lumberjack:server:stopJob',function(src)local session,leader=getSession(src);if src~=leader then return false,'Somente o lider pode finalizar o trabalho da dupla.'end;if session then finishSession(leader,'O lider finalizou o trabalho da dupla.')end;return true end)

OR.Callback.register('orbis-lumberjack:server:inviteMember',function(src,target)
 if not OR.Security.rateLimit(src,'lumberjack:group_invite',3,10000)then return false,'Aguarde antes de convidar novamente.'end
 target=tonumber(target);local leader,group=getGroup(src,true);if src~=leader then return false,'Somente o lider pode convidar.'end;if sessions[leader]then return false,'Finalize o trabalho antes de alterar a dupla.'end
 if not target or target==src or not getUserId(target)then return false,'Jogador invalido.'end
 local targetLeader,targetGroup=getGroup(target,false);if sessions[targetLeader]then return false,'Esse jogador esta em servico.'end;if targetGroup and #groupSources(targetLeader)==1 then groups[targetLeader]=nil;memberGroup[target]=nil elseif memberGroup[target]then return false,'Esse jogador ja esta em uma dupla.'end
 if #groupSources(leader)>=(Lumberjack.group.maxMembers or 2)then return false,'A dupla ja esta completa.'end
 local p1,p2=GetPlayerPed(src),GetPlayerPed(target);if p1==0 or p2==0 or #(GetEntityCoords(p1)-GetEntityCoords(p2))>(Lumberjack.group.inviteDistance or 18.0)then return false,'O jogador precisa estar proximo.'end
 pendingInvites[target]={leader=leader,expires=os.time()+(Lumberjack.group.inviteSeconds or 30)};TriggerClientEvent('orbis-lumberjack:client:groupInvite',target,{name=GetPlayerName(src)or('ID %s'):format(src)});return true,'Convite enviado.'
end)
OR.Callback.register('orbis-lumberjack:server:answerInvite',function(src,accept)
 local invite=pendingInvites[src];pendingInvites[src]=nil;local group=invite and groups[invite.leader]
 if not invite or invite.expires<os.time()or not group then return false,'Convite expirado.'end;if not accept then return true,'Convite recusado.'end
 if memberGroup[src]or sessions[src]or sessions[invite.leader]or #groupSources(invite.leader)>=(Lumberjack.group.maxMembers or 2)then return false,'Dupla indisponivel.'end
 local p1,p2=GetPlayerPed(invite.leader),GetPlayerPed(src);if p1==0 or p2==0 or #(GetEntityCoords(p1)-GetEntityCoords(p2))>(Lumberjack.group.inviteDistance or 18.0)then return false,'Aproxime-se do lider para entrar na dupla.'end
 group.members[src]=true;memberGroup[src]=invite.leader;broadcastGroup(invite.leader);return true,'Voce entrou na dupla de lenhadores.'
end)
OR.Callback.register('orbis-lumberjack:server:leaveGroup',function(src)
 local leader,group=getGroup(src,false);if not group then return true end;if sessions[leader]then return false,'Finalize o trabalho antes de sair da dupla.'end
 if src==leader then local members=groupSources(leader);groups[leader]=nil;for _,member in ipairs(members)do memberGroup[member]=nil;TriggerClientEvent('orbis-lumberjack:client:groupUpdated',member,groupPayload(member))end
 else group.members[src]=nil;memberGroup[src]=nil;TriggerClientEvent('orbis-lumberjack:client:groupUpdated',src,groupPayload(src));broadcastGroup(leader)end
 return true,'Voce saiu da dupla.'
end)

AddEventHandler('playerDropped',function()
 local dropped=source;pendingInvites[dropped]=nil;local leader,group=getGroup(dropped,false)
 if sessions[leader]then finishSession(leader,dropped==leader and'O lider saiu; o trabalho da dupla foi encerrado.'or'Um integrante saiu; o trabalho da dupla foi encerrado.',dropped==leader)end
 if not group then return end;group.members[dropped]=nil;memberGroup[dropped]=nil
 if dropped==leader then groups[leader]=nil;local nextLeader;for member in pairs(group.members)do if getUserId(member)then nextLeader=member break end end
  if nextLeader then group.leader=nextLeader;groups[nextLeader]=group;for member in pairs(group.members)do memberGroup[member]=nextLeader end;broadcastGroup(nextLeader)end
 else broadcastGroup(leader)end
end)
AddEventHandler('onResourceStop',function(resource)if resource~=GetCurrentResourceName()then return end;for leader,session in pairs(sessions)do if session.vehicle then exports.ob_core:DeleteTemporaryVehicleDetached(leader,session.vehicle)end;sessions[leader]=nil end end)
CreateThread(function()
 if not OR.Database.waitForReady(30000)then print('[ob_lumberjackjob] Banco indisponivel; emprego nao iniciado.');return end
 local columnType=characterIdColumnType();if not columnType then print('[ob_lumberjackjob] Tipo de ob_characters.user_id indisponivel.');return end
 local created,errorMessage=OR.Database.query.await(progressSchema:format(columnType));databaseReady=created~=nil;if not databaseReady then print(('[ob_lumberjackjob] Falha ao criar tabela: %s'):format(errorMessage or'desconhecida'))end
end)
