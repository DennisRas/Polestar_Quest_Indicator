-- Which loaded Polestar guides include the quest you are looking at.
-- Author: Liquidor
--
-- A mark on the quest log, the objective tracker and an NPC's quest list.
-- On the open quest (the log and the accept, progress and complete dialogs)
-- each guide is its own line under the description. The same guides are
-- listed on a quest tooltip, and on an item that starts a quest the player
-- has not taken yet.
--
-- A quest is in a guide when one of that guide's goals carries its id
-- (goal.quest), and the guide and that step are for this character
-- (Guides.List is the packs that are on; Guides.GuideMatches, OtherStart and
-- Matches drop the other faction, the other race and the other class).
-- Built once, again when guides are registered or a pack is switched
-- (GUIDES_REGISTERED, PACKS_CHANGED). A guide whose steps are still the
-- source string is read and then released, so a guide nobody has open does
-- not stay built.
--
-- Dungeon pre-quests have no dungeon tag. The pick-up guide that contains
-- them is registered only once someone builds it, so a quest the Codex
-- already marks (Dungeons.QuestMark: the dungeon's own quests and the
-- nearest pre-quests) is listed too, under that dungeon, unless a loaded
-- guide already covers it.
--
-- The gamepad interface is left alone (ns.GamepadUI): these hooks write the
-- game's quest buttons, which that UI rebuilds inside the caller's code.
-- Item and quest-link tooltips are not those buttons and still get the line.

---@type PQI_Polestar
local ns = Polestar
if not ns then return end

local L = ns.L
local readable = ns.Compat.Readable

local type, pairs, ipairs, pcall = type, pairs, ipairs, pcall
local format, floor, max = string.format, math.floor, math.max

---@type PQI_HitMap?
local byQuest
---@type PQI_ItemMap?
local byItem
local built = false
local pending = false

local tipped = setmetatable({}, { __mode = "k" })

---------------------------------------------------------------------------
-- Index
---------------------------------------------------------------------------

---@return PQI_Player?
local function playerInfo()
	local C = ns.Compat
	if not (C and C.GetPlayerInfo) then return nil end
	local ok, info = pcall(C.GetPlayerInfo)
	return ok and type(info) == "table" and info or nil
end

---@param g PQI_Guide
---@param player PQI_Player?
---@return boolean
local function includeGuide(g, player)
	local G = ns.Guides
	if not player then return true end
	if G.OtherFaction and G.OtherFaction(g, player) then return false end
	if not G.GuideMatches or G.GuideMatches(g, player) then return true end
	return G.OtherStart and G.OtherStart(g, player) or false
end

---@param only PQI_Only?
---@param player PQI_Player?
---@return boolean
local function applies(only, player)
	local G = ns.Guides
	if not player or not G.Matches then return true end
	return G.Matches(only, player)
end

---@param g PQI_Guide
---@return string
local function guideTitle(g)
	local UI = ns.UI
	if UI and UI.GuideLabel then
		local ok, text = pcall(UI.GuideLabel, g)
		if ok and type(text) == "string" and text ~= "" then return text end
	end
	if type(g.title) == "string" and g.title ~= "" then return g.title end
	return g.id
end

---@param g PQI_Guide
---@return string?
local function dungeonKey(g)
	if type(g.dungeon) == "string" and g.dungeon ~= "" then return g.dungeon end
	local id = g.id
	if type(id) ~= "string" then return nil end
	return id:match("^lookup/pickup/(.+)$") or id:match("^lookup/handin/(.+)$")
end

