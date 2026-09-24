-- Companion for launcher-owned AethroParagon.
-- Detects when UIParagon opens and pushes it to the front. Slash is optional.
-- Also keeps ParagonExpBar visible when bar addons hide MainMenuBar.
-- Do not edit AethroParagon itself.
-- Per-character SavedVariables are assigned after this file runs. Touch
-- ParagonFronterDB only after ADDON_LOADED.

local ADDON = "Paragon_Fronter"
local DEFAULT_STRATA = "DIALOG"
local HOLD_SECONDS = 0.25
-- Their live ParagonExpBar_UpdatePosition uses x = 0, y = -2.
local EXP_BAR_BASE_X = 0
local EXP_BAR_BASE_Y = -2
local EXP_BAR_BASE_WIDTH = 1024
local EXP_BAR_BASE_HEIGHT = 11
local EXP_BAR_STATUS_HEIGHT = 8
local EXP_BAR_TEX_WIDTH = 256
local EXP_BAR_TEX_HEIGHT = 11
local SCALE_MIN = 0.2
local SCALE_MAX = 3
local CONFIG_NAME = "ParagonFronterConfig"
local DEFAULT_PANEL_POINT = "TOPLEFT"
local DEFAULT_PANEL_X = 16
local DEFAULT_PANEL_Y = -160

local hookedFrame = nil
local wasShown = false
local holdUntil = 0
local watcher
local expBarHooked = false
local visibilityHooked = false
local RescueExpBar
local configFrame
local configShowCheck
local configBoxes
local specialFrameAdded = false

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffb66cffParagon Fronter:|r " .. msg)
end

local function FormatNum(n)
    n = tonumber(n) or 0
    if math.abs(n - math.floor(n + 0.0001)) < 0.0001 then
        return tostring(math.floor(n + 0.0001))
    end
    local text = string.format("%.3f", n)
    while string.sub(text, -1) == "0" do
        text = string.sub(text, 1, -2)
    end
    if string.sub(text, -1) == "." then
        text = string.sub(text, 1, -2)
    end
    return text
end

local function ClampScale(n)
    n = tonumber(n)
    if not n then
        return nil
    end
    if n < SCALE_MIN then
        n = SCALE_MIN
    elseif n > SCALE_MAX then
        n = SCALE_MAX
    end
    return n
end

local function EnsureDB()
    ParagonFronterDB = ParagonFronterDB or {}
    if not ParagonFronterDB.strata then
        ParagonFronterDB.strata = DEFAULT_STRATA
    end
    if type(ParagonFronterDB.expBar) ~= "table" then
        ParagonFronterDB.expBar = {}
    end
    local expBar = ParagonFronterDB.expBar
    -- Offsets / scales from their original point and size, not the live frame.
    if expBar.x == nil then
        expBar.x = 0
    end
    if expBar.y == nil then
        expBar.y = tonumber(ParagonFronterDB.xpvoffset) or 0
    end
    if expBar.width == nil then
        expBar.width = 1
    end
    if expBar.height == nil then
        expBar.height = 1
    end
    -- Their checkbox only SetCVars. 3.3.5 does not persist that CVar.
    if expBar.show == nil then
        expBar.show = GetCVar("paragonShowMainMenuXP") == "1"
    end
    ParagonFronterDB.xpvoffset = tonumber(expBar.y) or 0
    if type(ParagonFronterDB.panel) ~= "table" then
        ParagonFronterDB.panel = {}
    end
end

local function GetStrata()
    EnsureDB()
    local strata = ParagonFronterDB.strata
    if strata == "HIGH" or strata == "DIALOG" or strata == "FULLSCREEN_DIALOG" then
        return strata
    end
    return DEFAULT_STRATA
end

local function GetExpBarOffset()
    EnsureDB()
    return tonumber(ParagonFronterDB.expBar.y) or 0
end

local function GetExpBarOffsetX()
    EnsureDB()
    return tonumber(ParagonFronterDB.expBar.x) or 0
end

local function GetExpBarScaleX()
    EnsureDB()
    return ClampScale(ParagonFronterDB.expBar.width) or 1
end

local function GetExpBarScaleY()
    EnsureDB()
    return ClampScale(ParagonFronterDB.expBar.height) or 1
end

local function SetExpBarOffset(y)
    EnsureDB()
    y = tonumber(y) or 0
    ParagonFronterDB.expBar.y = y
    ParagonFronterDB.xpvoffset = y
end

local function SetExpBarOffsetX(x)
    EnsureDB()
    ParagonFronterDB.expBar.x = tonumber(x) or 0
end

