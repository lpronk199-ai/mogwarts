-- Aldermoor HUD: calm, minimal, magic-school style.
-- Top: school info pill (place, time, house). Bottom-left: keybind hints (clickable on touch).
-- Bottom-centre: slim vitality bar; spell slots + mana only while the wand is drawn.
-- Also: toast messages, the Grimoire (reroll book) and custom-styled interaction prompts.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")
local PPS = game:GetService("ProximityPromptService")
local Config = require(RS:WaitForChild("WizardShared"):WaitForChild("Config"))
local Locations = require(RS.WizardShared:WaitForChild("Locations"))
local UI = require(RS.WizardShared:WaitForChild("UIStyle"))
local Sounds = require(RS.WizardShared:WaitForChild("MogwartsSounds")) -- [MogwartsSounds] 
local DayCycle = require(RS.WizardShared:WaitForChild("DayCycle"))
local Remotes = RS.WizardShared:WaitForChild("Remotes")

local player = Players.LocalPlayer
local gui = script.Parent
gui.IgnoreGuiInset = true
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end) -- keep the HUD out of phone notches
local TOUCH = UIS.TouchEnabled and not UIS.KeyboardEnabled
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false) end)
pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false) end)

local C, F, new, text = UI.C, UI.F, UI.new, UI.text

-- shared menu toggle channel (Map / Emotes / Grimoire scripts listen to this)
local toggleMenu = gui:FindFirstChild("ToggleMenu") or new("BindableEvent", { Name = "ToggleMenu" }, gui)
local toastEvent = gui:FindFirstChild("Toast") or new("BindableEvent", { Name = "Toast" }, gui)
local function action(name)
	local ev = player:FindFirstChild("WizardAction")
	if ev then ev:Fire(name) end
end

-- very soft vignette so the edges feel candlelit rather than dark
local vig = new("Frame", { Name = "Vignette", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 0 }, gui)
for _, r in ipairs({ 0, 90, 180, 270 }) do
	local f = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(20, 10, 6), BorderSizePixel = 0 }, vig)
	new("UIGradient", { Rotation = r, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.72), NumberSequenceKeypoint.new(0.14, 1), NumberSequenceKeypoint.new(1, 1) }) }, f)
end

-- ================= TOP: SCHOOL INFO PILL =================
local top = new("Frame", { Name = "Top", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(600, 120), BackgroundTransparency = 1 }, gui)
UI.autoScale(top)
local pill = new("Frame", { Name = "InfoPill", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 3 }, top)
UI.glass(pill, { radius = 15, transparency = 0.18 })
UI.pad(pill, 16, 0)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, pill)
local function pillText(order, font, color)
	return text(pill, { LayoutOrder = order, Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, Text = "", FontFace = font, TextSize = 14, TextColor3 = color, ZIndex = 4 })
end
local function pillGem(order)
	local holder = new("Frame", { LayoutOrder = order, Size = UDim2.fromOffset(6, 30), BackgroundTransparency = 1, ZIndex = 4 }, pill)
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(5, 5), Rotation = 45, BackgroundColor3 = C.Gold, BorderSizePixel = 0, ZIndex = 4 }, holder)
end
local placeLbl = pillText(1, F.Title, C.GoldHi)
placeLbl.TextSize = 16
pillGem(2)
-- sun / moon / horizon icon, drawn with frames (no images, no emoji)
local sky = new("Frame", { Name = "SkyIcon", LayoutOrder = 3, Size = UDim2.fromOffset(18, 30), BackgroundTransparency = 1, ZIndex = 4 }, pill)
local skyRays = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1, ZIndex = 4 }, sky)
for i = 0, 7 do
	local a = i / 8 * math.pi * 2
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.cos(a) * 8, 0.5, math.sin(a) * 8), Size = UDim2.fromOffset(3, 1.5), Rotation = math.deg(a), BackgroundColor3 = C.Candle, BorderSizePixel = 0, ZIndex = 4 }, skyRays)
end
local skyDisc = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = C.Candle, BorderSizePixel = 0, ZIndex = 5 }, sky)
UI.corner(skyDisc, UDim.new(1, 0))
local skyCut = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 3, 0.5, -2), Size = UDim2.fromOffset(9, 9), BackgroundColor3 = Color3.fromRGB(34, 26, 22), BorderSizePixel = 0, ZIndex = 6 }, sky)
UI.corner(skyCut, UDim.new(1, 0))
local skyLow = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 1), Size = UDim2.fromOffset(20, 9), BackgroundColor3 = Color3.fromRGB(30, 23, 20), BorderSizePixel = 0, ZIndex = 6 }, sky)
local skyLine = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 1), Size = UDim2.fromOffset(18, 1.5), BackgroundColor3 = C.Gold, BorderSizePixel = 0, ZIndex = 7 }, sky)
local skyStars = {}
for _, p in ipairs({ { -6, -6 }, { 7, 5 } }) do
	table.insert(skyStars, new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, p[1], 0.5, p[2]), Size = UDim2.fromOffset(2, 2), Rotation = 45, BackgroundColor3 = C.Parchment, BorderSizePixel = 0, ZIndex = 5 }, sky))
end
local skyPhase
local function setSky(phase)
	if phase == skyPhase then return end
	skyPhase = phase
	local night, low = phase == "night", phase == "dawn" or phase == "dusk"
	skyRays.Visible = not night
	skyCut.Visible = night
	skyLow.Visible = low
	skyLine.Visible = low
	for _, s in ipairs(skyStars) do s.Visible = night end
	local col = (night and Color3.fromRGB(222, 228, 255)) or (phase == "dawn" and Color3.fromRGB(255, 186, 170)) or (phase == "dusk" and Color3.fromRGB(255, 164, 88)) or C.Candle
	skyDisc.BackgroundColor3 = col
	for _, r in ipairs(skyRays:GetChildren()) do r.BackgroundColor3 = col end
end
local timeLbl = pillText(4, F.SerifBold, C.Text)
timeLbl.TextSize = 13
pillGem(5)
local houseLbl = pillText(6, F.Serif, C.Muted)
houseLbl.TextSize = 13

-- ================= TOAST =================
local toastStack = new("Frame", { Name = "Toasts", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.fromOffset(560, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 5 }, top)
new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, toastStack)
local toasts, toastSeq, MAX_TOASTS, TOAST_TIME = {}, 0, 4, 3.2
local function dismissToast(t)
	if t.gone then return end
	t.gone = true
	local i = table.find(toasts, t)
	if i then table.remove(toasts, i) end
	local to = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(t.frame, to, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(t.label, to, { TextTransparency = 1 }):Play()
	TweenService:Create(t.dot, to, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(t.stroke, to, { Transparency = 1 }):Play()
	TweenService:Create(t.scale, to, { Scale = 0.9 }):Play()
	task.delay(0.36, function() t.frame:Destroy() end)
end
local function notify(msg, color)
	msg = tostring(msg)
	for _, t in ipairs(toasts) do
		if t.msg == msg then -- same message again: bump the counter instead of stacking copies
			t.count += 1
			t.label.Text = msg .. "  x" .. t.count
			t.stamp = os.clock()
			t.scale.Scale = 1.08
			TweenService:Create(t.scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			return
		end
	end
	toastSeq += 1
	local col = color or C.GoldHi
	local f = new("Frame", { Name = "Toast", LayoutOrder = toastSeq, Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 5 }, toastStack)
	local st = UI.glass(f, { radius = 16, transparency = 0.12, strokeT = 0.3 })
	UI.pad(f, 16, 0)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	local dot = new("Frame", { LayoutOrder = 1, Size = UDim2.fromOffset(6, 6), Rotation = 45, BackgroundColor3 = col, BorderSizePixel = 0, ZIndex = 6 }, f)
	local lbl = text(f, { LayoutOrder = 2, Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, Text = msg, FontFace = F.Serif, TextSize = 14, TextColor3 = col, ZIndex = 6 })
	local sc = new("UIScale", { Scale = 0.85 }, f)
	f.BackgroundTransparency = 1 lbl.TextTransparency = 1 st.Transparency = 1 dot.BackgroundTransparency = 1
	local ti = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(f, ti, { BackgroundTransparency = 0.12 }):Play()
	TweenService:Create(lbl, ti, { TextTransparency = 0 }):Play()
	TweenService:Create(dot, ti, { BackgroundTransparency = 0 }):Play()
	TweenService:Create(st, ti, { Transparency = 0.3 }):Play()
	TweenService:Create(sc, ti, { Scale = 1 }):Play()
	local t = { frame = f, label = lbl, stroke = st, dot = dot, scale = sc, msg = msg, count = 1, stamp = os.clock() }
	table.insert(toasts, t)
	while #toasts > MAX_TOASTS do dismissToast(toasts[1]) end
	task.spawn(function()
		while not t.gone do
			task.wait(0.2)
			if os.clock() - t.stamp > TOAST_TIME then dismissToast(t) end
		end
	end)
end
Remotes.Notify.OnClientEvent:Connect(function(t) notify(t) end)
toastEvent.Event:Connect(function(t, c) notify(t, c) end)

-- ================= BOTTOM-LEFT: KEYBIND HINTS =================
-- on phones the thumbstick lives bottom-left, so the list moves up to the left edge and only shows tappable rows
local keys = new("Frame", { Name = "Keybinds", AnchorPoint = TOUCH and Vector2.new(0, 0.5) or Vector2.new(0, 1), Position = TOUCH and UDim2.new(0, 16, 0.42, 0) or UDim2.new(0, 16, 1, -16), Size = UDim2.fromOffset(190, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, gui)
UI.autoScale(keys, 1280, 800, 0.7, 1.1)
-- soft dark fade behind the list so it reads on bright ground
local keysBack = new("Frame", { Name = "Backdrop", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, -16, 1, 16), Size = UDim2.new(1, 90, 1, 40), BackgroundColor3 = Color3.fromRGB(14, 10, 8), BorderSizePixel = 0, ZIndex = 0 }, keys)
new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.6, 0.85), NumberSequenceKeypoint.new(1, 1) }) }, keysBack)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom }, keys)
local keyRows = {}
local function keyRow(order, key, label, onClick)
	local row = new("TextButton", { LayoutOrder = order, Size = UDim2.new(1, 0, 0, TOUCH and 32 or 20), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 2, Visible = (not TOUCH) or onClick ~= nil }, keys)
	local cap = UI.keycap(row, key, { ZIndex = 2, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5) })
	for _, d in ipairs(cap:GetDescendants()) do if d:IsA("GuiObject") then d.ZIndex = 3 end end
	local lbl = text(row, { Position = UDim2.fromOffset(cap.Size.X.Offset + 9, 0), Size = UDim2.new(1, -(cap.Size.X.Offset + 9), 1, 0), Text = label, FontFace = F.Sans, TextSize = 13, TextColor3 = C.Text, TextTransparency = 0.12, TextStrokeColor3 = Color3.fromRGB(12, 8, 6), TextStrokeTransparency = 0.75, ZIndex = 2 })
	row.MouseEnter:Connect(function() TweenService:Create(lbl, TweenInfo.new(0.12), { TextColor3 = C.GoldHi }):Play() end)
	row.MouseLeave:Connect(function() TweenService:Create(lbl, TweenInfo.new(0.2), { TextColor3 = C.Text }):Play() end)
	if onClick then row.MouseButton1Click:Connect(onClick) end
	keyRows[key] = lbl
	return lbl
