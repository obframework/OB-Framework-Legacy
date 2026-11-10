local ready, sessions, locks, epochs = false, {}, {}, {}
local function uid(src) return exports.ob_core:GetUserId(src) end
local function same(src, s)
    return GetPlayerName(src) and uid(src) == s.uid and (epochs[src] or 0) == s.epoch
end
local function distance(a,b)
    return math.sqrt((a.x-b.x)^2 + (a.y-b.y)^2 + (a.z-b.z)^2)
end
local function notify(src, text, kind)
    TriggerClientEvent('ob_notification:client:notify', src, text, kind or 'info', 7000)
end
local function sql(kind, statement, params)
    local result, err = OR.Database[kind].await(statement, params or {})
    if result == nil then error(err or 'Banco indisponivel.') end
    return result
end
local function records(id)
    local result = {}
    for _, row in ipairs(sql('query', 'SELECT * FROM ob_licenses WHERE user_id=?', {id})) do result[row.category] = row end
    return result
end
local function yes(value) return value == true or tonumber(value) == 1 end
local function documentsAvailable()
    return GetResourceState('ob_documents') == 'started'
end
local function documentStatus(src)
    if not documentsAvailable() then return nil end
    local ok,result=pcall(function() return exports.ob_documents:GetStatus(src) end)
    if ok and type(result)=='table' then return result end
    print('[ob_licenca] Integracao opcional ob_documents indisponivel: '..tostring(result))
end
local function nearNpc(src)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and GetPlayerRoutingBucket(src) == 0 and distance(GetEntityCoords(ped), OBLicenca.Npc.coords) <= 4.0
end
local function usable(src)
    local state, ped = Player(src).state, GetPlayerPed(src)
    return ped ~= 0 and state['or:loaded'] == true and state['or:downed'] ~= true
        and state['ob:restrained'] ~= true and GetEntityHealth(ped) > 0
end
local function refund(src, ctx)
    if not ctx.payment or ctx.committed then return end
    if not same(src, ctx) then
        print(('[ob_licenca] ESTORNO PENDENTE user_id=%s valor=%s recibo=%s'):format(ctx.uid,ctx.payment.amount,tostring(ctx.payment.receipt)))
        return
    end
    local p = ctx.payment
    local ok, result = pcall(function()
        if p.receipt then return exports.ob_economy:RefundCharge(src,p.receipt,'Estorno prova indisponivel').success end
        if p.method == 'bank' then return exports.ob_bank:RefundToBank(src,p.amount,'Estorno prova indisponivel') end
        return exports.ob_inventory:AddMoney(src,'money',p.amount)
    end)
    if not ok or result ~= true then print(('[ob_licenca] Falha no estorno user_id=%s valor=%s'):format(ctx.uid,p.amount)) end
    ctx.payment = nil
end
local function charge(src, ctx, amount)
    if amount <= 0 then return true end
    if GetResourceState('ob_economy') == 'started' then
        local r = exports.ob_economy:ChargePlayer(src, amount, 'license_fee', 'Centro de licencas')
        if r and r.success then ctx.payment={amount=amount,receipt=r.receipt};return true end
        if not r or not r.fallback then return nil, r and r.error or 'Pagamento indisponivel.' end
    end
    if not same(src,ctx) then return nil, 'Sessao alterada.' end
    if GetResourceState('ob_bank') == 'started' and exports.ob_bank:PayWithCard(src, amount, 'Centro de licencas') == true then
        ctx.payment={amount=amount,method='bank'};return true
    end
    if not same(src,ctx) then return nil, 'Sessao alterada.' end
    if GetResourceState('ob_inventory') == 'started' and exports.ob_inventory:RemoveMoney(src,'money',amount) == true then
        ctx.payment={amount=amount,method='cash'};return true
    end
    return nil, 'Saldo insuficiente no cartao ou dinheiro em maos.'
end

local function schoolData(src,userId)
    local data,list=records(userId),{}
    local documents=documentStatus(src)
    local driver=documents and documents.driver
    for _,name in ipairs(OBLicenca.Order) do
        local c,r=OBLicenca.Categories[name],data[name] or {}
        local owned=yes(r.licensed)
        list[#list+1]={name=name,label=c.label,class=OBLicenca.Classes[name],owned=owned,expired=owned and driver and driver.expired or false,
            theory=yes(r.theory),fee=(tonumber(r.attempts) or 0)>0 and c.practicalRetakeFee or 0}
    end
    return {categories=list,theory=OBLicenca.Theory,documents=documents}
end

