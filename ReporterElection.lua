-- Storm's Dungeon Data - Reporter Election Module
-- Transparently elects a single addon user in the party to handle auto-reporting
-- to party chat. Uses hidden addon messages over the "SDD" prefix.
--
-- Protocol:
--   On CHALLENGE_MODE_START (and on bootstrap recovery), each addon instance
--   that has auto-report enabled broadcasts a HELLO:<GUID> message.
--   Recipients reply with ACK:<GUID> (only if they also have auto-report on).
--   The designated reporter is the participant with the lexicographically
--   smallest GUID — a deterministic result every client computes identically.
--
--   Clients with auto-report disabled never broadcast and never join the
--   election. Manual "Report to Party" is never blocked.

local MPT = StormsDungeonData
MPT.ReporterElection = MPT.ReporterElection or {}
local Election = MPT.ReporterElection

local ADDON_PREFIX = "SDD"
local MSG_HELLO = "HELLO"
local MSG_ACK = "ACK"

-- State
Election.candidates = {}   -- GUID -> true  (only peers with auto-report enabled)
Election.myGUID = nil
Election._initialized = false

local function L(level, msg)
    if MPT.Log then MPT.Log:Log(level or "INFO", msg) end
end

-- Helper: is auto-report enabled on this client?
local function IsAutoReportEnabled()
    if StormsDungeonDataDB and StormsDungeonDataDB.settings then
        return StormsDungeonDataDB.settings.autoReportToParty == true
    end
    return false
end

-- Register the addon message prefix at file-load time (top-level, untainted).
C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)

-- Dedicated frame for addon-message and group lifecycle events.
local electionFrame = CreateFrame("Frame")
electionFrame:RegisterEvent("CHAT_MSG_ADDON")
electionFrame:RegisterEvent("GROUP_LEFT")

function Election:Initialize()
    if self._initialized then return end
    self._initialized = true
    self.myGUID = UnitGUID("player")
    self:Reset()
    L("INFO", "ReporterElection initialized, myGUID=" .. tostring(self.myGUID))
end

-- Reset candidates (call at the start of every new key).
function Election:Reset()
    self.candidates = {}
    if not self.myGUID then
        self.myGUID = UnitGUID("player")
    end
    -- Register self only if auto-report is enabled
    if self.myGUID and IsAutoReportEnabled() then
        self.candidates[self.myGUID] = true
    end
    L("INFO", "ReporterElection: state reset, autoReport=" .. tostring(IsAutoReportEnabled()))
end

-- Broadcast our presence to party members who also have the addon.
-- Only broadcasts when auto-report is enabled on this client.
function Election:BroadcastPresence()
    if not IsAutoReportEnabled() then return end

    if not self.myGUID then
        self.myGUID = UnitGUID("player")
    end
    if not self.myGUID then return end

    self.candidates[self.myGUID] = true

    if IsInGroup() then
        C_ChatInfo.SendAddonMessage(ADDON_PREFIX, MSG_HELLO .. ":" .. self.myGUID, "PARTY")
        L("INFO", "ReporterElection: broadcast HELLO")
    end
end

-- Handle incoming addon messages.
function Election:OnAddonMessage(prefix, message, distribution, sender)
    if prefix ~= ADDON_PREFIX then return end
    if distribution ~= "PARTY" then return end

    local msgType, guid = message:match("^(%a+):(.+)$")
    if not msgType or not guid or guid == "" then return end

    if msgType == MSG_HELLO then
        -- The sender has auto-report enabled; track them as a candidate.
        if not self.candidates[guid] then
            self.candidates[guid] = true
            L("INFO", "ReporterElection: discovered candidate via HELLO, GUID=" .. tostring(guid))
        end
        -- Reply only if we also have auto-report enabled.
        if IsAutoReportEnabled() and self.myGUID and IsInGroup() then
            self.candidates[self.myGUID] = true
            C_ChatInfo.SendAddonMessage(ADDON_PREFIX, MSG_ACK .. ":" .. self.myGUID, "PARTY")
        end
    elseif msgType == MSG_ACK then
        if not self.candidates[guid] then
            self.candidates[guid] = true
            L("INFO", "ReporterElection: discovered candidate via ACK, GUID=" .. tostring(guid))
        end
    end
end

-- Returns true when THIS client should be the one to auto-report.
-- Returns false if auto-report is disabled locally (user can still report manually).
function Election:IsDesignatedReporter()
    if not IsAutoReportEnabled() then
        return false
    end

    if not self.myGUID then
        self.myGUID = UnitGUID("player")
    end
    if not self.myGUID then return true end  -- safety fallback

    self.candidates[self.myGUID] = true

    local smallest = nil
    for guid in pairs(self.candidates) do
        if not smallest or guid < smallest then
            smallest = guid
        end
    end

    local isReporter = (smallest == self.myGUID)
    L("INFO", "ReporterElection: IsDesignatedReporter=" .. tostring(isReporter)
        .. " myGUID=" .. tostring(self.myGUID)
        .. " smallest=" .. tostring(smallest)
        .. " candidateCount=" .. tostring(self:GetCandidateCount()))
    return isReporter
end

-- How many candidates (addon users with auto-report enabled) we know about.
function Election:GetCandidateCount()
    local count = 0
    for _ in pairs(self.candidates) do
        count = count + 1
    end
    return count
end

-- Wire up events.
electionFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        Election:OnAddonMessage(...)
    elseif event == "GROUP_LEFT" then
        Election:Reset()
    end
end)
