--!strict

local Formex = require(script.Parent:FindFirstChild("Formex"))

Formex.Math = {}

function Formex.Math.DoLinesIntersect(p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2): boolean
    local function Orientation(a: Vector2, b: Vector2, c: Vector2): number
        local val = (b.Y - a.Y) * (c.X - b.X) - (b.X - a.X) * (c.Y - b.Y)
        if val == 0 then
            return 0 -- collinear
        elseif val > 0 then
            return 1 -- clockwise
        else
            return 2 -- counterclockwise
        end
    end

    local o1 = Orientation(p1, p2, q1)
    local o2 = Orientation(p1, p2, q2)
    local o3 = Orientation(q1, q2, p1)
    local o4 = Orientation(q1, q2, p2)

    if o1 ~= o2 and o3 ~= o4 then return true end
    return false
end

function Formex.Math.IsSimplePolygon(polygon: {Vector2}): boolean
    -- A simple polygon is one that does not intersect itself.
    local n = #polygon
    for i = 1, n do
        local a1 = polygon[i]
        local a2 = polygon[(i % n) + 1]
        for j = i + 2, n do
            if j == (i % n) + 1 then
                break
            end
            local b1 = polygon[j]
            local b2 = polygon[(j % n) + 1]
            if Formex.Math.DoLinesIntersect(a1, a2, b1, b2) then return false end
        end
    end
    return true
end

function Formex.Math.SimplifyPolygon(polygon: {Vector2}): {Vector2}
    -- Remove consecutive duplicates
    -- Remove collinear vertices
    
    return polygon
end

return Formex.Math