--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FormexFolder = ReplicatedStorage:WaitForChild("Formex")
local Formex = require(FormexFolder:WaitForChild("Formex"))
Formex.Math = require(FormexFolder:WaitForChild("FormexMath"))
Formex.Plot = require(FormexFolder:WaitForChild("FormexPlot"))
Formex.Util = require(FormexFolder:WaitForChild("FormexUtil"))
Formex.Floors = require(FormexFolder:WaitForChild("FormexFloors"))
Formex.Walls = require(FormexFolder:WaitForChild("FormexWalls"))
Formex.Objects = require(FormexFolder:WaitForChild("FormexObjects"))
Formex.Serialization = require(FormexFolder:WaitForChild("FormexSerialization"))
require(FormexFolder:WaitForChild("FormexData"))

return Formex
