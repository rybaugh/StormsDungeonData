-- Live Dungeon Tracker - Data module
-- Records point-in-time snapshots per player (cumulative totals). One line per player; never decreases.

local MPT = StormsDungeonData
local LiveTracker = {}
MPT.LiveTracker = LiveTracker

local function L(level, msg)
    if MPT.Log then MPT.Log:Log(level or "INFO", "[LiveTracker] " .. tostring(msg)) end
end

LiveTracker.startTime = nil       -- set when M+ starts
LiveTracker.dataPoints = {}      -- { { elapsed, players = { [name] = { damage, healing, interrupts } } }, ... }
LiveTracker.bossKills = {}       -- { elapsed1, elapsed2, ... }
LiveTracker.periodicTicker = nil -- C_Timer ticker for backup snapshots
LiveTracker.lastCumulative = {}  -- { [name] = { damage, healing, interrupts } } so we never chart a decrease
LiveTracker.exitCombatRetryTicker = nil -- short-lived retry ticker after leaving combat
LiveTracker.lastEventSnapshotAt = 0 -- throttle combat-event driven snapshots
LiveTracker.collectionActive = false -- collect during active key only; keep graph data after stop
LiveTracker.timelineEndElapsed = nil -- freeze x-axis at key end
LiveTracker.combatSessions = {}              -- { { startElapsed, endElapsed, players = { [name] = { dps, hps } } }, ... }
LiveTracker.currentSessionStartElapsed = nil  -- M+ elapsed when current combat session started
LiveTracker.combatStartTotals = {}            -- { [name] = { damage, healing } } snapshot at enter-combat for delta fallback
LiveTracker.processedSessionIDs = {}          -- set of API sessionIDs already appended to combatSessions
LiveTracker.runStartKnownSessionIDs = {}      -- API sessionIDs that existed before this run started (excluded)

function LiveTracker:RefreshIfVisible()
    if MPT.LiveTrackerFrame and MPT.LiveTrackerFrame.IsVisible and MPT.LiveTrackerFrame:IsVisible() and MPT.LiveTrackerFrame.RefreshChart then
        MPT.LiveTrackerFrame:RefreshChart()
    end
end

-- Returns true if we cannot collect data right now (e.g. in combat / restricted)
local function IsDataRestricted()
    if MPT.DamageMeterCompat and MPT.DamageMeterCompat.IsWoW12Plus and MPT.DamageMeterCompat.IsRestricted then
        if Enum and Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Combat then
            if MPT.DamageMeterCompat:IsRestricted(Enum.AddOnRestrictionType.Combat) then
                return true
            end
        end
    end
    return false
end

-- Canonicalize player names so "Name" and "Name-Realm" map to one series.
local function CanonicalPlayerName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local short = name:match("^([^%-]+)%-.+$")
    return short or name
end

