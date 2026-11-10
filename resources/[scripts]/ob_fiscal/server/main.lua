local ready = false
local actionLocks = {}

local function clean(value, maximum)
    value = tostring(value or ''):gsub('[\r\n%z]', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''
    return value:sub(1, maximum or 120)
end

local function whole(value, maximum)
    value = math.floor(tonumber(value) or 0)
    return math.max(0, math.min(value, maximum or 1000000000))
end

local function userId(source)
    source = tonumber(source)
    return source and GetPlayerName(source) and tonumber(exports.ob_core:GetUserId(source)) or nil
end

local function fullName(source)
    local ok, value = pcall(function() return exports.ob_core:GetFullName(source) end)
    value = ok and clean(value, 100) or clean(GetPlayerName(source), 100)
    return value ~= '' and value or ('ID %s'):format(userId(source) or '?')
end

local function policeAllowed(source)
    if GetResourceState('ob_org') ~= 'started' then return false end
    local ok, allowed = pcall(function()
        return exports.ob_org:HasPermission(source, OBFiscal.PolicePermission or 'police', OBFiscal.PoliceRequireDuty ~= false)
    end)
    return ok and allowed == true
end

local function inventoryReady()
    return GetResourceState('ob_inventory') == 'started'
end

local function fiscalBusiness(shopId)
    if not inventoryReady() then return nil, 'As lojas estao indisponiveis; as lavagens comuns continuam funcionando.' end
    local ok, data, err = pcall(function() return exports.ob_inventory:GetFiscalBusiness(tostring(shopId or '')) end)
    if not ok then return nil, 'A integracao fiscal das lojas ainda nao esta pronta.' end
    return data, err
end

local function ownerBusinesses(ownerUserId)
    if not inventoryReady() then return nil, 'As lojas estao indisponiveis.' end
    local ok, data, err = pcall(function() return exports.ob_inventory:GetFiscalBusinesses(ownerUserId) end)
    if not ok then return nil, 'A integracao fiscal das lojas ainda nao esta pronta.' end
    return data, err
end

local function nearManager(source, business)
    local point = business and business.manager
    local ped = GetPlayerPed(source)
    if not point or not ped or ped <= 0 then return false end
    return #(GetEntityCoords(ped) - vector3(point.x, point.y, point.z)) <= (tonumber(OBFiscal.ManagerDistance) or 5.0)
end

local function ensureAccount(business)
    local row = OR.Database.single.await('SELECT * FROM ob_fiscal_business_accounts WHERE shop_id=? LIMIT 1', { business.shopId })
    if not row then
        local inserted, err = OR.Database.insert.await([[INSERT INTO ob_fiscal_business_accounts
            (shop_id,owner_user_id,owner_name,shop_label,unreported_balance,risk_score) VALUES (?,?,?,?,0,0)]],
            { business.shopId,business.ownerUserId,business.ownerName or '',business.label })
        if not inserted then return nil, err or 'Nao foi possivel abrir o livro fiscal.' end
        row = OR.Database.single.await('SELECT * FROM ob_fiscal_business_accounts WHERE shop_id=? LIMIT 1', { business.shopId })
    elseif tonumber(row.owner_user_id) ~= tonumber(business.ownerUserId) then
        if tonumber(row.unreported_balance) > 0 then return nil, 'A loja mudou de proprietario com caixa nao declarado. Procure a administracao.' end
        OR.Database.update.await([[UPDATE ob_fiscal_business_accounts SET owner_user_id=?,owner_name=?,shop_label=?,risk_score=0
            WHERE shop_id=? AND unreported_balance=0]], {business.ownerUserId,business.ownerName or '',business.label,business.shopId})
        row.owner_user_id,row.owner_name,row.shop_label,row.risk_score=business.ownerUserId,business.ownerName,business.label,0
    else
        OR.Database.update.await('UPDATE ob_fiscal_business_accounts SET owner_name=?,shop_label=? WHERE shop_id=?',
            { business.ownerName or '',business.label,business.shopId })
    end
    return row
end

local function capacity(business)
    local dailySales = (tonumber(business.sales7d) or 0) / 7
    local value = whole((tonumber(OBFiscal.BaseDailyCapacity) or 15000) + dailySales * (tonumber(OBFiscal.SalesCoverRate) or 0.35))
    return math.max(1, math.min(value, tonumber(OBFiscal.MaximumDailyCapacity) or 500000))
end

local function declaredToday(shopId)
    return tonumber(OR.Database.scalar.await([[SELECT COALESCE(SUM(gross_amount),0) FROM ob_fiscal_declarations
        WHERE shop_id=? AND created_at>=DATE_SUB(NOW(),INTERVAL 24 HOUR) AND status NOT IN ('failed','cancelled')]], { shopId })) or 0
end

local function riskFor(business, amount, used, dailyCapacity)
    local score, reasons = 0, {}
    local average = (tonumber(business.sales7d) or 0) / 7
    local ratio = amount / math.max(1, average)
    if average < 1000 then score=score+35; reasons[#reasons+1]='loja sem faturamento real suficiente'
    elseif ratio>2 then score=score+40; reasons[#reasons+1]='declaracao superior ao dobro da media diaria'
    elseif ratio>1 then score=score+25; reasons[#reasons+1]='declaracao superior a media diaria'
    elseif ratio>0.5 then score=score+10; reasons[#reasons+1]='declaracao relevante frente a media diaria' end
    if amount >= dailyCapacity*0.75 then score=score+20; reasons[#reasons+1]='uso de mais de 75% do limite diario' end
    local count = tonumber(OR.Database.scalar.await([[SELECT COUNT(*) FROM ob_fiscal_declarations
        WHERE shop_id=? AND created_at>=DATE_SUB(NOW(),INTERVAL 24 HOUR)]], {business.shopId})) or 0
    if count>=3 then score=score+15; reasons[#reasons+1]='declaracoes fracionadas e repetidas' end
    if used+amount >= dailyCapacity then score=score+10; reasons[#reasons+1]='limite diario completamente utilizado' end
    return math.min(100,score),reasons
end

local function dispatchRegister()
    if GetResourceState('ob_dispatch')~='started' then return end
    local cfg=OBFiscal.Dispatch or {}
    pcall(function() exports.ob_dispatch:RegisterType(cfg.Type or 'fiscal_suspicion',{
        code=cfg.Code or '10-90F',title=cfg.Title or 'Alerta fiscal',message=cfg.Message or 'Movimentacao fiscal suspeita.',
        groups={OBFiscal.PolicePermission or 'police'},priority=2,duration=cfg.Duration or 180,radius=cfg.Radius or 90.0,
        offsetMin=25.0,offsetMax=70.0,radiusOnly=true,blip={sprite=500,colour=1,scale=0.9},sound=true,
    }) end)
end

local function sendRiskAlert(business,declarationId,risk,reasons)
    if risk < (tonumber(OBFiscal.DispatchRiskScore) or 75) or GetResourceState('ob_dispatch')~='started' or not business.manager then return end
    local cfg=OBFiscal.Dispatch or {}
    pcall(function() exports.ob_dispatch:CreateAlert(cfg.Type or 'fiscal_suspicion',{
        coords=business.manager,radiusOnly=true,
        message=('Relatorio automatico aponta incompatibilidade fiscal em %s.'):format(business.label),
        metadata={declarationId=declarationId,shopId=business.shopId,risk=risk,reasons=reasons},
    }) end)
end

local function ownerPanel(source, requestedShopId)
    if not ready then return nil,'Sistema fiscal ainda esta iniciando.' end
    local uid=userId(source);if not uid then return nil,'Personagem indisponivel.' end
    local businesses,err=ownerBusinesses(uid);if not businesses then return nil,err end
    if #businesses<1 then return nil,'Voce nao possui uma loja de conveniencia.' end
    local business
    requestedShopId=tostring(requestedShopId or '')
    for _,entry in ipairs(businesses)do if requestedShopId=='' or entry.shopId==requestedShopId then business=entry;break end end
    if not business then return nil,'Esta loja nao pertence a voce.' end
    local account,accountError=ensureAccount(business);if not account then return nil,accountError end
    local dailyCapacity,used=capacity(business),declaredToday(business.shopId)
    local declarations=OR.Database.query.await([[SELECT id,gross_amount,tax_amount,net_amount,risk_score,risk_reasons,status,police_status,
        DATE_FORMAT(created_at,'%d/%m/%Y %H:%i') AS created_at FROM ob_fiscal_declarations
        WHERE shop_id=? ORDER BY id DESC LIMIT ?]],{business.shopId,tonumber(OBFiscal.RecentDeclarations) or 30}) or {}
    local payroll=OR.Database.query.await([[SELECT id,amount,status,DATE_FORMAT(created_at,'%d/%m/%Y %H:%i') AS created_at
        FROM ob_fiscal_payroll WHERE shop_id=? ORDER BY id DESC LIMIT 15]],{business.shopId}) or {}
    local dirtyBalance=0
    pcall(function() dirtyBalance=tonumber(exports.ob_inventory:GetMoney(source,OBFiscal.DirtyAccount or 'black_money')) or 0 end)
    return {mode='owner',selectedShopId=business.shopId,businesses=businesses,business=business,
        fiscal={unreported=tonumber(account.unreported_balance) or 0,risk=tonumber(account.risk_score) or 0,
            dailyCapacity=dailyCapacity,usedToday=used,remaining=math.max(0,dailyCapacity-used),taxPercent=tonumber(OBFiscal.DeclarationTaxPercent) or 20,
            dirtyBalance=dirtyBalance},
        declarations=declarations,payroll=payroll}
end

OR.Callback.register('ownerPanel',ownerPanel,{rateLimit={limit=8,window=10000}})

OR.Callback.register('deposit',function(source,shopId,rawAmount)
    if not ready then return nil,'Sistema fiscal indisponivel.' end
    local uid=userId(source);if not uid or actionLocks[uid] then return nil,'Aguarde a operacao atual.' end
    actionLocks[uid]=true
    local function finish(result,message)actionLocks[uid]=nil;return result,message end
    local business,err=fiscalBusiness(shopId);if not business then return finish(nil,err) end
    if tonumber(business.ownerUserId)~=uid then return finish(nil,'Somente o proprietario pode movimentar o caixa fiscal.') end
    if not nearManager(source,business) then return finish(nil,'Fale com o atendente da loja para depositar.') end
    local account,accountError=ensureAccount(business);if not account then return finish(nil,accountError) end
    local amount=whole(rawAmount,tonumber(OBFiscal.MaximumDeposit) or 1000000)
    if amount<(tonumber(OBFiscal.MinimumDeposit) or 1000) then return finish(nil,'Valor abaixo do minimo permitido.') end
    local remaining=math.max(0,capacity(business)-declaredToday(business.shopId)-(tonumber(account.unreported_balance) or 0))
    if amount>remaining then return finish(nil,('O caixa fiscal comporta apenas $%s neste periodo.'):format(remaining)) end
    local before=0
    local balanceOk=pcall(function()before=tonumber(exports.ob_inventory:GetMoney(source,OBFiscal.DirtyAccount or 'black_money')) or 0 end)
    if not balanceOk then return finish(nil,'Inventario indisponivel para confirmar o saldo.') end
    if before<amount then return finish(nil,'Dinheiro sujo insuficiente.') end
    local removeOk,removed,removeError=pcall(function()return exports.ob_inventory:RemoveMoney(source,OBFiscal.DirtyAccount or 'black_money',amount)end)
    if not removeOk then return finish(nil,'Inventario indisponivel para recolher o dinheiro.') end
    if not removed then return finish(nil,removeError or 'Nao foi possivel recolher o dinheiro.') end
    local result,dbError=OR.Database.transaction.await({
        {kind='update',statement='UPDATE ob_fiscal_business_accounts SET unreported_balance=unreported_balance+? WHERE shop_id=? AND owner_user_id=?',parameters={amount,business.shopId,uid},expectAffectedMin=1},
        {kind='insert',statement=[[INSERT INTO ob_fiscal_deposits (shop_id,user_id,amount,balance_before,balance_after)
            VALUES (?,?,?,?,?)]],parameters={business.shopId,uid,amount,before,before-amount},expectAffectedMin=1},
    })
    if not result then
        local refundCall,refunded=pcall(function()return exports.ob_inventory:AddMoney(source,OBFiscal.DirtyAccount or 'black_money',amount)end)
        if not refundCall or not refunded then
            print(('[ob_fiscal] ALERTA: falha ao devolver $%s sujos ao ID %s apos erro de deposito: %s'):format(amount,uid,tostring(dbError)))
            return finish(nil,'Falha critica ao registrar e devolver o valor. Procure a administracao com o horario desta tentativa.')
        end
        return finish(nil,dbError or 'Falha ao registrar; valor devolvido.')
    end
    local panel=ownerPanel(source,business.shopId)
    TriggerClientEvent('ob_fiscal:client:refresh',source,business.shopId)
    return finish(panel,('Foram colocados $%s no caixa nao declarado.'):format(amount))
end,{rateLimit={limit=3,window=10000}})

OR.Callback.register('declare',function(source,shopId,rawAmount)
    if not ready then return nil,'Sistema fiscal indisponivel.' end
    local uid=userId(source);if not uid or actionLocks[uid] then return nil,'Aguarde a operacao atual.' end
    actionLocks[uid]=true
    local function finish(result,message)actionLocks[uid]=nil;return result,message end
    local business,err=fiscalBusiness(shopId);if not business then return finish(nil,err) end
    if tonumber(business.ownerUserId)~=uid then return finish(nil,'Somente o proprietario pode declarar.') end
    if not nearManager(source,business) then return finish(nil,'Fale com o atendente da loja para declarar.') end
    local account,accountError=ensureAccount(business);if not account then return finish(nil,accountError) end
    local amount=whole(rawAmount,tonumber(OBFiscal.MaximumDeposit) or 1000000)
    local used,dailyCapacity=declaredToday(business.shopId),capacity(business)
    if amount<(tonumber(OBFiscal.MinimumDeposit) or 1000) then return finish(nil,'Valor abaixo do minimo permitido.') end
    if amount>(tonumber(account.unreported_balance) or 0) then return finish(nil,'Caixa nao declarado insuficiente.') end
    if used+amount>dailyCapacity then return finish(nil,'A declaracao ultrapassa a capacidade fiscal das ultimas 24 horas.') end
    local taxPercent=math.max(0,math.min(95,tonumber(OBFiscal.DeclarationTaxPercent) or 20))
    local tax=math.floor(amount*taxPercent/100);local net=amount-tax
    local risk,reasons=riskFor(business,amount,used,dailyCapacity)
    local reasonsJson=json.encode(reasons)
    local declarationId,dbError=OR.Database.insert.await([[INSERT INTO ob_fiscal_declarations
        (shop_id,owner_user_id,owner_name,shop_label,gross_amount,tax_percent,tax_amount,net_amount,real_sales_7d,risk_score,risk_reasons,status)
        SELECT ?,?,?,?,?,?,?,?,?,?,?,'reserving' FROM ob_fiscal_business_accounts
        WHERE shop_id=? AND owner_user_id=? AND unreported_balance>=?]],
        {business.shopId,uid,business.ownerName or fullName(source),business.label,amount,taxPercent,tax,net,business.sales7d,risk,reasonsJson,business.shopId,uid,amount})
    if not declarationId then return finish(nil,dbError or 'Nao foi possivel reservar a declaracao.') end
    local reserved,reserveError=OR.Database.transaction.await({
        {kind='update',statement=[[UPDATE ob_fiscal_business_accounts SET unreported_balance=unreported_balance-?,risk_score=GREATEST(risk_score,?),last_declaration_at=NOW()
            WHERE shop_id=? AND owner_user_id=? AND unreported_balance>=?]],parameters={amount,risk,business.shopId,uid,amount},expectAffectedMin=1},
        {kind='update',statement="UPDATE ob_fiscal_declarations SET status='crediting' WHERE id=? AND status='reserving'",parameters={declarationId},expectAffectedMin=1},
    })
    if not reserved then OR.Database.update.await("UPDATE ob_fiscal_declarations SET status='failed',integrity_note=? WHERE id=?",{clean(reserveError or 'Saldo fiscal mudou durante declaracao',255),declarationId});return finish(nil,'O caixa fiscal mudou; tente novamente.') end
    local token=('fiscal:declaration:%s'):format(declarationId)
    local ok,movement,moveError=pcall(function()return exports.ob_inventory:ApplyFiscalBusinessBalance(business.shopId,uid,'credit',net,token,{declarationId=declarationId,tax=tax})end)
    if not ok or not movement then
        OR.Database.transaction.await({
            {kind='update',statement="UPDATE ob_fiscal_declarations SET status='failed',integrity_note=? WHERE id=? AND status='crediting'",parameters={clean(moveError or movement or 'Falha no credito empresarial',255),declarationId},expectAffectedMin=1},
            {kind='update',statement='UPDATE ob_fiscal_business_accounts SET unreported_balance=unreported_balance+? WHERE shop_id=? AND owner_user_id=?',parameters={amount,business.shopId,uid},expectAffectedMin=1},
        })
        return finish(nil,moveError or 'Nao foi possivel creditar a empresa; o valor voltou ao caixa nao declarado.')
    end
    local treasuryReceipt
    if tax>0 and GetResourceState('ob_economy')=='started' then
        local success,result=pcall(function()return exports.ob_economy:Deposit(OBFiscal.EconomyAccount or 'city_treasury',tax,'fiscal_declaration_tax',('Declaracao fiscal %s'):format(declarationId),{declarationId=declarationId,shopId=business.shopId})end)
        if success and result then treasuryReceipt=tonumber(result.ledgerId) end
    end
    OR.Database.update.await("UPDATE ob_fiscal_declarations SET status='credited',credit_token=? WHERE id=? AND status='crediting'",{token,declarationId})
    local status=risk>=(tonumber(OBFiscal.FlagRiskScore) or 45) and 'flagged' or 'completed'
    OR.Database.update.await([[UPDATE ob_fiscal_declarations SET status=?,credit_token=?,treasury_ledger_id=?,settled_at=NOW() WHERE id=?]],
        {status,token,treasuryReceipt or 0,declarationId})
    sendRiskAlert(business,declarationId,risk,reasons)
    local panel=ownerPanel(source,business.shopId)
    return finish(panel,('Declaracao #%s concluida: imposto $%s, saldo empresarial $%s.'):format(declarationId,tax,net))
end,{rateLimit={limit=2,window=15000}})

OR.Callback.register('payroll',function(source,shopId,rawAmount)
    if not ready then return nil,'Sistema fiscal indisponivel.' end
    if GetResourceState('ob_bank')~='started' then return nil,'Banco indisponivel para pro-labore.' end
    local uid=userId(source);if not uid or actionLocks[uid] then return nil,'Aguarde a operacao atual.' end
    actionLocks[uid]=true
    local function finish(result,message)actionLocks[uid]=nil;return result,message end
    local business,err=fiscalBusiness(shopId);if not business then return finish(nil,err) end
    if tonumber(business.ownerUserId)~=uid then return finish(nil,'Somente o proprietario pode retirar pro-labore.') end
    if not nearManager(source,business) then return finish(nil,'Fale com o atendente da loja.') end
    local amount=whole(rawAmount,1000000000);if amount<1 then return finish(nil,'Valor invalido.') end
    local payrollId,insertError=OR.Database.insert.await([[INSERT INTO ob_fiscal_payroll
        (shop_id,owner_user_id,owner_name,amount,status) VALUES (?,?,?,?,'paying')]],{business.shopId,uid,business.ownerName or fullName(source),amount})
    if not payrollId then return finish(nil,insertError or 'Falha ao iniciar pro-labore.') end
    local debitToken=('fiscal:payroll:%s:debit'):format(payrollId)
    local ok,debit,debitError=pcall(function()return exports.ob_inventory:ApplyFiscalBusinessBalance(business.shopId,uid,'debit',amount,debitToken,{payrollId=payrollId})end)
    if not ok or not debit then OR.Database.update.await("UPDATE ob_fiscal_payroll SET status='failed',integrity_note=? WHERE id=?",{clean(debitError or 'Saldo empresarial insuficiente',255),payrollId});return finish(nil,debitError or 'Saldo empresarial insuficiente.') end
    local bankOk,paid,payError=pcall(function()return exports.ob_bank:CreditSalary(source,amount,('Pro-labore fiscal #%s - %s'):format(payrollId,business.label))end)
    if not bankOk then paid,payError=false,'Banco reiniciado durante o pagamento.' end
    if not paid then
        local refundToken=('fiscal:payroll:%s:refund'):format(payrollId)
        local refundOk,refund=pcall(function()return exports.ob_inventory:ApplyFiscalBusinessBalance(business.shopId,uid,'credit',amount,refundToken,{payrollId=payrollId,reason='bank_failed'})end)
        OR.Database.update.await("UPDATE ob_fiscal_payroll SET status=?,integrity_note=? WHERE id=?",{refundOk and refund and 'failed' or 'review',clean(payError or 'Banco recusou pagamento',255),payrollId})
        return finish(nil,payError or 'Banco recusou o pagamento; o saldo foi devolvido a loja.')
    end
    OR.Database.update.await("UPDATE ob_fiscal_payroll SET status='paid',debit_token=?,paid_at=NOW() WHERE id=?",{debitToken,payrollId})
    return finish(ownerPanel(source,business.shopId),('Pro-labore de $%s enviado ao banco.'):format(amount))
end,{rateLimit={limit=2,window=15000}})

local function policePanel(source)
    if not ready then return nil,'Sistema fiscal indisponivel.' end
    if not policeAllowed(source) then return nil,'Acesso exclusivo da investigacao policial em servico.' end
    local rows=OR.Database.query.await([[SELECT id,shop_id,shop_label,owner_user_id,owner_name,gross_amount,tax_amount,net_amount,
        real_sales_7d,risk_score,risk_reasons,status,police_status,police_notes,
        DATE_FORMAT(created_at,'%d/%m/%Y %H:%i') AS created_at FROM ob_fiscal_declarations
        ORDER BY (risk_score>=?) DESC,risk_score DESC,id DESC LIMIT ?]],
        {tonumber(OBFiscal.FlagRiskScore) or 45,tonumber(OBFiscal.PoliceRows) or 100}) or {}
    return {mode='police',rows=rows,threshold=tonumber(OBFiscal.FlagRiskScore) or 45}
end

OR.Callback.register('policePanel',policePanel,{rateLimit={limit=8,window=10000}})

OR.Callback.register('policeStatus',function(source,rawId,rawStatus,rawNotes)
    if not policeAllowed(source) then return nil,'Sem permissao policial.' end
    local id=tonumber(rawId);local status=clean(rawStatus,16):lower()
    if not id or not ({new=true,reviewing=true,cleared=true,escalated=true})[status] then return nil,'Atualizacao invalida.' end
    local changed,err=OR.Database.update.await([[UPDATE ob_fiscal_declarations SET police_status=?,police_notes=?,reviewed_by=?,reviewed_at=NOW() WHERE id=?]],
        {status,clean(rawNotes,500),userId(source),id})
    if not changed or changed<1 then return nil,err or 'Declaracao nao encontrada.' end
    return policePanel(source),'Investigacao atualizada.'
end,{rateLimit={limit=6,window=10000}})

local schemas={
[[CREATE TABLE IF NOT EXISTS ob_fiscal_business_accounts (shop_id varchar(64) NOT NULL PRIMARY KEY,owner_user_id bigint unsigned NOT NULL,owner_name varchar(100) NULL,shop_label varchar(100) NOT NULL,unreported_balance bigint unsigned NOT NULL DEFAULT 0,risk_score tinyint unsigned NOT NULL DEFAULT 0,last_declaration_at datetime NULL,updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),KEY idx_ob_fiscal_account_owner(owner_user_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
[[CREATE TABLE IF NOT EXISTS ob_fiscal_deposits (id bigint unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,shop_id varchar(64) NOT NULL,user_id bigint unsigned NOT NULL,amount bigint unsigned NOT NULL,balance_before bigint unsigned NOT NULL,balance_after bigint unsigned NOT NULL,created_at timestamp NOT NULL DEFAULT current_timestamp(),KEY idx_ob_fiscal_deposit_shop(shop_id,created_at),KEY idx_ob_fiscal_deposit_user(user_id,created_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
[[CREATE TABLE IF NOT EXISTS ob_fiscal_declarations (id bigint unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,shop_id varchar(64) NOT NULL,owner_user_id bigint unsigned NOT NULL,owner_name varchar(100) NULL,shop_label varchar(100) NOT NULL,gross_amount bigint unsigned NOT NULL,tax_percent tinyint unsigned NOT NULL,tax_amount bigint unsigned NOT NULL,net_amount bigint unsigned NOT NULL,real_sales_7d bigint unsigned NOT NULL DEFAULT 0,risk_score tinyint unsigned NOT NULL DEFAULT 0,risk_reasons longtext NULL,status enum('reserving','crediting','credited','completed','flagged','failed','review') NOT NULL DEFAULT 'reserving',credit_token varchar(96) NULL,treasury_ledger_id bigint unsigned NULL,integrity_note varchar(255) NULL,police_status enum('new','reviewing','cleared','escalated') NOT NULL DEFAULT 'new',police_notes varchar(500) NULL,reviewed_by bigint unsigned NULL,reviewed_at datetime NULL,created_at timestamp NOT NULL DEFAULT current_timestamp(),settled_at datetime NULL,KEY idx_ob_fiscal_declaration_shop(shop_id,created_at),KEY idx_ob_fiscal_declaration_risk(risk_score,police_status,created_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
[[CREATE TABLE IF NOT EXISTS ob_fiscal_payroll (id bigint unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,shop_id varchar(64) NOT NULL,owner_user_id bigint unsigned NOT NULL,owner_name varchar(100) NULL,amount bigint unsigned NOT NULL,status enum('paying','paid','failed','review') NOT NULL DEFAULT 'paying',debit_token varchar(96) NULL,integrity_note varchar(255) NULL,created_at timestamp NOT NULL DEFAULT current_timestamp(),paid_at datetime NULL,KEY idx_ob_fiscal_payroll_shop(shop_id,created_at),KEY idx_ob_fiscal_payroll_owner(owner_user_id,created_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

CreateThread(function()
    if not OR.Database.waitForReady(30000) then print('[ob_fiscal] Banco indisponivel.');return end
    for _,sql in ipairs(schemas)do local result,err=OR.Database.query.await(sql);if result==nil then print('[ob_fiscal] Falha no schema: '..tostring(err));return end end
    local enumOk,enumError=OR.Database.query.await([[ALTER TABLE ob_fiscal_declarations MODIFY COLUMN status
        enum('reserving','crediting','credited','completed','flagged','failed','review') NOT NULL DEFAULT 'reserving']])
    if enumOk==nil then print('[ob_fiscal] Falha ao atualizar estados: '..tostring(enumError));return end
    OR.Database.update.await("UPDATE ob_fiscal_payroll SET status='review',integrity_note='Reinicio durante pagamento; revisar antes de repetir' WHERE status='paying'")
    OR.Database.update.await("UPDATE ob_fiscal_declarations SET status='failed',integrity_note='Reinicio antes da reserva fiscal; nenhum credito liberado' WHERE status='reserving'")
    OR.Database.update.await("UPDATE ob_fiscal_declarations SET status='review',integrity_note='Reinicio durante credito idempotente; conferir saldo empresarial' WHERE status IN ('crediting','credited')")
    ready=true;dispatchRegister();print('[ob_fiscal] Sistema fiscal pronto.')
end)

AddEventHandler('onResourceStart',function(name)if name=='ob_dispatch' then dispatchRegister()end end)
