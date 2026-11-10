local editorResource, capturing
OBShopEditorActive = false
local resources = { inventory = 'ob_inventory', stores = 'ob_stores' }

local function closeEditor()
    OBShopEditorActive, capturing, editorResource = false, false, nil
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'shopEditorClose' })
end
local function openEditor(mode)
    if OBShopEditorActive or IsNuiFocused() then return end
    local target = resources[mode]
    if not target or GetResourceState(target) ~= 'started' then return OR.Notify('Sistema indisponivel.', 'error') end
    local data, err = OR.Callback.awaitResource(target, 'worldShopEditorData')
    if not data then return OR.Notify(err or 'Sem permissao.', 'error') end
    editorResource, OBShopEditorActive = target, true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'shopEditorOpen', data = data })
end
RegisterNetEvent('ob_adminmenu:client:shopEditor', openEditor)
RegisterCommand('obshopseditor', function() openEditor('inventory') end, false)
RegisterCommand('obstoreseditor', function() openEditor('stores') end, false)

RegisterNUICallback('shopEditorClose', function(_, cb) closeEditor(); cb({ ok = true }) end)
RegisterNUICallback('shopEditorRefresh', function(_, cb)
    if not editorResource then return cb({ ok = false, error = 'Editor fechado.' }) end
    local data, err = OR.Callback.awaitResource(editorResource, 'worldShopEditorData')
    cb({ ok = data ~= nil, data = data, error = err })
end)
RegisterNUICallback('shopEditorSave', function(data, cb)
    if not editorResource then return cb({ ok = false, error = 'Editor fechado.' }) end
    if editorResource == 'ob_inventory' and data.recordType == 'group' then
        local model = joaat(tostring(data.ped or ''))
        if not IsModelInCdimage(model) or not IsModelAPed(model) then return cb({ ok = false, error = 'Modelo de atendente invalido.' }) end
    end
    local row, message = OR.Callback.awaitResource(editorResource, 'worldShopEditorSave', data)
    cb({ ok = row ~= nil, data = row, message = row and message or nil, error = row == nil and message or nil })
end)
RegisterNUICallback('shopEditorDelete', function(data, cb)
    if not editorResource then return cb({ ok = false, error = 'Editor fechado.' }) end
    local payload = editorResource == 'ob_inventory' and data or (data and data.id)
    local result, message = OR.Callback.awaitResource(editorResource, 'worldShopEditorDelete', payload)
    cb({ ok = result == true, message = result and message or nil, error = result ~= true and message or nil })
end)
RegisterNUICallback('shopEditorTeleport', function(data, cb)
    if not editorResource or capturing then return cb({ ok = false, error = 'Editor indisponivel.' }) end
    local coords, err = OR.Callback.awaitResource(editorResource, 'worldShopEditorTeleport', data and data.id)
    if not coords then return cb({ ok = false, error = err }) end
    closeEditor()
    TriggerEvent('ob_admin:client:teleport', coords)
    cb({ ok = true })
end)

RegisterNUICallback('shopEditorCapture', function(data, cb)
    if not OBShopEditorActive or capturing then return cb({ ok = false }) end
    local field = type(data) == 'table' and tostring(data.field or 'coords') or 'coords'
    capturing = true
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'shopEditorCaptureStart' })
    cb({ ok = true })
    CreateThread(function()
        while capturing and OBShopEditorActive do
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            DisableControlAction(0, 200, true)
            DisableControlAction(0, 177, true)
            DrawMarker(28, coords.x, coords.y, coords.z + 0.2, 0.0,0.0,0.0,0.0,0.0,0.0,
                0.3,0.3,0.3, 40,181,255,200, false,false,2,false,nil,nil,false)
            local cancel = IsDisabledControlJustReleased(0, 200) or IsDisabledControlJustReleased(0, 177)
            if cancel or IsControlJustReleased(0, 38) then
                capturing = false
                SetNuiFocus(true, true)
                SendNUIMessage({ action = 'shopEditorCaptureResult', cancelled = cancel,
                    field = field,
                    point = { x=coords.x, y=coords.y, z=coords.z, w=GetEntityHeading(ped) } })
                break
            end
            Wait(0)
        end
    end)
end)
AddEventHandler('onClientResourceStop', function(name)
    if name == GetCurrentResourceName() and OBShopEditorActive then closeEditor() end
end)
