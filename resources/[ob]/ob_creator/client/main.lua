local isOpen = false
local activeLocation = nil
local activeMode = 'shop'
local cartEnabled = true
local activeUiConfig = nil
local externalStoreUi = false
local creatorReturn = nil
local creatorSpawned = false
local creatorGenderOverride = nil
local creatorHeading = nil
local creatorSaving = false
local appearanceOpening = false
local storeSaving = false
local creatorInstanceActive = false
local pendingIdentityPromise = nil
local pendingFinishPromise = nil
local creatorIdentity = nil
local creatorCid = nil
local camHandle = nil
local camFov = 32.0
local camBaseDir = vector3(0.0, 1.0, 0.0)

local Catalog = {}
local CatalogLoaded = false

local function loadCatalog()
    if CatalogLoaded then return end
    CatalogLoaded = true
    local raw = LoadResourceFile(GetCurrentResourceName(), 'shared/catalog.json')
    if not raw then return end

    local ok, data = pcall(json.decode, raw)
    if ok and type(data) == 'table' then
        Catalog = data
    else
        Catalog = {}
    end
end

local CurrentAppearance = nil
local OriginalAppearance = nil
local CartTotal = 0
local CartKeys = {}
local TextureState = {}
local TextureMax = {}
local ColorState = {}
local ColorMax = {}
local ActiveSelection = nil

local CategoryIndex = {}

local function markDiagnosticAction(action, data)
    if GetResourceState('ob_diagnostics') ~= 'started' then return end
    pcall(function()
        exports.ob_diagnostics:markAction(action, data)
    end)
end

local function indexSections(sections)
    if type(sections) ~= 'table' then return end
    for _, section in ipairs(sections) do
        for _, category in ipairs(section.categories or {}) do
            CategoryIndex[section.id .. ':' .. category.id] = category
        end
    end
end

indexSections(Config.Ui.sections)
indexSections(Config.CreatorUi and Config.CreatorUi.sections)

local TattooLookup = {}
for zone, list in pairs(Config.Tattoos or {}) do
    for _, t in ipairs(list) do
        if t.hashMale then TattooLookup[t.hashMale] = t end
        if t.hashFemale then TattooLookup[t.hashFemale] = t end
    end
end

local OverlayIndex = {}
if constants and constants.HEAD_OVERLAYS then
    for i, name in ipairs(constants.HEAD_OVERLAYS) do
        OverlayIndex[name] = i - 1 -- native overlay index is 0-based
    end
end

local function deepCopy(data)
    return json.decode(json.encode(data))
end

local function capString(str)
    if type(str) ~= 'string' then return '' end
    return str:gsub("(%w)([%w']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
end

local function trimString(value)
    if type(value) ~= 'string' then return '' end
    return value:match('^%s*(.-)%s*$') or ''
end

local function normalizeNameKey(value)
    if type(value) ~= 'string' then return '' end
    local key = value:lower()
    key = key:gsub('%s+', '')
    return key
end

local function isBlacklisted(value, list)
    if not value or value == '' then return false end
    if type(list) ~= 'table' then return false end
    local key = normalizeNameKey(value)
    for _, item in ipairs(list) do
        if key == normalizeNameKey(item) then
            return true
        end
    end
    return false
end

local function parseBirthdate(value)
    if type(value) ~= 'string' then return nil end
    local text = value:match('^%s*(.-)%s*$') or value
    local d, m, y = text:match('^(%d%d)%/(%d%d)%/(%d%d%d%d)$')
    if not (d and m and y) then
        y, m, d = text:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    end
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not y or not m or not d then return nil end
    if m < 1 or m > 12 or d < 1 or d > 31 then return nil end
    return { year = y, month = m, day = d }
end

local function getTodayDate()
    local unix = GetCloudTimeAsInt()
    if not unix or unix <= 0 then return nil end
    local days = math.floor(unix / 86400)
    local z = days + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp + ((mp < 10) and 3 or -9)
    y = y + ((m <= 2) and 1 or 0)
    return { year = y, month = m, day = d }
end

local function calculateAge(dateParts)
    if not dateParts then return nil end
    local today = getTodayDate()
    if not today then return nil end
    local age = today.year - dateParts.year
    if today.month < dateParts.month or (today.month == dateParts.month and today.day < dateParts.day) then
        age = age - 1
    end
    return age
end

local function normalizeBirthdate(value)
    if type(value) ~= 'string' then return '' end
    local text = value:match('^%s*(.-)%s*$') or value
    local d, m, y = text:match('^(%d%d)%/(%d%d)%/(%d%d%d%d)$')
    if d and m and y then
        return string.format('%s/%s/%s', d, m, y)
    end
    y, m, d = text:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    if y and m and d then
        return string.format('%s/%s/%s', d, m, y)
    end
    return text
end

local function getGender()
    if creatorGenderOverride then
        return creatorGenderOverride
    end
    return IsPedMale(PlayerPedId()) and 'male' or 'female'
end

local function replaceGenderToken(value, gender)
    if type(value) ~= 'string' then return value end
    return value:gsub('{gender}', gender)
end

local function prepareUiConfig(uiConfig)
    local gender = getGender()
    local copy = deepCopy(uiConfig or {})
    if not copy.sections then return copy end
    for _, section in ipairs(copy.sections) do
        if section.categories then
            for _, category in ipairs(section.categories) do
                if category.icon then
                    category.icon = replaceGenderToken(category.icon, gender)
                end
            end
        end
    end
    return copy
end

local function vadd(a, b)
    return vector3(a.x + b.x, a.y + b.y, a.z + b.z)
end

local function vsub(a, b)
    return vector3(a.x - b.x, a.y - b.y, a.z - b.z)
end

local function vlen(v)
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

local function vscale(v, s)
    return vector3(v.x * s, v.y * s, v.z * s)
end

local function vnorm(v)
    local len = vlen(v)
    if len < 0.0001 then
        return vector3(0.0, 1.0, 0.0)
    end
    return vector3(v.x / len, v.y / len, v.z / len)
end

local function drawHelp(text)
    OR.Help.Show(text)
end

local function draw3DText(coords, text, scale, color)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end

    SetTextScale(scale, scale)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(color[1], color[2], color[3], color[4])
    SetTextCentre(true)
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(x, y)
end

local function faceCamera()
    if not camHandle then return end
    if creatorHeading then
        SetEntityHeading(PlayerPedId(), creatorHeading)
    end
end


local function setupBlips()
    if Config.ShowBlips == false then
        return
    end
    for _, loc in ipairs(Config.Locations or {}) do
        if loc.showBlip ~= false then
            local style = Config.TypeStyles and Config.TypeStyles[loc.type] or nil
            local blipCfg = style and style.blip or Config.Blip
            local blip = AddBlipForCoord(loc.coords.x, loc.coords.y, loc.coords.z)
            SetBlipSprite(blip, blipCfg.sprite)
            SetBlipDisplay(blip, 4)
            SetBlipScale(blip, blipCfg.scale)
            SetBlipColour(blip, blipCfg.color)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(loc.label)
            EndTextCommandSetBlipName(blip)
        end
    end
end

local function setCamToPreset(presetName)
    if not camHandle or camHandle == -1 then return end

    local preset = Config.FocusPresets[presetName] or Config.FocusPresets.full
    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)

    local target = vadd(pedCoords, vector3(0.0, 0.0, preset.z))
    local camPos = vadd(pedCoords, vscale(camBaseDir, preset.dist))
    camPos = vadd(camPos, vector3(0.0, 0.0, preset.z))

    SetCamCoord(camHandle, camPos.x, camPos.y, camPos.z)
    PointCamAtCoord(camHandle, target.x, target.y, target.z)
end

local function createCamera(loc)
    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)

    local camCoords
    local lookAt

    if loc.camOffset then
        camCoords = GetOffsetFromEntityInWorldCoords(ped, loc.camOffset.x, loc.camOffset.y, loc.camOffset.z)
    elseif loc.cam and loc.cam.coords then
        camCoords = loc.cam.coords
    else
        camCoords = vadd(pedCoords, vector3(0.0, 2.0, 0.8))
    end

    if loc.lookAtOffset then
        lookAt = GetOffsetFromEntityInWorldCoords(ped, loc.lookAtOffset.x, loc.lookAtOffset.y, loc.lookAtOffset.z)
    elseif loc.cam and loc.cam.lookAt then
        lookAt = loc.cam.lookAt
    else
        lookAt = vadd(pedCoords, vector3(0.0, 0.0, 0.5))
    end

    camHandle = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(camHandle, camCoords.x, camCoords.y, camCoords.z)
    PointCamAtCoord(camHandle, lookAt.x, lookAt.y, lookAt.z)

    camFov = (loc.cam and loc.cam.fov) or (Config.Camera and Config.Camera.fovMin) or 32.0
    SetCamFov(camHandle, camFov)

    camBaseDir = vnorm(vsub(camCoords, pedCoords))

    RenderScriptCams(true, true, 250, true, true)
end

local function destroyCamera()
    if camHandle and camHandle ~= -1 then
        RenderScriptCams(false, true, 200, true, true)
        DestroyCam(camHandle, false)
        camHandle = nil
    end
end

local function ensureAppearanceDefaults(appearance)
    if not appearance then
        appearance = Appearance.getPedAppearance(PlayerPedId())
    end

    appearance.components = appearance.components or Appearance.getPedAppearance(PlayerPedId()).components
    appearance.props = appearance.props or Appearance.getPedAppearance(PlayerPedId()).props
    appearance.hair = appearance.hair or { style = 0, color = 0, highlight = 0, texture = 0 }
    appearance.headOverlays = appearance.headOverlays or {}
    appearance.tattoos = appearance.tattoos or {}
    appearance.headBlend = appearance.headBlend or {
        shapeFirst = 0, shapeSecond = 0, shapeThird = 0,
        skinFirst = 0, skinSecond = 0, skinThird = 0,
        shapeMix = 0.5, skinMix = 0.5, thirdMix = 0
    }
    appearance.faceFeatures = appearance.faceFeatures or {}
    for _, feature in ipairs(constants.FACE_FEATURES or {}) do
        if appearance.faceFeatures[feature] == nil then
            appearance.faceFeatures[feature] = 0.0
        end
    end

    return appearance
end

