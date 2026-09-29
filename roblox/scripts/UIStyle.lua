-- Aldermoor UI style: calm, polished magic-school look. Dark walnut glass panels with thin antique-gold
-- trim for the HUD, parchment pages bound in burgundy leather for menus. No emojis.
local TweenService = game:GetService("TweenService")
local UI = {}

-- ===== palette =====
UI.C = {
	Panel = Color3.fromRGB(24, 18, 16),      -- dark walnut
	PanelHi = Color3.fromRGB(40, 30, 25),
	Burgundy = Color3.fromRGB(74, 24, 30),
	BurgundyDark = Color3.fromRGB(46, 14, 20),
	Gold = Color3.fromRGB(201, 168, 106),
	GoldHi = Color3.fromRGB(236, 208, 148),
	GoldDim = Color3.fromRGB(120, 98, 62),
	Text = Color3.fromRGB(242, 232, 210),    -- parchment white
	Muted = Color3.fromRGB(178, 162, 134),
	Faint = Color3.fromRGB(122, 108, 88),
	Parchment = Color3.fromRGB(236, 222, 190),
	ParchmentDark = Color3.fromRGB(214, 194, 152),
	Ink = Color3.fromRGB(56, 38, 28),
	InkSoft = Color3.fromRGB(118, 92, 70),
	Health = Color3.fromRGB(172, 52, 56),
	Mana = Color3.fromRGB(86, 118, 196),
	Candle = Color3.fromRGB(255, 196, 120),
	Danger = Color3.fromRGB(214, 120, 100),
}

-- ===== fonts =====
UI.F = {
	Title = Font.fromEnum(Enum.Font.Fondamento),                                          -- elegant, storybook
	Serif = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular),
	SerifBold = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold),
	Sans = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium),
	SansBold = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
}

function UI.new(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props or {}) do i[k] = v end
	if parent then i.Parent = parent end
	return i
end
local new = UI.new

function UI.corner(p, r) return new("UICorner", { CornerRadius = (typeof(r) == "UDim") and r or UDim.new(0, r or 8) }, p) end
function UI.stroke(p, color, transparency, thickness)
	return new("UIStroke", { Color = color or UI.C.Gold, Transparency = transparency or 0.35, Thickness = thickness or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end
function UI.pad(p, x, y) return new("UIPadding", { PaddingLeft = UDim.new(0, x), PaddingRight = UDim.new(0, x), PaddingTop = UDim.new(0, y or x), PaddingBottom = UDim.new(0, y or x) }, p) end
function UI.text(parent, props)
	local base = { BackgroundTransparency = 1, TextColor3 = UI.C.Text, FontFace = UI.F.Sans, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center }
	for k, v in pairs(props) do base[k] = v end
	return new("TextLabel", base, parent)
end

-- soft drop shadow behind a rounded element (sits one ZIndex below it)
function UI.shadow(p, spread, transparency)
	spread = spread or 10
	local s = new("ImageLabel", {
		Name = "Shadow", BackgroundTransparency = 1, Image = "rbxassetid://6014261993", ImageColor3 = Color3.new(0, 0, 0),
		ImageTransparency = transparency or 0.55, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(49, 49, 450, 450),
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 3), Size = UDim2.new(1, spread * 2, 1, spread * 2),
		ZIndex = math.max(0, p.ZIndex - 1),
	}, p)
	return s
end

-- HUD glass: dark translucent walnut with a whisper of warm gradient and a thin gold outline
function UI.glass(p, opts)
	opts = opts or {}
	p.BackgroundColor3 = UI.C.Panel
	p.BackgroundTransparency = opts.transparency or 0.22
	p.BorderSizePixel = 0
	UI.corner(p, opts.radius or 8)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(UI.C.PanelHi, UI.C.Panel) }, p)
	return UI.stroke(p, UI.C.Gold, opts.strokeT or 0.55, 1)
end

-- thin gold rule with fading ends and a centre diamond
function UI.rule(parent, props)
	local d = new("Frame", { BackgroundColor3 = UI.C.Gold, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1) }, parent)
	for k, v in pairs(props or {}) do d[k] = v end
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.15), NumberSequenceKeypoint.new(1, 1) }) }, d)
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(5, 5), Rotation = 45, BackgroundColor3 = UI.C.GoldHi, BorderSizePixel = 0 }, d)
	return d
end

