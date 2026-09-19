-- ============================================================================
-- HoverCast - mouseover macros without typing them.
--
-- Pick a spell, click Create. It writes a real per-character macro:
--
--     #showtooltip Holy Light
--     /cast [@mouseover,help,nodead][@target,help,nodead][@player] Holy Light
--
-- and puts it on your cursor, so the next click on an action bar slot places
-- it. Bind that slot however you normally bind keys.
--
-- It stores nothing of its own. Macros are kept by the game, so this keeps
-- working even while addon SavedVariables are not being restored (the Forever
-- beta, 1.60.1). The macro list IS the state: anything named "HC <spell>"
-- containing @mouseover is ours.
--
-- Spells with ranks ask which one you want; "Max rank" leaves the rank off so
-- the macro always casts your highest. A specific rank uses the same form the
-- spellbook shift-click writes into macros: Holy Light(Rank 1).
--
-- Click one of your macros in the list to load its spell and targeting back
-- into the editor. Picking a damage spell switches to enemy targeting (and a
-- heal switches back) so a new macro starts out pointed the right way.
--
-- "Also start auto-attack" adds /startattack [harm,nodead] above the cast: it
-- only fires when your target is a live enemy, so heals stay error-free.
--
-- /hover                        open the window (also in the addon menu by the minimap)
-- /hover Holy Light             make that macro and put it on the cursor
-- /hover Holy Light(Rank 1)     same, for a specific rank
-- ============================================================================

local PREFIX = "|cff4cc776HoverCast|r: "
local NAME_PREFIX = "HC "
local MAX_SCAN = 150          -- 120 account + up to 30 character macro slots

local MODES = {
	{ key = "heal", short = "heal", friendly = true,
	  label = "Friendly mouseover > target > you",
	  best = "most heals and buffs",
	  help = "Mouse over a friendly player to cast on them. With nobody friendly under your mouse it goes to your target if they're friendly, otherwise to you, so it always casts.",
	  cond = "[@mouseover,help,nodead][@target,help,nodead][@player]" },
	-- target the boss and it heals whoever the boss is hitting
	{ key = "tank", short = "tank", friendly = true,
	  label = "Mouseover > target > boss's target (tank) > you",
	  best = "tank healing",
	  help = "Like heal, with one extra step: if your target is an enemy, it goes to whoever that enemy is attacking. Target the boss and it heals the tank; mouse over anyone else to heal them instead.",
	  cond = "[@mouseover,help,nodead][@target,help,nodead][@targettarget,help,nodead][@player]" },
	{ key = "help", short = "friendly", friendly = true,
	  label = "Friendly mouseover > target",
	  best = "buffs you aim yourself",
	  help = "Mouse over a friendly player to cast on them, otherwise it goes to your target like a normal cast. No extra fallback to you.",
	  cond = "[@mouseover,help,nodead][]" },
	{ key = "any",  short = "any",
	  label = "Any mouseover > target (dispels)",
	  best = "dispels that work on friends and enemies",
	  help = "Casts on whoever is under your mouse, friend or enemy, otherwise on your target.",
	  cond = "[@mouseover,exists,nodead][]" },
	{ key = "harm", short = "enemy",
	  label = "Enemy mouseover > target (damage)",
	  best = "damage spells, DoTs, interrupts",
	  help = "Mouse over an enemy to cast on it without changing your target, otherwise it goes to your target.",
	  cond = "[@mouseover,harm,nodead][]" },
	{ key = "rez",  short = "resurrect", friendly = true,
	  label = "Dead friendly mouseover > target (resurrect)",
	  best = "resurrect spells",
	  help = "Mouse over a dead friendly player to cast on them, otherwise it goes to your target. The other options skip dead players, so resurrect spells need this one.",
	  cond = "[@mouseover,help,dead][]" },
}
local MODE_INDEX = {}
for i, m in ipairs(MODES) do MODE_INDEX[m.key] = i end

-- Which mode a macro body was written with (nil if it was edited by hand).
local function modeOf(body)
	for i, m in ipairs(MODES) do
		if body and body:find(m.cond, 1, true) then return i end
	end
end