local function cleanup(src, s)
    if s.vehicle and DoesEntityExist(s.vehicle) then
        if GetResourceState('ob_vehiclekeys') == 'started' then
            pcall(function() exports.ob_vehiclekeys:PrepareVehicleRemoval(src,s.netId,false) end)
        end
        if DoesEntityExist(s.vehicle) and NetworkGetNetworkIdFromEntity(s.vehicle) == s.netId then DeleteEntity(s.vehicle) end
    end
    if s.bucket and same(src,s) then
        SetPlayerRoutingBucket(src,s.previousBucket or 0)
        local ped, c = GetPlayerPed(src), OBLicenca.ReturnCoords
        if ped ~= 0 then SetEntityCoords(ped,c.x,c.y,c.z,false,false,false,false) end
        TriggerClientEvent('ob_licenca:client:finish',src)
    end
    if sessions[src] == s then sessions[src] = nil end
end
local function finish(src, s, passed, reason)
    if s.finishing then return end
    s.finishing = true
    if passed and same(src,s) then
        local ok, err = pcall(sql,'update',
            'UPDATE ob_licenses SET licensed=1,issued_at=UNIX_TIMESTAMP() WHERE user_id=? AND category=? AND theory=1', {s.uid,s.category})
        if not ok or (tonumber(err) or 0)<1 then passed=false;reason='Falha ao salvar a licenca. Procure a administracao.';print('[ob_licenca] Falha de emissao: '..tostring(err)) end
        if passed and documentsAvailable() then
            local integrated,delivered,deliveryError=pcall(function()
                return exports.ob_documents:IssueDriverAfterApproval(src)
            end)
            if not integrated or not delivered then
                notify(src,deliveryError or 'Habilitacao registrada; o documento fisico esta indisponivel.','warning')
            end
        end
    else passed=false end
    if same(src,s) then
        notify(src,passed and 'Parabens! Habilitacao emitida e registrada.' or reason or 'Prova encerrada.',passed and 'success' or 'error')
    end
    print(('[ob_licenca] PRACTICAL user_id=%s category=%s passed=%s'):format(s.uid,s.category,tostring(passed)))
    cleanup(src,s)
end

local function callback(name, fn)
    OR.Callback.register(name,function(src,...)
        if not ready then return nil,'Centro de licencas inicializando.' end
        if locks[src] or not OR.Security.rateLimit(src,'licenca:request',12,10000) then return nil,'Aguarde a operacao atual.' end
        local ctx={uid=uid(src),epoch=epochs[src] or 0}
        if not ctx.uid or not usable(src) then return nil,'Personagem indisponivel.' end
        locks[src]=ctx
        local ok,result,err=pcall(fn,src,ctx,...)
        if not ok then
            print('[ob_licenca] '..name..': '..tostring(result))
            result,err=nil,'Nao foi possivel concluir. Tente novamente.'
        end
        if not ctx.committed then refund(src,ctx) end
        if not ok and sessions[src] and sessions[src].uid==ctx.uid then cleanup(src,sessions[src]) end
        if locks[src]==ctx then locks[src]=nil end
        if not same(src,ctx) then return nil,'Sessao alterada.' end
        return result,err
    end)
end

callback('status',function(src,ctx)
    if not nearNpc(src) then return nil,'Aproxime-se do instrutor.' end
    return schoolData(src,ctx.uid)
end)

callback('document',function(src,ctx,kind)
    if not nearNpc(src) then return nil,'Aproxime-se do instrutor.' end
    if kind~='driver' then return nil,'A identidade e atendida em outro local.' end
    if not documentsAvailable() then return nil,'Servico de documento fisico nao instalado.' end
    local integrated,processed,message=pcall(function()
        return exports.ob_documents:ProcessDriverDmv(src)
    end)
    if not integrated then return nil,'Servico de documento fisico indisponivel.' end
    if not processed then return nil,message end
    local result=schoolData(src,ctx.uid);result.notice=message
    return result
end)

