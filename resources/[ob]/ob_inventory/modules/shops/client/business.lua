local commerceOpen = false
local commerceShopId
local activeDeliveries = {}
local managerPeds = {}
local depotPeds = {}
local managerDefinitions = {}
local depotDefinitions = {}
local managerStreamBusy = false
local trackingRequests = {}
local ensureActiveDeliveries
ORInventoryShopBusinessClient = ORInventoryShopBusinessClient or {}
function ORInventoryShopBusinessClient.IsManagerPed(ped)
    for _,entity in pairs(managerPeds)do if entity==ped and DoesEntityExist(entity)then return true end end
    for _,entity in pairs(depotPeds)do if entity==ped and DoesEntityExist(entity)then return true end end
    for _,delivery in pairs(activeDeliveries)do if delivery.driver==ped and DoesEntityExist(ped)then return true end end
    return false
end

local function notify(message, kind)
    if OR and OR.Notify then OR.Notify(message, kind or 'inform') end
end

local function request(name, ...)
    local ok, payload, message = OR.Callback.awaitResource('ob_inventory', name, ...)
    return ok == true and payload or nil, ok == true and message or payload or message
end

local function openCommerce(shopId)
    if commerceOpen or IsNuiFocused() or LocalPlayer.state['or:loaded'] ~= true then return end
    CreateThread(function()
        local data, err = request('commercePanel', shopId)
        if not data then return notify(err or 'Comercio indisponivel.', 'error') end
        commerceOpen = true
        commerceShopId = type(shopId)=='string' and shopId or nil
        SetNuiFocus(true, true)
        SendNUIMessage({ action='commerceOpen', data=data, contextShopId=shopId })
        if ensureActiveDeliveries then ensureActiveDeliveries(data,false) end
    end)
end

local function closeCommerce()
    if not commerceOpen then return end
    commerceOpen = false
    commerceShopId = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action='commerceClose' })
end

RegisterCommand('comercio', function() openCommerce(nil) end, false)
RegisterNetEvent('ob_inventory:client:openCommerce', function(shopId) openCommerce(shopId) end)
RegisterNetEvent('ob_inventory:client:commerceRefresh', function()
    if not commerceOpen then return end
    CreateThread(function()
        local data = request('commercePanel',commerceShopId)
        if data then
            SendNUIMessage({action='commerceData',data=data})
            if ensureActiveDeliveries then ensureActiveDeliveries(data,false) end
        end
    end)
end)

RegisterNUICallback('commerceClose', function(_,cb) closeCommerce(); cb({ok=true}) end)
RegisterNUICallback('commerceFiscal', function(data, cb)
    local shopId = type(data)=='table' and tostring(data.shopId or '') or ''
    if shopId=='' or GetResourceState('ob_fiscal')~='started' then
        return cb({ok=false,message='Contabilidade fiscal indisponivel.'})
    end
    cb({ok=true})
    closeCommerce()
    TriggerEvent('ob_fiscal:client:openAtShop',shopId)
end)
RegisterNUICallback('commerceCancelOrder',function(data,cb)
    local result,message=request('commerceCancelDelivery',data and data.orderId)
    cb({ok=result~=nil,message=message or result})
    if result~=nil then
        local refreshed=request('commercePanel',commerceShopId)
        if refreshed then SendNUIMessage({action='commerceData',data=refreshed}) end
    end
end)
RegisterNUICallback('commerceTrackOrder',function(data,cb)
    local orderId=tonumber(data and data.orderId)
    if not orderId then return cb({ok=false,message='Pedido invalido.'}) end
    TriggerEvent('ob_inventory:client:trackShopDelivery',orderId,true)
    CreateThread(function()
        local timeout=GetGameTimer()+15000
        while GetGameTimer()<timeout do
            local delivery=activeDeliveries[orderId]
            if delivery and delivery.vehicle and DoesEntityExist(delivery.vehicle)
                and delivery.blip and DoesBlipExist(delivery.blip) then
                local coords=GetEntityCoords(delivery.vehicle)
                SetBlipCoords(delivery.blip,coords.x,coords.y,coords.z)
                SetBlipDisplay(delivery.blip,4)
                local routeBlip=delivery.routeBlip and DoesBlipExist(delivery.routeBlip) and delivery.routeBlip
                if routeBlip then
                    SetBlipDisplay(routeBlip,4)
                    SetBlipRoute(routeBlip,true)
                    SetBlipRouteColour(routeBlip,5)
                end
                return cb({ok=true,message='Caminhao localizado. O blip vermelho foi atualizado.'})
            end
            Wait(250)
        end
        cb({ok=false,message='O pedido existe, mas o caminhao nao apareceu. Confira o F8 ou cancele o pedido para estornar.'})
    end)
end)
for nui,callback in pairs({
    commercePurchase='commercePurchase', commerceRename='commerceRename', commerceSetPrice='commerceSetPrice',
    commerceWithdraw='commerceWithdraw', commerceDeposit='commerceDeposit', commerceOrder='commerceOrder',
}) do
    RegisterNUICallback(nui,function(data,cb)
        local result,message=request(callback,data)
        cb({ok=result~=nil,message=message or result})
        if result~=nil then
            local refreshed=request('commercePanel',commerceShopId)
            if refreshed then
                SendNUIMessage({action='commerceData',data=refreshed})
                if ensureActiveDeliveries then ensureActiveDeliveries(refreshed,false) end
            end
        end
    end)
end

local function model(name)
    local hash=type(name)=='number' and name or joaat(name)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash); local timeout=GetGameTimer()+10000
    while not HasModelLoaded(hash) and GetGameTimer()<timeout do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function cleanup(orderId)
    local delivery=activeDeliveries[orderId]; if not delivery then return end
    TriggerServerEvent('ob_inventory:server:releaseDeliveryEntities',orderId)
    if GetResourceState('ob_target')=='started' and delivery.driver then exports.ob_target:RemoveEntityOption(('ob_inventory:delivery:%s'):format(orderId)) end
    if GetResourceState('ob_target')=='started' and delivery.vehicle then exports.ob_target:RemoveEntityOption(('ob_inventory:pickup:%s'):format(orderId)) end
    if GetResourceState('ob_target')=='started' then exports.ob_target:UnregisterZone(('ob_inventory:pickup_dropoff:%s'):format(orderId)) end
    if delivery.blip and DoesBlipExist(delivery.blip) then RemoveBlip(delivery.blip) end
    if delivery.routeBlip and DoesBlipExist(delivery.routeBlip) then RemoveBlip(delivery.routeBlip) end
    if delivery.cargo and DoesEntityExist(delivery.cargo) then DeleteEntity(delivery.cargo) end
    -- Veiculo e motorista pertencem ao servidor. Ele remove primeiro a chave
    -- temporaria e depois as entidades, evitando deixar uma chave fantasma.
    activeDeliveries[orderId]=nil
