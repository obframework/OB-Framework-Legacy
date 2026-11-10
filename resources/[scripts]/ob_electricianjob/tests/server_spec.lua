-- Harness Lua 5.4 isolado: nenhum banco, entidade ou jogador real.
local callbacks, threads, timers, events = {}, {}, {}, {}
local positions, health, driver, now, payments = {}, {}, 0, 0, 0
local mt = {}
function vec3(x,y,z) return setmetatable({x=x,y=y,z=z}, mt) end
vector3 = vec3
function vec4(x,y,z,w) local v=vec3(x,y,z);v.w=w;return v end
mt.__add=function(a,b)return vec3(a.x+b.x,a.y+b.y,a.z+b.z)end
mt.__sub=function(a,b)return vec3(a.x-b.x,a.y-b.y,a.z-b.z)end
mt.__len=function(v)return math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z)end
function CreateThread(fn) threads[#threads+1]=fn end
function SetTimeout(ms,fn) timers[#timers+1]={ms=ms,fn=fn} end
function AddEventHandler(name,fn) events[name]=fn end
function TriggerClientEvent() end
function TriggerEvent() end
function GetGameTimer() return now end
function GetPlayerPed(source) return source end
function GetPlayerName(source) return 'Test '..source end
function GetEntityCoords(entity) return positions[entity] or vec3(0,0,0) end
function GetEntityHealth(entity) return health[entity] or 200 end
function NetworkGetEntityFromNetworkId(id) return id end
function NetworkGetNetworkIdFromEntity(id) return id end
function DoesEntityExist(entity) return entity ~= 0 end
function GetPedInVehicleSeat() return driver end
function GetPlayerRoutingBucket() return 0 end
function SetEntityRoutingBucket() end
function SetEntityOrphanMode() end
function DeleteEntity() end
function CreateObject() return 200 end
function joaat() return 1 end
function Entity() return {state={set=function()end}} end
function Wait() coroutine.yield() end
OR = {Callback={register=function(name,fn) callbacks[name:match('server:(.+)')]=fn end},Security={rateLimit=function()return true end},Database={}}
OR.Database.update={await=function()return 1 end}
OR.Database.single={await=function()return {xp=0} end}
exports = {
 ob_core={GetUserId=function(_,source)return source end,SpawnTemporaryVehicle=function()return true,{netId=100}end,DeleteTemporaryVehicle=function()return true end},
 ob_vehiclekeys={GrantTemporaryKey=function()end},
 ob_inventory={AddItem=function(_,source,item,amount)payments=payments+1;return true end},
}
dofile(TEST_ROOT .. '/config.lua')
dofile(TEST_ROOT .. '/server/main.lua')
for i=1,20 do local name=debug.getupvalue(callbacks.startJob,i);if name=='databaseReady' then debug.setupvalue(callbacks.startJob,i,true);break end end
local function status(source) return callbacks.getStatus(source or 1) end
local function atTask()
 local task=Electrician.tasks[status().task]
 positions[1]=task.search;positions[100]=task.search
 return task
end
local function prepare()
 return atTask()
end
local function repair(task, testFailures)
 for stage=1,3 do
  positions[1]=positions[100]
  assert(not callbacks.takeTool(1,stage==1 and 2 or 1),'Ferramenta errada foi aceita')
  assert(callbacks.takeTool(1,stage))
  positions[1]=task.search+vec3(0,0,task.zOffset)
  assert(callbacks.beginStep(1,stage))
  assert(not callbacks.beginStep(1,stage),'Dupla iniciou simultaneamente')
  if testFailures and stage==1 then
   assert(not callbacks.finishStep(1,stage,true),'Conclusao instantanea foi aceita')
   assert(callbacks.beginStep(1,stage));now=now+3000
   assert(not callbacks.finishStep(1,stage,false),'Cancelamento foi aceito como sucesso')
   assert(callbacks.beginStep(1,stage));now=now+3000
   positions[1]=vec3(0,0,0)
   assert(not callbacks.finishStep(1,stage,true),'Reparo remoto foi aceito')
   positions[1]=task.search+vec3(0,0,task.zOffset)
   assert(callbacks.beginStep(1,stage))
  end
  now=now+3000
  local ok,complete=callbacks.finishStep(1,stage,true)
  assert(ok and complete==(stage==3))
  if stage<3 then assert(not callbacks.beginStep(1,stage+1),'Nao exigiu troca da ferramenta') end
  positions[1]=positions[100]
  assert(callbacks.returnTool(1))
 end
 assert(status().repaired)
 assert(callbacks.completeService(1))
 assert(status().stage==1 and not status().repaired)
end
assert(callbacks.startJob(1));assert(callbacks.spawnVehicle(1))
for i=1,5 do
 local task=prepare();assert(task.type=='ground','Solo recebeu poste');repair(task,i==1)
end
assert(status().completed==5 and status().batchCompleted==0 and payments==1,'Lote nao pago corretamente')
assert(not callbacks.completeService(1));assert(payments==1,'Pagamento duplicado')
assert(callbacks.stopJob(1))
positions[1]=vec3(0,0,0);positions[2]=vec3(0,0,0)
assert(callbacks.invite(1,2));assert(callbacks.answerInvite(2,true))
assert(callbacks.startJob(1));assert(callbacks.spawnVehicle(1))
-- Forca somente a escolha do ponto para exercitar a regra aerea.
local jobFor
for i=1,20 do local name,value=debug.getupvalue(callbacks.beginStep,i);if name=='jobFor' then jobFor=value;break end end
local job=jobFor(1);job.task=5
local task=prepare();assert(callbacks.takeTool(1,1))
positions[1]=task.search+vec3(0,0,task.zOffset)
assert(not callbacks.beginStep(1,1),'Poste sem operador foi aceito')
driver=2;assert(callbacks.beginStep(1,1));now=now+3000;driver=0
assert(not callbacks.finishStep(1,1,true),'Operador saiu mas reparo foi aceito')
driver=2;assert(callbacks.beginStep(1,1));now=now+3000
assert(callbacks.finishStep(1,1,true))
assert(status(2).stage==2,'Dupla nao compartilha progresso')
positions[1]=positions[100];assert(callbacks.returnTool(1));assert(callbacks.takeTool(1,2))
positions[1]=task.search+vec3(0,0,task.zOffset);assert(callbacks.beginStep(1,2))
timers[#timers].fn();assert(callbacks.beginStep(1,2),'Timeout manteve a etapa travada')
health[1]=0
local watchdog=coroutine.create(threads[1]);assert(coroutine.resume(watchdog));assert(coroutine.resume(watchdog))
assert(status().toolHolder==false and job.busy==nil,'Morte manteve ferramenta ou etapa travada')
print('Servidor OK: 5 chamados solo, 3 etapas, ferramentas, concorrencia, cancelamento, distancia, pagamento unico, dupla, timeout e morte.')
