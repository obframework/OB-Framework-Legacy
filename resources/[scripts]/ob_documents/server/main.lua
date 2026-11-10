local ready,locks=false,{}

local function sql(kind,statement,params)
    local result,err=OR.Database[kind].await(statement,params or {})
    if result==nil then error(err or 'Banco indisponivel.') end
    return result
end
local function userId(src) return exports.ob_core:GetUserId(src) end
local function notify(src,text,kind)
    TriggerClientEvent('ob_notification:client:notify',src,text,kind or 'info',7000)
end
local function rowFor(id)
    local rows=sql('query',[[SELECT user_id,identity_issued_at,driver_issued_at,driver_expires_at
        FROM ob_license_documents WHERE user_id=? LIMIT 1]],{id})
    return rows[1] or {user_id=id,identity_issued_at=0,driver_issued_at=0,driver_expires_at=0}
end
local function licenseRows(id)
    if GetResourceState('ob_licenca')~='started' then return {},false end
    local ok,rows=pcall(sql,'query','SELECT category,licensed,issued_at FROM ob_licenses WHERE user_id=?',{id})
    if not ok then return {},false end
    local result={}
    for _,row in ipairs(rows) do
        result[row.category]=row
    end
    return result,true
end
local function yes(value) return value==true or tonumber(value)==1 end
local function fullName(character)
    return (('%s %s'):format(character and character.firstname or '',character and character.lastname or '')):gsub('^%s+',''):gsub('%s+$','')
end
local function legalJobLabel(src)
    local org=Player(src).state['ob:org']
    if type(org)=='table' then
        if org.type=='illegal' then return 'Desempregado' end
        if org.type=='legal' then return tostring(org.label or org.key or 'Trabalho legal') end
    end
    local job=exports.ob_core:GetJob(src)
    if type(job)=='table' and job.name~='unemployed' then return tostring(job.label or job.name) end
    return 'Desempregado'