end

local function point(raw)
    return type(raw)=='table' and tonumber(raw.x) and {
        x=tonumber(raw.x),y=tonumber(raw.y),z=tonumber(raw.z),w=tonumber(raw.w) or 0.0,
    } or nil
end

local function routeTo(delivery,coords,label,enableRoute)
    if delivery.routeBlip and DoesBlipExist(delivery.routeBlip) then RemoveBlip(delivery.routeBlip) end
    delivery.routeBlip=AddBlipForCoord(coords.x,coords.y,coords.z)
    SetBlipSprite(delivery.routeBlip,1);SetBlipColour(delivery.routeBlip,5);SetBlipScale(delivery.routeBlip,0.82)
    SetBlipRoute(delivery.routeBlip,enableRoute~=false);SetBlipRouteColour(delivery.routeBlip,5)
    BeginTextCommandSetBlipName('STRING');AddTextComponentString(label);EndTextCommandSetBlipName(delivery.routeBlip)
end

local function createTruckBlip(coords,label)
    local blip=AddBlipForCoord(coords.x,coords.y,coords.z)
    if not blip or blip==0 or not DoesBlipExist(blip) then return nil end
    SetBlipSprite(blip,67)
    SetBlipColour(blip,1)
    SetBlipScale(blip,0.9)
    SetBlipDisplay(blip,4)
    SetBlipAsShortRange(blip,false)
    SetBlipHighDetail(blip,true)
    SetBlipRoute(blip,false)
    BeginTextCommandSetBlipName('STRING');AddTextComponentString(label);EndTextCommandSetBlipName(blip)
    return blip
end

local function followTruckBlip(orderId)
    CreateThread(function()
        while true do
            local delivery=activeDeliveries[orderId]
            if not delivery or not delivery.vehicle or not DoesEntityExist(delivery.vehicle) then return end
            if not delivery.blip or not DoesBlipExist(delivery.blip) then
                print(('[ob_inventory] Entrega #%s perdeu o blip do caminhao.'):format(orderId))
                return
            end
            local coords=GetEntityCoords(delivery.vehicle)
            SetBlipCoords(delivery.blip,coords.x,coords.y,coords.z)
            Wait(750)
        end
    end)
end

local function protectNpcTruck(orderId)
    CreateThread(function()
        while true do
            local delivery=activeDeliveries[orderId]
            if not delivery or delivery.method~='npc' or not delivery.vehicle or not DoesEntityExist(delivery.vehicle) then return end
            SetVehicleDoorsLocked(delivery.vehicle,delivery.allowDriverEntry and 1 or 2)
            SetVehicleDoorsLockedForAllPlayers(delivery.vehicle,true)
            SetVehicleCanBeUsedByFleeingPeds(delivery.vehicle,false)
            if delivery.driver and DoesEntityExist(delivery.driver) then
                SetPedCanBeDraggedOut(delivery.driver,false)
                SetPedStayInVehicleWhenJacked(delivery.driver,true)
            end
            Wait(1000)
        end
    end)
end

local function closestPickupDepot(origin)
    local closest,index,distance
    for depotIndex,depot in ipairs((((ORInventoryShops.Business or {}).Delivery or {}).PickupDepots or {})) do
        local coords=point(depot.coords or depot)
        if coords then
            local current=#(vector3(origin.x,origin.y,origin.z)-vector3(coords.x,coords.y,coords.z))
            if not distance or current<distance then closest,index,distance={id=depot.id,label=depot.label,coords=coords},depotIndex,current end
        end
    end
    return closest,index
end

local function startCarryingCargo(delivery)
    if delivery.cargo and DoesEntityExist(delivery.cargo) then return true end
    local ped=PlayerPedId()
    local cargoHash=model((((ORInventoryShops.Business or {}).Delivery or {}).CargoModel) or 'prop_cs_cardbox_01')
    if not cargoHash then return false end
    local coords=GetEntityCoords(ped)
    local cargo=CreateObject(cargoHash,coords.x,coords.y,coords.z,false,false,false)
    SetModelAsNoLongerNeeded(cargoHash)
    if not cargo or cargo==0 then return false end
    SetEntityCollision(cargo,false,false)
    AttachEntityToEntity(cargo,ped,GetPedBoneIndex(ped,28422),0.01,-0.02,-0.02,0.0,0.0,0.0,true,true,false,true,1,true)
    RequestAnimDict('anim@heists@box_carry@')
    local timeout=GetGameTimer()+5000
    while not HasAnimDictLoaded('anim@heists@box_carry@') and GetGameTimer()<timeout do Wait(0) end
    if not HasAnimDictLoaded('anim@heists@box_carry@') then DeleteEntity(cargo);return false end
    TaskPlayAnim(ped,'anim@heists@box_carry@','idle',8.0,-8.0,-1,49,0,false,false,false)
    delivery.cargo=cargo
    return true
end

local function stopCarryingCargo(delivery)
    local ped=PlayerPedId()
    StopAnimTask(ped,'anim@heists@box_carry@','idle',2.0)
    if delivery.cargo and DoesEntityExist(delivery.cargo) then
        DetachEntity(delivery.cargo,true,true)
        DeleteEntity(delivery.cargo)
    end
    delivery.cargo=nil
end