end
local combatLbl = keyRow(1, "T", "Draw wand", function() action("ToggleCombat") end)
keyRow(2, "F", "Interact")
keyRow(3, "C", "Dash", function() action("Dash") end)
keyRow(4, "Shift", "Sprint")
keyRow(5, "G", "Grimoire", function() toggleMenu:Fire("Grimoire") end)
keyRow(6, "M", "Map", function() toggleMenu:Fire("Map") end)
keyRow(7, "B", "Emotes", function() toggleMenu:Fire("Emotes") end)
-- effects quality toggle (per player, this device only): Reduced roughly halves spell/step particles
local fxLbl
local function setReduced(on)
	player:SetAttribute("ReducedFX", on or nil)
	fxLbl.Text = on and "Effects: Reduced" or "Effects: Full"
end
fxLbl = keyRow(8, "V", "Effects: Full", function() setReduced(not player:GetAttribute("ReducedFX")) end)
keyRow(9, "K", "Settings", function() toggleMenu:Fire("Settings") end)
keyRow(10, Config.Spells.Charge.Key, "Charge shot (hold)")
keyRow(11, Config.Spells.Barrage.Key, "Barrage")
player:GetAttributeChangedSignal("ReducedFX"):Connect(function() fxLbl.Text = player:GetAttribute("ReducedFX") and "Effects: Reduced" or "Effects: Full" end)
UIS.InputBegan:Connect(function(io, gpe)
	if gpe then return end
	if io.KeyCode == Enum.KeyCode.V then
		setReduced(not player:GetAttribute("ReducedFX"))
		notify(player:GetAttribute("ReducedFX") and "Reduced effects on" or "Full effects on")
	end
end)

-- ================= BOTTOM-CENTRE: VITALS + SPELLS =================
local bottom = new("Frame", { Name = "Vitals", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(300, 120), BackgroundTransparency = 1 }, gui)
UI.autoScale(bottom, 1280, 800, 0.75, 1.1)

local function slimBar(y, h, color)
	local back = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, y), Size = UDim2.new(1, -40, 0, h), BackgroundColor3 = Color3.fromRGB(16, 12, 10), BackgroundTransparency = 0.25, BorderSizePixel = 0 }, bottom)
	UI.corner(back, UDim.new(1, 0))
	local backStroke = UI.stroke(back, C.Gold, 0.6, 1)
	local ghost = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 214, 160), BackgroundTransparency = 0.3, BorderSizePixel = 0 }, back)
	UI.corner(ghost, UDim.new(1, 0))
	local fill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 2 }, back)
	UI.corner(fill, UDim.new(1, 0))
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.25), color:Lerp(Color3.new(0, 0, 0), 0.2)) }, fill)
	return back, fill, ghost, backStroke
end
-- vitality (always)
local hpBack, hpFill, hpGhost, hpStroke = slimBar(104, 6, C.Health)
-- low vitality: a red pulse around the screen edge
local lowVig = new("CanvasGroup", { Name = "LowVitality", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, GroupTransparency = 1, Visible = false, ZIndex = 0 }, gui)
for _, r in ipairs({ 0, 90, 180, 270 }) do
	local f = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(150, 20, 24), BorderSizePixel = 0 }, lowVig)
	new("UIGradient", { Rotation = r, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(0.16, 1), NumberSequenceKeypoint.new(1, 1) }) }, f)
end
local ghostHold, lastHpPct = 0, 1
local hpCaption = text(bottom, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 86), Size = UDim2.new(1, -40, 0, 14), Text = "", FontFace = F.Sans, TextSize = 11, TextColor3 = C.Text, TextTransparency = 0.15, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeColor3 = Color3.fromRGB(12, 8, 6), TextStrokeTransparency = 0.6 })

-- combat group: spell slots + mana (fades in only while the wand is drawn)
local combat = new("CanvasGroup", { Name = "Combat", Size = UDim2.fromOffset(300, 84), BackgroundTransparency = 1, GroupTransparency = 1, Visible = false }, bottom)
local mpBack = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 75), Size = UDim2.new(1, -40, 0, 5), BackgroundColor3 = Color3.fromRGB(16, 12, 10), BackgroundTransparency = 0.25, BorderSizePixel = 0 }, combat)
UI.corner(mpBack, UDim.new(1, 0))
UI.stroke(mpBack, C.Gold, 0.7, 1)
local mpGhost = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(196, 214, 255), BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 1 }, mpBack)
UI.corner(mpGhost, UDim.new(1, 0))
local mpFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Mana, BorderSizePixel = 0, ZIndex = 2 }, mpBack)
UI.corner(mpFill, UDim.new(1, 0))
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.Mana:Lerp(Color3.new(1, 1, 1), 0.3), C.Mana) }, mpFill)
-- a soft shine that glides along the mana bar
local mpShine = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 2 }, mpFill)
UI.corner(mpShine, UDim.new(1, 0))
local mpShineGrad = new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.45, 1), NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(0.55, 1), NumberSequenceKeypoint.new(1, 1) }), Offset = Vector2.new(-1, 0) }, mpShine)

-- drawn rune glyphs (no images, no emoji)
local function line(parent, a, b, th, color, size)
	local mid, d = (a + b) / 2, b - a
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(mid.X, mid.Y), Size = UDim2.fromOffset(d.Magnitude * size, th), BackgroundColor3 = color, BorderSizePixel = 0, Rotation = math.deg(math.atan2(d.Y, d.X)), ZIndex = 3 }, parent)
end
local glyphs = {}
function glyphs.Bolt(b, c, s)
	line(b, Vector2.new(0.62, 0.08), Vector2.new(0.36, 0.5), 2, c, s) line(b, Vector2.new(0.36, 0.5), Vector2.new(0.64, 0.5), 2, c, s) line(b, Vector2.new(0.64, 0.5), Vector2.new(0.38, 0.92), 2, c, s)
end
function glyphs.Blast(b, c, s)
	local ring = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.46, 0.46), BackgroundTransparency = 1, ZIndex = 3 }, b)
	UI.corner(ring, UDim.new(1, 0)) UI.stroke(ring, c, 0, 1.5)
	for i = 0, 7 do local a = i / 8 * math.pi * 2 line(b, Vector2.new(0.5 + math.cos(a) * 0.32, 0.5 + math.sin(a) * 0.32), Vector2.new(0.5 + math.cos(a) * 0.46, 0.5 + math.sin(a) * 0.46), 1.5, c, s) end
end
function glyphs.Shield(b, c, s)
	local d = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.56, 0.56), BackgroundTransparency = 1, Rotation = 45, ZIndex = 3 }, b)
	UI.stroke(d, c, 0, 1.5)
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.26, 0.26), BackgroundColor3 = c, BackgroundTransparency = 0.3, BorderSizePixel = 0, Rotation = 45, ZIndex = 3 }, b)
end
function glyphs.Dash(b, c, s)
	for _, x in ipairs({ 0.22, 0.46 }) do line(b, Vector2.new(x, 0.22), Vector2.new(x + 0.28, 0.5), 2, c, s) line(b, Vector2.new(x + 0.28, 0.5), Vector2.new(x, 0.78), 2, c, s) end
end

function glyphs.Charge(b, c, s)
	-- a gathering orb: filled core inside two rings, with small motes drawn in
	local ring = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.86, 0.86), BackgroundTransparency = 1, ZIndex = 3 }, b)
	UI.corner(ring, UDim.new(1, 0)) UI.stroke(ring, c, 0.45, 1)
	local ring2 = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.56, 0.56), BackgroundTransparency = 1, ZIndex = 3 }, b)
	UI.corner(ring2, UDim.new(1, 0)) UI.stroke(ring2, c, 0, 1.5)
	local core = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.28, 0.28), BackgroundColor3 = c, BorderSizePixel = 0, ZIndex = 3 }, b)
	UI.corner(core, UDim.new(1, 0))
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5 + math.cos(a) * 0.43, 0.5 + math.sin(a) * 0.43), Size = UDim2.fromOffset(3, 3), Rotation = 45, BackgroundColor3 = c, BorderSizePixel = 0, ZIndex = 3 }, b)
	end
end
function glyphs.Barrage(b, c, s)
	-- three small bolts in a fan
	for i, y in ipairs({ 0.2, 0.5, 0.8 }) do
		local x0 = i == 2 and 0.1 or 0.2
		line(b, Vector2.new(x0, y), Vector2.new(x0 + 0.46, y), 1.5, c, s)
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x0 + 0.56, y), Size = UDim2.fromOffset(5, 5), Rotation = 45, BackgroundColor3 = c, BorderSizePixel = 0, ZIndex = 3 }, b)
	end
end

