-- Renders spell visuals locally for every cast in the server (Remotes.SpellFX).
-- The server decides hits and damage; this only draws. Bolts fly smoothly at render rate and stop
-- on walls instantly (local prediction); the server's Impact message then confirms the hit.
-- Also: camera shake for the caster / the player who got hit, and a red edge flash when you're hit.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("WizardShared")
local VFX = require(Shared:WaitForChild("SpellFX"))
local Sounds = require(Shared:WaitForChild("MogwartsSounds")) -- [MogwartsSounds] 
local SpellFX = Shared:WaitForChild("Remotes"):WaitForChild("SpellFX")

local player = Players.LocalPlayer
local bolts = {}

-- ===== camera shake (via Humanoid.CameraOffset, decays quickly) =====
local shake = 0
local function addShake(a) shake = math.min(0.6, shake + a) end

-- ===== red edge flash when you get hit =====
local hurtGui = Instance.new("ScreenGui")
hurtGui.Name = "HurtFlash" hurtGui.IgnoreGuiInset = true hurtGui.ResetOnSpawn = false hurtGui.DisplayOrder = 5
hurtGui.Parent = player:WaitForChild("PlayerGui")
local hurt = Instance.new("Frame")
hurt.Size = UDim2.fromScale(1, 1) hurt.BackgroundTransparency = 1 hurt.BorderSizePixel = 0 hurt.Parent = hurtGui
local edges = {}
for _, r in ipairs({ 0, 90, 180, 270 }) do
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1) f.BackgroundColor3 = Color3.fromRGB(150, 20, 24) f.BackgroundTransparency = 1 f.BorderSizePixel = 0 f.Parent = hurt
	local g = Instance.new("UIGradient") g.Rotation = r
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.18, 1), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = f
	table.insert(edges, f)