local function registerPickupTarget(orderId,label)
    local delivery=activeDeliveries[orderId]
    if not delivery or not delivery.vehicle or GetResourceState('ob_target')~='started' then return end
    local key=('ob_inventory:pickup:%s'):format(orderId)
    local minimum=select(1,GetModelDimensions(GetEntityModel(delivery.vehicle)))
    local rearOffset=minimum and tonumber(minimum.y) or -4.0
    local targetDistance=math.max(6.0,math.abs(rearOffset)+3.0)
    exports.ob_target:RemoveEntityOption(key)
    exports.ob_target:RegisterEntity(key,delivery.vehicle,{
        label=label,event='ob_inventory:client:pickupDeliveryAction',distance=targetDistance,
        targetPoint=function(entity)
            local bounds=select(1,GetModelDimensions(GetEntityModel(entity)))
            local rearY=(bounds and tonumber(bounds.y) or -4.0)-0.35
            return GetOffsetFromEntityInWorldCoords(entity,0.0,rearY,0.55)
        end,
        canInteract=function(entity)
            local current=activeDeliveries[orderId]
            if not current or current.busy or current.vehicle~=entity then return false end
            local target=(current.stage=='loading' and current.depot and current.depot.coords)
                or ((current.stage=='to_store' or current.stage=='store_done') and current.destination) or nil
            if not target or #(GetEntityCoords(entity)-vector3(target.x,target.y,target.z))>15.0 then return false end
            local bounds=select(1,GetModelDimensions(GetEntityModel(entity)))
            local rearY=(bounds and tonumber(bounds.y) or -4.0)-0.35
            local rear=GetOffsetFromEntityInWorldCoords(entity,0.0,rearY,0.35)
            return #(GetEntityCoords(PlayerPedId())-rear)<=3.5
        end,
    })
end

local function registerPickupDropoffTarget(orderId)
    local delivery=activeDeliveries[orderId]
    local coords=delivery and delivery.deliveryPoint
    if not coords or GetResourceState('ob_target')~='started' then return end
    local key=('ob_inventory:pickup_dropoff:%s'):format(orderId)
    exports.ob_target:UnregisterZone(key)
    exports.ob_target:RegisterSphereZone(key,{
        coords=vector3(coords.x,coords.y,coords.z),radius=3.0,
        option={
            label='Entregar mercadoria na loja',distance=3.0,
            canInteract=function()
                local current=activeDeliveries[orderId]
                return current and current.stage=='delivering' and not current.busy
            end,
            action=function() TriggerEvent('ob_inventory:client:finishPickupDropoff',orderId) end,
        },
    })
    if not delivery.dropoffMarkerStarted then
        delivery.dropoffMarkerStarted=true
        CreateThread(function()
            while true do
                local current=activeDeliveries[orderId]
                if not current or current.stage~='delivering' then break end
                DrawMarker(1,coords.x,coords.y,coords.z-1.0,0.0,0.0,0.0,0.0,0.0,0.0,1.4,1.4,0.35,20,175,235,115,false,false,2,false,nil,nil,false)
                Wait(0)
            end
            if activeDeliveries[orderId] then activeDeliveries[orderId].dropoffMarkerStarted=nil end
        end)
    end
end

local function waitForPickupTruckHorn(orderId)
    CreateThread(function()
        while true do
            local delivery=activeDeliveries[orderId]
            if not delivery or delivery.stage~='store_done' or not delivery.vehicle or not DoesEntityExist(delivery.vehicle) then return end
            local ped=PlayerPedId()
            if GetPedInVehicleSeat(delivery.vehicle,-1)==ped
                and #(GetEntityCoords(delivery.vehicle)-vector3(delivery.destination.x,delivery.destination.y,delivery.destination.z))<=15.0
                and IsControlJustPressed(0,86) then
                notify('Caminhao guardado. Entrega encerrada.','success')
                cleanup(orderId)
                return
            end
            Wait(0)
        end
    end)
end

local function pickupForDepot(depotIndex)
    local configured=((((ORInventoryShops.Business or {}).Delivery or {}).PickupDepots or {})[depotIndex])
    local configuredCoords=configured and point(configured.coords or configured)
    for orderId,delivery in pairs(activeDeliveries) do
        if delivery.method=='pickup' then
            local deliveryCoords=delivery.depot and delivery.depot.coords
            local sameDepot=delivery.depotIndex==depotIndex
                or (configuredCoords and deliveryCoords
                    and #(vector3(configuredCoords.x,configuredCoords.y,configuredCoords.z)
                        -vector3(deliveryCoords.x,deliveryCoords.y,deliveryCoords.z))<=5.0)
            if sameDepot then
                return orderId,delivery
            end
        end
    end
end

local function recoverPickupForDepot(depotIndex)
    local orderId,delivery=pickupForDepot(depotIndex)
    if orderId and not delivery.starting then return orderId,delivery end
    local ok,orders=OR.Callback.awaitResource('ob_inventory','commerceResumeDeliveries')
    if ok==true and type(orders)=='table' then
        for _,order in ipairs(orders) do
            if order.method=='pickup' and order.shop then
                local destination=point(order.shop.truckStop or order.shop.npcTruckStop or order.shop.dropoff or order.shop.coords)
                local _,nearestIndex=destination and closestPickupDepot(destination)
                if nearestIndex==depotIndex then
                    TriggerEvent('ob_inventory:client:startShopDelivery',order)
                    orderId=tonumber(order.id)
                    break
                end
            end
        end
    end
    local timeout=GetGameTimer()+20000
    while orderId and GetGameTimer()<timeout do
        delivery=activeDeliveries[orderId]
        if delivery and not delivery.starting then return orderId,delivery end
        Wait(100)
    end
    return pickupForDepot(depotIndex)
end

local function registerDepotTarget(index,ped)
    if GetResourceState('ob_target')~='started' or not ped or not DoesEntityExist(ped) then return end
    local key=('ob_inventory:depot:%s'):format(index)
    exports.ob_target:RemoveEntityOption(key)
    exports.ob_target:RegisterEntity(key,ped,{
        label='Retirar mercadoria da loja',event='ob_inventory:client:loadPickupCargo',distance=2.5,
        canInteract=function(entity)return depotPeds[index]==entity end,
    })
end

