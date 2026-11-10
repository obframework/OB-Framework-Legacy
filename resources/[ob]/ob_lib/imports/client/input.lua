local Input = OR.Input
local resourceName = GetCurrentResourceName()
local bindings = {}

local function safeName(value)
    value = tostring(value or ''):lower():gsub('[^%w_%-]', '_')
    return value ~= '' and value:sub(1, 64) or nil
end

function Input.RegisterKeybind(data)
    assert(type(data) == 'table', 'keybind data must be a table')
    local name = safeName(data.name)
    assert(name, 'keybind name must be set')
    local command = ('ob_%s_%s'):format(resourceName:gsub('[^%w_%-]', '_'), name)
    if bindings[name] then return bindings[name] end

    local binding = { name = name, command = command, enabled = data.enabled ~= false }
    function binding:setEnabled(enabled) self.enabled = enabled == true end
    function binding:isEnabled() return self.enabled end
    bindings[name] = binding

    RegisterCommand('+' .. command, function()
        if binding.enabled and type(data.onPressed) == 'function' then
            local ok, err = pcall(data.onPressed, binding)
            if not ok then OR.Logger.error(('keybind %s falhou'):format(name), err) end
        end
    end, false)
    RegisterCommand('-' .. command, function()
        if binding.enabled and type(data.onReleased) == 'function' then
            local ok, err = pcall(data.onReleased, binding)
            if not ok then OR.Logger.error(('keybind %s falhou ao soltar'):format(name), err) end
        end
    end, false)
    RegisterKeyMapping('+' .. command, data.description or name, data.device or 'keyboard', data.defaultKey or '')
    return binding
end

function Input.Get(name)
    return bindings[safeName(name)]
end

function Input.SetEnabled(name, enabled)
    local binding = Input.Get(name)
    if not binding then return false end
    binding:setEnabled(enabled)
    return true
end