local function getAvailableTattooHashSet(gender)
    local set = {}
    local hashList = (Catalog.tattoos and Catalog.tattoos[gender] and Catalog.tattoos[gender].hashes) or {}
    for _, item in ipairs(hashList) do
        set[item.hash] = item.img
    end
    return set
end

local function buildImageMap(list)
    local map = {}
    if type(list) ~= 'table' then return map end
    for _, item in ipairs(list) do
        if item.drawable ~= nil and item.img then
            map[item.drawable] = item.img
        end
    end
    return map
end

local function buildItemsForCategory(sectionId, categoryId)
    loadCatalog()
    local gender = getGender()
    local key = sectionId .. ':' .. categoryId
    local category = CategoryIndex[key]
    if not category then return {} end

    local items = {}
    local ped = PlayerPedId()

    if sectionId == 'skinshop' then
        if category.kind == 'component' then
            local list = (Catalog.clothes and Catalog.clothes[gender] and Catalog.clothes[gender].components and Catalog.clothes[gender].components[tostring(category.component)]) or {}
            local imgMap = buildImageMap(list)
            if Config.UseLiveVariations then
                local max = GetNumberOfPedDrawableVariations(ped, category.component)
                for drawable = 0, max - 1 do
                    items[#items + 1] = {
                        id = tostring(drawable),
                        label = tostring(drawable + 1),
                        img = imgMap[drawable],
                        drawable = drawable
                    }
                end
            else
                for _, item in ipairs(list) do
                    items[#items + 1] = {
                        id = tostring(item.drawable),
                        label = tostring(item.drawable + 1),
                        img = item.img,
                        drawable = item.drawable
                    }
                end
            end
            table.sort(items, function(a, b) return (a.drawable or 0) < (b.drawable or 0) end)
        elseif category.kind == 'prop' then
            local list = (Catalog.clothes and Catalog.clothes[gender] and Catalog.clothes[gender].props and Catalog.clothes[gender].props[tostring(category.prop)]) or {}
            local imgMap = buildImageMap(list)
            items[#items + 1] = { id = '-1', label = 'Nenhum', drawable = -1, none = true }
            if Config.UseLiveVariations then
                local max = GetNumberOfPedPropDrawableVariations(ped, category.prop)
                for drawable = 0, max - 1 do
                    items[#items + 1] = {
                        id = tostring(drawable),
                        label = tostring(drawable + 1),
                        img = imgMap[drawable],
                        drawable = drawable
                    }
                end
            else
                for _, item in ipairs(list) do
                    items[#items + 1] = {
                        id = tostring(item.drawable),
                        label = tostring(item.drawable + 1),
                        img = item.img,
                        drawable = item.drawable
                    }
                end
            end
            table.sort(items, function(a, b) return (a.drawable or 0) < (b.drawable or 0) end)
        end
    elseif sectionId == 'creator' then
        if category.kind == 'overlay' then
            items[#items + 1] = {id='none', label='Remover', drawable=-1, none=true}
        end
        local imgFolder = category.imgFolder
        local max = 0
        if category.kind == 'hair' then
            max = GetNumberOfPedDrawableVariations(ped, 2)
        elseif category.kind == 'overlay' then
            local overlayId = OverlayIndex[category.overlay]
            if overlayId ~= nil then
                max = GetNumHeadOverlayValues(overlayId)
            end
        elseif category.kind == 'eyeColor' then
            max = constants and constants.EYE_COLORS and #constants.EYE_COLORS or 0
        end

        for drawable = 0, math.max(0, max - 1) do
            local img = nil
            if imgFolder then
                img = ('nui://ob_creator/creator/%s/%s/%d.png'):format(gender, imgFolder, drawable)
            end
            items[#items + 1] = {
                id = tostring(drawable),
                label = tostring(drawable + 1),
                img = img,
                drawable = drawable
            }
        end
        table.sort(items, function(a, b) return (a.drawable or 0) < (b.drawable or 0) end)
    elseif sectionId == 'barbershop' then
        if category.kind == 'overlay' then
            items[#items + 1] = {id='none', label='Remover', drawable=-1, none=true}
        end
        local list = (Catalog.barbershop and Catalog.barbershop[gender] and Catalog.barbershop[gender][category.id]) or {}
        local imgMap = buildImageMap(list)
        if Config.UseLiveVariations then
            local max = 0
            if category.kind == 'hair' then
                max = GetNumberOfPedDrawableVariations(ped, 2)
            elseif category.kind == 'overlay' then
                local overlayId = OverlayIndex[category.overlay]
                if overlayId ~= nil then
                    max = GetNumHeadOverlayValues(overlayId)
                end
            elseif category.kind == 'eyeColor' then
                max = constants and constants.EYE_COLORS and #constants.EYE_COLORS or 0
            end

            for drawable = 0, math.max(0, max - 1) do
                items[#items + 1] = {
                    id = tostring(drawable),
                    label = tostring(drawable + 1),
                    img = imgMap[drawable],
                    drawable = drawable
                }
            end
        else
            for _, item in ipairs(list) do
                items[#items + 1] = {
                    id = tostring(item.drawable),
                    label = tostring(item.drawable + 1),
                    img = item.img,
                    drawable = item.drawable
                }
            end
        end
        table.sort(items, function(a, b) return (a.drawable or 0) < (b.drawable or 0) end)
    elseif sectionId == 'tattoos' then
        local hashSet = getAvailableTattooHashSet(gender)
        local zoneList = Config.Tattoos and Config.Tattoos[category.zone] or {}

        items[#items + 1] = {
            id = 'none',
            label = 'Nenhum',
            img = nil,
            none = true
        }

        for _, tat in ipairs(zoneList) do
            local hash = gender == 'male' and tat.hashMale or tat.hashFemale
            local img = hashSet[hash]
            if hash then
                items[#items + 1] = {
                    id = hash,
                    label = tat.label,
                    img = img,
                    hash = hash
                }
            end
        end
    end

    return items
end

local function getPagedItems(items, page, perPage)
    local total = #items
    local totalPages = math.max(1, math.ceil(total / perPage))
    local currentPage = math.max(1, math.min(page or 1, totalPages))

    local startIndex = (currentPage - 1) * perPage + 1
    local endIndex = math.min(startIndex + perPage - 1, total)

    local pageItems = {}
    for i = startIndex, endIndex do
        pageItems[#pageItems + 1] = items[i]
    end

    return pageItems, currentPage, totalPages, total
end

local function setComponent(appearance, componentId, drawable, applied)
    for _, comp in ipairs(appearance.components) do
        if comp.component_id == componentId then
            comp.drawable = drawable
            comp.texture = applied and applied.texture or comp.texture or 0
            comp.palette = applied and applied.palette or comp.palette or 0
            comp.collection = applied and applied.collection or comp.collection or ''
            comp.local_drawable = applied and applied.local_drawable or comp.local_drawable or -1
            return
        end
    end
    appearance.components[#appearance.components + 1] = {
        component_id = componentId,
        drawable = drawable,
        texture = applied and applied.texture or 0,
        palette = applied and applied.palette or 0,
        collection = applied and applied.collection or '',
        local_drawable = applied and applied.local_drawable or -1
    }
end

local function setProp(appearance, propId, drawable, applied)
    for _, prop in ipairs(appearance.props) do
        if prop.prop_id == propId then
            prop.drawable = drawable
            prop.texture = applied and applied.texture or prop.texture or 0
            prop.collection = applied and applied.collection or prop.collection or ''
            prop.local_drawable = applied and applied.local_drawable or prop.local_drawable or -1
            return
        end
    end
    appearance.props[#appearance.props + 1] = {
        prop_id = propId,
        drawable = drawable,
        texture = applied and applied.texture or 0,
        collection = applied and applied.collection or '',
        local_drawable = applied and applied.local_drawable or -1
    }
end

local function setComponentTexture(appearance, componentId, texture)
    for _, comp in ipairs(appearance.components) do
        if comp.component_id == componentId then
            comp.texture = texture
            return
        end
    end
end

local function setPropTexture(appearance, propId, texture)
    for _, prop in ipairs(appearance.props) do
        if prop.prop_id == propId then
            prop.texture = texture
            return
        end
    end
end

local function getTextureMax(category, drawable)
    if (tonumber(drawable) or -1) < 0 then return 1 end
    local ped = PlayerPedId()
    if category.kind == 'component' then
        return math.max(1, GetNumberOfPedTextureVariations(ped, category.component, drawable))
    elseif category.kind == 'prop' then
        return math.max(1, GetNumberOfPedPropTextureVariations(ped, category.prop, drawable))
    end
    return 1
end

local function getOverlayColorMax(category)
    if category.kind == 'hair' then
        return GetNumHairColors()
    end
    if category.kind == 'overlay' then
        if category.overlay == 'makeUp' or category.overlay == 'lipstick' or category.overlay == 'blush' then
            return GetNumMakeupColors()
        end
        return GetNumHairColors()
    end
    return 0
end

local function getCompValue(appearance, componentId)
    if not appearance or not appearance.components then return { drawable = 0, texture = 0 } end
    for _, comp in ipairs(appearance.components) do
        if comp.component_id == componentId then
            return comp
        end
    end
    return { drawable = 0, texture = 0 }
end

local function getPropValue(appearance, propId)
    if not appearance or not appearance.props then return { drawable = -1, texture = 0 } end
    for _, prop in ipairs(appearance.props) do
        if prop.prop_id == propId then
            return prop
        end
    end
    return { drawable = -1, texture = 0 }
end

local function getTattooName(appearance, zone)
    if not appearance or not appearance.tattoos then return nil end
    local list = appearance.tattoos[zone]
    if type(list) ~= 'table' or #list == 0 then return nil end
    return list[1].name or list[1].label or nil
end

local function isCategoryChanged(sectionId, category)
    if not OriginalAppearance or not CurrentAppearance or not category then return false end

    if sectionId == 'skinshop' then
        if category.kind == 'component' then
            local o = getCompValue(OriginalAppearance, category.component)
            local c = getCompValue(CurrentAppearance, category.component)
            return o.drawable ~= c.drawable or o.texture ~= c.texture
        elseif category.kind == 'prop' then
            local o = getPropValue(OriginalAppearance, category.prop)
            local c = getPropValue(CurrentAppearance, category.prop)
            return o.drawable ~= c.drawable or o.texture ~= c.texture
        end
    elseif sectionId == 'barbershop' or sectionId == 'creator' then
        if category.kind == 'hair' then
            local oh = OriginalAppearance.hair or {}
            local ch = CurrentAppearance.hair or {}
            return (oh.style or 0) ~= (ch.style or 0) or (oh.color or 0) ~= (ch.color or 0) or (oh.highlight or 0) ~= (ch.highlight or 0)
        elseif category.kind == 'eyeColor' then
            return (OriginalAppearance.eyeColor or 0) ~= (CurrentAppearance.eyeColor or 0)
        elseif category.kind == 'overlay' then
            local oh = (OriginalAppearance.headOverlays and OriginalAppearance.headOverlays[category.overlay]) or {}
            local ch = (CurrentAppearance.headOverlays and CurrentAppearance.headOverlays[category.overlay]) or {}
            return (oh.style or 0) ~= (ch.style or 0) or (oh.color or 0) ~= (ch.color or 0)
        end
    elseif sectionId == 'tattoos' then
        local o = getTattooName(OriginalAppearance, category.zone)
        local c = getTattooName(CurrentAppearance, category.zone)
        return o ~= c
    end

    return false
end

local function updateCartForCategory(sectionId, categoryId)
    if not cartEnabled then return end
    local key = sectionId .. ':' .. categoryId
    local category = CategoryIndex[key]
    if not category then return end

    local changed = isCategoryChanged(sectionId, category)
    local sectionType = (sectionId == 'skinshop' and 'clothing') or (sectionId == 'barbershop' and 'barber') or (sectionId == 'tattoos' and 'tattoo') or nil
    local economy = activeLocation and type(activeLocation.economy) == 'table' and activeLocation.economy or {}
    local itemPrices = type(economy.itemPrices) == 'table' and economy.itemPrices or {}
    local price = tonumber(itemPrices[sectionType]) or tonumber(economy.unitPrice)
        or (sectionType and Config.Prices and Config.Prices[sectionType]) or 0
    price = math.max(0, math.floor(tonumber(price) or 0))

    if changed and not CartKeys[key] then
        CartKeys[key] = true
        CartTotal = CartTotal + price
        SendNUIMessage({ action = 'cart_update', total = CartTotal })
    elseif (not changed) and CartKeys[key] then
        CartKeys[key] = nil
        CartTotal = math.max(0, CartTotal - price)
        SendNUIMessage({ action = 'cart_update', total = CartTotal })
    end
end

local function getCurrentSelectionId(sectionId, category)
    if not CurrentAppearance or not category then return nil end

    if sectionId == 'skinshop' then
        if category.kind == 'component' then
            local c = getCompValue(CurrentAppearance, category.component)
            return tostring(c.drawable or 0)
        elseif category.kind == 'prop' then
            local p = getPropValue(CurrentAppearance, category.prop)
            return tostring(p.drawable == nil and -1 or p.drawable)
        end
    elseif sectionId == 'barbershop' or sectionId == 'creator' then
        if category.kind == 'hair' then
            return tostring((CurrentAppearance.hair and CurrentAppearance.hair.style) or 0)
        elseif category.kind == 'eyeColor' then
            return tostring(CurrentAppearance.eyeColor or 0)
        elseif category.kind == 'overlay' then
            local overlay = (CurrentAppearance.headOverlays and CurrentAppearance.headOverlays[category.overlay]) or {}
            if (tonumber(overlay.opacity) or 0) <= 0 or overlay.style == 255 then return 'none' end
            return tostring(overlay.style or 0)
        end
    elseif sectionId == 'tattoos' then
        local list = CurrentAppearance.tattoos and CurrentAppearance.tattoos[category.zone]
        if type(list) == 'table' and list[1] then
            local hash = (getGender() == 'male' and list[1].hashMale) or list[1].hashFemale
            if hash then return tostring(hash) end
        end
        return 'none'
    end

    return nil
end

local function syncAdjustBars(sectionId, category, selectedItem)
    if not category then return end

    if sectionId == 'skinshop' and selectedItem then
        local key = sectionId .. ':' .. category.id
        local max = getTextureMax(category, selectedItem.drawable)
        local current = 0
        if category.kind == 'component' then
            current = getCompValue(CurrentAppearance, category.component).texture or 0
        elseif category.kind == 'prop' then
            current = getPropValue(CurrentAppearance, category.prop).texture or 0
        end
        TextureMax[key] = max
        TextureState[key] = current
        SendNUIMessage({ action = 'texture_update', enabled = max > 1, current = current, max = max })
        SendNUIMessage({ action = 'colob_update', enabled = false })
        ActiveSelection = { sectionId = sectionId, categoryId = category.id, category = category, item = selectedItem }
        return
    end

    if sectionId == 'barbershop' or sectionId == 'creator' then
        SendNUIMessage({ action = 'texture_update', enabled = false })
        local max = getOverlayColorMax(category)
        local current = 0
        if category.kind == 'hair' then
            current = (CurrentAppearance.hair and CurrentAppearance.hair.color) or 0
        elseif category.kind == 'overlay' then
            local overlay = CurrentAppearance.headOverlays and CurrentAppearance.headOverlays[category.overlay]
            current = overlay and overlay.color or 0
        end
        ColorMax[sectionId .. ':' .. category.id] = max
        ColorState[sectionId .. ':' .. category.id] = current
        SendNUIMessage({ action = 'colob_update', enabled = max > 1, current = current, max = max })
        ActiveSelection = { sectionId = sectionId, categoryId = category.id, category = category, item = selectedItem }
        return
    end

    SendNUIMessage({ action = 'texture_update', enabled = false })
    SendNUIMessage({ action = 'colob_update', enabled = false })
    ActiveSelection = selectedItem and {
        sectionId = sectionId,
        categoryId = category.id,
        category = category,
        item = selectedItem
    } or nil
end

local function applySelection(sectionId, categoryId, item)
    if not CurrentAppearance then return end

    local key = sectionId .. ':' .. categoryId
    local category = CategoryIndex[key]
    if not category then return end

    local ped = PlayerPedId()
    ActiveSelection = { sectionId = sectionId, categoryId = categoryId, category = category, item = item }
    markDiagnosticAction('appearance_selection', {
        mode = activeMode,
        section = sectionId,
        category = categoryId,
        kind = category.kind,
        component = category.component,
        prop = category.prop,
        drawable = item and item.drawable,
    })

    if sectionId == 'skinshop' then
        if category.kind == 'component' then
            local applied = Appearance.setPedComponent(ped, {
                component_id = category.component,
                drawable = item.drawable,
                texture = 0
            })
            if not applied then return end
            setComponent(CurrentAppearance, category.component, applied.drawable, applied)
        elseif category.kind == 'prop' then
            local applied = Appearance.setPedProp(ped, {
                prop_id = category.prop,
                drawable = item.drawable,
                texture = 0
            })
            if not applied then return end
            setProp(CurrentAppearance, category.prop, applied.drawable, applied)
        end
        local max = getTextureMax(category, item.drawable)
        TextureMax[key] = max
        TextureState[key] = 0
        SendNUIMessage({ action = 'texture_update', enabled = max > 1, current = 0, max = max })
        SendNUIMessage({ action = 'colob_update', enabled = false })
    elseif sectionId == 'barbershop' or sectionId == 'creator' then
        if category.kind == 'hair' then
            local requested = deepCopy(CurrentAppearance.hair)
            requested.style = item.drawable
            requested.texture = 0
            requested.collection = nil
            requested.local_drawable = nil
            local applied = Appearance.setPedHair(ped, requested, CurrentAppearance.tattoos)
            if not applied then return end
            CurrentAppearance.hair = applied
        elseif category.kind == 'eyeColor' then
            CurrentAppearance.eyeColor = item.drawable
            Appearance.setPedEyeColor(ped, item.drawable)
        elseif category.kind == 'overlay' then
            local previous = CurrentAppearance.headOverlays[category.overlay] or {}
            local currentColor = ColorState[key]
            if currentColor == nil then currentColor = previous.color or 0 end
            CurrentAppearance.headOverlays[category.overlay] = {
                style = item.none and 0 or item.drawable,
                opacity = item.none and 0.0 or 1.0,
                color = currentColor,
                secondColor = previous.secondColor or currentColor
            }
            Appearance.setPedHeadOverlays(ped, CurrentAppearance.headOverlays)
        end
        SendNUIMessage({ action = 'texture_update', enabled = false })
        local max = getOverlayColorMax(category)
        if max and max > 0 then
            local colorKey = sectionId .. ':' .. categoryId
            local currentColor = ColorState[colorKey]
            if currentColor == nil then
                if category.kind == 'hair' then
                    currentColor = CurrentAppearance.hair.color or 0
                elseif category.kind == 'overlay' then
                    local overlay = CurrentAppearance.headOverlays[category.overlay]
                    currentColor = overlay and overlay.color or 0
                else
                    currentColor = 0
                end
            end
            ColorState[colorKey] = currentColor
            ColorMax[colorKey] = max
            SendNUIMessage({ action = 'colob_update', enabled = max > 1, current = currentColor, max = max })
        else
            SendNUIMessage({ action = 'colob_update', enabled = false })
        end
    elseif sectionId == 'tattoos' then
        CurrentAppearance.tattoos = CurrentAppearance.tattoos or {}

        if item.none then
            CurrentAppearance.tattoos[category.zone] = {}
        else
            local tat = TattooLookup[item.hash]
            if tat then
                CurrentAppearance.tattoos[category.zone] = {
                    {
                        name = tat.name,
                        label = tat.label,
                        hashMale = tat.hashMale,
                        hashFemale = tat.hashFemale,
                        zone = tat.zone,
                        collection = tat.collection,
                        opacity = 1.0
                    }
                }
            end
        end

        Appearance.setPedTattoos(ped, CurrentAppearance.tattoos)
        SendNUIMessage({ action = 'texture_update', enabled = false })
        SendNUIMessage({ action = 'colob_update', enabled = false })
    end
    updateCartForCategory(sectionId, categoryId)
end

local function applyUndress(ped, gender)
    local cfg = Config.UndressOutfits and Config.UndressOutfits[gender]
    if not cfg then return end

    for _, item in ipairs(cfg) do
        Appearance.setPedComponent(ped, {
            component_id = item.component,
            drawable = item.drawable,
            texture = item.texture or 0
        })
    end

    -- clear props
    ClearPedProp(ped, 0)
    ClearPedProp(ped, 1)
    ClearPedProp(ped, 2)
    ClearPedProp(ped, 6)
    ClearPedProp(ped, 7)
end

local function closeCreator()
    if not isOpen then return end
    local wasExternalStoreUi = externalStoreUi
    isOpen = false
    activeLocation = nil
    activeMode = 'shop'
    cartEnabled = true
    activeUiConfig = nil
    creatorGenderOverride = nil
    creatorIdentity = nil
    creatorCid = nil
    creatorHeading = nil
    creatorSaving = false
    storeSaving = false
    externalStoreUi = false

    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    destroyCamera()

    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)

    if wasExternalStoreUi then
        TriggerEvent('ob_creator:client:externalStoreClosed')
    else
        SendNUIMessage({ action = 'close' })
    end
end

local function applyDefaultOutfit(gender)
    if not Config.Creator or not Config.Creator.defaultOutfit then return end
    local cfg = Config.Creator.defaultOutfit[gender]
    if not cfg or not CurrentAppearance then return end

    local ped = PlayerPedId()
    local components = cfg.components or {}
    for _, item in ipairs(components) do
        local applied = Appearance.setPedComponent(ped, {
            component_id = item.component,
            drawable = item.drawable,
            texture = item.texture or 0
        })
        if applied then
            setComponent(CurrentAppearance, item.component, applied.drawable, applied)
        end
    end

    local props = cfg.props or {}
    for _, item in ipairs(props) do
        local applied = Appearance.setPedProp(ped, {
            prop_id = item.prop,
            drawable = item.drawable,
            texture = item.texture or 0
        })
        if applied then
            setProp(CurrentAppearance, item.prop, applied.drawable, applied)
        end
    end
end

local function applyHeadBlend(mother, father, shapeMix, skinMix)
    if not CurrentAppearance then return end
    local hb = CurrentAppearance.headBlend or {}
    hb.shapeFirst = mother or hb.shapeFirst or 0
    hb.shapeSecond = father or hb.shapeSecond or 0
    hb.shapeThird = hb.shapeThird or 0
    hb.skinFirst = hb.shapeFirst
    hb.skinSecond = hb.shapeSecond
    hb.skinThird = hb.skinThird or 0
    hb.shapeMix = shapeMix or hb.shapeMix or 0.5
    hb.skinMix = skinMix or hb.skinMix or 0.5
    hb.thirdMix = hb.thirdMix or 0

    CurrentAppearance.headBlend = hb
    Appearance.setPedHeadBlendAndWait(PlayerPedId(), hb)
end

local function stabilizeCurrentAppearance()
    if not CurrentAppearance or not Appearance.setPlayerAppearance(CurrentAppearance) then return false end

    -- Read back only the safe named getters after one complete writer pass.
    -- Besides confirming what the game accepted, this upgrades old global-only
    -- clothing saves to collection/local indexes before they reach the server.
    local captured = Appearance.getPedAppearance(PlayerPedId())
    if not captured then return false end
    CurrentAppearance = ensureAppearanceDefaults(captured)
    return true
end

local function applyFaceFeature(feature, value)
    if not CurrentAppearance or not feature then return end
    CurrentAppearance.faceFeatures = CurrentAppearance.faceFeatures or {}
    CurrentAppearance.faceFeatures[feature] = value or 0.0
    Appearance.setPedFaceFeatures(PlayerPedId(), CurrentAppearance.faceFeatures)
end

local function cancelAndClose()
    if creatorSaving then return end
    if activeMode == 'appearance' then
        local ok, cancelled = pcall(function() return OR.Callback.await('cancelAppearanceEdit') end)
        if not ok or cancelled ~= true then
            OR.Notify('Nao foi possivel encerrar a edicao. Tente novamente.', 'error')
            return
        end
        creatorInstanceActive = false
    end
    if OriginalAppearance then
        pcall(function()
            Appearance.setPlayerAppearance(OriginalAppearance)
        end)
    end
    if activeMode == 'creator' and creatorReturn then
        local ped = PlayerPedId()
        SetEntityCoords(ped, creatorReturn.x, creatorReturn.y, creatorReturn.z, false, false, false, false)
        SetEntityHeading(ped, creatorReturn.w or GetEntityHeading(ped))
        creatorReturn = nil
        creatorSpawned = false
    end
    if creatorInstanceActive then
        pcall(function()
            OR.Callback.await('leaveCreatorInstance')
        end)
        creatorInstanceActive = false
    end
    if pendingFinishPromise then
        pendingFinishPromise:resolve(false)
        pendingFinishPromise = nil
    end
    creatorIdentity = nil
    creatorCid = nil
    creatorHeading = nil
    closeCreator()
end

local function openCreator(loc, opts)
    if isOpen then return end
    opts = opts or {}
    isOpen = true
    activeLocation = loc
    activeMode = opts.mode or 'shop'
    cartEnabled = opts.cartEnabled ~= false
    activeUiConfig = opts.ui or Config.Ui
    -- Recursos externos podem fornecer uma configuracao de secoes propria
    -- (ex.: ob_stores), mas o catalogo continua centralizado no ob_creator.
    indexSections(activeUiConfig and activeUiConfig.sections)

    local ped = PlayerPedId()
    SetEntityHeading(ped, loc.heading or GetEntityHeading(ped))
    FreezeEntityPosition(ped, true)

    -- A mesma camera do criador acompanha as categorias da loja (rosto,
    -- torso, pernas etc.), mantendo o personagem sempre no enquadramento.
    createCamera(loc)
    setCamToPreset('full')
    faceCamera()

    CreateThread(function()
        local appearance = opts.initialAppearance or OR.Callback.await('getAppearance')
        local gender = getGender()

        if activeMode == 'creator' then
            local model = gender == 'male' and 'mp_m_freemode_01' or 'mp_f_freemode_01'
            Appearance.setPlayerModel(model)
        end

        if appearance then
            Appearance.setPlayerAppearance(appearance)
            CurrentAppearance = ensureAppearanceDefaults(appearance)
        else
            CurrentAppearance = ensureAppearanceDefaults(Appearance.getPedAppearance(PlayerPedId()))
            if activeMode == 'creator' then
                applyDefaultOutfit(gender)
            end
        end

        if activeMode == 'creator' or activeMode == 'appearance' then
            local pedNow = PlayerPedId()
            local targetHeading = creatorHeading or loc.heading or GetEntityHeading(pedNow)
            SetEntityHeading(pedNow, targetHeading)
            destroyCamera()
            createCamera(loc)
            setCamToPreset('full')
            faceCamera()
        end

        OriginalAppearance = deepCopy(CurrentAppearance)
        CartTotal = 0
        CartKeys = {}
        SendNUIMessage({ action = 'cart_update', total = CartTotal })

        if (loc.type == 'barber' or loc.type == 'tattoo') and activeMode ~= 'creator' then
            applyUndress(PlayerPedId(), getGender())
        end

        local allowedSections = opts.allowedSections or loc.allowedSections
        local defaultSection = opts.defaultSection or loc.defaultSection
        if not allowedSections and defaultSection then
            allowedSections = { defaultSection }
        end

        local imageBaseUrl = opts.imageBaseUrl or Config.ImageBaseUrl
        imageBaseUrl = replaceGenderToken(imageBaseUrl or "", gender)

        local uiConfig = prepareUiConfig(activeUiConfig)

        if opts.externalUi then
            externalStoreUi = true
            TriggerEvent('ob_creator:client:externalStoreReady', {
                id = opts.id or loc.id,
                data = uiConfig,
                defaultSection = defaultSection,
                allowedSections = allowedSections,
                title = opts.title or loc.title or loc.label,
                economy = opts.economy,
                imageBaseUrl = (imageBaseUrl or ""):gsub("^%s+", ""):gsub("%s+$", ""),
            })
            return
        end

        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false)
        SetCursorLocation(0.5, 0.5)

        SendNUIMessage({
            action = 'open',
            data = uiConfig,
            defaultSection = defaultSection,
            imageBaseUrl = (imageBaseUrl or ""):gsub("^%s+", ""):gsub("%s+$", ""),
            allowedSections = allowedSections,
            titleOverride = opts.title or loc.title or loc.label,
            imageProxyEnabled = Config.ImageProxy == true,
            uiOptions = {
                saveLabel = opts.saveLabel,
                cancelLabel = opts.cancelLabel,
                showTotal = cartEnabled,
                mode = activeMode,
                validation = (activeMode == 'creator' and Config.Creator and Config.Creator.Validation) or nil
            }
        })
        SendNUIMessage({ action = 'texture_update', enabled = false })
        SendNUIMessage({ action = 'colob_update', enabled = false })
        if activeMode == 'creator' or activeMode == 'appearance' then
            local parentsCfg = (Config.Creator and Config.Creator.parents) or {}
            local hb = CurrentAppearance.headBlend or {}
            local faceFeatures = {}
            for _, feature in ipairs(constants.FACE_FEATURES or {}) do
                faceFeatures[feature] = CurrentAppearance.faceFeatures and CurrentAppearance.faceFeatures[feature] or 0.0
            end
            SendNUIMessage({
                action = 'creatob_init',
                parents = {
                    mothers = parentsCfg.mothers or {},
                    fathers = parentsCfg.fathers or {}
                },
                selected = {
                    mother = hb.shapeFirst or parentsCfg.defaultMother or 0,
                    father = hb.shapeSecond or parentsCfg.defaultFather or 0
                },
                shapeMix = hb.shapeMix or 0.5,
                skinMix = hb.skinMix or hb.shapeMix or 0.5,
                identity = creatorIdentity,
                faceFeatures = faceFeatures,
                faceLabels = Config.CreatorFaceFeatures or {}
            })
        end
        if Config.Debug then
            print(('[ob_creator] ImageBaseUrl: %s'):format((imageBaseUrl or ""):gsub("^%s+", ""):gsub("%s+$", "")))
        end
    end)
end

local function openCharacterCreator()
    if not Config.Creator or Config.Creator.enabled == false then return end
    creatorIdentity = creatorIdentity or {
        firstname = '',
        lastname = '',
        nationality = 'Brasileiro',
        gender = 'male',
        birthdate = '2000-01-01',
    }
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    if Config.Creator.spawn and Config.Creator.spawn.coords then
        -- Do this before teleporting to the shared creator room.  Otherwise
        -- another player creating a character can stream this unfinished ped.
        local ok, entered = pcall(function()
            return OR.Callback.await('enterCreatorInstance')
        end)
        creatorInstanceActive = ok and entered == true
        if not creatorSpawned then
            creatorReturn = vec4(coords.x, coords.y, coords.z, GetEntityHeading(ped))
            creatorSpawned = true
        end
        DoScreenFadeOut(300)
        while not IsScreenFadedOut() do Wait(0) end
        local sp = Config.Creator.spawn.coords
        SetEntityCoords(ped, sp.x, sp.y, sp.z, false, false, false, false)
        SetEntityHeading(ped, (sp.w or sp.heading or 0.0))
        RequestCollisionAtCoord(sp.x, sp.y, sp.z)
        while not HasCollisionLoadedAroundEntity(ped) do Wait(0) end
        FreezeEntityPosition(ped, true)
        DoScreenFadeIn(300)
    end
    SetEntityVisible(ped, true, false)
    ResetEntityAlpha(ped)
    creatorHeading = GetEntityHeading(ped)

    if not creatorGenderOverride then
        creatorGenderOverride = 'male'
    end
    local model = creatorGenderOverride == 'female' and 'mp_f_freemode_01' or 'mp_m_freemode_01'
    Appearance.setPlayerModel(model)
    CurrentAppearance = ensureAppearanceDefaults(Appearance.getPedAppearance(PlayerPedId()))
    applyDefaultOutfit(creatorGenderOverride)
    local loc = {
        id = 'creator',
        label = Config.Creator.title or 'Criador de Personagem',
        title = Config.Creator.title or 'Criador de Personagem',
        type = 'creator',
        coords = Config.Creator.spawn and Config.Creator.spawn.coords or coords,
        heading = GetEntityHeading(ped),
        camOffset = Config.Creator.camOffset or vector3(0.0, 2.6, 0.55),
        lookAtOffset = Config.Creator.lookAtOffset or vector3(0.0, 0.0, 0.5),
        defaultSection = Config.Creator.defaultSection or 'creator',
        allowedSections = Config.Creator.allowedSections
    }

    openCreator(loc, {
        mode = 'creator',
        ui = Config.CreatorUi or Config.Ui,
        imageBaseUrl = Config.Creator.imageBaseUrl or '',
        title = Config.Creator.title or 'Criador de Personagem',
        saveLabel = 'Finalizar',
        cancelLabel = 'Cancelar',
        cartEnabled = false,
        defaultSection = Config.Creator.defaultSection or 'creator',
        allowedSections = Config.Creator.allowedSections
    })
end

RegisterNetEvent('ob_creator:client:editAppearance', function()
    if source ~= 65535 or appearanceOpening then return end
    TriggerEvent('ob_admin:client:closeForAppearance')
    if isOpen or IsNuiFocused() or IsPedInAnyVehicle(PlayerPedId(), false)
        or LocalPlayer.state['or:downed'] == true then
        OR.Callback.await('cancelAppearanceEdit')
        return OR.Notify('Feche outras interfaces, saia do veiculo e esteja consciente para editar a aparencia.', 'error')
    end
    appearanceOpening = true
    local ok, entered, appearance = pcall(function() return OR.Callback.await('beginAppearanceEdit') end)
    appearanceOpening = false
    if not ok or entered ~= true then
        OR.Callback.await('cancelAppearanceEdit')
        return OR.Notify(type(appearance)=='string' and appearance or 'Nao foi possivel abrir a aparencia.', 'error')
    end
    creatorInstanceActive = true
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    creatorHeading = GetEntityHeading(ped)
    -- Mesma interface completa, na posicao atual e em instancia privada.
    -- Nao executa criacao de personagem, cadastro, intro nem chegada ao aeroporto.
    openCreator({id='admin_appearance', type='appearance', coords=coords, heading=creatorHeading,
        camOffset=Config.Creator.camOffset, lookAtOffset=Config.Creator.lookAtOffset}, {
        mode='appearance', ui=Config.CreatorUi, cartEnabled=false,
        defaultSection='creator', allowedSections={'creator'},
        title='Refazer aparencia', saveLabel='Salvar aparencia', cancelLabel='Cancelar',
        initialAppearance=appearance, imageBaseUrl=Config.Creator.imageBaseUrl,
    })
end)

local function loadModelWithin(model, timeout)
    RequestModel(model)
    local deadline = GetGameTimer() + (timeout or 5000)

    while not HasModelLoaded(model) and GetGameTimer() < deadline do
        Wait(10)
    end

    return HasModelLoaded(model)
end

local function playPlaneIntro()
    local intro = Config.Creator and Config.Creator.intro
    if not intro or intro.enabled == false then return end

    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 500, true, true)
    if intro.camFov then
        SetCamFov(cam, intro.camFov)
    end

    if intro.tennis and intro.tennis.enabled then
        local tcfg = intro.tennis
        local peds = {}
        for i = 1, #tcfg.pedModels do
            local model = joaat(tcfg.pedModels[i])
            if loadModelWithin(model) then
                local c = tcfg.coords[i]
                if c then
                    local ped = CreatePed(4, model, c.x, c.y, c.z, c.w or 0.0, false, false)
                    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_TENNIS_PLAYER', 0, true)
                    peds[#peds + 1] = ped
                end
                SetModelAsNoLongerNeeded(model)
            end
        end

        if tcfg.cam and tcfg.cam.pos and tcfg.cam.lookAt then
            SetCamCoord(cam, tcfg.cam.pos.x, tcfg.cam.pos.y, tcfg.cam.pos.z)
            PointCamAtCoord(cam, tcfg.cam.lookAt.x, tcfg.cam.lookAt.y, tcfg.cam.lookAt.z)
        end

        DoScreenFadeIn(400)
        Wait(tcfg.duration or 4000)

        for _, ped in ipairs(peds) do
            DeleteEntity(ped)
        end
    end

    local model = joaat(intro.planeModel or 'luxor2')
    if not loadModelWithin(model, 2500) then
        model = joaat('luxor')
        if not loadModelWithin(model, 5000) then
            RenderScriptCams(false, true, 500, true, true)
            DestroyCam(cam, false)
            return
        end
    end

    local start = intro.planeStart
    local finish = intro.planeEnd
    if not start or not finish then return end

    local heading = GetHeadingFromVectob_2d(finish.x - start.x, finish.y - start.y)
    local plane = CreateVehicle(model, start.x, start.y, start.z, heading, false, false)
    SetEntityInvincible(plane, true)
    SetEntityCollision(plane, false, false)
    SetVehicleEngineOn(plane, true, true, false)
    SetEntityDynamic(plane, false)

    local pilotModel = joaat('s_m_m_pilot_02')
    local pilot
    if loadModelWithin(pilotModel, 5000) then
        pilot = CreatePedInsideVehicle(plane, 26, pilotModel, -1, false, false)
        SetModelAsNoLongerNeeded(pilotModel)
    end

    local duration = intro.duration or 8000
    local startTime = GetGameTimer()

    DoScreenFadeIn(400)
    while GetGameTimer() - startTime < duration do
        local t = (GetGameTimer() - startTime) / duration
        if t > 1.0 then t = 1.0 end
        local x = start.x + (finish.x - start.x) * t
        local y = start.y + (finish.y - start.y) * t
        local z = start.z + (finish.z - start.z) * t
        SetEntityCoordsNoOffset(plane, x, y, z, false, false, false)
        SetEntityHeading(plane, heading)

        local forward = GetEntityForwardVector(plane)
        local right = GetEntityRightVector(plane)
        local follow = intro.camFollow or { back = 200.0, up = 60.0, side = 0.0 }
        local camPos = vector3(
            x - forward.x * follow.back + right.x * (follow.side or 0),
            y - forward.y * follow.back + right.y * (follow.side or 0),
            z - forward.z * follow.back + (follow.up or 35.0)
        )
        SetCamCoord(cam, camPos.x, camPos.y, camPos.z)
        PointCamAtEntity(cam, plane, 0.0, 0.0, 0.0, true)
        Wait(0)
    end

    DoScreenFadeOut(400)
    while not IsScreenFadedOut() do Wait(0) end

    RenderScriptCams(false, true, 500, true, true)
    DestroyCam(cam, false)
    if DoesEntityExist(pilot) then DeleteEntity(pilot) end
    DeleteEntity(plane)
    SetModelAsNoLongerNeeded(model)
end

local function startSpawnSelection()
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })

    DoScreenFadeOut(400)
    while not IsScreenFadedOut() do Wait(0) end

    -- O novo personagem continua isolado ate confirmar o local de spawn.
    if creatorInstanceActive then
        pcall(function()
            OR.Callback.await('leaveCreatorInstance')
        end)
        creatorInstanceActive = false
    end

    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    DoScreenFadeIn(350)
    creatorReturn = nil
    creatorSpawned = false
    if pendingFinishPromise then
        pendingFinishPromise:resolve(true)
        pendingFinishPromise = nil
    end
    closeCreator()
    TriggerEvent('ob_spawn:client:open')
