-- Wand combat: damage, cooldowns, mana, dash validation, spell VFX, cast/dash poses and SFX.
-- Everything that matters is decided here on the server.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Config = require(RS.WizardShared.Config)
local Remotes = RS.WizardShared.Remotes
-- shared spell visuals: bolts/impacts/blasts/cast flashes are rendered on every client via Remotes.SpellFX
-- (smooth + per-client quality); the shield bubble is still built here on the server.
local VFX = require(RS.WizardShared.SpellFX)
local Sounds = require(RS.WizardShared.MogwartsSounds) -- [MogwartsSounds] the new sound pack
local SpellFX = Remotes:WaitForChild("SpellFX")
local boltId = 0

local fxFolder = workspace:FindFirstChild("SpellEffects") or Instance.new("Folder")
fxFolder.Name = "SpellEffects" fxFolder.Parent = workspace

local state = {}
local function getState(player)
	local s = state[player]
	if not s then s = { cd = {}, shieldUntil = 0, calls = 0, window = os.clock() } state[player] = s end
	return s
end
local function affinityOf(player) return Config.Find("Affinities", player:GetAttribute("Affinity") or "Ember") end
local function aliveChar(player)
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local r = c and c:FindFirstChild("HumanoidRootPart")
	if h and r and h.Health > 0 then return c, h, r end
end
local function rateOk(s)
	local now = os.clock()
	if now - s.window > 1 then s.window = now s.calls = 0 end
	s.calls += 1
	return s.calls <= 14
end

-- ================= SOUND =================
local SFX = {
	Cast = { id = 9114159112, vol = 0.28, pitch = 1.45 },
	Impact = { id = 9116279560, vol = 0.3, pitch = 1.1 },
	Blast = { id = 9119388384, vol = 0.38, pitch = 1.15 },
	BlastWhoosh = { id = 9114157694, vol = 0.22, pitch = 0.8 },
	Shield = { id = 9114159710, vol = 0.26, pitch = 0.6 },
	Dash = { id = 9113942270, vol = 0.3, pitch = 1 },
	MythicCast = { id = 9125484367, vol = 0.32, pitch = 1.35 },
	MythicWhoosh = { id = 9114159710, vol = 0.28, pitch = 0.7 },
	Draw = { id = 9114157694, vol = 0.16, pitch = 1.8 },
	Holster = { id = 9113942270, vol = 0.18, pitch = 1.3 },
}
local function oldSound(parent, key)
	local def = SFX[key]
	if not def or not parent then return end
	if typeof(parent) == "Vector3" then
		-- play at a point in the world (bolts no longer have a server-side part)
		local p = Instance.new("Part")
		p.Anchored = true p.CanCollide = false p.CanQuery = false p.CanTouch = false p.Transparency = 1 p.Size = Vector3.one * 0.2
		p.CFrame = CFrame.new(parent) p.Parent = fxFolder
		Debris:AddItem(p, 4)
		parent = p
	end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. def.id
	s.Volume = def.vol
	s.PlaybackSpeed = def.pitch * (0.9 + math.random() * 0.2)
	s.RollOffMinDistance = 8 s.RollOffMaxDistance = 80
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 4)
end
-- [MogwartsSounds] play from the sound pack; the old library sounds above stay as a fallback until the pack is uploaded
local PACK = { Cast = "cast", Impact = "impact", Blast = "blast", BlastWhoosh = "blast_whoosh", Shield = "shield_up",
	Dash = "dash", MythicCast = "mythic_cast", MythicWhoosh = "blast_whoosh", Draw = "duel_draw", Holster = "duel_holster" }
local function sound(parent, key)
	if not parent then return end
	if Sounds.play(PACK[key] or key, parent) then return end
	oldSound(parent, key)
end

-- ================= VFX HELPERS =================
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local function fx(size, cf, color, shape, transp)
	local p = Instance.new("Part")
	p.Anchored = true p.CanCollide = false p.CanQuery = false p.CanTouch = false p.CastShadow = false
	p.Size = size p.CFrame = cf p.Color = color p.Material = Enum.Material.Neon
	p.Shape = shape or Enum.PartType.Ball p.Transparency = transp or 0
	p.Parent = fxFolder
	return p
end
local function tween(inst, t, props, style)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
local function burst(pos, color, count, speed, size)
	local host = fx(Vector3.one * 0.2, CFrame.new(pos), color, nil, 1)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = SPARK pe.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.35), color)
	pe.LightEmission = 1 pe.Size = NumberSequence.new(size or 0.35, 0)
	pe.Lifetime = NumberRange.new(0.25, 0.45) pe.Speed = NumberRange.new(speed * 0.6, speed)
	pe.Drag = 6 pe.SpreadAngle = Vector2.new(180, 180) pe.Rate = 0
	pe.Parent = host
	pe:Emit(count)
	Debris:AddItem(host, 1)