local slots, order = {}, {}
for name, cfg in pairs(Config.Spells) do table.insert(order, { name = name, key = cfg.Key, order = cfg.Order, mana = cfg.Mana }) end
table.sort(order, function(a, b) return a.order < b.order end)
table.insert(order, { name = "Dash", key = Config.Dash.Key, order = 99, mana = 0 })
local SLOT, GAP = 42, 8
local rowW = #order * SLOT + (#order - 1) * GAP
for i, s in ipairs(order) do
	local b = new("TextButton", { Position = UDim2.fromOffset((300 - rowW) / 2 + (i - 1) * (SLOT + GAP), 8), Size = UDim2.fromOffset(SLOT, SLOT), Text = "", AutoButtonColor = false }, combat)
	local st = UI.glass(b, { radius = 10, transparency = 0.15, strokeT = 0.45 })
	local box = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(24, 24), BackgroundTransparency = 1 }, b)
	glyphs[s.name](box, C.GoldHi, 24)
	local cap = UI.keycap(b, s.key, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(18, 14), ZIndex = 5 })
	for _, d in ipairs(cap:GetDescendants()) do if d:IsA("TextLabel") then d.TextSize = 9 d.ZIndex = 6 end end
	text(b, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 3), Size = UDim2.fromOffset(60, 12), Text = s.name, FontFace = F.Sans, TextSize = 10, TextColor3 = C.Text, TextTransparency = 0.15, TextStrokeColor3 = Color3.fromRGB(12, 8, 6), TextStrokeTransparency = 0.6, TextXAlignment = Enum.TextXAlignment.Center })
	-- radial sweep: two clipped half-discs whose gradients rotate (dark = still cooling down)
	local cd = new("Frame", { Name = "Sweep", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -2, 1, -2), BackgroundTransparency = 1, Visible = false, ZIndex = 4 }, b)
	local sweep = {}
	for _, side in ipairs({ "L", "R" }) do
		local clip = new("Frame", { Position = UDim2.fromScale(side == "L" and 0 or 0.5, 0), Size = UDim2.fromScale(0.5, 1), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 4 }, cd)
		local disc = new("Frame", { Position = UDim2.fromScale(side == "L" and 0 or -1, 0), Size = UDim2.fromScale(2, 1), BackgroundColor3 = Color3.fromRGB(8, 6, 5), BackgroundTransparency = 0.28, BorderSizePixel = 0, ZIndex = 4 }, clip)
		UI.corner(disc, UDim.new(1, 0))
		sweep[side] = new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(0.502, 1), NumberSequenceKeypoint.new(1, 1) }) }, disc)
	end
	local cdText = text(b, { Size = UDim2.fromScale(1, 1), Text = "", FontFace = F.SerifBold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
	-- glow ring in the house colour that flashes when the spell is ready again
	local ready = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 8, 1, 8), BackgroundTransparency = 1, ZIndex = 1 }, b)
	UI.corner(ready, 13)
	local readyStroke = UI.stroke(ready, C.GoldHi, 1, 2)
	local chargeFill
	if s.name == "Charge" then
		-- hold the slot (mouse or touch) to charge, let go to fire; the fill rises while charging
		chargeFill = new("Frame", { Name = "ChargeFill", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 3, 1, -3), Size = UDim2.new(1, -6, 0, 0), BackgroundColor3 = C.GoldHi, BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 2 }, b)
		UI.corner(chargeFill, 8)
		b.InputBegan:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then action("ChargeDown") end
		end)
		b.InputEnded:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then action("ChargeUp") end
		end)
	else
		b.MouseButton1Click:Connect(function() action(s.name) end)
	end
	UI.hover(b, nil, nil, st)
	slots[s.name] = { button = b, cd = cd, sweepL = sweep.L, sweepR = sweep.R, stroke = st, text = cdText, box = box, mana = s.mana, readyStroke = readyStroke, wasCd = false, chargeFill = chargeFill }
end
local function setSweep(s, frac)
	s.cd.Visible = frac > 0.001
	local a = frac * 360
	s.sweepR.Rotation = math.clamp(a, 0, 180)
	s.sweepL.Rotation = math.clamp(a, 180, 360)
end
-- slot borders take a soft tint of your house (affinity) colour
local function paintSlots()
	local aff = Config.Find("Affinities", player:GetAttribute("Affinity") or "")
	local col = aff and aff.Color or C.Gold
	for _, s in pairs(slots) do s.stroke.Color = col:Lerp(C.Gold, 0.45) end
end
paintSlots()
player:GetAttributeChangedSignal("Affinity"):Connect(paintSlots)

local function applyMode(instant)
	local on = player:GetAttribute("CombatMode") == true
	combatLbl.Text = on and "Put wand away" or "Draw wand"
	local ti = TweenInfo.new(instant and 0 or 0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if on then
		combat.Visible = true
		combat.Position = UDim2.fromOffset(0, 10)
		TweenService:Create(combat, ti, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) }):Play()
	else
		local tw = TweenService:Create(combat, ti, { GroupTransparency = 1, Position = UDim2.fromOffset(0, 10) })
		tw:Play()
		tw.Completed:Connect(function() if not player:GetAttribute("CombatMode") then combat.Visible = false end end)
	end
end
player:GetAttributeChangedSignal("CombatMode"):Connect(function() applyMode(false) end)
applyMode(true)

-- ================= GRIMOIRE (reroll book) =================
local book, page = UI.book(gui, UDim2.fromOffset(460, 620), { Name = "Grimoire", Visible = false, Position = UDim2.new(0.5, 130, 0.5, 0) })
UI.autoScale(book, (Config.LookingGlass and Config.LookingGlass.BaseW) or 980, (Config.LookingGlass and Config.LookingGlass.BaseH) or 700, 0.45, 1.1)
local closeButton = UI.closeButton

-- ===== LOOKING GLASS: a big live portrait of your wizard beside the Grimoire (drag to turn, scroll/pinch to zoom) =====
-- Tune it in Config.LookingGlass (size, field of view, light). On narrow screens it shares the book's spot (Mirror / Book buttons).
local GL = Config.LookingGlass or {}
local BOOK_W, BOOK_H0 = 460, 620
local GLASS_W, GLASS_GAP = GL.Width or 380, GL.Gap or 16
local glass = new("Frame", { Name = "LookingGlass", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0, -GLASS_GAP, 0.5, 0), Size = UDim2.fromOffset(GLASS_W, BOOK_H0),
	BackgroundColor3 = C.Burgundy, BorderSizePixel = 0, ZIndex = 20 }, book)
UI.corner(glass, 12)
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.Burgundy, C.BurgundyDark) }, glass)
UI.stroke(glass, C.Gold, 0.25, 1.5)
UI.shadow(glass, 20, 0.45)
local mirrorBack = new("Frame", { Name = "MirrorBack", Position = UDim2.fromOffset(12, 48), Size = UDim2.new(1, -24, 1, -110), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 21 }, glass)
UI.corner(mirrorBack, 10)
UI.stroke(mirrorBack, C.GoldDim, 0.3, 1)
local DARK = Color3.fromRGB(20, 15, 18)
local backGrad = new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(92, 78, 84), DARK) }, mirrorBack)
local mirror = new("ViewportFrame", { Name = "Mirror", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 22,
	Ambient = GL.Ambient or Color3.fromRGB(168, 160, 152), LightColor = GL.LightColor or Color3.fromRGB(255, 244, 228),
	LightDirection = GL.LightDirection or Vector3.new(-0.35, -0.55, 1) }, mirrorBack)
text(glass, { Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 28), Text = "Looking Glass", FontFace = F.Title, TextSize = 24, TextColor3 = C.GoldHi, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22 })
local glassSub = text(glass, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -34), Size = UDim2.new(1, 0, 0, 18), Text = "", FontFace = F.Serif, TextSize = 14, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22 })
local glassHint = text(glass, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -14), Size = UDim2.new(1, 0, 0, 14), Text = UIS.TouchEnabled and "Drag to turn  ·  pinch to zoom" or "Drag to turn  ·  scroll to zoom",
	FontFace = F.Sans, TextSize = 11, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22 })
local world = new("WorldModel", {}, mirror)
local mirrorCam = new("Camera", { FieldOfView = GL.FOV or 24 }, mirror)
mirror.CurrentCamera = mirrorCam
-- the character faces you; it only turns while you drag, and eases back to the front ~2 s after you let go
local FRONT = math.pi
local mirrorModel, mirrorYaw, mirrorDrag = nil, FRONT, nil
local lastDrag = 0
local zoom, zoomGoal = 1, 1 -- 1 = close up on the face, 0 = full body
local shape = { headY = 4.5, headH = 1.4, feetY = 0, topY = 6 }
local viewBtn = new("TextButton", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -22, 1, -70), Size = UDim2.fromOffset(92, 28), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.2, AutoButtonColor = false,
	Text = "Full body", FontFace = F.SansBold, TextSize = 12, TextColor3 = C.GoldHi, ZIndex = 24 }, glass)
UI.corner(viewBtn, 14) UI.stroke(viewBtn, C.Gold, 0.4, 1)
local function setZoomGoal(z)
	zoomGoal = math.clamp(z, 0, 1)
	viewBtn.Text = zoomGoal > 0.5 and "Full body" or "Close up"
end
viewBtn.MouseButton1Click:Connect(function() setZoomGoal(zoomGoal > 0.5 and 0 or 1) end)

