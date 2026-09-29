-- Opens every part tagged "MagicDoor" with its ProximityPrompt, closes again after a few seconds.
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Sounds = require(game:GetService("ReplicatedStorage").WizardShared.MogwartsSounds) -- [MogwartsSounds] 

local OPEN_TIME = 6
local info = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function setup(door)
	local prompt = door:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then return end
	local closedCF = door.CFrame
	local hinge = closedCF * CFrame.new(-door.Size.X / 2, 0, 0)
	local openCF = hinge * CFrame.Angles(0, math.rad(-100), 0) * CFrame.new(door.Size.X / 2, 0, 0)
	local isOpen, token = false, 0

	local function close()
		isOpen = false
		prompt.ActionText = "Open"
		Sounds.play("magic_door_close", door) -- [MogwartsSounds] 
		TweenService:Create(door, info, { CFrame = closedCF }):Play()
		task.delay(0.3, function() if not isOpen then door.CanCollide = true end end)
	end

	prompt.Triggered:Connect(function()
		token += 1
		if isOpen then close() return end
		isOpen = true
		prompt.ActionText = "Close"
		Sounds.play("magic_door_open", door) -- [MogwartsSounds] 
		door.CanCollide = false
		TweenService:Create(door, info, { CFrame = openCF }):Play()
		local my = token
		task.delay(OPEN_TIME, function()
			if isOpen and token == my then close() end
		end)
	end)
end

for _, d in ipairs(CollectionService:GetTagged("MagicDoor")) do setup(d) end
CollectionService:GetInstanceAddedSignal("MagicDoor"):Connect(setup)