RegisterNetEvent('ob_inventory:client:loadPickupCargo',function(entity)
    for index,ped in pairs(depotPeds) do
        if ped==entity then
            CreateThread(function()
                local orderId,delivery=recoverPickupForDepot(index)
                if not orderId or not delivery then return notify('Nao existe pedido de retirada ativo para este centro.','error') end
                if delivery.stage=='loading' then return notify('A mercadoria ja foi retirada. Coloque a caixa no caminhao.','inform') end
                if delivery.stage=='to_store' then return notify('A mercadoria ja esta no caminhao. Leve-a para sua loja.','inform') end
                if delivery.stage=='delivering' then return notify('Leve a caixa ate o ponto de entrega da loja e use o target.','inform') end
                if delivery.stage=='store_done' then return notify('A mercadoria ja foi entregue. Guarde o caminhao na loja.','inform') end
                if delivery.stage~='to_depot' then return notify('A entrega ainda esta sendo preparada. Tente novamente em alguns segundos.','inform') end
                if not delivery.vehicle or not DoesEntityExist(delivery.vehicle) then
                    return notify('O caminhao do pedido nao esta sincronizado. Use o painel para destacar novamente a entrega.','error')
                end
                local depot=delivery.depot and delivery.depot.coords
                local distance=depot and #(GetEntityCoords(delivery.vehicle)-vector3(depot.x,depot.y,depot.z)) or nil
                if not distance or distance>40.0 then
                    return notify(('Aproxime o caminhao deste atendente. Distancia atual: %d metros.'):format(math.floor(distance or 0.0)),'error')
                end
                if delivery.busy then return end
                delivery.busy=true
                if not activeDeliveries[orderId] or not DoesEntityExist(delivery.vehicle) then delivery.busy=false;return end
                if not startCarryingCargo(delivery) then delivery.busy=false;return notify('Nao foi possivel preparar a caixa da mercadoria.','error') end
                delivery.stage='loading'
                delivery.busy=false
                if delivery.routeBlip and DoesBlipExist(delivery.routeBlip) then RemoveBlip(delivery.routeBlip);delivery.routeBlip=nil end
                registerPickupTarget(orderId,'Colocar mercadoria no caminhao')
                notify('Mercadoria retirada. Leve a caixa ate a traseira do caminhao.','success')
            end)
            return
        end
    end
end)

local function waitForNetworkEntity(netId,kind)
    netId=tonumber(netId)
    if not netId or netId==0 then return nil end
    local timeout=GetGameTimer()+15000
    while GetGameTimer()<timeout do
        if NetworkDoesEntityExistWithNetworkId(netId) then
            local entity=kind=='ped' and NetToPed(netId) or NetToVeh(netId)
            if entity and entity~=0 and DoesEntityExist(entity) then return entity end
        end
        Wait(50)
    end
end

local function waitForNetworkControl(entity)
    local timeout=GetGameTimer()+5000
    while DoesEntityExist(entity) and not NetworkHasControlOfEntity(entity) and GetGameTimer()<timeout do
        NetworkRequestControlOfEntity(entity)
        Wait(50)
    end
    return DoesEntityExist(entity) and NetworkHasControlOfEntity(entity)
end

