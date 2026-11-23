local addonName, ns = ...

-- The flight bar (counting down to landing, or timing a new route) and the
-- flight times shown at the flight master.

local ACCENT_R, ACCENT_G, ACCENT_B = 0.85, 0.63, 0.40
local BAR_WIDTH, BAR_HEIGHT = 300, 34

local function Fill(frame, r, g, b, a, layer)
    local texture = frame:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetAllPoints()
    texture:SetColorTexture(r, g, b, a)
    return texture
end

local function Outline(frame, alpha)
    local function Edge(point1, point2, isVertical)
        local edge = frame:CreateTexture(nil, "BORDER")
        edge:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, alpha)
        edge:SetPoint(point1)
        edge:SetPoint(point2)
        if isVertical then edge:SetWidth(1) else edge:SetHeight(1) end
    end
    Edge("TOPLEFT", "TOPRIGHT", false)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", false)
    Edge("TOPLEFT", "BOTTOMLEFT", true)
    Edge("TOPRIGHT", "BOTTOMRIGHT", true)
end
ns.Fill, ns.Outline = Fill, Outline

----------------------------------------------------------------------------
-- The flight bar
----------------------------------------------------------------------------

local bar = CreateFrame("Frame", "FlightDataRecorderBar", UIParent)
bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
bar:SetFrameStrata("MEDIUM")
bar:SetClampedToScreen(true)
bar:SetMovable(true)
bar:EnableMouse(true)
bar:RegisterForDrag("LeftButton")
bar:Hide()
Fill(bar, 0.05, 0.05, 0.06, 0.85)
Outline(bar, 0.6)

-- How much of the flight is left, shrinking from the right.
bar.fill = bar:CreateTexture(nil, "ARTWORK")
bar.fill:SetPoint("TOPLEFT", 1, -1)
bar.fill:SetPoint("BOTTOMLEFT", 1, 1)
bar.fill:SetColorTexture(0.25, 0.55, 0.85, 0.55)

bar.icon = bar:CreateTexture(nil, "OVERLAY")
bar.icon:SetSize(BAR_HEIGHT - 8, BAR_HEIGHT - 8)
bar.icon:SetPoint("LEFT", 4, 0)
bar.icon:SetTexture("Interface\\Icons\\Ability_Mount_Gryphon_01")
bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

bar.where = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
bar.where:SetPoint("LEFT", bar.icon, "RIGHT", 6, 0)
bar.where:SetPoint("RIGHT", -64, 0)
bar.where:SetJustifyH("LEFT")
bar.where:SetWordWrap(false)

bar.clock = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
bar.clock:SetPoint("RIGHT", -8, 0)
bar.clock:SetJustifyH("RIGHT")

bar:SetScript("OnDragStart", function(self) self:StartMoving() end)
bar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint()
    ns.db.barPoint = { point, relativePoint, x, y }
