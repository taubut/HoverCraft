-- ============================================================================
-- HoverCast - mouseover macros without typing them.
--
-- Pick a spell, press a key, done. It writes a real per-character macro:
--
--     #showtooltip Holy Light
--     /cast [@mouseover,help,nodead][@target,help,nodead][@player] Holy Light
--
-- and binds the key straight to that macro, no action bar slot needed.
--
-- It stores nothing of its own. Macros and keybindings are kept by the game,
-- so this keeps working even while addon SavedVariables are not being restored
-- (the Forever beta, 1.60.1). The macro list IS the state: anything named
-- "HC <spell>" containing @mouseover is ours.
--
-- /hover                       open the window
-- /hover Holy Light NUMPAD2    create and bind in one go
-- ============================================================================

local PREFIX = "|cff4cc776HoverCast|r: "
local NAME_PREFIX = "HC "
local MAX_SCAN = 150          -- 120 account + up to 30 character macro slots

local MODES = {
	{ key = "heal", label = "Friendly mouseover > target > you",
	  cond = "[@mouseover,help,nodead][@target,help,nodead][@player]" },
	{ key = "help", label = "Friendly mouseover > target",
	  cond = "[@mouseover,help,nodead][]" },
	{ key = "any",  label = "Any mouseover > target (dispels, damage)",
	  cond = "[@mouseover,exists,nodead][]" },
}

-- ---------------------------------------------------------------------------
-- spellbook
-- ---------------------------------------------------------------------------
local function isHelpful(spellID)
	if not spellID or not (C_Spell and C_Spell.IsSpellHelpful) then return false end
	local ok, v = pcall(C_Spell.IsSpellHelpful, spellID)
	return ok and v and true or false
end

