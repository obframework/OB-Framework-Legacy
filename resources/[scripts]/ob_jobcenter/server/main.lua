local function allowedKeys()
    local keys = {}
    for _, job in ipairs(OBJobCenterConfig.Jobs or {}) do
        if type(job.key) == 'string' and job.key ~= '' then keys[#keys + 1] = job.key:lower() end
    end
    return keys
end

local function nearCenter(source)
    local ped = GetPlayerPed(source)
    if not ped or ped <= 0 then return false end
    local coords = GetEntityCoords(ped)
    local location = OBJobCenterConfig.Location.coords
    return #(coords - vector3(location.x, location.y, location.z))
        <= (tonumber(OBJobCenterConfig.Location.interactionDistance) or 3.0) + 2.0
end

local function jobConfig(key)
    for _, job in ipairs(OBJobCenterConfig.Jobs or {}) do
        if job.key == key then return job end
    end
end

local function status(source)
    if GetResourceState('ob_org') ~= 'started' then return nil, 'Sistema de organizacoes indisponivel.' end
    local ok, data, err = pcall(function()
        return exports.ob_org:GetPublicEmploymentStatus(
            source, allowedKeys(), OBJobCenterConfig.MinimumStaySeconds
        )
    end)
    if not ok or not data then return nil, ok and err or 'Falha ao consultar as organizacoes.' end

    local available = {}
    for _, job in ipairs(data.jobs or {}) do available[job.key] = job end
    data.jobs = {}
    for _, configured in ipairs(OBJobCenterConfig.Jobs or {}) do
        local job = available[configured.key]
        if job then
            job.description = configured.description
            job.tag = configured.tag
        else
            job = {
                key = configured.key,
                label = configured.fallbackLabel or configured.key,
                rankLabel = 'Indisponivel',
                description = configured.description,
                tag = configured.tag,
                available = false,
                unavailableReason = 'Organizacao legal nao cadastrada ou desativada.',
            }
        end
        data.jobs[#data.jobs + 1] = job
    end
    data.rules = OBJobCenterConfig.Rules
    data.minimumStaySeconds = OBJobCenterConfig.MinimumStaySeconds
    data.leaveBlacklistSeconds = OBJobCenterConfig.LeaveBlacklistSeconds
    return data
end

OR.Callback.register('status', function(source)
    if not OR.Security.rateLimit(source, 'jobcenter:status', 6, 10000) then
        return nil, 'Aguarde um instante.'
    end
    if not nearCenter(source) then return nil, 'Aproxime-se da Central de Empregos.' end
    return status(source)
end)

OR.Callback.register('join', function(source, orgKey)
    if not OR.Security.rateLimit(source, 'jobcenter:join', 2, 10000) then
        return false, 'Aguarde antes de tentar novamente.'
    end
    if not nearCenter(source) then return false, 'Aproxime-se da Central de Empregos.' end
    local configured = jobConfig(type(orgKey) == 'string' and orgKey:lower() or '')
    if not configured then return false, 'Trabalho nao autorizado nesta central.' end
    local ok, success, message = pcall(function()
        return exports.ob_org:JoinPublicEmployment(source, configured.key, allowedKeys())
    end)
    if not ok then return false, 'Sistema de organizacoes indisponivel.' end
    return success == true, message
end)

OR.Callback.register('leave', function(source)
    if not OR.Security.rateLimit(source, 'jobcenter:leave', 2, 10000) then
        return false, 'Aguarde antes de tentar novamente.'
    end
    if not nearCenter(source) then return false, 'Aproxime-se da Central de Empregos.' end
    local ok, success, message = pcall(function()
        return exports.ob_org:LeavePublicEmployment(
            source, allowedKeys(), OBJobCenterConfig.MinimumStaySeconds,
            OBJobCenterConfig.LeaveBlacklistSeconds
        )
    end)
    if not ok then return false, 'Sistema de organizacoes indisponivel.' end
    return success == true, message
end)
