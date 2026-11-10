local Streaming = OR.Streaming

local function waitFor(hasLoaded, timeout)
    local deadline = GetGameTimer() + math.max(250, math.floor(tonumber(timeout) or 8000))
    repeat
        if hasLoaded() then return true end
        Wait(0)
    until GetGameTimer() >= deadline
    return hasLoaded()
end

local function modelHash(model)
    if type(model) == 'string' then model = joaat(model) end
    model = tonumber(model)
    return model and math.floor(model) or nil
end

function Streaming.RequestModel(model, timeout)
    model = modelHash(model)
    if not model or not IsModelInCdimage(model) or not IsModelValid(model) then return false end
    RequestModel(model)
    return waitFor(function() return HasModelLoaded(model) end, timeout)
end

function Streaming.ReleaseModel(model)
    model = modelHash(model)
    if not model then return false end
    SetModelAsNoLongerNeeded(model)
    return true
end

function Streaming.RequestAnimDict(dictionary, timeout)
    if type(dictionary) ~= 'string' or dictionary == '' or not DoesAnimDictExist(dictionary) then return false end
    RequestAnimDict(dictionary)
    return waitFor(function() return HasAnimDictLoaded(dictionary) end, timeout)
end

function Streaming.ReleaseAnimDict(dictionary)
    if type(dictionary) ~= 'string' or dictionary == '' then return false end
    RemoveAnimDict(dictionary)
    return true
end

function Streaming.RequestAnimSet(animationSet, timeout)
    if type(animationSet) ~= 'string' or animationSet == '' then return false end
    RequestAnimSet(animationSet)
    return waitFor(function() return HasAnimSetLoaded(animationSet) end, timeout)
end

function Streaming.ReleaseAnimSet(animationSet)
    if type(animationSet) ~= 'string' or animationSet == '' then return false end
    RemoveAnimSet(animationSet)
    return true
end

function Streaming.RequestPtfx(asset, timeout)
    if type(asset) ~= 'string' or asset == '' then return false end
    RequestNamedPtfxAsset(asset)
    return waitFor(function() return HasNamedPtfxAssetLoaded(asset) end, timeout)
end

function Streaming.ReleasePtfx(asset)
    if type(asset) ~= 'string' or asset == '' then return false end
    RemoveNamedPtfxAsset(asset)
    return true
end

function Streaming.RequestTextureDictionary(dictionary, timeout)
    if type(dictionary) ~= 'string' or dictionary == '' then return false end
    RequestStreamedTextureDict(dictionary, false)
    return waitFor(function() return HasStreamedTextureDictLoaded(dictionary) end, timeout)
end

function Streaming.ReleaseTextureDictionary(dictionary)
    if type(dictionary) ~= 'string' or dictionary == '' then return false end
    SetStreamedTextureDictAsNoLongerNeeded(dictionary)
    return true
end

function Streaming.RequestScaleform(movie, timeout)
    if type(movie) ~= 'string' or movie == '' then return nil end
    local handle = RequestScaleformMovie(movie)
    if handle == 0 then return nil end
    return waitFor(function() return HasScaleformMovieLoaded(handle) end, timeout) and handle or nil
end

function Streaming.ReleaseScaleform(handle)
    handle = tonumber(handle)
    if not handle or handle == 0 then return false end
    SetScaleformMovieAsNoLongerNeeded(handle)
    return true
end

function Streaming.RequestWeaponAsset(weapon, timeout, flags)
    weapon = modelHash(weapon)
    if not weapon then return false end
    RequestWeaponAsset(weapon, math.floor(tonumber(flags) or 31), 0)
    return waitFor(function() return HasWeaponAssetLoaded(weapon) end, timeout)
end

function Streaming.ReleaseWeaponAsset(weapon)
    weapon = modelHash(weapon)
    if not weapon then return false end
    RemoveWeaponAsset(weapon)
    return true
end

function Streaming.RequestAudioBank(bank)
    return type(bank) == 'string' and bank ~= '' and RequestScriptAudioBank(bank, false) == true
end

function Streaming.ReleaseAudioBank(bank)
    if type(bank) ~= 'string' or bank == '' then return false end
    ReleaseNamedScriptAudioBank(bank)
    return true
end

-- Compatibilidade com a API anterior.
OR.Model.Load = Streaming.RequestModel
