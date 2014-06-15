local addon = ...
local prefix = "<RBW>:"
local dndMsg = prefix .. " Encounter in progress: %s"
local combatEndedWin = prefix .. " Combat ended. Win against %s."
local combatEndedWipe = prefix .. " Combar ended. Wipe against %s."

local playerName = UnitName("player")

local db
local options = {
	disableChatFilter = false,
	whisperers = {},
}

local meta = {
	__index = function(tbl, key)
		if tbl == options then
			return nil -- TODO: I probably have to raise an error here or warn that I'm trying to access an undefined key
		end
		tbl[key] = options[key]
		return options[key]
	end
}

local BNET_CLIENT_WOW = BNET_CLIENT_WOW

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(self, event, ...) self[event](self, ...) end)
frame:RegisterEvent("ENCOUNTER_START")
frame:RegisterEvent("ENCOUNTER_END")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:RegisterEvent("CHAT_MSG_BN_WHISPER")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ADDON_LOADED")

local function GetReply(sender, msg, accountName, client)
	if (not client or client == BNET_CLIENT_WOW) and (type(sender) ~= "string" or playerName == sender or UnitInRaid(sender) or UnitInParty(sender)) then return end

	if not db.whisperers[accountName or sender] or msg == "status" then
		db.whisperers[accountName or sender] = true

		return string.format(dndMsg, client and client ~= BNET_CLIENT_WOW and db.encounterName or db.encounterLink)
	end
end

function frame:ENCOUNTER_START(encounterID, encounterName, difficultyID, size)
	db.encounterName = encounterName
	local i = 1
	while true do
		local _, _, _, name, _, _, _, link = EJ_GetMapEncounter(i)
		if not name then
			db.encounterLink = encounterName -- fall-back
			break
		elseif name == encounterName then
			db.encounterLink = link
			break
		end
		i = i + 1
	end
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

	local _, _, _, _, toonName, _, client = BNGetFriendInfoByID(presenceID)
	local reply = GetReply(toonName, msg, sender, client)
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

local FilterWhisper = function(chatframe, event, msg)
	if string.find(msg, "^" .. prefix) then
		return true
	end
end

local ToggleChatFilter = function(enable)
	if enable then
		ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", FilterWhisper)
		ChatFrame_AddMessageEventFilter("CHAT_MSG_BN_WHISPER_INFORM", FilterWhisper)
	else
		ChatFrame_RemoveMessageEventFilter("CHAT_MSG_WHISPER_INFORM", FilterWhisper)
		ChatFrame_RemoveMessageEventFilter("CHAT_MSG_BN_WHISPER_INFORM", FilterWhisper)
	end
end

local Command = function(msg, editbox)
	msg = string.lower(msg)
	if msg == "chatfilter" then
		db.disableChatFilter = not db.disableChatFilter
		ToggleChatFilter(db.disableChatFilter)
		print(prefix, "chat filter is", db.disableChatFilter and "OFF" or "ON")
	else
		print(prefix, "Unknown command:", msg)
	end
end

function frame:ADDON_LOADED(name)
	if name ~= addon then return end

	self:UnregisterEvent("ADDON_LOADED")

	rainBossWhispererDB = rainBossWhispererDB or options
	db = setmetatable(rainBossWhispererDB, meta)

	if not db.disableChatFilter then
		ToggleChatFilter(true)
	end

	SLASH_rainBossWhisperer1 = "/rbw"
	SLASH_rainBossWhisperer2 = "/rainBW"
	SlashCmdList[addon] = Command
end