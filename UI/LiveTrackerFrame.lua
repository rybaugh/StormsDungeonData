-- Live Dungeon Tracker - UI Frame with line graph
-- Toggle Damage / Healing / Interrupts; marks boss kills on the chart

local MPT = StormsDungeonData
local LiveTrackerFrame = {}
MPT.LiveTrackerFrame = LiveTrackerFrame

local CHART_PADDING = 40
local CHART_WIDTH = 420
local CHART_HEIGHT = 200
local LINE_THICKNESS = 2
local MAX_PLAYERS = 5
local MAX_SEGMENTS_PER_PLAYER = 400
local MAX_POINTS_PER_PLAYER = 201
local MAX_SEGMENTS = MAX_PLAYERS * MAX_SEGMENTS_PER_PLAYER
local MAX_POINTS = MAX_PLAYERS * MAX_POINTS_PER_PLAYER
local BOSS_MARKER_HEIGHT = 12
-- Distinct colors per player (R,G,B)
local PLAYER_COLORS = {
    { 1, 0.3, 0.3 },   -- red
    { 0.3, 0.5, 1 },   -- blue
    { 0.3, 0.85, 0.3 }, -- green
    { 1, 0.85, 0.2 },  -- gold
    { 0.9, 0.4, 0.9 }, -- magenta
}

local function SetBackdropCompat(frame, backdropInfo, backdropColor, backdropBorderColor)
    if frame.SetBackdrop then
        frame:SetBackdrop(backdropInfo)
        if backdropColor then
            frame:SetBackdropColor(backdropColor[1], backdropColor[2], backdropColor[3], backdropColor[4])
        end
        if backdropBorderColor then
            frame:SetBackdropBorderColor(backdropBorderColor[1], backdropBorderColor[2], backdropBorderColor[3], backdropBorderColor[4])
        end
    elseif frame.SetBackdropInfo then
        frame:SetBackdropInfo(backdropInfo)
        if backdropColor then
            frame:SetBackdropColor(backdropColor[1], backdropColor[2], backdropColor[3], backdropColor[4])
        end
        if backdropBorderColor then
            frame:SetBackdropBorderColor(backdropBorderColor[1], backdropBorderColor[2], backdropBorderColor[3], backdropBorderColor[4])
        end
    end
end

local function FormatNumber(n)
    if n >= 1e9 then
        return string.format("%.1fB", n / 1e9)
    elseif n >= 1e6 then
        return string.format("%.1fM", n / 1e6)
    elseif n >= 1e3 then
        return string.format("%.1fK", n / 1e3)
    end
    return tostring(math.floor(n))
end

local function FormatTime(seconds)
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return string.format("%d:%02d", m, s)
end

