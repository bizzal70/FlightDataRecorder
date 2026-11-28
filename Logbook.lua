local addonName, ns = ...

-- The logbook: every recorded route, grouped by where it starts, and FDR's
-- settings. Scrolls with the mouse wheel, the arrows, or the controller's
-- D-pad; B closes it. Each route has an x that forgets it (press twice).

local WIDTH, PAD, HEADER, ROW_HEIGHT, ROWS = 460, 12, 36, 20, 16
local SETTINGS_HEIGHT = 58
local HEIGHT = HEADER + PAD + ROW_HEIGHT * (ROWS + 1) + 44 + SETTINGS_HEIGHT
local ARM_TIME = 4          -- seconds the x waits for its second press

local window, rows, footer, upButton, downButton
local offset = 0
local entries = {}
local ticks = {}
local armedKey, armedAt

-- The logbook's lines: a heading for each place flights start from, then
-- its routes, quickest first. Places A to Z.
function ns.LogbookEntries()
    local byFrom, places = {}, {}
    for key, route in pairs(ns.db.routes) do
        local list = byFrom[route.from]
        if not list then
            list = { name = route.fromName or "?" }
            byFrom[route.from] = list
            places[#places + 1] = list
        end
        list[#list + 1] = { route = route, key = key }
    end
    table.sort(places, function(a, b) return a.name < b.name end)
    local lines = {}
    for _, list in ipairs(places) do
        lines[#lines + 1] = { heading = list.name }
        table.sort(list, function(a, b) return (a.route.time or 0) < (b.route.time or 0) end)
        for _, entry in ipairs(list) do lines[#lines + 1] = entry end
    end
    return lines
end

local function Scroll(delta)
    offset = math.max(0, math.min(offset + delta, math.max(0, #entries - ROWS)))
    ns.RefreshLogbook()
end
ns.ScrollLogbook = Scroll

-- The x on a route: the first press asks, the second forgets.
function ns.PressForget(key)
    if armedKey == key and armedAt and time() - armedAt <= ARM_TIME then
        armedKey, armedAt = nil, nil
        return ns.ForgetRoute(key)
    end
    armedKey, armedAt = key, time()
    ns.RefreshLogbook()
    if C_Timer and C_Timer.After then
        C_Timer.After(ARM_TIME + 0.1, function()
            if armedKey == key and time() - armedAt >= ARM_TIME then
                armedKey, armedAt = nil, nil
                ns.RefreshLogbook()
            end
        end)
    end
    return false
end

function ns.RefreshLogbook()
    if not (window and window:IsShown()) then return end
    entries = ns.LogbookEntries()
    offset = math.max(0, math.min(offset, #entries - ROWS))
    if armedKey and not ns.db.routes[armedKey] then armedKey = nil end
    for index = 1, ROWS do
        local row, entry = rows[index], entries[index + offset]
        row.key = entry and entry.key
        if entry and entry.heading then
            row.name:SetText(entry.heading)
            row.name:SetTextColor(0.4, 0.76, 1)
            row.time:SetText("")
            row.flown:SetText("")
            row.forget:Hide()
            row:Show()
        elseif entry then
            local route = entry.route
            local armed = armedKey == entry.key
            row.name:SetText("    to " .. (route.toName or "?"))
            row.name:SetTextColor(1, 1, 1)
            row.time:SetText(ns.Clock(route.time))
            row.flown:SetText(("x%d"):format(route.flown or 1))
            row.flown:SetShown(not armed)
            row.forget.label:SetText(armed and "Forget?" or "x")
            if armed then row.forget.label:SetTextColor(1, 0.35, 0.35) else row.forget.label:SetTextColor(0.6, 0.6, 0.6) end
            row.forget:SetWidth(armed and 60 or 20)
            row.forget:Show()
            row:Show()
        else
            row:Hide()
        end
    end
    local routes = 0
    for _ in pairs(ns.db.routes) do routes = routes + 1 end
    footer:SetText(routes == 0 and "No flights recorded yet. Take a flight and FDR times it from take off to landing."
        or ("%d %s recorded. Times are the usual of your last few flights."):format(routes, routes == 1 and "route" or "routes"))
    upButton:SetShown(offset > 0)
    downButton:SetShown(offset + ROWS < #entries)
    for _, tick in ipairs(ticks) do tick.Refresh() end
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

-- A setting with a tick box, drawn from plain colours.
local function Tick(x, y, text, key, after)
    local row = CreateFrame("Button", nil, window)
    row:SetSize((WIDTH - PAD * 2) / 2 - 4, 22)
    row:SetPoint("BOTTOMLEFT", x, y)
    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.07)
    local box = CreateFrame("Frame", nil, row)
    box:SetSize(14, 14)
    box:SetPoint("LEFT", 2, 0)
    ns.Fill(box, 0, 0, 0, 0.5)
    ns.Outline(box, 0.7)
    local mark = box:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("TOPLEFT", 3, -3)
    mark:SetPoint("BOTTOMRIGHT", -3, 3)
    mark:SetColorTexture(0.85, 0.63, 0.40, 1)
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    label:SetText(text)
    row.key, row.mark = key, mark
    function row.Refresh() mark:SetShown(ns.db[key] and true or false) end
    row:SetScript("OnClick", function()
        ns.db[key] = not ns.db[key]
        if after then after() end
        row.Refresh()
    end)
    ticks[#ticks + 1] = row
    return row
end

local function SavePoint()
    local point, _, relativePoint, x, y = window:GetPoint()
    if point then ns.db.logbookPoint = { point, relativePoint, x, y } end
end

local function CreateLogbook()
    window = CreateFrame("Frame", "FlightDataRecorderLogbook", UIParent)
    window:SetSize(WIDTH, HEIGHT)
    local saved = ns.db.logbookPoint
    if type(saved) == "table" and saved[1] then
        window:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    else
        window:SetPoint("CENTER")
    end
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
    header:SetScript("OnDragStop", function()
        window:StopMovingOrSizing()
        SavePoint()
    end)
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
    columnsRight:SetPoint("TOPRIGHT", -(PAD + 32 + 24), -(HEADER + 8))
    columnsRight:SetText("Time      Flown")

    rows = {}
    for index = 1, ROWS do
        local row = CreateFrame("Frame", nil, window)
        row:SetSize(WIDTH - PAD * 2 - 32, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", PAD, -(HEADER + 8 + ROW_HEIGHT * index))
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT")
        row.name:SetPoint("RIGHT", -134, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.time:SetPoint("RIGHT", -74, 0)
        row.time:SetJustifyH("RIGHT")
        row.flown = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        row.flown:SetPoint("RIGHT", -28, 0)
        row.flown:SetJustifyH("RIGHT")
        local forget = CreateFrame("Button", nil, row)
        forget:SetSize(20, ROW_HEIGHT - 2)
        forget:SetPoint("RIGHT", 0, 0)
        local forgetHover = forget:CreateTexture(nil, "HIGHLIGHT")
        forgetHover:SetAllPoints()
        forgetHover:SetColorTexture(0.9, 0.2, 0.2, 0.3)
        forget.label = forget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        forget.label:SetPoint("CENTER")
        forget.label:SetText("x")
        forget:SetScript("OnClick", function() if row.key then ns.PressForget(row.key) end end)
        forget:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Forget this route", 1, 1, 1)
            GameTooltip:AddLine("Press twice. The next flight there records it afresh.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        forget:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.forget = forget
        rows[index] = row
    end

    upButton = ArrowButton("^", function() Scroll(-ROWS) end)
    upButton:SetPoint("TOPRIGHT", -PAD, -(HEADER + 8 + ROW_HEIGHT))
    downButton = ArrowButton("v", function() Scroll(ROWS) end)
    downButton:SetPoint("TOPRIGHT", -PAD, -(HEADER + 8 + ROW_HEIGHT * ROWS))

    footer = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOMLEFT", PAD, 26 + SETTINGS_HEIGHT)
    footer:SetPoint("BOTTOMRIGHT", -PAD, 26 + SETTINGS_HEIGHT)
    footer:SetJustifyH("LEFT")
    footer:SetWordWrap(true)

    -- Settings, two by two.
    local half = (WIDTH - PAD * 2) / 2
    Tick(PAD, 30 + 26, "Flight bar", "bar", function() ns.UpdateBar() end)
    Tick(PAD + half, 30 + 26, "Times beside the flight map", "mapPanel")
    Tick(PAD, 30, "A line in chat on landing", "chat")
    Tick(PAD + half, 30, "Alert 10 seconds before landing", "alert")

    local hint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", PAD, 10)
    hint:SetText("Scroll with the mouse wheel or the D-pad. B or Escape closes. Drag the bar to move it.")

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

function ns.LogbookTicks() return ticks end

-- Listed in the game's own Options > AddOns, with a button that opens the
-- logbook, where the settings are: that's where many players look first.
local function RegisterSettings()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local panel = CreateFrame("Frame")
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("FDR - Flight Data Recorder")
    local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    text:SetWidth(520)
    text:SetJustifyH("LEFT")
    text:SetText("Times every flight-master flight and counts the next one on that route down to landing. The logbook lists every route and holds the settings.")
    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(220, 26)
    open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)
    open:SetText("Open the logbook")
    open:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() and HideUIPanel then pcall(HideUIPanel, SettingsPanel) end
        if not (window and window:IsShown()) then ns.ToggleLogbook() end
    end)
    local category = Settings.RegisterCanvasLayoutCategory(panel, "FDR - Flight Data Recorder")
    Settings.RegisterAddOnCategory(category)
end
pcall(RegisterSettings)