callback('theory',function(src,ctx,category)
    local c=type(category)=='string' and OBLicenca.Categories[category]
    if not c or not nearNpc(src) or sessions[src] then return nil,'Aproxime-se do instrutor e finalize a prova anterior.' end
    local r=records(ctx.uid)[category] or {}
    if yes(r.licensed) or yes(r.theory) then return nil,'Essa etapa ja foi aprovada.' end
    -- Cada categoria usa somente suas dez perguntas diretas. Assim a prova
    -- de barco/helicoptero nao recebe questoes genericas de transito terrestre.
    local bank=OBLicenseQuestions[category]
    if type(bank)~='table' or #bank<OBLicenca.Theory.questionAmount then
        return nil,'Perguntas desta categoria indisponiveis.'
    end
    local pool={}
    for _,q in ipairs(bank) do pool[#pool+1]=q end
    for i=#pool,2,-1 do local j=math.random(i);pool[i],pool[j]=pool[j],pool[i] end
    local public,answers={},{}
    for i=1,math.min(#pool,OBLicenca.Theory.questionAmount) do
        local q=pool[i];local order={1,2,3,4}
        for j=4,2,-1 do local k=math.random(j);order[j],order[k]=order[k],order[j] end
        local options={}
        for j,index in ipairs(order) do options[j]=q.answers[index];if index==q.correct then answers[i]=j end end
        public[i]={id=i,question=q.question,answers=options}
    end
    local paid,err=charge(src,ctx,OBLicenca.Theory.fee)
    if not paid then return nil,err end
    if not same(src,ctx) or not nearNpc(src) or not usable(src) then return nil,'Prova cancelada: personagem se afastou.' end
    sessions[src]={uid=ctx.uid,epoch=ctx.epoch,kind='theory',category=category,answers=answers,
        started=GetGameTimer(),deadline=GetGameTimer()+OBLicenca.Theory.timeLimitSeconds*1000}
    ctx.committed=true
    return {questions=public,seconds=OBLicenca.Theory.timeLimitSeconds,label=c.label}
end)

callback('answers',function(src,ctx,answers)
    local s=sessions[src]
    if not s or s.kind~='theory' or not same(src,s) or type(answers)~='table' then return nil,'Prova invalida.' end
    sessions[src]=nil -- consumo unico, sem reenvio de respostas
    local errors=0
    for i,correct in ipairs(s.answers) do if tonumber(answers[tostring(i)] or answers[i])~=correct then errors=errors+1 end end
    if GetGameTimer()>s.deadline or not nearNpc(src) then return {passed=false,errors=errors,message='Tempo esgotado ou fora do local da prova.'} end
    if GetGameTimer()-s.started < 10000 then return {passed=false,errors=errors,message='Prova enviada cedo demais.'} end
    if errors>OBLicenca.Theory.maxErrors then return {passed=false,errors=errors,message='Reprovado na prova teorica.'} end
    sql('query','INSERT INTO ob_licenses (user_id,category,theory) VALUES (?,?,1) ON DUPLICATE KEY UPDATE theory=1',{ctx.uid,s.category})
    return {passed=true,errors=errors,message='Teorica aprovada! Volte ao menu para iniciar a pratica.'}
end)

callback('practical',function(src,ctx,category)
    local c=type(category)=='string' and OBLicenca.Categories[category]
    if not c or not nearNpc(src) or sessions[src] then return nil,'Prova indisponivel. Aproxime-se do instrutor.' end
    if GetVehiclePedIsIn(GetPlayerPed(src),false)~=0 then return nil,'Saia do veiculo para iniciar.' end
    if GetResourceState('ob_vehiclekeys')~='started' then return nil,'Sistema de chaves indisponivel.' end
    local r=records(ctx.uid)[category] or {}
    if not yes(r.theory) or yes(r.licensed) then return nil,'Conclua a teorica primeiro ou confira sua habilitacao.' end
    local paid,err=charge(src,ctx,(tonumber(r.attempts) or 0)>0 and c.practicalRetakeFee or 0)
    if not paid then return nil,err end
    if not same(src,ctx) or not nearNpc(src) or not usable(src) then return nil,'Sessao alterada.' end
    local bucket=OBLicenca.BucketBase+src
    for _,id in ipairs(GetPlayers()) do if GetPlayerRoutingBucket(tonumber(id))==bucket then return nil,'Pista ocupada. Tente novamente.' end end
    local s={uid=ctx.uid,epoch=ctx.epoch,kind='loading',category=category,bucket=bucket,
        previousBucket=GetPlayerRoutingBucket(src),index=1,errors=0,lastPoint=GetGameTimer(),lastPenalty=0}
    sessions[src]=s
    SetRoutingBucketPopulationEnabled(bucket,false)
    SetPlayerRoutingBucket(src,bucket)
    local spawned,payload=exports.ob_core:SpawnTemporaryVehicle(src,c.vehicle,c.spawn,
        {serverSetterType=c.serverType,maxDistance=5000,clearRadius=false,platePrefix='ESC',fuel=100})
    if not spawned then cleanup(src,s);return nil,payload or 'Falha ao criar veiculo.' end
    s.netId=payload.netId;s.vehicle=NetworkGetEntityFromNetworkId(s.netId)
    if not same(src,s) or sessions[src]~=s or not DoesEntityExist(s.vehicle) then cleanup(src,s);return nil,'Prova cancelada.' end
    sql('update','UPDATE ob_licenses SET attempts=attempts+1 WHERE user_id=? AND category=?',{ctx.uid,category})
    if not same(src,s) then cleanup(src,s);return nil,'Sessao alterada.' end
    s.kind='practical';s.start=GetGameTimer();s.deadline=s.start+c.timeLimitSeconds*1000
    ctx.committed=true
    return {netId=s.netId,category=category,seconds=c.timeLimitSeconds}
end)

callback('cancel',function(src)
    local s=sessions[src]
    if s and not s.finishing then finish(src,s,false,'Prova cancelada. Taxas de provas iniciadas nao sao reembolsadas.') end
    return true
end)

callback('inspect',function(src,ctx,targetUserId)
    targetUserId=tonumber(targetUserId)
    if not targetUserId or targetUserId%1~=0 then return nil,'Informe o ID do personagem.' end
    local allowed=GetResourceState('ob_org')=='started' and exports.ob_org:HasPermission(src,OBLicenca.PolicePermission,true)
    if allowed~=true or not same(src,ctx) then return nil,'Consulta exclusiva para policiais em servico.' end
    local target=exports.ob_core:GetSourceByUserId(targetUserId)
    local function nearTarget()
        return target and GetPlayerName(target) and uid(target)==targetUserId and GetPlayerRoutingBucket(src)==GetPlayerRoutingBucket(target)
            and distance(GetEntityCoords(GetPlayerPed(src)),GetEntityCoords(GetPlayerPed(target)))<=OBLicenca.InspectDistance
    end
    if not nearTarget() then return nil,'Aproxime-se da pessoa para conferir os documentos.' end
    if not same(src,ctx) or not nearTarget() or not usable(src) then return nil,'Pessoa indisponivel.' end
    if exports.ob_org:HasPermission(src,OBLicenca.PolicePermission,true)~=true
        or not same(src,ctx) or not nearTarget() then return nil,'Consulta nao autorizada.' end
    local inspection,inspectionError
    if documentsAvailable() then
        local integrated
        integrated,inspection,inspectionError=pcall(function()
            return exports.ob_documents:GetInspection(targetUserId,target)
        end)
        if not integrated then inspection=nil end
    end
    if not inspection then
        local character=exports.ob_core:GetCharacter(target)
        if not character then return nil,inspectionError or 'Personagem indisponivel.' end
        local stored,categories=records(targetUserId),{}
        for _,name in ipairs(OBLicenca.Order) do
            local definition,row=OBLicenca.Categories[name],stored[name]
            categories[#categories+1]={label=definition.label,class=OBLicenca.Classes[name],
                valid=row~=nil and yes(row.licensed),issuedAt=row and tonumber(row.issued_at) or 0}
        end
        local job=exports.ob_core:GetJob(target)
        inspection={userId=targetUserId,
            name=((tostring(character.firstname or '')..' '..tostring(character.lastname or '')):gsub('^%s+',''):gsub('%s+$','')),
            birthdate=character.birthdate,nationality=character.nationality,
            job=type(job)=='table' and tostring(job.label or job.name or 'Desempregado') or 'Desempregado',
            identityIssued=false,licenseExpiresAt=0,licenseExpired=false,categories=categories}
    end
    print(('[ob_licenca] INSPECT officer=%s target=%s'):format(ctx.uid,targetUserId))
    return inspection
end)

-- Apenas recursos do servidor podem consultar este export. Nao concede licencas.
exports('HasLicense',function(userId,category)
    userId=tonumber(userId)
    if not ready or not userId or type(category)~='string' or not OBLicenca.Categories[category] then return false end
    local row=records(userId)[category]
    return row~=nil and yes(row.licensed)
end)

exports('UseInventoryDocument',function(src,itemName,metadata)
    src=tonumber(src)
    local id=src and uid(src)
    if not ready or not id or not usable(src) then return false,'Personagem indisponivel.' end
    if itemName~='driver_license' or type(metadata)~='table'
        or metadata.documentType~='driver_license' or tonumber(metadata.userId)~=id then
        return false,'Esta CNH nao pertence ao personagem atual.'
    end
    if not documentsAvailable() then return false,'Sistema de documentos indisponivel.' end
    local ok,data,message=pcall(function() return exports.ob_documents:GetInspection(id,src) end)
    if not ok or type(data)~='table' then return false,message or 'Nao foi possivel consultar a CNH.' end
    TriggerClientEvent('ob_licenca:client:toggleDriverDocument',src,data)
    return true,'CNH consultada.'
end)

CreateThread(function()
    while not ready do
        if OR.Database.waitForReady(10000) then
            local ok,err=pcall(sql,'query',[[CREATE TABLE IF NOT EXISTS ob_licenses (
                user_id BIGINT UNSIGNED NOT NULL, category VARCHAR(16) NOT NULL,
                theory TINYINT NOT NULL DEFAULT 0, licensed TINYINT NOT NULL DEFAULT 0,
                attempts INT UNSIGNED NOT NULL DEFAULT 0, issued_at BIGINT NOT NULL DEFAULT 0,
                PRIMARY KEY (user_id,category)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
            ready=ok
            if not ok then print('[ob_licenca] Banco: '..tostring(err)) end
        end
        if not ready then Wait(5000) end
    end
    print('[ob_licenca] Centro de licencas pronto.')
end)

CreateThread(function()
    while true do
        Wait(500)
        for src,s in pairs(sessions) do
            if not s.finishing and s.kind=='theory' and GetGameTimer()>s.deadline then
                sessions[src]=nil
                if same(src,s) then TriggerClientEvent('ob_licenca:client:expired',src) end
            elseif not s.finishing and s.kind=='practical' then
                local c,now=OBLicenca.Categories[s.category],GetGameTimer()
                local ped=GetPlayerPed(src)
                if not same(src,s) or not usable(src) or not DoesEntityExist(s.vehicle) or GetPlayerRoutingBucket(src)~=s.bucket then
                    finish(src,s,false,'Prova interrompida: personagem ou veiculo indisponivel.')
                elseif now>s.deadline then finish(src,s,false,'O tempo da prova acabou.')
                elseif (s.entered or now-s.start>15000) and GetPedInVehicleSeat(s.vehicle,-1)~=ped then finish(src,s,false,'Voce saiu do banco do motorista da prova.')
                elseif GetPedInVehicleSeat(s.vehicle,-1)==ped then
                    s.entered=true
                    local point=c.checkpoints[s.index]
                    local speed=GetEntitySpeed(s.vehicle)*3.6
                    if point.speedLimit and speed>point.speedLimit+OBLicenca.SpeedTolerance then
                        s.speedSince=s.speedSince or now
                        if now-s.speedSince>=OBLicenca.SpeedGraceMs and now-s.lastPenalty>=OBLicenca.PenaltyCooldownMs then
                            s.errors=s.errors+1;s.lastPenalty=now
                            notify(src,'Excesso de velocidade. Erros: '..s.errors..'/'..c.maxErrors,'warning')
                            TriggerClientEvent('ob_licenca:client:progress',src,s.index,s.errors)
                        end
                    else s.speedSince=nil end
                    local health=GetVehicleBodyHealth(s.vehicle)
                    if s.health and health<s.health-10 and now-s.lastPenalty>=OBLicenca.PenaltyCooldownMs then
                        s.errors=s.errors+1;s.lastPenalty=now;notify(src,'Veiculo danificado: penalidade aplicada.','warning')
                        TriggerClientEvent('ob_licenca:client:progress',src,s.index,s.errors)
                    end
                    s.health=health
                    if s.errors>c.maxErrors or health<=0 or GetEntityHealth(s.vehicle)<=0 then finish(src,s,false,'Reprovado: limite de erros ou veiculo destruido.')
                    elseif distance(GetEntityCoords(ped),point.coords)<=point.radius+2 and now-s.lastPoint>=OBLicenca.MinCheckpointMs then
                        s.index=s.index+1;s.lastPoint=now
                        if s.index>#c.checkpoints then finish(src,s,true)
                        else TriggerClientEvent('ob_licenca:client:progress',src,s.index,s.errors) end
                    end
                end
            end
        end
    end
end)

AddEventHandler('playerDropped',function()
    local src=source;epochs[src]=(epochs[src] or 0)+1;locks[src]=nil
    local s=sessions[src];if s then CreateThread(function() cleanup(src,s) end) end
end)
AddEventHandler('onResourceStop',function(name)
    if name~=GetCurrentResourceName() then return end
    for src,s in pairs(sessions) do
        -- Limpeza imediata sem aguardar SQL durante o encerramento do recurso.
        if s.vehicle and DoesEntityExist(s.vehicle) then DeleteEntity(s.vehicle) end
        if s.bucket and same(src,s) then
            SetPlayerRoutingBucket(src,s.previousBucket or 0)
            local c,ped=OBLicenca.ReturnCoords,GetPlayerPed(src)
            if ped~=0 then SetEntityCoords(ped,c.x,c.y,c.z,false,false,false,false) end
        end
    end
end)
