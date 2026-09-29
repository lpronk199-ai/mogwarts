-- Zoned ambient soundscape: village murmur, night forest, echoing castle, underwater.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- volumes follow the Settings panel (player attributes AmbienceVolume / MusicVolume, 0..1)
local function group(name)
	local g = SoundService:FindFirstChild(name)
	if not g then g = Instance.new("SoundGroup") g.Name = name g.Parent = SoundService end
	return g
end
local function applyVolumes()
	group("Ambience").Volume = player:GetAttribute("AmbienceVolume") or 1
	group("Music").Volume = player:GetAttribute("MusicVolume") or 0.6
end
applyVolumes()
player:GetAttributeChangedSignal("AmbienceVolume"):Connect(applyVolumes)
player:GetAttributeChangedSignal("MusicVolume"):Connect(applyVolumes)
local function loop(id, vol)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id s.Looped = true s.Volume = 0 s:SetAttribute("Target", 0) s:SetAttribute("Max", vol)
	s.SoundGroup = group("Ambience")
	s.Parent = SoundService
	s:Play()
	return s
end
local layers = {
	village = loop(9119996136, 0.12),   -- distant chatter
	night = loop(9112764040, 0.32),     -- crickets
	forest = loop(9112832297, 0.18),    -- wind in the trees, faint birds
	castle = loop(9119996106, 0.07),    -- low hall murmur
	under = loop(9112889917, 0.55),     -- underwater
}
-- background music: a calm loop, quieter inside the castle so the halls stay atmospheric
local music = Instance.new("Sound")
music.Name = "Music" music.SoundId = "rbxassetid://91587908006120" music.Looped = true music.Volume = 0.22
music.SoundGroup = group("Music") music.Parent = SoundService
music:Play()
local owl = Instance.new("Sound") owl.SoundId = "rbxassetid://9117181886" owl.Volume = 0.35 owl.SoundGroup = group("Ambience") owl.Parent = SoundService

-- [MogwartsSounds] haunted zones get their own soundscape, and the clock tower rings when night falls
local Sounds = require(game:GetService("ReplicatedStorage"):WaitForChild("WizardShared"):WaitForChild("MogwartsSounds"))
Sounds.preload()
local ZONES = {
	{ name = "deadwood_loop", center = Vector3.new(410, 20, 0), radius = 130, max = 0.5 },   -- Deadwood Hollow
	{ name = "shore_loop", center = Vector3.new(-305, 4, 360), radius = 120, max = 0.45 },   -- Mourning Shore
	{ name = "moonpool_loop", center = Vector3.new(-220, 13, -410), radius = 60, max = 0.4 }, -- The Moonpool
}
for _, z in ipairs(ZONES) do
	z.sound = Sounds.loop(z.name, nil, { group = group("Ambience") })
	if z.sound then z.sound.Volume = 0 end
end
local BELLS = 3 -- strikes when night falls (the villagers swear it was thirteen once)
local wasNight = (workspace:GetAttribute("NightLevel") or 1) > 0.5

local V = Vector3.new(-60, 38, -345)
local function zone(pos)
	local inCastle = math.abs(pos.X) < 205 and pos.Z > -190 and pos.Z < 180 and pos.Y > 55
	local inVillage = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(V.X, 0, V.Z)).Magnitude < 140 and pos.Y > 30
	return inCastle, inVillage
end
local function underwater(pos)
	local r = Region3.new(pos - Vector3.new(2, 2, 2), pos + Vector3.new(2, 2, 2)):ExpandToGrid(4)
	local ok, m = pcall(function() return workspace.Terrain:ReadVoxels(r, 4) end)
	return ok and m[1] and m[1][1] and m[1][1][1] == Enum.Material.Water
end

local nextOwl = os.clock() + 20
local lastReverb
RunService.Heartbeat:Connect(function(dt)
	local c = player.Character
	local root = c and c:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local pos = root.Position
	local inCastle, inVillage = zone(pos)
	local under = underwater(camera.CFrame.Position)
	local night = workspace:GetAttribute("NightLevel") or 1
	local day = 1 - night
	local t = {
		village = (inVillage and not under) and (0.6 + 0.4 * day) or 0,
		night = under and 0 or (inCastle and 0.25 or (inVillage and 0.45 or 1)) * night,
		forest = under and 0 or (inCastle and 0.2 or (inVillage and 0.5 or 1)) * day,
		castle = (inCastle and not under) and 1 or 0,
		under = under and 1 or 0,
	}
	for k, s in pairs(layers) do
		local target = t[k] * s:GetAttribute("Max")
		s.Volume = s.Volume + (target - s.Volume) * math.min(1, dt * 1.5)
	end
	-- [MogwartsSounds] zone loops fade in near their place, the bell rings at dusk
	for _, z in ipairs(ZONES) do
		if z.sound then
			local d = (pos - z.center).Magnitude
			local target = under and 0 or z.max * math.clamp((z.radius - d) / (z.radius * 0.4), 0, 1)
			z.sound.Volume += (target - z.sound.Volume) * math.min(1, dt * 1.5)
		end
	end
	local isNight = night > 0.5
	if isNight ~= wasNight then
		wasNight = isNight
		if isNight then
			task.spawn(function()
				for _ = 1, BELLS do
					Sounds.play("clock_bell", nil, { group = group("Ambience"), volume = inCastle and 0.8 or 0.5 })
					task.wait(2.6)
				end
			end)
		end
	end
	local reverb = under and Enum.ReverbType.UnderWater or (inCastle and Enum.ReverbType.StoneCorridor or Enum.ReverbType.Forest)
	if reverb ~= lastReverb then SoundService.AmbientReverb = reverb lastReverb = reverb end
	if not inCastle and not under and (workspace:GetAttribute("NightLevel") or 1) > 0.6 and os.clock() > nextOwl then
		nextOwl = os.clock() + math.random(25, 55)
		owl.PlaybackSpeed = 0.9 + math.random() * 0.2
		owl.Volume = inVillage and 0.18 or 0.35
		owl:Play()
	end
end)
