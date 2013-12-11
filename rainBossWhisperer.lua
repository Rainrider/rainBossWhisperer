local addon = ...
local prefix = "<RBW>: "
local dndMsg = prefix .. "Encounter in progress %s: %s"
local combatEndedWin = prefix .. "Combat ended. Win against %s."
local combatEndedWipe = prefix .. "Combar ended. Wipe against %s."
local bossFormat = " %s (%d%%)" -- name (health%)

local playerName = UnitName("player")
local disableChatFilter = true

local whisperers = {}

local encounterLinkFormat = "|cff66bbff|Hjournal:1:%d:%d|h[%s]|h|r" -- encounterID, difficultyID, name
local encounterLink
local encounterName

local debug = false

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(self, event, ...) self[event](self, ...) end)
frame:RegisterEvent("ENCOUNTER_START")
frame:RegisterEvent("ENCOUNTER_END")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:RegisterEvent("CHAT_MSG_BN_WHISPER")
frame:RegisterEvent("ADDON_LOADED")

local function Debug(...)
	if not debug then return end

	print(prefix, ...)
end

local function GetReply(sender, msg, presenceID, client)
	if (not client or client == "WoW") and (type(sender) ~= "string" or playerName == sender or UnitInRaid(sender) or UnitInParty(sender)) then return end

	if not whisperers[presenceID or sender] or msg == "status" then
		whisperers[presenceID or sender] = client and client or "WoW"
		local str = ""
		for i = 1, MAX_BOSS_FRAMES do
			local unit = "boss" .. i
			if UnitExists(unit) then
				str = str .. string.format(bossFormat, UnitName(unit), math.floor(UnitHealth(unit) / UnitHealthMax(unit) * 100 + 0.5))
			end
		end
		-- message length should not be > 255 characters (utf8 aware)
		-- SendChatMessage truncates to 255 chars, BNSendWhisper fails silently
		local reply = string.format(dndMsg, client and client ~= "WoW" and encounterName or encounterLink, str)

		if strlenutf8(reply) > 255 then
			reply = string.format(dndMsg, client and client ~= "WoW" and encounterName or encounterLink, "")
		end

		return reply
	end
end

function frame:ENCOUNTER_START(encounterID, name, difficultyID, size)
	encounterLink = string.format(encounterLinkFormat, encounterID, difficultyID, name)
	encounterName = name
end

function frame:ENCOUNTER_END(_, _, _, _, success)
	for player, client in pairs(whisperers) do
		local presenceID = tonumber(player)
		local reply = string.format(success == 1 and combatEndedWin or combatEndedWipe, client == "WoW" and encounterLink or encounterName)
		if presenceID then
			BNSendWhisper(presenceID, reply)
		else
			SendChatMessage(reply, "WHISPER", nil, player)
		end
	end
	encounterLink = nil
	encounterName = nil
	wipe(whisperers)
end

function frame:CHAT_MSG_WHISPER(msg, sender, _, _, _, flag)
	if flag == "GM" or not encounterLink then return end

	local reply = GetReply(sender, msg)
	if reply then
		SendChatMessage(reply, "WHISPER", nil, sender)
	end
end

function frame:CHAT_MSG_BN_WHISPER(msg, _, _, _, _, _, _, _, _, _, _, _, presenceID)
	if not encounterLink then return end

	local _, _, _, _, toonName, _, client = BNGetFriendInfoByID(presenceID) -- client: WoW, D3, ...
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