end
local function flash(pos, color, size, range)
	local f = fx(Vector3.one * size, CFrame.new(pos), color:Lerp(Color3.new(1, 1, 1), 0.3), nil, 0.25)
	local l = Instance.new("PointLight") l.Color = color l.Range = range or 12 l.Brightness = 2.5 l.Parent = f
	tween(f, 0.14, { Size = Vector3.one * size * 2.6, Transparency = 1 })
	tween(l, 0.2, { Brightness = 0 })
	Debris:AddItem(f, 0.25)
end
local function ring(cf, color, fromD, toD, t, thick)
	local r = fx(Vector3.new(thick or 0.08, fromD, fromD), cf, color, Enum.PartType.Cylinder, 0.3)
	tween(r, t, { Size = Vector3.new(thick or 0.08, toD, toD), Transparency = 1 })
	Debris:AddItem(r, t + 0.05)
	return r
end

-- ================= POSES (server-side joint offsets, visible to everyone) =================
local POSES = {
	DashForward = { Root = CFrame.Angles(math.rad(-22), 0, 0), RightShoulder = CFrame.Angles(math.rad(-30), 0, 0), LeftShoulder = CFrame.Angles(math.rad(-35), 0, 0) },
	DashBack = { Root = CFrame.Angles(math.rad(16), 0, 0), RightShoulder = CFrame.Angles(math.rad(20), 0, 0), LeftShoulder = CFrame.Angles(math.rad(40), 0, 0) },
	DashLeft = { Root = CFrame.Angles(0, 0, math.rad(18)), LeftShoulder = CFrame.Angles(0, 0, math.rad(-25)) },
	DashRight = { Root = CFrame.Angles(0, 0, math.rad(-18)), RightShoulder = CFrame.Angles(0, 0, math.rad(25)) },
	-- casts: anticipation -> action -> recovery (each spell plays a wind-up pose, then its action pose)
	BoltWind = { RightShoulder = CFrame.Angles(math.rad(-18), 0, math.rad(12)), Waist = CFrame.Angles(0, math.rad(14), 0) },
	CastBolt = { RightShoulder = CFrame.Angles(math.rad(82), 0, math.rad(-4)), Waist = CFrame.Angles(0, math.rad(-16), 0) },
	BlastWind = { RightShoulder = CFrame.Angles(math.rad(-30), 0, math.rad(35)), LeftShoulder = CFrame.Angles(math.rad(-30), 0, math.rad(-35)), Root = CFrame.new(0, -0.35, 0) * CFrame.Angles(math.rad(10), 0, 0) },
	CastBlast = { RightShoulder = CFrame.Angles(math.rad(95), 0, math.rad(-25)), LeftShoulder = CFrame.Angles(math.rad(95), 0, math.rad(25)), Waist = CFrame.Angles(math.rad(-8), 0, 0), Root = CFrame.new(0, -0.15, 0) },
	CastShield = { RightShoulder = CFrame.Angles(math.rad(150), 0, math.rad(-8)), LeftShoulder = CFrame.Angles(math.rad(75), 0, math.rad(18)), Waist = CFrame.Angles(math.rad(6), 0, 0) },
	ChargeHold = { RightShoulder = CFrame.Angles(math.rad(-35), 0, math.rad(28)), LeftShoulder = CFrame.Angles(math.rad(80), 0, math.rad(14)), Waist = CFrame.Angles(0, math.rad(28), 0), Root = CFrame.new(0, -0.2, 0) },
	ChargeRelease = { RightShoulder = CFrame.Angles(math.rad(95), 0, 0), LeftShoulder = CFrame.Angles(math.rad(-25), 0, math.rad(-12)), Waist = CFrame.Angles(0, math.rad(-26), 0), Root = CFrame.Angles(math.rad(-10), 0, 0) },
	BarrageA = { RightShoulder = CFrame.Angles(math.rad(80), 0, math.rad(-16)), Waist = CFrame.Angles(0, math.rad(-16), 0) },
	BarrageB = { RightShoulder = CFrame.Angles(math.rad(78), 0, math.rad(12)), Waist = CFrame.Angles(0, math.rad(-4), 0) },
	Idle = { RightShoulder = CFrame.new(), LeftShoulder = CFrame.new(), Waist = CFrame.new(), Root = CFrame.new() },
	Draw = { RightShoulder = CFrame.Angles(math.rad(60), 0, math.rad(-10)), Waist = CFrame.Angles(0, math.rad(-10), 0) },
	Holster = { RightShoulder = CFrame.Angles(math.rad(-25), 0, math.rad(8)), Waist = CFrame.Angles(0, math.rad(8), 0) },
}
-- combat stances (Config.Stances, cosmetic): each adds its own Draw_<name> and CastBolt_<name> pose
do
	local JOINT = { R = "RightShoulder", L = "LeftShoulder", W = "Waist", Root = "Root" }
	local function build(def)
		local out = {}
		for k, a in pairs(def or {}) do
			local j = JOINT[k]
			if j then out[j] = CFrame.Angles(math.rad(a[1]), math.rad(a[2]), math.rad(a[3])) end
		end
		return out
	end
	for _, st in ipairs(Config.Stances or {}) do
		POSES["Draw_" .. st.Name] = build(st.Draw)
		-- the stance flavours the cast; the arm is raised further so the wand points at the target
		local cast = table.clone(st.Cast or {})
		if cast.R then cast.R = { math.min(150, cast.R[1] + 40), cast.R[2], cast.R[3] } end
		POSES["CastBolt_" .. st.Name] = build(cast)
	end
	-- a mirrored variant of every bolt cast so quick casts alternate instead of looking robotic
	local extra = {}
	for k, def in pairs(POSES) do
		if k:sub(1, 8) == "CastBolt" then
			local alt = table.clone(def)
			if alt.RightShoulder then alt.RightShoulder = alt.RightShoulder * CFrame.Angles(math.rad(-6), 0, math.rad(10)) end
			alt.Waist = (alt.Waist or CFrame.new()) * CFrame.Angles(0, math.rad(6), 0)
			extra[k .. "~"] = alt
		end
	end
	for k, v in pairs(extra) do POSES[k] = v end
