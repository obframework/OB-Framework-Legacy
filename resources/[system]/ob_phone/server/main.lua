local ready=false
local phoneVisuals, phoneVisualSerial = {}, 0
local shareRequests, shareRequestSerial = {}, 0
local vehicleTrackCooldown = {}
local phoneCharging = {}
local function uid(s)return OBPhoneDevice.UserId(s)end
local function gate(s,key,limit,window)
 local allowed,retry=OR.Security.rateLimit(s,'phone:'..key,limit,window)
 return allowed,allowed and nil or ('Muitas solicitacoes. Aguarde %d segundos.'):format(math.max(1,math.ceil((retry or 1000)/1000)))
end
local function num()return ('555%06d'):format(math.random(0,999999))end
OBPhoneService = { uid = uid, deviceUid = OBPhoneDevice.DeviceUserId, gate = gate, hasSignal = OBPhoneDevice.HasSignal }
local function phone(id)
 local row=OR.Database.single.await('SELECT phone_number,battery FROM ob_phone_numbers WHERE user_id=?',{id});if row then return row end
 for _=1,15 do
  local n=num()
  OR.Database.update.await('INSERT IGNORE INTO ob_phone_numbers (user_id,phone_number,battery) VALUES (?,?,100)',{id,n})
  local made=OR.Database.single.await('SELECT phone_number,battery FROM ob_phone_numbers WHERE user_id=?',{id})
  if made then return made end
 end
 return nil
