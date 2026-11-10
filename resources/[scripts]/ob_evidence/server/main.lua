local resource=GetCurrentResourceName()
local casings={}
local nextCasingId=0
local shotCooldowns={}
local actionCooldowns={}
local recentGunshots={}
local magnifierUsers={}
local databaseReady=false

local function validSource(value)
    value=tonumber(value)
    return value and value>0 and GetPlayerName(value) and value or nil
end

local function notify(src,message,kind)
    if validSource(src) then exports.ob_notification:Notify(src,message,kind or 'info') end
end

local function isPolice(src)
    src=validSource(src)
    return src and GetResourceState('ob_org')=='started'
        and exports.ob_org:HasPermission(src,OBEvidenceConfig.Permission or 'police',OBEvidenceConfig.RequireDuty~=false)==true
end

local function isRegisteredPoliceWeapon(metadata)
    metadata=type(metadata)=='table' and metadata or {}
    return metadata.serialRemoved~=true and metadata.serialStatus~='removed'
        and type(metadata.serial)=='string' and metadata.serial~=''
end

local function playerNear(src,coords,distance)
    local ped=GetPlayerPed(src)
    return ped and ped>0 and #(GetEntityCoords(ped)-vector3(coords.x+0.0,coords.y+0.0,coords.z+0.0))<=(distance or 3.0)
end

local function playersNear(first,second,distance)
    first,second=validSource(first),validSource(second)
    if not first or not second or first==second or GetPlayerRoutingBucket(first)~=GetPlayerRoutingBucket(second) then return false end
    local firstPed,secondPed=GetPlayerPed(first),GetPlayerPed(second)
    return firstPed>0 and secondPed>0 and #(GetEntityCoords(firstPed)-GetEntityCoords(secondPed))<=(distance or 2.5)
end

local function fingerprintCode(userId)
    local hash=joaat(('ob:%s'):format(tostring(userId or '')))
    if hash<0 then hash=hash+4294967296 end
    return ('FP-%08X'):format(hash)
end

local function findLab(labId)
    for _,lab in ipairs(OBEvidenceConfig.Labs or {}) do if lab.id==labId then return lab end end
end

local function firstItemSlot(src,itemName)
    local inventory=exports.ob_inventory:GetInventory(src)
    for slot,item in pairs(inventory and inventory.items or {}) do
        if item and item.name==itemName and (tonumber(item.amount) or 0)>0 then return tonumber(slot),item end
    end
end

local function publicCasing(entry)
    return {id=entry.id,coords=entry.coords,ammoType=entry.ammoType,expiresAt=entry.expiresAt}
end

