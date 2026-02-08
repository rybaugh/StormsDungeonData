-- Storm's Dungeon Data - LFG Rating Indicator
-- Shows good/bad player ratings in the Group Finder (search results and applicant list)

local MPT = StormsDungeonData
if not MPT or not MPT.Database then return end

local LFGRating = {}
MPT.LFGRatingIndicator = LFGRating

-- Cache our rating indicator frames per search-entry frame (reuse like PGF)
local ratingIndicators = {}

local function GetLeaderRatingIndicator(parent)
    local ind = ratingIndicators[parent]
    if not ind then
        ind = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ind:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
        ind:SetJustifyH("RIGHT")
        ind:Hide()
        ratingIndicators[parent] = ind
    end
    return ind
end

-- Display count: use stored count, or 1 if they were rated good before we tracked counts
local function GetDisplayGoodCount(playerName)
    if not MPT.Database or not playerName then return 0 end
    local goodCount = MPT.Database.GetPlayerGoodCount and MPT.Database:GetPlayerGoodCount(playerName) or 0
    if goodCount > 0 then return goodCount end
    local rating = MPT.Database.GetPlayerRating and MPT.Database:GetPlayerRating(playerName) or nil
    return (rating == "good") and 1 or 0
end

-- Display bad count: use stored count, or 1 if they were rated bad before we tracked counts
local function GetDisplayBadCount(playerName)
    if not MPT.Database or not playerName then return 0 end
    local badCount = MPT.Database.GetPlayerBadCount and MPT.Database:GetPlayerBadCount(playerName) or 0
    if badCount > 0 then return badCount end
    local rating = MPT.Database.GetPlayerRating and MPT.Database:GetPlayerRating(playerName) or nil
    return (rating == "bad") and 1 or 0
end

