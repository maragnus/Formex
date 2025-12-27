local FormexSystem = require(script:WaitForChild("FormexSystem"))

local FormexWorkspace = workspace:WaitForChild("Formex")
local FormexPlots = FormexWorkspace:WaitForChild("Plots")

-- Register all existing plots
for _, plot in ipairs(FormexPlots:GetChildren()) do
	if plot:IsA("Part") then
        FormexSystem.RegisterPlot(plot)
	end
end
