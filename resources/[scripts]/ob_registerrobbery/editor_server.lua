local resource=GetCurrentResourceName()
local function allowed(src)
    if exports.ob_core:IsAdmin(src) then return true end
    if IsPlayerAceAllowed(src,Config.EditorAce or 'or.admin') then return true end
    if GetResourceState('ob_admin')=='started' then
        local ok,result=pcall(function() return exports.ob_admin:HasPermission(src,Config.EditorPermission or 'world.shops') end)
        return ok and result==true
    end
    return false
end
local function number(value,min,max)
    local n=tonumber(value)
    if not n or n~=n or n<min or n>max then return nil end
    return n
end
local function normalize(data)
    if type(data)~='table' or type(data.coords)~='table' then return nil,'Dados invalidos.' end
    local id=type(data.id)=='string' and data.id or ''
    if #id<1 or #id>48 or not id:match('^[%w_%-]+$') then return nil,'ID invalido: use letras, numeros e _.' end
    local p=data.coords
    local coords={x=number(p.x,-16000,16000),y=number(p.y,-16000,16000),z=number(p.z,-300,3000),w=number(p.w or 0,0,360)}
    if not coords.x or not coords.y or not coords.z or not coords.w then return nil,'Coordenadas invalidas.' end
    local minimum=number(data.minimum or Config.Reward.min,1,50000)
    local maximum=number(data.maximum or Config.Reward.max,1,50000)
    local police=number(data.police or Config.MinimumPolice,0,128)
    local seconds=number(data.seconds or Config.RegisterSeconds,3,600)
    local cooldown=number(data.cooldown or Config.CooldownSeconds,30,604800)
    if not minimum or not maximum or minimum>maximum or not police or not seconds or not cooldown then return nil,'Premios, policia ou tempos invalidos.' end
    return {id=id,label=tostring(data.label or id):sub(1,80),coords=coords,radius=8,
        police=math.floor(police),cooldown=math.floor(cooldown),prop=data.spawnProp==true and 'prop_till_01' or nil,
        reward={min=math.floor(minimum),max=math.floor(maximum)},
        steps={{label='Arrombar registradora',item=Config.RegisterItem,consume=true,seconds=math.floor(seconds),game='Keypress',options={steps=3,speed=1,tolerance=0.12}}},
        loot={{x=coords.x,y=coords.y,z=coords.z,model='prop_cash_pile_01'}},
    }
end
local ready=true
local raw=GetResourceKvpString('registers:definitions:v1')
if raw then
    local ok, rows=pcall(json.decode,raw)
    if ok and type(rows)=='table' then HeistLocations=rows
    else ready=false; print('[ob_registerrobbery] Cadastro KVP invalido; editor bloqueado para preservar os dados.') end
end
local function save() SetResourceKvp('registers:definitions:v1',json.encode(HeistLocations)); HeistBroadcast() end
local function rows()
    local list={}
    for id,location in pairs(HeistLocations) do
        local reward=location.reward or Config.Reward
        list[#list+1]={id=id,label=location.label,coords=location.coords,spawnProp=location.prop~=nil,
            police=location.police or Config.MinimumPolice,cooldown=location.cooldown or Config.CooldownSeconds,
            seconds=location.steps[1].seconds,minimum=reward.min,maximum=reward.max}
    end
    table.sort(list,function(a,b) return a.label<b.label end)
    return list
end
OR.Callback.register('editorData',function(src)
    if not allowed(src) then return nil,'Sem permissao.' end
    if not ready then return nil,'Cadastro indisponivel. Verifique o console.' end
    return {rows=rows()}
end)
OR.Callback.register('editorSave',function(src,data)
    if not allowed(src) or not ready then return nil,'Sem permissao ou cadastro indisponivel.' end
    local row,message=normalize(data)
    if not row then return nil,message end
    local count=0; for _ in pairs(HeistLocations) do count=count+1 end
    if not HeistLocations[row.id] and count>=(Config.MaxRegisters or 300) then return nil,'Limite de registradoras atingido.' end
    if HeistStateFor(row.id).phase=='active' then return nil,'Espere o roubo em andamento terminar.' end
    HeistLocations[row.id]=row; save()
    print(('[%s] registradora salva por session=%s id=%s'):format(resource,src,row.id))
    return {rows=rows()},'Registradora salva.'
end,{rateLimit={limit=5,window=10000}})
OR.Callback.register('editorDelete',function(src,id)
    if not allowed(src) or not ready then return nil,'Sem permissao ou cadastro indisponivel.' end
    if type(id)~='string' or not HeistLocations[id] then return nil,'Registradora nao encontrada.' end
    if HeistStateFor(id).phase=='active' then return nil,'Espere o roubo terminar.' end
    HeistLocations[id]=nil; save()
    return {rows=rows()},'Registradora excluida.'
end,{rateLimit={limit=5,window=10000}})
OR.Callback.register('editorTeleport',function(src,id)
    if not allowed(src) or not ready then return nil,'Sem permissao.' end
    local row=type(id)=='string' and HeistLocations[id]
    if not row then return nil,'Salve a registradora primeiro.' end
    -- Retorna somente o local cadastrado, nunca um destino recebido da NUI.
    return {x=row.coords.x,y=row.coords.y-1.2,z=row.coords.z+0.5,w=row.coords.w or 0}
end,{rateLimit={limit=4,window=10000}})
