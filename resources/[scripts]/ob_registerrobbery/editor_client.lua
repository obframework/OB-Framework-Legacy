local opened=false
local function close()
    opened=false
    SetNuiFocus(false,false)
    SendNUIMessage({action='close'})
end
local function open()
    if opened or IsNuiFocused() then return end
    local data,message=OR.Callback.await('editorData')
    if not data then return OR.Notify(message or 'Editor indisponivel.','error') end
    opened=true; SetNuiFocus(true,true)
    SendNUIMessage({action='open',rows=data.rows})
end
RegisterNetEvent('ob_registerrobbery:editor',open)
RegisterCommand('obregistereditor',open,false)
RegisterNUICallback('close',function(_,cb) close(); cb({ok=true}) end)
for _,action in ipairs({'Save','Delete','Teleport'}) do
    RegisterNUICallback('editor'..action,function(data,cb)
        if not opened then return cb({ok=false,message='Editor fechado.'}) end
        local result,message=OR.Callback.await('editor'..action,action=='Save' and data or data.id)
        if result and action=='Teleport' then
            close()
            local p=result
            RequestCollisionAtCoord(p.x,p.y,p.z)
            SetEntityCoordsNoOffset(PlayerPedId(),p.x,p.y,p.z,false,false,false)
            SetEntityHeading(PlayerPedId(),p.w)
        end
        cb({ok=result~=nil,data=result,message=message})
    end)
end
RegisterNUICallback('capture',function(_,cb)
    if not opened then return cb({ok=false}) end
    local ped=PlayerPedId()
    local p=GetEntityCoords(ped)
    local object=GetClosestObjectOfType(p.x,p.y,p.z,3.0,joaat('prop_till_01'),false,false,false)
    if object~=0 then p=GetEntityCoords(object) end
    cb({ok=true,coords={x=p.x,y=p.y,z=p.z,w=object~=0 and GetEntityHeading(object) or GetEntityHeading(ped)}})
end)
AddEventHandler('onClientResourceStop',function(name)
    if name==GetCurrentResourceName() and opened then close() end
end)