end
local function stancePose(char, base)
	local pl = game:GetService("Players"):GetPlayerFromCharacter(char)
	local st = pl and pl:GetAttribute("Stance")
	local key = st and (base .. "_" .. st)
	if key and POSES[key] then return key end
	return base
end
local motorPaths = { Root = "LowerTorso", Waist = "UpperTorso", RightShoulder = "RightUpperArm", LeftShoulder = "LeftUpperArm" }
local function pose(char, name, inT, hold, outT)
	local def = POSES[name]
	if not def then return end
	for motorName, offset in pairs(def) do
		local part = char:FindFirstChild(motorPaths[motorName])
		local m = part and part:FindFirstChild(motorName)
		-- Motor6D: offset C0. Upgraded avatar joints (AnimationConstraint): offset its Attachment0 instead
		local obj, prop = nil, nil
		if m and m:IsA("Motor6D") then obj, prop = m, "C0"
		elseif m and m:IsA("AnimationConstraint") and m.Attachment0 then obj, prop = m.Attachment0, "CFrame" end
		if obj then
			local token = (m:GetAttribute("PoseToken") or 0) + 1
			if not m:GetAttribute("Posing") then m:SetAttribute("OrigC0", obj[prop]) end
			m:SetAttribute("Posing", true)
			m:SetAttribute("PoseToken", token)
			local orig = m:GetAttribute("OrigC0")
			TweenService:Create(obj, TweenInfo.new(inT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { [prop] = orig * offset }):Play()
			task.delay(inT + hold, function()
				if m.Parent and m:GetAttribute("PoseToken") == token then
					local tw = TweenService:Create(obj, TweenInfo.new(outT, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { [prop] = orig })
					tw:Play()
					tw.Completed:Connect(function()
						if m:GetAttribute("PoseToken") == token then m:SetAttribute("Posing", nil) end
					end)
				end
			end)
		end
	end
end

-- ================= DAMAGE =================
local function damageNumber(pos, text, color)
	local a = Instance.new("Part")
	a.Anchored = true a.CanCollide = false a.CanQuery = false a.Transparency = 1 a.Size = Vector3.one * 0.2
	a.CFrame = CFrame.new(pos + Vector3.new(math.random(-10, 10) / 10, 1.5, math.random(-10, 10) / 10))
	a.Parent = fxFolder
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(90, 36) bb.AlwaysOnTop = true bb.LightInfluence = 0 bb.Parent = a
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1) t.BackgroundTransparency = 1 t.Text = text
	t.FontFace = Font.new("rbxasset://fonts/families/AccanthisADFStd.json", Enum.FontWeight.Bold)
	t.TextScaled = true t.TextColor3 = color t.TextStrokeTransparency = 0.2 t.Parent = bb
	TweenService:Create(a, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = a.CFrame + Vector3.new(0, 3.5, 0) }):Play()
	TweenService:Create(t, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(a, 1)
end
local function targetInfo(inst)
	local model = inst:FindFirstAncestorOfClass("Model")
	while model do
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum then return model, hum end
		model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model")
	end
end
local function markCombat(pl) if pl and state[pl] then state[pl].lastCombat = os.clock() end end
local function applyDamage(attacker, model, hum, amount, pos, aff)
	if hum.Health <= 0 or hum:GetAttribute("NPC") then return end
	local victim = Players:GetPlayerFromCharacter(model)
	markCombat(attacker) if victim then getState(victim) markCombat(victim) end
	if victim and state[victim] and os.clock() < state[victim].shieldUntil then
		damageNumber(pos, "Blocked", Color3.fromRGB(200, 220, 255))
		Sounds.play("shield_block", pos) -- [MogwartsSounds] 
		local vaff = affinityOf(victim)
		SpellFX:FireAllClients("ShieldHit", { pos = pos, color = vaff.Color, tier = VFX.TierOf(vaff.Name) })
		return
	end
	if model:FindFirstChildOfClass("ForceField") then return end
	amount = math.floor(amount + 0.5)
	local isDummy = CollectionService:HasTag(model, "TrainingDummy")
	if isDummy and hum.Health - amount <= 0 then
		damageNumber(pos, "KO!", Color3.fromRGB(255, 220, 90))
		Sounds.play("knockout", pos) -- [MogwartsSounds] 
		hum.Health = hum.MaxHealth
	else
		if victim then
			local tag = hum:FindFirstChild("creator") or Instance.new("ObjectValue")
			tag.Name = "creator" tag.Value = attacker tag.Parent = hum
		end
		hum:TakeDamage(amount)
	end
	local vs = victim and state[victim]
	if vs and vs.chargeStart then vs.chargeStart += (os.clock() - vs.chargeStart) * (Config.Spells.Charge.HitLoss or 0.3) end
	damageNumber(pos, tostring(amount), aff.Color)
	if aff.Lifesteal then
		local _, ah, ar = aliveChar(attacker)
		if ah then ah.Health = math.min(ah.MaxHealth, ah.Health + amount * aff.Lifesteal) end
		if ar then Sounds.play("lifesteal", ar, { volume = 0.6 }) end -- [MogwartsSounds] 
	end
	if aff.Burn then
		task.spawn(function()
			for i = 1, 3 do
				task.wait(1)
				if hum.Health <= 0 then break end
				local head = model:FindFirstChild("Head")
				if isDummy then
					if hum.Health - aff.Burn > 0 then hum.Health -= aff.Burn end
				else hum:TakeDamage(aff.Burn) end
				if head then damageNumber(head.Position, tostring(aff.Burn), Color3.fromRGB(255, 150, 60)) end
				if head then Sounds.play("burn_tick", head) end -- [MogwartsSounds] 
			end
		end)
	end
	if aff.Slow and not isDummy then
		-- the client applies the slow to its own walk/sprint speed
		hum:SetAttribute("SlowMult", 0.55)
		Sounds.play("frost_slow", pos) -- [MogwartsSounds] 
		hum:SetAttribute("SlowUntil", workspace:GetServerTimeNow() + aff.Slow)
	end
end

-- ================= SPELLS =================
local function wandTip(char, root)
	local wand = char:FindFirstChild("Wand")
	local tip = wand and wand:FindFirstChild("Tip")
	return tip and tip.Position or (root.Position + root.CFrame.LookVector * 2 + Vector3.new(0, 1.5, 0))
end

-- one bolt, any size: Bolt, the charged shot and each barrage shot all fly through here.
-- o = { damage, speed, range, radius, scale, knockback, explode = {radius, mult}, perkMult, windup, castFX }
local function weakAff(aff, mult)
	if not mult or mult >= 1 then return aff end
	local a = table.clone(aff)
	if a.Burn then a.Burn = math.max(1, math.floor(a.Burn * mult + 0.5)) end
	if a.Lifesteal then a.Lifesteal *= mult end
	if a.Splash then a.Splash *= mult end
	if a.Slow then a.Slow *= mult end
	return a
end
local function fireBolt(player, char, root, target, aff, o)
	local origin = wandTip(char, root)
	local dir = target - origin
	if dir.Magnitude < 0.1 then dir = root.CFrame.LookVector end
	dir = dir.Unit
	local speed = o.speed * (aff.BoltSpeed or 1)
	local tier = VFX.TierOf(aff.Name)
	local paff = weakAff(aff, o.perkMult)
	boltId += 1
	local id = boltId
	if o.castFX ~= false then
		SpellFX:FireAllClients("Cast", { pos = origin, dir = dir, color = aff.Color, aff = aff.Name, caster = player.UserId, tier = tier, windup = o.windup or 0 })
	end
	if o.windup and o.windup > 0 then
		task.wait(o.windup)
		if not (char.Parent and root.Parent) then return end
		origin = wandTip(char, root)
		dir = target - origin
		if dir.Magnitude < 0.1 then dir = root.CFrame.LookVector end
		dir = dir.Unit
	end
	SpellFX:FireAllClients("Bolt", { id = id, origin = origin, dir = dir, speed = speed, range = o.range, radius = o.radius * 0.5,
		color = aff.Color, aff = aff.Name, caster = player.UserId, tier = tier, scale = o.scale, full = o.explode ~= nil })

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char, fxFolder }
	local pos, travelled = origin, 0
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		local step = dir * speed * dt
		local hit = workspace:Spherecast(pos, o.radius * 0.5, step, params)
		if hit then
			conn:Disconnect()
			local p = hit.Position
			local model, hum = targetInfo(hit.Instance)
			local splash = {}
			if paff.Splash then
				local op = OverlapParams.new()
				op.FilterType = Enum.RaycastFilterType.Exclude
				op.FilterDescendantsInstances = { char, fxFolder }
				local seen = { [model or false] = true }
				for _, part in ipairs(workspace:GetPartBoundsInRadius(p, paff.Splash, op)) do
					local m2, h2 = targetInfo(part)
					if h2 and not seen[m2] then seen[m2] = true table.insert(splash, { m = m2, h = h2 }) end
				end
			end
			local splashModels = {}
			for _, sp in ipairs(splash) do table.insert(splashModels, sp.m) end
			SpellFX:FireAllClients("Impact", { id = id, pos = p, normal = hit.Normal, color = aff.Color, aff = aff.Name, tier = tier,
				frost = aff.Name == "Frost" or aff.Name == "Crystal", target = hum and model or nil, splash = splashModels, scale = o.scale })
			sound(p, "Impact")
			if #splashModels > 0 then Sounds.play("crystal_shatter", p) end -- [MogwartsSounds] 
			if hum then
				applyDamage(player, model, hum, o.damage * aff.Damage, p, paff)
				local victim = Players:GetPlayerFromCharacter(model)
				if o.knockback and o.knockback > 1 and victim and not (state[victim] and os.clock() < state[victim].shieldUntil) then
					Remotes.Knockback:FireClient(victim, dir * Vector3.new(1, 0, 1) * o.knockback + Vector3.new(0, 22, 0))
				end
			end
			for _, sp in ipairs(splash) do
				local tr = sp.m:FindFirstChild("HumanoidRootPart")
				applyDamage(player, sp.m, sp.h, o.damage * aff.Damage * (aff.SplashMult or 0.5), tr and tr.Position or p, paff)
			end
			if o.explode then
				local op = OverlapParams.new()
				op.FilterType = Enum.RaycastFilterType.Exclude
				op.FilterDescendantsInstances = { char, fxFolder }
				local seen, hits = { [model or false] = true }, {}
				for _, part in ipairs(workspace:GetPartBoundsInRadius(p, o.explode.radius, op)) do
					local m2, h2 = targetInfo(part)
					if h2 and not seen[m2] then
						seen[m2] = true
						table.insert(hits, m2)
						local tr = m2:FindFirstChild("HumanoidRootPart")
						applyDamage(player, m2, h2, o.damage * aff.Damage * o.explode.mult, tr and tr.Position or p, paff)
					end
				end
				SpellFX:FireAllClients("Blast", { center = p, groundY = p.Y, color = aff.Color, range = o.explode.radius, aff = aff.Name,
					caster = player.UserId, hits = hits, tier = tier })
				sound(p, "Blast")
			end
			return
		end
		pos += step
		travelled += step.Magnitude
		if travelled > o.range then
			conn:Disconnect()
			SpellFX:FireAllClients("BoltEnd", { id = id })
		end
	end)