local function DownsampleSeries(series, maxPoints)
    if not series or #series <= maxPoints or maxPoints < 2 then
        return series
    end
    local result = {}
    local n = #series
    local span = n - 1
    local steps = maxPoints - 1
    for i = 0, steps do
        local idx = math.floor((i * span) / steps + 0.5) + 1
        if idx < 1 then idx = 1 end
        if idx > n then idx = n end
        result[#result + 1] = series[idx]
    end
    return result
end

local function BuildSmoothRenderSeries(series, maxSegments)
    if not series or #series <= 1 then
        return series
    end
    local working = series
    if (#working - 1) > maxSegments then
        working = DownsampleSeries(working, maxSegments + 1)
    end

    local baseSegments = #working - 1
    if baseSegments <= 0 then
        return working
    end
    local substeps = math.max(1, math.floor(maxSegments / baseSegments))
    local smoothed = { working[1] }

    for i = 1, baseSegments do
        local a = working[i]
        local b = working[i + 1]
        local e1 = a.elapsed or 0
        local e2 = b.elapsed or e1
        local v1 = a.value or 0
        local v2 = b.value or v1
        local deltaE = e2 - e1
        local deltaV = v2 - v1

        for s = 1, substeps do
            local t = s / substeps
            local ease = t * t * (3 - 2 * t) -- smoothstep
            local elapsed = e1 + (deltaE * t)
            local value = v1 + (deltaV * ease)
            smoothed[#smoothed + 1] = { elapsed = elapsed, value = value }
        end
    end
    return smoothed
end

local function ShowTrackerTooltip(owner, trackerFrame, title, detail)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    -- Keep tooltip above the tracker frame (tracker uses very high frame level).
    if trackerFrame and trackerFrame.GetFrameStrata and trackerFrame.GetFrameLevel then
        GameTooltip:SetFrameStrata(trackerFrame:GetFrameStrata() or "TOOLTIP")
        GameTooltip:SetFrameLevel((trackerFrame:GetFrameLevel() or 0) + 20)
    end
    GameTooltip:SetText(title or "—")
    if detail and detail ~= "" then
        GameTooltip:AddLine(detail, 0.9, 0.9, 0.9)
    end
    GameTooltip:Show()
end

function LiveTrackerFrame:Create()
    if self.frame then
        self.frame:Show()
        self:RefreshChart()
        return self.frame
    end

    local frame = CreateFrame("Frame", "StormsDungeonDataLiveTracker", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(560, 460)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(1000)

    frame.TitleBg:SetHeight(30)
    frame.InsetBg:SetAlpha(0.35)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame.TitleBg, "TOPLEFT", 10, -5)
    title:SetText("Live Dungeon Tracker")
    frame.Title = title

    if not frame.CloseButton and not frame.closeButton then
        local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", frame.TitleBg, "TOPRIGHT", -5, -5)
        closeBtn:SetScript("OnClick", function()
            MPT.LiveTrackerFrame:Hide()
        end)
    end

    -- Toggle: Damage | Healing | Interrupts | DPS | HPS
    self.mode = "damage" -- "damage" | "healing" | "interrupts" | "dps" | "hps"
    local btnW, btnH = 75, 24
    local damageBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    damageBtn:SetSize(btnW, btnH)
    damageBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -42)
    damageBtn:SetText("Damage")
    damageBtn:SetScript("OnClick", function()
        LiveTrackerFrame.mode = "damage"
        LiveTrackerFrame:RefreshChart()
        LiveTrackerFrame:UpdateButtonHighlight()
    end)

    local healingBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    healingBtn:SetSize(btnW, btnH)
    healingBtn:SetPoint("LEFT", damageBtn, "RIGHT", 4, 0)
    healingBtn:SetText("Healing")
    healingBtn:SetScript("OnClick", function()
        LiveTrackerFrame.mode = "healing"
        LiveTrackerFrame:RefreshChart()
        LiveTrackerFrame:UpdateButtonHighlight()
    end)

    local interruptsBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    interruptsBtn:SetSize(btnW, btnH)
    interruptsBtn:SetPoint("LEFT", healingBtn, "RIGHT", 4, 0)
    interruptsBtn:SetText("Interrupts")
    interruptsBtn:SetScript("OnClick", function()
        LiveTrackerFrame.mode = "interrupts"
        LiveTrackerFrame:RefreshChart()
        LiveTrackerFrame:UpdateButtonHighlight()
    end)

    local dpsBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    dpsBtn:SetSize(btnW, btnH)
    dpsBtn:SetPoint("LEFT", interruptsBtn, "RIGHT", 4, 0)
    dpsBtn:SetText("DPS")
    dpsBtn:SetScript("OnClick", function()
        LiveTrackerFrame.mode = "dps"
        LiveTrackerFrame:RefreshChart()
        LiveTrackerFrame:UpdateButtonHighlight()
    end)

    local hpsBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    hpsBtn:SetSize(btnW, btnH)
    hpsBtn:SetPoint("LEFT", dpsBtn, "RIGHT", 4, 0)
    hpsBtn:SetText("HPS")
    hpsBtn:SetScript("OnClick", function()
        LiveTrackerFrame.mode = "hps"
        LiveTrackerFrame:RefreshChart()
        LiveTrackerFrame:UpdateButtonHighlight()
    end)

    frame.DamageBtn = damageBtn
    frame.HealingBtn = healingBtn
    frame.InterruptsBtn = interruptsBtn
    frame.DPSBtn = dpsBtn
    frame.HPSBtn = hpsBtn

    -- Legend: player name + color swatch (directly under Damage button)
    frame.Legend = {}
    for i = 1, MAX_PLAYERS do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(130, 14)
        local anchor = (i == 1) and damageBtn or frame.Legend[i-1].row
        row:SetPoint("TOPLEFT", anchor, (i == 1) and "BOTTOMLEFT" or "BOTTOMLEFT", 0, (i == 1) and -4 or -2)
        local swatch = row:CreateTexture(nil, "OVERLAY")
        swatch:SetSize(10, 10)
        swatch:SetPoint("LEFT", row, "LEFT", 0, 0)
        swatch:SetColorTexture(unpack(PLAYER_COLORS[i] or PLAYER_COLORS[1]))
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", swatch, "RIGHT", 4, 0)
        label:SetText("—")
        frame.Legend[i] = { row = row, swatch = swatch, label = label }
    end

    -- Chart container (with padding for axes) — below legend
    local chartContainer = CreateFrame("Frame", nil, frame)
    chartContainer:SetSize(CHART_WIDTH + CHART_PADDING * 2, CHART_HEIGHT + CHART_PADDING * 2)
    chartContainer:SetPoint("TOPLEFT", frame.Legend[MAX_PLAYERS].row, "BOTTOMLEFT", 0, -6)
    frame.ChartContainer = chartContainer

    local backdropInfo = {
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    }
    SetBackdropCompat(chartContainer, backdropInfo, { 0.08, 0.08, 0.12, 0.85 }, { 0.3, 0.3, 0.4, 0.6 })

    -- Chart area (where we draw) - origin bottom-left for easy Y-up mapping
    local chartArea = CreateFrame("Frame", nil, chartContainer)
    chartArea:SetSize(CHART_WIDTH, CHART_HEIGHT)
    chartArea:SetPoint("BOTTOMLEFT", chartContainer, "BOTTOMLEFT", CHART_PADDING, CHART_PADDING)
    frame.ChartArea = chartArea

    -- Transparent overlay for hover tooltips (points filled in RefreshChart)
    local hoverOverlay = CreateFrame("Frame", nil, chartArea)
    hoverOverlay:SetAllPoints(chartArea)
    hoverOverlay:EnableMouse(true)
    hoverOverlay:SetScript("OnEnter", function()
        hoverOverlay.isOver = true
    end)
    hoverOverlay:SetScript("OnLeave", function()
        hoverOverlay.isOver = nil
        GameTooltip:Hide()
    end)
    hoverOverlay:SetScript("OnUpdate", function()
        if not hoverOverlay.isOver then return end
        local hasPoints = frame.ChartHoverPoints and #frame.ChartHoverPoints > 0
        local hasSegments = frame.ChartHoverSegments and #frame.ChartHoverSegments > 0
        if not hasPoints and not hasSegments then return end
        local scale = chartArea:GetEffectiveScale()
        if not scale or scale == 0 then return end
        local cx, cy = GetCursorPosition()
        local l, b = chartArea:GetLeft(), chartArea:GetBottom()
        local relX = (cx / scale) - l
        local relY = (cy / scale) - b

        -- Prefer nearest point first.
        local bestPointIdx, bestPointDist = nil, 36 -- 12px radius
        if hasPoints then
            for i, p in ipairs(frame.ChartHoverPoints) do
                local dx = p.x - relX
                local dy = p.y - relY
                local d = dx * dx + dy * dy
                if d < bestPointDist * bestPointDist then
                    bestPointDist = math.sqrt(d)
                    bestPointIdx = i
                end
            end
        end

        if bestPointIdx then
            local p = frame.ChartHoverPoints[bestPointIdx]
            local modeLabel = (frame.ChartHoverMode == "damage" and "Damage") 
                or (frame.ChartHoverMode == "healing" and "Healing") 
                or (frame.ChartHoverMode == "interrupts" and "Interrupts")
                or (frame.ChartHoverMode == "dps" and "DPS")
                or (frame.ChartHoverMode == "hps" and "HPS")
                or "Unknown"
            ShowTrackerTooltip(
                hoverOverlay,
                frame,
                p.playerName or "—",
                FormatTime(p.elapsed or 0) .. "  |  " .. modeLabel .. ": " .. FormatNumber(p.value or 0)
            )
            return
        end

        -- Fallback: nearest line segment within threshold.
        local bestSeg, bestSegDist, bestT = nil, 8, 0 -- 8px line hover radius
        if hasSegments then
            for _, s in ipairs(frame.ChartHoverSegments) do
                local vx = s.x2 - s.x1
                local vy = s.y2 - s.y1
                local lenSq = vx * vx + vy * vy
                if lenSq > 0 then
                    local wx = relX - s.x1
                    local wy = relY - s.y1
                    local t = (wx * vx + wy * vy) / lenSq
                    if t < 0 then t = 0 end
                    if t > 1 then t = 1 end
                    local px = s.x1 + t * vx
                    local py = s.y1 + t * vy
                    local dx = relX - px
                    local dy = relY - py
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist < bestSegDist then
                        bestSegDist = dist
                        bestSeg = s
                        bestT = t
                    end
                end
            end
        end

        if bestSeg then
            local elapsed = (bestSeg.elapsed1 or 0) + ((bestSeg.elapsed2 or 0) - (bestSeg.elapsed1 or 0)) * bestT
            local value = (bestSeg.value1 or 0) + ((bestSeg.value2 or 0) - (bestSeg.value1 or 0)) * bestT
            local modeLabel = (frame.ChartHoverMode == "damage" and "Damage") 
                or (frame.ChartHoverMode == "healing" and "Healing") 
                or (frame.ChartHoverMode == "interrupts" and "Interrupts")
                or (frame.ChartHoverMode == "dps" and "DPS")
                or (frame.ChartHoverMode == "hps" and "HPS")
                or "Unknown"
            ShowTrackerTooltip(
                hoverOverlay,
                frame,
                bestSeg.playerName or "—",
                FormatTime(elapsed) .. "  |  " .. modeLabel .. ": " .. FormatNumber(value)
            )
        else
            GameTooltip:Hide()
        end
    end)
    frame.ChartHoverOverlay = hoverOverlay

    -- Pool of line segments (MAX_PLAYERS * MAX_SEGMENTS_PER_PLAYER); each player uses a contiguous block
    frame.LineSegments = {}
    for i = 1, MAX_SEGMENTS do
        local tex = chartArea:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(0.2, 0.7, 1, 0.95)
        tex:SetHeight(LINE_THICKNESS)
        tex:Hide()
        frame.LineSegments[i] = tex
    end

    -- Pool of point textures (one per player per point)
    frame.PointTextures = {}
    for i = 1, MAX_POINTS do
        local tex = chartArea:CreateTexture(nil, "ARTWORK")
        tex:SetColorTexture(1, 0.9, 0.3, 1)
        tex:SetSize(4, 4)
        tex:Hide()
        frame.PointTextures[i] = tex
    end

    -- Y-axis grid lines (horizontal lines across chart)
    frame.YGridLines = {}
    for i = 1, 8 do
        local tex = chartArea:CreateTexture(nil, "BACKGROUND")
        tex:SetColorTexture(0.35, 0.35, 0.4, 0.6)
        tex:SetSize(CHART_WIDTH, 1)
        tex:Hide()
        frame.YGridLines[i] = tex
    end

    -- Boss kill markers (vertical lines)
    frame.BossMarkers = {}
    for i = 1, 20 do
        local tex = chartArea:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(1, 0.4, 0.1, 0.9)
        tex:SetSize(2, CHART_HEIGHT)
        tex:Hide()
        frame.BossMarkers[i] = tex
    end

    -- Axis labels (Y = value, X = time)
    local yLabel = chartContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    yLabel:SetPoint("BOTTOMLEFT", chartContainer, "BOTTOMLEFT", 4, CHART_PADDING + CHART_HEIGHT / 2 - 8)
    yLabel:SetJustifyV("MIDDLE")
    yLabel:SetText("0")
    frame.YLabel = yLabel

    local xLabel = chartContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    xLabel:SetPoint("BOTTOMLEFT", chartContainer, "BOTTOMLEFT", CHART_PADDING + CHART_WIDTH / 2 - 20, 2)
    xLabel:SetText("Time")
    frame.XLabel = xLabel

    self.frame = frame
    self:UpdateButtonHighlight()
    self:RefreshChart()
    return frame
end

function LiveTrackerFrame:UpdateButtonHighlight()
    local frame = self.frame
    if not frame then return end
    local normal = { 0.5, 0.5, 0.5, 1 }
    local highlight = { 0.2, 0.7, 0.2, 1 }
    for _, btn in ipairs({ frame.DamageBtn, frame.HealingBtn, frame.InterruptsBtn, frame.DPSBtn, frame.HPSBtn }) do
        if btn then
            btn:GetFontString():SetTextColor(unpack(normal))
        end
    end
    local active = (self.mode == "damage" and frame.DamageBtn) 
        or (self.mode == "healing" and frame.HealingBtn) 
        or (self.mode == "interrupts" and frame.InterruptsBtn)
        or (self.mode == "dps" and frame.DPSBtn)
        or (self.mode == "hps" and frame.HPSBtn)
    if active then
        active:GetFontString():SetTextColor(unpack(highlight))
    end
end

-- Build per-player series from dataPoints: each series is list of { elapsed, value } with cumulative (non-decreasing) value. Each line starts at (0,0).
local function buildPlayerSeries(points, mode)
    local playerNames = {}
    for _, p in ipairs(points) do
        if p.players then
            for name in pairs(p.players) do
                playerNames[name] = true
            end
        end
    end
    local ordered = {}
    for name in pairs(playerNames) do
        table.insert(ordered, name)
    end
    table.sort(ordered)
    local seriesByPlayer = {}
    local runningMax = {}
    for _, name in ipairs(ordered) do
        seriesByPlayer[name] = {}
        runningMax[name] = 0
    end
    for _, p in ipairs(points) do
        local elapsed = p.elapsed and p.elapsed >= 0 and p.elapsed or 0
        for name, data in pairs(p.players or {}) do
            if seriesByPlayer[name] then
                local v
                if mode == "damage" then
                    v = data.damage or 0
                elseif mode == "healing" then
                    v = data.healing or 0
                elseif mode == "interrupts" then
                    v = data.interrupts or 0
                elseif mode == "dps" then
                    v = data.dps or 0
                elseif mode == "hps" then
                    v = data.hps or 0
                else
                    v = 0
                end
                -- Cumulative metrics (damage, healing, interrupts) are monotonically non-decreasing;
                -- rate metrics (dps, hps) naturally fluctuate and must not be clamped to a running max.
                if mode == "dps" or mode == "hps" then
                    table.insert(seriesByPlayer[name], { elapsed = elapsed, value = v })
                else
                    runningMax[name] = math.max(runningMax[name] or 0, v)
                    table.insert(seriesByPlayer[name], { elapsed = elapsed, value = runningMax[name] })
                end
            end
        end
    end
    -- Ensure each player line starts at (0, 0)
    for _, name in ipairs(ordered) do
        local s = seriesByPlayer[name]
        if #s == 0 or (s[1].elapsed > 0) then
            table.insert(s, 1, { elapsed = 0, value = 0 })
        end
        seriesByPlayer[name] = DownsampleSeries(s, MAX_POINTS_PER_PLAYER)
    end
    return ordered, seriesByPlayer
end

-- Build per-player step-function series from combatSessions for DPS/HPS mode.
-- Each combat session becomes a horizontal plateau; gaps between sessions are zeroed out.
local function buildSessionSeries(sessions, mode, maxElapsed)
    local playerNames = {}
    for _, s in ipairs(sessions) do
        for name in pairs(s.players or {}) do
            playerNames[name] = true
        end
    end
    local ordered = {}
    for name in pairs(playerNames) do
        table.insert(ordered, name)
    end
    table.sort(ordered)

    local seriesByPlayer = {}
    for _, name in ipairs(ordered) do
        local pts = { { elapsed = 0, value = 0 } }
        local prevEnd = 0
        for _, session in ipairs(sessions) do
            local stats = session.players and session.players[name]
            local v = 0
            if stats then
                v = (mode == "dps") and (stats.dps or 0) or (stats.hps or 0)
            end
            -- Explicitly zero out the gap before this session starts.
            if session.startElapsed > prevEnd + 0.1 then
                table.insert(pts, { elapsed = session.startElapsed, value = 0 })
            end
            -- Step up at session start, hold through session end, then step back to zero.
            table.insert(pts, { elapsed = session.startElapsed, value = v })
            table.insert(pts, { elapsed = session.endElapsed,   value = v })
            table.insert(pts, { elapsed = session.endElapsed,   value = 0 })
            prevEnd = session.endElapsed
        end
        -- Extend the zero baseline to the final X position so the axis is fully drawn.
        if maxElapsed and maxElapsed > prevEnd + 0.1 then
            table.insert(pts, { elapsed = maxElapsed, value = 0 })
        end
        seriesByPlayer[name] = DownsampleSeries(pts, MAX_POINTS_PER_PLAYER)
    end
    return ordered, seriesByPlayer
end

function LiveTrackerFrame:RefreshChart()
    local frame = self.frame
    if not frame or not frame.ChartArea then return end

    for i = 1, MAX_SEGMENTS do
        frame.LineSegments[i]:Hide()
    end
    for i = 1, MAX_POINTS do
        frame.PointTextures[i]:Hide()
    end
    for i = 1, 20 do
        frame.BossMarkers[i]:Hide()
    end
    for i = 1, #(frame.YGridLines or {}) do
        if frame.YGridLines[i] then frame.YGridLines[i]:Hide() end
    end
    for i = 1, MAX_PLAYERS do
        frame.Legend[i].row:Hide()
    end
    frame.ChartHoverPoints = {}
    frame.ChartHoverSegments = {}
    frame.ChartHoverMode = nil

    local tracker = MPT.LiveTracker
    if not tracker then return end

    local points = tracker:GetDataPoints()
    local bossKills = tracker:GetBossKills()
    if not points or #points == 0 then
        frame.YLabel:SetText("0")
        frame.XLabel:SetText("Time")
        return
    end

    local tMaxHint = (tracker.GetTimelineMaxElapsed and tracker:GetTimelineMaxElapsed()) or 0

    -- For DPS/HPS use combat-session step series; fall back to snapshot-based series when no sessions exist.
    local orderedNames, seriesByPlayer
    if (self.mode == "dps" or self.mode == "hps") and tracker.GetCombatSessions then
        local sessions = tracker:GetCombatSessions()
        if sessions and #sessions > 0 then
            orderedNames, seriesByPlayer = buildSessionSeries(sessions, self.mode, tMaxHint)
        end
    end
    if not orderedNames then
        orderedNames, seriesByPlayer = buildPlayerSeries(points, self.mode)
    end

    local tMax = 1
    local vMax = 1
    for _, name in ipairs(orderedNames) do
        local series = seriesByPlayer[name]
        for _, pt in ipairs(series) do
            if pt.elapsed > tMax then tMax = pt.elapsed end
            if pt.value > vMax then vMax = pt.value end
        end
    end
    tMax = math.max(tMax, tMaxHint)
    if tMax <= 0 then tMax = 1 end
    if vMax <= 0 then vMax = 1 end

    local w, h = CHART_WIDTH, CHART_HEIGHT
    local function toX(elapsed) return (elapsed / tMax) * w end
    local function toY(value) return (value / vMax) * h end

    -- Build hover point list for tooltips (x, y, elapsed, value, playerName)
    frame.ChartHoverPoints = {}
    frame.ChartHoverSegments = {}
    frame.ChartHoverMode = self.mode

    -- Draw one line per player (up to MAX_PLAYERS)
    for pidx = 1, math.min(#orderedNames, MAX_PLAYERS) do
        local name = orderedNames[pidx]
        local series = seriesByPlayer[name]
        local renderSeries = BuildSmoothRenderSeries(series, MAX_SEGMENTS_PER_PLAYER)
        local color = PLAYER_COLORS[pidx] or PLAYER_COLORS[1]
        local segBase = (pidx - 1) * MAX_SEGMENTS_PER_PLAYER
        local ptBase = (pidx - 1) * MAX_POINTS_PER_PLAYER

        -- Legend
        frame.Legend[pidx].swatch:SetColorTexture(unpack(color))
        frame.Legend[pidx].label:SetText(name)
        frame.Legend[pidx].row:Show()

        -- Draw point markers from raw series (actual sampled points)
        for i = 1, #series do
            local pt = series[i]
            local x = toX(pt.elapsed)
            local y = toY(pt.value)
            table.insert(frame.ChartHoverPoints, { x = x, y = y, elapsed = pt.elapsed, value = pt.value, playerName = name })
            local texIdx = ptBase + i
            if frame.PointTextures[texIdx] then
                local tex = frame.PointTextures[texIdx]
                tex:SetColorTexture(unpack(color))
                tex:ClearAllPoints()
                tex:SetPoint("CENTER", frame.ChartArea, "BOTTOMLEFT", x, y)
                tex:Show()
            end
        end

        -- Draw smoothed line segments from interpolated render series
        for i = 1, (#renderSeries - 1) do
            local pt1 = renderSeries[i]
            local pt2 = renderSeries[i + 1]
            local x = toX(pt1.elapsed)
            local y = toY(pt1.value)
            local x2 = toX(pt2.elapsed)
            local y2 = toY(pt2.value)
            local dx = x2 - x
            local dy = y2 - y
            local len = math.sqrt(dx * dx + dy * dy)
            local segIdx = segBase + i
            if len > 0.5 and frame.LineSegments[segIdx] then
                local seg = frame.LineSegments[segIdx]
                seg:SetColorTexture(unpack(color))
                seg:SetWidth(len)
                seg:ClearAllPoints()
                seg:SetPoint("CENTER", frame.ChartArea, "BOTTOMLEFT", (x + x2) / 2, (y + y2) / 2)
                if seg.SetRotation then
                    seg:SetRotation(math.atan2(dy, dx))
                end
                seg:Show()
                table.insert(frame.ChartHoverSegments, {
                    x1 = x, y1 = y, x2 = x2, y2 = y2,
                    elapsed1 = pt1.elapsed, elapsed2 = pt2.elapsed,
                    value1 = pt1.value, value2 = pt2.value,
                    playerName = name,
                })
            end
        end
    end

    -- Boss kill markers
    for i = 1, math.min(#bossKills, 20) do
        local elapsed = bossKills[i]
        local x = toX(elapsed)
        if frame.BossMarkers[i] then
            local mk = frame.BossMarkers[i]
            mk:ClearAllPoints()
            mk:SetPoint("BOTTOM", frame.ChartArea, "BOTTOMLEFT", x, 0)
            mk:SetHeight(CHART_HEIGHT)
            mk:Show()
        end
    end

    -- Y-axis horizontal grid lines (0%, 25%, 50%, 75%, 100%) so damage lines align with Y labels
    local numGridLines = 5
    for i = 1, numGridLines do
        local tex = frame.YGridLines and frame.YGridLines[i]
        if tex then
            local frac = (i - 1) / (numGridLines - 1)  -- 0, 0.25, 0.5, 0.75, 1
            local y = frac * h
            tex:ClearAllPoints()
            tex:SetPoint("BOTTOMLEFT", frame.ChartArea, "BOTTOMLEFT", 0, y)
            tex:SetSize(CHART_WIDTH, 1)
            tex:Show()
        end
    end

    frame.YLabel:SetText(FormatNumber(vMax))
    frame.XLabel:SetText("Time (0 - " .. FormatTime(tMax) .. ")")
end

function LiveTrackerFrame:Show()
    self:Create()
    if self.frame then
        self.frame:Show()
        self:RefreshChart()
    end
end

function LiveTrackerFrame:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

function LiveTrackerFrame:IsVisible()
    return self.frame and self.frame:IsVisible()
end

function LiveTrackerFrame:Toggle()
    if self:IsVisible() then
        self:Hide()
    else
        self:Show()
    end
end

-- Optional: refresh chart on a timer when visible and in M+
if C_Timer then
    C_Timer.NewTicker(2, function()
        if MPT.LiveTrackerFrame and MPT.LiveTrackerFrame:IsVisible() and MPT.InMythicPlus then
            MPT.LiveTrackerFrame:RefreshChart()
        end
    end)
end