local function playerSpells()
	local out, seen = {}, {}
	local function add(name, icon, id)
		if not name or name == "" or seen[name] then return end
		seen[name] = true
		out[#out + 1] = { name = name, icon = icon, id = id, helpful = isHelpful(id) }
	end

	if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and Enum and Enum.SpellBookSpellBank then
		local bank = Enum.SpellBookSpellBank.Player
		local spellType = Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
		local okN, nLines = pcall(C_SpellBook.GetNumSpellBookSkillLines)
		for i = 1, (okN and nLines or 0) do
			local okL, line = pcall(C_SpellBook.GetSpellBookSkillLineInfo, i)
			if okL and line and not line.shouldHide then
				for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
					local okI, info = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
					if okI and info and not info.isPassive and not info.isOffSpec
						and (spellType == nil or info.itemType == spellType) then
						add(info.name, info.iconID, info.spellID or info.actionID)
					end
				end
			end
		end
	end

	-- helpful spells first, then alphabetical
	table.sort(out, function(a, b)
		if a.helpful ~= b.helpful then return a.helpful end
		return a.name < b.name
	end)
	return out
end

-- ---------------------------------------------------------------------------
-- macros and bindings
-- ---------------------------------------------------------------------------
local function macroName(spell) return (NAME_PREFIX .. spell):sub(1, 16) end

local function macroBody(spell, mode)
	return "#showtooltip " .. spell .. "\n/cast " .. mode.cond .. " " .. spell
end

-- every macro of ours, read straight from the game
local function ourMacros()
	local out = {}
	for i = 1, MAX_SCAN do
		local name, icon, body = GetMacroInfo(i)
		if name and name:sub(1, #NAME_PREFIX) == NAME_PREFIX and body and body:find("@mouseover", 1, true) then
			local spell = body:match("#showtooltip ([^\n]+)") or name:sub(#NAME_PREFIX + 1)
			local keys = { GetBindingKey("MACRO " .. name) }
			out[#out + 1] = { index = i, name = name, icon = icon, spell = spell, keys = keys }
		end
	end
	table.sort(out, function(a, b) return a.spell < b.spell end)
	return out
end

local function clearBindingsFor(name)
	for _, k in ipairs({ GetBindingKey("MACRO " .. name) }) do SetBinding(k) end
end

local function save() SaveBindings(GetCurrentBindingSet()) end

-- returns ok, message
local function createAndBind(spell, key, mode)
	if InCombatLockdown() then return false, "can't change macros or bindings in combat." end
	spell = spell and strtrim(spell) or ""
	if spell == "" then return false, "pick a spell first." end
	if not key or key == "" then return false, "press a key first." end
	mode = mode or MODES[1]

	local name, body = macroName(spell), macroBody(spell, mode)
	if #body > 255 then return false, "that spell name makes the macro too long." end

	local index = GetMacroIndexByName(name)
	local ok, err
	if index and index > 0 then
		ok, err = pcall(EditMacro, index, name, 134400, body)
	else
		ok, err = pcall(CreateMacro, name, 134400, body, true)   -- per-character
	end
	if not ok then
		return false, "couldn't write the macro (" .. tostring(err) .. "). Character macro slots may be full."
	end

	-- one key per macro: drop whatever it was bound to before
	clearBindingsFor(name)
	local was = GetBindingAction(key)
	local okB = SetBindingMacro(key, name)
	if not okB then return false, "the game refused to bind " .. key .. "." end
	save()

	local note = ""
	if was and was ~= "" and was ~= ("MACRO " .. name) then note = "  (" .. key .. " was bound to " .. was .. ")" end
	return true, spell .. " on " .. key .. "." .. note
end

local function deleteOurs(m)
	if InCombatLockdown() then return false, "can't change macros in combat." end
	clearBindingsFor(m.name)
	save()
	local ok, err = pcall(DeleteMacro, m.index)
	if not ok then return false, "couldn't delete: " .. tostring(err) end
	return true, "removed " .. m.spell .. "."
end

-- ---------------------------------------------------------------------------
-- window
-- ---------------------------------------------------------------------------
local win
local ACCENT = { 0.30, 0.78, 0.46 }
local ROW_H, SPELL_ROWS, MACRO_ROWS = 22, 8, 6

local function tex(parent, layer, r, g, b, a)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	t:SetColorTexture(r, g, b, a or 1)
	return t
end

local function flatButton(parent, text, w, h, onClick)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(w, h or 24)
	b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	b:SetBackdropColor(1, 1, 1, 0.05); b:SetBackdropBorderColor(1, 1, 1, 0.16)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.text:SetPoint("CENTER"); b.text:SetText(text)
	b:SetScript("OnEnter", function(s) s:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.8) end)
	b:SetScript("OnLeave", function(s) if not s.capturing then s:SetBackdropBorderColor(1, 1, 1, 0.16) end end)
	if onClick then b:SetScript("OnClick", onClick) end
	return b
end

local function status(msg, good)
	if not win then return end
	win.status:SetText(msg or "")
	if good then win.status:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3]) else win.status:SetTextColor(1, 0.45, 0.4) end
end

local MODIFIERS = { LSHIFT = 1, RSHIFT = 1, LCTRL = 1, RCTRL = 1, LALT = 1, RALT = 1, LMETA = 1, RMETA = 1 }

local function withModifiers(key)
	local p = ""
	if IsAltKeyDown() then p = p .. "ALT-" end
	if IsControlKeyDown() then p = p .. "CTRL-" end
	if IsShiftKeyDown() then p = p .. "SHIFT-" end
	return p .. key
end

local function build()
	if win then return win end
	win = CreateFrame("Frame", "HoverCastWindow", UIParent, "BackdropTemplate")
	win:SetSize(460, 520); win:SetPoint("CENTER")
	win:SetFrameStrata("DIALOG"); win:SetToplevel(true)
	win:SetMovable(true); win:EnableMouse(true); win:SetClampedToScreen(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
	win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	win:SetBackdropColor(0.05, 0.06, 0.08, 0.97); win:SetBackdropBorderColor(ACCENT[1] * 0.6, ACCENT[2] * 0.6, ACCENT[3] * 0.6, 1)
	tinsert(UISpecialFrames, "HoverCastWindow")
	win.mode = 1

	local bar = tex(win, "BACKGROUND", 1, 1, 1, 0.035); bar:SetPoint("TOPLEFT", 1, -1); bar:SetPoint("TOPRIGHT", -1, -1); bar:SetHeight(32)
	local line = tex(win, "ARTWORK", ACCENT[1], ACCENT[2], ACCENT[3], 0.5); line:SetPoint("TOPLEFT", 1, -33); line:SetPoint("TOPRIGHT", -1, -33); line:SetHeight(1)
	local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 14, -9); title:SetText("|cff4cc776HoverCast|r")
	local sub = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sub:SetPoint("LEFT", title, "RIGHT", 10, -1); sub:SetText("pick a spell, press a key")
	local close = CreateFrame("Button", nil, win, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -2, -2)

	-- 1. spell -----------------------------------------------------------
	local h1 = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	h1:SetPoint("TOPLEFT", 14, -46); h1:SetText("1. SPELL")
	local search = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
	search:SetSize(200, 20); search:SetPoint("TOPRIGHT", -16, -42); search:SetAutoFocus(false)
	search:SetScript("OnEscapePressed", function(s) s:SetText(""); s:ClearFocus() end)
	search:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
	search:SetScript("OnTextChanged", function() win.spellOffset = 0; win:RenderSpells() end)
	local ph = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	ph:SetPoint("LEFT", 4, 0); ph:SetText("filter")
	search:HookScript("OnTextChanged", function(s) ph:SetShown(s:GetText() == "") end)
	win.search = search

	local list = CreateFrame("Frame", nil, win, "BackdropTemplate")
	list:SetPoint("TOPLEFT", 14, -68); list:SetPoint("TOPRIGHT", -14, -68); list:SetHeight(SPELL_ROWS * ROW_H + 4)
	list:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	list:SetBackdropColor(0, 0, 0, 0.3); list:SetBackdropBorderColor(1, 1, 1, 0.08)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, d)
		local maxOff = math.max(0, #(win.filtered or {}) - SPELL_ROWS)
		win.spellOffset = math.max(0, math.min(maxOff, (win.spellOffset or 0) - d * 2))
		win:RenderSpells()
	end)
	win.spellRows = {}
	for i = 1, SPELL_ROWS do
		local r = CreateFrame("Button", nil, list)
		r:SetHeight(ROW_H); r:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_H); r:SetPoint("RIGHT", list, "RIGHT", -2, 0)
		r.bg = tex(r, "BACKGROUND", 1, 1, 1, 0); r.bg:SetAllPoints()
		r.hl = tex(r, "HIGHLIGHT", ACCENT[1], ACCENT[2], ACCENT[3], 0.12); r.hl:SetAllPoints()
		r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", 4, 0); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.label:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
		r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); r.tag:SetPoint("RIGHT", -8, 0)
		r:SetScript("OnClick", function(self)
			if self.spell then win.selected = self.spell.name; win:RenderSpells(); win:RenderPick() end
		end)
		win.spellRows[i] = r
	end

	-- 2. key + mode ------------------------------------------------------
	local h2 = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	h2:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -14); h2:SetText("2. KEY AND TARGETING")

	local keyBtn = flatButton(win, "Click, then press a key", 190, 26)
	keyBtn:SetPoint("TOPLEFT", h2, "BOTTOMLEFT", 0, -6)
	keyBtn:RegisterForClicks("AnyUp")
	local function stopCapture()
		keyBtn.capturing = false
		keyBtn:EnableKeyboard(false)
		keyBtn:SetBackdropBorderColor(1, 1, 1, 0.16)
		win:RenderPick()
	end
	local function takeKey(k)
		win.key = withModifiers(k)
		stopCapture()
	end
	keyBtn:SetScript("OnClick", function(self, button)
		if InCombatLockdown() then status("leave combat first."); return end
		if self.capturing then
			-- mouse buttons 3-5 can be bound too; left and right just confirm
			if button == "MiddleButton" then takeKey("BUTTON3")
			elseif button == "Button4" then takeKey("BUTTON4")
			elseif button == "Button5" then takeKey("BUTTON5") end
			return
		end
		self.capturing = true
		self.text:SetText("|cffffd100press a key...|r  (Esc cancels)")
		self:SetBackdropBorderColor(1, 0.82, 0, 1)
		self:EnableKeyboard(true)
		self:SetPropagateKeyboardInput(false)
	end)
	keyBtn:SetScript("OnKeyDown", function(self, k)
		if not self.capturing then return end
		if k == "ESCAPE" then stopCapture(); return end
		if MODIFIERS[k] then return end   -- wait for the real key
		takeKey(k)
	end)
	win.keyBtn = keyBtn

	local modeBtn = flatButton(win, "", 226, 26, function()
		win.mode = (win.mode % #MODES) + 1
		win:RenderPick()
	end)
	modeBtn:SetPoint("LEFT", keyBtn, "RIGHT", 8, 0)
	win.modeBtn = modeBtn

	-- preview + create ---------------------------------------------------
	local preview = CreateFrame("Frame", nil, win, "BackdropTemplate")
	preview:SetPoint("TOPLEFT", keyBtn, "BOTTOMLEFT", 0, -10); preview:SetPoint("RIGHT", win, "RIGHT", -14, 0); preview:SetHeight(40)
	preview:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
	preview:SetBackdropColor(0, 0, 0, 0.35)
	win.previewText = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	win.previewText:SetPoint("TOPLEFT", 8, -6); win.previewText:SetPoint("RIGHT", -8, 0)
	win.previewText:SetJustifyH("LEFT"); win.previewText:SetFont(STANDARD_TEXT_FONT, 10)

	local create = flatButton(win, "Create and bind", 150, 26, function()
		local ok, msg = createAndBind(win.selected, win.key, MODES[win.mode])
		status(msg, ok)
		if ok then win:RenderMacros() end
	end)
	create:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -8)
	create:SetBackdropColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.18)
	win.status = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	win.status:SetPoint("LEFT", create, "RIGHT", 10, 0); win.status:SetPoint("RIGHT", win, "RIGHT", -14, 0)
	win.status:SetJustifyH("LEFT"); win.status:SetWordWrap(true)

	-- 3. existing --------------------------------------------------------
	local h3 = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	h3:SetPoint("TOPLEFT", create, "BOTTOMLEFT", 0, -16); h3:SetText("YOUR HOVER MACROS")
	win.macroRows = {}
	for i = 1, MACRO_ROWS do
		local r = CreateFrame("Frame", nil, win)
		r:SetHeight(ROW_H); r:SetPoint("TOPLEFT", h3, "BOTTOMLEFT", 0, -4 - (i - 1) * ROW_H); r:SetPoint("RIGHT", win, "RIGHT", -14, 0)
		r.bg = tex(r, "BACKGROUND", 1, 1, 1, (i % 2 == 0) and 0.03 or 0); r.bg:SetAllPoints()
		r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 4, 0); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.label:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
		r.key = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); r.key:SetPoint("RIGHT", -70, 0)
		r.del = flatButton(r, "Remove", 58, 18)
		r.del:SetPoint("RIGHT", -2, 0)
		r.del:SetScript("OnClick", function(self)
			if not self.macro then return end
			local ok, msg = deleteOurs(self.macro)
			status(msg, ok)
			win:RenderMacros()
		end)
		win.macroRows[i] = r
	end
	win.emptyMacros = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.emptyMacros:SetPoint("TOPLEFT", h3, "BOTTOMLEFT", 4, -8)
	win.emptyMacros:SetText("None yet.")

	-- renderers ------------------------------------------------------------
	function win:RenderSpells()
		local f = strlower(self.search:GetText() or "")
		self.filtered = {}
		for _, s in ipairs(self.spells or {}) do
			if f == "" or strlower(s.name):find(f, 1, true) then self.filtered[#self.filtered + 1] = s end
		end
		local off = self.spellOffset or 0
		for i, r in ipairs(self.spellRows) do
			local s = self.filtered[off + i]
			r.spell = s
			if s then
				r.icon:SetTexture(s.icon or 134400)
				r.label:SetText(s.name)
				r.tag:SetText(s.helpful and "|cff4cc776helpful|r" or "")
				local sel = (s.name == self.selected)
				r.bg:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], sel and 0.22 or 0)
				r:Show()
			else
				r:Hide()
			end
		end
	end

	function win:RenderPick()
		local mode = MODES[self.mode]
		self.modeBtn.text:SetText(mode.label)
		if not self.keyBtn.capturing then
			self.keyBtn.text:SetText(self.key and ("Key: |cffffd100" .. self.key .. "|r") or "Click, then press a key")
		end
		local spell = self.selected or "<spell>"
		self.previewText:SetText("|cff808080" .. macroBody(spell, mode):gsub("\n", "|n") .. "|r")
	end

	function win:RenderMacros()
		local ms = ourMacros()
		for i, r in ipairs(self.macroRows) do
			local m = ms[i]
			if m then
				r.icon:SetTexture(m.icon or 134400)
				r.label:SetText(m.spell)
				r.key:SetText(#m.keys > 0 and table.concat(m.keys, ", ") or "|cff808080unbound|r")
				r.del.macro = m
				r:Show()
			else
				r:Hide()
			end
		end
		self.emptyMacros:SetShown(#ms == 0)
	end

	function win:Refresh()
		self.spells = playerSpells()
		self:RenderSpells(); self:RenderPick(); self:RenderMacros()
	end

	win:SetScript("OnShow", function(self) self:Refresh() end)
	win:SetScript("OnHide", function(self)
		if self.keyBtn.capturing then self.keyBtn.capturing = false; self.keyBtn:EnableKeyboard(false) end
	end)
	win:Hide()
	return win
end

-- stay current while open
do
	local f = CreateFrame("Frame")
	f:RegisterEvent("SPELLS_CHANGED")
	f:RegisterEvent("UPDATE_MACROS")
	f:RegisterEvent("UPDATE_BINDINGS")
	f:SetScript("OnEvent", function(_, event)
		if not (win and win:IsShown()) then return end
		if event == "SPELLS_CHANGED" then win:Refresh() else win:RenderMacros() end
	end)
end

-- ---------------------------------------------------------------------------
-- slash
-- ---------------------------------------------------------------------------
SLASH_HOVERCAST1 = "/hover"
SLASH_HOVERCAST2 = "/hovercast"
SlashCmdList["HOVERCAST"] = function(msg)
	msg = strtrim(msg or "")
	if msg == "" then
		build()
		if win:IsShown() then win:Hide() else win:Show() end
		return
	end
	-- "/hover Holy Light NUMPAD2": last word is the key, the rest is the spell
	local spell, key = msg:match("^(.-)%s+(%S+)$")
	if not spell or spell == "" then
		print(PREFIX .. "/hover opens the window, or /hover <spell> <key>, e.g. /hover Holy Light NUMPAD2")
		return
	end
	local _, res = createAndBind(spell, key:upper(), MODES[1])
	print(PREFIX .. res)
end