end

-- Bolt: a quick pull-back, then the wand snaps forward at the target (alternating a little each cast)
local function castBolt(player, char, root, target, aff)
	local cfg = Config.Spells.Bolt
	local s = getState(player)
	s.alt = not s.alt
	local tier = VFX.TierOf(aff.Name)
	local windup = tier >= 6 and (Config.MythicWindup or 0) or 0
	pose(char, "BoltWind", 0.05, 0.02 + windup, 0.05)
	task.delay(0.06 + windup * 0.6, function()
		if char.Parent then pose(char, stancePose(char, "CastBolt") .. (s.alt and "" or "~"), 0.05, 0.08, 0.22) end
	end)
	sound(root, "Cast")
	Sounds.affinity(aff.Name, root) -- [MogwartsSounds] fire, ice, storm, dark... layer
	if tier >= 6 then sound(root, "MythicCast") sound(root, "MythicWhoosh") end
	fireBolt(player, char, root, target, aff, { damage = cfg.Damage, speed = cfg.Speed, range = cfg.Range, radius = cfg.Radius, windup = windup })
end

-- ===== charged shot =====
local function chargeCancel(player, s, silent)
	if not s.chargeStart then return end
	s.chargeStart = nil
	player:SetAttribute("ChargeStart", nil)
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if h then h:SetAttribute("SlowUntil", 0) end
	if c and not silent then pose(c, "Idle", 0.12, 0, 0.15) end