-- things that must never go into the mirror (they either don't render there or blow up the framing)
local JUNK = { ParticleEmitter = true, Trail = true, Beam = true, PointLight = true, SpotLight = true, SurfaceLight = true, Sound = true, BillboardGui = true,
	ForceField = true, Highlight = true, Fire = true, Smoke = true, Sparkles = true, ProximityPrompt = true, ClickDetector = true }
local fadeTw
local function rebuildMirror()
	local c = player.Character
	if not c then return end
	local was = c.Archivable
	c.Archivable = true
	local ok, clone = pcall(function() return c:Clone() end)
	c.Archivable = was
	if not ok or not clone then return end
	local root = clone:FindFirstChild("HumanoidRootPart")
	if not root then clone:Destroy() return end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or JUNK[d.ClassName] then d:Destroy()
		elseif d:IsA("BasePart") then d.Anchored = true d.CastShadow = false
		end
	end
	local hum = clone:FindFirstChildOfClass("Humanoid")
	if hum then hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None hum.NameDisplayDistance = 0 hum.HealthDisplayDistance = 0 end
	root.Transparency = 1
	clone.PrimaryPart = root
	-- stand it upright at the origin, facing the glass
	clone:PivotTo(CFrame.new())
	-- drop stray pieces (an accessory still loading at the old spot, big aura bits): they used to zoom the camera way out
	local maxD = GL.MaxPartDistance or 7
	for _, p in ipairs(clone:GetDescendants()) do
		if p.Parent and p:IsA("BasePart") and p ~= root and (p.Position.Magnitude > maxD or p.Size.Magnitude > 14) then
			local acc = p:FindFirstAncestorOfClass("Accessory")
			if acc then acc:Destroy() else p:Destroy() end
		end
	end
	-- measure from the real body, not the whole model: head for close ups, feet to hat for full body
	local head = clone:FindFirstChild("ClassicHead") or clone:FindFirstChild("Head")
	local headH = head and head.Size.Y * (head:FindFirstChildOfClass("SpecialMesh") and 1.2 or 1) or 1.4
	local headY = head and head.Position.Y or 4.5
	local feetY = math.huge
	for _, n in ipairs({ "LeftFoot", "RightFoot" }) do
		local f = clone:FindFirstChild(n)
		if f then feetY = math.min(feetY, f.Position.Y - f.Size.Y / 2) end
	end
	if feetY == math.huge then feetY = -3 end
	local topY = headY + headH * 0.6
	for _, p in ipairs(clone:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 0.9 then
			local flat = Vector2.new(p.Position.X, p.Position.Z).Magnitude
			local top = p.Position.Y + p.Size.Y / 2
			if flat < 2.2 and top > topY and top < headY + 4 then topY = top end
		end
	end
	shape = { headY = headY, headH = headH, feetY = feetY, topY = topY }
	if mirrorModel then mirrorModel:Destroy() end
	clone.Parent = world
	mirrorModel = clone
	-- soft fade in; a newer rebuild cancels the old fade so it can never get stuck half-way
	if fadeTw then fadeTw:Cancel() end
	mirror.ImageTransparency = 0.6
	fadeTw = TweenService:Create(mirror, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { ImageTransparency = 0 })
	fadeTw:Play()
	local aff = Config.Find("Affinities", player:GetAttribute("Affinity") or "")
	local rar = Config.Rarities[aff.Rarity]
	local tier = rar and rar.Order or 1
	-- aura stand-in (particles don't render in a ViewportFrame): thin glowing rings at the feet
	for i, r in ipairs({ { 3.2, 0.4 }, { 4.4, 0.75 } }) do
		if i == 1 or tier >= 3 then
			local ring = Instance.new("Part")
			ring.Shape = Enum.PartType.Cylinder ring.Anchored = true ring.Material = Enum.Material.Neon ring.CastShadow = false
			ring.Color = aff.Color ring.Transparency = r[2] ring.Size = Vector3.new(0.06, r[1], r[1])
			ring.CFrame = CFrame.new(0, feetY + 0.04 * i, 0) * CFrame.Angles(0, 0, math.rad(90))
			ring.Parent = clone
		end
	end
	-- the backdrop takes a soft tint of your house colour (stronger for rarer houses)
	backGrad.Color = ColorSequence.new(aff.Color:Lerp(Color3.fromRGB(64, 52, 58), math.clamp(0.82 - tier * 0.05, 0.5, 0.8)), DARK)
	local wand = (player:FindFirstChild("Backpack") and player.Backpack:FindFirstChild("Wand")) or c:FindFirstChild("Wand")
	glassSub.Text = (wand and wand:GetAttribute("WandName") or "Wand") .. "  ·  " .. aff.Name .. " House"
end

-- rebuilds wait until the server has finished the new look (RebuildHolds back to 0 and nothing added/removed
-- for a moment), and only the newest request wins, so fast rerolls never catch a half-built character
local mirrorReq = 0
local function requestMirror(immediate)
	mirrorReq += 1
	local my = mirrorReq
	task.spawn(function()
		local c = player.Character
		local t0 = os.clock()
		local last = immediate and 0 or os.clock()
		local conns = {}
		if c then
			table.insert(conns, c.DescendantAdded:Connect(function() last = os.clock() end))
			table.insert(conns, c.DescendantRemoving:Connect(function() last = os.clock() end))
		end
		if not immediate then task.wait(0.2) end
		while os.clock() - t0 < (GL.MaxWait or 4) do
			if my ~= mirrorReq then break end
			local holds = c and c:GetAttribute("RebuildHolds") or 0
			if holds == 0 and os.clock() - last > (GL.Settle or 0.3) then break end
			task.wait(0.05)
		end
		for _, x in ipairs(conns) do x:Disconnect() end
		if my == mirrorReq and book.Visible then rebuildMirror() end
	end)
end
local function watchLook(c)
	c:GetAttributeChangedSignal("LookVersion"):Connect(function() if book.Visible then requestMirror(false) end end)
end
if player.Character then watchLook(player.Character) end
player.CharacterAdded:Connect(function(c) watchLook(c) if book.Visible then requestMirror(false) end end)

-- turning and zooming
mirror.InputBegan:Connect(function(io)
	if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then mirrorDrag = io.Position.X end
end)
mirror.InputChanged:Connect(function(io)
	if io.UserInputType == Enum.UserInputType.MouseWheel then setZoomGoal(zoomGoal + io.Position.Z * 0.2) end
end)
UIS.InputChanged:Connect(function(io)
	if mirrorDrag and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then
		mirrorYaw += (io.Position.X - mirrorDrag) * 0.012
		mirrorDrag = io.Position.X
	end
end)
UIS.InputEnded:Connect(function(io)
	if (io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch) and mirrorDrag then mirrorDrag = nil lastDrag = os.clock() end
end)
local pinchStart
UIS.TouchPinch:Connect(function(positions, scale, _, state)
	if not (book.Visible and glass.Visible and positions[1]) then return end
	local p, a, s = positions[1], mirror.AbsolutePosition, mirror.AbsoluteSize
	if state == Enum.UserInputState.Begin then
		pinchStart = (p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y) and zoomGoal or nil
	elseif pinchStart and state == Enum.UserInputState.Change then
		setZoomGoal(pinchStart + (scale - 1) * 1.2)
		mirrorDrag = nil
	elseif state == Enum.UserInputState.End then
		pinchStart = nil
	end
end)
RunService.RenderStepped:Connect(function(dt)
	if not book.Visible or not mirrorModel then return end
	if not mirrorDrag and os.clock() - lastDrag > 2 then
		-- ease back to the nearest "facing the screen" angle
		local goal = FRONT + math.floor((mirrorYaw - FRONT) / (2 * math.pi) + 0.5) * 2 * math.pi
		mirrorYaw += (goal - mirrorYaw) * math.min(1, dt * 4)
	end
	zoom += (zoomGoal - zoom) * math.min(1, dt * 7)
	local tanH = math.tan(math.rad(mirrorCam.FieldOfView / 2))
	local sz = mirror.AbsoluteSize
	local aspect = sz.X / math.max(1, sz.Y)
	-- close up: head and shoulders, head in the upper part of the glass
	local cT, cH, cW = Vector3.new(0, shape.headY - shape.headH * (GL.CloseUpDrop or 0.22), 0), shape.headH * (GL.CloseUpHeads or 2.4), shape.headH * 1.9
	-- full body: feet to the top of the hat
	local fT, fH, fW = Vector3.new(0, (shape.feetY + shape.topY) / 2 - 0.15, 0), (shape.topY - shape.feetY) * (GL.FullBodyMargin or 1.24), 3.8
	local target = fT:Lerp(cT, zoom)
	local h = fH + (cH - fH) * zoom
	local w = fW + (cW - fW) * zoom
	local dist = math.max((h / 2) / tanH, (w / 2) / (tanH * math.max(0.2, aspect)))
	mirrorCam.CFrame = CFrame.lookAt(target + Vector3.new(math.sin(mirrorYaw) * dist, h * 0.05, math.cos(mirrorYaw) * dist), target)
end)

-- layout: side by side when there's room, otherwise the mirror and the book share one spot
local bookScale = book:FindFirstChild("AutoScale")
local compact, showMirror = false, false
local mirrorToggle = UI.inkButton(page, "Mirror", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -122, 0, 24), Size = UDim2.fromOffset(84, 44), ZIndex = 26, Visible = false })
local backBtn = UI.inkButton(glass, "Book", { Position = UDim2.fromOffset(14, 8), Size = UDim2.fromOffset(72, 36), ZIndex = 26, Visible = false })
local function layoutGlass()
	local vp = workspace.CurrentCamera.ViewportSize
	local sc = bookScale and bookScale.Scale or 1
	compact = vp.X < (BOOK_W + GLASS_GAP + GLASS_W) * sc + 24
	mirrorToggle.Visible = compact
	backBtn.Visible = compact
	if compact then
		book.Position = UDim2.fromScale(0.5, 0.5)
		glass.AnchorPoint = Vector2.new(0.5, 0.5) glass.Position = UDim2.fromScale(0.5, 0.5) glass.Size = UDim2.fromScale(1, 1) glass.ZIndex = 30
		glass.Visible = showMirror
		page.Visible = not showMirror
	else
		book.Position = UDim2.new(0.5, (GLASS_W + GLASS_GAP) / 2 * sc, 0.5, 0)
		glass.AnchorPoint = Vector2.new(1, 0.5) glass.Position = UDim2.new(0, -GLASS_GAP, 0.5, 0) glass.Size = UDim2.fromOffset(GLASS_W, BOOK_H0) glass.ZIndex = 20
		glass.Visible = true
		page.Visible = true
	end
end
mirrorToggle.MouseButton1Click:Connect(function() showMirror = true layoutGlass() end)
backBtn.MouseButton1Click:Connect(function() showMirror = false layoutGlass() end)
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutGlass)
if bookScale then bookScale:GetPropertyChangedSignal("Scale"):Connect(layoutGlass) end
layoutGlass()