local function SetExpBarScaleX(width)
    EnsureDB()
    ParagonFronterDB.expBar.width = ClampScale(width) or 1
end

local function SetExpBarScaleY(height)
    EnsureDB()
    ParagonFronterDB.expBar.height = ClampScale(height) or 1
end

local function WantExpBarShown()
    EnsureDB()
    return ParagonFronterDB.expBar.show == true
end

local function SyncExpBarCheckbox(checked)
    local box = _G.UIParagon and _G.UIParagon.ShowMainMenuXP
    if box and box.SetChecked then
        box:SetChecked(checked)
    end
    if configShowCheck then
        configShowCheck:SetChecked(checked)
    end
end

local function SetExpBarShown(shown)
    EnsureDB()
    shown = shown and true or false
    ParagonFronterDB.expBar.show = shown
    SetCVar("paragonShowMainMenuXP", shown and "1" or "0")
    SyncExpBarCheckbox(shown)
    RescueExpBar()
end

local function RestoreExpBarVisibility()
    EnsureDB()
    if ParagonFronterDB.expBar.show then
        SetCVar("paragonShowMainMenuXP", "1")
        SyncExpBarCheckbox(true)
    end
    RescueExpBar()
end

-- 3.3.5 StatusBar fill does not follow SetWidth until value/texture are poked.
local function RefreshExpBarFill(status)
    if not status then
        return
    end

    local current = 0
    local maxXP = 150
    if ParagonExpData then
        current = tonumber(ParagonExpData.currentXP) or 0
        maxXP = tonumber(ParagonExpData.maxXP) or 150
    else
        current = status:GetValue() or 0
        local _, maxValue = status:GetMinMaxValues()
        maxXP = maxValue or 150
    end
    if maxXP <= 0 then
        maxXP = 1
    end

    if status.SetStatusBarTexture then
        status:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    end
    if status.SetStatusBarColor then
        status:SetStatusBarColor(0.90, 0.80, 0.50)
    end

    local tex = status.GetStatusBarTexture and status:GetStatusBarTexture()
    if tex then
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", status, "TOPLEFT")
        tex:SetPoint("BOTTOMLEFT", status, "BOTTOMLEFT")
    end

    status:SetMinMaxValues(0, maxXP)
    status:SetValue(0)
    status:SetValue(current)
end

local function ApplyExpBarLayout()
    local frame = _G.ParagonExpBar
    if not frame then
        return false
    end

    local x = EXP_BAR_BASE_X + GetExpBarOffsetX()
    local y = EXP_BAR_BASE_Y + GetExpBarOffset()
    frame:ClearAllPoints()
    if ReputationWatchBar and ReputationWatchBar:IsVisible() then
        frame:SetPoint("BOTTOM", ReputationWatchBar, "TOP", x, y)
    elseif MainMenuBar then
        frame:SetPoint("BOTTOM", MainMenuBar, "TOP", x, y)
    else
        frame:SetPoint("BOTTOM", UIParent, "BOTTOM", x, y)
    end

    local scaleX = GetExpBarScaleX()
    local scaleY = GetExpBarScaleY()
    frame:SetWidth(EXP_BAR_BASE_WIDTH * scaleX)
    frame:SetHeight(EXP_BAR_BASE_HEIGHT * scaleY)

    local status = frame.StatusBar or _G.ParagonExpBarStatusBar
    if status then
        status:SetWidth(EXP_BAR_BASE_WIDTH * scaleX)
        status:SetHeight(EXP_BAR_STATUS_HEIGHT * scaleY)
        RefreshExpBarFill(status)
    end

    local i
    for i = 0, 3 do
        local tex = _G["ParagonExpBarStatusBarTexture" .. i]
        if tex then
            tex:SetWidth(EXP_BAR_TEX_WIDTH * scaleX)
            tex:SetHeight(EXP_BAR_TEX_HEIGHT * scaleY)
        end
    end
    return true
end

local function ResetExpBarDefaults()
    SetExpBarOffsetX(0)
    SetExpBarOffset(0)
    SetExpBarScaleX(1)
    SetExpBarScaleY(1)
    ApplyExpBarLayout()
end

RescueExpBar = function()
    local frame = _G.ParagonExpBar
    if not frame then
        return
    end

    -- Bartender (and similar) hide MainMenuBar. This bar is parented to it, so
    -- their :Show() never becomes visible. Move it to UIParent first.
    if WantExpBarShown() then
        if frame:GetParent() ~= UIParent then
            frame:SetParent(UIParent)
        end
        if not frame:IsShown() then
            frame:Show()
        end
        ApplyExpBarLayout()
    elseif frame:IsShown() then
        frame:Hide()
    end