end
local function chargeStart(player, s, char, hum)
	local cfg = Config.Spells.Charge
	s.chargeStart = os.clock()
	player:SetAttribute("ChargeStart", workspace:GetServerTimeNow())
	hum:SetAttribute("SlowMult", cfg.SlowMult)
	hum:SetAttribute("SlowUntil", workspace:GetServerTimeNow() + cfg.MaxCharge + 6)
	pose(char, "ChargeHold", 0.18, cfg.MaxCharge + 6, 0.2)
end
local function chargeRelease(player, s, char, root, target, aff)
	local cfg = Config.Spells.Charge
	local held = math.min(os.clock() - s.chargeStart, cfg.MaxCharge)
	chargeCancel(player, s, true)
	if held < cfg.MinCharge then pose(char, "Idle", 0.12, 0, 0.15) return false end -- too short: cancelled, free
	local frac = math.clamp((held - cfg.MinCharge) / (cfg.MaxCharge - cfg.MinCharge), 0, 1)
	local cost = math.floor(cfg.Mana + (cfg.ManaMax - cfg.Mana) * frac + 0.5)
	local mana = player:GetAttribute("Mana") or 0
	if mana < cost then
		if mana < cfg.Mana then player:SetAttribute("NoMana", os.clock()) pose(char, "Idle", 0.12, 0, 0.15) return false end
		frac = math.clamp((mana - cfg.Mana) / math.max(1, cfg.ManaMax - cfg.Mana), 0, 1)
		cost = mana
	end
	player:SetAttribute("Mana", mana - cost)
	s.cd.Charge = os.clock() + cfg.Cooldown - 0.05
	local full = held / cfg.MaxCharge >= cfg.FullAt and frac > 0.9
	pose(char, "ChargeRelease", 0.05, 0.14, 0.3)
	-- [MogwartsSounds] one heavy launch instead of blast + cast
	if not Sounds.play("charge_release", root) then sound(root, "Blast") sound(root, "Cast") end
	Sounds.affinity(aff.Name, root)
	fireBolt(player, char, root, target, aff, {
		damage = cfg.DamageMin + (cfg.DamageMax - cfg.DamageMin) * frac,
		speed = cfg.Speed, range = cfg.Range, radius = cfg.Radius * (0.7 + 0.6 * frac), scale = 1.4 + 1.6 * frac,
		knockback = full and cfg.Knockback or cfg.Knockback * 0.35 * frac,
		explode = full and { radius = cfg.ExplodeRadius, mult = cfg.ExplodeMult } or nil,
	})
	return true