-- ===== RARE REVEAL: a banner + a burst of sparkles around you for Rare+ rerolls =====
local reveal = new("Frame", { Name = "Reveal", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.19), Size = UDim2.fromOffset(460, 92), BackgroundTransparency = 1, Visible = false, ZIndex = 40 }, gui)
UI.autoScale(reveal, 1280, 800, 0.6, 1.1)
local revealBand = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.1, BorderSizePixel = 0, ZIndex = 40 }, reveal)
UI.corner(revealBand, 14)
local revealStroke = UI.stroke(revealBand, C.GoldHi, 0, 2)
local revealGrad = new("UIGradient", { Rotation = 0, Color = ColorSequence.new(C.Panel, C.PanelHi) }, revealBand)
local revealShine = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 41 }, revealBand)
UI.corner(revealShine, 14)
local revealShineGrad = new("UIGradient", { Rotation = 20, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1), NumberSequenceKeypoint.new(0.5, 0.6), NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1) }), Offset = Vector2.new(-1, 0) }, revealShine)
local revealTier = text(revealBand, { Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 22), Text = "", FontFace = F.SansBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 42 })
local revealName = text(revealBand, { Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 36), Text = "", FontFace = F.Title, TextSize = 32, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 42 })
local revealSub = text(revealBand, { Position = UDim2.fromOffset(0, 68), Size = UDim2.new(1, 0, 0, 16), Text = "", FontFace = F.Serif, TextSize = 12, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 42 })
local revealScale = new("UIScale", { Scale = 1 }, revealBand)
local revealId = 0
local function sparkleBurst(color, count, mythic)
	local c = player.Character
	local root = c and c:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local q = player:GetAttribute("ReducedFX") and 0.5 or 1
	local a = Instance.new("Attachment") a.Parent = root
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxassetid://1053546634" pe.LightEmission = 1 pe.LightInfluence = 0 pe.Rate = 0
	pe.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.6), color)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.5), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.8, 1.6) pe.Speed = NumberRange.new(4, 11) pe.Drag = 3 pe.SpreadAngle = Vector2.new(180, 180)
	pe.Acceleration = Vector3.new(0, 3, 0) pe.Rotation = NumberRange.new(0, 360) pe.RotSpeed = NumberRange.new(-200, 200)
	pe.Shape = Enum.ParticleEmitterShape.Cylinder pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	pe.Parent = a
	pe:Emit(math.floor(count * q))
	if mythic then
		local l = Instance.new("PointLight") l.Color = color l.Range = 18 l.Brightness = 4 l.Parent = a
		TweenService:Create(l, TweenInfo.new(1.4), { Brightness = 0 }):Play()
	end
	game:GetService("Debris"):AddItem(a, 2)
end
local function revealItem(label, item, rar)
	revealId += 1
	local id = revealId
	revealTier.Text = string.upper(item.Rarity) .. "  ·  " .. string.upper(label)
	revealTier.TextColor3 = rar.Color:Lerp(Color3.new(1, 1, 1), 0.2)
	revealName.Text = item.Name
	revealSub.Text = item.Perk or ""
	revealStroke.Color = rar.Color
	revealGrad.Color = ColorSequence.new(C.Panel, rar.Color:Lerp(C.Panel, 0.7), C.Panel)
	reveal.Visible = true
	revealScale.Scale = rar.Order >= 5 and 0.45 or 0.6 -- Legendary+ pops in from further away
	revealBand.BackgroundTransparency = 0.1
	TweenService:Create(revealScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	revealShineGrad.Offset = Vector2.new(-1, 0)
	TweenService:Create(revealShineGrad, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Offset = Vector2.new(1, 0) }):Play()
	-- Rare 36 / Epic 60 / Legendary 80 / Mythic 110 sparkles; Epic+ gets a chime; Mythic a screen flash + pillar of light
	sparkleBurst(rar.Color, ({ [3] = 36, [4] = 60, [5] = 80, [6] = 110 })[rar.Order] or 36, rar.Order >= 5)
	-- [MogwartsSounds] a stinger per rarity (Rare, Epic, Legendary, Mythic); the old chime stays as a fallback
	local packed = Sounds.play("reveal_" .. string.lower(item.Rarity), nil, { group = UI.soundGroup("UI") })
	if not packed and rar.Order >= 4 then
		local s = Instance.new("Sound")
		s.SoundId = rar.Order >= 6 and "rbxassetid://9125484367" or "rbxassetid://9114159710"
		s.Volume = rar.Order >= 6 and 0.5 or 0.35 s.PlaybackSpeed = rar.Order >= 6 and 1.1 or 1.6
		s.Parent = gui s:Play()
		game:GetService("Debris"):AddItem(s, 4)
	end
	if rar.Order >= 6 then
		local fl = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rar.Color:Lerp(Color3.new(1, 1, 1), 0.6), BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 39 }, gui)
		TweenService:Create(fl, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
		game:GetService("Debris"):AddItem(fl, 0.9)
		local c = player.Character
		local root = c and c:FindFirstChild("HumanoidRootPart")
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if root and hum then
			local ok, VFX = pcall(require, RS.WizardShared:FindFirstChild("SpellFX"))
			if ok and VFX then VFX.Pillar(root.Position - Vector3.new(0, hum.HipHeight + root.Size.Y / 2, 0), rar.Color, 80, 1.4) end
		end
		-- the banner shimmers through colours for Mythic
		task.spawn(function()
			local t0 = os.clock()
			while id == revealId and os.clock() - t0 < 2.3 do
				local h = (os.clock() * 0.5) % 1
				revealStroke.Color = Color3.fromHSV(h, 0.55, 1)
				revealTier.TextColor3 = Color3.fromHSV((h + 0.1) % 1, 0.4, 1)
				task.wait()
			end
		end)
	end
	task.delay(2.2, function()
		if id ~= revealId then return end
		local tw = TweenService:Create(revealScale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.85 })
		tw:Play()
		tw.Completed:Connect(function() if id == revealId then reveal.Visible = false end end)
	end)
end

text(page, { Position = UDim2.fromOffset(26, 16), Size = UDim2.fromOffset(260, 40), Text = "Grimoire", FontFace = F.Title, TextSize = 34, TextColor3 = C.Ink, ZIndex = 24 })
local nameLbl = text(page, { Position = UDim2.fromOffset(28, 54), Size = UDim2.fromOffset(280, 18), Text = "", FontFace = F.Serif, TextSize = 13, TextColor3 = C.InkSoft, ZIndex = 24 })
-- wax-seal reroll counter
local seal = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -52, 0, 16), Size = UDim2.fromOffset(58, 58), BackgroundColor3 = Color3.fromRGB(128, 30, 36), BorderSizePixel = 0, ZIndex = 24 }, page)
UI.corner(seal, UDim.new(1, 0))
new("UIGradient", { Rotation = 45, Color = ColorSequence.new(Color3.fromRGB(156, 44, 48), Color3.fromRGB(96, 20, 26)) }, seal)
UI.stroke(seal, Color3.fromRGB(80, 16, 22), 0.2, 2)
local rerollCount = text(seal, { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 26), Text = "0", FontFace = F.SerifBold, TextSize = 20, TextColor3 = C.GoldHi, TextXAlignment = Enum.TextXAlignment.Center, TextScaled = false, ZIndex = 25 })
text(seal, { Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 12), Text = "REROLLS", FontFace = F.SansBold, TextSize = 8, TextColor3 = C.Parchment, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 25 })
UI.rule(page, { Position = UDim2.fromOffset(26, 84), Size = UDim2.new(1, -52, 0, 1), BackgroundColor3 = C.GoldDim, ZIndex = 24 })

-- ===== TABS: Magic / Appearance / Outfits =====
local TABS = Config.RerollTabs or { "Magic", "Appearance", "Outfits" }
local TAB_HINT = { Magic = "Affinity, wand, stance and body", Appearance = "Face, hair and features", Outfits = "Uniforms, robes and skirts" }
local tabBar = new("Frame", { Position = UDim2.fromOffset(22, 94), Size = UDim2.new(1, -44, 0, 44), BackgroundTransparency = 1, ZIndex = 24 }, page)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom }, tabBar)
local tabHint = text(page, { Position = UDim2.fromOffset(26, 140), Size = UDim2.new(1, -52, 0, 16), Text = "", FontFace = F.Serif, TextSize = 11, TextColor3 = C.InkSoft, ZIndex = 24 })
local tabButtons, lists = {}, {}
for i, name in ipairs(TABS) do
	local b = new("TextButton", { LayoutOrder = i, Size = UDim2.new(1 / #TABS, -4, 0, 38), BackgroundColor3 = C.ParchmentDark, BorderSizePixel = 0, AutoButtonColor = false,
		Text = "", ZIndex = 25 }, tabBar)
	UI.corner(b, 8)
	local st = UI.stroke(b, C.GoldDim, 0.4, 1)
	local lbl = text(b, { Size = UDim2.fromScale(1, 1), Text = name, FontFace = F.Title, TextSize = 19, TextColor3 = C.Ink, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 26 })
	local key = UI.keycap(b, tostring(i), { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(16, 16), ZIndex = 26 })
	for _, d in ipairs(key:GetDescendants()) do if d:IsA("GuiObject") then d.ZIndex = 27 end if d:IsA("TextLabel") then d.TextSize = 9 end end
	tabButtons[name] = { b = b, st = st, lbl = lbl }
	local l = new("ScrollingFrame", { Name = "List_" .. name, Position = UDim2.fromOffset(18, 160), Size = UDim2.new(1, -30, 1, -226), BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3, ScrollBarImageColor3 = C.InkSoft, ScrollBarImageTransparency = 0.3, ScrollingDirection = Enum.ScrollingDirection.Y, VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar, Visible = false, ZIndex = 24 }, page)
	UI.pad(l, 6, 2)
	new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, l)
	lists[name] = l