end
CreateThread(function()
 if not OR.Database.waitForReady(30000)then return end
 local sql={[[CREATE TABLE IF NOT EXISTS ob_phone_numbers (user_id int NOT NULL PRIMARY KEY,phone_number varchar(16) NOT NULL UNIQUE,battery tinyint unsigned NOT NULL DEFAULT 100,updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],[[CREATE TABLE IF NOT EXISTS ob_phone_contacts (user_id int NOT NULL,contact_number varchar(16) NOT NULL,contact_name varchar(40) NOT NULL,PRIMARY KEY(user_id,contact_number)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],[[CREATE TABLE IF NOT EXISTS ob_phone_messages (id bigint unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,sender_id int NOT NULL,recipient_phone varchar(20) NOT NULL,body varchar(500) NOT NULL,created_at timestamp NOT NULL DEFAULT current_timestamp(),INDEX idx_phone_recipient(recipient_phone,id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],[[CREATE TABLE IF NOT EXISTS ob_phone_profiles (user_id int NOT NULL PRIMARY KEY,username varchar(24) NOT NULL UNIQUE,display_name varchar(32) NOT NULL,created_at timestamp NOT NULL DEFAULT current_timestamp()) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],[[CREATE TABLE IF NOT EXISTS ob_phone_posts (id bigint unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,user_id int NOT NULL,body varchar(350) NOT NULL,created_at timestamp NOT NULL DEFAULT current_timestamp()) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]}
 sql[#sql+1] = [[CREATE TABLE IF NOT EXISTS ob_phone_calls (id bigint unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,caller_id int NOT NULL,callee_id int NOT NULL,caller_number varchar(16) NOT NULL,callee_number varchar(16) NOT NULL,call_type varchar(8) NOT NULL DEFAULT 'voice',status varchar(24) NOT NULL,duration int unsigned NOT NULL DEFAULT 0,created_at timestamp NOT NULL DEFAULT current_timestamp(),INDEX idx_call_caller(caller_id,id),INDEX idx_call_callee(callee_id,id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
 sql[#sql+1] = [[CREATE TABLE IF NOT EXISTS ob_phone_apps (user_id int NOT NULL,app_id varchar(48) NOT NULL,installed tinyint(1) NOT NULL DEFAULT 1,updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),PRIMARY KEY(user_id,app_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
 sql[#sql+1] = [[CREATE TABLE IF NOT EXISTS ob_phone_profile_media (user_id int NOT NULL PRIMARY KEY,avatar_url varchar(700) DEFAULT NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
 sql[#sql+1] = [[CREATE TABLE IF NOT EXISTS ob_phone_device_profiles (user_id int NOT NULL PRIMARY KEY,avatar_url varchar(700) DEFAULT NULL,updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
 sql[#sql+1] = [[CREATE TABLE IF NOT EXISTS ob_phone_post_media (post_id bigint unsigned NOT NULL PRIMARY KEY,media_url varchar(700) NOT NULL,media_type enum('photo','video') NOT NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
 sql[#sql+1] = [[CREATE TABLE IF NOT EXISTS ob_phone_follows (follower_id int NOT NULL,followed_id int NOT NULL,created_at timestamp NOT NULL DEFAULT current_timestamp(),PRIMARY KEY(follower_id,followed_id),INDEX idx_phone_followed(followed_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
 sql[#sql+1] = [[CREATE TABLE IF NOT EXISTS ob_phone_post_likes (post_id bigint unsigned NOT NULL,user_id int NOT NULL,created_at timestamp NOT NULL DEFAULT current_timestamp(),PRIMARY KEY(post_id,user_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
 sql[#sql+1] = [[CREATE TABLE IF NOT EXISTS ob_phone_post_comments (id bigint unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,post_id bigint unsigned NOT NULL,user_id int NOT NULL,body varchar(180) NOT NULL,created_at timestamp NOT NULL DEFAULT current_timestamp(),INDEX idx_phone_comment_post(post_id,id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
 sql[#sql+1] = [[CREATE TABLE IF NOT EXISTS ob_phone_stories (id bigint unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,user_id int NOT NULL,media_url varchar(700) NOT NULL,media_type enum('photo','video') NOT NULL,created_at timestamp NOT NULL DEFAULT current_timestamp(),expires_at timestamp NOT NULL,INDEX idx_phone_story_expiry(expires_at),INDEX idx_phone_story_user(user_id,id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
 sql[#sql+1] = [[CREATE TABLE IF NOT EXISTS ob_phone_story_views (story_id bigint unsigned NOT NULL,user_id int NOT NULL,viewed_at timestamp NOT NULL DEFAULT current_timestamp(),PRIMARY KEY(story_id,user_id),INDEX idx_story_view_user(user_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
 sql[#sql+1] = [[CREATE TABLE IF NOT EXISTS ob_phone_media (id bigint unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,user_id int NOT NULL,remote_id varchar(160) NOT NULL,media_type enum('photo','video') NOT NULL,media_url varchar(700) NOT NULL,created_at timestamp NOT NULL DEFAULT current_timestamp(),INDEX idx_phone_media_user(user_id,id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
 sql[#sql+1] = [[CREATE TABLE IF NOT EXISTS ob_phone_dark_groups (id bigint unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,owner_id int NOT NULL,name varchar(40) NOT NULL,invite_code varchar(20) NOT NULL UNIQUE,created_at timestamp NOT NULL DEFAULT current_timestamp(),INDEX idx_dark_owner(owner_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
 sql[#sql+1] = [[CREATE TABLE IF NOT EXISTS ob_phone_dark_members (group_id bigint unsigned NOT NULL,user_id int NOT NULL,joined_at timestamp NOT NULL DEFAULT current_timestamp(),PRIMARY KEY(group_id,user_id),INDEX idx_dark_member(user_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
 sql[#sql+1] = [[CREATE TABLE IF NOT EXISTS ob_phone_dark_messages (id bigint unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,group_id bigint unsigned NOT NULL,user_id int NOT NULL,body varchar(500) NOT NULL DEFAULT '',media_url varchar(700) DEFAULT NULL,media_type varchar(12) NOT NULL DEFAULT 'text',created_at timestamp NOT NULL DEFAULT current_timestamp(),INDEX idx_dark_messages(group_id,id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
 sql[#sql+1] = [[CREATE TABLE IF NOT EXISTS ob_phone_settings (user_id int NOT NULL PRIMARY KEY,airplane_mode tinyint(1) NOT NULL DEFAULT 0,notifications tinyint(1) NOT NULL DEFAULT 1,darkchat_notifications tinyint(1) NOT NULL DEFAULT 1,ringtone varchar(20) NOT NULL DEFAULT 'classic',share_name varchar(40) DEFAULT NULL,updated_at timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
 sql[#sql+1] = [[CREATE TABLE IF NOT EXISTS ob_phone_message_groups (id bigint unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,owner_id int NOT NULL,name varchar(40) NOT NULL,invite_permission varchar(12) NOT NULL DEFAULT 'moderators',created_at timestamp NOT NULL DEFAULT current_timestamp(),INDEX idx_message_group_owner(owner_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
 sql[#sql+1] = [[CREATE TABLE IF NOT EXISTS ob_phone_message_group_members (group_id bigint unsigned NOT NULL,user_id int NOT NULL,role varchar(12) NOT NULL DEFAULT 'member',joined_at timestamp NOT NULL DEFAULT current_timestamp(),PRIMARY KEY(group_id,user_id),INDEX idx_message_member(user_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
 sql[#sql+1] = [[CREATE TABLE IF NOT EXISTS ob_phone_message_group_messages (id bigint unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,group_id bigint unsigned NOT NULL,user_id int NOT NULL,body varchar(500) NOT NULL DEFAULT '',message_type varchar(12) NOT NULL DEFAULT 'text',media_url varchar(700) NOT NULL DEFAULT '',created_at timestamp NOT NULL DEFAULT current_timestamp(),INDEX idx_message_group_messages(group_id,id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
 for _,q in ipairs(sql)do if not OR.Database.query.await(q)then return end end
 if not OR.Database.single.await("SHOW COLUMNS FROM ob_phone_profiles LIKE 'display_name'") then
  if OR.Database.query.await("ALTER TABLE ob_phone_profiles ADD COLUMN display_name varchar(32) NULL AFTER username")==nil then return end
 end
 local messageColumns={
  {'message_type',"varchar(12) NOT NULL DEFAULT 'text' AFTER body"},
  {'media_url','varchar(700) NULL AFTER message_type'},
  {'contact_name','varchar(40) NULL AFTER media_url'},
  {'contact_number','varchar(16) NULL AFTER contact_name'}
 }
 for _,migration in ipairs(messageColumns)do
  local column,definition=migration[1],migration[2]
  if not OR.Database.single.await("SHOW COLUMNS FROM ob_phone_messages LIKE '"..column.."'")then
   if OR.Database.query.await('ALTER TABLE ob_phone_messages ADD COLUMN '..column..' '..definition)==nil then return end
  end
 end
 if not OR.Database.single.await("SHOW COLUMNS FROM ob_phone_settings LIKE 'darkchat_notifications'")then
  if OR.Database.query.await("ALTER TABLE ob_phone_settings ADD COLUMN darkchat_notifications tinyint(1) NOT NULL DEFAULT 1 AFTER notifications")==nil then return end
 end
 if not OR.Database.single.await("SHOW COLUMNS FROM ob_phone_settings LIKE 'share_name'")then
  if OR.Database.query.await("ALTER TABLE ob_phone_settings ADD COLUMN share_name varchar(40) NULL AFTER ringtone")==nil then return end
 end
 if not OR.Database.single.await("SHOW COLUMNS FROM ob_phone_calls LIKE 'call_type'")then
  if OR.Database.query.await("ALTER TABLE ob_phone_calls ADD COLUMN call_type varchar(8) NOT NULL DEFAULT 'voice' AFTER callee_number")==nil then return end
 end
 OR.Database.update.await("UPDATE ob_phone_profiles SET display_name=username WHERE display_name IS NULL OR display_name='' ")
 ready=true
end)
OBPhoneService.getPhone = function(id) if ready then return phone(id) end end
OBPhoneService.isReady = function() return ready end
AddEventHandler('ob_core:server:characterSelected',function(_,character)
 if ready and type(character)=='table' and character.userId then phone(character.userId) end
end)
RegisterNetEvent('ob_phone:server:phoneVisual',function(active)
 local src=tonumber(source);if not src or not GetPlayerName(src) then return end
 if not OR.Security.rateLimit(src,'phone:visual',10,5000) then return end
 if active==true then
  if not uid(src) or (exports.ob_inventory:GetItemCount(src,'phone')or 0)<1 then return end
  phoneVisualSerial=phoneVisualSerial+1;phoneVisuals[src]=phoneVisualSerial
  Player(src).state:set('ob:phoneVisual',{token=phoneVisualSerial},true)
 else
  phoneVisuals[src]=nil;Player(src).state:set('ob:phoneVisual',nil,true)
 end
end)
AddEventHandler('playerDropped',function()
 local dropped=tonumber(source);phoneVisuals[dropped]=nil
 for token,request in pairs(shareRequests)do if request.source==dropped or request.target==dropped then shareRequests[token]=nil end end
end)
AddEventHandler('onResourceStop',function(resource)
 if resource~=GetCurrentResourceName() then return end
 for src in pairs(phoneVisuals) do if GetPlayerName(src) then Player(src).state:set('ob:phoneVisual',nil,true) end end
end)
local function data(s)
 local id=uid(s);if not id or not ready then return nil,'Celular indisponivel.' end;local p=phone(id);if not p then return nil,'Nao foi possivel criar numero.' end
 local recent=OR.Database.query.await([[SELECT CASE WHEN m.sender_id=? THEN 'out' ELSE 'in' END AS direction,CASE WHEN m.sender_id=? THEN m.recipient_phone ELSE n.phone_number END AS other_phone,m.body,m.message_type,m.media_url,m.contact_name,m.contact_number,DATE_FORMAT(m.created_at,'%d/%m %H:%i') AS created_at FROM ob_phone_messages m LEFT JOIN ob_phone_numbers n ON n.user_id=m.sender_id WHERE m.sender_id=? OR m.recipient_phone=? ORDER BY m.id DESC LIMIT 80]],{id,id,id,p.phone_number})or{}
 local msgs={};for i=#recent,1,-1 do msgs[#msgs+1]=recent[i] end
 local contacts=OR.Database.query.await([[SELECT c.contact_number,c.contact_name,pm.avatar_url
  FROM ob_phone_contacts c LEFT JOIN ob_phone_numbers n ON n.phone_number=c.contact_number
  LEFT JOIN ob_phone_device_profiles pm ON pm.user_id=n.user_id
  WHERE c.user_id=? ORDER BY c.contact_name]],{id})or{}
 local profile=OR.Database.single.await([[SELECT p.user_id,p.username,p.display_name,pm.avatar_url,
  (SELECT COUNT(*) FROM ob_phone_follows f WHERE f.followed_id=p.user_id) AS followers,
  (SELECT COUNT(*) FROM ob_phone_follows f WHERE f.follower_id=p.user_id) AS following
  FROM ob_phone_profiles p LEFT JOIN ob_phone_profile_media pm ON pm.user_id=p.user_id WHERE p.user_id=?]],{id})or{}
 if not profile.avatar_url then profile.avatar_url=OR.Database.scalar.await('SELECT avatar_url FROM ob_phone_profile_media WHERE user_id=?',{id}) end
 local posts,stories={},{}
 if profile.user_id then
  posts=OR.Database.query.await([[SELECT p.id,p.user_id,COALESCE(pr.username,CONCAT('usuario',p.user_id)) AS username,COALESCE(NULLIF(pr.display_name,''),pr.username,CONCAT('Usuario ',p.user_id)) AS display_name,pm.avatar_url,p.body,m.media_url,m.media_type,
  (SELECT COUNT(*) FROM ob_phone_post_likes l WHERE l.post_id=p.id) AS likes,
  (SELECT COUNT(*) FROM ob_phone_post_comments c WHERE c.post_id=p.id) AS comments,
  EXISTS(SELECT 1 FROM ob_phone_post_likes ml WHERE ml.post_id=p.id AND ml.user_id=?) AS liked,
  EXISTS(SELECT 1 FROM ob_phone_follows mf WHERE mf.follower_id=? AND mf.followed_id=p.user_id) AS followed,
  DATE_FORMAT(p.created_at,'%d/%m %H:%i') AS created_at
  FROM ob_phone_posts p LEFT JOIN ob_phone_profiles pr ON pr.user_id=p.user_id
  LEFT JOIN ob_phone_profile_media pm ON pm.user_id=p.user_id LEFT JOIN ob_phone_post_media m ON m.post_id=p.id
  ORDER BY p.id DESC LIMIT 30]],{id,id})or{}
  stories=OR.Database.query.await([[SELECT s.id,s.user_id,s.media_url,s.media_type,pr.username,COALESCE(NULLIF(pr.display_name,''),pr.username) AS display_name,pm.avatar_url,
  (s.user_id=? OR EXISTS(SELECT 1 FROM ob_phone_story_views sv WHERE sv.story_id=s.id AND sv.user_id=?)) AS viewed,
  TIMESTAMPDIFF(SECOND,NOW(),s.expires_at) AS seconds_left
  FROM ob_phone_stories s JOIN ob_phone_profiles pr ON pr.user_id=s.user_id
  LEFT JOIN ob_phone_profile_media pm ON pm.user_id=s.user_id WHERE s.expires_at>NOW() ORDER BY s.id DESC LIMIT 40]],{id,id})or{}
 end
 local appRows=OR.Database.query.await('SELECT app_id,installed FROM ob_phone_apps WHERE user_id=?',{id})or{}
 local installedApps={};for _,row in ipairs(appRows)do installedApps[row.app_id]=tonumber(row.installed)==1 end
 local ownerName=profile.display_name or profile.username
 if not ownerName and tonumber(OBPhoneDevice.HolderId(s))==tonumber(id) and type(GetPlayerName)=='function'then ownerName=GetPlayerName(s)end
 local settings=OR.Database.single.await('SELECT airplane_mode,notifications,darkchat_notifications,ringtone,share_name FROM ob_phone_settings WHERE user_id=?',{id})or{airplane_mode=0,notifications=1,darkchat_notifications=1,ringtone='classic'}
 local deviceAvatar=OR.Database.scalar.await('SELECT avatar_url FROM ob_phone_device_profiles WHERE user_id=?',{id})
 local shareName=settings.share_name or ownerName or('Contato '..id)
 return {number=p.phone_number,ownerName=ownerName or('Contato '..id),shareName=shareName,battery=tonumber(p.battery)or 0,messages=msgs,contacts=contacts,profile=profile,deviceAvatar=deviceAvatar,posts=posts,stories=stories,installedApps=installedApps,settings=settings,userId=id}
end
OR.Callback.register('data',function(s)local d,e=data(s);return d~=nil,d or e end)
OR.Callback.register('nearbyContacts',function(s,targets)
 local allowed,limitError=gate(s,'nearbyContacts',12,30000);if not allowed then return false,limitError end
 if type(targets)~='table'then return true,{}end
 local sourcePed=GetPlayerPed(s);if not sourcePed or sourcePed<=0 then return true,{}end
 local origin,rows,seen=GetEntityCoords(sourcePed),{},{}
 for index=1,math.min(#targets,16)do
  local target=tonumber(targets[index])
  if target and target~=s and not seen[target] and GetPlayerName(target)then
   seen[target]=true
   local targetPed=GetPlayerPed(target)
   if targetPed and targetPed>0 and phoneVisuals[target] and #(GetEntityCoords(targetPed)-origin)<=(tonumber(OBPhoneConfig.ShareDistance)or 3.0) then
    local targetId=uid(target)
    if targetId then
     local contact=OR.Database.single.await([[SELECT COALESCE(NULLIF(st.share_name,''),NULLIF(pr.display_name,''),pr.username,?) AS name,dp.avatar_url
      FROM ob_phone_numbers n LEFT JOIN ob_phone_settings st ON st.user_id=n.user_id LEFT JOIN ob_phone_profiles pr ON pr.user_id=n.user_id
      LEFT JOIN ob_phone_device_profiles dp ON dp.user_id=n.user_id WHERE n.user_id=? LIMIT 1]],{'Contato '..targetId,targetId})
     rows[#rows+1]={serverId=target,name=contact and contact.name or GetPlayerName(target)or('Contato '..targetId),avatar_url=contact and contact.avatar_url or nil}
    end
   end
  end
 end
 return true,rows
end)
OR.Callback.register('saveBattery',function(s,value)
 local allowed,limitError=gate(s,'battery',12,60000);if not allowed then return false,limitError end
 local id=uid(s);value=math.max(0,math.min(100,math.floor(tonumber(value)or 0)));if not id or not ready then return false,'Celular indisponivel.' end
 local current=tonumber(OR.Database.scalar.await('SELECT battery FROM ob_phone_numbers WHERE user_id=?',{id}))or 0
 if phoneCharging[id] then return true end
 -- O cliente informa apenas consumo. Aumentos pertencem ao callback charge,
 -- que valida e remove um powerbank no servidor.
 value=math.min(value,current)
 OR.Database.update.await('UPDATE ob_phone_numbers SET battery=? WHERE user_id=?',{value,id});return true
end)
OR.Callback.register('charge',function(s,slot)
 local item=exports.ob_inventory:GetItemAtSlot(s,slot)
 if not item or item.name~='powerbank'then return false,'O powerbank foi movido ou nao esta mais nesse slot.'end
 local id=OBPhoneDevice.ResolveOwner(s);if not id then return false,'O celular esta sem sinal ou foi desativado.' end
 if phoneCharging[id] then return false,'Esse celular ja esta carregando.'end
 local own=phone(id);if not own then return false,'Nao foi possivel acessar a bateria do celular.'end
 local current=tonumber(own.battery)or 0
 if current>=100 then return false,'A bateria do celular ja esta cheia.'end
 local removed,errorMessage=exports.ob_inventory:ConsumeItemAtSlot(s,slot,'powerbank',1)
 if not removed then return false,errorMessage or 'Nao foi possivel consumir o powerbank.'end
 local charge={};phoneCharging[id]=charge
 TriggerClientEvent('ob_phone:client:notification',s,'Powerbank conectado. O celular esta carregando.','phone')
 CreateThread(function()
  local charging=OBPhoneConfig.Charging or{}
  local step=math.max(1,math.min(100,math.floor(tonumber(charging.Step)or 10)))
  local interval=math.max(1,math.floor(tonumber(charging.IntervalSeconds)or 10))*1000
  while phoneCharging[id]==charge do
   Wait(interval)
   local changed=OR.Database.update.await('UPDATE ob_phone_numbers SET battery=LEAST(100,battery+?) WHERE user_id=?',{step,id})
   if changed==nil then
    phoneCharging[id]=nil
    local holder=OBPhoneDevice.HolderSourceForUser(id)
    if holder then TriggerClientEvent('ob_phone:client:notification',holder,'O carregamento foi interrompido.','phone')end
    return
   end
   local battery=tonumber(OR.Database.scalar.await('SELECT battery FROM ob_phone_numbers WHERE user_id=?',{id}))or 0
   local holder=OBPhoneDevice.HolderSourceForUser(id)
   if holder then TriggerClientEvent('ob_phone:client:chargingProgress',holder,battery,battery>=100)end
   if battery>=100 then
    phoneCharging[id]=nil
    if holder then TriggerClientEvent('ob_phone:client:notification',holder,'Celular carregado. Bateria em 100%.','phone')end
    return
   end
  end
 end)
 return true,{battery=current,message='Powerbank conectado. O celular esta carregando.'}
end)
OR.Callback.register('setAppInstalled',function(s,appId,installed)
 local allowed,limitError=gate(s,'apps',12,30000);if not allowed then return false,limitError end
 local id=uid(s);appId=tostring(appId or ''):lower()
 if not id or not appId:match('^[a-z0-9][a-z0-9_.%-]+$') or #appId>48 or type(installed)~='boolean' then return false,'Aplicativo invalido.' end
 local placement=tostring((OBPhoneConfig.Apps or{})[appId]or''):lower()
 if placement=='disabled'or(placement=='default'and installed==false)then return false,'Este aplicativo e controlado pela configuracao do servidor.' end
 local saved=OR.Database.update.await('INSERT INTO ob_phone_apps (user_id,app_id,installed) VALUES (?,?,?) ON DUPLICATE KEY UPDATE installed=VALUES(installed)',{id,appId,installed and 1 or 0})
 return saved~=nil,saved~=nil and(installed and 'Aplicativo instalado.' or 'Aplicativo removido.')or'Nao foi possivel atualizar o aplicativo.'
end)
OR.Callback.register('saveContact',function(s,n,name)local allowed,limitError=gate(s,'contact',15,30000);if not allowed then return false,limitError end;local id=uid(s);n=tostring(n or ''):gsub('%D','');name=tostring(name or ''):sub(1,40);if not id or #n<5 or #name<1 then return false,'Contato invalido.' end;OR.Database.query.await('INSERT INTO ob_phone_contacts (user_id,contact_number,contact_name) VALUES (?,?,?) ON DUPLICATE KEY UPDATE contact_name=VALUES(contact_name)',{id,n,name});return true,'Contato salvo.' end)
OR.Callback.register('setUsername',function(s,username,displayName)
 local allowed,limitError=gate(s,'username',5,60000);if not allowed then return false,limitError end
 local id=uid(s);username=tostring(username or ''):lower():gsub('%s+','');displayName=tostring(displayName or ''):gsub('[%c]',''):match('^%s*(.-)%s*$') or''
 if not id or #displayName<2 or #displayName>32 then return false,'Informe um nome de 2 a 32 caracteres.' end
 local existing=OR.Database.single.await('SELECT username FROM ob_phone_profiles WHERE user_id=? LIMIT 1',{id})
 if existing then
  local result,errorMessage=OR.Database.update.await('UPDATE ob_phone_profiles SET display_name=? WHERE user_id=?',{displayName,id})
  return result~=nil,result~=nil and'Nome atualizado.'or(errorMessage or'Nao foi possivel atualizar o nome.')
 end
 if not username:match('^[a-z0-9_.]+$') or #username<3 or #username>24 then return false,'Use de 3 a 24 letras, numeros, ponto ou _ no @.' end
 local owner=OR.Database.single.await('SELECT user_id FROM ob_phone_profiles WHERE username=? LIMIT 1',{username})
 if owner and tonumber(owner.user_id)~=tonumber(id) then return false,'Esse @ ja esta em uso.' end
 local result,errorMessage=OR.Database.update.await('INSERT INTO ob_phone_profiles (user_id,username,display_name) VALUES (?,?,?)',{id,username,displayName})
 return result~=nil,result~=nil and'Conta @'..username..' criada. O @ nao podera ser alterado.'or(errorMessage or'Nao foi possivel criar a conta.')
end)
local notifyUser
OR.Callback.register('sendMessage',function(s,to,body,messageType,payload)
 local allowed,limitError=gate(s,'message',8,30000);if not allowed then return false,limitError end
 local id=uid(s);to=tostring(to or ''):gsub('%D','');body=tostring(body or ''):sub(1,500);payload=type(payload)=='table' and payload or{}
 messageType=tostring(messageType or 'text'):lower()
 if not ({text=true,contact=true,photo=true,video=true,audio=true,location=true})[messageType] then return false,'Tipo de mensagem invalido.' end
 if not id or not ready or #to<5 or #to>16 then return false,'Numero ou mensagem invalida.' end
 local recipient=OR.Database.single.await('SELECT user_id FROM ob_phone_numbers WHERE phone_number=?',{to})
 if not recipient then return false,'Numero nao encontrado.' end
 local own=phone(id)
 if not own or (tonumber(own.battery)or 0)<=0 or (exports.ob_inventory:GetItemCount(s,'phone')or 0)<1 or uid(s)~=id then return false,'Celular indisponivel.' end
 -- Nunca use nil no meio deste array: tabelas Lua esparsas perdem os campos
 -- finais e o adaptador recebe menos parametros que os sete placeholders.
 local mediaUrl,contactName,contactNumber='','',''
 if messageType=='text' then
  if not body:match('%S') then return false,'Escreva uma mensagem.' end
 elseif messageType=='contact' then
  contactName=tostring(payload.contactName or ''):gsub('[%c]',''):sub(1,40)
  contactNumber=tostring(payload.contactNumber or ''):gsub('%D',''):sub(1,16)
  if #contactName<1 or #contactNumber<5 then return false,'Contato invalido.' end
  body='Contato: '..contactName
 elseif messageType=='location' then
  local x,y=tostring(payload.location or''):match('^(-?%d+%.?%d*),(-?%d+%.?%d*)$')
  x,y=tonumber(x),tonumber(y)
  if not x or not y or math.abs(x)>10000 or math.abs(y)>10000 then return false,'Localizacao invalida.' end
  mediaUrl=('%0.3f,%0.3f'):format(x,y);body='Localizacao compartilhada'
 else
  local mediaId=math.floor(tonumber(payload.mediaId)or 0)
  local media=OR.Database.single.await('SELECT media_url,media_type FROM ob_phone_media WHERE id=? AND user_id=? LIMIT 1',{mediaId,id})
  if not media or media.media_type~=messageType then return false,'Midia invalida.' end
  mediaUrl=media.media_url;body=body:match('%S') and body or (messageType=='audio' and 'Audio' or messageType=='video' and 'Video' or 'Foto')
 end
 local saved=OR.Database.insert.await('INSERT INTO ob_phone_messages (sender_id,recipient_phone,body,message_type,media_url,contact_name,contact_number) VALUES (?,?,?,?,?,?,?)',{id,to,body,messageType,mediaUrl,contactName,contactNumber})
 if saved then
  notifyUser(recipient.user_id,'Nova mensagem de '..own.phone_number..'.','messages')
 end
 return saved and true or false,saved and 'Mensagem enviada.' or 'Nao foi possivel enviar.'
end)
local function ownedMedia(id,mediaId,variantId)
 mediaId=math.floor(tonumber(mediaId)or 0);if mediaId<1 then return nil end
 variantId=math.floor(tonumber(variantId)or 0)
 if variantId>0 then
  return OR.Database.single.await([[SELECT v.media_url,'photo' AS media_type FROM ob_phone_media_variants v
   JOIN ob_phone_media m ON m.id=v.source_media_id AND m.user_id=v.user_id
   WHERE v.id=? AND v.user_id=? AND v.source_media_id=? LIMIT 1]],{variantId,id,mediaId})
 end
 return OR.Database.single.await('SELECT media_url,media_type FROM ob_phone_media WHERE id=? AND user_id=? LIMIT 1',{mediaId,id})
end
notifyUser=function(userId,text,kind)
 userId=tonumber(userId);if not userId then return end
 local column=kind=='darkchat'and'darkchat_notifications'or'notifications'
 local enabled=OR.Database.scalar.await('SELECT '..column..' FROM ob_phone_settings WHERE user_id=?',{userId})
 if enabled~=nil and tonumber(enabled)==0 then return end
  local foundPeer=OBPhoneDevice.SourceForUser(userId) or exports.ob_core:GetSourceByUserId(userId)
  local peer=foundPeer and tonumber(foundPeer) or nil
 if peer and GetPlayerName(peer)then TriggerClientEvent('ob_phone:client:notification',peer,tostring(text or''),kind or'phone')end
end
OR.Callback.register('post',function(s,body,mediaId)
 local allowed,limitError=gate(s,'post',3,60000);if not allowed then return false,limitError end
 local id=uid(s);body=tostring(body or ''):sub(1,350);local media=ownedMedia(id,mediaId)
 if not id or (not body:match('%S') and not media) then return false,'Escreva algo ou selecione uma foto/video.' end
 if not OR.Database.single.await('SELECT user_id FROM ob_phone_profiles WHERE user_id=?',{id})then return false,'Crie seu @ antes de publicar.' end
 local postId=OR.Database.insert.await('INSERT INTO ob_phone_posts (user_id,body) VALUES (?,?)',{id,body})
 if postId and media then OR.Database.insert.await('INSERT INTO ob_phone_post_media (post_id,media_url,media_type) VALUES (?,?,?)',{postId,media.media_url,media.media_type}) end
 if postId then
  local author=OR.Database.scalar.await("SELECT COALESCE(NULLIF(display_name,''),username) FROM ob_phone_profiles WHERE user_id=?",{id})or'Um perfil'
  local followers=OR.Database.query.await('SELECT follower_id FROM ob_phone_follows WHERE followed_id=?',{id})or{}
  for _,row in ipairs(followers)do notifyUser(row.follower_id,author..' fez uma nova publicacao.','obgram')end
 end
 return postId and true or false,postId and 'Publicacao enviada.' or 'Falha ao publicar.'
end)
OR.Callback.register('obgramAction',function(s,action,payload)
 local allowed,limitError=gate(s,'obgram',20,60000);if not allowed then return false,limitError end
 local id=uid(s);payload=type(payload)=='table' and payload or{};if not id then return false,'Perfil indisponivel.' end
 if not OR.Database.scalar.await('SELECT 1 FROM ob_phone_profiles WHERE user_id=?',{id}) then return false,'Crie sua conta no Obgram para continuar.' end
 if action=='like' then
  local postId=math.floor(tonumber(payload.postId)or 0);if postId<1 then return false,'Publicacao invalida.' end
  local exists=OR.Database.scalar.await('SELECT 1 FROM ob_phone_post_likes WHERE post_id=? AND user_id=?',{postId,id})
  if exists then OR.Database.update.await('DELETE FROM ob_phone_post_likes WHERE post_id=? AND user_id=?',{postId,id}) else
   OR.Database.insert.await('INSERT IGNORE INTO ob_phone_post_likes (post_id,user_id) VALUES (?,?)',{postId,id})
   local owner=OR.Database.scalar.await('SELECT user_id FROM ob_phone_posts WHERE id=?',{postId})
   if owner and tonumber(owner)~=tonumber(id)then local actor=OR.Database.scalar.await("SELECT COALESCE(NULLIF(display_name,''),username) FROM ob_phone_profiles WHERE user_id=?",{id})or'Alguem';notifyUser(owner,actor..' curtiu sua publicacao.','obgram')end
  end
  return true,{liked=not exists}
 elseif action=='follow' then
  local target=math.floor(tonumber(payload.userId)or 0);if target<1 or target==id then return false,'Perfil invalido.' end
  if not OR.Database.scalar.await('SELECT 1 FROM ob_phone_profiles WHERE user_id=?',{target}) then return false,'Perfil nao encontrado.' end
  local exists=OR.Database.scalar.await('SELECT 1 FROM ob_phone_follows WHERE follower_id=? AND followed_id=?',{id,target})
  if exists then OR.Database.update.await('DELETE FROM ob_phone_follows WHERE follower_id=? AND followed_id=?',{id,target}) else OR.Database.insert.await('INSERT IGNORE INTO ob_phone_follows (follower_id,followed_id) VALUES (?,?)',{id,target}) end
  return true,{followed=not exists}
 elseif action=='comments' then
  local postId=math.floor(tonumber(payload.postId)or 0);if postId<1 then return false,'Publicacao invalida.' end
  local rows=OR.Database.query.await([[SELECT c.body,pr.username,COALESCE(NULLIF(pr.display_name,''),pr.username) AS display_name,pm.avatar_url,DATE_FORMAT(c.created_at,'%d/%m %H:%i') AS created_at
   FROM ob_phone_post_comments c JOIN ob_phone_profiles pr ON pr.user_id=c.user_id
   LEFT JOIN ob_phone_profile_media pm ON pm.user_id=c.user_id WHERE c.post_id=? ORDER BY c.id DESC LIMIT 50]],{postId})or{}
  return true,rows
 elseif action=='comment' then
  local postId=math.floor(tonumber(payload.postId)or 0);local body=tostring(payload.body or ''):sub(1,180)
  if postId<1 or not body:match('%S') then return false,'Comentario invalido.' end
  if not OR.Database.scalar.await('SELECT 1 FROM ob_phone_posts WHERE id=?',{postId}) then return false,'Publicacao nao encontrada.' end
  OR.Database.insert.await('INSERT INTO ob_phone_post_comments (post_id,user_id,body) VALUES (?,?,?)',{postId,id,body})
  local owner=OR.Database.scalar.await('SELECT user_id FROM ob_phone_posts WHERE id=?',{postId})
  if owner and tonumber(owner)~=tonumber(id)then local actor=OR.Database.scalar.await("SELECT COALESCE(NULLIF(display_name,''),username) FROM ob_phone_profiles WHERE user_id=?",{id})or'Alguem';notifyUser(owner,actor..' comentou na sua publicacao.','obgram')end
  return true,{commented=true}
 elseif action=='editPost' then
  local postId=math.floor(tonumber(payload.postId)or 0);local body=tostring(payload.body or ''):sub(1,350)
  if postId<1 then return false,'Publicacao invalida.' end
  local own=OR.Database.single.await([[SELECT p.id,EXISTS(SELECT 1 FROM ob_phone_post_media m WHERE m.post_id=p.id) AS has_media
   FROM ob_phone_posts p WHERE p.id=? AND p.user_id=? LIMIT 1]],{postId,id})
  if not own then return false,'Voce so pode editar suas publicacoes.' end
  if not body:match('%S') and tonumber(own.has_media)~=1 then return false,'A publicacao nao pode ficar vazia.' end
  OR.Database.update.await('UPDATE ob_phone_posts SET body=? WHERE id=? AND user_id=?',{body,postId,id})
  return true,'Publicacao atualizada.'
 elseif action=='deletePost' then
  local postId=math.floor(tonumber(payload.postId)or 0);if postId<1 then return false,'Publicacao invalida.' end
  if not OR.Database.scalar.await('SELECT 1 FROM ob_phone_posts WHERE id=? AND user_id=?',{postId,id}) then return false,'Voce so pode excluir suas publicacoes.' end
  OR.Database.update.await('DELETE FROM ob_phone_post_comments WHERE post_id=?',{postId})
  OR.Database.update.await('DELETE FROM ob_phone_post_likes WHERE post_id=?',{postId})
  OR.Database.update.await('DELETE FROM ob_phone_post_media WHERE post_id=?',{postId})
  OR.Database.update.await('DELETE FROM ob_phone_posts WHERE id=? AND user_id=?',{postId,id})
  return true,'Publicacao excluida.'
 elseif action=='story' then
  local media=ownedMedia(id,payload.mediaId);if not media then return false,'Selecione uma midia da sua galeria.' end
  local storyId=OR.Database.insert.await('INSERT INTO ob_phone_stories (user_id,media_url,media_type,expires_at) VALUES (?,?,?,DATE_ADD(NOW(),INTERVAL 24 HOUR))',{id,media.media_url,media.media_type})
  if storyId then
   local author=OR.Database.scalar.await("SELECT COALESCE(NULLIF(display_name,''),username) FROM ob_phone_profiles WHERE user_id=?",{id})or'Um perfil'
   local followers=OR.Database.query.await('SELECT follower_id FROM ob_phone_follows WHERE followed_id=?',{id})or{}
   for _,row in ipairs(followers)do notifyUser(row.follower_id,author..' publicou um novo story.','obgram')end
  end
  return storyId and true or false,storyId and{story=true}or'Nao foi possivel publicar o story.'
 elseif action=='viewStory' then
  local storyId=math.floor(tonumber(payload.storyId)or 0);if storyId<1 then return false,'Story invalido.' end
  if not OR.Database.scalar.await('SELECT 1 FROM ob_phone_stories WHERE id=? AND expires_at>NOW()',{storyId}) then return false,'Story indisponivel.' end
  OR.Database.update.await('INSERT IGNORE INTO ob_phone_story_views (story_id,user_id) VALUES (?,?)',{storyId,id});return true,{viewed=true}
 elseif action=='avatar' then
  local media=ownedMedia(id,payload.mediaId,payload.variantId);if not media or media.media_type~='photo' then return false,'Selecione uma foto da sua galeria.' end
  OR.Database.update.await('INSERT INTO ob_phone_profile_media (user_id,avatar_url) VALUES (?,?) ON DUPLICATE KEY UPDATE avatar_url=VALUES(avatar_url)',{id,media.media_url});return true,{avatar=true}
 end
 return false,'Acao invalida.'
end)
local function darkChatAllowed(source)
 local job=exports.ob_core:GetJob(source)or{};local current=tostring(job.name or ''):lower()
 for _,blocked in ipairs((OBPhoneConfig.DarkChat or{}).BlockedJobs or{})do
  if current==tostring(blocked):lower()then return false end
 end
 return true
end
local function darkMembership(userId,groupId)
 return OR.Database.scalar.await('SELECT 1 FROM ob_phone_dark_members WHERE group_id=? AND user_id=?',{groupId,userId})~=nil
end
OR.Callback.register('darkchat',function(s,action,payload)
 local allowed,limitError=gate(s,'darkchat',30,60000);if not allowed then return false,limitError end
 local id=uid(s);payload=type(payload)=='table'and payload or{};action=tostring(action or'state')
 if not id then return false,'Personagem indisponivel.' end
 if not darkChatAllowed(s)then return false,'Seu trabalho nao tem permissao para abrir o DarkChat.' end
 if action=='state'then
  local groups=OR.Database.query.await([[SELECT g.id,g.name,g.invite_code,(g.owner_id=?) AS owner,
   (SELECT body FROM ob_phone_dark_messages dm WHERE dm.group_id=g.id ORDER BY dm.id DESC LIMIT 1) AS last_message,
   DATE_FORMAT((SELECT created_at FROM ob_phone_dark_messages dm WHERE dm.group_id=g.id ORDER BY dm.id DESC LIMIT 1),'%H:%i') AS last_time
   FROM ob_phone_dark_groups g JOIN ob_phone_dark_members m ON m.group_id=g.id WHERE m.user_id=? ORDER BY g.id DESC]],{id,id})or{}
  return true,{groups=groups}
 elseif action=='create'then
  local name=tostring(payload.name or''):gsub('[%c]',''):match('^%s*(.-)%s*$')or''
  if #name<3 or #name>40 then return false,'Use um nome de 3 a 40 caracteres.' end
  local code
  for _=1,8 do
   code=('dark/%04X-%04X'):format(math.random(0,65535),math.random(0,65535))
   if not OR.Database.scalar.await('SELECT 1 FROM ob_phone_dark_groups WHERE invite_code=?',{code})then break else code=nil end
  end
  if not code then return false,'Nao foi possivel gerar o convite.' end
  local groupId=OR.Database.insert.await('INSERT INTO ob_phone_dark_groups (owner_id,name,invite_code) VALUES (?,?,?)',{id,name,code})
  if not groupId then return false,'Nao foi possivel criar o grupo.' end
  OR.Database.insert.await('INSERT INTO ob_phone_dark_members (group_id,user_id) VALUES (?,?)',{groupId,id})
  return true,{groupId=groupId,code=code}
 elseif action=='join'then
  local code=tostring(payload.code or''):lower():gsub('%s+',''):sub(1,20)
  local group=OR.Database.single.await('SELECT id FROM ob_phone_dark_groups WHERE LOWER(invite_code)=? LIMIT 1',{code})
  if not group then return false,'Convite do DarkChat nao encontrado.' end
  OR.Database.update.await('INSERT IGNORE INTO ob_phone_dark_members (group_id,user_id) VALUES (?,?)',{group.id,id})
  return true,{groupId=group.id}
 elseif action=='messages'then
  local groupId=math.floor(tonumber(payload.groupId)or 0);if not darkMembership(id,groupId)then return false,'Voce nao participa desse grupo.' end
  local group=OR.Database.single.await('SELECT id,name,invite_code,(owner_id=?) AS owner FROM ob_phone_dark_groups WHERE id=?',{id,groupId})
  local rows=OR.Database.query.await([[SELECT dm.id,dm.user_id,dm.body,dm.media_url,dm.media_type,
   COALESCE(NULLIF(p.display_name,''),p.username,CONCAT('anon',dm.user_id)) AS name,
   DATE_FORMAT(dm.created_at,'%d/%m %H:%i') AS created_at
   FROM ob_phone_dark_messages dm LEFT JOIN ob_phone_profiles p ON p.user_id=dm.user_id
   WHERE dm.group_id=? ORDER BY dm.id ASC LIMIT 100]],{groupId})or{}
  return true,{group=group,messages=rows}
 elseif action=='send'then
  local groupId=math.floor(tonumber(payload.groupId)or 0);if not darkMembership(id,groupId)then return false,'Voce nao participa desse grupo.' end
  local body=tostring(payload.body or''):sub(1,500);local mediaUrl,mediaType='','text'
  if payload.location then
   local x,y=tostring(payload.location):match('^(-?%d+%.?%d*),(-?%d+%.?%d*)$');x,y=tonumber(x),tonumber(y)
   if not x or not y or math.abs(x)>10000 or math.abs(y)>10000 then return false,'Localizacao invalida.' end
   mediaUrl=('%0.3f,%0.3f'):format(x,y);mediaType='location';body='Localizacao compartilhada'
  elseif not body:match('%S')then return false,'Escreva uma mensagem.' end
  local saved,errorMessage=OR.Database.update.await('INSERT INTO ob_phone_dark_messages (group_id,user_id,body,media_url,media_type) VALUES (?,?,?,?,?)',{groupId,id,body,mediaUrl,mediaType})
  if not saved then return false,errorMessage or'Nao foi possivel enviar a mensagem.' end
  local groupName=OR.Database.scalar.await('SELECT name FROM ob_phone_dark_groups WHERE id=?',{groupId})or'DarkChat'
  local members=OR.Database.query.await('SELECT user_id FROM ob_phone_dark_members WHERE group_id=? AND user_id<>?',{groupId,id})or{}
  for _,member in ipairs(members)do notifyUser(member.user_id,'Nova mensagem em '..groupName..'.','darkchat')end
  return true,{sent=true}
 elseif action=='leave'then
  local groupId=math.floor(tonumber(payload.groupId)or 0);local group=OR.Database.single.await('SELECT owner_id FROM ob_phone_dark_groups WHERE id=?',{groupId})
  if not group or not darkMembership(id,groupId)then return false,'Grupo invalido.' end
  if tonumber(group.owner_id)==tonumber(id)then return false,'O criador nao pode sair do proprio grupo.' end
  OR.Database.update.await('DELETE FROM ob_phone_dark_members WHERE group_id=? AND user_id=?',{groupId,id});return true,'Voce saiu do grupo.'
 end
 return false,'Acao do DarkChat invalida.'
end)
OR.Callback.register('phoneSettings',function(s,action,payload)
 local allowed,limitError=gate(s,'settings',12,30000);if not allowed then return false,limitError end
 local id=uid(s);payload=type(payload)=='table'and payload or{};if not id then return false,'Personagem indisponivel.' end
 if action=='avatar'then
  local media=ownedMedia(id,payload.mediaId,payload.variantId);if not media or media.media_type~='photo'then return false,'Escolha uma foto da galeria.'end
  local saved,errorMessage=OR.Database.update.await('INSERT INTO ob_phone_device_profiles (user_id,avatar_url) VALUES (?,?) ON DUPLICATE KEY UPDATE avatar_url=VALUES(avatar_url)',{id,media.media_url})
  return saved~=nil,saved and'Foto atualizada.'or(errorMessage or'Nao foi possivel atualizar a foto.')
 end
 local airplane=payload.airplane==true and 1 or 0
 local notifications=payload.notifications~=false and 1 or 0
 local darkchatNotifications=payload.darkchatNotifications~=false and 1 or 0
 local ringtone=tostring(payload.ringtone or'classic'):lower()
 if not({classic=true,digital=true,soft=true})[ringtone]then ringtone='classic'end
 local shareName=tostring(payload.shareName or''):gsub('[%c]',''):match('^%s*(.-)%s*$')or''
 if #shareName<2 or #shareName>40 then return false,'Informe um nome de compartilhamento entre 2 e 40 caracteres.'end
 local saved,errorMessage=OR.Database.update.await([[INSERT INTO ob_phone_settings (user_id,airplane_mode,notifications,darkchat_notifications,ringtone,share_name) VALUES (?,?,?,?,?,?)
  ON DUPLICATE KEY UPDATE airplane_mode=VALUES(airplane_mode),notifications=VALUES(notifications),darkchat_notifications=VALUES(darkchat_notifications),ringtone=VALUES(ringtone),share_name=VALUES(share_name)]],{id,airplane,notifications,darkchatNotifications,ringtone,shareName})
 return saved~=nil,saved and'Configuracoes salvas.'or(errorMessage or'Nao foi possivel salvar.')
end)

local function messageGroupMember(userId,groupId)
 return OR.Database.single.await('SELECT role FROM ob_phone_message_group_members WHERE group_id=? AND user_id=?',{groupId,userId})
end
OR.Callback.register('messageGroups',function(s,action,payload)
 local allowed,limitError=gate(s,'messageGroups',30,60000);if not allowed then return false,limitError end
 local id=uid(s);payload=type(payload)=='table'and payload or{};action=tostring(action or'state');if not id then return false,'Personagem indisponivel.'end
 if action=='state'then
  local rows=OR.Database.query.await([[SELECT g.id,g.name,m.role,g.invite_permission,
   (SELECT body FROM ob_phone_message_group_messages gm WHERE gm.group_id=g.id ORDER BY gm.id DESC LIMIT 1) AS last_message
   FROM ob_phone_message_groups g JOIN ob_phone_message_group_members m ON m.group_id=g.id WHERE m.user_id=? ORDER BY g.name]],{id})or{}
  return true,{groups=rows}
 elseif action=='create'then
  local name=tostring(payload.name or''):gsub('[%c]',''):match('^%s*(.-)%s*$')or'';if #name<3 or #name>40 then return false,'Nome invalido.'end
  local groupId=OR.Database.insert.await('INSERT INTO ob_phone_message_groups (owner_id,name) VALUES (?,?)',{id,name});if not groupId then return false,'Nao foi possivel criar o grupo.'end
  OR.Database.update.await('INSERT INTO ob_phone_message_group_members (group_id,user_id,role) VALUES (?,?,?)',{groupId,id,'owner'});return true,{groupId=groupId}
 elseif action=='open'then
  local groupId=math.floor(tonumber(payload.groupId)or 0);local member=messageGroupMember(id,groupId);if not member then return false,'Voce nao participa desse grupo.'end
  local group=OR.Database.single.await('SELECT id,name,owner_id,invite_permission FROM ob_phone_message_groups WHERE id=?',{groupId})
  local members=OR.Database.query.await([[SELECT m.user_id,m.role,n.phone_number,COALESCE(NULLIF(p.display_name,''),p.username,CONCAT('Contato ',m.user_id)) AS name,pm.avatar_url
   FROM ob_phone_message_group_members m LEFT JOIN ob_phone_numbers n ON n.user_id=m.user_id LEFT JOIN ob_phone_profiles p ON p.user_id=m.user_id LEFT JOIN ob_phone_device_profiles pm ON pm.user_id=m.user_id WHERE m.group_id=? ORDER BY name]],{groupId})or{}
  local messages=OR.Database.query.await([[SELECT gm.id,gm.user_id,gm.body,gm.message_type,gm.media_url,COALESCE(NULLIF(p.display_name,''),p.username,CONCAT('Contato ',gm.user_id)) AS name,DATE_FORMAT(gm.created_at,'%d/%m %H:%i') AS created_at FROM ob_phone_message_group_messages gm LEFT JOIN ob_phone_profiles p ON p.user_id=gm.user_id WHERE gm.group_id=? ORDER BY gm.id ASC LIMIT 120]],{groupId})or{}
  return true,{group=group,members=members,messages=messages,role=member.role}
 elseif action=='send'then
  local groupId=math.floor(tonumber(payload.groupId)or 0);if not messageGroupMember(id,groupId)then return false,'Grupo invalido.'end
  local body=tostring(payload.body or''):sub(1,500);local kind,url='text',''
  if payload.location then local x,y=tostring(payload.location):match('^(-?%d+%.?%d*),(-?%d+%.?%d*)$');x,y=tonumber(x),tonumber(y);if not x or not y then return false,'Localizacao invalida.'end;kind='location';url=('%0.3f,%0.3f'):format(x,y);body='Localizacao compartilhada' elseif not body:match('%S')then return false,'Escreva uma mensagem.'end
  local saved,errorMessage=OR.Database.update.await('INSERT INTO ob_phone_message_group_messages (group_id,user_id,body,message_type,media_url) VALUES (?,?,?,?,?)',{groupId,id,body,kind,url})
  if saved~=nil then local groupName=OR.Database.scalar.await('SELECT name FROM ob_phone_message_groups WHERE id=?',{groupId})or'grupo';local members=OR.Database.query.await('SELECT user_id FROM ob_phone_message_group_members WHERE group_id=? AND user_id<>?',{groupId,id})or{};for _,member in ipairs(members)do notifyUser(member.user_id,'Nova mensagem no grupo '..groupName..'.','messages')end end
  return saved~=nil,saved and{sent=true}or(errorMessage or'Falha ao enviar.')
 elseif action=='invite'then
  local groupId=math.floor(tonumber(payload.groupId)or 0);local member=messageGroupMember(id,groupId);if not member then return false,'Grupo invalido.'end
  local group=OR.Database.single.await('SELECT owner_id,invite_permission FROM ob_phone_message_groups WHERE id=?',{groupId});local can=member.role=='owner'or(member.role=='moderator'and group.invite_permission~='owner')or group.invite_permission=='members';if not can then return false,'Voce nao pode convidar.'end
  local number=tostring(payload.number or''):gsub('%D','');local target=OR.Database.single.await('SELECT user_id FROM ob_phone_numbers WHERE phone_number=?',{number});if not target then return false,'Numero nao encontrado.'end
  OR.Database.update.await('INSERT IGNORE INTO ob_phone_message_group_members (group_id,user_id) VALUES (?,?)',{groupId,target.user_id});return true,'Contato adicionado.'
 elseif action=='manage'then
  local groupId,targetId=math.floor(tonumber(payload.groupId)or 0),math.floor(tonumber(payload.userId)or 0);local member=messageGroupMember(id,groupId);if not member or(member.role~='owner'and member.role~='moderator')then return false,'Sem permissao.'end
  local target=messageGroupMember(targetId,groupId);if not target or target.role=='owner'or(member.role=='moderator'and target.role=='moderator')then return false,'Membro invalido.'end
  if payload.operation=='remove'then OR.Database.update.await('DELETE FROM ob_phone_message_group_members WHERE group_id=? AND user_id=?',{groupId,targetId})
  elseif payload.operation=='moderator'and member.role=='owner'then OR.Database.update.await("UPDATE ob_phone_message_group_members SET role='moderator' WHERE group_id=? AND user_id=?",{groupId,targetId}) else return false,'Operacao invalida.'end
  return true,'Grupo atualizado.'
 elseif action=='transfer'then
  local groupId,targetId=math.floor(tonumber(payload.groupId)or 0),math.floor(tonumber(payload.userId)or 0);local member=messageGroupMember(id,groupId);if not member or member.role~='owner'or not messageGroupMember(targetId,groupId)then return false,'Transferencia invalida.'end
  OR.Database.update.await("UPDATE ob_phone_message_group_members SET role='member' WHERE group_id=? AND user_id=?",{groupId,id});OR.Database.update.await("UPDATE ob_phone_message_group_members SET role='owner' WHERE group_id=? AND user_id=?",{groupId,targetId});OR.Database.update.await('UPDATE ob_phone_message_groups SET owner_id=? WHERE id=?',{targetId,groupId});return true,'Grupo transferido.'
 elseif action=='permission'then
  local groupId=math.floor(tonumber(payload.groupId)or 0);local member=messageGroupMember(id,groupId);local value=tostring(payload.value or'');if not member or member.role~='owner'or not({owner=true,moderators=true,members=true})[value]then return false,'Configuracao invalida.'end
  OR.Database.update.await('UPDATE ob_phone_message_groups SET invite_permission=? WHERE id=?',{value,groupId});return true,'Permissao atualizada.'
 elseif action=='delete'then
  local groupId=math.floor(tonumber(payload.groupId)or 0);local member=messageGroupMember(id,groupId);if not member or member.role~='owner'then return false,'Somente o dono pode excluir.'end
  OR.Database.update.await('DELETE FROM ob_phone_message_group_messages WHERE group_id=?',{groupId});OR.Database.update.await('DELETE FROM ob_phone_message_group_members WHERE group_id=?',{groupId});OR.Database.update.await('DELETE FROM ob_phone_message_groups WHERE id=?',{groupId});return true,'Grupo excluido.'
 end
 return false,'Acao invalida.'
end)
OR.Callback.register('bankData',function(s)
 local id=uid(s);if not id then return false,'Celular bloqueado ou sem sinal.'end
 OR.Database.update.await('INSERT IGNORE INTO ob_bank_accounts (user_id) VALUES (?)',{id})
 local account=OR.Database.single.await('SELECT balance FROM ob_bank_accounts WHERE user_id=?',{id})or{}
 local card=OR.Database.single.await('SELECT card_number FROM ob_bank_cards WHERE owner_user_id=? AND active=1 ORDER BY issued_at DESC LIMIT 1',{id})
 local rows=OR.Database.query.await('SELECT kind,amount,description,DATE_FORMAT(created_at,"%d/%m %H:%i") AS created_at FROM ob_bank_transactions WHERE user_id=? ORDER BY id DESC LIMIT 12',{id})or{}
 local week=OR.Database.single.await([[SELECT COALESCE(SUM(CASE WHEN kind IN ('deposit','refund','salary','transfer_in') THEN amount ELSE 0 END),0) AS incoming,COALESCE(SUM(CASE WHEN kind IN ('withdraw','card','pin_reset','transfer_out','fine_payment') THEN amount ELSE 0 END),0) AS outgoing FROM ob_bank_transactions WHERE user_id=? AND created_at>=CURDATE()-INTERVAL 6 DAY]],{id})or{}
 local fines=OR.Database.query.await([[SELECT id,reason,officer_name,fine,DATE_FORMAT(created_at,'%d/%m %H:%i') AS created_at FROM ob_mdt_records WHERE suspect_user_id=? AND fine>0 AND fine_status='pending' ORDER BY id ASC]],{id})or{}
 local fineTotal=0;for _,fine in ipairs(fines)do fineTotal=fineTotal+(tonumber(fine.fine) or 0)end
 return true,{balance=tonumber(account.balance) or 0,cash=0,card=card and{number=card.card_number,owner=true}or nil,transactions=rows,week={incoming=tonumber(week.incoming) or 0,outgoing=tonumber(week.outgoing) or 0},fines=fines,pendingFineTotal=fineTotal}
end)
OR.Callback.register('payPhoneFine',function(s,recordId)
 local id=uid(s);recordId=math.floor(tonumber(recordId) or 0);if not id or recordId<1 then return false,'Multa invalida.'end
 local fine=OR.Database.single.await('SELECT id,fine,fine_status FROM ob_mdt_records WHERE id=? AND suspect_user_id=? LIMIT 1',{recordId,id})
 if not fine then return false,'Esta multa nao pertence ao dono do aparelho.'end
 local amount=math.max(0,math.floor(tonumber(fine.fine) or 0));if amount<1 or fine.fine_status~='pending'then return false,'Esta multa nao esta pendente.'end
 local changed,errorMessage=OR.Database.update.await([[UPDATE ob_bank_accounts a INNER JOIN ob_mdt_records r ON r.id=? AND r.suspect_user_id=a.user_id SET a.balance=a.balance-r.fine,r.fine_status='paid' WHERE a.user_id=? AND r.fine_status='pending' AND r.fine>0 AND a.balance>=r.fine]],{recordId,id})
 if not changed or changed<1 then return false,errorMessage or'Saldo insuficiente ou multa ja paga.'end
 OR.Database.insert.await('INSERT INTO ob_bank_transactions (user_id,kind,amount,description) VALUES (?,?,?,?)',{id,'fine_payment',amount,'Pagamento da multa MDT #'..recordId})
 return true,('Multa #%s paga.'):format(recordId)
end)
OR.Callback.register('transfer',function(s,target,amount)
 local allowed,limitError=gate(s,'transfer',6,30000);if not allowed then return false,limitError end
 local id=uid(s);target=tonumber(target);amount=math.max(1,math.floor(tonumber(amount) or 0));if not id or not target or target==id then return false,'ID invalido.'end
 local exists=OR.Database.scalar.await('SELECT 1 FROM ob_characters WHERE user_id=? LIMIT 1',{target});if not exists then return false,'Destinatario nao encontrado.'end
 OR.Database.update.await('INSERT IGNORE INTO ob_bank_accounts (user_id) VALUES (?),(?)',{id,target})
 local debited=OR.Database.update.await('UPDATE ob_bank_accounts SET balance=balance-? WHERE user_id=? AND balance>=?',{amount,id,amount})
 if not debited or debited<1 then return false,'Saldo bancario insuficiente.'end
 local credited=OR.Database.update.await('UPDATE ob_bank_accounts SET balance=balance+? WHERE user_id=?',{amount,target})
 if not credited or credited<1 then OR.Database.update.await('UPDATE ob_bank_accounts SET balance=balance+? WHERE user_id=?',{amount,id});return false,'Nao foi possivel concluir a transferencia.'end
 OR.Database.insert.await('INSERT INTO ob_bank_transactions (user_id,kind,amount,description) VALUES (?,?,?,?)',{id,'transfer_out',amount,'Transferencia para ID '..target})
 OR.Database.insert.await('INSERT INTO ob_bank_transactions (user_id,kind,amount,description) VALUES (?,?,?,?)',{target,'transfer_in',amount,'Transferencia recebida do ID '..id})
 return true,'Transferencia concluida.'
end)
OR.Callback.register('garageData',function(s)
 local id=uid(s);if not id then return false,'Celular bloqueado ou sem sinal.'end
 local rows=OR.Database.query.await([[SELECT id,plate,model,label,garage,stored,fuel,body,engine
  FROM ob_vehicles WHERE owner_user_id=? AND vehicle_type<>'free' ORDER BY stored DESC,label ASC]],{id})or{}
 return true,rows
end)
OR.Callback.register('trackVehicle',function(s,vehicleId)
 local id=uid(s);if not id then return false,'Celular bloqueado ou sem sinal.'end
 local timestamp=os.time();local cooldown=tonumber(OBPhoneConfig.VehicleTrackingCooldownSeconds)or 30
 if (vehicleTrackCooldown[s]or 0)>timestamp then return false,('Aguarde %d segundos para rastrear novamente.'):format(vehicleTrackCooldown[s]-timestamp)end
 local row=OR.Database.single.await("SELECT id,plate,model,stored FROM ob_vehicles WHERE id=? AND owner_user_id=? AND vehicle_type<>'free' LIMIT 1",{tonumber(vehicleId),id})
 if not row then return false,'Veiculo nao encontrado.'end
 if tonumber(row.stored)==1 then return false,'Esse veiculo esta guardado na garagem.'end
 local wanted=tostring(row.plate or''):gsub('%s+',''):upper();local found
 for _,vehicle in ipairs(GetAllVehicles())do
  if DoesEntityExist(vehicle)and tostring(GetVehicleNumberPlateText(vehicle)or''):gsub('%s+',''):upper()==wanted then found=vehicle break end
 end
 if not found then return false,'O veiculo nao esta sincronizado para rastreamento.'end
 vehicleTrackCooldown[s]=timestamp+cooldown
 local coords=GetEntityCoords(found)
 return true,{plate=row.plate,model=row.model,x=coords.x,y=coords.y,z=coords.z,duration=tonumber(OBPhoneConfig.VehicleTrackingDurationSeconds)or 30}
end)
RegisterNetEvent('ob_phone:server:shareNumber',function(target,sharedName,sharedNumber)
 local source=source;if not gate(source,'share',6,30000) then return end;target=tonumber(target);if not ready or not target or target==source or not GetPlayerName(target) then return end
 if not phoneVisuals[source] or not phoneVisuals[target] then return TriggerClientEvent('ob_phone:client:notification',source,'A outra pessoa precisa estar com o celular aberto.','phone') end
 local fromPed,toPed=GetPlayerPed(source),GetPlayerPed(target);if not fromPed or not toPed or fromPed<=0 or toPed<=0 or #(GetEntityCoords(fromPed)-GetEntityCoords(toPed))>(tonumber(OBPhoneConfig.ShareDistance)or 3.0) then return end
 local fromId,toId=uid(source),uid(target);if not fromId or not toId then return end
 local sender=phone(fromId);if not sender then return end
 sharedNumber=tostring(sharedNumber or sender.phone_number):gsub('%D',''):sub(1,16)
  local name,number
  if sharedNumber==sender.phone_number then
   local profile=OR.Database.single.await([[SELECT COALESCE(NULLIF(st.share_name,''),NULLIF(pr.display_name,''),pr.username) AS name
    FROM ob_phone_numbers n LEFT JOIN ob_phone_settings st ON st.user_id=n.user_id LEFT JOIN ob_phone_profiles pr ON pr.user_id=n.user_id WHERE n.user_id=?]],{fromId})
  name=profile and profile.name or GetPlayerName(source)or('Contato '..fromId);number=sender.phone_number
 else
  local saved=OR.Database.single.await('SELECT contact_name,contact_number FROM ob_phone_contacts WHERE user_id=? AND contact_number=? LIMIT 1',{fromId,sharedNumber})
  if not saved then return end
  name=saved.contact_name;number=saved.contact_number
 end
 local senderName=OR.Database.scalar.await([[SELECT COALESCE(NULLIF(st.share_name,''),NULLIF(pr.display_name,''),pr.username,?)
  FROM ob_phone_numbers n LEFT JOIN ob_phone_settings st ON st.user_id=n.user_id LEFT JOIN ob_phone_profiles pr ON pr.user_id=n.user_id WHERE n.user_id=?]],{GetPlayerName(source)or('Contato '..fromId),fromId})
 shareRequestSerial=shareRequestSerial+1
 local token=shareRequestSerial
 shareRequests[token]={source=source,target=target,fromId=fromId,toId=toId,name=tostring(name):sub(1,40),number=number,senderName=tostring(senderName or GetPlayerName(source)or'Pessoa proxima'):sub(1,40),expires=GetGameTimer()+(tonumber(OBPhoneConfig.ShareRequestSeconds)or 20)*1000}
 TriggerClientEvent('ob_phone:client:shareRequest',target,{token=token,name=shareRequests[token].name,number=number,senderName=shareRequests[token].senderName,expiresIn=tonumber(OBPhoneConfig.ShareRequestSeconds)or 20})
 TriggerClientEvent('ob_phone:client:notification',source,'Solicitacao de contato enviada.','phone')
 SetTimeout((tonumber(OBPhoneConfig.ShareRequestSeconds)or 20)*1000+250,function()
  local pending=shareRequests[token];if not pending then return end
  shareRequests[token]=nil
  if pending.source and GetPlayerName(pending.source)then TriggerClientEvent('ob_phone:client:notification',pending.source,'A solicitacao de contato expirou.','phone')end
 end)
end)
OR.Callback.register('shareNumberResponse',function(s,token,accepted)
 token=math.floor(tonumber(token)or 0);local request=shareRequests[token]
 if not request or request.target~=s then return false,'Solicitacao invalida ou expirada.' end
 shareRequests[token]=nil
 local sender=request.source
 if GetGameTimer()>request.expires then
  if sender and GetPlayerName(sender)then TriggerClientEvent('ob_phone:client:notification',sender,'A solicitacao de contato expirou.','phone')end
  return false,'A solicitacao expirou.'
 end
 if accepted~=true then
  if sender and GetPlayerName(sender)then TriggerClientEvent('ob_phone:client:notification',sender,'A solicitacao de contato foi recusada.','phone')end
  return true,'Solicitacao recusada.'
 end
 if uid(s)~=request.toId or uid(sender)~=request.fromId then return false,'O personagem da solicitacao mudou.' end
 if not phoneVisuals[s] or not sender or not GetPlayerName(sender) or not phoneVisuals[sender] then return false,'Os dois celulares precisam continuar abertos.' end
 local fromPed,toPed=GetPlayerPed(sender),GetPlayerPed(s)
 if not fromPed or not toPed or fromPed<=0 or toPed<=0 or #(GetEntityCoords(fromPed)-GetEntityCoords(toPed))>(tonumber(OBPhoneConfig.ShareDistance)or 3.0) then return false,'A pessoa se afastou demais.' end
 local saved=OR.Database.query.await('INSERT INTO ob_phone_contacts (user_id,contact_number,contact_name) VALUES (?,?,?) ON DUPLICATE KEY UPDATE contact_name=VALUES(contact_name)',{request.toId,request.number,request.name})
 if not saved then return false,'Nao foi possivel salvar o contato.' end
 TriggerClientEvent('ob_phone:client:notification',sender,(request.senderName and 'Contato aceito.'or'Solicitacao aceita.'),'phone')
 return true,request.name..' foi adicionado aos contatos.'
end)
