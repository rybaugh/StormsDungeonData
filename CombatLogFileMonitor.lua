-- Combat Log File Monitor
-- Polls game state to auto-detect M+ run start/end and Hearthstone usage.
--
-- WoW 12+ broke ALL event-registration paths for addons:
--   Frame:RegisterEvent()                         – protected
--   EventRegistry:RegisterFrameEventAndCallback() – internally calls Frame:RegisterEvent()
--   EventUtil.ContinueOnEvent()                   – internally calls Frame:RegisterEvent()
--
-- We therefore avoid every event-registration API entirely and instead use
-- C_Timer.NewTicker to poll C_ChallengeMode and UnitCastingInfo on a short interval.
-- This is fully allowed in WoW 12+ and requires no frame or event registration.

local MPT = StormsDungeonData
MPT.CombatLogFileMonitor = MPT.CombatLogFileMonitor or {}
local Monitor = MPT.CombatLogFileMonitor

-- Configuration
Monitor.enabled       = true
Monitor.checkInterval = 0.5   -- Poll interval in seconds
Monitor.isMonitoring  = false
Monitor.ticker        = nil

-- Runtime state
Monitor.currentDungeon             = nil   -- Set when an M+ key is active
Monitor.lastZoneBeforeHearthstone  = nil
Monitor.lastActiveMapID            = nil   -- Tracks C_ChallengeMode map between ticks
Monitor.hearthstoneCastID          = nil   -- castID of the Hearthstone we are tracking

-- ─── Hearthstone detection helpers ───────────────────────────────────────────

-- Hearthstone and its variants all contain "Hearthstone" in the English locale
-- spell name. We match case-insensitively to be safe.
local HEARTHSTONE_PATTERN = "[Hh]earthstone"

local function IsHearthstoneSpell(spellName)
    return spellName and spellName:find(HEARTHSTONE_PATTERN) ~= nil
end

-- ─── Per-tick poll ────────────────────────────────────────────────────────────

function Monitor:Tick()
    -- ── 1. Challenge-mode change detection ──────────────────────────────────
    local activeMapID = C_ChallengeMode.GetActiveChallengeMapID()

    if activeMapID and activeMapID ~= self.lastActiveMapID then
        -- A new M+ key just became active (or the map changed).
        self.lastActiveMapID = activeMapID

        local keystoneLevel = select(1, C_ChallengeMode.GetActiveKeystoneInfo()) or 0
        local cmName        = C_ChallengeMode.GetMapUIInfo and select(1, C_ChallengeMode.GetMapUIInfo(activeMapID))
        local dungeonName   = (type(cmName) == "string" and cmName ~= "" and cmName) or ("Map " .. activeMapID)

        MPT.Log:Info("M+ started – " .. dungeonName .. " +" .. keystoneLevel)

        self.currentDungeon = {
            name          = dungeonName,
            mapID         = activeMapID,
            keystoneLevel = keystoneLevel,
            startTime     = time(),
        }
        self.lastZoneBeforeHearthstone = dungeonName

        -- Auto-start combat tracking if not already running.
        if MPT.CombatLog and MPT.CombatLog.StartTracking and not MPT.CombatLog.isTracking then
            MPT.Log:Info("Auto-starting combat tracking")
            MPT.CombatLog:StartTracking()
        end

    elseif not activeMapID and self.lastActiveMapID then
        -- The active challenge ended (timer expired, key completed, or left instance).
        self.lastActiveMapID = nil
        self:OnChallengeModeEnded()
    end

    -- ── 2. Hearthstone cast detection ───────────────────────────────────────
    -- UnitCastingInfo returns: name, text, texture, startMs, endMs, isTradeSkill,
    --                          castID, notInterruptible, spellID
    local castName, _, _, _, _, _, castID = UnitCastingInfo("player")

    if castName and IsHearthstoneSpell(castName) then
        if castID ~= self.hearthstoneCastID then
            -- New Hearthstone cast started; record it.
            self.hearthstoneCastID = castID
        end
    else
        if self.hearthstoneCastID then
            -- The tracked Hearthstone cast finished or was cancelled.
            -- Fire optimistically; the dungeon-match guard in OnHearthstoneUsed
            -- decides whether to actually save.
            self:OnHearthstoneUsed()
            self.hearthstoneCastID = nil
        end
    end
end

-- ─── State-change handlers ────────────────────────────────────────────────────

function Monitor:OnChallengeModeEnded()
    self.currentDungeon    = nil
    self.hearthstoneCastID = nil
end

function Monitor:OnHearthstoneUsed()
    MPT.Log:Info("Detected Hearthstone cast completion")

    if self.currentDungeon and self.lastZoneBeforeHearthstone then
        if self.currentDungeon.name == self.lastZoneBeforeHearthstone then
            MPT.Log:Info("Auto-logging run: "
                  .. self.currentDungeon.name .. " +" .. self.currentDungeon.keystoneLevel)

            -- Small delay so any last combat events are captured first.
            C_Timer.After(1, function()
                if MPT.PerformManualSave then
                    MPT.PerformManualSave("hearthstone_auto")
                elseif MPT.Events and MPT.Events.FinalizeRun then
                    MPT.Events:FinalizeRun("hearthstone_auto")
                end
            end)
        else
            MPT.Log:Info("Skipping auto-log: dungeon ("
                  .. self.currentDungeon.name .. ") doesn't match last zone ("
                  .. self.lastZoneBeforeHearthstone .. ")")
        end
    else
        MPT.Log:Info("No active dungeon to log")
    end

    self.currentDungeon = nil
end

-- ─── Monitoring lifecycle ─────────────────────────────────────────────────────

function Monitor:StartMonitoring()
    if self.isMonitoring then
        MPT.Log:Info("Combat log monitoring already active")
        return
    end

    -- Snapshot current challenge-mode state so the first tick doesn't false-fire.
    self.lastActiveMapID   = C_ChallengeMode.GetActiveChallengeMapID()
    self.hearthstoneCastID = nil

    -- C_Timer.NewTicker does NOT use Frame:RegisterEvent() internally.
    -- It is safe to call from any addon context in WoW 12+.
    self.ticker = C_Timer.NewTicker(self.checkInterval, function()
        self:Tick()
    end)

    self.isMonitoring = true
end

function Monitor:StopMonitoring()
    if not self.isMonitoring then
        return
    end

    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end

    self.isMonitoring = false
    MPT.Log:Info("Combat log monitoring stopped")
end

function Monitor:Initialize()
    if self.enabled then
        self:StartMonitoring()
    end
end

-- Clean up on disable
function Monitor:Shutdown()
    self:StopMonitoring()
end