-- Get current totals per player. Returns { [playerName] = { damage, healing, interrupts, deaths, avoidableDamageTaken } } or nil if we cannot collect (e.g. restricted).
function LiveTracker:GetCurrentTotalsPerPlayer()
    local restricted = IsDataRestricted()
    L("INFO", "GetCurrentTotalsPerPlayer: restricted=" .. tostring(restricted) .. " DamageMeterCompat.IsWoW12Plus=" .. tostring(MPT.DamageMeterCompat and MPT.DamageMeterCompat.IsWoW12Plus) .. " CombatLog.playerStats=" .. tostring(MPT.CombatLog and MPT.CombatLog.playerStats ~= nil))
    local players = {}
    local function ensurePlayer(name)
        local key = CanonicalPlayerName(name)
        if not key then return nil end
        if not players[key] then
            players[key] = { damage = 0, healing = 0, interrupts = 0, deaths = 0, avoidableDamageTaken = 0 }
        end
        return key
    end

    -- Prefer C_DamageMeter when available, but do NOT hard-stop on restrictions:
    -- we can still build timeline points from CombatLog fallback data.
    if (not restricted) and MPT.DamageMeterCompat and MPT.DamageMeterCompat.IsWoW12Plus then
        local dmgData = MPT.DamageMeterCompat:GetDamageData()
        local healData = MPT.DamageMeterCompat:GetHealingData()
        local intData = MPT.DamageMeterCompat:GetInterruptData()
        if dmgData then
            for name, stats in pairs(dmgData) do
                local key = ensurePlayer(name)
                if key then
                    local d = type(stats.damage) == "number" and stats.damage or 0
                    players[key].damage = math.max(players[key].damage or 0, d)
                end
            end
        end
        for name, stats in pairs(healData or {}) do
            local key = ensurePlayer(name)
            if key then
                local h = type(stats.healing) == "number" and stats.healing or 0
                players[key].healing = math.max(players[key].healing or 0, h)
            end
        end
        for name, stats in pairs(intData or {}) do
            local mappedName = name
            if MPT.CombatLog and type(stats) == "table" then
                local sourceGUID = stats.sourceGUID or stats.guid
                if sourceGUID ~= nil then
                    sourceGUID = tostring(sourceGUID)
                end

                -- Prefer GUID ownership when available.
                local ownerName = sourceGUID and MPT.CombatLog.petOwnerNameByGUID and MPT.CombatLog.petOwnerNameByGUID[sourceGUID] or nil

                -- Fallback for GUID-less pet entries from C_DamageMeter.
                if (not ownerName or ownerName == "") and type(name) == "string" and MPT.CombatLog.petOwnerByPetName then
                    ownerName = MPT.CombatLog.petOwnerByPetName[name]
                end

                -- Disabled: scanning live pet units can hit protected/secret strings in tainted execution.
                -- Keep ownership resolution to GUID and CombatLog name cache only.

                if ownerName and ownerName ~= "" then
                    mappedName = ownerName
                end
            end

            local key = ensurePlayer(mappedName)
            if key then
                local i = type(stats.interrupts) == "number" and stats.interrupts or 0
                players[key].interrupts = math.max(players[key].interrupts or 0, i)
            end
        end
    end

    if MPT.CombatLog and MPT.CombatLog.playerStats then
        for name, stats in pairs(MPT.CombatLog.playerStats) do
            local key = ensurePlayer(name)
            if key and stats then
                -- Max, not sum: CombatLog may contain both short and realm keys.
                players[key].damage = math.max(players[key].damage or 0, stats.damage or 0)
                players[key].healing = math.max(players[key].healing or 0, stats.healing or 0)
                players[key].interrupts = math.max(players[key].interrupts or 0, stats.interrupts or 0)
                players[key].deaths = math.max(players[key].deaths or 0, stats.deaths or 0)
                players[key].avoidableDamageTaken = math.max(players[key].avoidableDamageTaken or 0, stats.avoidableDamageTaken or 0)
            end
        end
    end

    if not next(players) then
        -- Keep a flat line when we cannot read fresh totals this tick.
        if self.lastCumulative and next(self.lastCumulative) then
            L("WARN", "GetCurrentTotalsPerPlayer: no live data, carrying forward lastCumulative")
            local carry = {}
            for name, stats in pairs(self.lastCumulative) do
                carry[name] = {
                    damage = stats.damage or 0,
                    healing = stats.healing or 0,
                    interrupts = stats.interrupts or 0,
                    deaths = stats.deaths or 0,
                    avoidableDamageTaken = stats.avoidableDamageTaken or 0,
                }
            end
            return carry
        end
        L("WARN", "GetCurrentTotalsPerPlayer: no live data AND no lastCumulative - returning nil")
        return nil
    end
    local resultCount = 0
    for _ in pairs(players) do resultCount = resultCount + 1 end
    L("INFO", "GetCurrentTotalsPerPlayer: returning " .. resultCount .. " player(s)")
    return players
end

-- Elapsed seconds since run start (synced with M+ timer)
function LiveTracker:GetElapsed()
    if not self.startTime then
        return 0
    end
    -- Use C_ChallengeMode.GetStartTime() to sync with the M+ timer if available
    if C_ChallengeMode and type(C_ChallengeMode.GetStartTime) == "function" then
        local apiStart = C_ChallengeMode.GetStartTime()
        if apiStart and apiStart > 0 then
            if type(GetTimePreciseSec) == "function" then
                return math.max(0, GetTimePreciseSec() - apiStart / 1000)
            else
                return math.max(0, GetTime() - apiStart / 1000)
            end
        end
    end
    -- Fallback to our own timer if API unavailable
    if type(GetTimePreciseSec) == "function" then
        return math.max(0, GetTimePreciseSec() - self.startTime)
    end
    return math.max(0, time() - self.startTime)