RegisterNetEvent('ob_inventory:client:startShopDelivery',function(order)
    if type(order)~='table' or not order.id or not order.shop then return end
    order.id=tonumber(order.id)
    if not order.id then return end
    if activeDeliveries[order.id] then return end
    -- Reserva o pedido imediatamente. O painel e o evento do servidor podem tentar
    -- recuperar a mesma entrega no mesmo frame.
    activeDeliveries[order.id]={starting=true}
    local shop=order.shop
    if order.method=='pickup' then
        local destination=point(shop.truckStop or shop.npcTruckStop or shop.dropoff or shop.coords)
        local deliveryPoint=point(shop.dropoff or shop.manager or shop.coords)
        local spawn=destination
        local depot,depotIndex=destination and closestPickupDepot(destination)
        if not spawn or not destination or not deliveryPoint or not depot then
            activeDeliveries[order.id]=nil
            request('commerceCancelDelivery',order.id)
            notify('A rota de retirada ou os centros de distribuicao estao incompletos. O valor voltou ao caixa.','error')
            return
        end
        local spawned,spawnError=request('commerceSpawnDeliveryEntities',order.id)
        if not spawned then
            activeDeliveries[order.id]=nil
            request('commerceCancelDelivery',order.id)
            notify((spawnError or 'Nao foi possivel criar o caminhao.')..' O valor voltou ao caixa.','error')
            return
        end
        local vehicle=waitForNetworkEntity(spawned.vehicleNetId,'vehicle')
        if not vehicle then
            activeDeliveries[order.id]=nil
            TriggerServerEvent('ob_inventory:server:releaseDeliveryEntities',order.id)
            request('commerceCancelDelivery',order.id)
            notify('O caminhao foi criado pelo servidor, mas nao sincronizou no cliente. O valor voltou ao caixa.','error')
            return
        end
        waitForNetworkControl(vehicle)
        SetVehicleNumberPlateText(vehicle,('OB%05d'):format(order.id%100000));SetVehicleOnGroundProperly(vehicle)
        SetVehicleDoorsLocked(vehicle,1);FreezeEntityPosition(vehicle,false);SetVehicleEngineOn(vehicle,false,true,false)
        local blip=createTruckBlip(spawn,'Caminhao do pedido')
        if not blip then
            activeDeliveries[order.id]=nil
            TriggerServerEvent('ob_inventory:server:releaseDeliveryEntities',order.id)
            request('commerceCancelDelivery',order.id)
            print(('[ob_inventory] Entrega #%s: AddBlipForCoord falhou na retirada.'):format(order.id))
            notify('Nao foi possivel criar o marcador do caminhao. O valor voltou ao caixa.','error')
            return
        end
        activeDeliveries[order.id]={vehicle=vehicle,blip=blip,method='pickup',stage='to_depot',pickupPoint=spawn,
            destination=destination,deliveryPoint=deliveryPoint,depot=depot,depotIndex=depotIndex,shopId=order.shopId}
        routeTo(activeDeliveries[order.id],depot.coords,depot.label or 'Centro de distribuicao')
        followTruckBlip(order.id)
        notify(('O caminhao esta ao lado da loja e a chave foi entregue. Leve-o ate %s para carregar.'):format(depot.label or 'o centro de distribuicao'),'success')
        return
    end
    local stop=shop.truckStop or shop.npcTruckStop
    local walkPoint=point(shop.npcWalkPoint)
    local drop=point(shop.dropoff or shop.manager or shop.coords)
    if not stop or not walkPoint or not drop then
        activeDeliveries[order.id]=nil
        request('commerceCancelDelivery',order.id)
        notify('A rota desta loja esta incompleta. O valor voltou ao caixa.','error')
        return
    end
    CreateThread(function()
        local spawn=point(shop.npcSpawn)
        if not spawn then
            activeDeliveries[order.id]=nil
            request('commerceCancelDelivery',order.id)
            return notify('Configure o nascimento do caminhao NPC no editor da loja. O valor voltou ao caixa.','error')
        end
        if IsPositionOccupied(spawn.x,spawn.y,spawn.z,7.0,false,true,true,false,false,0,false) then
            activeDeliveries[order.id]=nil
            request('commerceCancelDelivery',order.id)
            return notify('O ponto de nascimento do caminhao esta ocupado. O valor voltou ao caixa.','error')
        end
        local spawned,spawnError=request('commerceSpawnDeliveryEntities',order.id)
        if not spawned then
            activeDeliveries[order.id]=nil
            request('commerceCancelDelivery',order.id)
            return notify((spawnError or 'Nao foi possivel criar a entrega.')..' O valor voltou ao caixa.','error')
        end
        local vehicle=waitForNetworkEntity(spawned.vehicleNetId,'vehicle')
        local driver=waitForNetworkEntity(spawned.driverNetId,'ped')
        if not vehicle or not driver then
            activeDeliveries[order.id]=nil
            TriggerServerEvent('ob_inventory:server:releaseDeliveryEntities',order.id)
            request('commerceCancelDelivery',order.id)
            return notify('A entrega foi criada pelo servidor, mas nao sincronizou no cliente. O valor voltou ao caixa.','error')
        end
        local vehicleControl=waitForNetworkControl(vehicle)
        local driverControl=waitForNetworkControl(driver)
        SetVehicleNumberPlateText(vehicle,('OB%05d'):format(order.id%100000));SetVehicleOnGroundProperly(vehicle)
        if not IsPedInVehicle(driver,vehicle,false) and vehicleControl and driverControl then TaskWarpPedIntoVehicle(driver,vehicle,-1) end
        SetEntityAsMissionEntity(vehicle,true,true); SetEntityAsMissionEntity(driver,true,true)
        SetBlockingOfNonTemporaryEvents(driver,true)
        SetPedCanBeDraggedOut(driver,false)
        SetPedFleeAttributes(driver,0,false)
        SetDriverAbility(driver,1.0)
        SetDriverAggressiveness(driver,0.0)
        SetPedKeepTask(driver,true)
        FreezeEntityPosition(vehicle,false)
        SetVehicleUndriveable(vehicle,false)
        SetVehicleHandbrake(vehicle,false)
        SetVehicleEngineOn(vehicle,true,true,false)
        local blip=createTruckBlip(spawn,'Entrega de estoque')
        if not blip then
            activeDeliveries[order.id]=nil
            DeleteEntity(driver);DeleteEntity(vehicle);request('commerceCancelDelivery',order.id)
            print(('[ob_inventory] Entrega #%s: AddBlipForCoord falhou na entrega por motorista.'):format(order.id))
            return notify('Nao foi possivel criar o marcador do caminhao. O valor voltou ao caixa.','error')
        end
        activeDeliveries[order.id]={vehicle=vehicle,driver=driver,blip=blip,method='npc'}
        followTruckBlip(order.id)
        protectNpcTruck(order.id)
        notify('O motorista saiu para entrega. O caminhao e a rota amarela foram marcados no mapa.','success')
        local deliveryConfig=(ORInventoryShops.Business or {}).Delivery or {}
        local driveSpeed=tonumber(deliveryConfig.DriveSpeed) or 16.0
        local driveStyle=tonumber(deliveryConfig.DriveStyle) or 786475
        local function drive()
            vehicleControl=NetworkHasControlOfEntity(vehicle) or waitForNetworkControl(vehicle)
            driverControl=NetworkHasControlOfEntity(driver) or waitForNetworkControl(driver)
            if not vehicleControl or not driverControl then
                print(('[ob_inventory] Entrega #%s: aguardando controle da IA para iniciar a rota.'):format(order.id))
                return false
            end
            if not IsPedInVehicle(driver,vehicle,false) then TaskWarpPedIntoVehicle(driver,vehicle,-1) end
            FreezeEntityPosition(vehicle,false)
            SetVehicleUndriveable(vehicle,false)
            SetVehicleHandbrake(vehicle,false)
            SetVehicleEngineOn(vehicle,true,true,false)
            SetDriveTaskDrivingStyle(driver,driveStyle)
            SetDriveTaskCruiseSpeed(driver,driveSpeed)
            TaskVehicleDriveToCoordLongrange(driver,vehicle,stop.x,stop.y,stop.z,driveSpeed,driveStyle,4.0)
            SetPedKeepTask(driver,true)
            return true
        end
        drive()
        local timeout=GetGameTimer()+600000
        local lastCoords=GetEntityCoords(vehicle)
        local stuckFor=0
        while activeDeliveries[order.id] and GetGameTimer()<timeout and #(GetEntityCoords(vehicle)-vector3(stop.x,stop.y,stop.z))>12.0 do
            Wait(2000)
            local coords=GetEntityCoords(vehicle)
            if #(coords-lastCoords)<1.5 then stuckFor=stuckFor+2 else stuckFor=0;lastCoords=coords end
            if stuckFor>=8 then
                drive()
                if stuckFor>=16 and vehicleControl then SetVehicleForwardSpeed(vehicle,2.0) end
                if stuckFor>=20 then stuckFor=0;lastCoords=GetEntityCoords(vehicle) end
            end
        end
        if not activeDeliveries[order.id] then return end
        if activeDeliveries[order.id].routeBlip and DoesBlipExist(activeDeliveries[order.id].routeBlip) then
            RemoveBlip(activeDeliveries[order.id].routeBlip);activeDeliveries[order.id].routeBlip=nil
        end
        TaskVehicleTempAction(driver,vehicle,27,3000); Wait(1500)
        TaskLeaveVehicle(driver,vehicle,0); local leaveTimeout=GetGameTimer()+12000
        while IsPedInAnyVehicle(driver,false) and GetGameTimer()<leaveTimeout do Wait(250) end
        local cargoHash=model((ORInventoryShops.Business.Delivery or {}).CargoModel or 'prop_cs_cardbox_01')
        if cargoHash then
            local driverCoords=GetEntityCoords(driver)
            local cargo=CreateObject(cargoHash,driverCoords.x,driverCoords.y,driverCoords.z,false,false,false)
            SetEntityCollision(cargo,false,false)
            AttachEntityToEntity(cargo,driver,GetPedBoneIndex(driver,28422),0.01,-0.02,-0.02,0.0,0.0,0.0,true,true,false,true,1,true)
            RequestAnimDict('anim@heists@box_carry@'); while not HasAnimDictLoaded('anim@heists@box_carry@') do Wait(0) end
            TaskPlayAnim(driver,'anim@heists@box_carry@','idle',8.0,-8.0,-1,49,0,false,false,false)
            activeDeliveries[order.id].cargo=cargo
        end
        local function walkTo(target,walkTimeout)
            TaskFollowNavMeshToCoord(driver,target.x,target.y,target.z,1.0,walkTimeout,1.0,false,target.w or 0.0)
            if activeDeliveries[order.id] and activeDeliveries[order.id].cargo then
                TaskPlayAnim(driver,'anim@heists@box_carry@','idle',8.0,-8.0,-1,49,0,false,false,false)
            end
            local deadline=GetGameTimer()+walkTimeout
            while activeDeliveries[order.id] and DoesEntityExist(driver) and GetGameTimer()<deadline do
                if #(GetEntityCoords(driver)-vector3(target.x,target.y,target.z))<=2.0 then return true end
                Wait(500)
            end
            return false
        end
        if not walkTo(walkPoint,45000) or not walkTo(drop,45000) then
            notify('O entregador nao encontrou o caminho ate a loja. O pedido foi estornado.','error')
            request('commerceCancelDelivery',order.id);cleanup(order.id);return
        end
        TaskTurnPedToFaceCoord(driver,drop.x,drop.y,drop.z,1000);Wait(1200)
        local delivered,message=request('commerceCompleteDelivery',order.id)
        if not delivered then
            notify(message or 'Nao foi possivel concluir a entrega automatica.','error')
            request('commerceCancelDelivery',order.id);cleanup(order.id);return
        end
        local current=activeDeliveries[order.id]
        if not current then return end
        if current.cargo and DoesEntityExist(current.cargo) then DeleteEntity(current.cargo);current.cargo=nil end
        ClearPedTasks(driver)
        notify(message or 'Estoque recebido automaticamente.','success')

        walkTo(walkPoint,45000)
        local driverDoor=GetOffsetFromEntityInWorldCoords(vehicle,-2.0,0.0,0.0)
        walkTo({x=driverDoor.x,y=driverDoor.y,z=driverDoor.z,w=GetEntityHeading(vehicle)},30000)
        current.allowDriverEntry=true
        TaskEnterVehicle(driver,vehicle,15000,-1,1.0,1,0)
        local enterTimeout=GetGameTimer()+16000
        while activeDeliveries[order.id] and not IsPedInVehicle(driver,vehicle,false) and GetGameTimer()<enterTimeout do Wait(500) end
        if not IsPedInVehicle(driver,vehicle,false) and waitForNetworkControl(driver) and waitForNetworkControl(vehicle) then
            TaskWarpPedIntoVehicle(driver,vehicle,-1)
        end
        if not IsPedInVehicle(driver,vehicle,false) then cleanup(order.id);return end
        current.allowDriverEntry=false
        TaskVehicleDriveToCoordLongrange(driver,vehicle,spawn.x,spawn.y,spawn.z,18.0,driveStyle,8.0)
        local departureTimeout=GetGameTimer()+90000
        while activeDeliveries[order.id] and GetGameTimer()<departureTimeout do
            local coords=GetEntityCoords(vehicle)
            if #(coords-vector3(stop.x,stop.y,stop.z))>=60.0 or #(coords-vector3(spawn.x,spawn.y,spawn.z))<=10.0 then break end
            Wait(1000)
        end
        cleanup(order.id)
    end)
end)

