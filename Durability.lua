local addonName, ns = ...

-- Warns when gear is wearing out: a line on screen for as long as the most
-- worn piece is below the chosen level, and one line in chat when it first
-- drops below. Both go away once the gear is repaired.

-- Equipment slots, head to ranged.
local FIRST_SLOT, LAST_SLOT = 1, 18

-- The levels the warning can be set to, as percentages.
ns.DURABILITY_LEVELS = { 10, 25, 50 }

local warned = false   -- the chat line has been said for this spell of wear

local function Usable(value)
    return value ~= nil and not (issecretvalue and issecretvalue(value))
end

-- How worn the most worn piece of gear is, as a percentage left; nil if
-- nothing equipped has durability.
function ns.LowestDurability()
    local lowest
    for slot = FIRST_SLOT, LAST_SLOT do
        local current, maximum = GetInventoryItemDurability(slot)
        if Usable(current) and Usable(maximum) and maximum > 0 then
            local percent = current / maximum * 100
            if not lowest or percent < lowest then
                lowest = percent
            end
        end
    end
    return lowest
end

local notice = CreateFrame("Frame", addonName .. "DurabilityNotice", UIParent)
notice:SetSize(260, 26)
notice:SetPoint("TOP", UIParent, "TOP", 0, -150)
notice:SetMovable(true)
notice:SetClampedToScreen(true)
notice:EnableMouse(true)
notice:RegisterForDrag("LeftButton")
notice:SetScript("OnDragStart", notice.StartMoving)
notice:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint()
    ns.db.noticePosition = { point, relativePoint, x, y }
end)
notice:Hide()

local background = notice:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints()
background:SetColorTexture(0, 0, 0, 0.55)

local text = notice:CreateFontString(nil, "OVERLAY", "GameFontNormal")
text:SetPoint("CENTER")

-- Shows, updates or hides the warning to match the gear's condition.
function ns.UpdateDurability()
    local db = ns.db
    if not db then return end
    local lowest = db.durabilityWarn and ns.LowestDurability() or nil
    if not lowest or lowest >= db.durabilityLevel then
        warned = false
        notice:Hide()
        return
    end

    local percent = math.floor(lowest + 0.5)
    text:SetText(("Gear worn: %d%% left"):format(percent))
    -- Orange while there is some way to go, red when it is about to break.
    if percent <= 10 then
        text:SetTextColor(1, 0.25, 0.25)
    else
        text:SetTextColor(1, 0.65, 0.2)
    end
    notice:Show()
    if not warned then
        warned = true
        ns.Print(("Your most worn piece of gear is down to %d%%. Time to find a vendor who repairs."):format(percent))
    end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event)
    if not ns.db then return end
    if event == "PLAYER_LOGIN" and ns.db.noticePosition then
        local position = ns.db.noticePosition
        notice:ClearAllPoints()
        notice:SetPoint(position[1], UIParent, position[2], position[3], position[4])
    end
    -- Reading the gear must never put an error on screen.
    pcall(ns.UpdateDurability)
end)
frame:RegisterEvent("PLAYER_LOGIN")
-- Registering an event this client does not have throws.
for _, event in ipairs({ "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED", "MERCHANT_CLOSED", "PLAYER_REGEN_ENABLED" }) do
    pcall(frame.RegisterEvent, frame, event)
end