end
local currentTab
local function setTab(name, instant)
	if not lists[name] then name = TABS[1] end
	currentTab = name
	player:SetAttribute("GrimoireTab", name)
	for n, t in pairs(tabButtons) do
		local on = n == name
		local ti = TweenInfo.new(instant and 0 or 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(t.b, ti, { BackgroundColor3 = on and C.Burgundy or C.ParchmentDark, Size = UDim2.new(1 / #TABS, -4, 0, on and 44 or 38) }):Play()
		TweenService:Create(t.lbl, ti, { TextColor3 = on and C.GoldHi or C.Ink }):Play()
		t.st.Color = on and C.Gold or C.GoldDim
		t.st.Transparency = on and 0.1 or 0.4
		lists[n].Visible = on
	end
	tabHint.Text = TAB_HINT[name] or ""
end
for name, t in pairs(tabButtons) do t.b.MouseButton1Click:Connect(function() setTab(name) end) end

local rows, profile, busy = {}, nil, false
local oddsHook -- refreshes the odds panel when it's open
local onParchment = UI.onParchment
local function defOf(statId)
	for _, s in ipairs(Config.RerollStats) do if s.Id == statId then return s end end
end
local function rarityOf(statId)
	local def = defOf(statId)
	if not def or not def.List or not profile then return nil end
	local item = Config.Find(def.List, profile[statId])
	return item, Config.Rarities[item.Rarity], Config.ChanceFor(def.List, item.Name, profile.Gender)
end
local function pctText(p) p *= 100 return string.format(p < 1 and "%.2f%%" or "%.1f%%", p) end
-- chance per RARITY tier for one stat (sums the real weights in Config, per your gender), Common first
local function tierOdds(def)
	local sums, counts = {}, {}
	for _, it in ipairs(Config[def.List] or {}) do
		local ok, ch = pcall(Config.ChanceFor, def.List, it.Name, profile and profile.Gender)
		if ok and ch and ch > 0 then sums[it.Rarity] = (sums[it.Rarity] or 0) + ch counts[it.Rarity] = (counts[it.Rarity] or 0) + 1 end
	end
	local rs = {}
	for name, r in pairs(Config.Rarities) do if sums[name] then table.insert(rs, { name = name, r = r, p = sums[name], n = counts[name] }) end end
	table.sort(rs, function(a, b) return a.r.Order < b.r.Order end)
	return rs
end

-- ===== OUTFITS: a gallery of every outfit you can get (current one outlined) =====
local gallery = new("Frame", { Name = "Gallery", LayoutOrder = 900, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 24 }, lists.Outfits or lists[TABS[#TABS]])
text(gallery, { Size = UDim2.new(1, 0, 0, 26), Text = "Wardrobe of the Academy", FontFace = F.Title, TextSize = 17, TextColor3 = C.Burgundy, TextYAlignment = Enum.TextYAlignment.Bottom, ZIndex = 25 })
local grid = new("Frame", { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 24 }, gallery)
new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 74), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
new("UIPadding", { PaddingBottom = UDim.new(0, 8) }, grid)
local outfitCards = {}
local outfitSkirt = {}
for _, r in ipairs(Config.Robes) do outfitSkirt[r.Name] = r.Skirt == true end
do
	local robes = table.clone(Config.Robes)
	table.sort(robes, function(a, b)
		local ra, rb = Config.Rarities[a.Rarity].Order, Config.Rarities[b.Rarity].Order
		if ra ~= rb then return ra < rb end
		return a.Name < b.Name
	end)
	for i, r in ipairs(robes) do
		local rar = Config.Rarities[r.Rarity]
		local card = new("Frame", { LayoutOrder = i, BackgroundColor3 = C.ParchmentDark, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 25 }, grid)
		UI.corner(card, 8)
		local st = UI.stroke(card, onParchment(rar.Color), 0.55, 1)
		-- little drawn uniform: body block, trim band, tie stripe, and a hat shape if it has one
		local fig = new("Frame", { Position = UDim2.fromOffset(8, 10), Size = UDim2.fromOffset(34, 50), BackgroundTransparency = 1, ZIndex = 26 }, card)
		local body = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(28, 30), BackgroundColor3 = r.Body or C.Panel, BorderSizePixel = 0, ZIndex = 26 }, fig)
		UI.corner(body, 4)
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.fromOffset(4, 18), BackgroundColor3 = r.Tie or C.Gold, BorderSizePixel = 0, ZIndex = 27 }, body)
		new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -3), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = r.Trim or C.Gold, BorderSizePixel = 0, ZIndex = 27 }, body)
		new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -30), Size = UDim2.fromOffset(14, 12), BackgroundColor3 = Color3.fromRGB(200, 150, 112), BorderSizePixel = 0, ZIndex = 26 }, fig)
		-- witch look for this outfit: a pleated skirt (when the outfit has one) and a bow instead of the tie
		local skirtF = new("Frame", { Name = "Skirt", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 2), Size = UDim2.fromOffset(34, 11), BackgroundColor3 = r.SkirtColor or r.Body or C.Panel, BorderSizePixel = 0, ZIndex = 28, Visible = false }, fig)
		UI.corner(skirtF, 3)
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = r.Plaid or r.Trim or C.Gold, BorderSizePixel = 0, ZIndex = 29 }, skirtF)
		for k = 1, 3 do new("Frame", { Position = UDim2.new(k / 4, 0, 0, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = (r.SkirtColor or r.Body or C.Panel):Lerp(Color3.new(0, 0, 0), 0.35), BorderSizePixel = 0, ZIndex = 29 }, skirtF) end
		local bowF = new("Frame", { Name = "Bow", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -30), Size = UDim2.fromOffset(12, 5), BackgroundTransparency = 1, ZIndex = 28, Visible = false }, fig)
		for _, sx in ipairs({ 0, 1 }) do new("Frame", { AnchorPoint = Vector2.new(sx, 0), Position = UDim2.fromScale(sx, 0), Size = UDim2.fromOffset(5, 5), Rotation = 45, BackgroundColor3 = r.Tie or C.Gold, BorderSizePixel = 0, ZIndex = 28 }, bowF) end
		body:SetAttribute("SkirtOutfit", r.Skirt == true)
		body.Name = "Body"
		text(card, { Position = UDim2.fromOffset(50, 8), Size = UDim2.new(1, -56, 0, 30), Text = r.Name, FontFace = F.SerifBold, TextSize = 12, TextWrapped = true, TextColor3 = C.Ink, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 26 })
		local pill = UI.rarityPill(card, { Position = UDim2.fromOffset(50, 42), Size = UDim2.fromOffset(0, 13), ZIndex = 26 })
		UI.setRarityPill(pill, r.Rarity, rar.Color)
		local ch = text(card, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 42), Size = UDim2.fromOffset(60, 13), Text = "", FontFace = F.Sans, TextSize = 10, TextColor3 = C.InkSoft, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 26 })
		local tag = text(card, { Position = UDim2.fromOffset(50, 56), Size = UDim2.fromOffset(80, 11), Text = "", FontFace = F.SansBold, TextSize = 9, TextColor3 = C.Burgundy, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 26 })
		outfitCards[r.Name] = { card = card, st = st, ch = ch, tag = tag, rar = rar }
	end
end
local function refreshGallery()
	for name, o in pairs(outfitCards) do
		local gg = profile and profile.Gender or player:GetAttribute("Gender")
		local witch = gg == "F" or gg == "Female"
		local fig = o.card:FindFirstChild("Frame")
		for _, f in ipairs(o.card:GetDescendants()) do
			if f.Name == "Skirt" then f.Visible = witch and outfitSkirt[name] == true
			elseif f.Name == "Bow" then f.Visible = witch end
		end
		local on = profile and profile.Robe == name
		o.ch.Text = profile and pctText(Config.ChanceFor("Robes", name, profile.Gender)) or ""
		o.st.Color = on and C.Burgundy or onParchment(o.rar.Color)
		o.st.Transparency = on and 0 or 0.55
		o.st.Thickness = on and 2 or 1
		o.card.BackgroundTransparency = on and 0.05 or 0.35
		o.tag.Text = on and "WEARING" or ""
	end
end

local function refresh()
	if not profile then return end
	rerollCount.Text = tostring(profile.Rerolls)
	nameLbl.Text = profile.FirstName .. " " .. profile.LastName .. "  ·  " .. (player:GetAttribute("Affinity") or "") .. " House"
	for _, s in ipairs(Config.RerollStats) do
		local r = rows[s.Id]
		if r then
			if s.Id == "Name" then
				r.value.Text = profile.FirstName .. " " .. profile.LastName
				r.value.TextColor3 = C.Ink
				r.sub.Text = "Your first name stays, the family name can change"
				r.sub.TextColor3 = C.InkSoft
				r.gem.BackgroundColor3 = C.GoldDim
				r.pill.Visible = false
			else
				local item, rar, chance = rarityOf(s.Id)
				if item then
					r.value.Text = item.Name
					r.value.TextColor3 = rar.Order <= 1 and C.Ink or onParchment(rar.Color)
					local extra = s.Id == "Affinity" and ("  ·  " .. item.Perk) or ""
					r.sub.Text = pctText(chance) .. " for this exact one" .. extra
					r.sub.TextColor3 = onParchment(rar.Color):Lerp(C.InkSoft, 0.5)
					r.gem.BackgroundColor3 = onParchment(rar.Color)
					r.pill.Visible = true
					UI.setRarityPill(r.pill, item.Rarity, rar.Color)
				end
			end
		end
	end
	refreshGallery()
	if oddsHook then oddsHook() end
end

-- odds tooltip, shown beside the book while hovering a row
local tip = new("Frame", { Name = "OddsTip", Size = UDim2.fromOffset(250, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.Parchment, BorderSizePixel = 0, Visible = false, ZIndex = 40 }, book)
UI.corner(tip, 8) UI.stroke(tip, C.Gold, 0.2, 1.5) UI.shadow(tip, 12, 0.5) UI.pad(tip, 12, 10)
new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, tip)
local BOOK_H = 620
local function showTip(row, def)
	for _, c in ipairs(tip:GetChildren()) do if c:IsA("GuiObject") and c.Name ~= "Shadow" then c:Destroy() end end
	if not def.List then tip.Visible = false return end
	text(tip, { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 20), Text = def.Label .. " by rarity", FontFace = F.Title, TextSize = 17, TextColor3 = C.Ink, ZIndex = 41 })
	local rs = tierOdds(def)
	local top = 0
	for _, e in ipairs(rs) do top = math.max(top, e.p) end
	local cur = profile and Config.Find(def.List, profile[def.Id])
	for i, e in ipairs(rs) do
		local col = UI.onParchment(e.r.Color)
		local mine = cur and cur.Rarity == e.name
		local line = new("Frame", { LayoutOrder = i, Size = UDim2.new(1, 0, 0, 20), BackgroundColor3 = col, BackgroundTransparency = mine and 0.82 or 1, BorderSizePixel = 0, ZIndex = 41 }, tip)
		UI.corner(line, 4)
		text(line, { Position = UDim2.fromOffset(4, 0), Size = UDim2.new(0, 70, 1, 0), Text = e.name, FontFace = mine and F.SerifBold or F.Serif, TextSize = 12, TextColor3 = e.r.Order <= 1 and C.Ink or col, ZIndex = 42 })
		-- bar length = share of the biggest tier (so small tiers still read), exact % on the right
		local track = new("Frame", { Position = UDim2.new(0, 76, 0.5, -4), Size = UDim2.new(1, -128, 0, 8), BackgroundColor3 = C.ParchmentDark, BorderSizePixel = 0, ZIndex = 41 }, line)
		UI.corner(track, 4)
		local bar = new("Frame", { Size = UDim2.new(math.max(0.03, e.p / top), 0, 1, 0), BackgroundColor3 = col, BorderSizePixel = 0, ZIndex = 42 }, track)
		UI.corner(bar, 4)
		text(line, { Size = UDim2.new(1, -4, 1, 0), Text = pctText(e.p), FontFace = mine and F.SansBold or F.Sans, TextSize = 12, TextColor3 = C.Ink, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 42 })
	end
	text(tip, { LayoutOrder = 50, Size = UDim2.new(1, 0, 0, 26), Text = "Chance to land on each rarity. The small % under a row is for that exact one.", TextWrapped = true, FontFace = F.Sans, TextSize = 10, TextColor3 = C.InkSoft, ZIndex = 41 })
	local sc = math.max(0.01, book.AbsoluteSize.Y / BOOK_H)
	tip.Position = UDim2.new(1, 12, 0, math.clamp((row.AbsolutePosition.Y - book.AbsolutePosition.Y) / sc - 10, 10, BOOK_H - 220))
	tip.Visible = true