end

local function HookExpBar()
    if expBarHooked or type(hooksecurefunc) ~= "function" then
        return
    end
    if type(ParagonExpBar_UpdatePosition) ~= "function" then
        return
    end

    hooksecurefunc("ParagonExpBar_UpdatePosition", RescueExpBar)

    if type(ParagonExpBar_Update) == "function" then
        hooksecurefunc("ParagonExpBar_Update", RescueExpBar)
    end

    if type(UIParagon_ShowMainMenuXP_OnClick) == "function" and not visibilityHooked then
        hooksecurefunc("UIParagon_ShowMainMenuXP_OnClick", function(self)
            SetExpBarShown(self and self:GetChecked())
        end)
        visibilityHooked = true
    end

    expBarHooked = true
end

local function RefreshConfigBoxes()
    if not configBoxes then
        return
    end
    configBoxes.y:SetText(FormatNum(GetExpBarOffset()))
    configBoxes.x:SetText(FormatNum(GetExpBarOffsetX()))
    configBoxes.height:SetText(FormatNum(GetExpBarScaleY()))
    configBoxes.width:SetText(FormatNum(GetExpBarScaleX()))
    if configShowCheck then
        configShowCheck:SetChecked(WantExpBarShown())
    end
end

local function CommitConfigBox(box, key)
    local value = tonumber(strtrim(box:GetText() or ""))
    if key == "y" then
        if not value then
            RefreshConfigBoxes()
            return
        end
        SetExpBarOffset(value)
    elseif key == "x" then
        if not value then
            RefreshConfigBoxes()
            return
        end
        SetExpBarOffsetX(value)
    elseif key == "width" then
        value = ClampScale(value)
        if not value then
            RefreshConfigBoxes()
            return
        end
        SetExpBarScaleX(value)
    elseif key == "height" then
        value = ClampScale(value)
        if not value then
            RefreshConfigBoxes()
            return
        end
        SetExpBarScaleY(value)
    end
    ApplyExpBarLayout()
    RefreshConfigBoxes()
end

local function SavePanelPosition()
    if not configFrame then
        return
    end
    EnsureDB()
    local point, _, relPoint, x, y = configFrame:GetPoint(1)
    local panel = ParagonFronterDB.panel
    panel.point = point or DEFAULT_PANEL_POINT
    panel.relPoint = relPoint or DEFAULT_PANEL_POINT
    panel.x = x or DEFAULT_PANEL_X
    panel.y = y or DEFAULT_PANEL_Y
end

local function ApplyDefaultPanelPosition()
    if not configFrame then
        return
    end
    EnsureDB()
    local panel = ParagonFronterDB.panel
    panel.point = DEFAULT_PANEL_POINT
    panel.relPoint = DEFAULT_PANEL_POINT
    panel.x = DEFAULT_PANEL_X
    panel.y = DEFAULT_PANEL_Y
    configFrame:ClearAllPoints()
    configFrame:SetPoint(DEFAULT_PANEL_POINT, UIParent, DEFAULT_PANEL_POINT, DEFAULT_PANEL_X, DEFAULT_PANEL_Y)
end

local function ApplyPanelPosition()
    if not configFrame then
        return
    end
    EnsureDB()
    local panel = ParagonFronterDB.panel
    local x = tonumber(panel.x)
    local y = tonumber(panel.y)
    configFrame:ClearAllPoints()
    if not x or not y then
        ApplyDefaultPanelPosition()
        return
    end
    configFrame:SetPoint(
        panel.point or DEFAULT_PANEL_POINT,
        UIParent,
        panel.relPoint or DEFAULT_PANEL_POINT,
        x,
        y
    )
end

local function ClampPanelToScreen()
    if not configFrame or not configFrame:IsShown() then
        return
    end
    local left = configFrame:GetLeft()
    local right = configFrame:GetRight()
    local top = configFrame:GetTop()
    local bottom = configFrame:GetBottom()
    local screenW = UIParent:GetRight()
    local screenH = UIParent:GetTop()
    if not left or not right or not top or not bottom or not screenW or not screenH then
        return
    end
    if right < 40 or left > (screenW - 40) or top < 40 or bottom > (screenH - 40) then
        ApplyDefaultPanelPosition()
    end
end