end

-- ===== barrage =====
local function castBarrage(player, char, root, target, aff)
	local cfg = Config.Spells.Barrage
	local s = getState(player)
	s.barrageAim = target
	-- rarer houses fire longer volleys (Config.AffinityTierBonus); the extra shots hit a bit softer
	local shots = Config.BarrageShots(aff.Name)
	local extraMult = Config.AffinityTierBonus.ExtraShotDamage or 0.6
	task.spawn(function()
		for i = 1, shots do
			local c, h, r = aliveChar(player)
			if not c or not player:GetAttribute("CombatMode") or not c:FindFirstChild("Wand") then break end
			local aim = s.barrageAim or target
			local d = (aim - r.Position)
			local spread = math.rad(cfg.Spread)
			local rot = CFrame.Angles((math.random() - 0.5) * 2 * spread, (math.random() - 0.5) * 2 * spread, 0)
			local aimP = r.Position + (CFrame.lookAt(Vector3.zero, d.Magnitude > 0.1 and d.Unit or r.CFrame.LookVector) * rot).LookVector * math.max(d.Magnitude, 5)
			pose(c, (i % 2 == 1) and "BarrageA" or "BarrageB", 0.03, 0.04, 0.08)
			sound(r, "Cast")
			fireBolt(player, c, r, aimP, aff, { damage = cfg.Damage * (i > cfg.Shots and extraMult or 1), speed = cfg.Speed, range = cfg.Range, radius = cfg.Radius, scale = 0.6,
				perkMult = cfg.PerkMult, castFX = (i == 1) })
			task.wait(cfg.Interval)
		end
		s.barrageAim = nil
	end)
end

local function castBlast(player, char, root, aff)
	local cfg = Config.Spells.Blast
	pose(char, "BlastWind", 0.06, 0.02, 0.05)
	task.delay(0.08, function() if char.Parent then pose(char, "CastBlast", 0.05, 0.14, 0.25) end end)
	local center = root.Position
	local params = RaycastParams.new() params.FilterType = Enum.RaycastFilterType.Exclude params.FilterDescendantsInstances = { char, fxFolder }
	local g = workspace:Raycast(center, Vector3.new(0, -8, 0), params)
	local groundY = g and g.Position.Y + 0.08 or center.Y - 2.9
	local blastHits = {}
	sound(root, "Blast")
	sound(root, "BlastWhoosh")
	local hitModels = {}
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = { char, fxFolder }
	for _, part in ipairs(workspace:GetPartBoundsInRadius(center, cfg.Range, op)) do
		local model, hum = targetInfo(part)
		if hum and not hitModels[model] then
			hitModels[model] = true
			table.insert(blastHits, model)
			local tr = model:FindFirstChild("HumanoidRootPart") or part
			applyDamage(player, model, hum, cfg.Damage * aff.Damage, tr.Position, aff)
			local victim = Players:GetPlayerFromCharacter(model)
			if victim and not (state[victim] and os.clock() < state[victim].shieldUntil) then
				local away = (tr.Position - center) * Vector3.new(1, 0, 1)
				away = away.Magnitude > 0.1 and away.Unit or root.CFrame.LookVector
				Remotes.Knockback:FireClient(victim, away * cfg.Knockback * (aff.Knockback or 1) + Vector3.new(0, 34, 0))
			end
		end
	end
	SpellFX:FireAllClients("Blast", { center = center, groundY = groundY, color = aff.Color, range = cfg.Range, aff = aff.Name,
		caster = player.UserId, hits = blastHits, tier = VFX.TierOf(aff.Name) })
	if VFX.TierOf(aff.Name) >= 6 then sound(root, "MythicCast") end