end)
bar:SetScript("OnEnter", function(self)
    local flight = ns.flight
    if not flight then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Flight Data Recorder", 0.4, 0.76, 1)
    GameTooltip:AddLine(("%s to %s"):format(flight.fromName or "?", flight.toName or "?"), 1, 1, 1, true)
    local route = ns.Route(flight.from, flight.to)
    if route then
        GameTooltip:AddLine(("Usually %s; flown %d %s."):format(ns.Clock(route.time), route.flown or 1,
            (route.flown or 1) == 1 and "time" or "times"), 0.8, 0.8, 0.8)
    else
        GameTooltip:AddLine("A route FDR has not timed before: this flight is being recorded.", 0.8, 0.8, 0.8, true)
    end
    GameTooltip:AddLine("Drag to move; /fdr reset puts it back.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

function ns.PlaceBar()
    bar:ClearAllPoints()
    local saved = ns.db and ns.db.barPoint
    if type(saved) == "table" and saved[1] then
        bar:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    else
        bar:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
end

-- What the bar says, for the flight in the air: (where, clock, share of the
-- flight left or nil while recording).
function ns.BarText(flight, now)
    local elapsed = math.max(0, now - flight.started)
    local route = ns.Route(flight.from, flight.to)
    local where = "To " .. ns.ShortName(flight.toName)
    if route and route.time and route.time > 0 then
        local left = route.time - elapsed
        if left <= 0 then return where, "Landing", 0 end
        return where, ns.Clock(left), left / route.time
    end
    return where .. "  |cffff6666REC|r", ns.Clock(elapsed), nil
end

function ns.UpdateBar()
    local flight = ns.flight
    if not (flight and ns.db and ns.db.bar) then
        bar:Hide()
        return
    end
    if not bar.placed then
        ns.PlaceBar()
        bar.placed = true
    end
    local where, clock, share = ns.BarText(flight, time())
    bar.where:SetText(where)
    bar.clock:SetText(clock)
    if share then
        bar.fill:SetWidth(math.max(1, (BAR_WIDTH - 2) * share))
        bar.fill:SetColorTexture(0.25, 0.55, 0.85, 0.55)
        bar.fill:Show()
    else
        -- Recording a new route: a red fill that does not count down.
        bar.fill:SetWidth(BAR_WIDTH - 2)
        bar.fill:SetColorTexture(0.55, 0.15, 0.15, 0.35)
        bar.fill:Show()
    end
    bar:Show()
end

----------------------------------------------------------------------------
-- At the flight master
----------------------------------------------------------------------------

local panel = CreateFrame("Frame", "FlightDataRecorderPanel", UIParent)
panel:SetSize(250, 60)
panel:SetFrameStrata("HIGH")
panel:Hide()
Fill(panel, 0.05, 0.05, 0.06, 0.92)
Outline(panel, 0.55)
panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
panel.title:SetPoint("TOPLEFT", 10, -8)
panel.title:SetPoint("TOPRIGHT", -10, -8)
panel.title:SetJustifyH("LEFT")
panel.title:SetTextColor(0.4, 0.76, 1)
panel.lines = {}

local MAX_PANEL_LINES = 18

local function PanelLine(index)
    local line = panel.lines[index]
    if line then return line end
    line = {}
    line.name = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.name:SetPoint("TOPLEFT", 10, -10 - index * 16)
    line.name:SetPoint("RIGHT", -60, 0)
    line.name:SetJustifyH("LEFT")
    line.name:SetWordWrap(false)
    line.time = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.time:SetPoint("TOPRIGHT", -10, -10 - index * 16)
    line.time:SetJustifyH("RIGHT")
    panel.lines[index] = line
    return line
end

-- The flight map frame the game is showing, to sit beside.
local function TaxiWindow()
    for _, name in ipairs({ "FlightMapFrame", "TaxiFrame" }) do
        local frame = _G[name]
        if frame and frame.IsShown and frame:IsShown() then return frame end
    end
end

-- The times from where the player stands, for the panel: list of
-- { name, clock }, and the place's name.
function ns.PanelLines()
    local here = ns.ReadTaxiMap()
    if not here then return nil end
    local lines = {}
    for _, route in ipairs(ns.RoutesFrom(here.id)) do
        lines[#lines + 1] = { name = ns.ShortName(route.toName), clock = ns.Clock(route.time) }
    end
    return lines, here
end

function ns.ShowPanel()
    if not ns.db.mapPanel then return end
    local lines, here = ns.PanelLines()
    if not lines then return end
    panel.title:SetText("Flight times from " .. ns.ShortName(here.name))
    local shown = math.min(#lines, MAX_PANEL_LINES)
    for index = 1, MAX_PANEL_LINES do
        local line = panel.lines[index]
        if index <= shown then
            line = PanelLine(index)
            line.name:SetText(lines[index].name)
            line.time:SetText(lines[index].clock)
            line.name:Show(); line.time:Show()
        elseif line then
            line.name:Hide(); line.time:Hide()
        end
    end
    if shown == 0 then
        local line = PanelLine(1)
        line.name:SetText("None recorded yet: fly one and FDR times it.")
        line.time:SetText("")
        line.name:Show(); line.time:Show()
        shown = 1
    end
    panel:SetHeight(20 + (shown + 1) * 16)
    panel:ClearAllPoints()
    local window = TaxiWindow()
    if window then
        panel:SetPoint("TOPLEFT", window, "TOPRIGHT", 6, 0)
    else
        panel:SetPoint("LEFT", UIParent, "LEFT", 40, 60)
    end
    panel:Show()
end

local taxiEvents = CreateFrame("Frame")
pcall(taxiEvents.RegisterEvent, taxiEvents, "TAXIMAP_OPENED")
pcall(taxiEvents.RegisterEvent, taxiEvents, "TAXIMAP_CLOSED")
taxiEvents:SetScript("OnEvent", function(_, event)
    if event == "TAXIMAP_OPENED" then
        -- The game fills the map a moment after the event.
        if C_Timer and C_Timer.After then
            C_Timer.After(0.1, function() pcall(ns.ShowPanel) end)
        else
            pcall(ns.ShowPanel)
        end
    else
        panel:Hide()
    end
end)

-- Hovering a destination on the flight map: its recorded time in the
-- tooltip. The tooltip's first line is the destination's name.
local adding = false
function ns.AddTooltipTime(tooltip)
    if adding or not panel:IsShown() then return end
    local first = _G[(tooltip:GetName() or "GameTooltip") .. "TextLeft1"]
    local text = first and first:GetText()
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return end
    local here = ns.ReadTaxiMap()
    if not here then return end
    for _, route in ipairs(ns.RoutesFrom(here.id)) do
        if route.toName == text or ns.ShortName(route.toName) == text then
            adding = true
            tooltip:AddLine(("Flight time: %s"):format(ns.Clock(route.time)), 0.4, 0.76, 1)
            tooltip:Show()
            adding = false
            return true
        end
    end
end
GameTooltip:HookScript("OnShow", function(self) pcall(ns.AddTooltipTime, self) end)
