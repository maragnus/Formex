--!strict
--[[
FormexDesignObjects
Placeholder for object design interactions (selection/build/paint).
Exports:
- Init(): ()
- HandleUpdate(input): ()
- HandlePrimaryClick(input): ()
- HandlePrimaryRelease(input): ()
- CancelAction(): ()
]]
local Objects = {}

function Objects.Init() end

function Objects.HandleUpdate(_input: any) end

function Objects.HandlePrimaryClick(_input: any) end

function Objects.HandlePrimaryRelease(_input: any) end

function Objects.CancelAction() end

return Objects
