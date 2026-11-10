local groups, locations, ready = {}, {}, false
local settings = ORInventoryShops.Editor
local locationTable, groupTable = 'ob_inventory_shop_locations', 'ob_inventory_shop_groups'
local syncEvent = 'ob_inventory:client:shopDefinitions'

local function text(value, limit)
    return (tostring(value or ''):gsub('[\r\n%z]',' '):gsub('%s+',' '):match('^%s*(.-)%s*$') or ''):sub(1,limit or 80)
end
local function number(value, low, high, fallback)
    local n=tonumber(value); if not n or n~=n or n==math.huge or n==-math.huge then n=fallback end
    return n and math.max(low,math.min(high,n)) or nil
end
local function point(raw)
    if type(raw)~='table' and type(raw)~='vector3' and type(raw)~='vector4' then return nil end
    local x,y,z=number(raw.x,-10000,10000),number(raw.y,-10000,10000),number(raw.z,-1000,3000)
    return x and y and z and {x=x,y=y,z=z,w=number(raw.w or raw.heading,0,360,0)} or nil
end
local function idValue(raw)
    local id=text(raw,64):lower(); return id~='' and id:match('^[a-z0-9_%-]+$') and id or nil
end
local function normalizeBlip(raw)
    if type(raw)~='table' then return nil end
    return {sprite=math.floor(number(raw.sprite,0,1000,52)),color=math.floor(number(raw.color,0,100,3)),scale=number(raw.scale,0.2,3,0.72)}
end
local function normalizeGroup(raw)
    if type(raw)~='table' then return nil,'Dados invalidos.' end
    local id,label=idValue(raw.id),text(raw.label,80); if not id then return nil,'Identificador de grupo invalido.' end
    if label=='' then return nil,'Informe o nome do grupo.' end
    local ped=text(raw.ped,64); if ped=='' or not ped:match('^[a-zA-Z0-9_]+$') then return nil,'Modelo de atendente invalido.' end
    local currency=text(raw.currency,48); if currency=='' then currency=ORInventoryMoneyConfig.ShopAccount or 'money' end
    if not ORInventoryMoneyConfig.Accounts[currency] then return nil,'Moeda nao cadastrada.' end
    local permission=text(raw.permission,64):lower(); if permission~='' and not permission:match('^[a-z0-9_%.:%-]+$') then return nil,'Permissao invalida.' end
    local row={id=id,label=label,ped=ped,currency=currency,permission=permission~='' and permission or nil,requireDuty=raw.requireDuty==true,
        departmentAccount=text(raw.departmentAccount,64),category=text(raw.category,32),purchasable=raw.purchasable==true,
        purchasePrice=math.floor(number(raw.purchasePrice,0,1000000000,(ORInventoryShops.Business or {}).DefaultPurchasePrice or 0)),
        purchaseLimit=math.floor(number(raw.purchaseLimit,1,1000,id=='police' and 100 or 10)),
        initialStock=math.floor(number(raw.initialStock,0,1000000,(ORInventoryShops.Business or {}).DefaultInitialStock or 50)),
        maxStock=math.floor(number(raw.maxStock,1,1000000,(ORInventoryShops.Business or {}).DefaultMaximumStock or 500)),
        blip=normalizeBlip(raw.blip),items={}}
    if row.departmentAccount=='' then row.departmentAccount=nil end; if row.category=='' then row.category=nil end
    local seen={}
    for _,entry in ipairs(type(raw.items)=='table' and raw.items or {}) do
        local name=text(entry.name,64); if not ORInventoryItems[name] then return nil,'Item nao cadastrado: '..name end
        if seen[name] then return nil,'Item repetido: '..name end; seen[name]=true
        row.items[#row.items+1]={name=name,price=math.floor(number(entry.price,0,100000000,0)),departmentPrice=math.floor(number(entry.departmentPrice,0,100000000,0)),
            maxPurchase=math.floor(number(entry.maxPurchase,0,1000,0)),
            wholesalePrice=math.floor(number(entry.wholesalePrice,0,100000000,0)),initialStock=math.floor(number(entry.initialStock,0,1000000,row.initialStock)),maxStock=math.floor(number(entry.maxStock,1,1000000,row.maxStock))}
        if #row.items>(settings.MaxItems or 150) then return nil,'Limite de produtos atingido.' end
    end
    return row
end
local function normalizeLocation(raw)
    if type(raw)~='table' then return nil,'Dados invalidos.' end
    local id,label=idValue(raw.id),text(raw.label,80); if not id then return nil,'Identificador do local invalido.' end
    if label=='' then return nil,'Informe o nome do local.' end
    local group=idValue(raw.group); if not group then return nil,'Selecione um grupo de loja.' end
    local coords=point(raw.coords); if not coords then return nil,'Capture a posicao da loja.' end
    return {id=id,label=label,group=group,coords=coords,purchasable=raw.purchasable~=false,
        purchasePrice=math.floor(number(raw.purchasePrice,0,1000000000,0)),
        purchaseLimit=math.floor(number(raw.purchaseLimit,0,1000,0)),manager=point(raw.manager),
        npcSpawn=point(raw.npcSpawn),truckStop=point(raw.truckStop or raw.npcTruckStop),
        npcWalkPoint=point(raw.npcWalkPoint),dropoff=point(raw.dropoff)}