RegisterNetEvent('ob_inventory:client:pickupDeliveryAction',function(entity)
    for orderId,delivery in pairs(activeDeliveries) do
        if delivery.method=='pickup' and delivery.vehicle==entity then
            CreateThread(function()
                if delivery.busy then return end
                delivery.busy=true
                if delivery.stage=='loading' then
                    if not delivery.cargo or not DoesEntityExist(delivery.cargo) then
                        delivery.busy=false
                        delivery.stage='to_depot'
                        return notify('Pegue novamente a mercadoria com o atendente.','error')
                    end
                    local ped=PlayerPedId()
                    TaskTurnPedToFaceEntity(ped,delivery.vehicle,1000);Wait(1000)
                    SetVehicleDoorOpen(delivery.vehicle,2,false,false);SetVehicleDoorOpen(delivery.vehicle,3,false,false)
                    Wait(1800);stopCarryingCargo(delivery)
                    SetVehicleDoorShut(delivery.vehicle,2,false);SetVehicleDoorShut(delivery.vehicle,3,false)
                    delivery.stage='to_store';delivery.busy=false
                    routeTo(delivery,delivery.destination,'Levar mercadoria para a loja')
                    registerPickupTarget(orderId,'Descarregar mercadoria na loja')
                    notify('Mercadoria carregada. Volte para sua loja e descarregue o caminhao.','success')
                elseif delivery.stage=='to_store' then
                    if not startCarryingCargo(delivery) then delivery.busy=false;return notify('Nao foi possivel retirar a caixa do caminhao.','error') end
                    local ped=PlayerPedId();SetVehicleDoorOpen(delivery.vehicle,2,false,false);SetVehicleDoorOpen(delivery.vehicle,3,false,false)
                    Wait(3000);SetVehicleDoorShut(delivery.vehicle,2,false);SetVehicleDoorShut(delivery.vehicle,3,false)
                    delivery.stage='delivering'
                    delivery.busy=false
                    if GetResourceState('ob_target')=='started' then exports.ob_target:RemoveEntityOption(('ob_inventory:pickup:%s'):format(orderId)) end
                    routeTo(delivery,delivery.deliveryPoint,'Entregar mercadoria na loja')
                    registerPickupDropoffTarget(orderId)
                    notify('Caixa retirada. Leve-a ate o ponto de entrega da loja e use o target.','success')
                else
                    delivery.busy=false
                end
            end)
            return
        end
    end
end)

