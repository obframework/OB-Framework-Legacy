local resourceName = GetCurrentResourceName()

-- O import e executado dentro do resource consumidor. A ob_lib centraliza os
-- arquivos, a versao e alguns coordenadores, mas cada resource recebe seu
-- proprio namespace OR e seus proprios callbacks.
if resourceName == 'ob_lib' then return end

local function loadModule(path)
    local source = LoadResourceFile('ob_lib', path)
    assert(type(source) == 'string' and source ~= '', ('modulo ob_lib ausente: %s'):format(path))
    local chunk, loadError = load(source, ('@ob_lib/%s'):format(path), 't', _ENV)
    assert(chunk, ('falha ao carregar %s: %s'):format(path, tostring(loadError)))
    return chunk()
end

loadModule('imports/shared/base.lua')
loadModule('imports/shared/validate.lua')
loadModule('imports/shared/currency.lua')
loadModule('imports/shared/locale.lua')
loadModule('imports/shared/logger.lua')

if IsDuplicityVersion() then
    loadModule('imports/server/security.lua')
    loadModule('imports/server/callback.lua')
    loadModule('imports/server/economy.lua')
else
    loadModule('imports/client/callback.lua')
    loadModule('imports/client/streaming.lua')
    loadModule('imports/client/entity.lua')
    loadModule('imports/client/nui.lua')
    loadModule('imports/client/input.lua')
    loadModule('imports/client/cache.lua')
    loadModule('imports/client/points.lua')
    loadModule('imports/client/ui.lua')
end