-- Short text for in-list (fits next to score/crown): "Good +5" and/or "Bad +3"
local function GetRatingText(leaderName)
    if not MPT.Database or not leaderName then return nil end
    local goodCount = GetDisplayGoodCount(leaderName)
    local badCount = GetDisplayBadCount(leaderName)
    if goodCount == 0 and badCount == 0 then return nil end
    local parts = {}
    if goodCount > 0 then
        parts[#parts + 1] = "|cff00ff00Good +" .. goodCount .. "|r"
    end
    if badCount > 0 then
        parts[#parts + 1] = "|cffff4444Bad +" .. badCount .. "|r"
    end
    return #parts > 0 and table.concat(parts, "  ") or nil
end

-- Update in-list indicator for one search result frame
local function UpdateSearchEntryIndicator(frame)
    if not frame or not frame.resultID then return end
    local info = C_LFGList and C_LFGList.GetSearchResultInfo and C_LFGList.GetSearchResultInfo(frame.resultID)
    if not info or not info.leader then return end
    local text = GetRatingText(info.leader)
    local ind = GetLeaderRatingIndicator(frame)
    if text then
        ind:SetText(text)
        ind:Show()
    else
        ind:Hide()
    end
end

-- Hook tooltip when hovering a search result (group listing)
local function OnSearchEntryTooltip(tooltip, resultID, autoAcceptOption)
    if not resultID or not tooltip or not tooltip.AddLine then return end
    local info = C_LFGList and C_LFGList.GetSearchResultInfo and C_LFGList.GetSearchResultInfo(resultID)
    if not info or not info.leader then return end
    local goodCount = GetDisplayGoodCount(info.leader)
    local badCount = GetDisplayBadCount(info.leader)
    if goodCount == 0 and badCount == 0 then return end
    tooltip:AddLine(" ")
    if goodCount > 0 then
        tooltip:AddLine("|cff00ff00Storm's Dungeon Data: Good player +" .. goodCount .. "|r")
    end
    if badCount > 0 then
        tooltip:AddLine("|cffff4444Storm's Dungeon Data: Bad player +" .. badCount .. "|r")
    end
    tooltip:Show()
end

-- Applicant list: add rating to tooltip when hovering an applicant (when you're leader viewing applicants)
local applicantHooks = {}
local function HookApplicantMemberTooltip(memberButton)
    if not memberButton or applicantHooks[memberButton] then return end
    applicantHooks[memberButton] = true
    memberButton:HookScript("OnEnter", function(self)
        local parent = self:GetParent()
        if not parent or not parent.applicantID then return end
        local applicantID, memberIdx = parent.applicantID, self.memberIdx
        if not applicantID or not memberIdx then return end
        local fullName = C_LFGList and C_LFGList.GetApplicantMemberInfo and C_LFGList.GetApplicantMemberInfo(applicantID, memberIdx)
        if not fullName then return end
        local goodCount = GetDisplayGoodCount(fullName)
        local badCount = GetDisplayBadCount(fullName)
        if goodCount == 0 and badCount == 0 then return end
        if GameTooltip:IsShown() then
            GameTooltip:AddLine(" ")
            if goodCount > 0 then
                GameTooltip:AddLine("|cff00ff00Storm's Dungeon Data: Good player +" .. goodCount .. "|r")
            end
            if badCount > 0 then
                GameTooltip:AddLine("|cffff4444Storm's Dungeon Data: Bad player +" .. badCount .. "|r")
            end
            GameTooltip:Show()
        end
    end)
end

local function OnSearchPanelFramesChanged(buttons)
    if not buttons then return end
    for _, frame in pairs(buttons) do
        if frame and frame.resultID then
            UpdateSearchEntryIndicator(frame)
        end
    end
end

local function OnApplicationViewerFramesChanged(buttons)
    if not buttons then return end
    for _, applicantFrame in pairs(buttons) do
        if applicantFrame and applicantFrame.Members then
            for _, memberBtn in pairs(applicantFrame.Members) do
                if type(memberBtn) == "table" and (memberBtn.memberIdx or memberBtn.GetScript) then
                    HookApplicantMemberTooltip(memberBtn)
                end
            end
        end
    end
end

function LFGRating:RefreshSearchIndicators()
    if not initialized then return end
    local searchPanel = LFGListFrame and LFGListFrame.SearchPanel
    if searchPanel and searchPanel.ScrollBox and searchPanel.ScrollBox.GetFrames then
        OnSearchPanelFramesChanged(searchPanel.ScrollBox:GetFrames())
    end
end

function LFGRating:Initialize()
    if not LFGListFrame then return end
    local searchPanel = LFGListFrame.SearchPanel
    local appViewer = LFGListFrame.ApplicationViewer
    if not searchPanel or not searchPanel.ScrollBox then return end

    -- Tooltip: add our rating line when hovering a group
    hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", OnSearchEntryTooltip)

    -- In-list: show [+] or [-] next to each group row for the leader's rating
    local scrollBox = searchPanel.ScrollBox
    local onUpdateEvent = ScrollBoxListMixin and ScrollBoxListMixin.Event and ScrollBoxListMixin.Event.OnUpdate
    if scrollBox and scrollBox.RegisterCallback and onUpdateEvent then
        scrollBox:RegisterCallback(onUpdateEvent, function()
            OnSearchPanelFramesChanged(scrollBox:GetFrames())
        end)
        -- Initial pass after a short delay so frames exist
        C_Timer.After(0.5, function()
            if scrollBox and scrollBox.GetFrames then
                OnSearchPanelFramesChanged(scrollBox:GetFrames())
            end
        end)
    end

    -- Refresh indicators when new search results arrive
    local refreshFrame = CreateFrame("Frame")
    refreshFrame:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
    refreshFrame:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
    refreshFrame:SetScript("OnEvent", function()
        C_Timer.After(0.1, function()
            LFGRating:RefreshSearchIndicators()
        end)
    end)

    -- Applicants (when you're leader): add rating to tooltip when hovering an applicant
    if appViewer and appViewer.ScrollBox and appViewer.ScrollBox.RegisterCallback and onUpdateEvent then
        appViewer.ScrollBox:RegisterCallback(onUpdateEvent, function()
            OnApplicationViewerFramesChanged(appViewer.ScrollBox:GetFrames())
        end)
    end

    print("|cff00ffaa[StormsDungeonData]|r LFG rating indicators enabled (Group Finder)")
end

-- Run when addon is loaded; LFG frame may not exist yet
local initialized = false
local function TryInit()
    if initialized then return true end
    if LFGListFrame and LFGListFrame.SearchPanel then
        LFGRating:Initialize()
        initialized = true
        return true
    end
    return false
end

if TryInit() then
    print("|cff00ffaa[StormsDungeonData]|r LFG Rating Indicator module loaded")
    return
end

-- Wait for LFG frame (user may not have opened Group Finder yet)
local waitFrame = CreateFrame("Frame")
waitFrame:RegisterEvent("ADDON_LOADED")
waitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
waitFrame:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
waitFrame:SetScript("OnEvent", function(_, event)
    if TryInit() then
        waitFrame:UnregisterAllEvents()
    end
end)

print("|cff00ffaa[StormsDungeonData]|r LFG Rating Indicator module loaded (will activate when Group Finder is used)")