end

-- A primeira entrada nao usa a ultima posicao e tambem nao precisa abrir o
-- seletor de locais. O ponto de chegada fica no config do criador para que o
-- aeroporto possa ser trocado sem alterar o fluxo de personagem.
local function finishNewCharacterArrival()
    if Config.Creator and Config.Creator.spawnSelectionAfterCreation == true then
        return startSpawnSelection()
    end

    local arrival = Config.Creator and Config.Creator.arrival and Config.Creator.arrival.coords
    if not arrival then
        return startSpawnSelection()
    end

    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })

    DoScreenFadeOut(400)
    while not IsScreenFadedOut() do Wait(0) end

    if creatorInstanceActive then
        pcall(function()
            OR.Callback.await('leaveCreatorInstance')
        end)
        creatorInstanceActive = false
    end

    creatorReturn = nil
    creatorSpawned = false
    if pendingFinishPromise then
        pendingFinishPromise:resolve(true)
        pendingFinishPromise = nil
    end
    closeCreator()

    -- A cena opcional termina com a tela escura e entao liberamos o ped no
    -- aeroporto. Por padrao ela fica desligada no config.
    playPlaneIntro()

    ped = PlayerPedId()
    SetEntityCoords(ped, arrival.x, arrival.y, arrival.z, false, false, false, false)
    SetEntityHeading(ped, arrival.w or arrival.heading or 0.0)
    SetEntityVisible(ped, true, false)
    ResetEntityAlpha(ped)
    FreezeEntityPosition(ped, false)
    DisplayRadar(true)
    SetFollowPedCamViewMode(1)
    SetFollowVehicleCamViewMode(1)

    -- Aguarda a coordenada sincronizar antes de o core persistir a primeira
    -- posicao e publicar or:loaded.
    Wait(250)
    TriggerServerEvent('ob_spawn:server:markSpawned')
    DoScreenFadeIn(500)
