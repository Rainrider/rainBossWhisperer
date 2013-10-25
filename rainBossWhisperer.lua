local addon = ...
local prefix = "<RBW>: "
local dndMsg = prefix .. "Encounter in progress %s: %s"
local combatEndedMsg = prefix .. "Combat ended."
local bossFormat = "%s (%d%%)" -- name (health%)

local playerName = UnitName("player")
local disableChatFilter = true

local bosses = {}
local whisperers = {}
local encounters = {}
--[[
	[encounterIndex] = {
		[link] = select(5, GetEncounterInfoByIndex(encounterIndex, instanceID))
		[bossName1] = true
		[bossName2] = true
	}
]]
local currentEncounterLink = ""

local debug = true

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(self, event, msg, ...) self[event](self, msg, ...) end)
frame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:RegisterEvent("CHAT_MSG_BN_WHISPER")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("ADDON_LOADED")

local function Debug(...)
	if not debug then return end

	print(prefix, ...)
end

local function GetReply(sender, msg, presenceID, client)
	if (not client or client == "WoW") and (type(sender) ~= "string" or playerName == sender or UnitInRaid(sender) or UnitInParty(sender)) then return end

	if not whisperers[presenceID or sender] or msg == "status" then
		whisperers[presenceID or sender] = true
		local str = ""
		for i = 1, MAX_BOSS_FRAMES do
			local unit = "boss" .. i
			if UnitExists(unit) then
				str = str .. string.format(bossFormat, UnitName(unit), math.floor(UnitHealth(unit) / UnitHealthMax(unit) * 100 + 0.5))
			end
		end
		-- TODO: message length should not be > 255 characters (utf8 aware)
		--		 SendChatMessage truncates to 255 chars, BNSendWhisper fails silently
		--		 use strlenutf8()
		return string.format(dndMsg, currentEncounterLink, str)
	end
end

function frame:PLAYER_ENTERING_WORLD()
	self:ZONE_CHANGED_NEW_AREA()
	self:INSTANCE_ENCOUNTER_ENGAGE_UNIT()
end

-- XXX: does not fire after reloadui
function frame:ZONE_CHANGED_NEW_AREA()
	if not IsAddOnLoaded("Blizzard_EncounterJournal") then
		LoadAddOn("Blizzard_EncounterJournal")
	end

	local instanceID = EJ_GetCurrentInstance()
	
	if not instanceID or instanceID == 0 then
		Debug("Not in an instance", instanceID)
		return
	end

	local encounterIndex = 1
	local _, _, encounterID, _, encounterLink = EJ_GetEncounterInfoByIndex(encounterIndex, instanceID)
	while encounterID do
		encounters[encounterIndex] = {}
		encounters[encounterIndex]["link"] = encounterLink

		local creatureIndex = 1
		local _, bossName = EJ_GetCreatureInfo(creatureIndex, encounterID)
		while bossName do
			encounters[encounterIndex][bossName] = true
			creatureIndex = creatureIndex + 1
			_, bossName = EJ_GetCreatureInfo(creatureIndex, encounterID)
		end

		encounterIndex = encounterIndex + 1
		_, _, encounterID, _, encounterLink = EJ_GetEncounterInfoByIndex(encounterIndex, instanceID)
	end

	if debug then
		if not IsAddOnLoaded("Blizzard_DebugTools") then
			LoadAddOn("Blizzard_DebugTools")
		end
		DevTools_Dump(encounters)
	end

end

-- XXX: does not fire after reloadui
function frame:INSTANCE_ENCOUNTER_ENGAGE_UNIT()
	wipe(bosses)
	for i = 1, MAX_BOSS_FRAMES do
		local unit = "boss" .. i
		-- Shado-Pan Garrison daily quests display your companion as a boss
		-- UnitClassification returns "normal" and UnitName returns nil for non-present units
		if UnitClassification(unit) ~= "normal" then
			bosses[#bosses + 1] = UnitName(unit)
		end
	end

	Debug("Bosses:", #bosses, "CurrentEncounter:", currentEncounterLink)

	if currentEncounterLink ~= "" then return end -- so we don't set this multiple times per encounter

	for i = 1, #bosses do
		for j = 1, #encounters do
			if encounters[j][bosses[i]] then
				currentEncounterLink = encounters[j]["link"]
				break
			end
		end
		if currentEncounterLink ~= "" then break end
	end
end

-- TODO: does this fire for dead units?
function frame:PLAYER_REGEN_ENABLED()
	for player in pairs(whisperers) do
		local presenceID = tonumber(player)
		if presenceID then
			BNSendWhisper(presenceID, combatEndedMsg)
		else
			SendChatMessage(combatEndedMsg, "WHISPER", nil, player)
		end
	end
	currentEncounterLink = ""
	wipe(bosses)
	wipe(whisperers)
end

function frame:CHAT_MSG_WHISPER(msg, sender, _, _, _, flag)
	if flag == "GM" or (#bosses == 0 and currentEncounterLink == "") then return end

	local reply = GetReply(sender, msg)
	if reply then
		SendChatMessage(reply, "WHISPER", nil, sender)
	end
end

function frame:CHAT_MSG_BN_WHISPER(msg, sender, _, _, _, _, _, _, _, _, _, _, presenceID)
	if #bosses == 0 and currentEncounterLink == "" then return end

	local _, _, _, _, toonName, _, client = BNGetFriendInfoByID(presenceID) -- client: WoW, D3
	local reply = GetReply(toonName, msg, presenceID, client)
	if reply then
		BNSendWhisper(presenceID, reply)
	end
end

function frame:ADDON_LOADED(name)
	if name ~= addon then return end

	self:UnregisterEvent("ADDON_LOADED")

	if not disableChatFilter then
		ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", function(self, event, msg)
			if string.find(msg, "^" .. prefix) then return true end
		end)
		ChatFrame_AddMessageEventFilter("CHAT_MSG_BN_WHISPER_INFORM", function(self, event, msg)
			if string.find(msg, "^" .. prefix) then return true end
		end)
	end
end