end

local order = {}
for i, s in ipairs(Config.RerollStats) do
	local tabName = lists[s.Tab or ""] and s.Tab or "Appearance"
	order[tabName] = (order[tabName] or 0) + 1
	local row = new("Frame", { LayoutOrder = order[tabName], Size = UDim2.new(1, 0, 0, 54), BackgroundColor3 = C.ParchmentDark, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 24 }, lists[tabName])
	UI.corner(row, 6)
	local gem = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(10, 27), Size = UDim2.fromOffset(7, 7), BackgroundColor3 = C.GoldDim, BorderSizePixel = 0, Rotation = 45, ZIndex = 25 }, row)
	local cap = new("Frame", { Position = UDim2.fromOffset(24, 3), Size = UDim2.new(1, -130, 0, 14), BackgroundTransparency = 1, ZIndex = 25 }, row)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, cap)
	text(cap, { LayoutOrder = 1, Size = UDim2.fromOffset(0, 12), AutomaticSize = Enum.AutomaticSize.X, Text = s.Label:upper(), FontFace = F.SansBold, TextSize = 9, TextColor3 = C.InkSoft, ZIndex = 25 })
	local pill = UI.rarityPill(cap, { LayoutOrder = 2, Size = UDim2.fromOffset(0, 13), ZIndex = 25, Visible = false })
	row.MouseEnter:Connect(function() if book.Visible then showTip(row, s) end end)
	row.MouseLeave:Connect(function() tip.Visible = false end)
	local value = text(row, { Position = UDim2.fromOffset(24, 18), Size = UDim2.new(1, -130, 0, 18), Text = "...", FontFace = F.SerifBold, TextSize = 15, TextColor3 = C.Ink, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 25 })
	local sub = text(row, { Position = UDim2.fromOffset(24, 36), Size = UDim2.new(1, -130, 0, 12), Text = "", FontFace = F.Sans, TextSize = 10, TextColor3 = C.InkSoft, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 25 })
	local btn = UI.inkButton(row, "Reroll", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(88, 44), ZIndex = 25 })
	new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 20, 1, 1), Size = UDim2.new(1, -30, 0, 1), BackgroundColor3 = C.GoldDim, BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 25 }, row)
	btn.MouseButton1Click:Connect(function()
		if busy then return end
		busy = true
		btn.Text = "..."
		Sounds.play("reroll", nil, { group = UI.soundGroup("UI") }) -- [MogwartsSounds] 
		local ok, res, err = pcall(function() return Remotes.Reroll:InvokeServer(s.Id) end)
		busy = false
		btn.Text = "Reroll"
		if ok and res then
			profile = res
			refresh()
			local item, rar = rarityOf(s.Id)
			row.BackgroundColor3 = rar and onParchment(rar.Color) or C.GoldDim
			row.BackgroundTransparency = 0.75
			TweenService:Create(row, TweenInfo.new(0.9), { BackgroundTransparency = 1 }):Play()
			local vs = value:FindFirstChild("Pop") or new("UIScale", { Name = "Pop" }, value)
			vs.Scale = 1.18
			TweenService:Create(vs, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			if rar and rar.Order >= 3 then revealItem(s.Label, item, rar) end
			if rar and rar.Order < 3 then Sounds.play("reveal_common", nil, { group = UI.soundGroup("UI") }) end -- [MogwartsSounds] 
			-- let the server rebuild the look, then refresh the Looking Glass (with a soft fade)
			requestMirror(false)
		else
			notify(tostring(err or "Cannot reroll right now"), C.Danger)
			Sounds.play("ui_denied", nil, { group = UI.soundGroup("UI") }) -- [MogwartsSounds] 
		end
	end)
	rows[s.Id] = { value = value, sub = sub, gem = gem, pill = pill }
end
setTab(player:GetAttribute("GrimoireTab") or TABS[1], true)

-- ===== ODDS CHART: chance per rarity for every stat on this tab =====
local oddsPanel = new("ScrollingFrame", { Name = "OddsPanel", Position = UDim2.fromOffset(18, 160), Size = UDim2.new(1, -30, 1, -226), BackgroundColor3 = C.Parchment, BackgroundTransparency = 0, BorderSizePixel = 0,
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3, ScrollBarImageColor3 = C.InkSoft, ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false, ZIndex = 30 }, page)
UI.pad(oddsPanel, 8, 4)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, oddsPanel)
local oddsBtn = UI.inkButton(page, "Odds", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -24, 0, 148), Size = UDim2.fromOffset(64, 24), TextSize = 12, ZIndex = 27 })
local function buildOdds()
	for _, c in ipairs(oddsPanel:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
	text(oddsPanel, { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 22), Text = (currentTab or "") .. " odds by rarity", FontFace = F.Title, TextSize = 18, TextColor3 = C.Burgundy, ZIndex = 31 })
	local n = 0
	for _, def in ipairs(Config.RerollStats) do
		local tabName = lists[def.Tab or ""] and def.Tab or "Appearance"
		if tabName == currentTab and def.List then
			n += 1
			local rs = tierOdds(def)
			local cur = profile and Config.Find(def.List, profile[def.Id])
			local card = new("Frame", { LayoutOrder = n, Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = C.ParchmentDark, BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 31 }, oddsPanel)
			UI.corner(card, 6)
			text(card, { Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 16), Text = def.Label:upper(), FontFace = F.SansBold, TextSize = 10, TextColor3 = C.InkSoft, ZIndex = 32 })
			-- stacked bar: each rarity's share; tiny tiers keep a sliver so they stay visible
			local bar = new("Frame", { Position = UDim2.fromOffset(10, 22), Size = UDim2.new(1, -20, 0, 12), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 32 }, card)
			UI.corner(bar, 6)
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder }, bar)
			local total = 0
			for _, e in ipairs(rs) do total += math.max(e.p, 0.012) end
			for i, e in ipairs(rs) do
				local seg = new("Frame", { LayoutOrder = i, Size = UDim2.new(math.max(e.p, 0.012) / total, 0, 1, 0), BackgroundColor3 = UI.onParchment(e.r.Color), BorderSizePixel = 0, ZIndex = 32 }, bar)
				if cur and cur.Rarity == e.name then UI.stroke(seg, C.Ink, 0, 2) end
			end
			local leg = new("Frame", { Position = UDim2.fromOffset(10, 38), Size = UDim2.new(1, -20, 0, 18), BackgroundTransparency = 1, ZIndex = 32 }, card)
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, leg)
			for i, e in ipairs(rs) do
				local mine = cur and cur.Rarity == e.name
				text(leg, { LayoutOrder = i, Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, Text = e.name:sub(1, 3) .. " " .. pctText(e.p),
					FontFace = mine and F.SansBold or F.Sans, TextSize = 10, TextColor3 = e.r.Order <= 1 and C.Ink or UI.onParchment(e.r.Color), ZIndex = 32 })
			end
		end
	end
	text(oddsPanel, { LayoutOrder = 999, Size = UDim2.new(1, 0, 0, 30), Text = "Each bar is the chance to land on that rarity when you reroll. Your current rarity is outlined.", TextWrapped = true, FontFace = F.Sans, TextSize = 10, TextColor3 = C.InkSoft, ZIndex = 31 })
end
local function showOdds(on)
	oddsPanel.Visible = on
	oddsBtn.Text = on and "Back" or "Odds"
	if on then buildOdds() end
end
oddsBtn.MouseButton1Click:Connect(function() showOdds(not oddsPanel.Visible) end)
oddsHook = function() if oddsPanel.Visible then buildOdds() end end
for _, t in pairs(tabButtons) do t.b.MouseButton1Click:Connect(function() task.defer(oddsHook) end) end
UIS.InputBegan:Connect(function(io, gpe) if not gpe and book.Visible and (io.KeyCode == Enum.KeyCode.One or io.KeyCode == Enum.KeyCode.Two or io.KeyCode == Enum.KeyCode.Three) then task.defer(oddsHook) end end)
UIS.InputBegan:Connect(function(io, gpe)
	if gpe or not book.Visible then return end
	local n = ({ [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3 })[io.KeyCode]
	if n and TABS[n] then setTab(TABS[n]) end
end)

-- code redemption along the bottom of the page
local codeBox = new("TextBox", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 22, 1, -18), Size = UDim2.new(1, -160, 0, 34), BackgroundColor3 = C.ParchmentDark, BorderSizePixel = 0,
	FontFace = F.Serif, TextSize = 14, TextColor3 = C.Ink, PlaceholderText = "Enter a code", PlaceholderColor3 = C.InkSoft, Text = "", ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 25 }, page)