end

RegisterNUICallback('close', function(_, cb)
    -- Criacao inicial nao pode ser cancelada. Alguns navegadores enviam este
    -- callback ao pressionar ESC ou ao tentar fechar a NUI; o encerramento
    -- valido e feito somente pelo fluxo de save/chegada apos finalizar.
    if activeMode == 'creator' then
        cb('ok')
        return
    end

    if activeMode == 'appearance' then cancelAndClose() else closeCreator() end
    cb('ok')
end)

RegisterNUICallback('focus', function(data, cb)
    setCamToPreset(data and data.focus or 'full')
    cb('ok')
end)

RegisterNUICallback('rotate', function(data, cb)
    local ped = PlayerPedId()
    local dir = data and data.dir or 0
    SetEntityHeading(ped, GetEntityHeading(ped) + (Config.Camera.rotateSpeed * dir))
    cb('ok')
end)

RegisterNUICallback('zoom', function(data, cb)
    if not camHandle then return cb('ok') end
    local dir = data and data.dir or 0
    camFov = math.max(Config.Camera.fovMin, math.min(Config.Camera.fovMax, camFov + (Config.Camera.zoomStep * dir)))
    SetCamFov(camHandle, camFov)
    cb('ok')
end)

RegisterNUICallback('get_items', function(data, cb)
    local sectionId = data and data.sectionId or ''
    local categoryId = data and data.categoryId or ''
    local page = data and data.page or 1
    local perPage = data and data.perPage or 60
    local autoSelect = data and data.autoSelect

    local items = buildItemsForCategory(sectionId, categoryId)
    local total = #items
    local totalPages = math.max(1, math.ceil(total / perPage))

    local currentPage = math.max(1, math.min(page or 1, totalPages))
    local selectedId = nil
    local selectedIndex = nil
    local selectedItem = nil

    if autoSelect or page == 0 then
        local category = CategoryIndex[sectionId .. ':' .. categoryId]
        selectedId = getCurrentSelectionId(sectionId, category)
        if selectedId then
            for i, item in ipairs(items) do
                if tostring(item.id) == tostring(selectedId) then
                    selectedIndex = i
                    selectedItem = item
                    break
                end
            end
        end

        if selectedIndex then
            currentPage = math.max(1, math.min(math.floor((selectedIndex - 1) / perPage) + 1, totalPages))
        else
            currentPage = 1
        end
    end

    local pageItems, _, _, _ = getPagedItems(items, currentPage, perPage)
    if autoSelect or page == 0 then
        local category = CategoryIndex[sectionId .. ':' .. categoryId]
        syncAdjustBars(sectionId, category, selectedItem)
    end

    cb({ items = pageItems, page = currentPage, totalPages = totalPages, total = total, selectedId = selectedId })
end)