RegisterNetEvent('ob_inventory:client:finishPickupDropoff',function(requestedOrderId)
    requestedOrderId=tonumber(requestedOrderId)
    for orderId,delivery in pairs(activeDeliveries) do
        if orderId==requestedOrderId and delivery.method=='pickup' and delivery.stage=='delivering' and not delivery.busy then
            delivery.busy=true
            CreateThread(function()
                if not delivery.cargo or not DoesEntityExist(delivery.cargo) then
                    if not startCarryingCargo(delivery) then delivery.busy=false;return notify('Nao foi possivel recuperar a caixa da entrega.','error') end
                end
                local ped=PlayerPedId()
                TaskPlayAnim(ped,'anim@heists@box_carry@','idle',8.0,-8.0,1200,49,0,false,false,false)
                Wait(1200)
                local ok,message=request('commerceCompleteDelivery',orderId)
                if not ok then delivery.busy=false;return notify(message or 'Nao foi possivel entregar o pedido.','error') end
                stopCarryingCargo(delivery)
                delivery.stage='store_done';delivery.busy=false
                if delivery.routeBlip and DoesBlipExist(delivery.routeBlip) then RemoveBlip(delivery.routeBlip);delivery.routeBlip=nil end
                if GetResourceState('ob_target')=='started' then
                    exports.ob_target:UnregisterZone(('ob_inventory:pickup_dropoff:%s'):format(orderId))
                end
                notify((message or 'Estoque recebido.')..' Entre no caminhao e buzine ao lado da loja para guarda-lo.','success')
                waitForPickupTruckHorn(orderId)
            end)
            return
        end
    end
end)

RegisterNetEvent('ob_inventory:client:trackShopDelivery',function(orderId,showMessage)
    orderId=tonumber(orderId)
    if not orderId or trackingRequests[orderId] then return end
    local active=activeDeliveries[orderId]
    if active then
        local routeBlip=active.routeBlip and DoesBlipExist(active.routeBlip) and active.routeBlip
        if routeBlip then
            SetBlipDisplay(routeBlip,4);SetBlipRoute(routeBlip,true);SetBlipRouteColour(routeBlip,5)
            local coords=active.routeBlip and DoesBlipExist(active.routeBlip) and GetBlipCoords(active.routeBlip)
                or active.vehicle and DoesEntityExist(active.vehicle) and GetEntityCoords(active.vehicle)
            SetWaypointOff()
            if showMessage then notify('A entrega ativa foi destacada pela rota amarela.','success') end
        elseif active.blip and DoesBlipExist(active.blip) then
            SetBlipDisplay(active.blip,4)
            if showMessage then notify('O caminhao foi destacado pelo blip vermelho.','success') end
        elseif showMessage then
            notify('A entrega esta ativa, mas o marcador ainda nao foi criado.','error')
        end
        return
    end
    trackingRequests[orderId]=true
    CreateThread(function()
        local order,message=request('commerceTrackDelivery',orderId)
        trackingRequests[orderId]=nil
        if not order then
            if showMessage then notify(message or 'Nao foi possivel localizar a entrega.','error') end
            return
        end
        TriggerEvent('ob_inventory:client:startShopDelivery',order)
    end)
end)

ensureActiveDeliveries=function(data,showMessage)
    for _,store in ipairs(type(data)=='table' and data.stores or {}) do
        if store.activeOrder and store.activeOrder.id then
            TriggerEvent('ob_inventory:client:trackShopDelivery',tonumber(store.activeOrder.id),showMessage==true)
        end
    end
end

RegisterNetEvent('ob_inventory:client:receiveShopDelivery',function(entity)
    for orderId,delivery in pairs(activeDeliveries) do
        if delivery.driver==entity then
            CreateThread(function()
                local ok,err=request('commerceCompleteDelivery',orderId)
                if not ok then return notify(err or 'Nao foi possivel receber a entrega.','error') end
                notify(err or 'Estoque recebido.','success'); cleanup(orderId)
            end)
            return
        end
    end
end)

RegisterNetEvent('ob_inventory:client:finishShopDelivery',function(orderId) cleanup(tonumber(orderId)) end)

local function clearManagers()
    for id,ped in pairs(managerPeds) do
        if GetResourceState('ob_target')=='started' then
            exports.ob_target:RemoveEntityOption(('ob_inventory:manager:%s'):format(id))
            exports.ob_target:RemoveEntityOption(('ob_inventory:fiscal:%s'):format(id))
        end
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    managerPeds={}
    for index,ped in pairs(depotPeds) do
        if GetResourceState('ob_target')=='started' then exports.ob_target:RemoveEntityOption(('ob_inventory:depot:%s'):format(index)) end
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    depotPeds={}
end
local function streamingSettings()
    local config=type(ORInventoryShops.Streaming)=='table' and ORInventoryShops.Streaming or {}
    local spawnDistance=math.max(20.0,tonumber(config.SpawnDistance) or 90.0)
    local despawnDistance=math.max(spawnDistance+10.0,tonumber(config.DespawnDistance) or 120.0)
    return spawnDistance,despawnDistance,math.max(500,math.floor(tonumber(config.UpdateInterval) or 1000))
end
local function registerManagerTarget(id,ped)
    if GetResourceState('ob_target')~='started' or not ped or not DoesEntityExist(ped) then return end
    exports.ob_target:RegisterEntity(('ob_inventory:manager:%s'):format(id),ped,{
        label='Comprar / gerenciar loja',event='ob_inventory:client:openCommerceAtManager',distance=2.0,
        canInteract=function(entity)return managerPeds[id]==entity end,
    })
