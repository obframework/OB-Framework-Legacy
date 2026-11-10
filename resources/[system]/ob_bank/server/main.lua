local schemaReady=false
CreateThread(function()
 if not OR.Database.waitForReady(30000) then print('[ob_bank] Banco de dados indisponivel.') return end
 local ok,err=OR.Database.query.await([[CREATE TABLE IF NOT EXISTS ob_bank_accounts (user_id int NOT NULL PRIMARY KEY,balance bigint NOT NULL DEFAULT 0,updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
 if not ok then print(('[ob_bank] Falha nas contas: %s'):format(tostring(err))) return end
 ok,err=OR.Database.query.await([[CREATE TABLE IF NOT EXISTS ob_bank_cards (card_number char(16) NOT NULL PRIMARY KEY,owner_user_id int NOT NULL,pin_hash char(64) NOT NULL,active tinyint(1) NOT NULL DEFAULT 1,issued_at timestamp NOT NULL DEFAULT current_timestamp(),cancelled_at timestamp NULL DEFAULT NULL,INDEX idx_bank_cards_owner (owner_user_id,active)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
 if not ok then print(('[ob_bank] Falha nos cartoes: %s'):format(tostring(err))) return end
 ok,err=OR.Database.query.await([[CREATE TABLE IF NOT EXISTS ob_bank_transactions (id bigint unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,user_id int NOT NULL,kind varchar(24) NOT NULL,amount bigint NOT NULL,description varchar(120) NOT NULL,created_at timestamp NOT NULL DEFAULT current_timestamp(),INDEX idx_bank_transactions_user (user_id,id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
 if not ok then print(('[ob_bank] Falha no extrato: %s'):format(tostring(err))) return end
 schemaReady=true
end)
local function whole(v)return math.max(0,math.floor(tonumber(v)or 0))end
local function validPin(pin)return type(pin)=='string' and pin:match('^%d%d%d%d$')~=nil end
local function userId(s)return exports.ob_core:GetUserId(s)end
local function gate(s,key,limit,window)
 local allowed,retry=OR.Security.rateLimit(s,'bank:'..key,limit,window)
 return allowed,allowed and nil or ('Muitas tentativas. Aguarde %d segundos.'):format(math.max(1,math.ceil((retry or 1000)/1000)))
end
local function account(s)local id=userId(s);if not id or not schemaReady then return nil,'Conta bancaria indisponivel.' end;OR.Database.query.await('INSERT IGNORE INTO ob_bank_accounts (user_id) VALUES (?)',{id});return id end
local function cardItem(s)
 local inv=exports.ob_inventory:GetInventory(s);for _,item in pairs(inv and inv.items or{})do if item.name=='bank_card' and type(item.metadata)=='table' and type(item.metadata.cardNumber)=='string' then return item end end
end
local function cardFor(s)
 local item=cardItem(s);if not item then return nil,'Cartao bancario necessario.' end
 local card=OR.Database.single.await('SELECT card_number,owner_user_id,active FROM ob_bank_cards WHERE card_number=? LIMIT 1',{item.metadata.cardNumber})
 if not card or tonumber(card.active)~=1 then return nil,'Este cartao foi cancelado.' end
 return card
end
local function ownedCardWithPin(s,pin)
 local id=userId(s);local card,e=cardFor(s);if not card then return nil,e end
 if tonumber(card.owner_user_id)~=tonumber(id) then return nil,'Use o seu proprio cartao bancario.' end
 if not validPin(pin) then return nil,'Informe o PIN de 4 digitos.' end
 local valid=OR.Database.single.await('SELECT card_number FROM ob_bank_cards WHERE card_number=? AND owner_user_id=? AND pin_hash=SHA2(?,256) AND active=1 LIMIT 1',{card.card_number,id,pin})
 if not valid then return nil,'PIN incorreto.' end
 return card
end
local function nearBranch(s)local ped=GetPlayerPed(s);if not ped or ped<=0 then return false end;local p=GetEntityCoords(ped);for _,b in ipairs(BankConfig.Branches)do if #(p-vector3(b.coords.x,b.coords.y,b.coords.z))<=3.5 then return true end end;return false end
local function tx(s,k,v,d)local id=userId(s);if id and schemaReady then OR.Database.insert.await('INSERT INTO ob_bank_transactions (user_id,kind,amount,description) VALUES (?,?,?,?)',{id,k,whole(v),d})end end
local function credit(s,v)local id,e=account(s);v=whole(v);if not id or v<1 then return false,e or 'Valor invalido.' end;return OR.Database.update.await('UPDATE ob_bank_accounts SET balance=balance+? WHERE user_id=?',{v,id})~=nil end
local function debit(s,v,cardRequired)local id,e=account(s);v=whole(v);if not id or v<1 then return false,e or 'Valor invalido.' end;if cardRequired then local c,ce=cardFor(s);if not c then return false,ce end end;local changed=OR.Database.update.await('UPDATE ob_bank_accounts SET balance=balance-? WHERE user_id=? AND balance>=?',{v,id,v});return changed and changed>0 or false,changed and nil or 'Saldo bancario insuficiente.' end
local function pendingFines(id)
 if GetResourceState('ob_mdt')~='started' then return {} end
 local rows,err=OR.Database.query.await([[SELECT id,reason,fine,officer_name,DATE_FORMAT(created_at,'%d/%m/%Y %H:%i') AS created_at
  FROM ob_mdt_records WHERE suspect_user_id=? AND fine>0 AND fine_status='pending' ORDER BY id ASC]],{id})
 if rows==nil then print(('[ob_bank] Falha ao consultar multas do MDT: %s'):format(tostring(err))) return {} end
 local total=0;for _,row in ipairs(rows)do row.id=whole(row.id);row.fine=whole(row.fine);total=total+row.fine end
 return rows,total
end
local function cardNumber()return ('%04d%04d%04d%04d'):format(math.random(1000,9999),math.random(1000,9999),math.random(1000,9999),math.random(1000,9999))end
exports('PayWithCard',function(s,v,d)local card,e=cardFor(s);if not card then return false,e end;if tonumber(card.owner_user_id)~=tonumber(userId(s)) then return false,'PIN necessario para cartao de terceiro.' end;local ok,er=debit(s,v,false);if ok then tx(s,'card',v,d or 'Pagamento com cartao')end;return ok,er end)
exports('TransferByUserId',function(s,target,v)
 local allowed,limitError=gate(s,'transfer',6,30000);if not allowed then return false,limitError end
 local sender,targetId=userId(s),tonumber(target);v=whole(v)
 if not sender or not targetId or targetId<=0 or targetId==sender or v<1 then return false,'Dados da transferencia invalidos.' end
 local targetSource=exports.ob_core:GetSourceByUserId(targetId)
 if not targetSource then return false,'Jogador de ID '..targetId..' nao esta online.' end
 local card,e=cardFor(s);if not card or tonumber(card.owner_user_id)~=tonumber(sender) then return false,e or 'Use o seu cartao para transferir.' end
 local ok,er=debit(s,v,false);if not ok then return false,er end
 local targetAccount=account(targetSource);if not targetAccount then credit(s,v);return false,'Conta do destinatario indisponivel.' end
 local credited=OR.Database.update.await('UPDATE ob_bank_accounts SET balance=balance+? WHERE user_id=?',{v,targetId})
 if not credited then credit(s,v);return false,'Falha ao transferir.' end
 tx(s,'transfer_out',v,'Transferencia para ID '..targetId)
 OR.Database.insert.await('INSERT INTO ob_bank_transactions (user_id,kind,amount,description) VALUES (?,?,?,?)',{targetId,'transfer_in',v,'Transferencia recebida do ID '..sender})
 TriggerClientEvent('ob_phone:client:notification',targetSource,('Voce recebeu %s via transferencia.'):format(OR.FormatMoney(v)))
 return true,'Transferencia realizada.'
end)
exports('RefundToBank',function(s,v,d)local ok,e=credit(s,v);if ok then tx(s,'refund',v,d or 'Estorno')end;return ok,e end)
exports('CreditSalary',function(s,v,d)local ok,e=credit(s,v);if ok then tx(s,'salary',v,d or 'Salario')end;return ok,e end)
exports('GetBalance',function(s)local id=account(s);local r=id and OR.Database.single.await('SELECT balance FROM ob_bank_accounts WHERE user_id=?',{id});return whole(r and r.balance)end)
OR.Callback.register('getAccount',function(s)
 local id,e=account(s);if not id then return false,e end;local a=OR.Database.single.await('SELECT balance FROM ob_bank_accounts WHERE user_id=?',{id})or{};local c=cardFor(s);local rows=OR.Database.query.await('SELECT kind,amount,description,DATE_FORMAT(created_at,"%d/%m %H:%i") AS created_at FROM ob_bank_transactions WHERE user_id=? ORDER BY id DESC LIMIT 12',{id})or{};local week=OR.Database.single.await([[SELECT COALESCE(SUM(CASE WHEN kind IN ('deposit','refund','salary','transfer_in') THEN amount ELSE 0 END),0) AS incoming,COALESCE(SUM(CASE WHEN kind IN ('withdraw','card','pin_reset','transfer_out','fine_payment') THEN amount ELSE 0 END),0) AS outgoing FROM ob_bank_transactions WHERE user_id=? AND created_at>=CURDATE()-INTERVAL 6 DAY]],{id})or{};local fines,fineTotal=pendingFines(id)
 return true,{balance=whole(a.balance),cash=exports.ob_inventory:GetMoney(s,'money')or 0,card=c and {number=c.card_number,owner=tonumber(c.owner_user_id)==tonumber(id)}or nil,transactions=rows,week={incoming=whole(week.incoming),outgoing=whole(week.outgoing)},fines=fines,pendingFineTotal=whole(fineTotal)}
end)
OR.Callback.register('payFine',function(s,recordId)
 local allowed,limitError=gate(s,'pay_fine',5,15000);if not allowed then return false,limitError end
 local id,e=account(s);recordId=whole(recordId);if not id or recordId<1 then return false,e or 'Multa invalida.' end
 local card,cardError=cardFor(s);if not card then return false,cardError end
 if tonumber(card.owner_user_id)~=tonumber(id) then return false,'Use o seu proprio cartao para pagar multas.' end
 if GetResourceState('ob_mdt')~='started' then return false,'O sistema de multas esta indisponivel.' end
 local fine=OR.Database.single.await('SELECT id,fine,fine_status FROM ob_mdt_records WHERE id=? AND suspect_user_id=? LIMIT 1',{recordId,id})
 if not fine then return false,'Esta multa nao pertence ao seu personagem.' end
 local amount=whole(fine.fine);if amount<1 then return false,'Este registro nao possui multa.' end
 if fine.fine_status~='pending' then return false,'Esta multa ja foi paga.' end
 local changed,updateError=OR.Database.update.await([[UPDATE ob_bank_accounts a
  INNER JOIN ob_mdt_records r ON r.id=? AND r.suspect_user_id=a.user_id
  SET a.balance=a.balance-r.fine,r.fine_status='paid'
  WHERE a.user_id=? AND r.fine_status='pending' AND r.fine>0 AND a.balance>=r.fine]],{recordId,id})
 if changed==nil then return false,updateError or 'Nao foi possivel pagar a multa.' end
 if changed<1 then
  local balance=OR.Database.single.await('SELECT balance FROM ob_bank_accounts WHERE user_id=? LIMIT 1',{id})or{}
  if whole(balance.balance)<amount then return false,'Saldo bancario insuficiente.' end
  return false,'A multa nao esta mais pendente.'
 end
 tx(s,'fine_payment',amount,('Pagamento da multa MDT #%s'):format(recordId))
 return true,('Multa #%s paga. %s debitados da conta.'):format(recordId,OR.FormatMoney(amount))
end)
OR.Callback.register('deposit',function(s,v,pin)
 local allowed,limitError=gate(s,'deposit_pin',5,60000);if not allowed then return false,limitError end
 local card,e=ownedCardWithPin(s,pin);if not card then return false,e end;v=whole(v);if v<1 then return false,'Informe um valor valido.' end;if (exports.ob_inventory:GetMoney(s,'money')or 0)<v then return false,'Dinheiro fisico insuficiente.' end
 local ok,er=exports.ob_inventory:RemoveMoney(s,'money',v);if not ok then return false,er end;ok,er=credit(s,v);if not ok then exports.ob_inventory:AddMoney(s,'money',v);return false,er end;tx(s,'deposit',v,'Deposito em caixa eletronico');return true,'Deposito realizado.'
end)
OR.Callback.register('withdraw',function(s,v,pin)
 local allowed,limitError=gate(s,'withdraw_pin',5,60000);if not allowed then return false,limitError end
 local card,e=ownedCardWithPin(s,pin);if not card then return false,e end
 v=whole(v);local ok,er=debit(s,v,false);if not ok then return false,er end;ok,er=exports.ob_inventory:AddMoney(s,'money',v);if not ok then credit(s,v);return false,er or 'Sem espaco na mochila.' end;tx(s,'withdraw',v,'Saque em caixa eletronico');return true,'Saque realizado.'
end)
OR.Callback.register('issueCard',function(s,pin)
 local allowed,limitError=gate(s,'issue_card',3,60000);if not allowed then return false,limitError end
 if not nearBranch(s) then return false,'Emita o cartao falando com o gerente.' end;if not validPin(pin) then return false,'Crie um PIN de exatamente 4 numeros.' end
 local id,e=account(s);if not id then return false,e end
 OR.Database.update.await('UPDATE ob_bank_cards SET active=0,cancelled_at=CURRENT_TIMESTAMP WHERE owner_user_id=? AND active=1',{id})
 if (exports.ob_inventory:GetItemCount(s,'bank_card') or 0)>0 then exports.ob_inventory:RemoveItem(s,'bank_card',1) end
 local number=cardNumber();local ok,er=OR.Database.update.await('INSERT INTO ob_bank_cards (card_number,owner_user_id,pin_hash) VALUES (?, ?, SHA2(?,256))',{number,id,pin});if not ok or ok<1 then return false,er or 'Nao foi possivel emitir o cartao.' end
 local added,ae=exports.ob_inventory:AddItem(s,'bank_card',1,{cardNumber=number});if not added then OR.Database.update.await('UPDATE ob_bank_cards SET active=0,cancelled_at=CURRENT_TIMESTAMP WHERE card_number=?',{number});return false,ae or 'Sem espaco na mochila.' end;tx(s,'card_issue',0,'Cartao bancario emitido');return true,'Novo cartao emitido. O anterior foi cancelado.'
end)
OR.Callback.register('resetPin',function(s,pin)
 local allowed,limitError=gate(s,'reset_pin',3,60000);if not allowed then return false,limitError end
 if not nearBranch(s) then return false,'Fale com o gerente para alterar o PIN.' end;if not validPin(pin) then return false,'Crie um PIN de exatamente 4 numeros.' end;local card,e=cardFor(s);if not card then return false,e end
 local price=1500;local ok,er=debit(s,price,false);if not ok then return false,er end;local changed=OR.Database.update.await('UPDATE ob_bank_cards SET pin_hash=SHA2(?,256) WHERE card_number=?',{pin,card.card_number});if not changed then credit(s,price);return false,'Falha ao alterar PIN.' end;tx(s,'pin_reset',price,'Redefinicao de PIN');return true,('PIN alterado. %s foram cobrados.'):format(OR.FormatMoney(price))
end)