UI.corner(codeBox, 6) UI.stroke(codeBox, C.GoldDim, 0.4, 1) UI.pad(codeBox, 10, 0)
local redeem = UI.inkButton(page, "Redeem", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -22, 1, -18), Size = UDim2.fromOffset(110, 34), ZIndex = 25 })
redeem.MouseButton1Click:Connect(function()
	local ok, res, msg = pcall(function() return Remotes.RedeemCode:InvokeServer(codeBox.Text) end)
	if ok and res then
		profile = res refresh() codeBox.Text = ""
		notify(msg or "Redeemed")
		Sounds.play("code_redeem", nil, { group = UI.soundGroup("UI") }) -- [MogwartsSounds] 
	else
		notify(tostring(msg or "Code not found"), C.Danger)
		Sounds.play("ui_denied", nil, { group = UI.soundGroup("UI") }) -- [MogwartsSounds] 
	end
end)

local function setGrimoire(open)
	if open then
		UI.claim(gui, "Grimoire")
		UI.popIn(book)
		mirrorYaw = FRONT
		showMirror = false
		layoutGlass()
		requestMirror(true)
		local ok, res = pcall(function() return Remotes.GetProfile:InvokeServer() end)
		if ok and res then profile = res refresh() end
	elseif book.Visible then
		UI.popOut(book)
		if gui:GetAttribute("OpenMenu") == "Grimoire" then gui:SetAttribute("OpenMenu", nil) end
	end
end
closeButton(book, function() setGrimoire(false) end)
UI.onOtherMenu(gui, "Grimoire", function() if book.Visible then book.Visible = false end end)
toggleMenu.Event:Connect(function(name) if name == "Grimoire" then setGrimoire(not book.Visible) end end)
UIS.InputBegan:Connect(function(io, gpe)
	if gpe then return end
	if io.KeyCode == Enum.KeyCode.G then setGrimoire(not book.Visible) end
end)
Remotes.ProfileChanged.OnClientEvent:Connect(function(p) profile = p refresh() end)
task.spawn(function()
	for _ = 1, 10 do
		local ok, res = pcall(function() return Remotes.GetProfile:InvokeServer() end)
		if ok and res then profile = res refresh() break end
		task.wait(1)
	end
end)

-- ================= INTERACTION PROMPTS (doors, seats) in the same style =================
local function customStyle(d) if d:IsA("ProximityPrompt") then d.Style = Enum.ProximityPromptStyle.Custom end end
for _, d in ipairs(workspace:GetDescendants()) do customStyle(d) end
workspace.DescendantAdded:Connect(customStyle)
local promptGuis = {}
PPS.PromptShown:Connect(function(prompt, inputType)
	if prompt.Style == Enum.ProximityPromptStyle.Default then prompt.Style = Enum.ProximityPromptStyle.Custom end
	local bb = new("BillboardGui", { Name = "Prompt", AlwaysOnTop = true, LightInfluence = 0, Size = UDim2.fromOffset(220, 40), StudsOffset = Vector3.new(0, 0.5, 0), ResetOnSpawn = false }, player:WaitForChild("PlayerGui"))
	bb.Adornee = prompt.Parent
	local holder = new("TextButton", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, Text = "", AutoButtonColor = false }, bb)
	UI.glass(holder, { radius = 16, transparency = 0.12, strokeT = 0.35 })
	UI.pad(holder, 8, 0)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8) }, holder)
	local key = inputType == Enum.ProximityPromptInputType.Gamepad and prompt.GamepadKeyCode.Name:gsub("Button", "") or (inputType == Enum.ProximityPromptInputType.Touch and "Tap" or UIS:GetStringForKeyCode(prompt.KeyboardKeyCode))
	if key == "" then key = prompt.KeyboardKeyCode.Name end
	UI.keycap(holder, key)
	text(holder, { Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, Text = prompt.ActionText .. ((prompt.ObjectText ~= "") and ("  ·  " .. prompt.ObjectText) or ""), FontFace = F.Serif, TextSize = 13, TextColor3 = C.Text })
	holder.MouseButton1Down:Connect(function() prompt:InputHoldBegin() end)
	holder.MouseButton1Up:Connect(function() prompt:InputHoldEnd() end)
	local sc = new("UIScale", { Scale = 0.85 }, holder)
	TweenService:Create(sc, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	promptGuis[prompt] = bb
	local c c = prompt:GetPropertyChangedSignal("ActionText"):Connect(function() if bb.Parent then local l = holder:FindFirstChildOfClass("TextLabel") if l then l.Text = prompt.ActionText end else c:Disconnect() end end)
end)
PPS.PromptHidden:Connect(function(prompt)
	local bb = promptGuis[prompt]
	if bb then bb:Destroy() promptGuis[prompt] = nil end
end)

-- ================= LIVE UPDATE =================
local AREA_NAMES = { Village = "Mistvale Village", Academy = "Aldermoor Academy", Wilds = "The Wilds" }
local function placeName(pos)
	local best, bestD
	for _, l in ipairs(Locations) do
		local d = (Vector3.new(l.Pos.X, pos.Y, l.Pos.Z) - pos).Magnitude
		if not bestD or d < bestD then best, bestD = l, d end
	end
	if not best then return "Aldermoor" end
	if bestD < 45 then return best.Name end
	return AREA_NAMES[best.Area] or best.Area
end
local function clockText(t)
	local h = math.floor(t) % 24
	local m = math.floor((t - math.floor(t)) * 60)
	local ampm = h >= 12 and "PM" or "AM"
	local h12 = h % 12 if h12 == 0 then h12 = 12 end
	return string.format("%d:%02d %s", h12, m, ampm)
end

local lastNoMana, shownHp, lastSlow = 0, 1, 0
RunService.RenderStepped:Connect(function(dt)
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local root = c and c:FindFirstChild("HumanoidRootPart")
	if h then
		local pct = math.clamp(math.max(0, h.Health) / h.MaxHealth, 0, 1)
		hpFill.Size = UDim2.fromScale(pct, 1)
		if pct < lastHpPct - 0.001 then ghostHold = os.clock() + 0.45 end
		lastHpPct = pct
		if os.clock() > ghostHold then shownHp = shownHp + (pct - shownHp) * math.min(1, dt * 4) end
		if shownHp < pct then shownHp = pct end
		hpGhost.Size = UDim2.fromScale(shownHp, 1)
		local low = pct < 0.3 and h.Health > 0
		if low then
			local pulse = 0.5 + 0.5 * math.sin(os.clock() * 6)
			hpStroke.Color = C.Health:Lerp(Color3.fromRGB(255, 170, 160), pulse)
			hpStroke.Transparency = 0.05 + 0.35 * (1 - pulse)
			lowVig.Visible = true
			lowVig.GroupTransparency = 0.35 + 0.4 * (1 - pulse) + pct
		elseif lowVig.Visible then
			lowVig.Visible = false
			hpStroke.Color = C.Gold
			hpStroke.Transparency = 0.6
		end
		hpCaption.Text = "Vitality  " .. math.floor(math.max(0, h.Health) + 0.5)
	end
	local mana = player:GetAttribute("Mana") or 0
	local maxMana = player:GetAttribute("MaxMana") or Config.MaxMana
	local mp = math.clamp(mana / maxMana, 0, 1)
	mpFill.Size = mpFill.Size:Lerp(UDim2.fromScale(mp, 1), math.min(1, dt * 12))
	local gx = mpGhost.Size.X.Scale
	mpGhost.Size = UDim2.fromScale(gx > mp and (gx + (mp - gx) * math.min(1, dt * 2.5)) or mp, 1)
	local so = (os.clock() * 0.45) % 1.6 - 0.8
	mpShineGrad.Offset = Vector2.new(so * 2, 0)
	local now = workspace:GetServerTimeNow()
	-- charged shot fill (0 → MaxCharge); turns white once fully charged
	local cs = slots.Charge
	if cs and cs.chargeFill then
		local t0 = player:GetAttribute("ChargeStart")
		local ccfg = Config.Spells.Charge
		local fr = t0 and math.clamp((now - t0) / ccfg.MaxCharge, 0, 1) or 0
		cs.chargeFill.Size = UDim2.new(1, -6, fr, fr > 0 and -6 or 0)
		cs.chargeFill.BackgroundColor3 = fr >= ccfg.FullAt and Color3.new(1, 1, 1) or (fr >= ccfg.MinCharge / ccfg.MaxCharge and C.GoldHi or C.GoldDim)
	end
	for name, s in pairs(slots) do
		local ends = player:GetAttribute("CD_" .. name) or 0
		local len = player:GetAttribute("CDLen_" .. name) or 1
		local left = ends - now
		if left > 0 then
			setSweep(s, math.clamp(left / len, 0, 1))
			s.text.Text = left >= 1 and string.format("%d", math.ceil(left)) or string.format("%.1f", left)
			s.wasCd = len > 0.9 -- only flash for real cooldowns, not the bolt's short one
		else
			if s.cd.Visible then setSweep(s, 0) end
			s.text.Text = ""
			if s.wasCd then
				s.wasCd = false
				local affc = Config.Find("Affinities", player:GetAttribute("Affinity") or "").Color
				s.readyStroke.Color = affc:Lerp(Color3.new(1, 1, 1), 0.35)
				s.readyStroke.Transparency = 0
				TweenService:Create(s.readyStroke, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 }):Play()
			end
		end
		local dim = s.mana > mana
		for _, g in ipairs(s.box:GetDescendants()) do
			if g:IsA("Frame") and g.BackgroundTransparency < 1 then g.BackgroundColor3 = dim and C.Faint or C.GoldHi end
			if g:IsA("UIStroke") then g.Color = dim and C.Faint or C.GoldHi end
		end
	end
	local nm = player:GetAttribute("NoMana")
	if nm and nm ~= lastNoMana then lastNoMana = nm notify("Not enough mana", Color3.fromRGB(150, 176, 230)) end
	-- the info pill updates a few times a second
	lastSlow += dt
	if lastSlow > 0.3 then
		lastSlow = 0
		local clk = DayCycle.now()
		timeLbl.Text = clockText(clk)
		setSky(DayCycle.phaseName(clk))
		if root then placeLbl.Text = placeName(root.Position) end
		local aff = player:GetAttribute("Affinity")
		houseLbl.Text = aff and (aff .. " House") or "First Year"
	end
end)