end

local function castShield(player, char, root, aff)
	local cfg = Config.Spells.Shield
	local dur = cfg.Duration * (aff.ShieldTime or 1)
	chargeCancel(player, getState(player), true)
	pose(char, "CastShield", 0.1, 0.5, 0.3)
	getState(player).shieldUntil = os.clock() + dur
	local old = char:FindFirstChild("MagicShield") if old then old:Destroy() end
	VFX.Shield(root, aff.Color, dur, aff.Name)
	sound(root, "Shield")
end

Remotes.CastSpell.OnServerEvent:Connect(function(player, spellName, target, phase)
	local s = getState(player)
	-- barrage aim updates (a few per second while the volley is flying) skip the rate limit
	if spellName == "BarrageAim" then
		if s.barrageAim and typeof(target) == "Vector3" and target == target then s.barrageAim = target end
		return
	end
	if not rateOk(s) then return end
	if type(spellName) ~= "string" then return end
	local cfg = Config.Spells[spellName]
	if not cfg then return end
	local char, hum, root = aliveChar(player)
	if spellName == "Charge" and phase == "cancel" then chargeCancel(player, s) return end
	if not player:GetAttribute("CombatMode") then chargeCancel(player, s) return end
	if not char or not char:FindFirstChild("Wand") then return end
	local now = os.clock()
	if typeof(target) ~= "Vector3" or target ~= target then target = root.Position + root.CFrame.LookVector * 50 end
	if (target - root.Position).Magnitude > 600 then return end
	local mana = player:GetAttribute("Mana") or 0
	local aff = affinityOf(player)
	if spellName == "Charge" then
		if phase == "start" then
			if s.chargeStart or (s.cd.Charge and now < s.cd.Charge) then return end
			if mana < cfg.Mana then player:SetAttribute("NoMana", os.clock()) return end
			chargeStart(player, s, char, hum)
		elseif phase == "release" and s.chargeStart then
			chargeRelease(player, s, char, root, target, aff)
		end
		return
	end
	if s.chargeStart and spellName ~= "Shield" then return end -- busy charging (Shield cancels it)
	if s.cd[spellName] and now < s.cd[spellName] then return end
	if mana < cfg.Mana then return end
	s.cd[spellName] = now + cfg.Cooldown - 0.05
	player:SetAttribute("Mana", mana - cfg.Mana)
	if spellName == "Bolt" then castBolt(player, char, root, target, aff)
	elseif spellName == "Blast" then castBlast(player, char, root, aff)
	elseif spellName == "Shield" then castShield(player, char, root, aff)
	elseif spellName == "Barrage" then castBarrage(player, char, root, target, aff) end
end)

-- ================= DASH =================
local DASH_DIRS = { Forward = true, Back = true, Left = true, Right = true }
Remotes.Dash.OnServerEvent:Connect(function(player, dirName)
	local s = getState(player)
	if not rateOk(s) then return end
	if not DASH_DIRS[dirName] then dirName = "Forward" end
	local now = os.clock()
	if s.cd.Dash and now < s.cd.Dash then return end
	local char, hum, root = aliveChar(player)
	if not char then return end
	-- no dashing in the air
	if hum.FloorMaterial == Enum.Material.Air then return end
	s.cd.Dash = now + Config.Dash.Cooldown - 0.2
	pose(char, "Dash" .. dirName, 0.06, Config.Dash.Duration - 0.04, 0.22)
	local aff = affinityOf(player)
	local a0 = Instance.new("Attachment") a0.Position = Vector3.new(0, 0.9, 0) a0.Parent = root
	local a1 = Instance.new("Attachment") a1.Position = Vector3.new(0, -0.9, 0) a1.Parent = root
	local trail = Instance.new("Trail") trail.Attachment0 = a0 trail.Attachment1 = a1
	trail.Color = ColorSequence.new(aff.Color) trail.LightEmission = 0.7 trail.Lifetime = 0.25
	trail.Transparency = NumberSequence.new(0.35, 1) trail.Parent = root
	local puff = fx(Vector3.one * 0.2, CFrame.new(root.Position - Vector3.new(0, 2.6, 0)), aff.Color, nil, 1)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = SMOKE pe.Color = ColorSequence.new(Color3.fromRGB(150, 150, 160)) pe.Size = NumberSequence.new(1, 2.5)
	pe.Transparency = NumberSequence.new(0.75, 1) pe.Lifetime = NumberRange.new(0.3, 0.5) pe.Speed = NumberRange.new(3, 6)
	pe.SpreadAngle = Vector2.new(180, 10) pe.Rate = 0 pe.Parent = puff
	pe:Emit(6)
	Debris:AddItem(puff, 0.8)
	sound(root, "Dash")
	Debris:AddItem(trail, 0.45) Debris:AddItem(a0, 0.45) Debris:AddItem(a1, 0.45)
end)