local function casingSnapshot()
    local result={}
    for _,entry in pairs(casings) do result[#result+1]=publicCasing(entry) end
    table.sort(result,function(a,b)return a.id<b.id end)
    return result
end

local function removeCasing(id)
    if not casings[id] then return end
    casings[id]=nil
    TriggerClientEvent(resource..':client:removeCasing',-1,id)
end

local function trimCasings()
    local count,oldest=0,nil
    for id,entry in pairs(casings) do
        count=count+1
        if not oldest or entry.createdAt<oldest.createdAt then oldest={id=id,createdAt=entry.createdAt} end
    end
    if count>=math.max(25,tonumber(OBEvidenceConfig.MaximumCasings) or 250) and oldest then removeCasing(oldest.id) end
end

local function firstCasingSlot(src)
    local accepted={[OBEvidenceConfig.CasingItem or 'casing_evidence']=true}
    for _,itemName in pairs(OBEvidenceConfig.CasingItems or {}) do accepted[itemName]=true end
    local inventory=exports.ob_inventory:GetInventory(src)
    for slot,item in pairs(inventory and inventory.items or {}) do
        if item and accepted[item.name] and (tonumber(item.amount) or 0)>0 then return tonumber(slot),item end
    end
end

local function formatDate(timestamp)
    timestamp=tonumber(timestamp)
    return timestamp and timestamp>0 and os.date('%d/%m/%Y %H:%M:%S',timestamp) or 'nao informado'
end

local function buildCasingReport(sealed,archiveId,expiresAt,analyst)
    local weaponMetadata=type(sealed.weaponMetadata)=='table' and sealed.weaponMetadata or {}
    local fingerprint=type(weaponMetadata.lastFingerprint)=='table' and weaponMetadata.lastFingerprint or nil
    local lines={
        'Tipo: Cadastro de estojo balistico',
        ('Arquivo balistico: #%s'):format(archiveId),
        ('Calibre aparente: %s'):format((OBEvidenceConfig.AmmoLabels or {})[sealed.ammoType] or sealed.ammoType or 'desconhecido'),
        ('Disparo registrado em: %s'):format(formatDate(sealed.firedAt)),
        ('Digital parcial: %s'):format(fingerprint and fingerprint.code or 'nao identificada'),
        ('Registro valido ate: %s'):format(formatDate(expiresAt)),
        'Nenhuma arma foi vinculada. Examine uma arma suspeita para comparar a assinatura balistica.',
    }
    return {reportType='Cadastro de estojo',archiveId=archiveId,ammoType=sealed.ammoType,fingerprintCode=fingerprint and fingerprint.code,
        firedAt=sealed.firedAt,archiveExpiresAt=expiresAt,analyzedAt=os.time(),analyzedBy=analyst,description=table.concat(lines,'\n')}
end

local function buildWeaponReport(evidence,registry,matches,analyst,fingerprintIdentity)
    local metadata=type(evidence.metadata)=='table' and evidence.metadata or {}
    local fingerprint=type(metadata.lastFingerprint)=='table' and metadata.lastFingerprint or nil
    local serial=metadata.serialRemoved==true and 'NUMERACAO RASPADA' or tostring(metadata.serial or 'SEM REGISTRO')
    local lines={
        'Tipo: Exame de arma',
        ('Arma: %s'):format(evidence.label or evidence.itemName or 'Desconhecida'),
        ('Calibre: %s'):format((OBEvidenceConfig.AmmoLabels or {})[evidence.ammoType] or evidence.ammoType or 'desconhecido'),
        ('Serial: %s'):format(serial),
    }
    if registry then lines[#lines+1]=('Registro: %s (ID %s), adquirido em %s, loja %s'):format(
        registry.purchaser_name or 'Desconhecido',registry.purchaser_user_id or '?',formatDate(registry.purchased_at),registry.shop_id or '?') end
    if fingerprint then
        if fingerprintIdentity then
            lines[#lines+1]=('Digital cadastrada: %s (ID %s), codigo %s, vestigio em %s'):format(
                fingerprintIdentity.person_name or 'Desconhecido',fingerprintIdentity.user_id or '?',fingerprint.code or '?',formatDate(fingerprint.at))
        else
            lines[#lines+1]=('Digital nao cadastrada: codigo %s, vestigio em %s'):format(
                fingerprint.code or '?',formatDate(fingerprint.at))
        end
    else lines[#lines+1]='Ultima digital na arma: nao identificada' end
    lines[#lines+1]=('Correspondencias balisticas ativas: %s'):format(#matches)
    for index,match in ipairs(matches) do
        lines[#lines+1]=('#%s - disparo em %s - arquivado em %s'):format(match.id,formatDate(match.fired_at),formatDate(match.created_at))
        if index>=10 then lines[#lines+1]='Outras correspondencias permanecem no arquivo digital.' break end
    end
    return {
        reportType='Exame de arma',itemName=evidence.itemName,weaponLabel=evidence.label,ammoType=evidence.ammoType,
        serial=metadata.serial,serialRemoved=metadata.serialRemoved==true,registry=registry,
        lastFingerprint=fingerprint and {code=fingerprint.code,at=fingerprint.at} or nil,
        fingerprintIdentity=fingerprintIdentity,
        ballisticMatches=matches,analyzedAt=os.time(),analyzedBy=analyst,description=table.concat(lines,'\n'),
    }
end

local function recordFingerprintTrace(code,traceType,referenceId,details,expiresAt)
    if not databaseReady or type(code)~='string' or code=='' then return end
    OR.Database.update.await([[INSERT INTO ob_fingerprint_traces
        (fingerprint_code,trace_type,reference_id,details,recorded_at,expires_at)
        VALUES (?,?,?,?,NOW(),FROM_UNIXTIME(?))
        ON DUPLICATE KEY UPDATE details=VALUES(details),recorded_at=NOW(),expires_at=VALUES(expires_at)]],{
        code,traceType or 'unknown',tostring(referenceId or ''),json.encode(details or {}),tonumber(expiresAt) or os.time()+345600,
    })
end

local function fingerprintIdentity(code)
    if not databaseReady or type(code)~='string' or code=='' then return nil end
    return OR.Database.single.await([[SELECT fingerprint_code,user_id,person_name,UNIX_TIMESTAMP(registered_at) AS registered_at
        FROM ob_fingerprint_registry WHERE fingerprint_code=?]],{code})
end

local function fingerprintTraces(code)
    if not databaseReady or type(code)~='string' or code=='' then return {} end
    return OR.Database.query.await([[SELECT trace_type,reference_id,details,UNIX_TIMESTAMP(recorded_at) AS recorded_at,
        UNIX_TIMESTAMP(expires_at) AS expires_at FROM ob_fingerprint_traces
        WHERE fingerprint_code=? AND expires_at>NOW() ORDER BY recorded_at DESC LIMIT 25]],{code}) or {}
end

local function buildFieldReport(kind,target,result,analyst)
    local title=kind=='residue' and 'Teste residual de disparo' or 'Teste quimico'
    local lines={('Tipo: %s'):format(title),('Pessoa examinada: %s (ID %s)'):format(target.name,target.userId),
        ('Resultado: %s'):format(result.message),('Coletado em: %s'):format(formatDate(os.time())),
        ('Responsavel: %s (ID %s)'):format(analyst.name,analyst.userId)}
    return {reportType=title,testKind=kind,subject=target,result=result,analyzedAt=os.time(),analyzedBy=analyst,
        description=table.concat(lines,'\n')}
end

local function buildFingerprintReport(sample,traces,analyst)
    local lines={'Tipo: Cadastro e confronto de digital',
        ('Pessoa cadastrada: %s (ID %s)'):format(sample.personName or 'Desconhecida',sample.personUserId or '?'),
        ('Codigo datiloscopico: %s'):format(sample.fingerprintCode or '?'),
        ('Ocorrencias periciais ativas: %s'):format(#traces)}
    for index,trace in ipairs(traces) do
        local label=trace.trace_type=='weapon' and 'arma examinada' or trace.trace_type=='casing' and 'estojo arquivado' or trace.trace_type
        lines[#lines+1]=('%s - %s (%s)'):format(formatDate(trace.recorded_at),label,trace.reference_id or 'sem referencia')
        if index>=10 then lines[#lines+1]='Outras ocorrencias permanecem no arquivo digital.' break end
    end
    if #traces==0 then lines[#lines+1]='Nenhum vestigio anterior foi localizado no periodo de retencao.' end
    return {reportType='Confronto de digital',fingerprintCode=sample.fingerprintCode,subjectUserId=sample.personUserId,
        subjectName=sample.personName,traces=traces,analyzedAt=os.time(),analyzedBy=analyst,description=table.concat(lines,'\n')}
end

local function archiveCasing(sealed,analyst)
    if not databaseReady then return nil,nil,'Arquivo balistico indisponivel.' end
    local weaponMetadata=type(sealed.weaponMetadata)=='table' and sealed.weaponMetadata or {}
    local fingerprint=type(weaponMetadata.lastFingerprint)=='table' and weaponMetadata.lastFingerprint or nil
    local expiresAt=os.time()+(math.max(1,tonumber(OBEvidenceConfig.ArchiveRetentionDays) or 4)*86400)
    local archiveData={evidenceId=sealed.evidenceId,ammoType=sealed.ammoType,firedAt=sealed.firedAt,
        collectedAt=sealed.collectedAt,collectedBy=sealed.collectedBy}
    local archiveId,errorMessage=OR.Database.insert.await([[INSERT INTO ob_ballistic_archive
        (ballistic_signature,ammo_type,weapon_item,fingerprint_code,evidence_data,analyzed_by,created_at,expires_at)
        VALUES (?,?,?,?,?,?,NOW(),FROM_UNIXTIME(?))]],{
        weaponMetadata.ballisticSignature or '',sealed.ammoType or '',sealed.itemName or '',fingerprint and fingerprint.code or '',
        json.encode(archiveData),tostring(analyst.userId or ''),expiresAt,
    })
    if archiveId==nil then return nil,nil,errorMessage end
    if fingerprint and fingerprint.code then
        recordFingerprintTrace(fingerprint.code,'casing',archiveId,{ammoType=sealed.ammoType,firedAt=sealed.firedAt},expiresAt)
    end
    return tonumber(archiveId),expiresAt
end

local function findBallisticMatches(signature)
    if not databaseReady or type(signature)~='string' or signature=='' then return {} end
    local rows=OR.Database.query.await([[SELECT id,ammo_type,fingerprint_code,evidence_data,
        UNIX_TIMESTAMP(created_at) AS created_at,UNIX_TIMESTAMP(expires_at) AS expires_at
        FROM ob_ballistic_archive WHERE ballistic_signature=? AND expires_at>NOW()
        ORDER BY created_at DESC LIMIT 25]],{signature}) or {}
    for _,row in ipairs(rows) do
        local decoded={}
        if type(row.evidence_data)=='string' and row.evidence_data~='' then
            local ok,value=pcall(json.decode,row.evidence_data)
            if ok and type(value)=='table' then decoded=value end
        end
        row.fired_at=tonumber(decoded.firedAt)
        row.evidence_data=nil
    end
    return rows
end

local function saveReport(src,report)
    local added,addError=exports.ob_inventory:AddItem(src,OBEvidenceConfig.ReportItem or 'forensic_report',1,report)
    if not added then return false,addError end
    if OR.Database and OR.Database.insert then
        OR.Database.insert.await([[INSERT INTO ob_forensic_reports
            (analyst_user_id,report_type,weapon_item,serial,report_data,created_at) VALUES (?,?,?,?,?,NOW())]],{
            tostring(report.analyzedBy and report.analyzedBy.userId or ''),report.reportType or '',report.itemName or '',
            report.serial or '',json.encode(report),
        })
    end
    return true
end

local function recordChemicalTrace(src,itemName,traceKind,origin)
    src=validSource(src)
    local userId=src and exports.ob_core:GetUserId(src)
    if not userId or not databaseReady then return false,'Arquivo quimico indisponivel.' end
    local settings=OBEvidenceConfig.FieldKits and OBEvidenceConfig.FieldKits.chemical_test_kit or {}
    local duration=traceKind=='use' and (settings.useSeconds or 7200) or (settings.contactSeconds or 3600)
    local label=(OBEvidenceConfig.DrugLabels or {})[itemName] or tostring(itemName or 'substancia desconhecida')
    local inserted,errorMessage=OR.Database.insert.await([[INSERT INTO ob_chemical_traces
        (user_id,trace_kind,substance,origin,detected_at,expires_at) VALUES (?,?,?,?,NOW(),FROM_UNIXTIME(?))]],{
        tostring(userId),traceKind or 'contact',label,tostring(origin or ''),os.time()+duration,
    })
    return inserted~=nil,errorMessage
end

exports('MarkDrugContact',function(src,itemName,origin)
    return recordChemicalTrace(src,itemName,'contact',origin)
end)

exports('MarkDrugUse',function(src,itemName,origin)
    return recordChemicalTrace(src,itemName,'use',origin)
end)

exports('UseFieldKit',function(src,itemName,slot)
    src=validSource(src)
    local kit=OBEvidenceConfig.FieldKits and OBEvidenceConfig.FieldKits[itemName]
    if not src or not isPolice(src) then return false,'Apenas policiais em servico podem usar este kit.' end
    if not kit or not tonumber(slot) then return false,'Kit pericial invalido.' end
    TriggerClientEvent(resource..':client:useFieldKit',src,itemName,math.floor(tonumber(slot)),kit.label)
    return true,'Aproxime-se da pessoa que sera examinada.'
end)

OR.Callback.register('evidenceLabData',function(src,labId)
    src=validSource(src)
    local lab=findLab(labId)
    if not src or not isPolice(src) then return nil,'Acesso restrito a policiais em servico.' end
    if not lab or not playerNear(src,lab.coords,(OBEvidenceConfig.AnalysisDistance or 2.5)+0.8) then return nil,'Aproxime-se da bancada de pericia.' end
    local accepted={[OBEvidenceConfig.CasingItem or 'casing_evidence']=true}
    for _,itemName in pairs(OBEvidenceConfig.CasingItems or {}) do accepted[itemName]=true end
    local casingCount,fingerprintCount,forensicKitCount=0,0,0
    local weapons={}
    local inventory=exports.ob_inventory:GetInventory(src)
    for _,item in pairs(inventory and inventory.items or {}) do
        if item then
            if accepted[item.name] then casingCount=casingCount+(tonumber(item.amount) or 0) end
            if item.name==(OBEvidenceConfig.FingerprintSampleItem or 'fingerprint_sample') then
                fingerprintCount=fingerprintCount+(tonumber(item.amount) or 0)
            end
            if item.name==(OBEvidenceConfig.ForensicKitItem or 'forensic_kit') then
                forensicKitCount=forensicKitCount+(tonumber(item.amount) or 0)
            end
            if item.type=='weapon' and not isRegisteredPoliceWeapon(item.metadata) then
                local metadata=type(item.metadata)=='table' and item.metadata or {}
                weapons[#weapons+1]={slot=tonumber(item.slot),itemName=item.name,label=item.label or item.name,
                    ammoType=(exports.ob_inventory:InspectWeaponAtSlot(src,item.slot,item.name) or {}).ammoType,
                    serial=metadata.serialRemoved==true and 'NUMERACAO RASPADA' or tostring(metadata.serial or 'SEM REGISTRO'),
                    registered=metadata.serialRemoved~=true and type(metadata.serial)=='string' and metadata.serial~=''}
            end
        end
    end
    table.sort(weapons,function(a,b)return (a.slot or 0)<(b.slot or 0) end)
    local archive,registrations,reports={},{},{}
    if databaseReady then
        archive=OR.Database.query.await([[SELECT id,ammo_type,UNIX_TIMESTAMP(created_at) AS created_at,
            UNIX_TIMESTAMP(expires_at) AS expires_at FROM ob_ballistic_archive
            WHERE expires_at>NOW() ORDER BY created_at DESC LIMIT 50]]) or {}
        registrations=OR.Database.query.await([[SELECT fingerprint_code,user_id,person_name,registered_by,
            UNIX_TIMESTAMP(registered_at) AS registered_at FROM ob_fingerprint_registry
            ORDER BY registered_at DESC LIMIT 50]]) or {}
        local rows=OR.Database.query.await([[SELECT id,report_type,weapon_item,serial,report_data,
            UNIX_TIMESTAMP(created_at) AS created_at FROM ob_forensic_reports ORDER BY id DESC LIMIT 60]]) or {}
        for _,row in ipairs(rows) do
            local decoded={}
            if type(row.report_data)=='string' and row.report_data~='' then
                local ok,value=pcall(json.decode,row.report_data)
                if ok and type(value)=='table' then decoded=value end
            end
            reports[#reports+1]={id=row.id,reportType=row.report_type,weaponItem=row.weapon_item,serial=row.serial,
                createdAt=row.created_at,description=tostring(decoded.description or ''),analyzedBy=decoded.analyzedBy,
                archiveId=decoded.archiveId,fingerprintCode=decoded.fingerprintCode}
        end
    end
    return {labId=labId,label=lab.label or 'Laboratorio pericial',databaseReady=databaseReady,
        casingCount=casingCount,fingerprintCount=fingerprintCount,forensicKitCount=forensicKitCount,
        weapons=weapons,archive=archive,registrations=registrations,reports=reports,
        retentionDays=math.max(1,tonumber(OBEvidenceConfig.ArchiveRetentionDays) or 4)}
end,{rateLimit={limit=8,window=10000}})

RegisterNetEvent(resource..':server:requestSnapshot',function()
    local src=tonumber(source)
    TriggerClientEvent(resource..':client:snapshot',src,casingSnapshot())
end)

RegisterNetEvent(resource..':server:disableMagnifier',function()
    magnifierUsers[tonumber(source)]=nil
end)

RegisterNetEvent(resource..':server:shot',function(slot,itemName,coords)
    local src=validSource(source)
    if not src or type(coords)~='table' or not playerNear(src,coords,4.0) then return end
    local now=GetGameTimer()
    if (shotCooldowns[src] or 0)>now then return end
    shotCooldowns[src]=now+math.max(80,tonumber(OBEvidenceConfig.ShotCooldownMs) or 100)
    local evidence=exports.ob_inventory:MarkWeaponUsed(src,slot,itemName)
    if not evidence or evidence.ammoType=='melee' then return end
    local shooterUserId=exports.ob_core:GetUserId(src)
    if shooterUserId then recentGunshots[tostring(shooterUserId)]={at=os.time(),ammoType=evidence.ammoType} end
    if isRegisteredPoliceWeapon(evidence.metadata) then return end
    trimCasings();nextCasingId=nextCasingId+1
    local created=os.time()
    local entry={id=nextCasingId,coords={x=coords.x+0.0,y=coords.y+0.0,z=coords.z+0.0},createdAt=created,
        expiresAt=created+(tonumber(OBEvidenceConfig.CasingLifetimeSeconds) or 2700),itemName=evidence.itemName,
        label=evidence.label,ammoType=evidence.ammoType,metadata=evidence.metadata,firedAt=created}
    casings[entry.id]=entry
    TriggerClientEvent(resource..':client:addCasing',-1,publicCasing(entry))
end)

RegisterNetEvent(resource..':server:useFieldKit',function(itemName,slot,targetSource)
    local src=validSource(source)
    targetSource=validSource(targetSource)
    slot=math.floor(tonumber(slot) or 0)
    local kit=OBEvidenceConfig.FieldKits and OBEvidenceConfig.FieldKits[itemName]
    if not src or not isPolice(src) then return notify(src,'Apenas policiais em servico podem realizar o teste.','error') end
    local now=GetGameTimer();if (actionCooldowns[src] or 0)>now then return end;actionCooldowns[src]=now+2000
    if not kit or slot<1 or not targetSource or not playersNear(src,targetSource,2.6) then
        return notify(src,'A pessoa se afastou ou o kit e invalido.','error')
    end
    local targetUserId=exports.ob_core:GetUserId(targetSource)
    if not targetUserId then return notify(src,'Personagem examinado indisponivel.','error') end
    local target={userId=targetUserId,name=exports.ob_core:GetFullName(targetSource) or GetPlayerName(targetSource)}
    local analyst={userId=exports.ob_core:GetUserId(src),name=exports.ob_core:GetFullName(src) or GetPlayerName(src)}
    local consumed,consumeError=exports.ob_inventory:ConsumeItemAtSlot(src,slot,itemName,1)
    if not consumed then return notify(src,consumeError or 'O kit foi movido.','error') end

    if kit.kind=='fingerprint' then
        local code=fingerprintCode(targetUserId)
        local sample={fingerprintCode=code,personUserId=targetUserId,personName=target.name,collectedAt=os.time(),collectedBy=analyst,
            description=('Amostra lacrada %s | aguardando cadastro no laboratorio'):format(code)}
        local added,addError=exports.ob_inventory:AddItem(src,OBEvidenceConfig.FingerprintSampleItem or 'fingerprint_sample',1,sample)
        if not added then exports.ob_inventory:AddItem(src,itemName,1);return notify(src,addError or 'Sem espaco para lacrar a amostra.','error') end
        notify(src,'Digital coletada e lacrada. Leve a amostra ao laboratorio.','success')
        return TriggerClientEvent(resource..':client:refreshLab',src)
    end

    local result
    if kit.kind=='residue' then
        local trace=recentGunshots[tostring(targetUserId)]
        local positive=trace and os.time()-(tonumber(trace.at) or 0)<=(kit.retentionSeconds or 2700)
        result={positive=positive,detectedAt=positive and trace.at or nil,ammoType=positive and trace.ammoType or nil,
            message=positive and ('POSITIVO para residuos recentes de disparo (%s).'):format(
                (OBEvidenceConfig.AmmoLabels or {})[trace.ammoType] or trace.ammoType or 'calibre nao determinado')
                or 'NEGATIVO para residuos recentes de disparo.'}
    elseif kit.kind=='chemical' then
        local row=databaseReady and OR.Database.single.await([[SELECT trace_kind,substance,origin,
            UNIX_TIMESTAMP(detected_at) AS detected_at FROM ob_chemical_traces
            WHERE user_id=? AND expires_at>NOW() ORDER BY detected_at DESC LIMIT 1]],{tostring(targetUserId)}) or nil
        if row and row.trace_kind=='use' then
            result={positive=true,traceKind='use',substance=row.substance,detectedAt=row.detected_at,
                message=('POSITIVO para consumo recente de %s.'):format(row.substance or 'substancia ilicita')}
        elseif row then
            result={positive=true,traceKind='contact',substance=row.substance,detectedAt=row.detected_at,
                message=('POSITIVO para contato/manuseio recente de %s; o teste nao comprova consumo.'):format(row.substance or 'substancia ilicita')}
        else
            result={positive=false,message='NEGATIVO para residuos quimicos recentes cadastrados.'}
        end
    else
        exports.ob_inventory:AddItem(src,itemName,1)
        return notify(src,'Tipo de teste invalido.','error')
    end
    local report=buildFieldReport(kit.kind,target,result,analyst)
    local saved,saveError=saveReport(src,report)
    if not saved then exports.ob_inventory:AddItem(src,itemName,1);return notify(src,saveError or 'Sem espaco para o laudo.','error') end
    notify(src,result.message,result.positive and 'warning' or 'success')
end)

RegisterNetEvent(resource..':server:collectCasing',function(id)
    local src=validSource(source);id=math.floor(tonumber(id) or 0)
    local entry=casings[id]
    if not src or not isPolice(src) then return notify(src,'Apenas policiais em servico podem recolher evidencias.','error') end
    if not magnifierUsers[src] then return notify(src,'Equipe a lupa pericial para iniciar a busca.','error') end
    if (exports.ob_inventory:GetItemCount(src,'forensic_magnifier') or 0)<1 then return notify(src,'Equipe a lupa pericial para localizar os vestigios.','error') end
    if not entry or entry.collecting or not playerNear(src,entry.coords,(OBEvidenceConfig.CollectDistance or 1.35)+0.8) then return notify(src,'Esse estojo nao esta mais aqui.','error') end
    local origin=vector3(entry.coords.x+0.0,entry.coords.y+0.0,entry.coords.z+0.0)
    local radius=math.max(0.5,tonumber(OBEvidenceConfig.BulkCollectRadius) or 2.0)
    local maximum=math.max(1,math.floor(tonumber(OBEvidenceConfig.BulkCollectMaximum) or 12))
    local nearby={{id=id,entry=entry}}
    entry.collecting=true
    for casingId,candidate in pairs(casings) do
        if #nearby>=maximum then break end
        if casingId~=id and not candidate.collecting and candidate.ammoType==entry.ammoType then
            local position=vector3(candidate.coords.x+0.0,candidate.coords.y+0.0,candidate.coords.z+0.0)
            if #(position-origin)<=radius then nearby[#nearby+1]={id=casingId,entry=candidate};candidate.collecting=true end
        end
    end
    table.sort(nearby,function(a,b)return a.id<b.id end)
    if #nearby==0 then return notify(src,'Nenhum estojo compativel foi encontrado nessa area.','error') end
    local bag=OBEvidenceConfig.EvidenceBagItem or 'empty_evidence_bag'
    local bagCount=exports.ob_inventory:GetItemCount(src,bag) or 0
    if bagCount<#nearby then
        for _,candidate in ipairs(nearby) do candidate.entry.collecting=nil end
        return notify(src,('Voce precisa de %s saco(s) vazio(s) para lacrar todos os estojos proximos.'):format(#nearby),'error')
    end
    local casingItem=(OBEvidenceConfig.CasingItems or {})[entry.ammoType] or OBEvidenceConfig.CasingItem or 'casing_evidence'
    local canCarry,carryError=exports.ob_inventory:CanCarryItem(src,casingItem,#nearby,{})
    if not canCarry then
        for _,candidate in ipairs(nearby) do candidate.entry.collecting=nil end
        return notify(src,carryError or 'Sem espaco para guardar os estojos.','error')
    end
    local removed,removeError=exports.ob_inventory:RemoveItem(src,bag,#nearby)
    if not removed then
        for _,candidate in ipairs(nearby) do candidate.entry.collecting=nil end
        return notify(src,removeError or 'Nao foi possivel separar os sacos de evidencia.','error')
    end
    local collector={userId=exports.ob_core:GetUserId(src),name=exports.ob_core:GetFullName(src) or GetPlayerName(src)}
    local collected,lastError=0
    for _,candidate in ipairs(nearby) do
        local casing=candidate.entry
        local sourceMetadata=type(casing.metadata)=='table' and casing.metadata or {}
        local lastFingerprint=type(sourceMetadata.lastFingerprint)=='table' and sourceMetadata.lastFingerprint or nil
        local sealedWeaponData={ballisticSignature=sourceMetadata.ballisticSignature}
        if lastFingerprint then sealedWeaponData.lastFingerprint={code=lastFingerprint.code,at=lastFingerprint.at} end
        local caliber=(OBEvidenceConfig.AmmoLabels or {})[casing.ammoType] or casing.ammoType or 'calibre desconhecido'
        local metadata={evidenceId=candidate.id,ammoType=casing.ammoType,weaponMetadata=sealedWeaponData,
            firedAt=casing.firedAt,collectedAt=os.time(),collectedBy=collector,
            description=('Estojo lacrado #%s | %s | coletado por %s'):format(candidate.id,caliber,collector.name)}
        local added,addError=exports.ob_inventory:AddItem(src,casingItem,1,metadata)
        if added then collected=collected+1;removeCasing(candidate.id)
        else casing.collecting=nil;lastError=addError end
    end
    local unused=#nearby-collected
    if unused>0 then exports.ob_inventory:AddItem(src,bag,unused) end
    if collected==0 then return notify(src,lastError or 'Nao foi possivel guardar os estojos.','error') end
    notify(src,('%s estojo(s) do mesmo calibre foram recolhidos e lacrados.'):format(collected),'success')
end)

RegisterNetEvent(resource..':server:analyzeCasing',function(labId)
    local src=validSource(source)
    if not src or not isPolice(src) then return notify(src,'Acesso restrito a policiais em servico.','error') end
    local now=GetGameTimer();if (actionCooldowns[src] or 0)>now then return end;actionCooldowns[src]=now+2000
    local lab
    for _,candidate in ipairs(OBEvidenceConfig.Labs or {}) do if candidate.id==labId then lab=candidate break end end
    if not lab or not playerNear(src,lab.coords,(OBEvidenceConfig.AnalysisDistance or 2.5)+0.8) then return notify(src,'Aproxime-se da bancada de pericia.','error') end
    local slot,item=firstCasingSlot(src)
    if not slot then return notify(src,'Voce nao possui um estojo lacrado para analisar.','error') end
    if not databaseReady then return notify(src,'O arquivo balistico esta indisponivel no momento.','error') end
    local sealed=type(item.metadata)=='table' and item.metadata or {}
    local analyst={userId=exports.ob_core:GetUserId(src),name=exports.ob_core:GetFullName(src) or GetPlayerName(src)}
    local consumed,consumeError=exports.ob_inventory:ConsumeItemAtSlot(src,slot,item.name,1)
    if not consumed then return notify(src,consumeError or 'A evidencia foi movida.','error') end
    local archiveId,expiresAt,archiveError=archiveCasing(sealed,analyst)
    if not archiveId then
        exports.ob_inventory:AddItem(src,item.name,1,sealed)
        return notify(src,archiveError or 'Nao foi possivel cadastrar o estojo no arquivo balistico.','error')
    end
    local report=buildCasingReport(sealed,archiveId,expiresAt,analyst)
    local saved,saveError=saveReport(src,report)
    if not saved then
        OR.Database.update.await('DELETE FROM ob_ballistic_archive WHERE id=?',{archiveId})
        OR.Database.update.await("DELETE FROM ob_fingerprint_traces WHERE trace_type='casing' AND reference_id=?",{tostring(archiveId)})
        exports.ob_inventory:AddItem(src,item.name,1,sealed)
        return notify(src,saveError or 'Sem espaco para o comprovante pericial.','error')
    end
    notify(src,('Estojo arquivado por %s dias. O comprovante foi colocado na mochila.'):format(
        math.max(1,tonumber(OBEvidenceConfig.ArchiveRetentionDays) or 4)),'success')
    TriggerClientEvent(resource..':client:refreshLab',src)
end)

RegisterNetEvent(resource..':server:analyzeFingerprint',function(labId)
    local src=validSource(source)
    if not src or not isPolice(src) then return notify(src,'Acesso restrito a policiais em servico.','error') end
    local now=GetGameTimer();if (actionCooldowns[src] or 0)>now then return end;actionCooldowns[src]=now+2000
    local lab=findLab(labId)
    if not lab or not playerNear(src,lab.coords,(OBEvidenceConfig.AnalysisDistance or 2.5)+0.8) then
        return notify(src,'Aproxime-se da bancada de pericia.','error')
    end
    if not databaseReady then return notify(src,'O arquivo datiloscopico esta indisponivel.','error') end
    local itemName=OBEvidenceConfig.FingerprintSampleItem or 'fingerprint_sample'
    local slot,item=firstItemSlot(src,itemName)
    if not slot then return notify(src,'Voce nao possui uma amostra de digital para analisar.','error') end
    local sample=type(item.metadata)=='table' and item.metadata or {}
    if type(sample.fingerprintCode)~='string' or not sample.personUserId then return notify(src,'A amostra esta danificada ou incompleta.','error') end
    local analyst={userId=exports.ob_core:GetUserId(src),name=exports.ob_core:GetFullName(src) or GetPlayerName(src)}
    local consumed,consumeError=exports.ob_inventory:ConsumeItemAtSlot(src,slot,itemName,1)
    if not consumed then return notify(src,consumeError or 'A amostra foi movida.','error') end
    local registered,registerError=OR.Database.update.await([[INSERT INTO ob_fingerprint_registry
        (fingerprint_code,user_id,person_name,registered_by,registered_at) VALUES (?,?,?,?,NOW())
        ON DUPLICATE KEY UPDATE user_id=VALUES(user_id),person_name=VALUES(person_name),
        registered_by=VALUES(registered_by),registered_at=NOW()]],{
        sample.fingerprintCode,tostring(sample.personUserId),tostring(sample.personName or 'Desconhecida'),tostring(analyst.userId or ''),
    })
    if registered==nil then
        exports.ob_inventory:AddItem(src,itemName,1,sample)
        return notify(src,registerError or 'Nao foi possivel cadastrar a digital.','error')
    end
    local traces=fingerprintTraces(sample.fingerprintCode)
    local report=buildFingerprintReport(sample,traces,analyst)
    local saved,saveError=saveReport(src,report)
    if not saved then exports.ob_inventory:AddItem(src,itemName,1,sample);return notify(src,saveError or 'Sem espaco para o laudo.','error') end
    notify(src,('Digital cadastrada. %s ocorrencia(s) pericial(is) ativa(s) localizada(s).'):format(#traces),'success')
    TriggerClientEvent(resource..':client:refreshLab',src)
end)

RegisterNetEvent(resource..':server:scanWeapon',function(slot,itemName,labId)
    local src=validSource(source)
    if not src or not isPolice(src) then return notify(src,'Acesso restrito a policiais em servico.','error') end
    local now=GetGameTimer();if (actionCooldowns[src] or 0)>now then return end;actionCooldowns[src]=now+2000
    local lab=findLab(labId)
    if not lab or not playerNear(src,lab.coords,(OBEvidenceConfig.AnalysisDistance or 2.5)+0.8) then
        return notify(src,'A arma deve ser examinada no computador do laboratorio.','error')
    end
    if (exports.ob_inventory:GetItemCount(src,OBEvidenceConfig.ForensicKitItem or 'forensic_kit') or 0)<1 then return notify(src,'Voce nao possui um kit de pericia.','error') end
    local evidence,errorMessage=exports.ob_inventory:InspectWeaponAtSlot(src,slot,itemName)
    if not evidence then return notify(src,errorMessage or 'Arma invalida.','error') end
    local metadata=evidence.metadata or {}
    if isRegisteredPoliceWeapon(metadata) then
        return notify(src,'Armas policiais registradas nao podem ser submetidas a este confronto.','error')
    end
    local registry=metadata.serial and exports.ob_inventory:LookupWeaponSerial(metadata.serial) or nil
    local analyst={userId=exports.ob_core:GetUserId(src),name=exports.ob_core:GetFullName(src) or GetPlayerName(src)}
    local matches=findBallisticMatches(metadata.ballisticSignature)
    local fingerprint=type(metadata.lastFingerprint)=='table' and metadata.lastFingerprint or nil
    local identity=fingerprint and fingerprintIdentity(fingerprint.code) or nil
    local report=buildWeaponReport(evidence,registry,matches,analyst,identity)
    local saved,saveError=saveReport(src,report)
    if not saved then return notify(src,saveError or 'Sem espaco para o laudo.','error') end
    if fingerprint and fingerprint.code then
        local reference=metadata.serial or metadata.ballisticSignature or ('slot-%s'):format(tostring(slot))
        recordFingerprintTrace(fingerprint.code,'weapon',reference,{itemName=evidence.itemName,serial=metadata.serial or '',
            serialRemoved=metadata.serialRemoved==true},os.time()+(math.max(1,tonumber(OBEvidenceConfig.ArchiveRetentionDays) or 4)*86400))
    end
    if #matches>0 then
        notify(src,('Arma examinada: %s correspondencia(s) no arquivo balistico.'):format(#matches),'success')
    else
        notify(src,'Arma examinada. Nenhuma correspondencia balistica ativa foi encontrada.','success')
    end
    TriggerClientEvent(resource..':client:refreshLab',src)
end)

exports('UseForensicKit',function(src)
    src=validSource(src)
    if not src or not isPolice(src) then return false,'Apenas policiais em servico podem usar o kit.' end
    if (exports.ob_inventory:GetItemCount(src,OBEvidenceConfig.ForensicKitItem or 'forensic_kit') or 0)<1 then return false,'Kit de pericia nao encontrado.' end
    return true,'Use o computador do laboratorio para selecionar a arma guardada no inventario.'
end)

exports('ToggleMagnifier',function(src)
    src=validSource(src)
    if not src or not isPolice(src) then return false,'Apenas policiais em servico podem usar a lupa pericial.' end
    if (exports.ob_inventory:GetItemCount(src,'forensic_magnifier') or 0)<1 then return false,'Lupa pericial nao encontrada.' end
    magnifierUsers[src]=not magnifierUsers[src]
    TriggerClientEvent(resource..':client:toggleMagnifier',src,magnifierUsers[src])
    return true,'Modo de busca pericial alternado.'
end)

CreateThread(function()
    if OR.Database.waitForReady(30000) then
        databaseReady=true
        local schemas={
            {name='historico de laudos',sql=[[CREATE TABLE IF NOT EXISTS ob_forensic_reports (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,analyst_user_id VARCHAR(64) NOT NULL,
                report_type VARCHAR(40) NOT NULL,weapon_item VARCHAR(64) NULL,serial VARCHAR(64) NULL,
                report_data LONGTEXT NOT NULL,created_at DATETIME NOT NULL,
                KEY idx_ob_forensic_serial (serial),KEY idx_ob_forensic_analyst (analyst_user_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]},
            {name='arquivo balistico',sql=[[CREATE TABLE IF NOT EXISTS ob_ballistic_archive (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
                ballistic_signature VARCHAR(96) NULL,ammo_type VARCHAR(32) NULL,weapon_item VARCHAR(64) NULL,
                fingerprint_code VARCHAR(64) NULL,evidence_data LONGTEXT NOT NULL,analyzed_by VARCHAR(64) NOT NULL,
                created_at DATETIME NOT NULL,expires_at DATETIME NOT NULL,
                KEY idx_ob_ballistic_signature (ballistic_signature),KEY idx_ob_ballistic_expires (expires_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]},
            {name='cadastro de digitais',sql=[[CREATE TABLE IF NOT EXISTS ob_fingerprint_registry (
                fingerprint_code VARCHAR(64) NOT NULL PRIMARY KEY,user_id VARCHAR(64) NOT NULL,
                person_name VARCHAR(100) NOT NULL,registered_by VARCHAR(64) NOT NULL,registered_at DATETIME NOT NULL,
                KEY idx_ob_fingerprint_user (user_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]},
            {name='vestigios digitais',sql=[[CREATE TABLE IF NOT EXISTS ob_fingerprint_traces (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,fingerprint_code VARCHAR(64) NOT NULL,
                trace_type VARCHAR(24) NOT NULL,reference_id VARCHAR(96) NOT NULL,details LONGTEXT NOT NULL,
                recorded_at DATETIME NOT NULL,expires_at DATETIME NOT NULL,
                UNIQUE KEY uq_ob_fingerprint_trace (fingerprint_code,trace_type,reference_id),
                KEY idx_ob_fingerprint_trace_expires (expires_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]},
            {name='vestigios quimicos',sql=[[CREATE TABLE IF NOT EXISTS ob_chemical_traces (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,user_id VARCHAR(64) NOT NULL,
                trace_kind VARCHAR(16) NOT NULL,substance VARCHAR(64) NOT NULL,origin VARCHAR(64) NOT NULL,
                detected_at DATETIME NOT NULL,expires_at DATETIME NOT NULL,
                KEY idx_ob_chemical_user (user_id,expires_at),KEY idx_ob_chemical_expires (expires_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]},
        }
        for _,schema in ipairs(schemas) do
            local result,errorMessage=OR.Database.query.await(schema.sql)
            if result==nil then
                databaseReady=false
                print(('[ob_evidence] Falha ao preparar %s: %s'):format(schema.name,tostring(errorMessage)))
            end
        end
        if databaseReady then
            OR.Database.update.await('DELETE FROM ob_ballistic_archive WHERE expires_at<=NOW()')
            OR.Database.update.await('DELETE FROM ob_fingerprint_traces WHERE expires_at<=NOW()')
            OR.Database.update.await('DELETE FROM ob_chemical_traces WHERE expires_at<=NOW()')
        end
    else
        print('[ob_evidence] Banco de dados indisponivel; arquivo balistico nao foi iniciado.')
    end
    local lastArchiveCleanup=os.time()
    while true do
        Wait(60000);local now=os.time()
        for id,entry in pairs(casings) do if entry.expiresAt<=now then removeCasing(id) end end
        if databaseReady and now-lastArchiveCleanup>=600 then
            OR.Database.update.await('DELETE FROM ob_ballistic_archive WHERE expires_at<=NOW()')
            OR.Database.update.await('DELETE FROM ob_fingerprint_traces WHERE expires_at<=NOW()')
            OR.Database.update.await('DELETE FROM ob_chemical_traces WHERE expires_at<=NOW()')
            lastArchiveCleanup=now
        end
        for userId,trace in pairs(recentGunshots) do if now-(tonumber(trace.at) or 0)>3600 then recentGunshots[userId]=nil end end
    end
end)

AddEventHandler('playerDropped',function() local src=tonumber(source);shotCooldowns[src]=nil;actionCooldowns[src]=nil;magnifierUsers[src]=nil end)
