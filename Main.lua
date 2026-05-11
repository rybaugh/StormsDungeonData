-- Mythic Plus Tracker - Main Module
-- Initializes UI and slash commands

local MPT = StormsDungeonData

local function GetMinimapAngleFromCursor()
    local mx, my = Minimap:GetCenter()
    if not mx or not my then
        return math.rad(225)
    end
    local scale = Minimap:GetEffectiveScale() or 1
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    return math.atan2(cy - my, cx - mx)
end

local function PositionMinimapButton(btn, angle)
    local radius = 72
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function IsLibDBIconRegistered()
    if not LibStub then
        return false
    end
    local dbIcon = LibStub("LibDBIcon-1.0", true)
    if not dbIcon or not dbIcon.IsRegistered then
        return false
    end
    return dbIcon:IsRegistered("StormsDungeonData")
end

local function CreateBasicMinimapButton(onClick)
    if not Minimap or not CreateFrame then
        return nil
    end
    local btn = _G["StormsDungeonDataMinimapButton"]
    if not btn then
        btn = CreateFrame("Button", "StormsDungeonDataMinimapButton", UIParent)
    end
    btn:SetSize(32, 32)
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel(200)
    btn:SetClampedToScreen(true)
    btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    btn:SetNormalTexture("Interface/AddOns/StormsDungeonData/stormsdungeondata_32x32")
    btn:SetPushedTexture("Interface/AddOns/StormsDungeonData/stormsdungeondata_32x32")
    btn:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")

    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
        GameTooltip:SetText("StormsDungeonData", 1, 1, 1)
        GameTooltip:AddLine("Left-click: Open history", 0.2, 1, 0.2)
        GameTooltip:AddLine("Right-click: Live dungeon tracker", 0.2, 1, 0.2)
        GameTooltip:AddLine("Drag to reposition", 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    if onClick then
        btn:SetScript("OnClick", onClick)
    end

    btn:SetScript("OnDragStart", function(self)
        self.isDragging = true
        self:SetScript("OnUpdate", function()
            PositionMinimapButton(self, GetMinimapAngleFromCursor())
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self.isDragging = false
        self:SetScript("OnUpdate", nil)

        local angle = GetMinimapAngleFromCursor()
        StormsDungeonDataDB = StormsDungeonDataDB or {}
        StormsDungeonDataDB.settings = StormsDungeonDataDB.settings or {}
        StormsDungeonDataDB.settings.minimap = StormsDungeonDataDB.settings.minimap or {}
        StormsDungeonDataDB.settings.minimap.angle = angle
        PositionMinimapButton(self, angle)
    end)

    local angle = math.rad(225)
    if StormsDungeonDataDB and StormsDungeonDataDB.settings and StormsDungeonDataDB.settings.minimap and StormsDungeonDataDB.settings.minimap.angle then
        angle = StormsDungeonDataDB.settings.minimap.angle
    end
    PositionMinimapButton(btn, angle)

    btn:Show()
    return btn
end

local function IsPlayerInCorrectDungeon()
    if not MPT.CurrentRunData or not MPT.CurrentRunData.dungeonID then
        return false
    end
    
    local _, instanceType, difficultyID = GetInstanceInfo()
    -- Must be in a Mythic+ dungeon (difficultyID 8 is Mythic Keystone)
    if instanceType ~= "party" or difficultyID ~= 8 then
        return false
    end
    
    -- Check if current challenge mode matches the pending run
    if C_ChallengeMode and type(C_ChallengeMode.GetActiveChallengeMapID) == "function" then
        local currentMapID = C_ChallengeMode.GetActiveChallengeMapID()
        if currentMapID and currentMapID == MPT.CurrentRunData.dungeonID then
            return true
        end
    end
    
    return false
end

-- Shared function for manual save logic (used by both minimap and slash command)
function MPT.PerformManualSave(source)
    -- Block duplicate saves while still inside the completed instance.
    -- RunJustSaved is set on successful FinalizeRun and cleared only when
    -- the challenge mode actually ends (player leaves the instance).
    if MPT.RunJustSaved then
        print("|cff00ffaa[StormsDungeonData]|r Save blocked: run already saved for this instance (source=" .. tostring(source) .. ")")
        return false
    end
    if MPT.Events and MPT.Events.RecordFlow then
        MPT.Events:RecordFlow("MANUAL_SAVE", "source=" .. tostring(source or "unknown"))
    end
    print("|cff00ffaa[StormsDungeonData]|r Manual save initiated (" .. (source or "unknown") .. ")...")
    
    -- Check combat tracking status
    if MPT.CombatLog then
        print("|cff00ffaa[StormsDungeonData]|r Combat tracking status: " .. (MPT.CombatLog.isTracking and "ACTIVE" or "INACTIVE"))
        if MPT.CombatLog.playerStats then
            local statsCount = 0
            local hasData = false
            for name, stats in pairs(MPT.CombatLog.playerStats) do
                statsCount = statsCount + 1
                if stats.damage > 0 or stats.healing > 0 or stats.interrupts > 0 then
                    hasData = true
                end
            end
            print("|cff00ffaa[StormsDungeonData]|r CombatLog has " .. statsCount .. " player entries, hasData=" .. tostring(hasData))
        end
    end
    -- If we have run data, show MVP ranking for each player (debug)
    if MPT.CurrentRunData and MPT.Scoreboard and MPT.Scoreboard.GetMVPRanking then
        local ranking = MPT.Scoreboard:GetMVPRanking(MPT.CurrentRunData)
        if ranking and #ranking > 0 then
            print("|cff00ffaa[StormsDungeonData]|r MVP ranking (balanced_roles):")
            for _, row in ipairs(ranking) do
                local rankLabel = (row.rank == 1) and "MVP #1" or ("#" .. row.rank)
                local d = row.damage and (row.damage >= 1e6 and string.format("%.2fM", row.damage/1e6) or (row.damage >= 1e3 and string.format("%.1fK", row.damage/1e3) or tostring(row.damage))) or "0"
                local h = row.healing and (row.healing >= 1e6 and string.format("%.2fM", row.healing/1e6) or (row.healing >= 1e3 and string.format("%.1fK", row.healing/1e3) or tostring(row.healing))) or "0"
                print(string.format("  %s |cffffcc00%s|r %s dmg=%s heal=%s int=%d score=%.3f", rankLabel, row.name or "?", row.role or "?", d, h, row.interrupts or 0, row.score or 0))
            end
        end
    end
    
    -- If no CurrentRunData exists, try to detect from active keystone FIRST, then history
    if not MPT.CurrentRunData then
        -- Priority 1: Try to build from active keystone (if we're currently in a dungeon)
        print("|cff00ffaa[StormsDungeonData]|r No pending run data, checking for active keystone...")
        if MPT.Events and MPT.Events.BuildRunDataFromActiveKeystone then
            local built = MPT.Events:BuildRunDataFromActiveKeystone()
            if built then
                print("|cff00ffaa[StormsDungeonData]|r Successfully built run data from active keystone!")
            else
                print("|cff00ffaa[StormsDungeonData]|r No active keystone found, trying run history...")
            end
        end
        
        -- Priority 2: Try to reconstruct from C_MythicPlus.GetRunHistory()
        if not MPT.CurrentRunData then
            if not C_MythicPlus then
                print("|cff00ffaa[StormsDungeonData]|r ERROR: C_MythicPlus API not available")
                return false
            end
            if not C_MythicPlus.GetRunHistory then
                print("|cff00ffaa[StormsDungeonData]|r ERROR: C_MythicPlus.GetRunHistory not available")
                return false
            end
            
                print("|cff00ffaa[StormsDungeonData]|r Attempting to reconstruct from run history...")
            local runHistory = C_MythicPlus.GetRunHistory(false, true)
            if runHistory and #runHistory > 0 then
            -- Log all runs found for debugging
            print("|cff00ffaa[StormsDungeonData]|r Found " .. #runHistory .. " runs in history:")
            for i, run in ipairs(runHistory) do
                local dungeonName = C_ChallengeMode.GetMapUIInfo(run.mapChallengeModeID)
                local dateStr = "no date"
                if run.completionDate then
                    if type(run.completionDate) == "table" then
                        dateStr = "table"
                    elseif type(run.completionDate) == "number" then
                        dateStr = tostring(run.completionDate)
                    else
                        dateStr = type(run.completionDate)
                    end
                end
                print("  [" .. i .. "] " .. (dungeonName or "Unknown") .. " +" .. run.level .. " (completed=" .. tostring(run.completed) .. ", date=" .. dateStr .. ")")
            end
            
            -- Find the most recent completed run by completionDate
            print("|cff00ffaa[StormsDungeonData]|r Starting run selection logic...")
            local latestRun = nil
            local latestDate = 0
            for i, run in ipairs(runHistory) do
                print("|cff00ffaa[StormsDungeonData]|r Checking run #" .. i .. ", completed=" .. tostring(run.completed) .. ", hasDate=" .. tostring(run.completionDate ~= nil))
                if run.completed then
                    if run.completionDate then
                        local runDate = run.completionDate
                        local timestamp = 0
                        if type(runDate) == "table" then
                            local success, result = pcall(time, runDate)
                            if success then
                                if result then
                                    timestamp = result
                                    print("|cff00ffaa[StormsDungeonData]|r Run #" .. i .. " date table converted to timestamp: " .. timestamp)
                                else
                                    print("|cff00ffaa[StormsDungeonData]|r Run #" .. i .. " date table conversion returned nil")
                                end
                            else
                                print("|cff00ffaa[StormsDungeonData]|r Run #" .. i .. " date table conversion FAILED: " .. tostring(result))
                            end
                        elseif type(runDate) == "number" then
                            timestamp = runDate
                            print("|cff00ffaa[StormsDungeonData]|r Run #" .. i .. " date number: " .. timestamp)
                        end
                        
                        if timestamp > latestDate then
                            latestDate = timestamp
                            latestRun = run
                            print("|cff00ffaa[StormsDungeonData]|r Run #" .. i .. " is now the latest (timestamp=" .. timestamp .. ")")
                        end
                    else
                        print("|cff00ffaa[StormsDungeonData]|r Run #" .. i .. " has no completionDate")
                    end
                else
                    print("|cff00ffaa[StormsDungeonData]|r Run #" .. i .. " is not completed")
                end
            end
            
            print("|cff00ffaa[StormsDungeonData]|r Selection complete. latestRun=" .. tostring(latestRun ~= nil) .. ", latestDate=" .. latestDate)
            
            -- Fallback to last completed run if no dates available
            if not latestRun then
                print("|cff00ffaa[StormsDungeonData]|r No completion dates found, searching for last completed run...")
                for i = #runHistory, 1, -1 do
                    if runHistory[i].completed then
                        latestRun = runHistory[i]
                        print("|cff00ffaa[StormsDungeonData]|r Using last completed run in array: #" .. i)
                        break
                    end
                end
            end
            
            if latestRun then
                local dungeonName = C_ChallengeMode.GetMapUIInfo(latestRun.mapChallengeModeID)
                print("|cff00ffaa[StormsDungeonData]|r Reconstructing from history: " .. (dungeonName or "Unknown") .. " +" .. latestRun.level .. " (mapID=" .. latestRun.mapChallengeModeID .. ")")
                
                if MPT.Events and MPT.Events.ReconstructRunDataFromHistory then
                    local success = MPT.Events:ReconstructRunDataFromHistory(latestRun)
                    if success and MPT.CurrentRunData then
                        print("|cff00ffaa[StormsDungeonData]|r Reconstructed: " .. tostring(MPT.CurrentRunData.dungeonName) .. " +" .. tostring(MPT.CurrentRunData.keystoneLevel) .. ", mapID=" .. tostring(MPT.CurrentRunData.mapID or MPT.CurrentRunData.dungeonID))
                        
                        -- Validate reconstructed data - but provide helpful diagnostic info
                        if not MPT.CurrentRunData.dungeonID or MPT.CurrentRunData.dungeonID == 0 then
                            print("|cffff4444[StormsDungeonData]|r ERROR: Reconstructed data has invalid dungeonID")
                            print("|cffff4444[StormsDungeonData]|r   mapChallengeModeID from history: " .. tostring(latestRun.mapChallengeModeID))
                            print("|cffff4444[StormsDungeonData]|r   This likely means WoW's API did not return the run properly")
                            print("|cffff4444[StormsDungeonData]|r   Try using /sdd force immediately after completing a key")
                            MPT.CurrentRunData = nil
                        end
                    else
                        print("|cffff4444[StormsDungeonData]|r ERROR: ReconstructRunDataFromHistory returned false or failed to create CurrentRunData")
                        print("|cffff4444[StormsDungeonData]|r   This means the run history entry was invalid")
                    end
                end
            else
                print("|cff00ffaa[StormsDungeonData]|r No completed runs found in history")
            end
        else
            print("|cff00ffaa[StormsDungeonData]|r No recent runs found in history")
        end
        end  -- Close the if runHistory block
    end  -- Close the if not MPT.CurrentRunData block
    
    -- If CurrentRunData still doesn't exist, try calling OnChallengeModeCompleted
    if not MPT.CurrentRunData and MPT.Events and MPT.Events.OnChallengeModeCompleted then
        print("|cff00ffaa[StormsDungeonData]|r Attempting to detect completion...")
        MPT.Events:OnChallengeModeCompleted()
    end
    
    local saved = false
    if MPT.Events and MPT.Events.FinalizeRun then
        saved = MPT.Events:FinalizeRun("manual") or false
    end
    if saved then
        if MPT.Events and MPT.Events.RecordFlow then
            MPT.Events:RecordFlow("MANUAL_SAVE_RESULT", "saved=true source=" .. tostring(source or "unknown"))
        end
        print("|cff00ffaa[StormsDungeonData]|r Run saved manually!")
        return true
    else
        if MPT.Events and MPT.Events.RecordFlow then
            MPT.Events:RecordFlow("MANUAL_SAVE_RESULT", "saved=false source=" .. tostring(source or "unknown"))
        end
        print("|cff00ffaa[StormsDungeonData]|r No pending run to save - try /sdd test or /sdd force")
        if C_ChallengeMode and C_ChallengeMode.GetCompletionInfo then
            local completionInfo = C_ChallengeMode.GetCompletionInfo()
            if completionInfo then
                print("|cff00ffaa[StormsDungeonData]|r DEBUG: GetCompletionInfo returned data but CurrentRunData was not created")
            else
                print("|cff00ffaa[StormsDungeonData]|r DEBUG: GetCompletionInfo returned nil - no completion detected")
            end
        end
        return false
    end
end

function MPT.UI:Initialize()
    -- Modules are loaded via the .toc file in order; don't overwrite them here.
    -- Just ensure tables exist so later calls don't hard error.
    MPT.Scoreboard = MPT.Scoreboard or {}
    MPT.HistoryViewer = MPT.HistoryViewer or {}
    
    local function OnMinimapClick(_, button)
        if button == "RightButton" then
            if MPT.LiveTrackerFrame and MPT.LiveTrackerFrame.Toggle then
                MPT.LiveTrackerFrame:Toggle()
            end
        else
            if MPT.Scoreboard and MPT.Scoreboard.Hide then
                MPT.Scoreboard:Hide()
            end
            MPT.HistoryViewer:Show()
        end
    end

    -- Minimap button is created via UI/MinimapButton.xml (fallback to code if XML fails)
    if not _G["StormsDungeonDataMinimapButton"] and MPT.UIUtils and MPT.UIUtils.CreateMinimapButton then
        MPT.UIUtils:CreateMinimapButton("StormsDungeonDataMinimapButton", "Interface/AddOns/StormsDungeonData/stormsdungeondata_32x32", OnMinimapClick)
    end
    if not _G["StormsDungeonDataMinimapButton"] and not IsLibDBIconRegistered() then
        CreateBasicMinimapButton(OnMinimapClick)
    end
    if _G["StormsDungeonDataMinimapButton"] then
        _G["StormsDungeonDataMinimapButton"]:Show()
        if _G["StormsDungeonDataMinimapButton"].ResetPosition then
            _G["StormsDungeonDataMinimapButton"]:ResetPosition()
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(2, function()
            if not _G["StormsDungeonDataMinimapButton"] and MPT.UIUtils and MPT.UIUtils.CreateMinimapButton then
                MPT.UIUtils:CreateMinimapButton("StormsDungeonDataMinimapButton", "Interface/AddOns/StormsDungeonData/stormsdungeondata_32x32", OnMinimapClick)
            end
            if not _G["StormsDungeonDataMinimapButton"] and not IsLibDBIconRegistered() then
                CreateBasicMinimapButton(OnMinimapClick)
            end
            if _G["StormsDungeonDataMinimapButton"] then
                _G["StormsDungeonDataMinimapButton"]:Show()
                if _G["StormsDungeonDataMinimapButton"].ResetPosition then
                    _G["StormsDungeonDataMinimapButton"]:ResetPosition()
                end
            end
        end)
    end
    
end

function MPT.UI:ShowScoreboard(runRecord)
    if MPT.HistoryViewer and MPT.HistoryViewer.Hide then
        MPT.HistoryViewer:Hide()
    end
    if MPT.Scoreboard and MPT.Scoreboard.Show then
        MPT.Scoreboard:Show(runRecord)
    end
end

-- Slash command handler function (defined at load time)
local function HandleSlashCommand(msg, editbox)
    msg = (msg or ""):lower():trim()
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = cmd or ""
    rest = rest or ""

    if cmd == "history" or cmd == "h" then
        MPT.HistoryViewer:Show()
    elseif cmd == "insights" or cmd == "i" then
        MPT.HistoryViewer:Show()
        if MPT.HistoryViewer and MPT.HistoryViewer.SetActivePage then
            MPT.HistoryViewer:SetActivePage("insights")
        end
    elseif cmd == "reset" then
        StormsDungeonDataDB = MPT.Database:CreateDefaultDB()
        print("|cff00ffaa[StormsDungeonData]|r Database reset!")
    elseif cmd == "status" then
        if MPT.Events and MPT.Events.TryBootstrapMythicPlusRun then
            if not MPT.InMythicPlus then
                MPT.Events:TryBootstrapMythicPlusRun("status_command", true)
            end
        end
        if MPT.InMythicPlus and MPT.Events and MPT.Events.EnsureCriteriaTrackingForActiveRun then
            MPT.Events:EnsureCriteriaTrackingForActiveRun("status_command")
        end
        print("|cff00ffaa[StormsDungeonData]|r Status:")
        print("  Total runs: " .. #StormsDungeonDataDB.runs)
        print("  Current run data exists: " .. tostring(MPT.CurrentRunData ~= nil))
        print("  In mythic plus: " .. tostring(MPT.InMythicPlus or false))
        if MPT.InMythicPlus then
            local recovered = (MPT.RunBootstrapRecovered == true)
            local reason = MPT.RunBootstrapReason or "none"
            local atTs = MPT.RunBootstrapAt or "n/a"
            print("  Bootstrap recovered this run: " .. tostring(recovered) .. " (reason=" .. tostring(reason) .. ", at=" .. tostring(atTs) .. ")")
        end
        if MPT.CurrentRunData then
            print("  Current run: " .. tostring(MPT.CurrentRunData.dungeonName) .. " +" .. tostring(MPT.CurrentRunData.keystoneLevel))
            print("  Completed: " .. tostring(MPT.CurrentRunData.completed))
            print("  Saved: " .. tostring(MPT.CurrentRunData.saved))
        end
        if MPT.RunCompletionRequirements then
            local req = MPT.RunCompletionRequirements
            local bossCount = tonumber(req.bossCount) or 0
            local mapID = tonumber(req.mapID) or 0
            local reqForces = tonumber(req.enemyForcesRequiredPercent) or 100
            print("  Completion requirements: mapID=" .. tostring(mapID) .. ", bosses=" .. tostring(bossCount) .. ", enemyForces>=" .. tostring(reqForces) .. "%")
        end
        if MPT.RunCompletionProgress then
            local p = MPT.RunCompletionProgress
            local bossesKilled = tonumber(p.bossesKilled) or 0
            local bossCount = tonumber(p.bossCount) or 0
            local bossesRemaining = tonumber(p.bossesRemaining) or math.max(0, bossCount - bossesKilled)
            local forcesPct = tonumber(p.forcesPercent) or 0
            local forcesRemaining = tonumber(p.enemyForcesRemainingPercent) or math.max(0, 100 - forcesPct)
            local pollRate = (MPT.Events and MPT.Events.criteriaCompletionPollInterval) or "n/a"
            print(string.format("  Completion progress: bosses=%d/%d (remaining=%d), enemyForces=%.1f%% (remaining=%.1f%%)", bossesKilled, bossCount, bossesRemaining, forcesPct, forcesRemaining))
            print("  Completion ready: bosses=" .. tostring(p.allBossesKilled) .. ", enemyForces=" .. tostring(p.forcesAtRequired) .. ", poll=" .. tostring(pollRate) .. "s")
        elseif MPT.InMythicPlus then
            print("  Completion progress: unavailable (waiting for scenario criteria data)")
        end
        print("  Type |cff00ffaa/sdd debug|r for player MVP ranking, |cff00ffaa/sdd history|r to view history")
    elseif cmd == "debug" then
        if not MPT.CurrentRunData then
            print("|cff00ffaa[StormsDungeonData]|r No current run data. Use |cff00ffaa/sdd save|r after a key or during a run to build run data, then /sdd debug.")
            return
        end
        print("|cff00ffaa[StormsDungeonData]|r Debug - " .. tostring(MPT.CurrentRunData.dungeonName) .. " +" .. tostring(MPT.CurrentRunData.keystoneLevel))
        if MPT.Scoreboard and MPT.Scoreboard.GetMVPRanking then
            local ranking = MPT.Scoreboard:GetMVPRanking(MPT.CurrentRunData)
            if ranking and #ranking > 0 then
                print("|cff00ffaa[StormsDungeonData]|r MVP ranking (balanced_roles) for each player:")
                for _, row in ipairs(ranking) do
                    local rankLabel = (row.rank == 1) and "MVP #1" or ("#" .. row.rank)
                    local d = row.damage and (row.damage >= 1e6 and string.format("%.2fM", row.damage/1e6) or (row.damage >= 1e3 and string.format("%.1fK", row.damage/1e3) or tostring(math.floor(row.damage)))) or "0"
                    local h = row.healing and (row.healing >= 1e6 and string.format("%.2fM", row.healing/1e6) or (row.healing >= 1e3 and string.format("%.1fK", row.healing/1e3) or tostring(math.floor(row.healing)))) or "0"
                    print(string.format("  %s |cffffcc00%s|r %s  dmg=%s  heal=%s  int=%d  score=%.3f", rankLabel, row.name or "?", row.role or "?", d, h, row.interrupts or 0, row.score or 0))
                end
            else
                print("|cff00ffaa[StormsDungeonData]|r No players in run data for MVP ranking.")
            end
        else
            print("|cff00ffaa[StormsDungeonData]|r Scoreboard/GetMVPRanking not available.")
        end
    elseif cmd == "test" then
        print("|cff00ffaa[StormsDungeonData]|r Testing completion detection...")
        if MPT.Events and MPT.Events.OnChallengeModeCompleted then
            MPT.Events:OnChallengeModeCompleted()
        end
    elseif cmd == "log" then
        if rest == "clear" or rest == "reset" then
            if MPT.Log then MPT.Log:Clear() end
            print("|cff00ffaa[StormsDungeonData]|r Log cleared.")
        elseif rest == "file" then
            if MPT.Log then MPT.Log:WriteToFile() end
        else
            local n = tonumber(rest)
            if MPT.Log then MPT.Log:DumpToChat(n or 100) end
        end
    elseif cmd == "events" then
        print("|cff00ffaa[StormsDungeonData]|r Testing event registration...")
        print("  Event frame exists: " .. tostring(MPT.Events and MPT.Events.frame ~= nil))
        if MPT.Events and MPT.Events.frame then
            print("  Frame registered for events: true")
            
            -- Check if frame is registered for CHALLENGE_MODE_COMPLETED
            local frame = MPT.Events.frame
            print("  Frame name: " .. tostring(frame:GetName() or "anonymous"))
            print("  Frame is shown: " .. tostring(frame:IsShown()))
            
            -- Try to manually check C_ChallengeMode
            if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
                local mapID = C_ChallengeMode.GetActiveChallengeMapID()
                print("  Active challenge map ID: " .. tostring(mapID))
            end
            if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
                local info = C_ChallengeMode.GetActiveKeystoneInfo()
                if type(info) == "table" then
                    print("  Active keystone: +" .. tostring(info.level or info.keystoneLevel))
                elseif info then
                    print("  Active keystone level: +" .. tostring(info))
                end
            end
        end
    elseif cmd == "flow" then
        local n = tonumber(rest) or 30
        if MPT.Events and MPT.Events.DumpFlowTrace then
            MPT.Events:DumpFlowTrace(n)
        else
            print("|cff00ffaa[StormsDungeonData]|r Flow trace is unavailable.")
        end
    elseif cmd == "" or cmd == "help" then
        print("|cff00ffaa[StormsDungeonData]|r Commands:")
        print("  |cff00ffaa/sdd history|r - Show run history")
        print("  |cff00ffaa/sdd insights|r - Show season insights")
        print("  |cff00ffaa/sdd status|r - Show addon status")
        print("  |cff00ffaa/sdd debug|r - Show current run players with MVP ranking")
        print("  |cff00ffaa/sdd log|r - Show last 100 action log lines (why run did/didn't save)")
        print("  |cff00ffaa/sdd log 500|r - Show last 500 lines")
        print("  |cff00ffaa/sdd log clear|r - Clear the log")
        print("  |cff00ffaa/sdd log file|r - Try to write log to file")
        print("  |cff00ffaa/sdd test|r - Test completion detection")
        print("  |cff00ffaa/sdd events|r - Test event registration")
        print("  |cff00ffaa/sdd flow [n]|r - Show recent event/save flow timeline")
        print("  |cff00ffaa/sdd reset|r - Reset database")
        print("  |cff00ffaa/sdd help|r - Show this message")
    else
        print("|cff00ffaa[StormsDungeonData]|r Unknown command: " .. msg)
    end
end

-- Register slash commands safely
-- Use pcall to prevent issues if SlashCmdList doesn't exist yet
if SlashCmdList then
    SLASH_STORMSDUNGEONDATA1 = "/sdd"
    SLASH_STORMSDUNGEONDATA2 = "/stormsdungeondata"
    SlashCmdList.STORMSDUNGEONDATA = HandleSlashCommand
end

