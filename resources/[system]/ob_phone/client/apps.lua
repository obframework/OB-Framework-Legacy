OBPhoneApps = OBPhoneApps or {}

local catalog = {}
local idPattern = '^[a-z0-9][a-z0-9_.%-]+$'

local function cleanText(value, maximum)
    if type(value) ~= 'string' then return nil end
    value = value:match('^%s*(.-)%s*$')
    if value == '' or #value > maximum then return nil end
    return value
end

local function cleanPath(value)
    value = cleanText(value, 256)
    if not value or value:find('\\', 1, true) or value:find(':', 1, true) or value:sub(1, 1) == '/' then return nil end
    for segment in value:gmatch('[^/]+') do if segment == '.' or segment == '..' then return nil end end
    return value
end

local function publicApp(app)
    return {
        id = app.id, name = app.name, description = app.description,
        developer = app.developer, version = app.version, category = app.category,
        icon = app.iconUrl, entry = app.entryUrl, defaultInstalled = app.defaultInstalled,
        removable = app.removable, external = true
    }
end

local function pushCatalog()
    local list = {}
    for _, app in pairs(catalog) do list[#list + 1] = publicApp(app) end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    SendNUIMessage({ action = 'appCatalog', apps = list })
end

local function addApp(definition)
    local owner = GetInvokingResource()
    if not owner or owner == '' or owner == GetCurrentResourceName() then return false, 'invalid_owner' end
    if GetResourceState(owner) ~= 'started' and GetResourceState(owner) ~= 'starting' then return false, 'owner_not_started' end
    if type(definition) ~= 'table' then return false, 'invalid_definition' end
    local id = cleanText(definition.id, 48)
    local name = cleanText(definition.name, 40)
    local description = cleanText(definition.description or 'Aplicativo da cidade.', 180)
    local entry = cleanPath(definition.entry)
    local icon = cleanPath(definition.icon)
    if not id or not id:match(idPattern) or not name or not description or not entry or not icon then return false, 'invalid_manifest' end
    if catalog[id] and catalog[id].owner ~= owner then return false, 'app_id_in_use' end
    catalog[id] = {
        id = id, name = name, description = description, entryUrl = ('https://cfx-nui-%s/%s'):format(owner, entry),
        iconUrl = ('https://cfx-nui-%s/%s'):format(owner, icon), owner = owner,
        developer = cleanText(definition.developer or owner, 48) or owner,
        version = cleanText(definition.version or '1.0.0', 20) or '1.0.0',
        category = cleanText(definition.category or 'utilidades', 24) or 'utilidades',
        defaultInstalled = definition.defaultInstalled == true, removable = definition.removable ~= false
    }
    pushCatalog()
    return true
end

local function removeOwnedApps(owner)
    local changed = false
    for id, app in pairs(catalog) do
        if app.owner == owner then catalog[id] = nil; changed = true end
    end
    if changed then pushCatalog() end
end

function OBPhoneApps.GetCatalog()
    local list = {}
    for _, app in pairs(catalog) do list[#list + 1] = publicApp(app) end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    return list
end

exports('AddApp', addApp)
exports('GetApps', OBPhoneApps.GetCatalog)
exports('RemoveApp', function(id)
    local owner, app = GetInvokingResource(), catalog[tostring(id or '')]
    if not app or app.owner ~= owner then return false end
    catalog[app.id] = nil; pushCatalog(); return true
end)
exports('SendAppMessage', function(id, payload)
    local owner, app = GetInvokingResource(), catalog[tostring(id or '')]
    if not app or app.owner ~= owner then return false end
    SendNUIMessage({ action = 'externalAppMessage', appId = app.id, payload = payload })
    return true
end)

RegisterNUICallback('externalAppEvent', function(data, cb)
    local app = type(data) == 'table' and catalog[tostring(data.appId or '')]
    if not app then return cb({ ok = false }) end
    TriggerEvent('ob_phone:client:appEvent', app.owner, app.id, data.event, data.payload)
    cb({ ok = true })
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then removeOwnedApps(resource) end
end)

CreateThread(function()
    Wait(0)
    TriggerEvent('ob_phone:client:appsReady')
end)
