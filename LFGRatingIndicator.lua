-- Storm's Dungeon Data - LFG Rating Indicator
-- Shows good/bad player ratings in the Group Finder (search results and applicant list)

local MPT = StormsDungeonData
if not MPT or not MPT.Database then return end

local LFGRating = {}
MPT.LFGRatingIndicator = LFGRating

-- Display count: total good ratings across all runs for this player
local function GetDisplayGoodCount(playerName)
    if not MPT.Database or not playerName then return 0 end
    return MPT.Database.GetPlayerGoodCount and MPT.Database:GetPlayerGoodCount(playerName) or 0
end

-- Display bad count: total bad ratings across all runs for this player
local function GetDisplayBadCount(playerName)
    if not MPT.Database or not playerName then return 0 end
    return MPT.Database.GetPlayerBadCount and MPT.Database:GetPlayerBadCount(playerName) or 0
end

local function FormatRatingLine(playerName)
    local goodCount = GetDisplayGoodCount(playerName)
    local badCount = GetDisplayBadCount(playerName)
    local ratingText
    if goodCount > 0 and badCount > 0 then
        ratingText = "|cff00ff00+" .. goodCount .. " Good|r / |cffff4444+" .. badCount .. " Bad|r"
    elseif goodCount > 0 then
        ratingText = "|cff00ff00+" .. goodCount .. " Good|r"
    elseif badCount > 0 then
        ratingText = "|cffff4444+" .. badCount .. " Bad|r"
    else
        ratingText = "|cffffffffNo rating yet|r"
    end
    return ratingText
end

-- Dedup: track the last resultID we added lines for on this tooltip.
local sddLastResultID = nil

-- Hook tooltip when hovering a search result (group listing)
local function OnSearchEntryTooltip(tooltip, resultID, autoAcceptOption)
    if not resultID then return end
    if sddLastResultID == resultID then return end
    sddLastResultID = resultID
    if not tooltip or not tooltip.AddLine then return end
    local info = C_LFGList and C_LFGList.GetSearchResultInfo and C_LFGList.GetSearchResultInfo(resultID)
    if not info then return end

    -- Gather all members
    local numMembers = info.numMembers or 0
    local members = {}
    if C_LFGList.GetSearchResultMemberInfo then
        for i = 1, numMembers do
            local name = C_LFGList.GetSearchResultMemberInfo(resultID, i)
            if name then
                members[#members + 1] = name
            end
        end
    end
    -- Fallback to leader only
    if #members == 0 and info.leaderName then
        members[1] = info.leaderName
    end
    if #members == 0 then return end

    tooltip:AddLine(" ")
    if #members == 1 then
        tooltip:AddLine("|cff00ffaaStorm's Dungeon Data:|r " .. FormatRatingLine(members[1]))
    else
        tooltip:AddLine("|cff00ffaaStorm's Dungeon Data|r")
        for _, name in ipairs(members) do
            local shortName = name:match("^([^%-]+)") or name
            tooltip:AddLine("  " .. shortName .. ": " .. FormatRatingLine(name))
        end
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
        if GameTooltip:IsShown() then
            GameTooltip:AddLine("|cff00ffaaStorm's Dungeon Data:|r " .. FormatRatingLine(fullName))
            GameTooltip:Show()
        end
    end)
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

function LFGRating:Initialize()
    if not LFGListFrame then return end
    local searchPanel = LFGListFrame.SearchPanel
    local appViewer = LFGListFrame.ApplicationViewer
    if not searchPanel or not searchPanel.ScrollBox then return end

    -- Tooltip: add our rating line when hovering a group
    hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", OnSearchEntryTooltip)

    -- Reset dedup guard when tooltip is cleared for a new target
    GameTooltip:HookScript("OnTooltipCleared", function()
        sddLastResultID = nil
    end)

    -- Applicants (when you're leader): add rating to tooltip when hovering an applicant
    local onUpdateEvent = ScrollBoxListMixin and ScrollBoxListMixin.Event and ScrollBoxListMixin.Event.OnUpdate
    if appViewer and appViewer.ScrollBox and appViewer.ScrollBox.RegisterCallback and onUpdateEvent then
        appViewer.ScrollBox:RegisterCallback(onUpdateEvent, function()
            OnApplicationViewerFramesChanged(appViewer.ScrollBox:GetFrames())
        end)
    end

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

