--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local formex = ReplicatedStorage:WaitForChild("Formex")
local Formex = require(formex)
require(formex:WaitForChild("Math"))
require(formex:WaitForChild("Data"))
require(formex:WaitForChild("Util"))
require(formex:WaitForChild("Poly"))
require(formex:WaitForChild("Floors"))
require(formex:WaitForChild("Walls"))
require(formex:WaitForChild("Objects"))
require(formex:WaitForChild("Rooms"))
require(formex:WaitForChild("Plot"))
require(formex:WaitForChild("Transaction"))
require(formex:WaitForChild("Serialization"))

return Formex