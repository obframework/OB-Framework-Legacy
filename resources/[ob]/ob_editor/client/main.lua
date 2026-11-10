local open, mapBlips = false, {}
local preview, previewItems, captureMode, previewFx=nil,{},nil,nil
local laserRay,laserTarget,laserStarted,toolBusy=nil,nil,0,false
local function placePreviewFire(p)
    if previewFx then StopParticleFxLooped(previewFx,false); previewFx=nil end
    UseParticleFxAssetNextCall('scr_ornate_heist')
    -- Mesmo efeito, origem e orientacao usados pelo assalto. O suporte e invisivel.
    previewFx=StartParticleFxLoopedAtCoord('scr_heist_ornate_thermal_burn',p.x,p.y,p.z,0.0,0.0,0.0,1.0,false,false,false,false)
    if not previewFx or previewFx==0 then previewFx=nil; error('Nao foi possivel iniciar o fogo de teste.') end
end
local function clearPreview()
    if previewFx then StopParticleFxLooped(previewFx,false); previewFx=nil end
    for _,entity in ipairs(previewItems) do if DoesEntityExist(entity) then DeleteEntity(entity) end end
    preview,previewItems=nil,{}
end
local function finishCapture()
    captureMode=nil
    OR.Help.Hide()
    laserRay,laserTarget=nil,nil
    SetNuiFocus(open,open)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({action='layoutCapture',hidden=false})
end
local function beginCapture(mode)
    captureMode=mode
    laserRay,laserTarget=nil,nil
    SetNuiFocus(false,false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({action='layoutCapture',hidden=true,mode=mode})
end

local function renderBlips(entries)
    local active = {}
    for _, entry in ipairs(entries or {}) do
        local id = tonumber(entry.id)
        active[id] = true
        local blip = mapBlips[id]
        if not blip or not DoesBlipExist(blip) then
            blip = AddBlipForCoord(tonumber(entry.x), tonumber(entry.y), tonumber(entry.z))
            mapBlips[id] = blip
        end
        SetBlipSprite(blip, tonumber(entry.sprite) or 1)
        SetBlipColour(blip, tonumber(entry.color) or 3)
        SetBlipScale(blip, tonumber(entry.scale) or 0.8)
        SetBlipAsShortRange(blip, tonumber(entry.short_range) ~= 0)
        BeginTextCommandSetBlipName('STRING'); AddTextComponentString(entry.label or 'Blip'); EndTextCommandSetBlipName(blip)
    end
    for id, blip in pairs(mapBlips) do
        if not active[id] then if DoesBlipExist(blip) then RemoveBlip(blip) end; mapBlips[id] = nil end
    end
end

RegisterNetEvent('ob_editor:client:syncBlips', renderBlips)
RegisterNetEvent('ob_editor:client:editorData', function(entries) SendNUIMessage({ action = 'data', blips = entries or {} }) end)
RegisterNetEvent('ob_editor:client:notify', function(message, kind) OR.Notify(message, kind) end)

RegisterNetEvent('ob_editor:client:open', function(mode)
    if open or IsNuiFocused() then return end
    local data, err = OR.Callback.awaitResource('ob_editor', 'getAccess')
    if not data then return OR.Notify(err or 'Sem permissao.', 'error') end
    open = true
    SetNuiFocus(true, true); SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'open', blips = data.blips or {}, mode=mode })
end)

RegisterNUICallback('close', function(_, cb) open = false; finishCapture(); clearPreview(); SetNuiFocus(false, false); SendNUIMessage({ action = 'close' }); cb({ ok = true }) end)
RegisterNUICallback('saveBlip', function(data, cb) TriggerServerEvent('ob_editor:server:saveBlip', data); cb({ ok = true }) end)
RegisterNUICallback('deleteBlip', function(data, cb) TriggerServerEvent('ob_editor:server:deleteBlip', data and data.id); cb({ ok = true }) end)

CreateThread(function()
    while LocalPlayer.state['or:loaded'] ~= true do Wait(500) end
    TriggerServerEvent('ob_editor:server:requestBlips')
end)

local bankResources={ob_pacificrobbery=true,ob_fleecarobbery=true}
local function point(raw)
    if type(raw)~='table' then return end
    local out={}
    for _,axis in ipairs({'x','y','z','w','rx','ry'}) do
        local n=tonumber(raw[axis] or 0)
        if not n or n~=n or math.abs(n)>20000 then return end
        out[axis]=n
    end
    return out