---@param map PQI_HitMap
---@param quest number
---@param hit PQI_Hit
local function addHit(map, quest, hit)
	local list = map[quest]
	if not list then
		list = {}
		map[quest] = list
	end
	for i = 1, #list do
		if list[i].key == hit.key then return end
	end
	list[#list + 1] = hit
end

---@param map PQI_ItemMap
---@param item number
---@param quest number
local function addItem(map, item, quest)
	local list = map[item]
	if not list then
		list = {}
		map[item] = list
	end
	for i = 1, #list do
		if list[i] == quest then return end
	end
	list[#list + 1] = quest
end

---@param header PQI_Guide
---@param player PQI_Player?
---@param quests PQI_HitMap
---@param items PQI_ItemMap
local function scanGuide(header, player, quests, items)
	local G = ns.Guides
	local g = G.Get(header.id)
	if not g then return end
	local had = rawget(g, "steps") ~= nil
	local ok, err = pcall(function()
		local steps = g.steps
		if type(steps) ~= "table" then return end
		local hit = { key = header.id, title = guideTitle(header), dungeon = dungeonKey(header) or dungeonKey(g) }
		for s = 1, #steps do
			local step = steps[s]
			if type(step) == "table" and applies(step.only, player) then
				local goals = step.goals
				if type(goals) == "table" then
					for i = 1, #goals do
						local goal = goals[i]
						if type(goal) == "table" and type(goal.quest) == "number" and applies(goal.only, player) then
							addHit(quests, goal.quest, hit)
							if goal.t == "accept" and type(goal.item) == "number" then
								addItem(items, goal.item, goal.quest)
							end
						end
					end
				end
			end
		end
	end)
	if not had and G.Release then G.Release(header.id) end
	if not ok then error(err, 0) end
end

local function build()
	local G = ns.Guides
	local quests, items = {}, {}
	byQuest, byItem = quests, items
	if not (G and G.List and G.Get) then return end
	local player = playerInfo()
	local list = G.List()
	for i = 1, #list do
		local header = list[i]
		if type(header) == "table" and type(header.id) == "string" and includeGuide(header, player) then
			local ok, err = pcall(scanGuide, header, player, quests, items)
			if not ok then ns.NoteError(err) end
		end
	end
end

local function ensure()
	if built then return end
	built = true
	local ok, err = pcall(build)
	if not ok then
		built = false
		byQuest, byItem = nil, nil
		ns.NoteError(err)
	end
end

local function scheduleBuild()
	byQuest, byItem, built = nil, nil, false
	if pending or not ns.IsLoggedIn() then return end
	pending = true
	ns.After(0, function()
		pending = false
		ensure()
		local map = QuestMapFrame
		if not ns.Hidden() and map and map.IsShown and map:IsShown() and type(QuestLogQuests_Update) == "function" then
			pcall(QuestLogQuests_Update)
		end
	end)
end

---@param id number
---@return string?
local function questTitle(id)
	local UI, N, Q = ns.UI, ns.Names, ns.QuestDB
	local title = UI and UI.QuestTitle and UI.QuestTitle(id)
	if type(title) == "string" and title ~= "" then return title end
	title = N and N.Quest and N.Quest(id)
	if type(title) == "string" and title ~= "" then return title end
	if Q and Q.GetQuestTitle then
		title = Q.GetQuestTitle(id)
		if type(title) == "string" and title ~= "" then return title end
	end
	return nil
end

---@param mark PQI_DungeonMark
---@return string?
local function dungeonWhy(mark)
	if not mark.quest then return nil end
	local title = questTitle(mark.quest) or ("#" .. mark.quest)
	local quoted = ns.Quoted and ns.Quoted(title) or title
	if mark.breadcrumb then return format(L["Leads to %s."], quoted) end
	return format(L["Needed for %s."], quoted)
end

-- Dungeon marks live in the Codex. Loading it parses the whole dungeon
-- database and freezes the game, so the quest list never starts that load.
-- Marks appear once something else has loaded the Codex.
---@return PQI_Dungeons?
local function dungeons()
	local D = ns.Dungeons
	if not (D and D.QuestMark and D.Meta and D.Meta()) then return nil end
	return D
end

-- The loaded guides, then a dungeon the Codex marks when no loaded guide
-- already names it. Nil when nothing does.
---@param questID number
---@return PQI_Hit[]?
local function hitsFor(questID)
	if type(questID) ~= "number" then return nil end
	ensure()
	local src = byQuest and byQuest[questID]
	local list
	if src then
		list = {}
		for i = 1, #src do
			local h = src[i]
			list[i] = { key = h.key, title = h.title, why = h.why, dungeon = h.dungeon }
		end
	end
	local D = dungeons()
	local mark = D and D.QuestMark(questID)
	if mark then
		local covered
		for i = 1, list and #list or 0 do
			if list[i].dungeon == mark.key then
				if mark.quest and not list[i].why then list[i].why = dungeonWhy(mark) end
				covered = true
				break
			end
		end
		if not covered then
			local d = D.Get and D.Get(mark.key)
			local name = d and d.name or mark.key
			list = list or {}
			if mark.quest then
				list[#list + 1] = { key = "dungeon:" .. mark.key, title = name, dungeon = mark.key, why = dungeonWhy(mark) }
			else
				list[#list + 1] = { key = "dungeon:" .. mark.key, title = format(L["Part of the %s quests"], name), dungeon = mark.key }
			end
		end
	end
	if not list or #list == 0 then return nil end
	return list
end

-- True when any loaded guide or a dungeon mark names it. The log paints a
-- mark on every row, so this stays a lookup. It does not build the index or
-- load the Codex: both of those stall the quest-log layout.
---@param questID number
---@return boolean
local function involved(questID)
	if type(questID) ~= "number" or questID <= 0 or not built then return false end
	if byQuest and byQuest[questID] then return true end
	local D = dungeons()
	local mark = D and D.QuestMark(questID)
	return mark ~= nil
end

---@param list PQI_Hit[]
---@return string
local function summary(list)
	local parts = {}
	for i = 1, #list do parts[i] = list[i].title end
	return table.concat(parts, ", ")
end

---@param questID number
---@return boolean
local function notStarted(questID)
	local C = ns.Compat
	if C.IsQuestCompleted and C.IsQuestCompleted(questID) then return false end
	if C.IsOnQuest and C.IsOnQuest(questID) then return false end
	return true
end

-- Quests an item starts: an accept goal's item, and the quest database's
-- start item. The database knows items no guide names.
---@param itemID number
---@return number[]?
local function questsFromItem(itemID)
	if type(itemID) ~= "number" then return nil end
	ensure()
	local seen, out = {}, {}
	---@param q number
	local function add(q)
		if type(q) == "number" and not seen[q] then
			seen[q] = true
			out[#out + 1] = q
		end
	end
	local from = byItem and byItem[itemID]
	if from then
		for i = 1, #from do add(from[i]) end
	end
	local Q = ns.QuestDB
	if Q and Q.StartedBy then
		local list = Q.StartedBy(itemID)
		if list then
			for i = 1, #list do add(list[i]) end
		end
	end
	return #out > 0 and out or nil
end

---------------------------------------------------------------------------
-- Guide mark. The same glyph as the Guides section on the guide window's
-- rail. The star is the favorite mark, so it stays off these quests.
---------------------------------------------------------------------------

local markTags = {}

-- r, g, b: the text this glyph sits in, so the icon takes that color.
---@param r number?
---@param g number?
---@param b number?
---@return string
local function mark(r, g, b)
	r, g, b = r or 1, g or 1, b or 1
	local key = floor(r * 255 + 0.5) .. ":" .. floor(g * 255 + 0.5) .. ":" .. floor(b * 255 + 0.5)
	local tag = markTags[key]
	if not tag then
		local T = ns.Theme
		local path = T and T.Media and T.Media("guides") or "Interface\\AddOns\\Polestar\\Media\\UI\\guides"
		tag = format("|T%s:0:0:0:0:32:32:0:32:0:32:%d:%d:%d|t", path, floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
		markTags[key] = tag
	end
	return tag
end

-- The color the letters are actually drawn in. A |c code in the title wins
-- over the font's own color.
---@param fs FontString?
---@param text string?
---@return number, number, number
local function textColor(fs, text)
	if type(text) == "string" then
		local hex
		for h in text:gmatch("|c(%x%x%x%x%x%x%x%x)") do hex = h end
		if hex then
			local r = tonumber(hex:sub(3, 4), 16)
			local g = tonumber(hex:sub(5, 6), 16)
			local b = tonumber(hex:sub(7, 8), 16)
			if r and g and b then return r / 255, g / 255, b / 255 end
		end
	end
	if fs and fs.GetTextColor then
		local r, g, b = fs:GetTextColor()
		if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
	end
	return 1, 1, 1
end

---@param text string?
---@return boolean
local function marked(text)
	return type(text) == "string" and (text:find("UI\\guides", 1, true) or text:find("UI/guides", 1, true)) and true or false
end

---@param obj PQI_TextHost|FontString|nil
---@return FontString?
local function textObject(obj)
	if not obj then return nil end
	if obj.GetObjectType and obj:GetObjectType() == "FontString" then
		---@cast obj FontString
		return obj
	end
	---@cast obj PQI_TextHost
	---@type FontString?
	local fs = obj.GetFontString and obj:GetFontString()
	if fs and fs.GetText and fs.SetText then return fs end
	fs = obj.Text
	if fs and fs.GetText and fs.SetText then return fs end
	return nil
end

-- kind "gossip" / "greeting" may grow the button. The log and the tracker
-- are already laid out, so a mark that would wrap the title onto another
-- line is left off.
---@param obj PQI_TextHost|FontString
---@param questID number
---@param kind string?
local function applyMark(obj, questID, kind)
	if ns.Hidden() or not involved(questID) then return end
	local fs = textObject(obj)
	if not fs then return end
	local text = readable(fs:GetText())
	if type(text) ~= "string" or text == "" then return end
	---@cast text string
	if marked(text) then return end
	local measure = not kind and fs.GetNumLines and fs or nil
	local lines = measure and measure:GetNumLines()
	local r, g, b = textColor(fs, text)
	fs:SetText(text .. " " .. mark(r, g, b))
	if lines and measure:GetNumLines() > lines then
		fs:SetText(text)
		return
	end
	if kind == "gossip" then
		---@cast obj PQI_TextHost
		if obj.Resize then obj:Resize() end
	end
	if kind == "greeting" then
		---@cast obj PQI_TextHost
		if obj.SetHeight and obj.GetTextHeight then
			local icon = obj.Icon
			local textH = obj:GetTextHeight() or 0
			local iconH = icon and icon.GetHeight and icon:GetHeight() or 0
			obj:SetHeight(max(textH + 2, iconH))
		end
	end
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------

---@return number, number, number
local function tipColor()
	local T = ns.Theme
	if T and T.TipColor then
		local r, g, b = T.TipColor("quest")
		if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
	end
	return 1, 0.82, 0.45
end

---@param tt GameTooltip
---@param questID number
---@return boolean
local function addQuestLines(tt, questID)
	if ns.Hidden() or tipped[tt] == questID then return false end
	local list = hitsFor(questID)
	if not list then return false end
	local r, g, b = tipColor()
	tt:AddLine(" ")
	tt:AddLine(L["Polestar Guides"], 0.65, 0.8, 1)
	for i = 1, #list do
		tt:AddLine(list[i].title or "", r, g, b, true)
	end
	tipped[tt] = questID
	return true
end

---@param owner PQI_TipOwner
---@param questID number
---@param anchor string?
local function showOwnedTip(owner, questID, anchor)
	if ns.Hidden() or type(questID) ~= "number" then return end
	local tt = GameTooltip
	if not tt or not hitsFor(questID) then return end
	local shown = tt.IsShown and tt:IsShown()
	if not shown then
		tt:SetOwner(owner, anchor or "ANCHOR_RIGHT")
		local title = questTitle(questID)
		if title and tt.SetText then tt:SetText(title, tipColor()) end
		owner.psGuideOwned = true
	end
	if addQuestLines(tt, questID) or owner.psGuideOwned then
		if tt.Show then tt:Show() end
	end
end

---@param obj PQI_TipOwner
---@param questID number
---@param anchor string
local function bindTip(obj, questID, anchor)
	if type(obj) ~= "table" then return end
	obj.psGuideQuest = questID
	obj.psGuideAnchor = anchor
	if obj.psGuideBound or not obj.HookScript then return end
	obj.psGuideBound = true
	obj:HookScript("OnEnter", function(self)
		local id = self.psGuideQuest
		if type(id) == "number" then showOwnedTip(self, id, self.psGuideAnchor) end
	end)
	obj:HookScript("OnLeave", function(self)
		if not self.psGuideOwned then return end
		self.psGuideOwned = nil
		if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
	end)
end

---@param tt GameTooltip
---@param link string?
---@param itemID number?
local function onItem(tt, link, itemID)
	if ns.Hidden() or type(itemID) ~= "number" then return end
	local quests = questsFromItem(itemID)
	if not quests then return end
	local r, g, b = tipColor()
	for i = 1, #quests do
		local q = quests[i]
		local list = notStarted(q) and hitsFor(q)
		if list and tt.AddLine then
			local title = questTitle(q) or L["Starts a quest"]
			tt:AddLine(title .. ": " .. summary(list), r, g, b, true)
		end
	end
end

---@param data PQI_TipData?
---@param link string?
---@return number?
local function questIdOf(data, link)
	local id = type(data) == "table" and readable(data.id)
	if type(id) == "number" and id > 0 then return id end
	if type(link) ~= "string" then
		link = type(data) == "table" and (data.hyperlink or data.guid)
	end
	if type(link) ~= "string" then return nil end
	return tonumber(link:match("quest:(%d+)"))
end

---@param tt GameTooltip
---@param data PQI_TipData?
local function onQuestTip(tt, data)
	if ns.Hidden() or not tt then return end
	if tt.IsForbidden then
		local ok, forbidden = pcall(tt.IsForbidden, tt)
		if not ok or forbidden then return end
	end
	local id = questIdOf(data)
	if id then addQuestLines(tt, id) end
end

---------------------------------------------------------------------------
-- Quest details, under the description
---------------------------------------------------------------------------

local generation = 0
---@type number?
local openQuest

---@param obj FontString|Frame|nil
---@return FontString?
local function asFont(obj)
	if type(obj) == "table" and obj.GetFont then return obj end
	return nil
end

---@param fs FontString
---@param sample FontString?
---@param fallbackName string
local function useFont(fs, sample, fallbackName)
	local fontObj = sample and sample.GetFontObject and sample:GetFontObject()
	if fontObj then
		fs:SetFontObject(fontObj)
	else
		---@type FontObject?
		local fallback = _G[fallbackName]
		if fallback then fs:SetFontObject(fallback) end
	end
	if sample and sample.GetTextColor then
		local r, g, b = sample:GetTextColor()
		if type(r) == "number" then fs:SetTextColor(r, g, b) end
	end
	if sample and sample.GetShadowOffset and fs.SetShadowOffset then
		local x, y = sample:GetShadowOffset()
		if type(x) == "number" then fs:SetShadowOffset(x, y) end
	end
	if sample and sample.GetShadowColor and fs.SetShadowColor then
		local r, g, b, a = sample:GetShadowColor()
		if type(r) == "number" then fs:SetShadowColor(r, g, b, a or 1) end
	end
end

-- A little room under the last guide line so the page can scroll past it.
local PAD = 14

-- Scroll the picker's list so the selected guide is in view. The row stores
-- its guide as psGuide; its top offset is how far the list has placed it.
---@param id string
local function scrollGuideIntoView(id)
	local UI = ns.UI
	local P = UI and UI.Picker
	local frame = P and P.frame
	local W = ns.Widgets
	if not P or not frame or not frame.Body or not P.scroll or not W then return end
	local children = { frame.Body:GetChildren() }
	for i = 1, #children do
		local child = children[i]
		---@cast child PQI_PickerRow
		local g = child.psGuide
		if g and g.id == id and child:IsShown() then
			local _, _, _, _, y = child:GetPoint(1)
			if type(y) == "number" then W.ScrollTo(P.scroll, max(0, -y - 36)) end
			return
		end
	end
end

-- Open the guide in the finder. Does not load it. Uses the picker's own
-- functions, so this addon does not patch Polestar.
---@param id string
---@return boolean
local function showGuide(id)
	local UI = ns.UI
	if not UI or not UI.ShowPicker then return false end
	local P = UI.Picker
	if not P or not P.ShowSection or not P.SetQuery or not P.SetCategory or not P.Select then return false end
	UI.ShowPicker()
	P.ShowSection("Guides")
	P.SetQuery("")
	P.SetCategory("All")
	local folder = P.FolderOf and P.FolderOf(id)
	if folder and P.SetCollapsed then P.SetCollapsed(folder, false) end
	P.Select(id)
	scrollGuideIntoView(id)
	ns.After(0, function() scrollGuideIntoView(id) end)
	return true
end

---@param hit PQI_Hit?
local function openHit(hit)
	if type(hit) ~= "table" then return end
	local id = hit.key
	if type(id) ~= "string" or id == "" then return end
	if id:sub(1, 8) == "dungeon:" then
		local D = ns.Dungeons
		if D and D.Open then D.Open(id:sub(9)) end
		return
	end
	showGuide(id)
end

local tipToken = 0

---@param row PQI_GuideRow
local function linkTip(row)
	local hit = row and row.hit
	if type(hit) ~= "table" or not GameTooltip then return end
	tipToken = tipToken + 1
	GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
	GameTooltip:SetText(hit.title or "", 1, 0.82, 0.45, 1, true)
	if hit.why then
		local r, g, b = tipColor()
		GameTooltip:AddLine(hit.why, r, g, b, true)
	end
	local dungeon = type(hit.key) == "string" and hit.key:sub(1, 8) == "dungeon:"
	local hint = dungeon and L["Click to open this dungeon."] or L["Click to show this guide."]
	GameTooltip:AddLine(hint, 0.7, 0.7, 0.7, true)
	GameTooltip:Show()
end

---@param block PQI_GuideRow
local function hideLinkTip(block)
	if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == block then GameTooltip:Hide() end
end

-- Leave fires before the next line's enter. Waiting a frame keeps the tip
-- up while the cursor moves from one guide name to the next.
---@param block PQI_GuideRow
local function queueHideLinkTip(block)
	local token = tipToken
	ns.After(0, function()
		if token ~= tipToken then return end
		hideLinkTip(block)
	end)
end

---@param self PQI_GuideRow
---@param delta number
local function passWheel(self, delta)
	local p = self
	for _ = 1, 8 do
		p = p and p.GetParent and p:GetParent()
		if not p then return end
		if p.GetVerticalScroll and p.SetVerticalScroll then
			local range = p.GetVerticalScrollRange and p:GetVerticalScrollRange() or 0
			local y = p:GetVerticalScroll() or 0
			if type(range) ~= "number" then range = 0 end
			if type(y) ~= "number" then y = 0 end
			y = math.min(range, math.max(0, y - delta * 40))
			p:SetVerticalScroll(y)
			return
		end
	end
end

-- A light wash behind the whole line. The quest text and icon stay as they are.
---@param r number?
---@param g number?
---@param b number?
---@return number, number, number
local function hoverInk(r, g, b)
	r, g, b = r or 1, g or 1, b or 1
	local lum = r * 0.3 + g * 0.59 + b * 0.11
	if lum > 0.55 then return 0.16, 0.13, 0.10 end
	return 0.45, 0.32, 0.16
end

---@param row PQI_GuideRow?
---@param r number?
---@param g number?
---@param b number?
local function paintRow(row, r, g, b)
	if not row then return end
	if row.Text then
		row.Text:SetTextColor(r or 1, g or 1, b or 1)
		row.Text:SetText(mark(r, g, b) .. " " .. (row.plain or ""))
	end
	if row.Why then row.Why:SetTextColor(r or 1, g or 1, b or 1) end
end

-- One button per guide. A font-string hyperlink in the quest scroll never
-- receives mouse motion, so the hover has to be a real button.
---@param block PQI_Overlay
---@param index number
---@return PQI_GuideRow
local function rowFor(block, index)
	local row = block.rows[index]
	if row then return row end
	row = ns.CreateFrameUnder("Button", nil, block)
	---@cast row PQI_GuideRow
	row:RegisterForClicks("LeftButtonUp")
	if row.EnableMouseWheel then row:EnableMouseWheel(true) end
	row:SetScript("OnMouseWheel", passWheel)
	row.Text = row:CreateFontString(nil, "OVERLAY")
	row.Text:SetJustifyH("LEFT")
	row.Text:SetJustifyV("TOP")
	row.Text:SetWordWrap(true)
	if row.Text.SetMaxLines then row.Text:SetMaxLines(0) end
	row.Text:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.Text:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.Why = row:CreateFontString(nil, "OVERLAY")
	row.Why:SetJustifyH("LEFT")
	row.Why:SetJustifyV("TOP")
	row.Why:SetWordWrap(true)
	row.Hover = row:CreateTexture(nil, "BACKGROUND")
	row.Hover:SetAllPoints(row)
	row.Hover:SetTexture("Interface\\Buttons\\WHITE8X8")
	row.Hover:Hide()
	row:SetScript("OnEnter", function(self)
		local br, bg, bb = hoverInk(self.tr, self.tg, self.tb)
		self.Hover:SetVertexColor(br, bg, bb, 0.12)
		self.Hover:Show()
		linkTip(self)
	end)
	row:SetScript("OnLeave", function(self)
		self.Hover:Hide()
		queueHideLinkTip(self)
	end)
	row:SetScript("OnClick", function(self)
		hideLinkTip(self)
		openHit(self.hit)
	end)
	block.rows[index] = row
	return row
end

-- The NPC dialog and the quest log both draw the quest prose through these
-- font strings, then anchor whatever comes next to the bottom of that string.
-- The guide rows are their own font strings under that prose. Putting them
-- inside it makes the quest frame clip the extra lines and end them with an
-- ellipsis.
---@return PQI_Prose?
local function prose()
	---@param fs FontString?
	---@return PQI_Prose?
	local function usable(fs)
		if not fs or not fs:IsShown() or not fs.GetText then return nil end
		local t = fs:GetText()
		if type(t) ~= "string" or t == "" then return nil end
		---@cast fs PQI_Prose
		return fs
	end
	return usable(QuestInfoDescriptionText) or usable(QuestInfoObjectivesText)
end

---@param text string?
---@return string, boolean
local function stripGuides(text)
	if type(text) ~= "string" then return "", false end
	for _, header in ipairs({ L["Polestar Guides"], L["Guide"] }) do
		local needle = "\n\n" .. header .. "\n\n"
		local at = text:find(needle, 1, true)
		if at then return text:sub(1, at - 1), true end
	end
	return text, false
end

---@param start Region
---@return Region?, ScrollFrame?
local function scrollPair(start)
	local p = start
	for _ = 1, 8 do
		if not p then return nil, nil end
		local parent = p.GetParent and p:GetParent()
		if parent and parent.GetScrollChild and parent:GetScrollChild() == p then
			---@cast parent ScrollFrame
			return p, parent
		end
		p = parent
	end
	return nil, nil
end

---@param frame Region?
---@param extra number
local function addHeight(frame, extra)
	if not frame or type(extra) ~= "number" or extra <= 0 then return end
	if not frame.GetHeight or not frame.SetHeight then return end
	local before = frame:GetHeight() or 0
	if before <= 1 then return end
	pcall(frame.SetHeight, frame, before + extra)
end

---@type table<FontString, PQI_Overlay>
local overlays = setmetatable({}, { __mode = "k" })

---@param desc PQI_Prose
---@return PQI_Overlay
local function overlayFor(desc)
	local parent = desc:GetParent() or desc
	local f = overlays[desc]
	if not f then
		f = ns.CreateFrameUnder("Frame", nil, parent)
		---@cast f PQI_Overlay
		f:EnableMouse(false)
		f.rows = {}
		overlays[desc] = f
	end
	if f:GetParent() ~= parent then f:SetParent(parent) end
	if not f.Header then
		f.Header = f:CreateFontString(nil, "OVERLAY")
		f.Header:SetJustifyH("LEFT")
		f.Header:SetJustifyV("BOTTOM")
		f.Header:SetWordWrap(false)
	end
	return f
end

-- Objectives, Description, Rewards. The map rewards frame has no heading of
-- its own, so a shown heading on this page is the one to copy.
---@return FontString?
local function sectionHeader()
	local found
	---@param fs FontString?
	---@return FontString?
	local function add(fs)
		if not fs or not asFont(fs) then return nil end
		found = found or fs
		if fs:IsShown() then return fs end
		return nil
	end
	---@type FontString?
	local rewardsHeader = QuestInfoRewardsFrameHeader
	local shown = add(QuestInfoObjectivesHeader) or add(QuestInfoDescriptionHeader) or add(rewardsHeader)
	if shown then return shown end
	if QuestInfoRewardsFrame then shown = add(QuestInfoRewardsFrame.Header) end
	if shown then return shown end
	---@type PQI_RewardsFrame?
	local rewards = QuestInfoFrame and QuestInfoFrame.rewardsFrame
	if rewards then shown = add(rewards.Header) end
	return shown or found
end

-- A bottom anchor locks the prose height, and the quest frame then draws "..."
-- for anything past that box. Keep the top anchor and the width.
---@param fs FontString
local function dropBottomAnchor(fs)
	if not (fs.GetNumPoints and fs.ClearAllPoints and fs.SetPoint) then return end
	local n = fs:GetNumPoints() or 0
	if n < 2 then return end
	---@type PQI_Anchor[]
	local kept = {}
	local width = fs.GetWidth and fs:GetWidth() or 0
	for i = 1, n do
		local point, rel, relPoint, x, y = fs:GetPoint(i)
		if type(point) == "string" and type(relPoint) == "string" and type(x) == "number" and type(y) == "number" and not point:find("BOTTOM", 1, true) then
			---@cast rel Frame
			kept[#kept + 1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
		end
	end
	if #kept == 0 or #kept == n then return end
	fs:ClearAllPoints()
	for i = 1, #kept do
		local a = kept[i]
		fs:SetPoint(a.point, a.rel, a.relPoint, a.x, a.y)
	end
	if type(width) == "number" and width > 20 and fs.SetWidth then fs:SetWidth(width) end
end

-- Measure the whole string, not the height it was clipped to. A reading that
-- comes back as the box we just opened is the box, not the text, so it is
-- discarded.
---@param fs FontString
---@return number
local function fitString(fs)
	if not fs then return 0 end
	if fs.SetMaxLines then pcall(fs.SetMaxLines, fs, 0) end
	if fs.SetWordWrap then pcall(fs.SetWordWrap, fs, true) end
	local before = fs.GetHeight and fs:GetHeight() or 0
	if fs.SetHeight then pcall(fs.SetHeight, fs, 0) end
	local h = fs.GetStringHeight and fs:GetStringHeight() or 0
	if type(h) ~= "number" or h < 1 then
		if fs.SetHeight then pcall(fs.SetHeight, fs, 4000) end
		h = fs.GetStringHeight and fs:GetStringHeight() or 0
	end
	if type(h) ~= "number" or h < 1 or h > 2000 then h = before end
	if type(h) ~= "number" or h < 1 then h = 1 end
	if fs.SetHeight then pcall(fs.SetHeight, fs, h) end
	return h
end

---@param fs FontString?
---@return number
local function measured(fs)
	if not fs then return 16 end
	if fs.SetHeight then fs:SetHeight(0) end
	local h = fs.GetStringHeight and fs:GetStringHeight() or 0
	if type(h) ~= "number" or h < 8 or h > 160 then
		if fs.SetHeight then fs:SetHeight(400) end
		h = fs.GetStringHeight and fs:GetStringHeight() or 0
	end
	if type(h) ~= "number" or h < 8 or h > 160 then h = 16 end
	if fs.SetHeight then fs:SetHeight(h) end
	return h
end

-- Whatever the page anchored under the prose (objectives, rewards) moves to
-- sit under the guide block.
---@param desc PQI_Prose
---@param overlay PQI_Overlay
local function shiftFollowers(desc, overlay)
	---@param frame Frame?
	local function scan(frame)
		if not frame or frame == overlay then return end
		---@param obj Region
		local function consider(obj)
			if obj == desc or obj == overlay or not obj.GetNumPoints then return end
			local n = obj:GetNumPoints() or 0
			for i = 1, n do
				local point, rel, relPoint, x, y = obj:GetPoint(i)
				if rel == desc and type(relPoint) == "string" and relPoint:find("BOTTOM", 1, true) and type(point) == "string" then
					pcall(obj.SetPoint, obj, point, overlay, relPoint, x or 0, y or 0)
				end
			end
		end
		if frame.GetChildren then
			local kids = { frame:GetChildren() }
			for i = 1, #kids do consider(kids[i]) end
		end
		if frame.GetRegions then
			local regs = { frame:GetRegions() }
			for i = 1, #regs do consider(regs[i]) end
		end
	end
	scan(desc:GetParent())
	if QuestInfoFrame and QuestInfoFrame ~= desc:GetParent() then scan(QuestInfoFrame) end
end

---@param desc PQI_Prose
---@param extra number
local function growChain(desc, extra)
	if type(extra) ~= "number" or extra <= 1 then return end
	local child, scroll = scrollPair(desc)
	if not child then
		addHeight(desc:GetParent(), extra + PAD)
		return
	end
	local p = desc:GetParent()
	for _ = 1, 8 do
		if not p then break end
		addHeight(p, p == child and (extra + PAD) or extra)
		if p == child then break end
		p = p:GetParent()
	end
	if scroll and scroll.UpdateScrollChildRect then pcall(scroll.UpdateScrollChildRect, scroll) end
end

---@param hit PQI_Hit
---@return string
local function plainTitle(hit)
	local title = type(hit.title) == "string" and hit.title or ""
	return (title:gsub("|", ""))
end

---@param desc PQI_Prose
---@param list PQI_Hit[]
---@return number
local function placeHits(desc, list)
	local overlay = overlayFor(desc)
	local r, g, b = textColor(desc, desc:GetText())
	overlay:ClearAllPoints()
	overlay:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -8)
	overlay:SetPoint("TOPRIGHT", desc, "BOTTOMRIGHT", 0, -8)
	local header = overlay.Header
	useFont(header, sectionHeader(), "GameFontNormal")
	header:SetWordWrap(true)
	if header.SetMaxLines then header:SetMaxLines(0) end
	header:SetText((#list == 1) and L["Guide"] or L["Polestar Guides"])
	header:ClearAllPoints()
	header:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 0, 0)
	header:Show()
	local y = measured(header) + 4
	for i = 1, #list do
		local hit = list[i]
		local row = rowFor(overlay, i)
		row.hit = hit
		row.plain = plainTitle(hit)
		row.tr, row.tg, row.tb = r, g, b
		useFont(row.Text, desc, "QuestFont")
		row.Text:SetWordWrap(true)
		if row.Text.SetMaxLines then row.Text:SetMaxLines(0) end
		paintRow(row, r, g, b)
		row.Text:Show()
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, -y)
		row:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 0, -y)
		local h = measured(row.Text)
		local why = type(hit.why) == "string" and hit.why:gsub("|", "") or ""
		if why ~= "" and row.Why then
			useFont(row.Why, desc, "QuestFont")
			row.Why:SetWordWrap(true)
			if row.Why.SetMaxLines then row.Why:SetMaxLines(0) end
			row.Why:SetText(why)
			row.Why:SetTextColor(r or 1, g or 1, b or 1)
			row.Why:ClearAllPoints()
			row.Why:SetPoint("TOPLEFT", row, "TOPLEFT", 16, -h)
			row.Why:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -h)
			row.Why:Show()
			h = h + measured(row.Why)
		elseif row.Why then
			row.Why:Hide()
		end
		if row.Hover then row.Hover:Hide() end
		row:SetHeight(h)
		row:Show()
		y = y + h + 2
	end
	for i = #list + 1, #overlay.rows do overlay.rows[i]:Hide() end
	overlay:SetHeight(math.max(y, 1))
	local host = desc:GetParent()
	local level = (host and host.GetFrameLevel and host:GetFrameLevel() or 0) + 8
	if overlay.SetFrameLevel then pcall(overlay.SetFrameLevel, overlay, level) end
	for i = 1, #list do
		local row = overlay.rows[i]
		if row and row.SetFrameLevel then row:SetFrameLevel(level + 2) end
	end
	overlay:Show()
	return y
end

---@param questID number?
local function place(questID)
	local desc = prose()
	if not desc then return end
	local list = nil
	if type(questID) == "number" and not ns.Hidden() then list = hitsFor(questID) end
	local raw = desc:GetText() or ""
	local stripped = stripGuides(raw)
	local base = (desc.psGuideShown == raw and desc.psGuideBase) or stripped
	if desc:GetText() ~= base then desc:SetText(base) end
	desc.psGuideBase = base
	desc.psGuideShown = desc:GetText()
	dropBottomAnchor(desc)
	fitString(desc)
	if not list then
		local overlay = overlays[desc]
		if overlay then overlay:Hide() end
		openQuest = nil
		return
	end
	openQuest = questID
	local blockH = placeHits(desc, list) or 0
	shiftFollowers(desc, overlays[desc])
	local grown = desc.psGuideGrown or 0
	local need = blockH + 8
	if need - grown > 1 then
		growChain(desc, need - grown)
		desc.psGuideGrown = need
	end
	if not desc.psGuideFit then
		desc.psGuideFit = true
		ns.After(0, function()
			if openQuest == questID and prose() == desc then place(questID) end
		end)
	end
end

---@param template PQI_QuestTemplate?
---@return number?
local function questOf(template)
	local q
	if type(template) == "table" and template.questLog and C_QuestLog and C_QuestLog.GetSelectedQuest then
		q = C_QuestLog.GetSelectedQuest()
	end
	q = readable(q)
	if type(q) ~= "number" and GetQuestID then q = readable(GetQuestID()) end
	if type(q) ~= "number" and C_QuestLog and C_QuestLog.GetSelectedQuest then
		q = readable(C_QuestLog.GetSelectedQuest())
	end
	if type(q) == "number" and q > 0 then return q end
	return nil
end

---@param template PQI_QuestTemplate?
local function onInfoDisplay(template)
	local questID = questOf(template)
	generation = generation + 1
	local gen = generation
	-- The game rebuilds the page, including its height, before this returns.
	-- Place on the next frame, and let that pass grow the page again.
	if QuestInfoDescriptionText then
		QuestInfoDescriptionText.psGuideGrown = nil
		QuestInfoDescriptionText.psGuideFit = nil
	end
	if QuestInfoObjectivesText then
		QuestInfoObjectivesText.psGuideGrown = nil
		QuestInfoObjectivesText.psGuideFit = nil
	end
	ns.After(0, function()
		if gen ~= generation then return end
		place(questID)
	end)
end

---------------------------------------------------------------------------
-- Quest log, tracker, gossip, greeting
---------------------------------------------------------------------------

---@param pool ObjectPool
---@return fun(): PQI_TextHost
local function activeButtons(pool)
	return pool:EnumerateActive()
end

local function onLogUpdate()
	if ns.Hidden() then return end
	local pool = QuestScrollFrame and QuestScrollFrame.titleFramePool
	if not pool then return end
	for button in activeButtons(pool) do
		local q = readable(button.questID)
		if type(q) == "number" and q > 0 then
			applyMark(button.Text or button, q)
			bindTip(button, q, "ANCHOR_LEFT")
		else
			button.psGuideQuest = nil
		end
	end
end

---@param module PQI_Tracker
---@param quest PQI_TrackerQuest?
local function onTrackerUpdate(module, quest)
	if ns.Hidden() then return end
	if not quest or not quest.GetID or not module or not module.GetExistingBlock then return end
	local q = readable(quest:GetID())
	if type(q) ~= "number" then return end
	local block = module:GetExistingBlock(q)
	if not block then return end
	if block.HeaderText then applyMark(block.HeaderText, q) end
	bindTip(block, q, "ANCHOR_LEFT")
end

---@param button PQI_QuestButton
---@param questInfo PQI_GossipInfo
local function onGossipSetup(button, questInfo)
	if ns.Hidden() or type(questInfo) ~= "table" then return end
	local q = readable(questInfo.questID)
	if type(q) ~= "number" then return end
	applyMark(button, q, "gossip")
	bindTip(button, q, "ANCHOR_RIGHT")
end

local function onGreetingShow()
	if ns.Hidden() then return end
	local panel = QuestFrameGreetingPanel
	if not panel then return end
	---@cast panel PQI_GreetingPanel
	local pool = panel.titleButtonPool
	if not pool then return end
	for button in activeButtons(pool) do
		local i = button:GetID()
		---@type number?
		local q
		if button.isActive == 1 and GetActiveQuestID then
			---@type number?
			local picked = GetActiveQuestID(i)
			q = picked
		elseif GetAvailableQuestInfo then
			---@type number?
			local picked = select(5, GetAvailableQuestInfo(i))
			q = picked
		end
		local id = readable(q)
		if type(id) == "number" then
			applyMark(button, id, "greeting")
			bindTip(button, id, "ANCHOR_RIGHT")
		else
			button.psGuideQuest = nil
		end
	end
end

local SURFACES = {
	{
		ready = function()
			return type(QuestLogQuests_Update) == "function" and QuestScrollFrame ~= nil
		end,
		install = function() hooksecurefunc("QuestLogQuests_Update", onLogUpdate) end,
	},
	{
		ready = function() return type(QuestObjectiveTracker) == "table" and QuestObjectiveTracker.UpdateSingle ~= nil end,
		install = function() hooksecurefunc(QuestObjectiveTracker, "UpdateSingle", onTrackerUpdate) end,
	},
	{
		ready = function()
			return type(CampaignQuestObjectiveTracker) == "table" and CampaignQuestObjectiveTracker.UpdateSingle ~= nil
		end,
		install = function() hooksecurefunc(CampaignQuestObjectiveTracker, "UpdateSingle", onTrackerUpdate) end,
	},
	{
		ready = function()
			return type(GossipAvailableQuestButtonMixin) == "table" and type(GossipActiveQuestButtonMixin) == "table"
		end,
		install = function()
			hooksecurefunc(GossipAvailableQuestButtonMixin, "Setup", onGossipSetup)
			hooksecurefunc(GossipActiveQuestButtonMixin, "Setup", onGossipSetup)
		end,
	},
	{
		ready = function()
			return QuestFrameGreetingPanel ~= nil and type(QuestFrameGreetingPanel_OnShow) == "function"
		end,
		install = function()
			QuestFrameGreetingPanel:HookScript("OnShow", onGreetingShow)
			hooksecurefunc("QuestFrameGreetingPanel_OnShow", onGreetingShow)
		end,
	},
	{
		ready = function() return type(QuestInfo_Display) == "function" end,
		install = function() hooksecurefunc("QuestInfo_Display", onInfoDisplay) end,
	},
}

local pendingSurfaces = #SURFACES

---@return boolean
local function installReady()
	for i = 1, #SURFACES do
		local s = SURFACES[i]
		if not s.done and s.ready() then
			s.done = true
			pendingSurfaces = pendingSurfaces - 1
			s.install()
		end
	end
	return pendingSurfaces == 0
end

local function onAddonLoaded()
	if installReady() then ns.UnregisterEvent("ADDON_LOADED", onAddonLoaded) end
end

local hookedTips = setmetatable({}, { __mode = "k" })

---@param tt GameTooltip?
local function watchTooltip(tt)
	if not tt or not tt.HookScript or hookedTips[tt] then return end
	if tt.HasScript then
		local ok, supported = pcall(tt.HasScript, tt, "OnTooltipCleared")
		if ok and supported == false then return end
	end
	---@param self GameTooltip
	local function clearTip(self) tipped[self] = nil end
	local ok = pcall(tt.HookScript, tt, "OnTooltipCleared", clearTip)
	if ok then hookedTips[tt] = true end
end

local function installTips()
	local H = ns.Hooks
	if H and H.ItemLines then H.ItemLines("guideMarks", onItem) end
	watchTooltip(GameTooltip)
	watchTooltip(ItemRefTooltip)
	local P = TooltipDataProcessor
	local T = Enum and Enum.TooltipDataType
	if P and P.AddTooltipPostCall and T and T.Quest then
		P.AddTooltipPostCall(T.Quest, onQuestTip)
		return
	end
	---@param self GameTooltip
	---@param link string
	local function onLink(self, link)
		local id = questIdOf(nil, link)
		if id then addQuestLines(self, id) end
	end
	if GameTooltip and hooksecurefunc then hooksecurefunc(GameTooltip, "SetHyperlink", onLink) end
	if ItemRefTooltip and hooksecurefunc then hooksecurefunc(ItemRefTooltip, "SetHyperlink", onLink) end
end

local function refreshOpen()
	if ns.Hidden() then
		for _, overlay in pairs(overlays) do
			if overlay.Hide then overlay:Hide() end
		end
	end
	if type(QuestLogQuests_Update) == "function" then pcall(QuestLogQuests_Update) end
	if not ns.Hidden() and openQuest then place(openQuest) end
end

ns.On("GUIDES_REGISTERED", scheduleBuild)
ns.On("PACKS_CHANGED", scheduleBuild)
ns.On("POLESTAR_HIDDEN", refreshOpen)
ns.OnLogin(scheduleBuild)

ns.OnInit(function()
	installTips()
	if ns.GamepadUI() then return end
	if not installReady() then ns.RegisterEvent("ADDON_LOADED", onAddonLoaded) end
end)