RegisterNUICallback('select_item', function(data, cb)
    local sectionId = data and data.sectionId or ''
    local categoryId = data and data.categoryId or ''
    local item = data and data.item or nil

    if item and CurrentAppearance then
        applySelection(sectionId, categoryId, item)
    end

    cb('ok')
end)

RegisterNUICallback('texture_change', function(data, cb)
    if not ActiveSelection or ActiveSelection.sectionId ~= 'skinshop' then
        cb('ok')
        return
    end

    local sectionId = ActiveSelection.sectionId
    local categoryId = ActiveSelection.categoryId
    local category = ActiveSelection.category
    local key = sectionId .. ':' .. categoryId

    local max = TextureMax[key] or 1
    if max <= 1 then
        SendNUIMessage({ action = 'texture_update', enabled = false })
        cb('ok')
        return
    end

    local dir = (data and data.dir) or 0
    local current = TextureState[key] or 0
    current = (current + dir) % max
    TextureState[key] = current
    markDiagnosticAction('appearance_texture', {
        mode = activeMode,
        category = categoryId,
        component = category.component,
        prop = category.prop,
        drawable = ActiveSelection.item and ActiveSelection.item.drawable,
        texture = current,
    })

    local ped = PlayerPedId()
    if category.kind == 'component' then
        local saved = getCompValue(CurrentAppearance, category.component)
        local applied = Appearance.setPedComponent(ped, {
            component_id = category.component,
            drawable = ActiveSelection.item.drawable,
            texture = current,
            palette = saved.palette,
            collection = saved.collection,
            local_drawable = saved.local_drawable
        })
        if applied then
            current = applied.texture
            TextureState[key] = current
            setComponent(CurrentAppearance, category.component, applied.drawable, applied)
        end
    elseif category.kind == 'prop' then
        local saved = getPropValue(CurrentAppearance, category.prop)
        local applied = Appearance.setPedProp(ped, {
            prop_id = category.prop,
            drawable = ActiveSelection.item.drawable,
            texture = current,
            collection = saved.collection,
            local_drawable = saved.local_drawable
        })
        if applied then
            current = applied.texture
            TextureState[key] = current
            setProp(CurrentAppearance, category.prop, applied.drawable, applied)
        end
    end

    SendNUIMessage({ action = 'texture_update', enabled = true, current = current, max = max })
    updateCartForCategory(sectionId, categoryId)
    cb('ok')
end)