end
local function hurtFlash()
	for _, f in ipairs(edges) do
		f.BackgroundTransparency = 0.35
		TweenService:Create(f, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	end
end

local function charOf(userId)
	local pl = userId and Players:GetPlayerByUserId(userId)
	return pl and pl.Character
end

-- ===== soft full-screen flash (Legendary+ impacts near you, Mythic casts) =====
local flashFrame = Instance.new("Frame")
flashFrame.Size = UDim2.fromScale(1, 1) flashFrame.BackgroundTransparency = 1 flashFrame.BorderSizePixel = 0 flashFrame.Parent = hurtGui
local function screenFlash(color, strength)
	if player:GetAttribute("ReducedFX") then strength *= 0.5 end
	flashFrame.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.5)
	flashFrame.BackgroundTransparency = 1 - strength
	TweenService:Create(flashFrame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end
-- how close the local camera is to a point (0 = far, 1 = on top of it)
local function nearness(pos, radius)
	local cam = workspace.CurrentCamera
	if not (cam and pos) then return 0 end
	return math.clamp(1 - (cam.CFrame.Position - pos).Magnitude / radius, 0, 1)
end
local function groundBelow(pos, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ignore, VFX.Folder }
	local hit = workspace:Raycast(pos, Vector3.new(0, -12, 0), params)
	return hit and hit.Position
end
local FROSTY = { Frost = true, Crystal = true }
local Config = require(Shared:WaitForChild("Config"))

-- a glowing orb that rides along with big (charged) bolts / gathers at the wand tip while charging
local function makeOrb(color, size, full)
	local o = Instance.new("Part")
	o.Name = "ChargeOrb" o.Shape = Enum.PartType.Ball o.Anchored = true o.CanCollide = false o.CanQuery = false o.CanTouch = false o.CastShadow = false
	o.Material = Enum.Material.Neon o.Color = full and color:Lerp(Color3.new(1, 1, 1), 0.45) or color o.Size = Vector3.one * size o.Transparency = 0.15
	local l = Instance.new("PointLight") l.Color = color l.Range = 6 + size * 4 l.Brightness = 2 l.Shadows = false l.Parent = o
	o.Parent = VFX.Folder
	return o
end
-- grow/shrink a bolt's particles (charged shot is bigger, barrage smaller)
local function scaleEmitters(inst, k)
	for _, e in ipairs(inst:GetDescendants()) do
		if e:IsA("ParticleEmitter") then
			local kp = {}
			for _, p in ipairs(e.Size.Keypoints) do table.insert(kp, NumberSequenceKeypoint.new(p.Time, p.Value * k, p.Envelope * k)) end
			e.Size = NumberSequence.new(kp)
		elseif e:IsA("Trail") or e:IsA("Beam") then
			if e:IsA("Beam") then e.Width0 *= k e.Width1 *= k end
		end
	end
end

local function finish(b, impactPos, impactNormal, data)
	if b.done then return end
	b.done = true
	if impactPos then
		b.core.CFrame = CFrame.lookAt(impactPos, impactPos + b.dir)
		if b.st.glow then b.st.glow.CFrame = b.core.CFrame end
		VFX.Impact(impactPos, impactNormal or -b.dir, b.color, FROSTY[b.aff] == true, b.aff)
		local tier = VFX.TierOf(b.aff)
		if tier >= 5 then
			local n = nearness(impactPos, 45)
			if n > 0 then screenFlash(b.color, 0.25 * n) end
		end
		if tier >= 6 then addShake(0.4 * nearness(impactPos, 60)) end
		b.impactAt = impactPos
	end
	VFX.EndBolt(b.core, b.st)
	if b.orb then
		local orb = b.orb
		b.orb = nil
		TweenService:Create(orb, TweenInfo.new(0.25), { Size = orb.Size * 2.2, Transparency = 1 }):Play()
		game:GetService("Debris"):AddItem(orb, 0.3)
	end
end

-- ===== server messages =====
SpellFX.OnClientEvent:Connect(function(kind, d)
	if type(d) ~= "table" then return end
	if kind == "Cast" then
		local tier = d.tier or VFX.TierOf(d.aff)
		local c = charOf(d.caster)
		local root = c and c:FindFirstChild("HumanoidRootPart")
		if d.windup and d.windup > 0 then
			-- Mythic: light pours into the tip, then the charge pops as the bolt leaves
			VFX.Windup(d.pos, d.color, d.windup, d.aff)
			task.delay(d.windup, function()
				local w = c and c:FindFirstChild("Wand")
				local tip = w and w:FindFirstChild("Tip")
				local p = tip and tip.Position or d.pos
				VFX.CastCharge(p, d.dir, d.color, d.aff)
				VFX.CastMist(p, d.color, d.aff)
				if d.caster == player.UserId then addShake(0.14) end
				screenFlash(d.color, 0.12 * math.max(nearness(p, 40), d.caster == player.UserId and 1 or 0))
			end)
		else
			VFX.CastCharge(d.pos, d.dir, d.color, d.aff)
			VFX.CastMist(d.pos, d.color, d.aff)
			if d.caster == player.UserId then addShake(0.04 + tier * 0.01) end
		end
		-- Epic+: a rune circle under the caster's feet; Legendary+: a flare of power around them
		if tier >= 4 and root then
			local g = groundBelow(root.Position, c)
			if g then VFX.CastCircle(g, d.color, 1.6 + (tier - 4) * 0.5, 0.8) end
		end
		if tier >= 5 and root then VFX.CasterFlare(root, d.color, tier) end
	elseif kind == "Bolt" then
		local core, st = VFX.Bolt(d.origin, d.dir, d.color, d.aff)
		-- charged shots are bigger (with a riding orb), barrage shots smaller
		local sc = math.clamp(d.scale or 1, 0.4, 3.2)
		if sc ~= 1 then
			scaleEmitters(core, math.clamp(sc, 0.5, 2))
			if st and typeof(st.glow) == "Instance" then st.glow.Size *= sc end
		end
		local orb = sc > 1.2 and makeOrb(d.color, 0.45 * sc, d.full) or nil
		local btier = d.tier or VFX.TierOf(d.aff)
		local reduced = player:GetAttribute("ReducedFX")
		if orb and btier >= 4 then
			-- Epic+: the charged shot leaves a glowing trail
			local a0 = Instance.new("Attachment") a0.Position = Vector3.new(0, orb.Size.Y * 0.35, 0) a0.Parent = orb
			local a1 = Instance.new("Attachment") a1.Position = Vector3.new(0, -orb.Size.Y * 0.35, 0) a1.Parent = orb
			local tr = Instance.new("Trail") tr.Attachment0 = a0 tr.Attachment1 = a1 tr.Lifetime = reduced and 0.15 or 0.3
			tr.Color = ColorSequence.new(d.color:Lerp(Color3.new(1, 1, 1), 0.4), d.color) tr.LightEmission = 0.8
			tr.Transparency = NumberSequence.new(0.2, 1) tr.FaceCamera = true tr.Parent = orb
		end
		if orb and btier >= 6 and not reduced then VFX.Signature(orb, d.aff, 8, 4) end
		-- Epic+ barrage shots get a little muzzle flash each
		if sc < 1 and btier >= 4 and not reduced then VFX.CastCharge(d.origin, d.dir, d.color, d.aff) end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { charOf(d.caster), VFX.Folder, workspace:FindFirstChild("SpellEffects") }
		bolts[d.id] = { core = core, st = st, pos = d.origin, dir = d.dir, speed = d.speed, range = d.range, radius = d.radius or 0.5,
			travelled = 0, color = d.color, aff = d.aff, params = params, born = os.clock(), orb = orb, scale = sc }
	elseif kind == "Impact" then
		local b = bolts[d.id]
		if b and b.impactAt and (b.impactAt - d.pos).Magnitude < 6 then
			-- we already drew this impact locally
		elseif b then
			b.done = false
			finish(b, d.pos, d.normal, d)
		else
			VFX.Impact(d.pos, d.normal, d.color, d.frost, d.aff)
		end
		if (d.scale or 1) > 1.5 and not player:GetAttribute("ReducedFX") then
			VFX.Impact(d.pos + d.normal * 0.5, d.normal, d.color:Lerp(Color3.new(1, 1, 1), 0.3), d.frost, d.aff)
			local itier = d.tier or VFX.TierOf(d.aff)
			VFX.CastCircle(d.pos, d.color, (1 + d.scale * 0.8) * (itier >= 5 and 1.6 or 1), itier >= 5 and 0.8 or 0.5)
			addShake(0.25 * nearness(d.pos, 50))
			-- Mythic full charge: a pillar of light where it lands
			if itier >= 6 and d.scale >= 2.9 then VFX.Pillar(d.pos, d.color, 45, 0.9) end
		end
		bolts[d.id] = nil
		if d.target then
			VFX.HitFlash(d.target, d.color)
			if d.target == player.Character then addShake(0.35) hurtFlash() end
		end
		for _, m in ipairs(d.splash or {}) do
			VFX.HitFlash(m, d.color)
			if m == player.Character then addShake(0.2) hurtFlash() end
		end
	elseif kind == "BoltEnd" then
		local b = bolts[d.id]
		if b then finish(b) end
		bolts[d.id] = nil
	elseif kind == "Blast" then
		VFX.Blast(d.center, d.groundY, d.color, d.range, d.aff)
		for _, m in ipairs(d.hits or {}) do
			VFX.HitFlash(m, d.color)
			if m == player.Character then addShake(0.45) hurtFlash() end
		end
		if d.caster == player.UserId then addShake(0.22) end
		local tier = d.tier or VFX.TierOf(d.aff)
		if tier >= 6 then
			local n = nearness(d.center, 70)
			addShake(0.45 * n)
			screenFlash(d.color, 0.3 * n)
		elseif tier >= 5 then
			screenFlash(d.color, 0.18 * nearness(d.center, 45))
		end
	elseif kind == "ShieldHit" then
		VFX.ShieldHit(d.pos, d.color, d.tier)
	elseif kind == "Draw" then
		VFX.DrawFX(d.pos, d.color, d.tier or 1, d.holster, d.ground)
	end
end)

-- ===== bolts fly at render rate =====
RunService.RenderStepped:Connect(function(dt)
	for id, b in pairs(bolts) do
		if b.done then
			-- keep the record a moment so the server's Impact can be matched, then drop it
			if os.clock() - b.born > 4 then bolts[id] = nil end
		else
			local step = b.dir * b.speed * dt
			local hit = workspace:Spherecast(b.pos, b.radius, step, b.params)
			if hit then
				finish(b, hit.Position, hit.Normal)
			else
				b.pos += step
				b.travelled += step.Magnitude
				VFX.MoveBolt(b.core, b.st, CFrame.lookAt(b.pos, b.pos + b.dir), dt)
				if b.orb then b.orb.CFrame = CFrame.new(b.pos) end
				if b.travelled > b.range then finish(b) end
			end
		end
	end
	-- camera shake
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if h then
		if shake > 0.002 then
			local t = os.clock() * 38
			h.CameraOffset = Vector3.new(math.noise(t, 1.3) , math.noise(t, 7.1), math.noise(t, 3.7) * 0.5) * shake * 1.6
			shake *= math.exp(-dt * 9)
		elseif shake > 0 then
			shake = 0
			h.CameraOffset = Vector3.zero
		end
	end
end)

-- ===== charged shot: an orb gathers at the wand tip of anyone charging (player attribute ChargeStart, server time) =====
-- Rarer houses get fancier charges (Config.AffinityTierBonus[tier].ChargeFX):
--   3+ orbiting sparks and a turning ring at the tip, 4+ a rune circle under the feet that fills up,
--   5+ energy drawn in from all around, 6 the house's signature swirl and an edge glow for the caster at full charge.
local charging = {}
local HUM_ID = "rbxassetid://9114159710"
local function affColor(pl)
	local ok, a = pcall(Config.Find, "Affinities", pl:GetAttribute("Affinity") or "")
	return ok and a and a.Color or Color3.fromRGB(150, 190, 255)
end
local function neon(shape, size, color, tr)
	local p = Instance.new("Part")
	p.Shape = shape p.Anchored = true p.CanCollide = false p.CanQuery = false p.CanTouch = false p.CastShadow = false
	p.Material = Enum.Material.Neon p.Color = color p.Size = size p.Transparency = tr or 0.1
	p.Parent = VFX.Folder
	return p
end
-- screen-edge glow for the caster (Mythic full charge)
local edgeGlow = {}
for _, r in ipairs({ 0, 90, 180, 270 }) do
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1) f.BackgroundTransparency = 1 f.BorderSizePixel = 0 f.Parent = hurt
	local g = Instance.new("UIGradient") g.Rotation = r
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(0.14, 1), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = f
	table.insert(edgeGlow, f)