local function CreateConfigFrame()
    if configFrame then
        return
    end

    local frame = CreateFrame("Frame", CONFIG_NAME, UIParent)
    frame:SetSize(240, 286)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:Hide()

    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePanelPosition()
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Paragon XP Bar")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)

    configBoxes = {}
    local rows = {
        { label = "Vertical Offset", key = "y" },
        { label = "Horizontal Offset", key = "x" },
        { label = "Vertical Scale", key = "height" },
        { label = "Horizontal Scale", key = "width" },
    }
    local rowY = -44
    local i
    for i = 1, #rows do
        local row = rows[i]
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, rowY)
        label:SetText(row.label)

        local box = CreateFrame("EditBox", "ParagonFronterBox_" .. row.key, frame, "InputBoxTemplate")
        box:SetSize(72, 20)
        box:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, rowY + 3)
        box:SetAutoFocus(false)
        box:SetMaxLetters(8)
        box:SetScript("OnEnterPressed", function(self)
            CommitConfigBox(self, row.key)
            self:ClearFocus()
        end)
        box:SetScript("OnEditFocusLost", function(self)
            CommitConfigBox(self, row.key)
        end)
        box:SetScript("OnEscapePressed", function(self)
            RefreshConfigBoxes()
            self:ClearFocus()
        end)
        configBoxes[row.key] = box
        rowY = rowY - 32
    end

    local showCheck = CreateFrame("CheckButton", "ParagonFronterShowXP", frame, "UICheckButtonTemplate")
    showCheck:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 44)
    showCheck:SetChecked(WantExpBarShown())
    local showLabel = _G[showCheck:GetName() .. "Text"]
    if showLabel then
        showLabel:SetText("Show XP Bar")
    else
        showLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        showLabel:SetPoint("LEFT", showCheck, "RIGHT", 0, 1)
        showLabel:SetText("Show XP Bar")
    end
    showCheck:SetScript("OnClick", function(self)
        SetExpBarShown(self:GetChecked())
        if self:GetChecked() then
            PlaySound("igMainMenuOptionCheckBoxOn")
        else
            PlaySound("igMainMenuOptionCheckBoxOff")
        end
    end)
    configShowCheck = showCheck

    local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reset:SetSize(100, 22)
    reset:SetPoint("BOTTOM", frame, "BOTTOM", 0, 16)
    reset:SetText("Reset")
    reset:SetScript("OnClick", function()
        ResetExpBarDefaults()
        RefreshConfigBoxes()
        PlaySound("igMainMenuOptionCheckBoxOn")
    end)

    if not specialFrameAdded then
        tinsert(UISpecialFrames, CONFIG_NAME)
        specialFrameAdded = true
    end

    configFrame = frame
end

local function ShowConfig()
    CreateConfigFrame()
    RefreshConfigBoxes()
    ApplyPanelPosition()
    configFrame:Show()
    ClampPanelToScreen()
    configFrame:Raise()
end

local function ToggleConfig()
    if configFrame and configFrame:IsShown() then
        configFrame:Hide()
        return
    end
    ShowConfig()
end

local function ResetAllDefaults()
    ResetExpBarDefaults()
    CreateConfigFrame()
    ApplyDefaultPanelPosition()
    RefreshConfigBoxes()
    configFrame:Show()
    configFrame:Raise()
end

local function BringToFront(frame)
    frame = frame or _G.UIParagon
    if not frame then
        return false
    end
    if frame.SetToplevel then
        frame:SetToplevel(true)
    end
    frame:SetFrameStrata(GetStrata())
    frame:Raise()
    return true
end

local function StartFrontHold(frame)
    holdUntil = GetTime() + HOLD_SECONDS
    BringToFront(frame)
end

local function HookFrame(frame)
    if not frame or hookedFrame == frame then
        return
    end
    hookedFrame = frame

    if frame.SetToplevel then
        frame:SetToplevel(true)
    end

    -- 3.3.5 widget Show() is not reliably hooksecurefunc'd. Wrap OnShow instead.
    local prev = frame.GetScript and frame:GetScript("OnShow")
    frame:SetScript("OnShow", function(self, ...)
        if prev then
            prev(self, ...)
        end
        StartFrontHold(self)
    end)
end

local function WatchTick()
    local frame = _G.UIParagon
    if frame then
        HookFrame(frame)

        local shown = frame:IsShown()
        if shown and not wasShown then
            StartFrontHold(frame)
        elseif shown and GetTime() <= holdUntil then
            BringToFront(frame)
        end
        wasShown = shown
    else
        wasShown = false
    end

    HookExpBar()
    local expBar = _G.ParagonExpBar
    if expBar then
        if WantExpBarShown() then
            if expBar:GetParent() ~= UIParent or not expBar:IsVisible() then
                RescueExpBar()
            end
        elseif expBar:IsShown() then
            RescueExpBar()
        end
    end
end