RegisterNUICallback('colob_change', function(data, cb)
    if not ActiveSelection or (ActiveSelection.sectionId ~= 'barbershop' and ActiveSelection.sectionId ~= 'creator') then
        cb('ok')
        return
    end

    local category = ActiveSelection.category
    if category.kind ~= 'hair' and category.kind ~= 'overlay' then
        cb('ok')
        return
    end

    local key = ActiveSelection.sectionId .. ':' .. ActiveSelection.categoryId
    local max = ColorMax[key] or getOverlayColorMax(category)
    if not max or max <= 1 then
        SendNUIMessage({ action = 'colob_update', enabled = false })
        cb('ok')
        return
    end

    local dir = (data and data.dir) or 0
    local current = ColorState[key] or 0
    current = (current + dir) % max
    ColorState[key] = current
    markDiagnosticAction('appearance_color', {
        mode = activeMode,
        category = ActiveSelection.categoryId,
        kind = category.kind,
        color = current,
    })

    local ped = PlayerPedId()
    if category.kind == 'hair' then
        local requested = deepCopy(CurrentAppearance.hair)
        requested.color = current
        requested.highlight = current
        local applied = Appearance.setPedHair(ped, requested, CurrentAppearance.tattoos)
        if applied then CurrentAppearance.hair = applied end
    elseif category.kind == 'overlay' then
        local overlay = CurrentAppearance.headOverlays[category.overlay] or { style = 0, opacity = 1.0, color = 0, secondColor = 0 }
        overlay.color = current
        overlay.secondColor = current
        CurrentAppearance.headOverlays[category.overlay] = overlay
        Appearance.setPedHeadOverlays(ped, CurrentAppearance.headOverlays)
    end

    SendNUIMessage({ action = 'colob_update', enabled = true, current = current, max = max })
    updateCartForCategory(ActiveSelection.sectionId, ActiveSelection.categoryId)
    cb('ok')
end)

RegisterNUICallback('creatob_submit_identity', function(data, cb)
    if activeMode == 'appearance' then cb('ok'); return end
    creatorIdentity = data or {}
    if not creatorIdentity.nationality or creatorIdentity.nationality == '' then
        creatorIdentity.nationality = 'Brasileiro'
    end
    local gender = creatorIdentity.gender == 'female' and 'female' or 'male'
    local previousGender = creatorGenderOverride
    creatorGenderOverride = gender

    if previousGender ~= gender or not CurrentAppearance then
        local model = gender == 'male' and 'mp_m_freemode_01' or 'mp_f_freemode_01'
        Appearance.setPlayerModel(model)
        CurrentAppearance = ensureAppearanceDefaults(Appearance.getPedAppearance(PlayerPedId()))
        applyDefaultOutfit(gender)
    end
    faceCamera()

    if pendingIdentityPromise then
        pendingIdentityPromise:resolve(creatorIdentity)
        pendingIdentityPromise = nil
    end
    TriggerEvent('ob_creator:client:identityResult', creatorIdentity)
    cb('ok')
end)

RegisterNUICallback('creatob_set_gender', function(data, cb)
    if activeMode == 'appearance' then cb('ok'); return end
    local gender = (data and data.gender) == 'female' and 'female' or 'male'
    creatorGenderOverride = gender
    local model = gender == 'male' and 'mp_m_freemode_01' or 'mp_f_freemode_01'
    Appearance.setPlayerModel(model)
    CurrentAppearance = ensureAppearanceDefaults(Appearance.getPedAppearance(PlayerPedId()))
    applyDefaultOutfit(gender)
    faceCamera()
    cb('ok')
end)

RegisterNUICallback('creatob_set_parents', function(data, cb)
    local mother = data and data.mother or 0
    local father = data and data.father or 0
    local shapeMix = data and data.shapeMix or 0.5
    local skinMix = data and data.skinMix or shapeMix
    applyHeadBlend(mother, father, shapeMix, skinMix)
    cb('ok')
end)

RegisterNUICallback('creatob_set_face_feature', function(data, cb)
    local feature = data and data.feature
    local value = data and data.value
    if feature then
        applyFaceFeature(feature, value or 0.0)
    end
    cb('ok')
end)