end
local function requestModel(name)
    local hash=tonumber(name) or joaat(tostring(name))
    if not IsModelInCdimage(hash) then error('Modelo nao existe: '..tostring(name)) end
    RequestModel(hash)
    local deadline=GetGameTimer()+4000
    while open and not HasModelLoaded(hash) and GetGameTimer()<deadline do Wait(0) end
    if not open then error('Editor fechado.') end
    if not HasModelLoaded(hash) then error('Nao foi possivel carregar o modelo.') end
    return hash
end
local function createPreview(data)
    clearPreview()
    local p=point(data.point)
    if not p then error('Posicao invalida.') end
    if #(GetEntityCoords(PlayerPedId())-vector3(p.x,p.y,p.z))>100 then error('Use Ir ao ponto antes de criar a previa distante.') end
    if data.kind=='animation' or data.kind=='ped' then
        local hash=requestModel(data.kind=='ped' and data.model or 'a_m_y_business_01')
        if not IsModelAPed(hash) then SetModelAsNoLongerNeeded(hash); error('Selecione um modelo de ped.') end
        preview=CreatePed(4,hash,p.x,p.y,p.z,p.w,false,false)
        SetModelAsNoLongerNeeded(hash)
        if preview==0 then error('Nao foi possivel criar o ped de teste.') end
        previewItems[#previewItems+1]=preview
        -- CreatePed pode ajustar a altura de nascimento. Usa a mesma origem exata
        -- do personagem no assalto, antes de iniciar a animacao.
        SetEntityCoordsNoOffset(preview,p.x,p.y,p.z,false,false,false)
        SetEntityHeading(preview,p.w)
        SetEntityInvincible(preview,true); SetBlockingOfNonTemporaryEvents(preview,true)
        if data.kind=='animation' then
            local dict,clip=tostring(data.dict or ''),tostring(data.clip or '')
            if dict=='' or clip=='' then error('Informe dicionario e nome da animacao.') end
            RequestAnimDict(dict)
            local deadline=GetGameTimer()+4000
            while open and not HasAnimDictLoaded(dict) and GetGameTimer()<deadline do Wait(0) end
            if not open then error('Editor fechado.') end
            if not HasAnimDictLoaded(dict) then error('Dicionario de animacao nao encontrado.') end
            if GetAnimDuration(dict,clip)<=0 then error('Clipe nao encontrado nesse dicionario.') end
            TaskPlayAnim(preview,dict,clip,4.0,-4.0,10000,0,0.0,false,false,false)
            local function attach(name,bone,x,y,z,rx,ry,rz)
                local model=requestModel(name)
                local obj=CreateObjectNoOffset(model,p.x,p.y,p.z,false,false,false)
                SetModelAsNoLongerNeeded(model)
                if obj==0 then error('Falha ao criar prop de teste.') end
                previewItems[#previewItems+1]=obj
                SetEntityCollision(obj,false,false)
                AttachEntityToEntity(obj,preview,GetPedBoneIndex(preview,bone),x,y,z,rx,ry,rz,true,true,false,true,1,true)
            end
            if data.preset=='thermite' then
                attach('hei_p_m_bag_var22_arm_s',24818,0.05,-0.18,0,0,90,0)
                attach('hei_prop_heist_thermite',28422,0,0,0,0,0,200)
            elseif data.preset=='cash' then
                attach('hei_p_m_bag_var22_arm_s',24818,0.05,-0.18,0,0,90,0)
                attach('hei_prop_heist_cash_pile',60309,0,0,0,0,0,0)
            elseif data.preset=='keycard' then attach('p_ld_id_card_01',28422,0.12,0.028,0.001,10,175,0)
            elseif data.attachedModel and data.attachedModel~='' then
                attach(data.attachedModel,tonumber(data.bone) or 28422,tonumber(data.ax) or 0,tonumber(data.ay) or 0,tonumber(data.az) or 0,0,0,0)
            end
        end
    else
        local hash=requestModel(data.kind=='fx' and 'prop_mp_cone_01' or data.model or 'prop_mp_cone_01')
        if IsModelAPed(hash) or IsModelAVehicle(hash) then SetModelAsNoLongerNeeded(hash); error('Escolha um prop, nao ped/veiculo.') end
        local create=data.kind~='fx' and data.adjustHeight and CreateObject or CreateObjectNoOffset
        preview=create(hash,p.x,p.y,p.z,false,false,false)
        SetModelAsNoLongerNeeded(hash)
        if preview==0 then error('Falha ao criar previa do prop.') end
        previewItems[#previewItems+1]=preview
        if data.kind=='fx' then SetEntityAlpha(preview,0,false) end
    end
    SetEntityAsMissionEntity(preview,true,true)
    FreezeEntityPosition(preview,true); SetEntityCollision(preview,false,false)
    SetEntityRotation(preview,p.rx,p.ry,p.w,2,true)
    if data.kind=='fx' then
        RequestNamedPtfxAsset('scr_ornate_heist')
        local deadline=GetGameTimer()+3000
        while open and not HasNamedPtfxAssetLoaded('scr_ornate_heist') and GetGameTimer()<deadline do Wait(0) end
        if not open then error('Editor fechado.') end
        if not HasNamedPtfxAssetLoaded('scr_ornate_heist') then error('Nao foi possivel carregar o fogo de teste.') end
        placePreviewFire(p)
    end
    return true
end
local function captured(entity,p)
    p=p or GetEntityCoords(entity)
    local r=entity and GetEntityRotation(entity,2) or vector3(0,0,GetEntityHeading(PlayerPedId()))
    local model=entity and GetEntityModel(entity) or nil
    local name
    if entity then local ok,result=pcall(GetEntityArchetypeName,entity); if ok then name=result end end
    return {point={x=p.x,y=p.y,z=p.z,w=r.z,rx=r.x,ry=r.y},model=name or model,adjustHeight=false}
end
RegisterNUICallback('layoutData',function(data,cb)
    if not open or not bankResources[data.resource] or GetResourceState(data.resource)~='started' then return cb({error='Recurso indisponivel.'}) end
    local result,err=OR.Callback.awaitResource(data.resource,'layoutEditorData')
    cb(result and {ok=true,data=result} or {error=err or 'Sem acesso.'})
end)
RegisterNUICallback('layoutSave',function(data,cb)
    if not open or not bankResources[data.resource] then return cb({error='Editor fechado.'}) end
    local result,err=OR.Callback.awaitResource(data.resource,'layoutEditorSave',data)
    cb(result and {ok=true,data=result,message=err} or {error=err or 'Falha ao salvar.'})
end)
RegisterNUICallback('layoutTool',function(data,cb)
    if not open or captureMode or toolBusy then return cb({error='Editor indisponivel.'}) end
    toolBusy=true
    local ok,result=pcall(function()
        if data.tool=='self' then return captured(PlayerPedId()) end
        if data.tool=='clear' then clearPreview(); return {} end
        if data.tool=='teleport' then
            local allowed=OR.Callback.awaitResource('ob_editor','getAccess')
            local p=point(data.point)
            if not allowed or not p then error('Sem acesso ou posicao invalida.') end
            clearPreview()
            SetEntityCoords(PlayerPedId(),p.x,p.y,p.z,false,false,false,false)
            SetEntityHeading(PlayerPedId(),p.w)
            return {}
        end
        if data.tool=='preview' or data.tool=='move' then
            -- Libera a visao ANTES de carregar/iniciar a animacao, nao depois dos 10 s.
            beginCapture('loading')
            createPreview(data)
            if not open then error('Editor fechado.') end
            beginCapture(data.tool=='preview' and 'preview' or 'move')
        end
        if data.tool=='laser' then clearPreview() end
        if data.tool=='laser' then beginCapture('laser') end
        return {}
    end)
    if not ok then clearPreview(); finishCapture() end
    toolBusy=false
    cb(ok and {ok=true,data=result} or {error=tostring(result)})
end)

local function updateLaser()
    local now=GetGameTimer()
    if laserRay then
        local status,hit,p,_,entity=GetShapeTestResult(laserRay)
        if status==2 then
            laserRay=nil
            if hit==true or hit==1 then
                laserTarget={point=p,entity=entity or 0,at=now}
            else laserTarget=nil end
        elseif status==0 or now-laserStarted>2000 then laserRay,laserTarget=nil,nil end
    end
    if not laserRay then
        local origin,rotation=GetGameplayCamCoord(),GetGameplayCamRot(2)
        local x,z=math.rad(rotation.x),math.rad(rotation.z)
        local dest=origin+vector3(-math.sin(z)*math.cos(x),math.cos(z)*math.cos(x),math.sin(x))*60
        -- Mundo + objetos + vidro. Opcoes 0: nao ignora vidro, grades transparentes
        -- ou props sem colisao. Nunca usa resultados ainda pendentes do raycast.
        laserRay=StartShapeTestLosProbe(origin.x,origin.y,origin.z,dest.x,dest.y,dest.z,81,PlayerPedId(),0)
        laserStarted=now
    end
    if laserTarget and now-laserTarget.at>250 then laserTarget=nil end
    return laserTarget
end
local function drawLaserTarget(target)
    DrawRect(0.5,0.5,0.012,0.002,70,220,255,230)
    DrawRect(0.5,0.5,0.001,0.020,70,220,255,230)
    if not target then return 'Nenhum ponto atingido. Aproxime-se e mire na superficie.' end
    local p=target.point
    local origin=GetGameplayCamCoord()
    DrawLine(origin.x,origin.y,origin.z,p.x,p.y,p.z,50,200,255,220)
    DrawMarker(28,p.x,p.y,p.z,0,0,0,0,0,0,0.055,0.055,0.055,50,220,255,200,false,false,2,false,nil,nil,false)
    local entity=target.entity
    if entity~=0 and DoesEntityExist(entity) then
        local name=tostring(GetEntityModel(entity))
        local ok,result=pcall(GetEntityArchetypeName,entity)
        if ok and type(result)=='string' and result~='' then name=result end
        return name..' | ENTER: origem do objeto | E: ponto exato na superficie'
    end
    return 'Superficie do mapa (sem objeto selecionavel) | E: capturar ponto exato'
end
CreateThread(function()
    while true do
        if not captureMode then Wait(300) else
            Wait(0)
            DisableAllControlActions(0)
            EnableControlAction(0,1,true); EnableControlAction(0,2,true)
            if captureMode=='preview' or captureMode=='laser' then
                EnableControlAction(0,30,true); EnableControlAction(0,31,true); EnableControlAction(0,21,true)
            end
            local target=captureMode=='laser' and updateLaser() or nil
            local text=captureMode=='laser' and drawLaserTarget(target)
                or captureMode=='loading' and 'Carregando a previa...'
                or captureMode=='preview' and 'Teste no mundo: WASD andar | MOUSE olhar | ENTER / ESC voltar ao painel'
                or 'SETAS mover | Q/E altura | RODA: Z | A+RODA: X | D+RODA: Y | SHIFT fino | ENTER confirmar | ESC cancelar'
            text=text..(captureMode=='laser' and ' | ESC voltar' or '')
            OR.Help.Show(text)
            if captureMode=='loading' then
                -- Nao reabre a NUI durante uma requisicao de modelo/animacao em andamento.
            elseif IsDisabledControlJustPressed(0,200) or IsDisabledControlJustPressed(0,177) then
                if captureMode~='preview' then clearPreview() end
                finishCapture()
            elseif captureMode=='preview' then
                if IsDisabledControlJustPressed(0,191) then finishCapture() end
            elseif captureMode=='move' and preview and DoesEntityExist(preview) then
                local p=GetEntityCoords(preview)
                local step=(IsDisabledControlPressed(0,21) and 0.08 or 0.8)*GetFrameTime()
                local dx=(IsDisabledControlPressed(0,175) and step or 0)-(IsDisabledControlPressed(0,174) and step or 0)
                local dy=(IsDisabledControlPressed(0,172) and step or 0)-(IsDisabledControlPressed(0,173) and step or 0)
                local dz=(IsDisabledControlPressed(0,44) and step or 0)-(IsDisabledControlPressed(0,38) and step or 0)
                SetEntityCoordsNoOffset(preview,p.x+dx,p.y+dy,p.z+dz,false,false,false)
                if previewFx and (dx~=0 or dy~=0 or dz~=0) then
                    SetParticleFxLoopedOffsets(previewFx,p.x+dx,p.y+dy,p.z+dz,0.0,0.0,0.0)
                end
                local wheel=(IsDisabledControlJustPressed(0,241) and 1 or 0)-(IsDisabledControlJustPressed(0,242) and 1 or 0)
                if wheel~=0 then
                    local r=GetEntityRotation(preview,2)
                    local amount=wheel*(IsDisabledControlPressed(0,21) and 0.1 or 1.0)
                    local x,y,z=r.x,r.y,r.z
                    if IsDisabledControlPressed(0,34) then x=x+amount
                    elseif IsDisabledControlPressed(0,35) then y=y+amount
                    else z=z+amount end
                    SetEntityRotation(preview,x,y,z,2,true)
                end
                if IsDisabledControlJustPressed(0,191) then SendNUIMessage({action='layoutCaptured',data=captured(preview)}); finishCapture() end
            elseif captureMode=='laser' then
                if target then
                    if IsDisabledControlJustPressed(0,191) then
                        if target.entity~=0 and DoesEntityExist(target.entity) then
                            SendNUIMessage({action='layoutCaptured',data=captured(target.entity)}); finishCapture()
                        else OR.Notify('Esta superficie nao tem entidade propria. Use E para capturar o ponto exato.','info') end
                    elseif IsDisabledControlJustPressed(0,38) then SendNUIMessage({action='layoutCaptured',data=captured(nil,target.point)}); finishCapture() end
                end
            end
        end
    end
end)
AddEventHandler('onClientResourceStop',function(name)
    if name==GetCurrentResourceName() then open=false; finishCapture(); clearPreview() end
end)
