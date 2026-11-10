local pendingUploads = {}
local mediaReady = false

local function userId(source)
    return OBPhoneDevice.UserId(source)
end

local function cleanHost(url)
    return type(url) == 'string' and url:match('^https://([^/%?#]+)') or nil
end

local function isFiveManageHost(url)
    local host = cleanHost(url)
    if not host then return false end
    host = host:lower()
    return host == 'api.fivemanage.com' or host == 'fmapi.net' or host == 'r2.fivemanage.com'
        or host:match('%.fivemanage%.com$') ~= nil
end

local function isUploadedMedia(url)
    local host = cleanHost(url)
    return host and host:lower() == 'r2.fivemanage.com' or false
end

local function http(url, method, headers, timeout)
    local request, settled = promise.new(), false
    PerformHttpRequest(url, function(status, body, responseHeaders, errorData)
        if settled then return end
        settled = true
        request:resolve({ status = status, body = body, headers = responseHeaders, error = errorData })
    end, method or 'GET', '', headers or {})
    SetTimeout(timeout or 10000, function()
        if settled then return end
        settled = true
        request:resolve({ status = 0, body = 'timeout' })
    end)
    return Citizen.Await(request)
end

CreateThread(function()
    if not OR.Database.waitForReady(30000) then return end
    local ok = OR.Database.query.await([[CREATE TABLE IF NOT EXISTS ob_phone_media (
        id bigint unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,
        user_id int NOT NULL,
        remote_id varchar(160) NOT NULL,
        media_type enum('photo','video','audio') NOT NULL,
        media_url varchar(700) NOT NULL,
        created_at timestamp NOT NULL DEFAULT current_timestamp(),
        INDEX idx_phone_media_user (user_id,id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    local variantsOk = OR.Database.query.await([[CREATE TABLE IF NOT EXISTS ob_phone_media_variants (
        id bigint unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,
        user_id int NOT NULL,
        source_media_id bigint unsigned NOT NULL,
        remote_id varchar(160) NOT NULL,
        media_url varchar(700) NOT NULL,
        created_at timestamp NOT NULL DEFAULT current_timestamp(),
        INDEX idx_phone_media_variant_user (user_id,id),
        INDEX idx_phone_media_variant_source (source_media_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    if ok~=nil and OR.Database.single.await("SHOW COLUMNS FROM ob_phone_media WHERE Field='media_type' AND Type LIKE '%audio%'")==nil then
        OR.Database.query.await("ALTER TABLE ob_phone_media MODIFY media_type enum('photo','video','audio') NOT NULL")
    end
    mediaReady = ok ~= nil and variantsOk ~= nil
end)

OR.Callback.register('mediaRequestUpload', function(source, mediaType)
    local allowed, retry = OR.Security.rateLimit(source, 'phone:media_request', 6, 60000)
    if not allowed then return false, ('Aguarde %d segundos para enviar outra midia.'):format(math.max(1, math.ceil((retry or 1000) / 1000))) end
    local id = userId(source)
    mediaType = tostring(mediaType or '')
    if not id or not mediaReady or (mediaType ~= 'photo' and mediaType ~= 'video' and mediaType ~= 'audio') then return false, 'Pedido de midia invalido.' end
    local config = OBPhoneServerConfig or {}
    local apiKey = tostring(config.fivemanageApiKey or '')
    local baseUrl = tostring(config.uploadServer or ''):gsub('/+$', '')
    if apiKey == '' then return false, 'Configure fivemanageApiKey no server_config.lua.' end
    if not isFiveManageHost(baseUrl) then return false, 'uploadServer do FiveManage invalido.' end
    local response = http(baseUrl .. '/presigned-url', 'GET', { ['Authorization'] = apiKey }, 10000)
    if response.status == 401 or response.status == 403 then return false, 'A chave do FiveManage foi recusada.' end
    if response.status == 429 then return false, 'O FiveManage limitou os envios. Tente novamente.' end
    if response.status < 200 or response.status >= 300 then return false, 'FiveManage indisponivel (HTTP ' .. tostring(response.status) .. ').' end
    local decodedOk, decoded = pcall(json.decode, response.body or '')
    local payload = decodedOk and type(decoded) == 'table' and (decoded.data or decoded) or nil
    local presigned = payload and (payload.presignedUrl or payload.presigned_url)
    if not isFiveManageHost(presigned) then return false, 'O FiveManage retornou um endereco de envio invalido.' end
    local requestId = ('%d:%d:%d'):format(source, os.time(), math.random(100000, 999999))
    pendingUploads[requestId] = { source = source, userId = id, mediaType = mediaType, expires = os.time() + 90 }
    return true, { requestId = requestId, presignedUrl = presigned, uploadTimeoutMs = tonumber(config.uploadTimeoutMs) or 25000 }
end)

OR.Callback.register('mediaCompleteUpload', function(source, requestId, remoteId, url, mediaType, variantForMediaId)
    local pending = pendingUploads[tostring(requestId or '')]
    pendingUploads[tostring(requestId or '')] = nil
    if not pending or pending.source ~= source or pending.userId ~= userId(source) or pending.expires < os.time() then return false, 'Envio expirado ou invalido.' end
    if tostring(mediaType or '') ~= pending.mediaType or not isUploadedMedia(url) then return false, 'Resposta de midia invalida.' end
    remoteId = tostring(remoteId or ''):sub(1, 160)
    url = tostring(url or ''):sub(1, 700)
    if remoteId == '' or url == '' then return false, 'O FiveManage nao retornou o arquivo.' end
    variantForMediaId = math.floor(tonumber(variantForMediaId) or 0)
    if variantForMediaId > 0 then
        if pending.mediaType ~= 'photo' then return false, 'Somente fotos podem receber filtros.' end
        local original = OR.Database.scalar.await('SELECT 1 FROM ob_phone_media WHERE id=? AND user_id=? AND media_type=?', { variantForMediaId, pending.userId, 'photo' })
        if not original then return false, 'A foto original nao foi encontrada.' end
        local variantId = OR.Database.insert.await('INSERT INTO ob_phone_media_variants (user_id,source_media_id,remote_id,media_url) VALUES (?,?,?,?)', { pending.userId, variantForMediaId, remoteId, url })
        if not variantId then return false, 'Nao foi possivel salvar o filtro.' end
        return true, { id = variantForMediaId, variant_id = variantId, media_type = 'photo', media_url = url }
    end
    local inserted = OR.Database.insert.await('INSERT INTO ob_phone_media (user_id,remote_id,media_type,media_url) VALUES (?,?,?,?)', { pending.userId, remoteId, pending.mediaType, url })
    if not inserted then return false, 'Nao foi possivel salvar a midia.' end
    return true, { id = inserted, media_type = pending.mediaType, media_url = url }
end)

OR.Callback.register('mediaList', function(source)
    local id = userId(source)
    if not id or not mediaReady then return false, 'Galeria indisponivel.' end
    local rows = OR.Database.query.await([[SELECT m.id,m.media_type,m.media_url,DATE_FORMAT(m.created_at,'%d/%m %H:%i') AS created_at,
        (EXISTS(SELECT 1 FROM ob_phone_post_media pm JOIN ob_phone_posts p ON p.id=pm.post_id
          WHERE p.user_id=m.user_id AND pm.media_url=m.media_url)
         OR EXISTS(SELECT 1 FROM ob_phone_stories s WHERE s.user_id=m.user_id AND s.media_url=m.media_url)
         OR EXISTS(SELECT 1 FROM ob_phone_profile_media a WHERE a.user_id=m.user_id AND a.avatar_url=m.media_url)) AS used_in_obgram
        FROM ob_phone_media m WHERE m.user_id=? ORDER BY m.id DESC LIMIT 60]], { id }) or {}
    return true, rows
end)

OR.Callback.register('mediaDelete', function(source, mediaId)
    local allowed, retry = OR.Security.rateLimit(source, 'phone:media_delete', 12, 60000)
    if not allowed then return false, ('Aguarde %d segundos.'):format(math.max(1, math.ceil((retry or 1000) / 1000))) end
    local id = userId(source);mediaId=math.floor(tonumber(mediaId)or 0)
    if not id or mediaId<1 then return false,'Midia invalida.' end
    local media=OR.Database.single.await('SELECT remote_id,media_url FROM ob_phone_media WHERE id=? AND user_id=? LIMIT 1',{mediaId,id})
    if not media then return false,'Midia nao encontrada.' end
    local shared=OR.Database.scalar.await([[SELECT 1 FROM ob_phone_messages WHERE sender_id=? AND media_url=?
        UNION SELECT 1 FROM ob_phone_dark_messages WHERE user_id=? AND media_url=? LIMIT 1]],{id,media.media_url,id,media.media_url})
    local emptyPosts=OR.Database.query.await([[SELECT p.id FROM ob_phone_posts p JOIN ob_phone_post_media pm ON pm.post_id=p.id
        WHERE p.user_id=? AND pm.media_url=? AND (p.body IS NULL OR TRIM(p.body)='')]],{id,media.media_url})or{}
    OR.Database.update.await('DELETE FROM ob_phone_stories WHERE user_id=? AND media_url=?',{id,media.media_url})
    OR.Database.update.await('DELETE FROM ob_phone_profile_media WHERE user_id=? AND avatar_url=?',{id,media.media_url})
    OR.Database.update.await('DELETE pm FROM ob_phone_post_media pm JOIN ob_phone_posts p ON p.id=pm.post_id WHERE p.user_id=? AND pm.media_url=?',{id,media.media_url})
    for _,row in ipairs(emptyPosts)do
        OR.Database.update.await('DELETE FROM ob_phone_post_comments WHERE post_id=?',{row.id})
        OR.Database.update.await('DELETE FROM ob_phone_post_likes WHERE post_id=?',{row.id})
        OR.Database.update.await('DELETE FROM ob_phone_posts WHERE id=? AND user_id=?',{row.id,id})
    end
    OR.Database.update.await('DELETE FROM ob_phone_media WHERE id=? AND user_id=?',{mediaId,id})
    local config=OBPhoneServerConfig or{};local apiKey=tostring(config.fivemanageApiKey or'');local base=tostring(config.uploadServer or''):gsub('/+$','')
    if not shared and apiKey~='' and isFiveManageHost(base) and tostring(media.remote_id or'')~='' then
        CreateThread(function() http(base..'/'..tostring(media.remote_id), 'DELETE', {['Authorization']=apiKey}, 10000) end)
    end
    return true,'Midia excluida.'
end)

AddEventHandler('playerDropped', function()
    local dropped = source
    for requestId, pending in pairs(pendingUploads) do
        if pending.source == dropped then pendingUploads[requestId] = nil end
    end
end)