end
local function removeManagerPed(id)
    local ped=managerPeds[id];if not ped then return end
    if GetResourceState('ob_target')=='started' then
        exports.ob_target:RemoveEntityOption(('ob_inventory:manager:%s'):format(id))
        exports.ob_target:RemoveEntityOption(('ob_inventory:fiscal:%s'):format(id))
    end
    if DoesEntityExist(ped) then DeleteEntity(ped) end
    managerPeds[id]=nil
end
local function removeDepotPed(index)
    local ped=depotPeds[index];if not ped then return end
    if GetResourceState('ob_target')=='started' then exports.ob_target:RemoveEntityOption(('ob_inventory:depot:%s'):format(index)) end
    if DoesEntityExist(ped) then DeleteEntity(ped) end
    depotPeds[index]=nil
end
local function configureServicePed(ped)
    SetEntityAsMissionEntity(ped,true,true);SetEntityInvincible(ped,true)
    SetBlockingOfNonTemporaryEvents(ped,true);FreezeEntityPosition(ped,true)
    TaskStartScenarioInPlace(ped,'WORLD_HUMAN_CLIPBOARD',0,true)
end
local function streamManagers()
    if managerStreamBusy then return end
    managerStreamBusy=true
    local origin=GetEntityCoords(PlayerPedId())
    local spawnDistance,despawnDistance=streamingSettings()
    local missingManagers={}
    for id,p in pairs(managerDefinitions) do
        local distance=#(origin-vector3(p.x,p.y,p.z))
        local ped=managerPeds[id]
        if ped and (not DoesEntityExist(ped) or distance>despawnDistance) then removeManagerPed(id)
        elseif not ped and distance<=spawnDistance then missingManagers[#missingManagers+1]={id=id,coords=p} end
    end
    if #missingManagers>0 then
        local hash=model(((ORInventoryShops.Business or {}).Delivery or {}).Manager or 'a_m_m_business_01')
        if hash then
            for _,entry in ipairs(missingManagers) do
                if managerDefinitions[entry.id]==entry.coords and not managerPeds[entry.id] then
                    local p=entry.coords
                    local ped=CreatePed(4,hash,p.x,p.y,p.z-1.0,p.w or 0.0,false,true)
                    if ped and ped~=0 then configureServicePed(ped);managerPeds[entry.id]=ped;registerManagerTarget(entry.id,ped) end
                end
            end
            SetModelAsNoLongerNeeded(hash)
        end
    end

    local missingDepots={}
    for index,p in pairs(depotDefinitions) do
        local distance=#(origin-vector3(p.x,p.y,p.z))
        local ped=depotPeds[index]
        if ped and (not DoesEntityExist(ped) or distance>despawnDistance) then removeDepotPed(index)
        elseif not ped and distance<=spawnDistance then missingDepots[#missingDepots+1]={index=index,coords=p} end
    end
    if #missingDepots>0 then
        local delivery=(ORInventoryShops.Business or {}).Delivery or {}
        local hash=model(delivery.Loader or 's_m_m_dockwork_01')
        if hash then
            for _,entry in ipairs(missingDepots) do
                if depotDefinitions[entry.index]==entry.coords and not depotPeds[entry.index] then
                    local p=entry.coords
                    local ped=CreatePed(4,hash,p.x,p.y,p.z,p.w or 0.0,false,true)
                    if ped and ped~=0 then configureServicePed(ped);depotPeds[entry.index]=ped;registerDepotTarget(entry.index,ped) end
                end
            end
            SetModelAsNoLongerNeeded(hash)
        end
    end
    managerStreamBusy=false
end
local function loadManagers(payload)
    if type(payload)~='table' or type(payload.groups)~='table' or type(payload.shops)~='table' then
        print('[ob_inventory] Sincronizacao de gestores ignorada: definicoes incompletas.')
        return false
    end
    clearManagers();managerDefinitions={};depotDefinitions={}
    for _,shop in ipairs(payload.shops) do
        local group=payload.groups and payload.groups[shop.group]
        if shop.manager and group and group.category=='convenience' and group.purchasable==true then
            managerDefinitions[shop.id]=shop.manager
        end
    end
    local delivery=(ORInventoryShops.Business or {}).Delivery or {}
    for index,depot in ipairs(delivery.PickupDepots or {}) do
        local p=point(depot.coords or depot);if p then depotDefinitions[index]=p end
    end
    CreateThread(streamManagers)
    return true
end
RegisterNetEvent('ob_inventory:client:openCommerceAtManager',function(entity)for id,ped in pairs(managerPeds)do if ped==entity then openCommerce(id);return end end end)
RegisterNetEvent('ob_inventory:client:shopDefinitions',function(payload)loadManagers(payload)end)
AddEventHandler('ob_target:client:ready',function()
    for id,ped in pairs(managerPeds)do registerManagerTarget(id,ped)end
    for index,ped in pairs(depotPeds)do registerDepotTarget(index,ped)end
    for orderId,delivery in pairs(activeDeliveries) do
        if delivery.method=='pickup' then
            if delivery.stage=='loading' then registerPickupTarget(orderId,'Colocar mercadoria no caminhao')
            elseif delivery.stage=='to_store' then registerPickupTarget(orderId,'Descarregar mercadoria na loja')
            elseif delivery.stage=='delivering' then registerPickupDropoffTarget(orderId) end
        end
    end
end)
CreateThread(function()
    while LocalPlayer.state['or:loaded']~=true do Wait(500) end
    -- O servidor retorna as definicoes diretamente. Repetir enquanto o banco
    -- ainda estiver carregando garante gestores/depositos no primeiro login.
    local payload
    while not payload do
        local received=OR.Callback.awaitResource('ob_inventory','worldShopDefinitions')
        if type(received)=='table' and loadManagers(received) then payload=received else Wait(1500) end
    end
    local ok,orders=OR.Callback.awaitResource('ob_inventory','commerceResumeDeliveries')
    if ok==true and type(orders)=='table' then for _,order in ipairs(orders)do TriggerEvent('ob_inventory:client:startShopDelivery',order) end end
end)
CreateThread(function()
    while true do
        if LocalPlayer.state['or:loaded']==true then streamManagers() end
        local _,_,interval=streamingSettings();Wait(interval)
    end
end)
AddEventHandler('onClientResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    closeCommerce(); clearManagers(); for orderId in pairs(activeDeliveries) do cleanup(orderId) end
end)
