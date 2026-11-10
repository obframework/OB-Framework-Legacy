local resource = GetCurrentResourceName()
local open, selectedShopId = false, nil

local function notify(message, kind)
    OR.Notify(message, kind or 'info')
end

local function closePanel()
    if not open then return end
    open, selectedShopId = false, nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action='close' })
end

local function showPanel(mode, shopId)
    if open or IsNuiFocused() or LocalPlayer.state['or:loaded'] ~= true then return end
    CreateThread(function()
        local data, err = OR.Callback.awaitResource(resource, mode == 'police' and 'policePanel' or 'ownerPanel', shopId)
        if not data then return notify(err or 'Sistema fiscal indisponivel.', 'error') end
        open, selectedShopId = true, data.selectedShopId
        SetNuiFocus(true, true)
        SendNUIMessage({ action='open', payload=data })
    end)
end

RegisterNetEvent('ob_fiscal:client:openAtShop', function(shopId)
    showPanel('owner', tostring(shopId or ''))
end)

RegisterCommand(OBFiscal.OwnerCommand or 'fiscal', function() showPanel('owner') end, false)
RegisterCommand(OBFiscal.PoliceCommand or 'fiscalpolicia', function() showPanel('police') end, false)

RegisterNUICallback('close', function(_, cb) closePanel(); cb({ok=true}) end)

RegisterNUICallback('selectShop', function(data, cb)
    local result, err = OR.Callback.awaitResource(resource, 'ownerPanel', data and data.shopId)
    if result then selectedShopId=result.selectedShopId end
    cb(result and {ok=true,data=result} or {ok=false,error=err})
end)

for nui, callback in pairs({ deposit='deposit', declare='declare', payroll='payroll' }) do
    RegisterNUICallback(nui, function(data, cb)
        local result, err = OR.Callback.awaitResource(resource, callback, selectedShopId, data and data.amount)
        cb(result and {ok=true,data=result,message=err} or {ok=false,error=err})
    end)
end

RegisterNUICallback('policeRefresh', function(_, cb)
    local result, err = OR.Callback.awaitResource(resource, 'policePanel')
    cb(result and {ok=true,data=result} or {ok=false,error=err})
end)

RegisterNUICallback('policeStatus', function(data, cb)
    local result, err = OR.Callback.awaitResource(resource, 'policeStatus', data and data.id, data and data.status, data and data.notes)
    cb(result and {ok=true,data=result,message=err} or {ok=false,error=err})
end)

RegisterNetEvent('ob_fiscal:client:refresh', function(shopId)
    if not open or (shopId and selectedShopId and tostring(shopId) ~= tostring(selectedShopId)) then return end
    SendNUIMessage({ action='refreshHint' })
end)

CreateThread(function()
    while true do
        if open then
            DisableControlAction(0, 200, true)
            if IsDisabledControlJustReleased(0, 200) then closePanel() end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

AddEventHandler('onClientResourceStop', function(name)
    if name == resource then closePanel() end
end)
