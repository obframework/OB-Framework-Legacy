-- Compatibilidade leve para recursos antigos que carregam @PolyZone/client.lua.
-- As zonas ficam no recurso consumidor, exatamente como no PolyZone original.
PolyZone = PolyZone or {}
CircleZone = CircleZone or {}

local function toVec3(coords)
    return vec3(tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0, tonumber(coords.z) or 0.0)
end

function CircleZone:Create(coords, radius, options)
    local zone = {
        center = toVec3(coords),
        radius = math.max(0.1, tonumber(radius) or 1.0),
        options = options or {},
        destroyed = false,
        inside = false
    }

    function zone:isPointInside(point)
        return #(toVec3(point) - self.center) <= self.radius
    end

    function zone:onPlayerInOut(callback, interval)
        CreateThread(function()
            while not self.destroyed do
                local isInside = self:isPointInside(GetEntityCoords(PlayerPedId()))
                if isInside ~= self.inside then
                    self.inside = isInside
                    callback(isInside, nil, self)
                end
                Wait(isInside and 100 or (interval or 400))
            end
        end)
    end

    function zone:destroy()
        self.destroyed = true
    end

    return zone
end