-- small key badge, e.g. [T]
function UI.keycap(parent, key, props)
	local w = math.max(20, 9 + #key * 8)
	local k = new("Frame", { Size = UDim2.fromOffset(w, 20), BackgroundColor3 = UI.C.Panel, BackgroundTransparency = 0.1, BorderSizePixel = 0 }, parent)
	for kk, v in pairs(props or {}) do k[kk] = v end
	UI.corner(k, 5)
	UI.stroke(k, UI.C.Gold, 0.35, 1)
	UI.text(k, { Size = UDim2.fromScale(1, 1), Text = key, FontFace = UI.F.SansBold, TextSize = 11, TextColor3 = UI.C.GoldHi, TextXAlignment = Enum.TextXAlignment.Center })
	return k
end

-- ===== book / parchment card for menus =====
-- returns (outer, page). outer = burgundy leather binding with gold edge, page = parchment inside
function UI.book(parent, size, props)
	local outer = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = size, BackgroundColor3 = UI.C.Burgundy, BorderSizePixel = 0, ZIndex = 20 }, parent)
	for k, v in pairs(props or {}) do outer[k] = v end
	UI.corner(outer, 12)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(UI.C.Burgundy, UI.C.BurgundyDark) }, outer)
	UI.stroke(outer, UI.C.Gold, 0.25, 1.5)
	UI.shadow(outer, 24, 0.4)
	local page = new("Frame", { Name = "Page", Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 1, -20), BackgroundColor3 = UI.C.Parchment, BorderSizePixel = 0, ZIndex = 21, ClipsDescendants = true }, outer)
	UI.corner(page, 8)
	UI.stroke(page, UI.C.GoldDim, 0.4, 1)
	-- aged-paper feel: warm edges, lighter centre
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, UI.C.ParchmentDark), ColorSequenceKeypoint.new(0.18, UI.C.Parchment), ColorSequenceKeypoint.new(0.82, UI.C.Parchment), ColorSequenceKeypoint.new(1, UI.C.ParchmentDark) }) }, page)
	-- gold corner flourishes on the binding
	for _, a in ipairs({ Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) }) do
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(a.X, a.X == 0 and 5 or -5, a.Y, a.Y == 0 and 5 or -5), Size = UDim2.fromOffset(6, 6), Rotation = 45, BackgroundColor3 = UI.C.GoldHi, BorderSizePixel = 0, ZIndex = 22 }, outer)
	end
	return outer, page
end

-- ink-on-parchment button (for use inside book pages)
function UI.inkButton(parent, text, props)
	local b = new("TextButton", { Size = UDim2.fromOffset(96, 30), BackgroundColor3 = UI.C.Burgundy, BorderSizePixel = 0, AutoButtonColor = false,
		Text = text, FontFace = UI.F.SerifBold, TextSize = 13, TextColor3 = UI.C.GoldHi, ZIndex = 24 }, parent)
	for k, v in pairs(props or {}) do b[k] = v end
	UI.corner(b, 6)
	local st = UI.stroke(b, UI.C.Gold, 0.4, 1)
	UI.hover(b, { BackgroundColor3 = Color3.fromRGB(104, 34, 42) }, { BackgroundColor3 = b.BackgroundColor3 }, st)
	return b, st
end

-- gentle hover / press feedback
function UI.hover(btn, hot, idle, st)
	local ti = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	btn.MouseEnter:Connect(function()
		if hot then TweenService:Create(btn, ti, hot):Play() end
		if st then TweenService:Create(st, ti, { Transparency = 0 }):Play() end
	end)
	btn.MouseLeave:Connect(function()
		if idle then TweenService:Create(btn, ti, idle):Play() end
		if st then TweenService:Create(st, ti, { Transparency = 0.4 }):Play() end
	end)
end

-- open/close with a soft fade + scale. Uses a CanvasGroup-free approach: UIScale + transparency of the root.
function UI.popIn(frame)
	local sc = frame:FindFirstChild("PopScale") or new("UIScale", { Name = "PopScale" }, frame)
	frame.Visible = true
	sc.Scale = 0.94
	TweenService:Create(sc, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end
function UI.popOut(frame)
	local sc = frame:FindFirstChild("PopScale") or new("UIScale", { Name = "PopScale" }, frame)
	local tw = TweenService:Create(sc, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.94 })
	tw:Play()
	tw.Completed:Connect(function() if sc.Scale < 0.95 then frame.Visible = false end end)
end

-- scale a whole screen element to the viewport (1 at 1280x800, smaller on phones)
function UI.autoScale(guiObject, baseW, baseH, minS, maxS)
	local sc = guiObject:FindFirstChild("AutoScale") or new("UIScale", { Name = "AutoScale" }, guiObject)
	local lp = game:GetService("Players").LocalPlayer
	local function fit()
		local vp = workspace.CurrentCamera.ViewportSize
		local user = lp and lp:GetAttribute("UIScale") or 1
		sc.Scale = math.clamp(math.min(vp.X / (baseW or 1280), vp.Y / (baseH or 800)), minS or 0.6, maxS or 1.15) * user
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	if lp then lp:GetAttributeChangedSignal("UIScale"):Connect(fit) end
	return sc
end