-- ================= NORMAL / COMBAT MODE =================
local function setMode(player, on, silent)
	local char, hum = aliveChar(player)
	player:SetAttribute("CombatMode", on)
	if not char then return end
	if on then
		local wand = player.Backpack:FindFirstChild("Wand") or char:FindFirstChild("Wand")
		if wand and wand.Parent ~= char then hum:EquipTool(wand) end
		if not silent then
			pose(char, stancePose(char, "Draw"), 0.1, 0.35, 0.3)
			local root = char:FindFirstChild("HumanoidRootPart")
			sound(root, "Draw")
			task.delay(0.1, function()
				-- the draw flourish scales with the wand's rarity (drawn on every client)
				local w = char:FindFirstChild("Wand")
				local tip = w and w:FindFirstChild("Tip")
				if tip then
					SpellFX:FireAllClients("Draw", { pos = tip.Position, color = affinityOf(player).Color, tier = w:GetAttribute("WandTier") or 1,
						caster = player.UserId, ground = root and (root.Position - Vector3.new(0, (hum.HipHeight + root.Size.Y / 2), 0)) })
				end
			end)
		end
	else
		chargeCancel(player, getState(player), true)
		hum:UnequipTools()
		if not silent then
			pose(char, "Holster", 0.08, 0.08, 0.25)
			sound(char:FindFirstChild("HumanoidRootPart"), "Holster")
			local hw = char:FindFirstChild("HolsteredWand")
			local ht = hw and hw:FindFirstChild("Tip")
			if ht then SpellFX:FireAllClients("Draw", { pos = ht.Position, color = affinityOf(player).Color, tier = 1, holster = true, caster = player.UserId }) end
		end
	end
end
Remotes.SetCombatMode.OnServerEvent:Connect(function(player, on)
	if type(on) ~= "boolean" then return end
	local s = getState(player)
	local now = os.clock()
	if s.modeT and now - s.modeT < 1 then return end
	if on == (player:GetAttribute("CombatMode") == true) then return end
	if not on and s.lastCombat and now - s.lastCombat < 4 then
		Remotes.Notify:FireClient(player, "You can't sheathe your wand in the middle of a fight")
		return
	end
	s.modeT = now
	setMode(player, on)
end)

-- ================= HEALTH + MANA =================
local function onCharacter(player, char)
	local hum = char:WaitForChild("Humanoid")
	hum.MaxHealth = Config.MaxHealth
	hum.Health = Config.MaxHealth
	hum.WalkSpeed = Config.Movement.Walk
	player:SetAttribute("MaxMana", Config.MaxMana)
	player:SetAttribute("Mana", Config.MaxMana)
	getState(player).shieldUntil = 0
	player:SetAttribute("CombatMode", false)
	-- [MogwartsSounds] arrival shimmer on spawn, a dark fall when defeated
	local spawnRoot = char:WaitForChild("HumanoidRootPart", 5)
	if spawnRoot then Sounds.play("respawn", spawnRoot) end
	hum.Died:Connect(function()
		local r = char:FindFirstChild("HumanoidRootPart")
		if r then Sounds.play("defeat", r.Position) end
	end)
	task.delay(0.8, function() if player.Character == char and not player:GetAttribute("CombatMode") then local h = char:FindFirstChildOfClass("Humanoid") if h then h:UnequipTools() end end end)
end
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(c) onCharacter(player, c) end)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	pl.CharacterAdded:Connect(function(c) onCharacter(pl, c) end)
	if pl.Character then task.spawn(onCharacter, pl, pl.Character) end
end
Players.PlayerRemoving:Connect(function(p) state[p] = nil end)

task.spawn(function()
	while true do
		local dt = task.wait(0.1)
		for _, pl in ipairs(Players:GetPlayers()) do
			local c = pl.Character
			local tip = c and c:FindFirstChild("Wand") and c.Wand:FindFirstChild("Tip")
			if tip then
				local col = affinityOf(pl).Color
				if tip.Color ~= col then
					tip.Color = col
					local l = tip:FindFirstChildOfClass("PointLight") if l then l.Color = col end
				end
			end
			local m = pl:GetAttribute("Mana")
			if m then
				local max = pl:GetAttribute("MaxMana") or Config.MaxMana
				if m < max then
					local rate = Config.ManaRegen * (affinityOf(pl).ManaRegen or 1)
					pl:SetAttribute("Mana", math.min(max, m + rate * dt))
				end
			end
		end
	end
end)