end

function LiveTracker:GetTimelineMaxElapsed()
    local maxElapsed = 0
    if self.dataPoints then
        for _, p in ipairs(self.dataPoints) do
            if p.elapsed and p.elapsed > maxElapsed then
                maxElapsed = p.elapsed
            end
        end
    end
    if self.collectionActive then
        maxElapsed = math.max(maxElapsed, self:GetElapsed())
    elseif self.timelineEndElapsed and self.timelineEndElapsed > 0 then
        maxElapsed = math.max(maxElapsed, self.timelineEndElapsed)
    end
    return maxElapsed
end

-- True if we have an active run session and are in a dungeon (so we should record points)
function LiveTracker:ShouldRecord()
    local ok = self.startTime ~= nil and self.collectionActive == true
    if not ok then
        L("DEBUG", "ShouldRecord=false startTime=" .. tostring(self.startTime) .. " collectionActive=" .. tostring(self.collectionActive))
    end
    return ok
end

-- Add one snapshot (used by OnExitCombat and periodic ticker). Skips if data cannot be collected (e.g. in combat).
-- Enforces cumulative: each player's value is max(current, previous) so the line never goes down.
-- Only adds a new data point if values have changed since the last snapshot.
function LiveTracker:AddSnapshot()
    L("INFO", "AddSnapshot called - startTime=" .. tostring(self.startTime) .. " collectionActive=" .. tostring(self.collectionActive) .. " dataPoints=" .. tostring(#(self.dataPoints or {})))
    if not self:ShouldRecord() then
        L("WARN", "AddSnapshot: ShouldRecord=false, skipping")
        return false
    end
    local raw = self:GetCurrentTotalsPerPlayer()
    if not raw or not next(raw) then
        L("WARN", "AddSnapshot: GetCurrentTotalsPerPlayer returned empty - raw=" .. tostring(raw))
        return false
    end
    local playerCount = 0
    for _ in pairs(raw) do playerCount = playerCount + 1 end
    L("INFO", "AddSnapshot: got data for " .. playerCount .. " players at elapsed=" .. string.format("%.1f", self:GetElapsed()))
    local elapsed = self:GetElapsed()
    local players = {}
    local dataChanged = false
    for name, stats in pairs(raw) do
        local last = self.lastCumulative[name]
        local d = type(stats.damage) == "number" and stats.damage or 0
        local h = type(stats.healing) == "number" and stats.healing or 0
        local i = type(stats.interrupts) == "number" and stats.interrupts or 0
        local deaths = type(stats.deaths) == "number" and stats.deaths or 0
        local avoidable = type(stats.avoidableDamageTaken) == "number" and stats.avoidableDamageTaken or 0
        if last then
            d = math.max(d, last.damage or 0)
            h = math.max(h, last.healing or 0)
            i = math.max(i, last.interrupts or 0)
            deaths = math.max(deaths, last.deaths or 0)
            avoidable = math.max(avoidable, last.avoidableDamageTaken or 0)
            -- Check if any value changed
            if d ~= last.damage or h ~= last.healing or i ~= last.interrupts or deaths ~= last.deaths or avoidable ~= last.avoidableDamageTaken then
                dataChanged = true
            end
        else
            -- New player, always a change
            dataChanged = true
        end
        -- Calculate DPS and HPS
        local dps = (elapsed > 0) and (d / elapsed) or 0
        local hps = (elapsed > 0) and (h / elapsed) or 0
        players[name] = { 
            damage = d, 
            healing = h, 
            interrupts = i, 
            deaths = deaths, 
            avoidableDamageTaken = avoidable,
            dps = dps,
            hps = hps
        }
        self.lastCumulative[name] = { damage = d, healing = h, interrupts = i, deaths = deaths, avoidableDamageTaken = avoidable }
    end
    -- Only add the snapshot if data has changed
    if dataChanged then
        table.insert(self.dataPoints, {
            elapsed = elapsed,
            players = players,
        })
        L("INFO", "AddSnapshot: snapshot added at elapsed=" .. string.format("%.1f", elapsed) .. " totalPoints=" .. tostring(#self.dataPoints))
        return true
    end
    L("INFO", "AddSnapshot: no data change, skipping insert (totalPoints=" .. tostring(#self.dataPoints) .. ")")
    return false
end

-- Called when player enters combat (PLAYER_REGEN_DISABLED). Records where this session starts on the timeline.
function LiveTracker:OnEnterCombat()
    if not self:ShouldRecord() then return end
    self.currentSessionStartElapsed = self:GetElapsed()
    -- Snapshot current cumulative totals so we can compute per-session delta as a fallback
    -- when C_DamageMeter amountPerSecond is unavailable.
    local raw = self:GetCurrentTotalsPerPlayer()
    self.combatStartTotals = {}
    if raw then
        for name, stats in pairs(raw) do
            self.combatStartTotals[name] = { damage = stats.damage or 0, healing = stats.healing or 0 }
        end
    end
    L("INFO", "OnEnterCombat: session starts at elapsed=" .. string.format("%.1f", self.currentSessionStartElapsed))
end

-- Capture per-session DPS/HPS and append to combatSessions.  Called when combat ends.
-- Primary path: iterates GetAvailableCombatSessions(), reads amountPerSecond (real session
-- DPS/HPS) via GetCombatSessionFromID() for each newly-completed session, and maps those
-- sessions onto the M+ timeline using our REGEN-event timestamps as anchors.
-- Fallback (pre-WoW 12 / restricted): delta-from-CombatLog divided by session wall-time.
function LiveTracker:CaptureSessionDPSHPS()
    if not self.currentSessionStartElapsed then return end
    local trackedStart = self.currentSessionStartElapsed
    local trackedEnd   = self:GetElapsed()
    local trackedDuration = trackedEnd - trackedStart

    self.currentSessionStartElapsed = nil   -- clear before any early return

    if trackedDuration < 0.5 then
        L("INFO", "CaptureSessionDPSHPS: session too short (" .. string.format("%.2f", trackedDuration) .. "s), discarding")
        self.combatStartTotals = {}
        return
    end

    -- ── Primary path: C_DamageMeter.GetAvailableCombatSessions() ──────────────
    -- Find every completed session (has durationSeconds) that:
    --   1. Was not present when this M+ run started (runStartKnownSessionIDs)
    --   2. Has not already been recorded (processedSessionIDs)
    -- These are the pulls that happened since the run began and ended just now.
    if MPT.DamageMeterCompat and MPT.DamageMeterCompat.IsWoW12Plus
            and MPT.DamageMeterCompat.GetAllSessionsWithStats then
        local allSessions = MPT.DamageMeterCompat:GetAllSessionsWithStats()
        if allSessions then
            -- Collect unprocessed, completed, in-run sessions (sorted by sessionID asc).
            local newSessions = {}
            for _, s in ipairs(allSessions) do
                local sid = s.sessionID
                if s.durationSeconds and s.durationSeconds > 0
                        and not self.runStartKnownSessionIDs[sid]
                        and not self.processedSessionIDs[sid] then
                    table.insert(newSessions, s)
                end
            end

            if #newSessions > 0 then
                -- Map new sessions onto the M+ timeline.
                -- The last new session ends at trackedEnd (our REGEN event anchor).
                -- Work backwards for any earlier sessions using their durationSeconds.
                local curEnd = trackedEnd
                for i = #newSessions, 1, -1 do
                    local s = newSessions[i]
                    local dur = s.durationSeconds
                    local sesStart, sesEnd
                    if i == #newSessions then
                        -- Use our REGEN-event timestamps for the most-recently-ended session
                        -- for the best accuracy; fall back to API duration when they diverge badly.
                        local regenDur = trackedEnd - trackedStart
                        if math.abs(dur - regenDur) < regenDur * 0.25 then
                            -- Within 25% — trust our REGEN boundary
                            sesStart = trackedStart
                        else
                            sesStart = trackedEnd - dur
                        end
                        sesEnd = trackedEnd
                    else
                        -- For any older missed sessions: place immediately before the next one
                        sesEnd   = curEnd
                        sesStart = math.max(0, curEnd - dur)
                    end
                    curEnd = sesStart

                    -- Build canonical-name player map from raw API names.
                    local players = {}
                    for rawName, stats in pairs(s.players or {}) do
                        local key = CanonicalPlayerName(rawName)
                        if key then
                            players[key] = {
                                dps = (type(stats.dps) == "number" and stats.dps or 0),
                                hps = (type(stats.hps) == "number" and stats.hps or 0),
                            }
                        end
                    end

                    if next(players) then
                        table.insert(self.combatSessions, {
                            startElapsed = math.max(0, sesStart),
                            endElapsed   = sesEnd,
                            players      = players,
                        })
                        L("INFO", "CaptureSessionDPSHPS[API]: sid=" .. s.sessionID
                            .. " name='" .. tostring(s.name) .. "'"
                            .. " dur=" .. string.format("%.1f", dur)
                            .. "s mapped to " .. string.format("%.1f", sesStart)
                            .. "->" .. string.format("%.1f", sesEnd))
                    end
                    self.processedSessionIDs[s.sessionID] = true
                end
                self.combatStartTotals = {}
                return  -- done via API path
            else
                L("WARN", "CaptureSessionDPSHPS: no new/unprocessed sessions in API list (allSessions=" .. #allSessions .. ")")
            end
        else
            L("WARN", "CaptureSessionDPSHPS: GetAllSessionsWithStats returned nil (restricted or no sessions)")
        end
    end

    -- ── Fallback: CombatLog delta / session wall-time ─────────────────────────
    L("INFO", "CaptureSessionDPSHPS: using CombatLog delta fallback")
    local dpsPerPlayer = {}
    local hpsPerPlayer = {}
    if MPT.CombatLog and MPT.CombatLog.playerStats then
        for name, stats in pairs(MPT.CombatLog.playerStats) do
            local key = CanonicalPlayerName(name)
            if key and stats then
                local startStats = self.combatStartTotals[key] or {}
                local dmgDelta  = math.max(0, (stats.damage  or 0) - (startStats.damage  or 0))
                local healDelta = math.max(0, (stats.healing or 0) - (startStats.healing or 0))
                dpsPerPlayer[key] = dmgDelta  / trackedDuration
                hpsPerPlayer[key] = healDelta / trackedDuration
            end
        end
    end
    local allNames = {}
    for name in pairs(dpsPerPlayer) do allNames[name] = true end
    for name in pairs(hpsPerPlayer) do allNames[name] = true end
    if next(allNames) then
        local players = {}
        for name in pairs(allNames) do
            players[name] = { dps = dpsPerPlayer[name] or 0, hps = hpsPerPlayer[name] or 0 }
        end
        table.insert(self.combatSessions, {
            startElapsed = trackedStart,
            endElapsed   = trackedEnd,
            players      = players,
        })
        L("INFO", "CaptureSessionDPSHPS[fallback]: "
            .. string.format("%.1f", trackedStart) .. "->" .. string.format("%.1f", trackedEnd))
    else
        L("WARN", "CaptureSessionDPSHPS: no player data from fallback either")
    end
    self.combatStartTotals = {}
end

-- Called when player exits combat (PLAYER_REGEN_ENABLED)
function LiveTracker:OnExitCombat()
    L("INFO", "OnExitCombat fired - ShouldRecord=" .. tostring(self:ShouldRecord()))
    -- Capture per-session DPS/HPS before the regular cumulative snapshot.
    self:CaptureSessionDPSHPS()
    local function tryCapture()
        L("INFO", "OnExitCombat:tryCapture attempt - collectionActive=" .. tostring(self.collectionActive) .. " startTime=" .. tostring(self.startTime))
        local ok = self:AddSnapshot()
        L("INFO", "OnExitCombat:tryCapture result=" .. tostring(ok))
        if ok then
            self:RefreshIfVisible()
        end
        return ok
    end

    self:RefreshIfVisible()
    if tryCapture() then
        L("INFO", "OnExitCombat: first attempt succeeded")
        return
    end
    L("WARN", "OnExitCombat: first attempt failed, scheduling retries")

    -- Combat restrictions/session updates may clear a bit later on WoW 12+.
    -- Retry for a short window so we still capture the post-pull point consistently.
    if self.exitCombatRetryTicker then
        self.exitCombatRetryTicker:Cancel()
        self.exitCombatRetryTicker = nil
    end
    if C_Timer and C_Timer.NewTicker then
        local attempts = 0
        self.exitCombatRetryTicker = C_Timer.NewTicker(0.5, function(ticker)
            attempts = attempts + 1
            local stillTracking = MPT and MPT.LiveTracker and MPT.LiveTracker.ShouldRecord and MPT.LiveTracker:ShouldRecord()
            L("INFO", "OnExitCombat retry #" .. attempts .. " stillTracking=" .. tostring(stillTracking))
            if not stillTracking then
                L("WARN", "OnExitCombat retry #" .. attempts .. ": tracking stopped, cancelling retries")
                ticker:Cancel()
                if MPT and MPT.LiveTracker and MPT.LiveTracker.exitCombatRetryTicker == ticker then
                    MPT.LiveTracker.exitCombatRetryTicker = nil
                end
                return
            end

            if tryCapture() then
                L("INFO", "OnExitCombat retry #" .. attempts .. ": succeeded")
                ticker:Cancel()
                if MPT.LiveTracker.exitCombatRetryTicker == ticker then
                    MPT.LiveTracker.exitCombatRetryTicker = nil
                end
                return
            end

            if attempts >= 12 then -- ~6 seconds max
                L("WARN", "OnExitCombat retry: gave up after " .. attempts .. " attempts")
                ticker:Cancel()
                if MPT.LiveTracker.exitCombatRetryTicker == ticker then
                    MPT.LiveTracker.exitCombatRetryTicker = nil
                end
            end
        end)
    end
end

-- Lightweight Details-like capture behavior: while combat events stream in,
-- checkpoint cumulative totals at most once per second.
function LiveTracker:CaptureFromCombatEvent()
    if not self:ShouldRecord() then
        -- ShouldRecord already logs when false
        return
    end
    local now = time()
    local timeSinceLast = self.lastEventSnapshotAt and (now - self.lastEventSnapshotAt) or 999
    if timeSinceLast < 1 then
        L("DEBUG", "CaptureFromCombatEvent: throttled (" .. string.format("%.2f", timeSinceLast) .. "s since last)")
        return
    end
    L("INFO", "CaptureFromCombatEvent: capturing (" .. string.format("%.2f", timeSinceLast) .. "s since last)")
    self.lastEventSnapshotAt = now
    if self:AddSnapshot() then
        self:RefreshIfVisible()
    end
end

-- Called when a boss is killed (ENCOUNTER_END success=1)
function LiveTracker:RecordBossKill()
    if not self.startTime then
        return
    end

    local elapsed = self:GetElapsed()
    if (not self.collectionActive) and self.timelineEndElapsed and self.timelineEndElapsed > 0 then
        -- CHALLENGE_MODE_END can stop collection before the final ENCOUNTER_END arrives.
        -- In that race, pin the final boss marker to the frozen run end time.
        elapsed = self.timelineEndElapsed
    end

    local last = self.bossKills[#self.bossKills]
    if last and math.abs((tonumber(last) or 0) - (tonumber(elapsed) or 0)) < 0.25 then
        return
    end

    table.insert(self.bossKills, elapsed)
end

-- Stop periodic snapshot timer (call when leaving instance)
function LiveTracker:StopPeriodicSnapshot()
    L("INFO", "StopPeriodicSnapshot called - periodicTicker=" .. tostring(self.periodicTicker ~= nil) .. " exitRetry=" .. tostring(self.exitCombatRetryTicker ~= nil))
    if self.periodicTicker then
        self.periodicTicker:Cancel()
        self.periodicTicker = nil
    end
    if self.exitCombatRetryTicker then
        self.exitCombatRetryTicker:Cancel()
        self.exitCombatRetryTicker = nil
    end
    self.collectionActive = false
    L("INFO", "StopPeriodicSnapshot: collectionActive=false")
end

-- Stop collecting further points, but keep current graph data visible.
function LiveTracker:StopCollection()
    local elapsed = self:GetElapsed()
    L("INFO", "StopCollection called at elapsed=" .. string.format("%.1f", elapsed) .. " totalPoints=" .. tostring(#(self.dataPoints or {})))
    self.timelineEndElapsed = elapsed
    self:StopPeriodicSnapshot()
end

-- Reset at start of new M+ run (CHALLENGE_MODE_START). Data is kept after exit so the tracker can be viewed outside the dungeon until the next run starts.
-- Collection starts immediately regardless of window visibility.
function LiveTracker:Reset()
    L("INFO", "Reset() called - stopping previous ticker if any")
    self:StopPeriodicSnapshot()
    -- Use C_ChallengeMode.GetStartTime() for M+ timer sync if available, otherwise fallback to current time
    if C_ChallengeMode and type(C_ChallengeMode.GetStartTime) == "function" then
        local apiStart = C_ChallengeMode.GetStartTime()
        L("INFO", "Reset: C_ChallengeMode.GetStartTime() returned " .. tostring(apiStart))
        if apiStart and apiStart > 0 then
            self.startTime = apiStart / 1000
            L("INFO", "Reset: startTime set from API = " .. tostring(self.startTime))
        else
            self.startTime = (type(GetTimePreciseSec) == "function") and GetTimePreciseSec() or time()
            L("WARN", "Reset: GetStartTime returned 0/nil - fallback startTime=" .. tostring(self.startTime))
        end
    else
        self.startTime = (type(GetTimePreciseSec) == "function") and GetTimePreciseSec() or time()
        L("WARN", "Reset: C_ChallengeMode.GetStartTime not available - fallback startTime=" .. tostring(self.startTime))
    end
    self.dataPoints = {}
    self.bossKills = {}
    self.lastCumulative = {}
    self.lastEventSnapshotAt = 0
    self.collectionActive = true
    self.timelineEndElapsed = nil
    self.combatSessions = {}
    self.currentSessionStartElapsed = nil
    self.combatStartTotals = {}
    self.processedSessionIDs = {}
    -- Snapshot which API sessionIDs already existed before this run so we never
    -- accidentally consume a leftover session from a previous dungeon or world-boss.
    self.runStartKnownSessionIDs = {}
    if MPT.DamageMeterCompat and MPT.DamageMeterCompat.IsWoW12Plus
            and MPT.DamageMeterCompat.GetAvailableSessions then
        for _, s in ipairs(MPT.DamageMeterCompat:GetAvailableSessions()) do
            local sid = s.sessionID
            if sid then self.runStartKnownSessionIDs[sid] = true end
        end
        L("INFO", "Reset: snapshotted " .. (function() local n=0 for _ in pairs(self.runStartKnownSessionIDs) do n=n+1 end return n end)() .. " pre-run sessionID(s)")
    end
    L("INFO", "Reset: collectionActive=true, startTime=" .. tostring(self.startTime))
    -- Initial point at run start (elapsed 0; player totals filled in by first snapshot)
    table.insert(self.dataPoints, {
        elapsed = 0,
        players = {},
    })
    -- Backup: add snapshots every 5s to avoid missing long in-combat windows.
    if C_Timer then
        local tickCount = 0
        self.periodicTicker = C_Timer.NewTicker(5, function()
            tickCount = tickCount + 1
            L("INFO", "PeriodicTicker tick #" .. tickCount .. " - collectionActive=" .. tostring(MPT.LiveTracker and MPT.LiveTracker.collectionActive) .. " startTime=" .. tostring(MPT.LiveTracker and MPT.LiveTracker.startTime) .. " elapsed=" .. string.format("%.1f", MPT.LiveTracker and MPT.LiveTracker:GetElapsed() or 0))
            if MPT.LiveTracker and MPT.LiveTracker.AddSnapshot then
                local ok = MPT.LiveTracker:AddSnapshot()
                L("INFO", "PeriodicTicker tick #" .. tickCount .. " AddSnapshot result=" .. tostring(ok))
            else
                L("ERROR", "PeriodicTicker tick #" .. tickCount .. ": LiveTracker.AddSnapshot not available")
            end
        end)
        L("INFO", "Reset: 5s periodic ticker started")
    else
        L("ERROR", "Reset: C_Timer not available - no periodic ticker started!")
    end
end

-- Clear (not used on exit; data is kept so tracker is viewable after run)
function LiveTracker:Clear()
    self.startTime = nil
    self.dataPoints = {}
    self.bossKills = {}
    self.lastCumulative = {}
end

function LiveTracker:GetDataPoints()
    return self.dataPoints
end

function LiveTracker:GetBossKills()
    return self.bossKills
end

function LiveTracker:GetCombatSessions()
    return self.combatSessions
end

function LiveTracker:IsActive()
    return self.startTime ~= nil and self.collectionActive == true
end

