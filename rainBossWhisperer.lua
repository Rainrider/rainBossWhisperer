local addon = ...
local prefix = "<RBW>: "
local dndMsg = prefix .. "Encounter in progress %s: %s"
local combatEndedWin = prefix .. "Combat ended. Win against %s."
local combatEndedWipe = prefix .. "Combar ended. Wipe against %s."
local bossFormat = " %s (%d%%)" -- name (health%)

local playerName = UnitName("player")

local encounterLinkFormat = "|cff66bbff|Hjournal:1:%d:%d|h[%s]|h|r" -- encounterID, difficultyID, name

local db
local options = {
	disableChatFilter = false,
	whisperers = {},
}

local debug = false

local BNET_CLIENT_WOW = BNET_CLIENT_WOW

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(self, event, ...) self[event](self, ...) end)
frame:RegisterEvent("ENCOUNTER_START")
frame:RegisterEvent("ENCOUNTER_END")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:RegisterEvent("CHAT_MSG_BN_WHISPER")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ADDON_LOADED")

local function Debug(...)
	if not debug then return end

	print(prefix, ...)
end

local function GetReply(sender, msg, accountName, client)
	if (not client or client == BNET_CLIENT_WOW) and (type(sender) ~= "string" or playerName == sender or UnitInRaid(sender) or UnitInParty(sender)) then return end

	if not db.whisperers[accountName or sender] or msg == "status" then
		db.whisperers[accountName or sender] = true
		local str = ""
		for i = 1, MAX_BOSS_FRAMES do
			local unit = "boss" .. i
			if UnitExists(unit) then
				str = str .. string.format(bossFormat, UnitName(unit), math.floor(UnitHealth(unit) / UnitHealthMax(unit) * 100 + 0.5))
			end
		end
		-- message length should not be > 255 characters (utf8 aware)
		-- SendChatMessage truncates to 255 chars, BNSendWhisper fails silently
		local reply = string.format(dndMsg, client and client ~= BNET_CLIENT_WOW and db.encounterName or db.encounterLink, str)

		if strlenutf8(reply) > 255 then
			reply = string.format(dndMsg, client and client ~= BNET_CLIENT_WOW and db.encounterName or db.encounterLink, "")
		end

		return reply
	end
end

function frame:ENCOUNTER_START(encounterID, name, difficultyID, size)
	db.encounterLink = string.format(encounterLinkFormat, encounterID, difficultyID, name)
	db.encounterName = name
end

function frame:ENCOUNTER_END(_, _, _, _, success)
	for player in pairs(db.whisperers) do
		local presenceID = BNet_GetPresenceID(player)
		if presenceID then
			local _, _, _, _, _, _, client, isOnline = BNGetFriendInfoByID(presenceID)
			if isOnline then
				local reply = string.format(success == 1 and combatEndedWin or combatEndedWipe, client == BNET_CLIENT_WOW and db.encounterLink or db.encounterName)
				BNSendWhisper(presenceID, reply)
			end
		else
			-- TODO: check online status before sending messages
			local reply = string.format(success == 1 and combatEndedWin or combatEndedWipe, db.encounterLink)
			SendChatMessage(reply, "WHISPER", nil, player)
		end
	end
	db.encounterLink = nil
	db.encounterName = nil
	wipe(db.whisperers)
end

function frame:CHAT_MSG_WHISPER(msg, sender, _, _, _, flag)
	if flag == "GM" or not db.encounterLink then return end

	local reply = GetReply(sender, msg)
	if reply then
		SendChatMessage(reply, "WHISPER", nil, sender)
	end
end

function frame:CHAT_MSG_BN_WHISPER(msg, sender, _, _, _, _, _, _, _, _, _, _, presenceID)
	if not db.encounterLink then return end

	local _, accountName, _, _, toonName, _, client = BNGetFriendInfoByID(presenceID) -- client: WoW, D3, ...
	local reply = GetReply(toonName, msg, accountName, client)
	if reply then
		BNSendWhisper(presenceID, reply)
	end
end

function frame:PLAYER_ENTERING_WORLD()
	if db.encounterLink and not IsEncounterInProgress() then
		db.encounterLink = nil
		db.encounterName = nil
	end
end

function frame:ADDON_LOADED(name)
	if name ~= addon then return end

	self:UnregisterEvent("ADDON_LOADED")

	rainBossWhispererDB = rainBossWhispererDB or options
	db = rainBossWhispererDB

	if not debug and not db.disableChatFilter then
		ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", function(self, event, msg)
			if string.find(msg, "^" .. prefix) then return true end
		end)
		ChatFrame_AddMessageEventFilter("CHAT_MSG_BN_WHISPER_INFORM", function(self, event, msg)
			if string.find(msg, "^" .. prefix) then return true end
		end)
	end
end