-- round burgundy close button with a drawn cross
function UI.closeButton(parent, onClick)
	local x = new("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = UI.C.Burgundy, BackgroundTransparency = 0.1, Text = "", AutoButtonColor = false, ZIndex = 30 }, parent)
	UI.corner(x, UDim.new(1, 0))
	local st = UI.stroke(x, UI.C.Gold, 0.4, 1)
	for _, r in ipairs({ 45, -45 }) do new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(12, 2), Rotation = r, BackgroundColor3 = UI.C.GoldHi, BorderSizePixel = 0, ZIndex = 31 }, x) end
	UI.hover(x, { BackgroundColor3 = Color3.fromRGB(104, 34, 42) }, { BackgroundColor3 = UI.C.Burgundy }, st)
	x.MouseButton1Click:Connect(onClick)
	return x
end

-- only one menu open at a time: menus call UI.claim(gui, name) and listen for others
function UI.claim(gui, name) gui:SetAttribute("OpenMenu", name) end
function UI.onOtherMenu(gui, name, closeFn)
	gui:GetAttributeChangedSignal("OpenMenu"):Connect(function()
		local m = gui:GetAttribute("OpenMenu")
		if m and m ~= name then closeFn() end
	end)
end

-- ===== shared measures (use these instead of magic numbers) =====
UI.S = { Gap = 6, Pad = 12, PagePad = 26, Row = 52 }         -- spacing
UI.R = { Small = 6, Panel = 8, Card = 12, Pill = 15 }          -- corner radii

-- rarity colour as it should read on parchment (a bit inkier) and on dark glass (a bit lighter)
function UI.onParchment(c) return c:Lerp(UI.C.Ink, 0.38) end
function UI.onGlass(c) return c:Lerp(Color3.new(1, 1, 1), 0.2) end

-- small rounded rarity tag, e.g. [ EPIC ]. Returns (frame, label); call UI.setRarityPill to change it.
function UI.rarityPill(parent, props)
	local p = new("Frame", { Name = "RarityPill", Size = UDim2.fromOffset(0, 14), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = UI.C.GoldDim, BorderSizePixel = 0 }, parent)
	for k, v in pairs(props or {}) do p[k] = v end
	UI.corner(p, UDim.new(1, 0))
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, p)
	local l = UI.text(p, { Name = "Label", Size = UDim2.fromOffset(0, 14), AutomaticSize = Enum.AutomaticSize.X, Text = "", FontFace = UI.F.SansBold, TextSize = 9, TextColor3 = UI.C.Parchment, ZIndex = p.ZIndex + 1 })
	return p, l
end
function UI.setRarityPill(pill, rarityName, color, onDark)
	pill.BackgroundColor3 = onDark and color or UI.onParchment(color)
	local l = pill:FindFirstChild("Label")
	if l then l.Text = string.upper(rarityName) l.TextColor3 = onDark and Color3.fromRGB(20, 14, 12) or UI.C.Parchment end
end

-- ===== UI sounds (click / hover), volume follows the player's "UIVolume" setting =====
local SoundService = game:GetService("SoundService")
UI.Sounds = { Click = "rbxassetid://17582213219", Hover = "rbxassetid://3623733749", Open = "rbxassetid://9114159710" }
local soundCache = {}
function UI.soundGroup(name)
	local g = SoundService:FindFirstChild(name)
	if not g then g = new("SoundGroup", { Name = name, Volume = 1 }, SoundService) end
	return g
end
-- [MogwartsSounds] interface sounds come from the sound pack when it is uploaded
local packOk, Pack = pcall(function() return require(script.Parent:FindFirstChild("MogwartsSounds")) end)
local PACK_UI = { Click = "ui_click", Hover = "ui_hover", Open = "ui_open", Close = "ui_close", Tab = "ui_tab", Denied = "ui_denied" }
function UI.play(kind, volume, speed)
	if packOk and Pack and PACK_UI[kind] then
		local rel = volume and volume / (kind == "Hover" and 0.12 or 0.35) or 1
		if Pack.play(PACK_UI[kind], nil, { volume = rel, pitch = speed, group = UI.soundGroup("UI") }) then return end
	end
	local id = UI.Sounds[kind]
	if not id then return end
	local s = soundCache[kind]
	if not s then
		s = new("Sound", { Name = "UI_" .. kind, SoundId = id, SoundGroup = UI.soundGroup("UI") }, SoundService)
		soundCache[kind] = s
	end
	s.Volume = volume or (kind == "Hover" and 0.12 or 0.35)
	s.PlaybackSpeed = speed or 1
	s.TimePosition = 0
	s:Play()
end