end
local function categories(id)
    local stored,available=licenseRows(id)
    local list,classes={},{}
    for _,name in ipairs(OBDocuments.CategoryOrder) do
        local definition,row=OBDocuments.Categories[name],stored[name]
        if definition and row and yes(row.licensed) then
            list[#list+1]={name=name,label=definition.label,class=definition.class,issuedAt=tonumber(row.issued_at) or 0}
            classes[#classes+1]=definition.class
        end
    end
    return list,classes,stored,available
end
local function owned(src,itemName,id)
    local inventory=exports.ob_inventory:GetInventory(src)
    for _,item in pairs(inventory and inventory.items or {}) do
        if item.name==itemName and tonumber(item.metadata and item.metadata.userId)==tonumber(id) then return item end
    end
end
local function identityMetadata(src,id)
    local character=exports.ob_core:GetCharacter(src)
    local name,job=fullName(character),legalJobLabel(src)
    return {documentType='identity',userId=id,firstname=character and character.firstname or '',
        lastname=character and character.lastname or '',fullName=name,birthdate=character and character.birthdate or '',
        nationality=character and character.nationality or '',job=job,
        description=('Nome: %s\nRegistro: %s\nNascimento: %s\nTrabalho: %s'):format(
            name,id,character and character.birthdate or 'Nao informado',job)}
end
local function driverMetadata(src,id,row)
    local character=exports.ob_core:GetCharacter(src)
    local list,classes=categories(id)
    local expiresAt=tonumber(row.driver_expires_at) or 0
    local days=math.max(0,math.ceil((expiresAt-os.time())/86400))
    local validity=expiresAt>os.time() and (('%s dia(s), ate %s'):format(days,os.date('%d/%m/%Y',expiresAt)))
        or (expiresAt>0 and ('VENCIDA em '..os.date('%d/%m/%Y',expiresAt)) or 'Nao emitida')
    local name=fullName(character)
    return {documentType='driver_license',userId=id,fullName=name,categories=list,
        categoryText=#classes>0 and table.concat(classes,', ') or 'Nenhuma',expiresAt=expiresAt,daysLeft=days,
        description=('Titular: %s\nRegistro: %s\nCategorias: %s\nValidade: %s'):format(
            name,id,#classes>0 and table.concat(classes,', ') or 'Nenhuma',validity)}
end
local function refresh(src,itemName,id,metadata)
    if not owned(src,itemName,id) then return false end
    return exports.ob_inventory:UpdateItemMetadata(src,itemName,metadata,{userId=id})==true
end
local function charge(src,amount,reason)
    if amount<=0 then return true,nil,nil end
    if GetResourceState('ob_economy')=='started' then
        local result=exports.ob_economy:ChargePlayer(src,amount,'document_fee',reason)
        if result and result.success then return true,nil,{receipt=result.receipt,amount=amount} end
        if not result or not result.fallback then return false,result and result.error or 'Pagamento indisponivel.' end
    end
    if GetResourceState('ob_bank')=='started' and exports.ob_bank:PayWithCard(src,amount,reason)==true then
        return true,nil,{method='bank',amount=amount}
    end
    if exports.ob_inventory:RemoveMoney(src,'money',amount)==true then return true,nil,{method='cash',amount=amount} end
    return false,'Saldo insuficiente no cartao ou dinheiro em maos.'
end
local function refund(src,payment)
    if not payment then return end
    if payment.receipt and GetResourceState('ob_economy')=='started' then
        exports.ob_economy:RefundCharge(src,payment.receipt,'Estorno de documento')
    elseif payment.method=='bank' and GetResourceState('ob_bank')=='started' then
        exports.ob_bank:RefundToBank(src,payment.amount,'Estorno de documento')
    elseif payment.method=='cash' then exports.ob_inventory:AddMoney(src,'money',payment.amount) end
end
local function status(src)
    local id=userId(src);if not id then return nil,'Personagem indisponivel.' end
    local row=rowFor(id)
    local identity=owned(src,OBDocuments.IdentityItem,id)
    if identity then refresh(src,OBDocuments.IdentityItem,id,identityMetadata(src,id)) end
    local list,_,_,driverAvailable=categories(id)
    local driver=owned(src,OBDocuments.DriverItem,id)
    if driver and driverAvailable then refresh(src,OBDocuments.DriverItem,id,driverMetadata(src,id,row)) end
    local expiresAt=tonumber(row.driver_expires_at) or 0
    return {
        identity={hasItem=identity~=nil,issued=(tonumber(row.identity_issued_at) or 0)>0,replacementFee=OBDocuments.ReplacementFee},
        driver={available=driverAvailable,eligible=driverAvailable and #list>0,hasItem=driver~=nil,issued=(tonumber(row.driver_issued_at) or 0)>0,
            expiresAt=expiresAt,expired=expiresAt>0 and expiresAt<=os.time(),daysLeft=math.max(0,math.ceil((expiresAt-os.time())/86400)),
            renewalFee=OBDocuments.RenewalFee,replacementFee=OBDocuments.ReplacementFee},
    }
end

local function issueIdentity(src)
    src=tonumber(src);local id=src and userId(src)
    if not ready or not id then return false,'Personagem indisponivel.' end
    local row=rowFor(id)
    if owned(src,OBDocuments.IdentityItem,id) then
        refresh(src,OBDocuments.IdentityItem,id,identityMetadata(src,id));return true,'Identidade atualizada.'
    end
    if (tonumber(row.identity_issued_at) or 0)>0 then return false,'Identidade ja emitida. Solicite uma segunda via.' end
    local metadata=identityMetadata(src,id)
    local canCarry,carryError=exports.ob_inventory:CanCarryItem(src,OBDocuments.IdentityItem,1,metadata)
    if not canCarry then return false,carryError end
    sql('query',[[INSERT INTO ob_license_documents (user_id,identity_issued_at) VALUES (?,?)
        ON DUPLICATE KEY UPDATE identity_issued_at=VALUES(identity_issued_at)]],{id,os.time()})
    local added,addError=exports.ob_inventory:AddItem(src,OBDocuments.IdentityItem,1,metadata)
    if not added then sql('update','UPDATE ob_license_documents SET identity_issued_at=0 WHERE user_id=?',{id});return false,addError end
    print(('[ob_documents] ISSUE user_id=%s type=identity'):format(id))
    return true,'Identidade emitida.'
end
local function replaceIdentity(src)
    src=tonumber(src);local id=src and userId(src)
    if not ready or not id then return false,'Personagem indisponivel.' end
    local row=rowFor(id)
    if (tonumber(row.identity_issued_at) or 0)<=0 then return false,'A identidade ainda nao foi emitida no local responsavel.' end
    if owned(src,OBDocuments.IdentityItem,id) then return false,'Sua identidade ja esta na mochila.' end
    local metadata=identityMetadata(src,id)
    local canCarry,carryError=exports.ob_inventory:CanCarryItem(src,OBDocuments.IdentityItem,1,metadata)
    if not canCarry then return false,carryError end
    local paid,payError,payment=charge(src,OBDocuments.ReplacementFee,'Segunda via da identidade')
    if not paid then return false,payError end
    local added,addError=exports.ob_inventory:AddItem(src,OBDocuments.IdentityItem,1,metadata)
    if not added then refund(src,payment);return false,addError end
    print(('[ob_documents] REPLACE user_id=%s type=identity fee=%s'):format(id,OBDocuments.ReplacementFee))
    return true,'Segunda via da identidade emitida.'
end
local function issueDriverAfterApproval(src)
    src=tonumber(src);local id=src and userId(src)
    if not ready or not id then return false,'Personagem indisponivel.' end
    if GetResourceState('ob_licenca')~='started' then return false,'Sistema de habilitacao nao instalado.' end
    local approved,_,_,licenseAvailable=categories(id)
    if not licenseAvailable then return false,'Integracao com o sistema de habilitacao indisponivel.' end
    if #approved==0 then return false,'Nenhuma categoria aprovada foi encontrada.' end
    local row=rowFor(id)
    if (tonumber(row.driver_expires_at) or 0)<=0 then
        row.driver_expires_at=os.time()+OBDocuments.DriverValidityDays*86400
        sql('query',[[INSERT INTO ob_license_documents (user_id,driver_expires_at) VALUES (?,?)
            ON DUPLICATE KEY UPDATE driver_expires_at=VALUES(driver_expires_at)]],{id,row.driver_expires_at})
    end
    local metadata=driverMetadata(src,id,row)
    if refresh(src,OBDocuments.DriverItem,id,metadata) then return true end
    if (tonumber(row.driver_issued_at) or 0)>0 then return false,'Sua CNH esta perdida. Solicite a segunda via.' end
    local added,addError=exports.ob_inventory:AddItem(src,OBDocuments.DriverItem,1,metadata)
    if not added then return false,addError end
    sql('update','UPDATE ob_license_documents SET driver_issued_at=? WHERE user_id=?',{os.time(),id})
    print(('[ob_documents] ISSUE user_id=%s type=driver expires_at=%s'):format(id,row.driver_expires_at))
    return true
end
local function processDriverDmv(src)
    src=tonumber(src);local id=src and userId(src)
    if not ready or not id then return false,'Personagem indisponivel.' end
    if GetResourceState('ob_licenca')~='started' then return false,'Sistema de habilitacao nao instalado.' end
    if locks[id] then return false,'Aguarde a operacao anterior.' end
    locks[id]=true
    local ok,result,message=pcall(function()
        local list,_,_,licenseAvailable=categories(id)
        if not licenseAvailable then return false,'Integracao com o sistema de habilitacao indisponivel.' end
        if #list==0 then return false,'Conclua ao menos uma categoria para receber a CNH.' end
        local row=rowFor(id);local existing=owned(src,OBDocuments.DriverItem,id)
        local previousIssued=tonumber(row.driver_issued_at) or 0
        local previousExpiry=tonumber(row.driver_expires_at) or 0
        local expired=previousExpiry<=os.time()
        if existing and previousIssued>0 and not expired then
            refresh(src,OBDocuments.DriverItem,id,driverMetadata(src,id,row));return true,'CNH atualizada.'
        end
        local fee=0
        if previousIssued>0 and expired then fee=fee+OBDocuments.RenewalFee end
        if previousIssued>0 and not existing then fee=fee+OBDocuments.ReplacementFee end
        local newExpiry=(previousIssued==0 or expired) and (os.time()+OBDocuments.DriverValidityDays*86400) or previousExpiry
        local metadata=driverMetadata(src,id,{driver_expires_at=newExpiry})
        if not existing then
            local canCarry,carryError=exports.ob_inventory:CanCarryItem(src,OBDocuments.DriverItem,1,metadata)
            if not canCarry then return false,carryError end
        end
        local paid,payError,payment=charge(src,fee,'Documento de motorista');if not paid then return false,payError end
        sql('query',[[INSERT INTO ob_license_documents (user_id,driver_expires_at) VALUES (?,?)
            ON DUPLICATE KEY UPDATE driver_expires_at=VALUES(driver_expires_at)]],{id,newExpiry})
        local delivered,deliveryError
        if existing then delivered,deliveryError=exports.ob_inventory:UpdateItemMetadata(src,OBDocuments.DriverItem,metadata,{userId=id})
        else delivered,deliveryError=exports.ob_inventory:AddItem(src,OBDocuments.DriverItem,1,metadata) end
        if not delivered then
            sql('update','UPDATE ob_license_documents SET driver_expires_at=?,driver_issued_at=? WHERE user_id=?',{previousExpiry,previousIssued,id})
            refund(src,payment);return false,deliveryError
        end
        local issuedAt=previousIssued>0 and previousIssued or os.time()
        sql('update','UPDATE ob_license_documents SET driver_issued_at=? WHERE user_id=?',{issuedAt,id})
        local action=expired and previousIssued>0 and (existing and 'renewal' or 'renewal_replacement') or previousIssued>0 and 'replacement' or 'issue'
        print(('[ob_documents] DOCUMENT user_id=%s type=driver action=%s fee=%s expires_at=%s'):format(id,action,fee,newExpiry))
        return true,action=='renewal_replacement' and 'CNH renovada e segunda via emitida.'
            or action=='renewal' and 'CNH renovada.' or action=='replacement' and 'Segunda via da CNH emitida.' or 'CNH emitida.'
    end)
    locks[id]=nil
    if not ok then print('[ob_documents] ProcessDriverDmv: '..tostring(result));return false,'Nao foi possivel processar o documento.' end
    return result,message
end
local function inspection(id,src)
    id,src=tonumber(id),tonumber(src)
    if not ready or not id or not src or userId(src)~=id then return nil,'Personagem indisponivel.' end
    local character=exports.ob_core:GetCharacter(src);if not character then return nil,'Personagem indisponivel.' end
    local row=rowFor(id);local expiresAt=tonumber(row.driver_expires_at) or 0
    local current=expiresAt>os.time();local list,_,stored,driverAvailable=categories(id);local result={}
    for _,name in ipairs(OBDocuments.CategoryOrder) do
        local definition,r=OBDocuments.Categories[name],stored[name]
        result[#result+1]={label=definition.label,class=definition.class,valid=current and r and yes(r.licensed) or false,issuedAt=r and tonumber(r.issued_at) or 0}
    end
    return {userId=id,name=fullName(character),birthdate=character.birthdate,nationality=character.nationality,
        job=legalJobLabel(src),identityIssued=(tonumber(row.identity_issued_at) or 0)>0,
        driverAvailable=driverAvailable,licenseExpiresAt=expiresAt,licenseExpired=expiresAt>0 and not current,categories=result}
end
local function hasLicense(id,category)
    id=tonumber(id);if not ready or not id or not OBDocuments.Categories[category] then return false end
    if GetResourceState('ob_licenca')~='started' then return false end
    local row=rowFor(id);if (tonumber(row.driver_expires_at) or 0)<=os.time() then return false end
    local stored=licenseRows(id);return stored[category]~=nil and yes(stored[category].licensed)
end

exports('GetStatus',status)
exports('IssueIdentity',issueIdentity)
exports('GiveInitialIdentity',issueIdentity)
exports('GiveInitialDocuments',issueIdentity)
exports('ReplaceIdentity',replaceIdentity)
exports('IssueDriverAfterApproval',issueDriverAfterApproval)
exports('ProcessDriverDmv',processDriverDmv)
exports('GetInspection',inspection)
exports('HasLicense',hasLicense)

CreateThread(function()
    while not ready do
        if OR.Database.waitForReady(10000) then
            local ok,err=pcall(sql,'query',[[CREATE TABLE IF NOT EXISTS ob_license_documents (
                user_id BIGINT UNSIGNED NOT NULL,identity_issued_at BIGINT NOT NULL DEFAULT 0,
                driver_issued_at BIGINT NOT NULL DEFAULT 0,driver_expires_at BIGINT NOT NULL DEFAULT 0,
                PRIMARY KEY (user_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
            ready=ok;if not ok then print('[ob_documents] Banco: '..tostring(err)) end
        end
        if not ready then Wait(5000) end
    end
    print('[ob_documents] Sistema de documentos pronto.')
end)

AddEventHandler('ob_core:server:jobChanged',function(src)
    src=tonumber(src);if not ready or not src or not GetPlayerName(src) then return end
    local id=userId(src)
    if id and owned(src,OBDocuments.IdentityItem,id) then refresh(src,OBDocuments.IdentityItem,id,identityMetadata(src,id)) end
end)
AddEventHandler('ob_core:server:playerLoaded',function(src)
    src=tonumber(src);if not ready or not src then return end
    local id=userId(src);if not id then return end
    if owned(src,OBDocuments.IdentityItem,id) then refresh(src,OBDocuments.IdentityItem,id,identityMetadata(src,id)) end
    local row=rowFor(id)
    if GetResourceState('ob_licenca')=='started' and owned(src,OBDocuments.DriverItem,id) then
        refresh(src,OBDocuments.DriverItem,id,driverMetadata(src,id,row))
    end
end)
