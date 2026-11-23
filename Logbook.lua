local addonName, ns = ...

-- The logbook: every recorded route, grouped by where it starts. Scrolls
-- with the mouse wheel, the arrows, or the controller's D-pad; B closes it.

local WIDTH, PAD, HEADER, ROW_HEIGHT, ROWS = 460, 12, 36, 20, 16
local HEIGHT = HEADER + PAD + ROW_HEIGHT * (ROWS + 1) + 44

local window, rows, footer, upButton, downButton
local offset = 0
local entries = {}

-- The logbook's lines: a heading for each place flights start from, then
-- its routes, quickest first. Places A to Z.
function ns.LogbookEntries()
    local byFrom, places = {}, {}
    for _, route in pairs(ns.db.routes) do
        local list = byFrom[route.from]
        if not list then
            list = { name = route.fromName or "?" }
            byFrom[route.from] = list
            places[#places + 1] = list
        end
        list[#list + 1] = route
    end
    table.sort(places, function(a, b) return a.name < b.name end)
    local lines = {}
    for _, list in ipairs(places) do
        lines[#lines + 1] = { heading = list.name }
        table.sort(list, function(a, b) return (a.time or 0) < (b.time or 0) end)
        for _, route in ipairs(list) do lines[#lines + 1] = { route = route } end
    end
    return lines
end

local function Scroll(delta)
    offset = math.max(0, math.min(offset + delta, math.max(0, #entries - ROWS)))
    ns.RefreshLogbook()
end
ns.ScrollLogbook = Scroll

function ns.RefreshLogbook()
    if not (window and window:IsShown()) then return end
    entries = ns.LogbookEntries()
    offset = math.max(0, math.min(offset, #entries - ROWS))
    for index = 1, ROWS do
        local row, entry = rows[index], entries[index + offset]
        if entry and entry.heading then
            row.name:SetText(entry.heading)
            row.name:SetTextColor(0.4, 0.76, 1)
            row.time:SetText("")
            row.flown:SetText("")
            row:Show()
        elseif entry then
            local route = entry.route
            row.name:SetText("    to " .. (route.toName or "?"))
            row.name:SetTextColor(1, 1, 1)
            row.time:SetText(ns.Clock(route.time))
            row.flown:SetText(("x%d"):format(route.flown or 1))
            row:Show()
        else
            row:Hide()
        end
    end
    local routes = 0
    for _ in pairs(ns.db.routes) do routes = routes + 1 end
    footer:SetText(routes == 0 and "No flights recorded yet. Take a flight and FDR times it from take off to landing."
        or ("%d %s recorded."):format(routes, routes == 1 and "route" or "routes"))
    upButton:SetShown(offset > 0)
    downButton:SetShown(offset + ROWS < #entries)
end

local function ArrowButton(text, onClick)
    local button = CreateFrame("Button", nil, window)
    button:SetSize(26, 20)
    ns.Fill(button, 0.16, 0.12, 0.08, 1)
    ns.Outline(button, 0.45)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("CENTER")
    label:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function CreateLogbook()
    window = CreateFrame("Frame", "FlightDataRecorderLogbook", UIParent)
    window:SetSize(WIDTH, HEIGHT)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetToplevel(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:EnableMouseWheel(true)
    window:SetScript("OnMouseWheel", function(_, delta) Scroll(delta > 0 and -3 or 3) end)
    window:Hide()
    ns.Fill(window, 0.05, 0.05, 0.06, 0.96)
    ns.Outline(window, 0.55)
    tinsert(UISpecialFrames, "FlightDataRecorderLogbook")
    ns.CloseWithPadB(window, "FlightDataRecorderLogbook", {
        PADDUP = function() Scroll(-1) end,
        PADDDOWN = function() Scroll(1) end,
    })

    local header = CreateFrame("Frame", nil, window)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() window:StartMoving() end)
    header:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
    ns.Fill(header, 0.16, 0.12, 0.08, 1)
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", PAD, 0)
    title:SetText("FDR  -  Flight Data Recorder")
    title:SetTextColor(1, 0.9, 0.75)
    local close = CreateFrame("Button", nil, header)
    close:SetSize(HEADER - 6, HEADER - 6)
    close:SetPoint("RIGHT", -3, 0)
    local closeHover = close:CreateTexture(nil, "HIGHLIGHT")
    closeHover:SetAllPoints()
    closeHover:SetColorTexture(0.9, 0.2, 0.2, 0.45)
    local closeLabel = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    closeLabel:SetPoint("CENTER")
    closeLabel:SetText("x")
    close:SetScript("OnClick", function() window:Hide() end)

    local columns = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    columns:SetPoint("TOPLEFT", PAD, -(HEADER + 8))
    columns:SetText("Route")
    local columnsRight = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    columnsRight:SetPoint("TOPRIGHT", -(PAD + 32), -(HEADER + 8))
    columnsRight:SetText("Time      Flown")

    rows = {}
    for index = 1, ROWS do
        local row = CreateFrame("Frame", nil, window)
        row:SetSize(WIDTH - PAD * 2 - 32, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", PAD, -(HEADER + 8 + ROW_HEIGHT * index))
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT")
        row.name:SetPoint("RIGHT", -110, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.time:SetPoint("RIGHT", -50, 0)
        row.time:SetJustifyH("RIGHT")
        row.flown = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        row.flown:SetPoint("RIGHT", -4, 0)
        row.flown:SetJustifyH("RIGHT")
        rows[index] = row
    end

    upButton = ArrowButton("^", function() Scroll(-ROWS) end)
    upButton:SetPoint("TOPRIGHT", -PAD, -(HEADER + 8 + ROW_HEIGHT))
    downButton = ArrowButton("v", function() Scroll(ROWS) end)
    downButton:SetPoint("TOPRIGHT", -PAD, -(HEADER + 8 + ROW_HEIGHT * ROWS))

    footer = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOMLEFT", PAD, 26)
    footer:SetPoint("BOTTOMRIGHT", -PAD, 26)
    footer:SetJustifyH("LEFT")
    footer:SetWordWrap(true)
    local hint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", PAD, 10)
    hint:SetText("Scroll with the mouse wheel or the D-pad. B or Escape closes. /fdr help for settings.")

    window:HookScript("OnShow", function() ns.RefreshLogbook() end)
    -- Fit small screens (such as a handheld): never taller or wider than
    -- the screen allows.
    window:HookScript("OnShow", function(self)
        local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
        if screenWidth and screenHeight and screenWidth > 0 and screenHeight > 0 then
            self:SetScale(math.min(1, (screenWidth - 20) / WIDTH, (screenHeight - 20) / HEIGHT))
        end
    end)
end

function ns.ToggleLogbook()
    if not window then CreateLogbook() end
    if window:IsShown() then window:Hide() else window:Show() end
end