end
local function list(map)
    local result={}; for _,row in pairs(map) do result[#result+1]=row end
    table.sort(result,function(a,b)return a.label==b.label and a.id<b.id or a.label<b.label end); return result
end
local function definitions()
    local publicGroups={}; for id,row in pairs(groups) do publicGroups[id]=row end
    return {groups=publicGroups,shops=list(locations)}
end
local function publish()
    local payload=definitions(); ORInventoryShops.Groups,ORInventoryShops.Shops=payload.groups,payload.shops
    TriggerLatentClientEvent(syncEvent,-1,100000,payload)
end
local function allowed(source)
    return settings.Enabled==true and GetResourceState('ob_admin')=='started' and exports.ob_admin:HasPermission(source,settings.Permission)==true
end
local function meta()
    local items={}; for name,item in pairs(ORInventoryItems) do items[#items+1]={name=name,label=item.label or name} end
    table.sort(items,function(a,b)return a.name<b.name end)
    return {mode='inventory',templates=OBShopSeeds.Groups,items=items,accounts=ORInventoryMoneyConfig.Accounts,maxItems=settings.MaxItems}
end
local function upsert(tableName,id,row)
    return OR.Database.query.await(('INSERT INTO %s (id,data,deleted) VALUES (?,?,0) ON DUPLICATE KEY UPDATE data=VALUES(data),deleted=0'):format(tableName),{id,json.encode(row)})
end

CreateThread(function()
    if not OR.Database.waitForReady(30000) then return print('[ob_inventory] Banco indisponivel para carregar lojas.') end
    for _,sql in ipairs({
        ('CREATE TABLE IF NOT EXISTS %s (id varchar(64) NOT NULL PRIMARY KEY,data longtext NOT NULL,deleted tinyint NOT NULL DEFAULT 0,updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'):format(locationTable),
        ('CREATE TABLE IF NOT EXISTS %s (id varchar(64) NOT NULL PRIMARY KEY,data longtext NOT NULL,deleted tinyint NOT NULL DEFAULT 0,updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'):format(groupTable),
    }) do local ok,err=OR.Database.query.await(sql); if ok==nil then return print(tostring(err)) end end
    local migrated=OR.Database.scalar.await(('SELECT id FROM %s WHERE id=?'):format(locationTable),{'__groups_v2'})
    if not migrated then
        local old=OR.Database.query.await(('SELECT id,data FROM %s WHERE deleted=0'):format(locationTable)) or {}
        if #old==0 then
            for id,raw in pairs(OBShopSeeds.Groups or {}) do local copy=json.decode(json.encode(raw));copy.id=id;local row=normalizeGroup(copy);if row then upsert(groupTable,id,row) end end
            for _,raw in ipairs(OBShopSeeds.Shops or {}) do local group=OBShopSeeds.Groups[raw.group] or {};local row=normalizeLocation({id=raw.id,label=raw.label or group.label,group=raw.group,coords=raw.coords,purchasable=raw.group=='convenience',purchasePrice=group.purchasePrice});if row then upsert(locationTable,row.id,row) end end
        else
            local made={}
            for _,entry in ipairs(old) do
                if entry.id:sub(1,2)~='__' then
                    local ok,raw=pcall(json.decode,entry.data); if ok and type(raw)=='table' then
                        local groupId=idValue(raw.group) or idValue(raw.id)
                        if groupId and not made[groupId] then local copy=json.decode(json.encode(raw));copy.id=groupId;copy.label=copy.label or groupId;if groupId=='convenience' then copy.category='convenience';copy.purchasable=true end;if groupId=='ammunation' then copy.category='weapons';copy.purchasable=false end;local group=normalizeGroup(copy);if group then upsert(groupTable,groupId,group);made[groupId]=true end end
                        local location=normalizeLocation({id=raw.id,label=raw.locationLabel or raw.label,group=groupId,coords=raw.coords,purchasable=groupId=='convenience',purchasePrice=raw.purchasePrice,manager=raw.manager,npcSpawn=raw.npcSpawn,truckStop=raw.truckStop,npcWalkPoint=raw.npcWalkPoint,dropoff=raw.dropoff})
                        if location then upsert(locationTable,location.id,location) end
                    end
                end
            end
        end
        OR.Database.query.await(('INSERT IGNORE INTO %s (id,data,deleted) VALUES (?,?,1)'):format(locationTable),{'__groups_v2','{}'})
    end
    for _,entry in ipairs(OR.Database.query.await(('SELECT id,data FROM %s WHERE deleted=0'):format(groupTable)) or {}) do local ok,raw=pcall(json.decode,entry.data);local row,err=ok and normalizeGroup(raw) or nil;if row then groups[row.id]=row else print('Grupo ignorado '..entry.id..': '..tostring(err)) end end
    local police=groups.police
    if police then
        local existing={};for _,item in ipairs(police.items or {}) do existing[item.name]=true end
        if not existing.empty_evidence_bag then police.items[#police.items+1]={name='empty_evidence_bag',price=0,departmentPrice=10,maxPurchase=20,wholesalePrice=0,initialStock=police.initialStock,maxStock=police.maxStock} end
        if not existing.forensic_kit then police.items[#police.items+1]={name='forensic_kit',price=0,departmentPrice=750,maxPurchase=1,wholesalePrice=0,initialStock=police.initialStock,maxStock=police.maxStock} end
        if not existing.residue_test_kit then police.items[#police.items+1]={name='residue_test_kit',price=0,departmentPrice=90,maxPurchase=10,wholesalePrice=0,initialStock=police.initialStock,maxStock=police.maxStock} end
        if not existing.chemical_test_kit then police.items[#police.items+1]={name='chemical_test_kit',price=0,departmentPrice=120,maxPurchase=10,wholesalePrice=0,initialStock=police.initialStock,maxStock=police.maxStock} end
        if not existing.fingerprint_collection_kit then police.items[#police.items+1]={name='fingerprint_collection_kit',price=0,departmentPrice=80,maxPurchase=10,wholesalePrice=0,initialStock=police.initialStock,maxStock=police.maxStock} end
        if not existing.forensic_magnifier then police.items[#police.items+1]={name='forensic_magnifier',price=0,departmentPrice=250,maxPurchase=1,wholesalePrice=0,initialStock=police.initialStock,maxStock=police.maxStock} end
        upsert(groupTable,police.id,police)
    end
    for _,entry in ipairs(OR.Database.query.await(('SELECT id,data FROM %s WHERE deleted=0'):format(locationTable)) or {}) do if entry.id:sub(1,2)~='__' then local ok,raw=pcall(json.decode,entry.data);local row,err=ok and normalizeLocation(raw) or nil;if row and groups[row.group] then locations[row.id]=row else print('Loja ignorada '..entry.id..': '..tostring(err or 'grupo inexistente')) end end end
    ready=true; publish()
end)

OR.Callback.register('worldShopDefinitions',function() if not ready then return nil,'Lojas carregando.' end return definitions() end)
OR.Callback.register('worldShopEditorData',function(source)
    if not allowed(source) then return nil,'Sem permissao.' end; if not ready then return nil,'Lojas carregando.' end
    return {records=list(locations),groups=list(groups),meta=meta()}
end)
OR.Callback.register('worldShopEditorTeleport',function(source,id)
    if not allowed(source) then return nil,'Sem permissao.' end; local row=locations[type(id)=='string' and id or ''];if not row then return nil,'Local nao encontrado.' end
    return {x=row.coords.x+1.5,y=row.coords.y,z=row.coords.z,heading=row.coords.w or 0}
end,{rateLimit={limit=3,window=10000}})
OR.Callback.register('worldShopEditorSave',function(source,raw)
    if not allowed(source) then return nil,'Sem permissao.' end;if not ready then return nil,'Aguarde o carregamento.' end
    if raw and raw.recordType=='group' then
        local row,err=normalizeGroup(raw);if not row then return nil,err end
        local result,dbErr=upsert(groupTable,row.id,row);if result==nil then return nil,dbErr or 'Falha ao salvar grupo.' end
        groups[row.id]=row;publish();return row,'Grupo salvo. Todas as lojas ligadas a ele foram atualizadas.'
    end
    local row,err=normalizeLocation(raw);if not row then return nil,err end;if not groups[row.group] then return nil,'Grupo de loja inexistente.' end
    if not locations[row.id] and #list(locations)>=(settings.MaxLocations or 200) then return nil,'Limite de locais atingido.' end
    local result,dbErr=upsert(locationTable,row.id,row);if result==nil then return nil,dbErr or 'Falha ao salvar local.' end
    locations[row.id]=row;publish();return row,'Local salvo e publicado.'
end,{rateLimit={limit=5,window=10000},payload={maxNodes=6000,maxDepth=12}})
OR.Callback.register('worldShopEditorDelete',function(source,data)
    if not allowed(source) then return nil,'Sem permissao.' end
    local id=type(data)=='table' and text(data.id,64) or text(data,64);local kind=type(data)=='table' and data.recordType or 'location'
    if kind=='group' then
        if not groups[id] then return nil,'Grupo nao encontrado.' end
        for _,location in pairs(locations) do if location.group==id then return nil,'Remova ou mova as lojas deste grupo primeiro.' end end
        local changed=OR.Database.update.await(('UPDATE %s SET deleted=1 WHERE id=?'):format(groupTable),{id});if not changed or changed<1 then return nil,'Falha ao remover grupo.' end;groups[id]=nil;publish();return true,'Grupo removido.'
    end
    if not locations[id] then return nil,'Local nao encontrado.' end
    local changed=OR.Database.update.await(('UPDATE %s SET deleted=1 WHERE id=?'):format(locationTable),{id});if not changed or changed<1 then return nil,'Falha ao remover local.' end;locations[id]=nil;publish();return true,'Local removido.'
end,{rateLimit={limit=3,window=10000}})