RegisterNUICallback('save', function(data, cb)
    if creatorSaving then cb('ok'); return end
    if CurrentAppearance then
        if activeMode == 'appearance' then
            creatorSaving = true
            local ok, saved, message = pcall(function()
                if not stabilizeCurrentAppearance() then return false, 'A aparencia ainda nao terminou de carregar.' end
                return OR.Callback.await('finishAppearanceEdit', CurrentAppearance)
            end)
            creatorSaving = false
            if ok and saved then
                creatorInstanceActive = false
                OriginalAppearance = deepCopy(CurrentAppearance)
                closeCreator()
                OR.Notify('Aparencia salva. Os dados do personagem foram preservados.', 'success')
            else
                OR.Notify(message or 'Nao foi possivel salvar a aparencia. Tente novamente ou cancele.', 'error')
            end
        elseif activeMode == 'creator' then
            if data and data.identity then
                creatorIdentity = data.identity
                if not creatorIdentity.nationality or creatorIdentity.nationality == '' then
                    creatorIdentity.nationality = 'Brasileiro'
                end
                local gender = creatorIdentity.gender == 'female' and 'female' or 'male'
                creatorGenderOverride = gender
            end

            local validation = (Config.Creator and Config.Creator.Validation) or {}
            local messages = validation.messages or {}
            local first = trimString(creatorIdentity and creatorIdentity.firstname or '')
            local last = trimString(creatorIdentity and creatorIdentity.lastname or '')
            local birth = trimString(creatorIdentity and creatorIdentity.birthdate or '')

            if (validation.requireName ~= false and first == '') or (validation.requireSurname ~= false and last == '') then
                OR.Notify(messages.missingName or 'Preencha nome e sobrenome.', 'error')
                cb('ok')
                return
            end

            if validation.requireBirthdate ~= false and birth == '' then
                OR.Notify(messages.missingBirthdate or 'Informe a data de nascimento.', 'error')
                cb('ok')
                return
            end

            if isBlacklisted(first, validation.blacklist and validation.blacklist.names)
                or isBlacklisted(last, validation.blacklist and validation.blacklist.surnames) then
                OR.Notify(messages.blacklisted or 'Nome ou sobrenome nao permitido.', 'error')
                cb('ok')
                return
            end

            local minAge = tonumber(validation.minAge) or 0
            if minAge > 0 and birth ~= '' then
                local parts = parseBirthdate(birth)
                if not parts then
                    OR.Notify(messages.invalidBirthdate or 'Data de nascimento invalida.', 'error')
                    cb('ok')
                    return
                end
                local age = calculateAge(parts)
                if not age or age < minAge then
                    OR.Notify(messages.underage or 'Voce precisa ter 18 anos ou mais.', 'error')
                    cb('ok')
                    return
                end
            end

            if not creatorIdentity or not creatorIdentity.firstname or not creatorIdentity.lastname or not creatorIdentity.birthdate then
                OR.Notify(messages.missingName or 'Preencha nome, sobrenome e data de nascimento.', 'error')
                cb('ok')
                return
            end

            local birthParts = parseBirthdate(birth)
            local payload = {
                firstname = capString(first),
                lastname = capString(last),
                nationality = capString(creatorIdentity.nationality or 'Brasileiro'),
                gender = (creatorIdentity.gender == 'female') and 1 or 0,
                birthdate = ('%04d-%02d-%02d'):format(birthParts.year, birthParts.month, birthParts.day),
                slot = creatorCid
            }

            if not stabilizeCurrentAppearance() then
                OR.Notify('A aparencia nao terminou de carregar. Tente finalizar novamente.', 'error')
                cb('ok')
                return
            end

            creatorSaving = true

            local ok, newData = pcall(function()
                return OR.Callback.awaitResource('ob_core', 'createCharacter', payload)
            end)

            if (not ok) or (not newData) then
                creatorSaving = false
                OR.Notify('Falha ao criar o personagem. Tente novamente.', 'error')
                cb('ok')
                return
            end

            local saved = OR.Callback.await('saveAppearance', CurrentAppearance)
            if not saved then
                creatorSaving = false
                OR.Notify('Nao foi possivel salvar a aparencia do personagem.', 'error')
                cb('ok')
                return
            end
            creatorSaving = false
            finishNewCharacterArrival()
        elseif activeMode == 'store' then
            -- As lojas usam a mesma aparencia/tabela do criador. A cobranca
            -- fica desligada ate o modulo de economia ser introduzido.
            if not stabilizeCurrentAppearance() then
                OR.Notify('A aparencia nao terminou de carregar. Tente salvar novamente.', 'error')
                cb('ok')
                return
            end
            local saved = OR.Callback.await('saveAppearance', CurrentAppearance)
            if saved then
                OR.Notify('Aparencia salva.', 'success')
                closeCreator()
            else
                OR.Notify('Nao foi possivel salvar a aparencia.', 'error')
            end
        else
            TriggerServerEvent('ob_creator:server:purchaseAndSave', CurrentAppearance, CartTotal)
        end
    end
    cb('ok')
end)

RegisterNUICallback('cancel', function(_, cb)
    -- O criador inicial e obrigatorio: nao restaura a aparencia anterior nem
    -- devolve o jogador para a selecao de personagem por ESC/botao de apagar.
    if activeMode == 'creator' then
        cb('ok')
        return
    end

    cancelAndClose()
    cb('ok')
end)

RegisterNUICallback('img_error', function(data, cb)
    if Config.Debug then
        print(('[ob_creator] NUI image error (%s): %s'):format(data and data.kind or 'unknown', data and data.src or 'nil'))
    end
    cb('ok')
end)

RegisterNUICallback('ui_debug', function(data, cb)
    if Config.Debug then
        print(('[ob_creator] NUI baseUrl: %s'):format(data and data.baseUrl or 'nil'))
    end
    cb('ok')
end)

AddEventHandler('onClientResourceStart', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end)

-- Diagnostico manual para o caso em que o material verde reaparecer no
-- Enhanced. O servidor aceita o resultado apenas de quem possui or.developer,
-- assim podemos le-lo no fxserver.log sem coletar ou expor dados do jogador.
RegisterCommand('ob_hairdiag', function()
    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) then return end

    local r0, g0, b0 = GetPedHairRgbColor(0)
    local r1, g1, b1 = GetPedHairRgbColor(1)
    local blendStatus = Appearance.getPedHeadBlendStatus(ped)
    TriggerServerEvent('ob_creator:server:hairDiagnostic', {
        model = GetEntityModel(ped),
        blendFinished = blendStatus.nativeFinished,
        blendCached = blendStatus.cached,
        blendSettled = blendStatus.settled,
        blendTimedOut = blendStatus.timedOut,
        blendFinalized = blendStatus.finalized,
        style = GetPedDrawableVariation(ped, 2),
        texture = GetPedTextureVariation(ped, 2),
        palette = type(GetPedPaletteVariation) == 'function' and GetPedPaletteVariation(ped, 2) or 0,
        color = GetPedHairColor(ped),
        highlight = GetPedHairHighlightColor(ped),
        rgb0 = { r0, g0, b0 },
        rgb1 = { r1, g1, b1 }
    })
    print('[ob_creator] Diagnostico de cabelo enviado ao log do servidor.')
end, false)

AddEventHandler('onClientResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end

    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
    destroyCamera()
    if activeMode == 'appearance' and OriginalAppearance and not creatorSaving then
        pcall(function() Appearance.setPlayerAppearance(OriginalAppearance) end)
    end

    -- So desfaz o freeze se o proprio criador ainda era dono dele. Depois de
    -- finalizar, o ob_spawn passa a controlar o ped durante sua propria NUI.
    if isOpen then FreezeEntityPosition(PlayerPedId(), false) end
    if creatorInstanceActive then TriggerServerEvent('ob_creator:server:abortCreator') end
end)

RegisterCommand('orcreatob_close', function()
    if activeMode == 'creator' then return end
    cancelAndClose()
end, false)

RegisterNetEvent('ob_creator:client:openCharacterCreator', function(slot)
    creatorCid = tonumber(slot)
    openCharacterCreator()
end)

exports('openCharacterCreator', function(slot)
    creatorCid = tonumber(slot)
    openCharacterCreator()
end)

-- API publica para lojas de roupa, barbearias e tatuagens. O recurso que
-- cria o ponto no mundo nao precisa duplicar NUI, catalogo ou banco de dados.
exports('openStore', function(location)
    if type(location) ~= 'table' or not location.coords then return false end
    if isOpen then return false end

    openCreator(location, {
        mode = 'store',
        ui = location.ui or Config.Ui,
        title = location.title or location.label or 'Personalizacao',
        saveLabel = location.saveLabel or 'Salvar',
        cancelLabel = location.cancelLabel or 'Cancelar',
        cartEnabled = type(location.economy) == 'table' and location.economy.enabled == true,
        id = location.id,
        economy = location.economy,
        defaultSection = location.defaultSection,
        allowedSections = location.allowedSections,
        externalUi = location.externalUi == true,
    })
    return true
end)