local function StartWatcher()
    if watcher then
        return
    end
    watcher = CreateFrame("Frame")
    watcher.elapsed = 0
    watcher:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        local interval = (holdUntil > 0 and GetTime() <= holdUntil) and 0 or 0.05
        if self.elapsed < interval then
            return
        end
        self.elapsed = 0
        WatchTick()
    end)
end

local function HookTheirSlash()
    if type(hooksecurefunc) ~= "function" then
        return
    end
    if type(SlashCmdList) ~= "table" or type(SlashCmdList.AETHROPARAGON) ~= "function" then
        return
    end
    hooksecurefunc(SlashCmdList, "AETHROPARAGON", function()
        local frame = _G.UIParagon
        if frame and frame:IsShown() then
            StartFrontHold(frame)
        end
    end)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name == ADDON then
            EnsureDB()
            StartWatcher()
        end
        if name == ADDON or name == "AethroParagon" then
            HookFrame(_G.UIParagon)
            HookExpBar()
            RestoreExpBarVisibility()
        end
        return
    end

    StartWatcher()
    HookFrame(_G.UIParagon)
    HookTheirSlash()
    HookExpBar()
    RestoreExpBarVisibility()
    if not _G.UIParagon then
        Print("AethroParagon not found. Enable it, then /reload.")
    end
    self:UnregisterEvent("PLAYER_LOGIN")
end)

SLASH_PARAGONFRONTER1 = "/pfront"
SLASH_PARAGONFRONTER2 = "/paragonfronter"
SlashCmdList["PARAGONFRONTER"] = function(msg)
    msg = strtrim(string.lower(msg or ""))

    if msg == "" or msg == "raise" then
        if BringToFront() then
            Print("raised UIParagon to " .. GetStrata())
        else
            Print("UIParagon is not loaded.")
        end
        return
    end

    if msg == "config" then
        ToggleConfig()
        return
    end

    if msg == "reset" then
        ResetAllDefaults()
        Print("reset to default")
        return
    end

    if msg == "status" then
        local frame = _G.UIParagon
        if frame then
            Print(string.format(
                "shown=%s strata=%s want=%s level=%s auto=on",
                tostring(frame:IsShown()),
                tostring(frame:GetFrameStrata()),
                GetStrata(),
                tostring(frame:GetFrameLevel())
            ))
        else
            Print("UIParagon is not loaded.")
        end

        local expBar = _G.ParagonExpBar
        if expBar then
            local parent = expBar:GetParent()
            Print(string.format(
                "expbar shown=%s visible=%s parent=%s cvar=%s x=%s y=%s w=%s h=%s",
                tostring(expBar:IsShown()),
                tostring(expBar:IsVisible()),
                tostring(parent and parent.GetName and parent:GetName() or "?"),
                tostring(GetCVar("paragonShowMainMenuXP")),
                FormatNum(GetExpBarOffsetX()),
                FormatNum(GetExpBarOffset()),
                FormatNum(GetExpBarScaleX()),
                FormatNum(GetExpBarScaleY())
            ))
        else
            Print("ParagonExpBar is not loaded.")
        end
        return
    end

    if msg == "high" or msg == "dialog" or msg == "fullscreen_dialog" then
        ParagonFronterDB.strata = string.upper(msg)
        if _G.UIParagon and _G.UIParagon:IsShown() then
            BringToFront()
        end
        Print("strata set to " .. ParagonFronterDB.strata)
        return
    end

    local offsetCmd, offsetRest = string.match(msg, "^(xpvoffset)%s*(.*)$")
    if offsetCmd then
        offsetRest = strtrim(offsetRest or "")
        if offsetRest == "" then
            Print("offset set to " .. FormatNum(GetExpBarOffset()))
            return
        end
        local offset = tonumber(offsetRest)
        if not offset then
            Print("xpvoffset needs a number. example: /pfront xpvoffset 40")
            return
        end
        SetExpBarOffset(offset)
        ApplyExpBarLayout()
        RefreshConfigBoxes()
        Print("offset set to " .. FormatNum(offset))
        return
    end

    if msg == "help" then
        Print("opens of /paragon are raised automatically")
        Print("/pfront                  raise Paragon now")
        Print("/pfront config           open XP bar options")
        Print("/pfront reset            stock XP bar and config window")
        Print("/pfront status           print current strata and exp bar")
        Print("/pfront high             use HIGH")
        Print("/pfront dialog           use DIALOG (default)")
        Print("/pfront fullscreen_dialog  last resort")
        Print("/pfront xpvoffset        print vertical offset")
        Print("/pfront xpvoffset 40     move exp bar +40 from original")
        return
    end

    Print("unknown command. /pfront help")
end
