local _, ns = ...

-- The controller's B button (PAD2) closes this addon's windows, as Escape
-- and their X do: while a window is shown, B is bound to closing it, and it
-- gets its usual job back once the window hides. A window can borrow other
-- buttons the same way (the logbook scrolls with the D-pad). When a fight
-- starts every borrowed button is handed back at once, and borrowed again
-- once the fight is over.

local padWindows = {}
local padFrame = CreateFrame("Frame")

local inFight = false
local function PadApply(window)
    if not (SetOverrideBinding and ClearOverrideBindings) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    ClearOverrideBindings(window)
    if window:IsShown() and not inFight then
        SetOverrideBinding(window, true, "PAD2", "CLICK " .. window.padCloseName .. ":LeftButton")
        for key, buttonName in pairs(window.padKeys or {}) do
            SetOverrideBinding(window, true, key, "CLICK " .. buttonName .. ":LeftButton")
        end
    end
end

padFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- A fight is starting: the buttons go back to their usual jobs now,
        -- the last moment the game allows a change, even with a window open.
        inFight = true
        for _, window in ipairs(padWindows) do
            if ClearOverrideBindings then pcall(ClearOverrideBindings, window) end
        end
    else
        inFight = false
        for _, window in ipairs(padWindows) do pcall(PadApply, window) end
    end
end)
pcall(padFrame.RegisterEvent, padFrame, "PLAYER_REGEN_DISABLED")
pcall(padFrame.RegisterEvent, padFrame, "PLAYER_REGEN_ENABLED")

-- window: the frame; name: its global name; keys: optional { PADDUP = fn, ... }
-- for other buttons to borrow while it is shown.
function ns.CloseWithPadB(window, name, keys)
    if not window or type(name) ~= "string" or window.padCloseName then return end
    -- Invisible buttons for the bindings to press: never placed on screen,
    -- and not clickable with the mouse.
    window.padCloseName = name .. "PadClose"
    local close = CreateFrame("Button", window.padCloseName, UIParent)
    close:EnableMouse(false)
    close:SetScript("OnClick", function() window:Hide() end)
    window.padClose = close
    window.padKeys = {}
    for key, action in pairs(keys or {}) do
        local buttonName = name .. "Pad" .. key
        local button = CreateFrame("Button", buttonName, UIParent)
        button:EnableMouse(false)
        button:SetScript("OnClick", function() action() end)
        window.padKeys[key] = buttonName
    end
    padWindows[#padWindows + 1] = window
    window:HookScript("OnShow", function(self) pcall(PadApply, self) end)
    window:HookScript("OnHide", function(self) pcall(PadApply, self) end)
end