-- API usada pela NUI propria do ob_stores. O ob_creator continua sendo o
-- unico recurso que aplica e salva aparencia; a interface fica desacoplada.
exports('storeGetItems', function(sectionId, categoryId, page, perPage)
    if not isOpen or activeMode ~= 'store' then return { items = {}, page = 1, totalPages = 1 } end
    local items = buildItemsForCategory(sectionId, categoryId)
    perPage = math.max(1, tonumber(perPage) or 24)
    local totalPages = math.max(1, math.ceil(#items / perPage))
    local requestedPage = tonumber(page) or 1
    local autoSelect = requestedPage == 0
    local category = CategoryIndex[sectionId .. ':' .. categoryId]
    local selectedId = getCurrentSelectionId(sectionId, category)
    local selectedIndex, selectedItem
    if selectedId ~= nil then
        for index, item in ipairs(items) do
            if tostring(item.id) == tostring(selectedId) then
                selectedIndex, selectedItem = index, item
                break
            end
        end
    end
    if autoSelect and selectedIndex then
        page = math.floor((selectedIndex - 1) / perPage) + 1
    else
        page = math.max(1, math.min(requestedPage, totalPages))
    end
    local startIndex = (page - 1) * perPage + 1
    local output = {}
    for index = startIndex, math.min(#items, startIndex + perPage - 1) do output[#output + 1] = items[index] end
    if autoSelect then syncAdjustBars(sectionId, category, selectedItem) end

    local texture, color
    if ActiveSelection and ActiveSelection.sectionId == 'skinshop' then
        local key = ActiveSelection.sectionId .. ':' .. ActiveSelection.categoryId
        texture = { enabled = (TextureMax[key] or 1) > 1, current = TextureState[key] or 0, max = TextureMax[key] or 1 }
    elseif ActiveSelection and (ActiveSelection.sectionId == 'barbershop' or ActiveSelection.sectionId == 'creator') then
        local key = ActiveSelection.sectionId .. ':' .. ActiveSelection.categoryId
        color = { enabled = (ColorMax[key] or 1) > 1, current = ColorState[key] or 0, max = ColorMax[key] or 1 }
    end
    return {
        items = output,
        page = page,
        totalPages = totalPages,
        selectedId = selectedId,
        texture = texture,
        color = color,
        cartTotal = CartTotal,
        cartCount = (function() local count = 0 for _ in pairs(CartKeys) do count = count + 1 end return count end)(),
    }
end)

exports('storeSelectItem', function(sectionId, categoryId, item)
    if not isOpen or activeMode ~= 'store' or type(item) ~= 'table' then return false end
    applySelection(sectionId, categoryId, item)
    local texture = nil
    local color = nil
    if ActiveSelection and ActiveSelection.sectionId == 'skinshop' then
        local key = ActiveSelection.sectionId .. ':' .. ActiveSelection.categoryId
        texture = { enabled = (TextureMax[key] or 1) > 1, current = TextureState[key] or 0, max = TextureMax[key] or 1 }
    elseif ActiveSelection and (ActiveSelection.sectionId == 'barbershop' or ActiveSelection.sectionId == 'creator') then
        local key = ActiveSelection.sectionId .. ':' .. ActiveSelection.categoryId
        color = { enabled = (ColorMax[key] or 1) > 1, current = ColorState[key] or 0, max = ColorMax[key] or 1 }
    end
    local count = 0 for _ in pairs(CartKeys) do count = count + 1 end
    return { ok = true, texture = texture, color = color, cartTotal = CartTotal, cartCount = count }
end)

exports('storeFocus', function(focus)
    if isOpen and activeMode == 'store' then setCamToPreset(focus or 'full') end
end)

exports('storeChangeTexture', function(direction)
    if not ActiveSelection or ActiveSelection.sectionId ~= 'skinshop' then return { enabled = false } end
    local category = ActiveSelection.category
    local key = ActiveSelection.sectionId .. ':' .. ActiveSelection.categoryId
    local max = TextureMax[key] or 1
    if max <= 1 then return { enabled = false } end
    local current = ((TextureState[key] or 0) + (tonumber(direction) or 0)) % max
    TextureState[key] = current
    local ped = PlayerPedId()
    if category.kind == 'component' then
        local saved = getCompValue(CurrentAppearance, category.component)
        local applied = Appearance.setPedComponent(ped, {
            component_id = category.component,
            drawable = ActiveSelection.item.drawable,
            texture = current,
            palette = saved.palette,
            collection = saved.collection,
            local_drawable = saved.local_drawable
        })
        if applied then
            current = applied.texture
            TextureState[key] = current
            setComponent(CurrentAppearance, category.component, applied.drawable, applied)
        end
    elseif category.kind == 'prop' then
        local saved = getPropValue(CurrentAppearance, category.prop)
        local applied = Appearance.setPedProp(ped, {
            prop_id = category.prop,
            drawable = ActiveSelection.item.drawable,
            texture = current,
            collection = saved.collection,
            local_drawable = saved.local_drawable
        })
        if applied then
            current = applied.texture
            TextureState[key] = current
            setProp(CurrentAppearance, category.prop, applied.drawable, applied)
        end
    end
    updateCartForCategory(ActiveSelection.sectionId, ActiveSelection.categoryId)
    local count = 0 for _ in pairs(CartKeys) do count = count + 1 end
    return { texture = { enabled = true, current = current, max = max }, cartTotal = CartTotal, cartCount = count }
end)

exports('storeChangeColor', function(direction)
    if not ActiveSelection or (ActiveSelection.sectionId ~= 'barbershop' and ActiveSelection.sectionId ~= 'creator') then return { enabled = false } end
    local category = ActiveSelection.category
    if category.kind ~= 'hair' and category.kind ~= 'overlay' then return { enabled = false } end
    local key = ActiveSelection.sectionId .. ':' .. ActiveSelection.categoryId
    local max = ColorMax[key] or getOverlayColorMax(category)
    if not max or max <= 1 then return { enabled = false } end
    local current = ((ColorState[key] or 0) + (tonumber(direction) or 0)) % max
    ColorState[key] = current
    if category.kind == 'hair' then
        local requested = deepCopy(CurrentAppearance.hair)
        requested.color = current
        requested.highlight = current
        local applied = Appearance.setPedHair(PlayerPedId(), requested, CurrentAppearance.tattoos)
        if applied then CurrentAppearance.hair = applied end
    else
        local overlay = CurrentAppearance.headOverlays[category.overlay] or { style = 0, opacity = 1.0, color = 0, secondColor = 0 }
        overlay.color, overlay.secondColor = current, current
        CurrentAppearance.headOverlays[category.overlay] = overlay
        Appearance.setPedHeadOverlays(PlayerPedId(), CurrentAppearance.headOverlays)
    end
    updateCartForCategory(ActiveSelection.sectionId, ActiveSelection.categoryId)
    local count = 0 for _ in pairs(CartKeys) do count = count + 1 end
    return { color = { enabled = true, current = current, max = max }, cartTotal = CartTotal, cartCount = count }
end)

exports('storeSave', function(checkout)
    if not isOpen or activeMode ~= 'store' or not CurrentAppearance or storeSaving then return false end
    checkout = type(checkout) == 'table' and checkout or nil
    if checkout and cartEnabled and next(CartKeys) == nil then
        OR.Notify('Nenhuma alteracao foi selecionada.', 'error')
        return false
    end
    storeSaving = true
    CreateThread(function()
        if not stabilizeCurrentAppearance() then
            storeSaving = false
            OR.Notify('A aparencia nao terminou de carregar. Tente salvar novamente.', 'error')
            return
        end
        local saved, message
        if checkout and type(checkout.callbackResource) == 'string' and checkout.callbackResource ~= ''
            and type(checkout.locationId) == 'string' and checkout.locationId ~= '' then
            saved, message = OR.Callback.awaitResource(checkout.callbackResource, 'purchase', checkout.locationId, CurrentAppearance)
        else
            saved = OR.Callback.await('saveAppearance', CurrentAppearance)
        end
        storeSaving = false
        if saved then
            OR.Notify(message or 'Aparencia salva.', 'success')
            closeCreator()
        else
            OR.Notify(message or 'Nao foi possivel salvar a aparencia.', 'error')
        end
    end)
    return true
end)

exports('storeCancel', function()
    if not isOpen or activeMode ~= 'store' then return false end
    cancelAndClose()
    return true
end)

RegisterNetEvent('ob_core:client:characterSelected', function(character)
    if not character or not character.userId then return end
    creatorGenderOverride = tonumber(character.gender) == 1 and 'female' or 'male'

    CreateThread(function()
        local appearance = OR.Callback.await('getAppearance')
        if appearance then
            pcall(function()
                Appearance.setPlayerAppearance(appearance)
            end)
        end
        TriggerEvent('ob_core:client:appearanceReady', character.userId)
    end)
end)

RegisterNetEvent('ob_creator:client:purchaseResult', function(success, message)
    if success then
        if CurrentAppearance then
            pcall(function()
                Appearance.setPlayerAppearance(CurrentAppearance)
            end)
        end
        OR.Notify(message or 'Compra realizada.', 'success')
        closeCreator()
    else
        OR.Notify(message or 'Economia indisponivel.', 'error')
        cancelAndClose()
    end
end)

CreateThread(function()
    setupBlips()

    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local pcoords = GetEntityCoords(ped)

        for _, loc in ipairs(Config.Locations or {}) do
            local dist = #(pcoords - loc.coords)
            if dist < 20.0 then
                sleep = 0
                local style = Config.TypeStyles and Config.TypeStyles[loc.type] or nil
                local markerColor = (style and style.marker and style.marker.color) or Config.Marker.color

                DrawMarker(
                    Config.Marker.type,
                    loc.coords.x, loc.coords.y, loc.coords.z + Config.Marker.zOffset,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, 0.0,
                    Config.Marker.radius * 2.0, Config.Marker.radius * 2.0, 0.45,
                    markerColor[1], markerColor[2], markerColor[3], markerColor[4],
                    false, true, 2, false, nil, nil, false
                )

                if dist < 1.5 and not isOpen then
                    local hint = Config.Hint or {}
                    if hint.type == '3d' then
                        local offset = hint.offset or vector3(0.0, 0.0, 0.6)
                        draw3DText(loc.coords + offset, hint.text or '[E] Abrir', hint.scale or 0.35, hint.color or {255, 255, 255, 215})
                    else
                        drawHelp('Pressione ~INPUT_CONTEXT~ para abrir o Orbis Creator')
                    end
                    if IsControlJustPressed(0, 38) then
                        openCreator(loc)
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        if isOpen then
            if not IsNuiFocused() then
                SetNuiFocus(true, true)
                SetNuiFocusKeepInput(false)
            end
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)
            DisableControlAction(0, 32, true)
            DisableControlAction(0, 33, true)
            DisableControlAction(0, 34, true)
            DisableControlAction(0, 35, true)
            DisableControlAction(0, 106, true)
            DisableControlAction(0, 177, true)
            DisableControlAction(0, 200, true)
            DisableControlAction(0, 322, true)

            HideHudAndRadarThisFrame()

            if IsDisabledControlPressed(0, 34) then
                SetEntityHeading(PlayerPedId(), GetEntityHeading(PlayerPedId()) + Config.Camera.rotateSpeed)
            elseif IsDisabledControlPressed(0, 35) then
                SetEntityHeading(PlayerPedId(), GetEntityHeading(PlayerPedId()) - Config.Camera.rotateSpeed)
            end

            if IsControlJustPressed(0, 14) then
                camFov = math.max(Config.Camera.fovMin, camFov - Config.Camera.zoomStep)
                if camHandle then SetCamFov(camHandle, camFov) end
            elseif IsControlJustPressed(0, 15) then
                camFov = math.min(Config.Camera.fovMax, camFov + Config.Camera.zoomStep)
                if camHandle then SetCamFov(camHandle, camFov) end
            end

            if activeMode ~= 'creator' and (
                IsDisabledControlJustPressed(0, 177)
                or IsDisabledControlJustPressed(0, 200)
                or IsDisabledControlJustPressed(0, 322)
                or IsControlJustPressed(0, 177)
                or IsControlJustPressed(0, 200)
                or IsControlJustPressed(0, 322)
            ) then
                cancelAndClose()
            end

            Wait(0)
        else
            SetNuiFocus(false, false)
            SendNUIMessage({ action = 'close' })
            Wait(1000)
        end
    end
end)