-- ===== controls for parchment pages (settings etc.) =====
-- segmented choice: UI.segmented(parent, {"Low","Medium","High"}, current, onChange) -> frame, set(value)
function UI.segmented(parent, options, current, onChange, props)
	local f = new("Frame", { Size = UDim2.fromOffset(240, 28), BackgroundColor3 = UI.C.ParchmentDark, BorderSizePixel = 0 }, parent)
	for k, v in pairs(props or {}) do f[k] = v end
	UI.corner(f, 7) UI.stroke(f, UI.C.GoldDim, 0.4, 1)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	new("UIPadding", { PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 2), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2) }, f)
	local btns = {}
	local function set(v)
		current = v
		for name, b in pairs(btns) do
			local on = name == v
			TweenService:Create(b, TweenInfo.new(0.15), { BackgroundTransparency = on and 0 or 1, TextColor3 = on and UI.C.GoldHi or UI.C.Ink }):Play()
		end
	end
	for i, o in ipairs(options) do
		local b = new("TextButton", { LayoutOrder = i, Size = UDim2.new(1 / #options, -2, 1, 0), BackgroundColor3 = UI.C.Burgundy, BackgroundTransparency = 1, BorderSizePixel = 0, AutoButtonColor = false,
			Text = o, FontFace = UI.F.SerifBold, TextSize = 12, TextColor3 = UI.C.Ink, ZIndex = f.ZIndex + 1 }, f)
		UI.corner(b, 5)
		b.MouseButton1Click:Connect(function() set(o) onChange(o) end)
		btns[o] = b
	end
	set(current)
	return f, set
end
-- on/off switch
function UI.toggle(parent, on, onChange, props)
	local b = new("TextButton", { Size = UDim2.fromOffset(46, 24), BackgroundColor3 = UI.C.ParchmentDark, BorderSizePixel = 0, AutoButtonColor = false, Text = "" }, parent)
	for k, v in pairs(props or {}) do b[k] = v end
	UI.corner(b, UDim.new(1, 0)) UI.stroke(b, UI.C.GoldDim, 0.35, 1)
	local knob = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = UI.C.InkSoft, BorderSizePixel = 0, ZIndex = b.ZIndex + 1 }, b)
	UI.corner(knob, UDim.new(1, 0))
	local function set(v, instant)
		on = v
		local ti = TweenInfo.new(instant and 0 or 0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(knob, ti, { Position = on and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0), BackgroundColor3 = on and UI.C.GoldHi or UI.C.InkSoft }):Play()
		TweenService:Create(b, ti, { BackgroundColor3 = on and UI.C.Burgundy or UI.C.ParchmentDark }):Play()
	end
	b.MouseButton1Click:Connect(function() set(not on) onChange(on) end)
	set(on, true)
	return b, set
end
-- slider: UI.slider(parent, min, max, value, step, onChange, fmt) -> frame, set(value)
function UI.slider(parent, min, max, value, step, onChange, fmt, props)
	local UIS = game:GetService("UserInputService")
	local f = new("Frame", { Size = UDim2.fromOffset(240, 28), BackgroundTransparency = 1 }, parent)
	for k, v in pairs(props or {}) do f[k] = v end
	local track = new("TextButton", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, -52, 0, 6), BackgroundColor3 = UI.C.ParchmentDark, BorderSizePixel = 0, AutoButtonColor = false, Text = "", ZIndex = f.ZIndex + 1 }, f)
	UI.corner(track, UDim.new(1, 0)) UI.stroke(track, UI.C.GoldDim, 0.4, 1)
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = UI.C.Burgundy, BorderSizePixel = 0, ZIndex = f.ZIndex + 2 }, track)
	UI.corner(fill, UDim.new(1, 0))
	local knob = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = UI.C.GoldHi, BorderSizePixel = 0, ZIndex = f.ZIndex + 3 }, track)
	UI.corner(knob, UDim.new(1, 0)) UI.stroke(knob, UI.C.Burgundy, 0, 2)
	local lbl = UI.text(f, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(46, 20), Text = "", FontFace = UI.F.SerifBold, TextSize = 12, TextColor3 = UI.C.Ink, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = f.ZIndex + 1 })
	local function set(v)
		v = math.clamp(math.floor((v - min) / step + 0.5) * step + min, min, max)
		value = v
		local a = (v - min) / (max - min)
		fill.Size = UDim2.fromScale(a, 1)
		knob.Position = UDim2.fromScale(a, 0.5)
		lbl.Text = fmt and fmt(v) or tostring(v)
	end
	local dragging = false
	local function fromX(x)
		local a = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		local old = value
		set(min + a * (max - min))
		if value ~= old then onChange(value) end
	end
	track.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then dragging = true fromX(io.Position.X) end
	end)
	UIS.InputChanged:Connect(function(io)
		if dragging and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then fromX(io.Position.X) end
	end)
	UIS.InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end)
	set(value)
	return f, set
end

return UI