end
local function edgeFlash(color)
	if player:GetAttribute("ReducedFX") then return end
	for _, f in ipairs(edgeGlow) do
		f.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.2)
		f.BackgroundTransparency = 0.25
		TweenService:Create(f, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	end
end
local function dropCharge(e)
	if e.snd then e.snd:Stop() end
	for _, p in ipairs(e.extra) do
		TweenService:Create(p, TweenInfo.new(0.15), { Transparency = 1 }):Play()
		game:GetService("Debris"):AddItem(p, 0.2)
	end
	TweenService:Create(e.orb, TweenInfo.new(0.15), { Size = Vector3.one * 0.05, Transparency = 1 }):Play()
	game:GetService("Debris"):AddItem(e.orb, 0.2)
end
RunService.RenderStepped:Connect(function()
	local cfg = Config.Spells.Charge
	local reduced = player:GetAttribute("ReducedFX")
	for _, pl in ipairs(Players:GetPlayers()) do
		local t0 = pl:GetAttribute("ChargeStart")
		local e = charging[pl]
		local c = pl.Character
		local w = c and c:FindFirstChild("Wand")
		local tip = w and w:FindFirstChild("Tip")
		local root = c and c:FindFirstChild("HumanoidRootPart")
		if t0 and tip and root then
			local col = affColor(pl)
			if not e then
				local fx = (Config.TierBonus(pl:GetAttribute("Affinity")).ChargeFX or 1)
				e = { orb = makeOrb(col, 0.3, false), full = false, fx = fx, extra = {}, sparks = {}, born = os.clock() }
				local snd = Sounds.loop("charge_loop", e.orb) -- [MogwartsSounds] deep charging hum
				if not snd then
					snd = Instance.new("Sound") snd.SoundId = HUM_ID snd.Looped = true snd.Volume = 0.2 snd.RollOffMaxDistance = 60 snd.Parent = e.orb
					snd:Play()
				end
				e.snd = snd
				if fx >= 3 then
					for i = 1, (reduced and 2 or 3) do
						local sp = neon(Enum.PartType.Ball, Vector3.one * 0.14, col:Lerp(Color3.new(1, 1, 1), 0.5), 0)
						table.insert(e.sparks, sp) table.insert(e.extra, sp)
					end
					e.ring = neon(Enum.PartType.Cylinder, Vector3.new(0.04, 1, 1), col:Lerp(Color3.new(1, 1, 1), 0.3), 0.35)
					table.insert(e.extra, e.ring)
				end
				if fx >= 4 then
					-- rune circle on the ground that fills up while you charge
					local params = RaycastParams.new() params.FilterType = Enum.RaycastFilterType.Exclude params.FilterDescendantsInstances = { c, VFX.Folder }
					local hit = workspace:Raycast(root.Position, Vector3.new(0, -8, 0), params)
					e.groundY = hit and hit.Position.Y or root.Position.Y - 3
					e.circle = neon(Enum.PartType.Cylinder, Vector3.new(0.04, 6, 6), col, 0.62)
					e.fill = neon(Enum.PartType.Cylinder, Vector3.new(0.05, 0.2, 0.2), col:Lerp(Color3.new(1, 1, 1), 0.2), 0.74)
					table.insert(e.extra, e.circle) table.insert(e.extra, e.fill)
				end
				if fx >= 5 and not reduced then
					-- energy drawn in: a big invisible shell whose particles fly inward to the orb
					local shell = Instance.new("Part")
					shell.Shape = Enum.PartType.Ball shell.Anchored = true shell.CanCollide = false shell.CanQuery = false shell.CanTouch = false
					shell.Transparency = 1 shell.Size = Vector3.one * 9 shell.Parent = VFX.Folder
					local pe = Instance.new("ParticleEmitter")
					pe.Shape = Enum.ParticleEmitterShape.Sphere pe.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
					pe.Texture = "rbxassetid://7587238412" pe.Orientation = Enum.ParticleOrientation.VelocityParallel
					pe.Color = ColorSequence.new(col:Lerp(Color3.new(1, 1, 1), 0.4), col) pe.LightEmission = 1 pe.LightInfluence = 0
					pe.Size = NumberSequence.new(0.25, 0.05) pe.Transparency = NumberSequence.new(0.2, 1)
					pe.Speed = NumberRange.new(9, 11) pe.Lifetime = NumberRange.new(0.38, 0.42) pe.Rate = 45
					pe.Parent = shell
					e.shell = shell table.insert(e.extra, shell)
				end
				charging[pl] = e
			end
			local held = workspace:GetServerTimeNow() - t0
			local frac = math.clamp(held / cfg.MaxCharge, 0, 1)
			local now = os.clock()
			local pulse = 1 + 0.08 * math.sin(now * (10 + frac * 14))
			local size = (0.3 + 1.3 * frac) * pulse
			e.orb.Size = Vector3.one * size
			e.orb.CFrame = tip.CFrame
			e.orb.Color = e.full and col:Lerp(Color3.new(1, 1, 1), 0.25) or col
			e.orb.Transparency = e.full and 0.25 or 0.15
			e.snd.PlaybackSpeed = 0.55 + frac * 0.9
			local l = e.orb:FindFirstChildOfClass("PointLight")
			if l then l.Range = 4 + frac * 10 l.Brightness = 1 + frac * 2 end
			-- orbiting sparks + a turning ring around the tip
			for i, sp in ipairs(e.sparks) do
				local a = now * (5 + frac * 6) + i * (math.pi * 2 / #e.sparks)
				local r = size * 0.5 + 0.35
				sp.CFrame = tip.CFrame * CFrame.new(math.cos(a) * r, math.sin(a * 1.3) * r * 0.5, math.sin(a) * r)
			end
			if e.ring then
				local rs = size + 0.5
				e.ring.Size = Vector3.new(0.04, rs, rs)
				e.ring.CFrame = tip.CFrame * CFrame.Angles(now * 2, now * 3, 0) * CFrame.Angles(0, 0, math.rad(90))
			end
			if e.circle then
				local g = Vector3.new(root.Position.X, e.groundY + 0.06, root.Position.Z)
				e.circle.CFrame = CFrame.new(g) * CFrame.Angles(0, now * 0.8, math.rad(90))
				local fr = 0.2 + 5.6 * frac
				e.fill.Size = Vector3.new(0.05, fr, fr)
				e.fill.CFrame = CFrame.new(g + Vector3.new(0, 0.01, 0)) * CFrame.Angles(0, 0, math.rad(90))
			end
			if e.shell then
				e.shell.CFrame = tip.CFrame
				local pe = e.shell:FindFirstChildOfClass("ParticleEmitter")
				if pe then pe.Rate = 25 + 60 * frac end
			end
			if e.fx >= 6 and not reduced and now - (e.sig or 0) > 0.25 then
				e.sig = now
				VFX.Signature(e.orb, pl:GetAttribute("Affinity"), 2 + math.floor(frac * 4), 3)
			end
			if e.snd then e.snd.PlaybackSpeed = 0.85 + 0.35 * math.clamp(frac, 0, 1) end -- [MogwartsSounds] the hum rises while charging
			if not e.full and frac >= cfg.FullAt then
				-- full charge: a white flash and a little pop
				e.full = true
				Sounds.play("charge_full", tip) -- [MogwartsSounds] 
				VFX.CastCharge(tip.Position, tip.CFrame.LookVector, Color3.new(1, 1, 1), pl:GetAttribute("Affinity"))
				if pl == player then
					addShake(0.08) screenFlash(col, 0.12)
					if e.fx >= 6 then edgeFlash(col) end
				end
			end
		elseif e then
			charging[pl] = nil
			dropCharge(e)
		end
	end
end)
Players.PlayerRemoving:Connect(function(pl) local e = charging[pl] if e then dropCharge(e) charging[pl] = nil end end)