-- A damage spell picked while a friendly mode is showing flips to enemy, and a
-- heal picked while enemy is showing flips back. Spells that are both (or
-- neither), and the "any" mode, are left alone.
local function suggestMode(spell, current)
	local m = MODES[current]
	if spell.harmful and not spell.helpful and m.friendly then return MODE_INDEX.harm end
	if spell.helpful and not spell.harmful and m.key == "harm" then return MODE_INDEX.heal end
	return current
end

-- ---------------------------------------------------------------------------
-- spellbook
-- ---------------------------------------------------------------------------
local function spellFlag(fn, spellID)
	if not spellID or not (C_Spell and C_Spell[fn]) then return false end
	local ok, v = pcall(C_Spell[fn], spellID)
	return ok and v and true or false
end

local function subtext(sub, id)
	if (not sub or sub == "") and id and C_Spell and C_Spell.GetSpellSubtext then
		local ok, v = pcall(C_Spell.GetSpellSubtext, id)
		if ok and type(v) == "string" then sub = v end
	end
	return sub or ""
end

-- One entry per spell name. The spellbook lists every rank you know (Blizzard's
-- "show all ranks" option only filters its own display), in ascending order, so
-- each entry gathers its ranks here.
local function playerSpells()
	local out, byName = {}, {}
	local function add(name, icon, id, sub)
		if not name or name == "" then return end
		local e = byName[name]
		if not e then
			e = { name = name, icon = icon, id = id, all = {} }
			byName[name] = e
			out[#out + 1] = e
		end
		e.all[#e.all + 1] = { id = id, sub = subtext(sub, id) }
		e.id = id or e.id   -- keep the highest rank's id
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
						add(info.name, info.iconID, info.spellID or info.actionID, info.subName)
					end
				end
			end
		end
	end

	for _, e in ipairs(out) do
		e.helpful = spellFlag("IsSpellHelpful", e.id)
		e.harmful = spellFlag("IsSpellHarmful", e.id)
		e.ranks = {}
		if #e.all > 1 then
			for i, r in ipairs(e.all) do
				-- subtext should read "Rank N"; if it hasn't loaded yet, book order is rank order
				r.n = tonumber(r.sub:match("%d+")) or i
				if not r.sub:match("%d") then r.sub = "Rank " .. r.n end
				e.ranks[#e.ranks + 1] = r
			end
			table.sort(e.ranks, function(a, b) return a.n < b.n end)
		end
		e.all = nil
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
-- "Holy Light(Rank 1)" -> "Holy Light", "Rank 1"
local function splitRank(spell)
	local base, sub = spell:match("^(.-)%s*%((.-)%)$")
	if base and base ~= "" then return base, sub end
	return spell, nil
end

-- Cut to n bytes without leaving half a UTF-8 character on the end.
local function cut(str, n)
	if #str <= n then return str end
	str = str:sub(1, n)
	local i = #str
	while i > 1 and str:byte(i) >= 0x80 and str:byte(i) < 0xC0 do i = i - 1 end
	local lead = str:byte(i)
	local need = (lead >= 0xF0 and 4) or (lead >= 0xE0 and 3) or (lead >= 0xC0 and 2) or 1
	if #str - i + 1 < need then str = str:sub(1, i - 1) end
	return str
end

-- "Lesser Healing Wave" -> "LHW", "Blessing of Might" -> "BoM"
local function initials(str)
	return (str:gsub("([^%s\128-\191][\128-\191]*)%S*%s*", "%1"))
end

-- Macro names cap at 16 characters, so long spell names can collide:
-- "Greater Blessing of Might" and "...of Kings" both cut to "HC Greater Bless".
-- These are the names a spell may use, best first. The first one is what
-- 1.2 always used ("HC Holy Light", "HC Holy Light r1", "HC LHW r2"), so
-- macros made before keep being found.
local function nameCandidates(spell)
	local base, sub = splitRank(spell)
	local suffix = sub and (" r" .. (sub:match("%d+") or cut(sub, 2))) or ""
	local room = 16 - #NAME_PREFIX - #suffix
	local short = cut(initials(base), room)
	local list, seen = {}, {}
	local function add(b)
		local n = NAME_PREFIX .. b .. suffix
		if b ~= "" and not seen[n] then seen[n] = true; list[#list + 1] = n end
	end
	if not sub or #base <= room then add(cut(base, room)) else add(short) end
	add(short)
	for i = 2, 9 do add(cut(short, room - 1) .. i) end   -- "HC BoS2" when BoS is taken
	return list
end

local ATTACK_LINE = "/startattack [harm,nodead]"

local function macroBody(spell, mode, attack)
	return "#showtooltip " .. spell .. "\n"
		.. (attack and (ATTACK_LINE .. "\n") or "")
		.. "/cast " .. mode.cond .. " " .. spell
end

-- The spell a macro is for, from its #showtooltip line (nil if it has none).
local function tooltipSpell(index)
	local _, _, body = GetMacroInfo(index)
	return body and body:match("#showtooltip ([^\n]+)")
end

local function sameSpell(a, b)
	return a and b and strlower(strtrim(a)) == strlower(strtrim(b))
end

-- The macro this spell already has (name, index), else the first free name
-- (name, nil). Never picks a name held by a macro for anything else.
local function resolveName(spell)
	local cands = nameCandidates(spell)
	for _, n in ipairs(cands) do
		local idx = GetMacroIndexByName(n)
		if idx and idx > 0 and sameSpell(tooltipSpell(idx), spell) then return n, idx end
	end
	for _, n in ipairs(cands) do
		local idx = GetMacroIndexByName(n)
		if not idx or idx == 0 then return n, nil end
	end
end

-- every macro of ours, read straight from the game
local function ourMacros()
	local out = {}
	for i = 1, MAX_SCAN do
		local name, icon, body = GetMacroInfo(i)
		if name and name:sub(1, #NAME_PREFIX) == NAME_PREFIX and body and body:find("@mouseover", 1, true) then
			local spell = body:match("#showtooltip ([^\n]+)") or name:sub(#NAME_PREFIX + 1)
			local keys = { GetBindingKey("MACRO " .. name) }
			out[#out + 1] = { index = i, name = name, icon = icon, spell = spell, keys = keys, mode = modeOf(body),
				attack = body:find("/startattack", 1, true) ~= nil }
		end
	end
	table.sort(out, function(a, b) return a.spell < b.spell end)
	return out
end

local function clearBindingsFor(name)
	for _, k in ipairs({ GetBindingKey("MACRO " .. name) }) do SetBinding(k) end
end

local function save() SaveBindings(GetCurrentBindingSet()) end

local function spellIcon(spell)
	if C_Spell and C_Spell.GetSpellTexture then
		local ok, t = pcall(C_Spell.GetSpellTexture, spell)
		if ok and t then return t end
	end
	return 134400   -- question mark; #showtooltip shows the real icon on the bar anyway
end

-- Put a macro on the cursor so the next click on an action bar slot places it.
local function pickUp(name)
	if InCombatLockdown() then return false end
	return (pcall(PickupMacro, name))
end

-- Create or update the macro. Returns ok, message.
local function createMacro(spell, mode, icon, attack)
	if InCombatLockdown() then return false, "can't change macros in combat." end
	spell = spell and strtrim(spell) or ""
	if spell == "" then return false, "pick a spell first." end
	mode = mode or MODES[1]
	icon = icon or spellIcon(spell)

	local body = macroBody(spell, mode, attack)
	if #body > 255 then return false, "that spell name makes the macro too long." end

	local name, index = resolveName(spell)
	if not name then
		return false, "every macro name HoverCast could give " .. spell .. " is already taken by other macros."
	end
	local ok, err, updated
	if index then
		ok, err = pcall(EditMacro, index, name, icon, body)
		updated = true
	else
		ok, err = pcall(CreateMacro, name, icon, body, true)   -- per-character
	end
	if not ok then
		return false, "couldn't write the macro (" .. tostring(err) .. "). Character macro slots may be full."
	end

	local onCursor = pickUp(name)
	return true, (updated and "Updated " or "Made ") .. spell .. "."
		.. (onCursor and "  It's on your cursor: click an action bar slot." or "")
end

local function deleteOurs(m)
	if InCombatLockdown() then return false, "can't change macros in combat." end
	-- Positions shift whenever any macro is added or removed, so the index from
	-- the list may be stale. Find it again by name and check it's still this spell.
	local index = GetMacroIndexByName(m.name)
	if not index or index == 0 then return false, m.spell .. " is already gone." end
	if not sameSpell(tooltipSpell(index), m.spell) then
		return false, "\"" .. m.name .. "\" isn't the " .. m.spell .. " macro any more; left it alone."
	end
	clearBindingsFor(m.name)
	save()
	local ok, err = pcall(DeleteMacro, index)
	if not ok then return false, "couldn't delete: " .. tostring(err) end
	return true, "removed " .. m.spell .. "."
end

-- ---------------------------------------------------------------------------
-- window
-- ---------------------------------------------------------------------------
local win
local ACCENT = { 0.30, 0.78, 0.46 }
local ROW_H, SPELL_ROWS, MACRO_ROWS = 22, 8, 5

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

-- Thin scroll bar on a list's right edge; hidden when everything fits.
-- Returns update(total, visible, offset).
local function scrollBar(list)
	local track = tex(list, "ARTWORK", 1, 1, 1, 0.05)
	track:SetPoint("TOPRIGHT", -2, -2); track:SetPoint("BOTTOMRIGHT", -2, 2); track:SetWidth(3)
	local thumb = tex(list, "OVERLAY", ACCENT[1], ACCENT[2], ACCENT[3], 0.7)
	thumb:SetWidth(3)
	return function(total, visible, offset)
		local fits = total <= visible
		track:SetShown(not fits); thumb:SetShown(not fits)
		if fits then return end
		local h = list:GetHeight() - 4
		local th = math.max(12, h * visible / total)
		thumb:SetHeight(th)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", -2, -2 - (h - th) * offset / (total - visible))
	end
end

local function clamp(off, total, visible)
	return math.max(0, math.min(math.max(0, total - visible), off or 0))
end

local function build()
	if win then return win end
	win = CreateFrame("Frame", "HoverCastWindow", UIParent, "BackdropTemplate")
	win:SetSize(460, 548); win:SetPoint("CENTER")   -- height is fitted to the content in OnShow
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
	sub:SetPoint("LEFT", title, "RIGHT", 10, -1); sub:SetText("pick a spell, drop it on a bar")
	local close = CreateFrame("Button", nil, win, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -2, -2)

	-- 1. spell -----------------------------------------------------------
	local h1 = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	h1:SetPoint("TOPLEFT", 14, -46); h1:SetText("1. SPELL")
	local search = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
	search:SetSize(200, 20); search:SetPoint("TOPRIGHT", -16, -42); search:SetAutoFocus(false)
	search:SetScript("OnEscapePressed", function(s) s:SetText(""); s:ClearFocus() end)
	search:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
	search:SetScript("OnTextChanged", function(_, typed)
		if typed then win.spellOffset = 0 end
		win:RenderSpells()
	end)
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
		win.spellOffset = clamp((win.spellOffset or 0) - d * 2, #(win.filtered or {}), SPELL_ROWS)
		win:RenderSpells()
	end)
	win.spellScroll = scrollBar(list)
	win.spellRows = {}
	for i = 1, SPELL_ROWS do
		local r = CreateFrame("Button", nil, list)
		r:SetHeight(ROW_H); r:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_H); r:SetPoint("RIGHT", list, "RIGHT", -8, 0)
		r.bg = tex(r, "BACKGROUND", 1, 1, 1, 0); r.bg:SetAllPoints()
		r.hl = tex(r, "HIGHLIGHT", ACCENT[1], ACCENT[2], ACCENT[3], 0.12); r.hl:SetAllPoints()
		r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", 4, 0); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.label:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
		r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); r.tag:SetPoint("RIGHT", -8, 0)
		r:SetScript("OnClick", function(self)
			if self.spell then
				win.selected = self.spell.name
				win.selectedIcon = self.spell.icon
				win.selectedEntry = self.spell
				local mode = suggestMode(self.spell, win.mode)
				if mode ~= win.mode then
					win.mode = mode
					status("Targeting switched to " .. MODES[mode].short .. " for this spell.", true)
				end
				win:RenderSpells(); win:RenderPick()
			end
		end)
		win.spellRows[i] = r
	end

	-- 2. targeting -------------------------------------------------------
	local h2 = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	h2:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -14); h2:SetText("2. TARGETING  |cff606060(click to change, right-click to go back)|r")

	-- What each targeting option does: the current one explained, then all of them.
	local function modeTooltip(owner)
		local cur = MODES[win.mode]
		GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
		GameTooltip:AddLine(cur.label, ACCENT[1], ACCENT[2], ACCENT[3])
		GameTooltip:AddLine(cur.help, 1, 1, 1, true)
		GameTooltip:AddLine("Good for: " .. cur.best, 0.75, 0.75, 0.75, true)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("All options (click to cycle, right-click to go back):", 0.55, 0.55, 0.55, true)
		for i, m in ipairs(MODES) do
			if i == win.mode then
				GameTooltip:AddDoubleLine("> " .. m.short, m.best, ACCENT[1], ACCENT[2], ACCENT[3], ACCENT[1], ACCENT[2], ACCENT[3])
			else
				GameTooltip:AddDoubleLine("   " .. m.short, m.best, 0.85, 0.85, 0.85, 0.55, 0.55, 0.55)
			end
		end
		GameTooltip:Show()
	end

	local helpBtn = flatButton(win, "?", 26, 26)
	helpBtn:SetPoint("TOP", h2, "BOTTOM", 0, -6); helpBtn:SetPoint("RIGHT", win, "RIGHT", -14, 0)
	helpBtn.text:SetFontObject("GameFontNormal")
	helpBtn:HookScript("OnEnter", modeTooltip)
	helpBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

	local modeBtn = flatButton(win, "", 100, 26, function(self, button)
		local step = (button == "RightButton") and -1 or 1
		win.mode = ((win.mode - 1 + step) % #MODES) + 1
		win:RenderPick()
		if GameTooltip:IsOwned(self) then modeTooltip(self) end
	end)
	modeBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	modeBtn:SetPoint("TOPLEFT", h2, "BOTTOMLEFT", 0, -6); modeBtn:SetPoint("RIGHT", helpBtn, "LEFT", -6, 0)
	modeBtn:HookScript("OnEnter", modeTooltip)
	modeBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
	win.modeBtn = modeBtn

	local atk = CreateFrame("Button", nil, win)
	atk:SetSize(300, 18); atk:SetPoint("TOPLEFT", modeBtn, "BOTTOMLEFT", 0, -8)
	atk.box = CreateFrame("Frame", nil, atk, "BackdropTemplate")
	atk.box:SetSize(14, 14); atk.box:SetPoint("LEFT", 1, 0)
	atk.box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	atk.box:SetBackdropColor(0, 0, 0, 0.4); atk.box:SetBackdropBorderColor(1, 1, 1, 0.25)
	atk.check = tex(atk.box, "ARTWORK", ACCENT[1], ACCENT[2], ACCENT[3], 1)
	atk.check:SetPoint("TOPLEFT", 3, -3); atk.check:SetPoint("BOTTOMRIGHT", -3, 3)
	atk.label = atk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	atk.label:SetPoint("LEFT", atk.box, "RIGHT", 7, 0)
	atk.label:SetText("Also start auto-attack  |cff707070/startattack|r")
	atk:SetScript("OnClick", function()
		win.startAttack = not win.startAttack
		win:RenderPick()
	end)
	atk:SetScript("OnEnter", function(self)
		atk.box:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.8)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Also start auto-attack", ACCENT[1], ACCENT[2], ACCENT[3])
		GameTooltip:AddLine("Adds " .. ATTACK_LINE .. " above the cast. It turns on auto-attack against your current target when that target is a live enemy, and does nothing otherwise.", 1, 1, 1, true)
		GameTooltip:AddLine("Works with any targeting option: heal a mouseover and keep swinging at the boss.", 0.75, 0.75, 0.75, true)
		GameTooltip:Show()
	end)
	atk:SetScript("OnLeave", function()
		atk.box:SetBackdropBorderColor(1, 1, 1, 0.25)
		GameTooltip:Hide()
	end)
	win.atkBox = atk

	-- preview + create ---------------------------------------------------
	local preview = CreateFrame("Frame", nil, win, "BackdropTemplate")
	preview:SetPoint("TOPLEFT", atk, "BOTTOMLEFT", 0, -8); preview:SetPoint("RIGHT", win, "RIGHT", -14, 0); preview:SetHeight(62)
	preview:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
	preview:SetBackdropColor(0, 0, 0, 0.35)
	win.previewText = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	win.previewText:SetPoint("TOPLEFT", 8, -6); win.previewText:SetPoint("RIGHT", -8, 0)
	win.previewText:SetJustifyH("LEFT"); win.previewText:SetFont(STANDARD_TEXT_FONT, 10)

	local function make(spell)
		win.rankPick:Hide()
		local ok, msg = createMacro(spell, MODES[win.mode], win.selectedIcon, win.startAttack)
		status(msg, ok)
		if ok then win:RenderMacros() end
	end

	local create = flatButton(win, "Create macro", 130, 26, function()
		local e = win.selectedEntry
		if e and e.name == win.selected and #e.ranks > 1 then
			win:AskRank(e)
		else
			make(win.selected)
		end
	end)
	create:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -8)
	win.createBtn = create
	create:SetBackdropColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.18)
	win.status = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	win.status:SetPoint("LEFT", create, "RIGHT", 10, 0); win.status:SetPoint("RIGHT", win, "RIGHT", -14, 0)
	win.status:SetJustifyH("LEFT"); win.status:SetWordWrap(true)

	-- 3. existing --------------------------------------------------------
	local h3 = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	h3:SetPoint("TOPLEFT", create, "BOTTOMLEFT", 0, -16); h3:SetText("YOUR HOVER MACROS")
	win.macroCount = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.macroCount:SetPoint("LEFT", h3, "RIGHT", 6, 0)

	local mlist = CreateFrame("Frame", nil, win)
	mlist:SetPoint("TOPLEFT", h3, "BOTTOMLEFT", 0, -4); mlist:SetPoint("RIGHT", win, "RIGHT", -14, 0)
	mlist:SetHeight(MACRO_ROWS * ROW_H + 4)
	mlist:EnableMouseWheel(true)
	mlist:SetScript("OnMouseWheel", function(_, d)
		win.macroOffset = clamp((win.macroOffset or 0) - d, #(win.macros or {}), MACRO_ROWS)
		win:RenderMacros(true)
	end)
	win.macroList = mlist
	win.macroScroll = scrollBar(mlist)
	win.macroRows = {}
	for i = 1, MACRO_ROWS do
		-- click the row itself to load that macro back into the editor
		local r = CreateFrame("Button", nil, mlist)
		r:SetHeight(ROW_H); r:SetPoint("TOPLEFT", 0, -2 - (i - 1) * ROW_H); r:SetPoint("RIGHT", mlist, "RIGHT", -8, 0)
		r.bg = tex(r, "BACKGROUND", 1, 1, 1, (i % 2 == 0) and 0.03 or 0); r.bg:SetAllPoints()
		r.hl = tex(r, "HIGHLIGHT", ACCENT[1], ACCENT[2], ACCENT[3], 0.10); r.hl:SetAllPoints()
		r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 4, 0); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.label:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
		r:SetScript("OnClick", function(self) if self.macro then win:LoadMacro(self.macro) end end)
		r.del = flatButton(r, "Remove", 58, 18)
		r.del:SetPoint("RIGHT", -2, 0)
		-- put an existing one back on the cursor, e.g. for a second bar
		r.pick = flatButton(r, "Pick up", 58, 18, function(self)
			if not self.macro then return end
			if pickUp(self.macro.name) then status("It's on your cursor: click an action bar slot.", true)
			else status("leave combat first.") end
		end)
		r.pick:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
		r.modeTag = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		r.modeTag:SetPoint("RIGHT", r.pick, "LEFT", -8, 0)
		r.label:SetPoint("RIGHT", r.modeTag, "LEFT", -6, 0); r.label:SetJustifyH("LEFT"); r.label:SetWordWrap(false)
		r.del:SetScript("OnClick", function(self)
			if not self.macro then return end
			local ok, msg = deleteOurs(self.macro)
			status(msg, ok)
			win:RenderMacros()
		end)
		win.macroRows[i] = r
	end
	win.emptyMacros = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.emptyMacros:SetPoint("TOPLEFT", mlist, "TOPLEFT", 4, -6)
	win.emptyMacros:SetText("None yet.")

	-- rank chooser ---------------------------------------------------------
	-- Covers the window; a click on the dimmed area outside the panel cancels.
	local PER_ROW, RB_W, RB_H = 5, 76, 22
	local pick = CreateFrame("Frame", nil, win)
	pick:SetAllPoints(); pick:SetFrameLevel(win:GetFrameLevel() + 30)
	pick:EnableMouse(true); pick:EnableMouseWheel(true); pick:Hide()
	pick:SetScript("OnMouseDown", function(self) self:Hide() end)
	pick:SetScript("OnMouseWheel", function() end)
	local dim = tex(pick, "BACKGROUND", 0, 0, 0, 0.6); dim:SetAllPoints()
	win.rankPick = pick

	local panel = CreateFrame("Frame", nil, pick, "BackdropTemplate")
	panel:SetWidth(432); panel:SetPoint("CENTER"); panel:EnableMouse(true)
	panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	panel:SetBackdropColor(0.07, 0.08, 0.10, 1); panel:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.7)
	panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.title:SetPoint("TOPLEFT", 14, -12)
	panel.max = flatButton(panel, "Max rank  |cff909090(always casts your highest)|r", 404, 28)
	panel.max:SetPoint("TOPLEFT", 14, -36)
	panel.max:SetBackdropColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.18)
	local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", 14, -76); hint:SetText("or a specific rank:")
	panel.cancel = flatButton(panel, "Cancel", 80, 22, function() pick:Hide() end)
	panel.rankBtns = {}

	function win:AskRank(e)
		panel.title:SetText(e.name .. ": which rank?")
		panel.max:SetScript("OnClick", function() make(e.name) end)
		for i, r in ipairs(e.ranks) do
			local b = panel.rankBtns[i]
			if not b then b = flatButton(panel, "", RB_W, RB_H); panel.rankBtns[i] = b end
			local col, row = (i - 1) % PER_ROW, math.floor((i - 1) / PER_ROW)
			b:ClearAllPoints(); b:SetPoint("TOPLEFT", 14 + col * (RB_W + 6), -92 - row * (RB_H + 6))
			b.text:SetText(r.sub)
			b:SetScript("OnClick", function() make(e.name .. "(" .. r.sub .. ")") end)
			b:Show()
		end
		for i = #e.ranks + 1, #panel.rankBtns do panel.rankBtns[i]:Hide() end
		local y = 92 + math.ceil(#e.ranks / PER_ROW) * (RB_H + 6) + 6
		panel.cancel:ClearAllPoints(); panel.cancel:SetPoint("TOPRIGHT", -14, -y)
		panel:SetHeight(y + RB_H + 12)
		pick:Show()
	end

	-- renderers ------------------------------------------------------------
	function win:RenderSpells()
		local f = strlower(self.search:GetText() or "")
		self.filtered = {}
		for _, s in ipairs(self.spells or {}) do
			if f == "" or strlower(s.name):find(f, 1, true) then self.filtered[#self.filtered + 1] = s end
		end
		self.spellOffset = clamp(self.spellOffset, #self.filtered, SPELL_ROWS)
		local off = self.spellOffset
		for i, r in ipairs(self.spellRows) do
			local s = self.filtered[off + i]
			r.spell = s
			if s then
				r.icon:SetTexture(s.icon or 134400)
				r.label:SetText(s.name)
				r.tag:SetText((#s.ranks > 1 and ("|cff707070" .. #s.ranks .. " ranks|r   ") or "")
					.. (s.helpful and "|cff4cc776helpful|r" or ""))
				local sel = (s.name == self.selected)
				if sel then self.selectedEntry = s end
				r.bg:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], sel and 0.22 or 0)
				r:Show()
			else
				r:Hide()
			end
		end
		self.spellScroll(#self.filtered, SPELL_ROWS, off)
	end

	function win:RenderPick()
		local mode = MODES[self.mode]
		self.modeBtn.text:SetText(mode.label)
		local spell = self.selected or "<spell>"
		self.previewText:SetText("|cff808080" .. macroBody(spell, mode, self.startAttack):gsub("\n", "|n") .. "|r")
		self.atkBox.check:SetShown(self.startAttack and true or false)
		local e = self.selectedEntry
		self.createBtn.text:SetText((e and e.name == self.selected and #e.ranks > 1) and "Create macro..." or "Create macro")
	end

	-- cached=true re-draws the last scan (mouse wheel) instead of re-reading 150 macro slots
	function win:RenderMacros(cached)
		if not cached or not self.macros then self.macros = ourMacros() end
		local ms = self.macros
		self.macroOffset = clamp(self.macroOffset, #ms, MACRO_ROWS)
		local off = self.macroOffset
		for i, r in ipairs(self.macroRows) do
			local m = ms[off + i]
			if m then
				r.icon:SetTexture(m.icon or 134400)
				local base, sub = splitRank(m.spell)
				r.label:SetText(sub and (base .. "  |cff808080" .. sub .. "|r") or m.spell)
				r.modeTag:SetText((m.mode and MODES[m.mode].short or "edited") .. (m.attack and " + attack" or ""))
				r.macro = m
				r.del.macro = m
				r.pick.macro = m
				r:Show()
			else
				r:Hide()
			end
		end
		self.emptyMacros:SetShown(#ms == 0)
		self.macroCount:SetText(#ms > MACRO_ROWS and ("|cff606060(" .. #ms .. ", scroll for more)|r") or "")
		self.macroScroll(#ms, MACRO_ROWS, off)
	end

	function win:LoadMacro(m)
		local base = splitRank(m.spell)
		self.selected, self.selectedEntry, self.selectedIcon = base, nil, m.icon
		self.search:SetText("")
		for i, s in ipairs(self.spells or {}) do
			if strlower(s.name) == strlower(base) then
				self.selected, self.selectedEntry, self.selectedIcon = s.name, s, s.icon
				self.spellOffset = i - 1 - math.floor(SPELL_ROWS / 2)   -- clamped when drawn
				break
			end
		end
		if m.mode then self.mode = m.mode end
		self.startAttack = m.attack
		self:RenderSpells(); self:RenderPick()
		status("Loaded " .. m.spell .. ": change the targeting, then Create.", true)
	end

	function win:Refresh()
		self.spells = playerSpells()
		self:RenderSpells(); self:RenderPick(); self:RenderMacros()
	end

	win:SetScript("OnHide", function(self) self.rankPick:Hide() end)
	win:SetScript("OnShow", function(self)
		self:Refresh()
		-- fit the window to the macro list's bottom edge, whatever the font heights came out as
		local top, bottom = self:GetTop(), mlist:GetBottom()
		if top and bottom then
			local want = math.floor(top - bottom + 14 + 0.5)
			if math.abs(self:GetHeight() - want) > 1 then self:SetHeight(want) end
		end
	end)
	win:Hide()
	return win
end

-- stay current while open
do
	local f = CreateFrame("Frame")
	f:RegisterEvent("SPELLS_CHANGED")
	f:RegisterEvent("UPDATE_MACROS")
	pcall(f.RegisterEvent, f, "SPELL_TEXT_UPDATE")   -- rank text loads late sometimes
	local pending
	f:SetScript("OnEvent", function(_, event)
		if not (win and win:IsShown()) then return end
		if event == "UPDATE_MACROS" then win:RenderMacros(); return end
		if pending then return end
		pending = true
		C_Timer.After(0.3, function()
			pending = false
			if win:IsShown() then win:Refresh() end
		end)
	end)
end

-- ---------------------------------------------------------------------------
-- slash
-- ---------------------------------------------------------------------------
-- addon menu by the minimap (## AddonCompartmentFunc in the TOC)
function HoverCast_OnAddonCompartmentClick()
	SlashCmdList.HOVERCAST("")
end

SLASH_HOVERCAST1 = "/hover"
SLASH_HOVERCAST2 = "/hovercast"
SlashCmdList["HOVERCAST"] = function(msg)
	msg = strtrim(msg or "")
	if msg == "" then
		build()
		if win:IsShown() then win:Hide() else win:Show() end
		return
	end
	-- "/hover Holy Light": make it and put it on the cursor
	local _, res = createMacro(msg, MODES[1])
	print(PREFIX .. res)
end
