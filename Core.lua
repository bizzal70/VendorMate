local addonName, ns = ...

-- When a vendor window opens: sell the junk in the bags and repair worn
-- gear, then say in chat what that earned and cost. Holding Shift while
-- opening the vendor skips both.
--
-- Selling uses the game's own "Sell All Junk" rules (grey items), so what
-- counts as junk is exactly what that button would sell. Where the client
-- has no such function, grey items with a sale value are sold one by one.

-- How long after selling the money is read again to see what it earned.
local REPORT_SECONDS = 1.0
-- Pause between items when selling one by one, so the game keeps up.
local SELL_INTERVAL = 0.15
-- The backpack and the four bag slots.
local FIRST_BAG, LAST_BAG = 0, 4
local JUNK_QUALITY = 0

local defaults = {
    sellJunk = true,
    repair = true,
    -- Whether to say in chat what was sold and repaired.
    report = true,
    -- Whether to warn when gear is wearing out, and below what percentage.
    durabilityWarn = true,
    durabilityLevel = 25,
}

function ns.Print(msg)
    print("|cffd9a066VendorMate|r: " .. tostring(msg))
end

-- A value the client may withhold cannot be compared or added up.
local function Usable(value)
    return value ~= nil and not (issecretvalue and issecretvalue(value))
end

-- 12345 copper -> "1g 23s 45c"
function ns.Money(copper)
    copper = math.floor(copper + 0.5)
    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper / 100) % 100
    local rest = copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end
    if rest > 0 or #parts == 0 then parts[#parts + 1] = rest .. "c" end
    return table.concat(parts, " ")
end

local function CurrentMoney()
    local money = GetMoney()
    return Usable(money) and money or nil
end

---------------------------------------------------------------------------
-- Repair
---------------------------------------------------------------------------

-- Repairs everything if this vendor can, it is needed, and the character
-- can afford it. Returns what it cost, or nil if nothing was repaired.
local function Repair()
    local canRepairHere = CanMerchantRepair()
    if not Usable(canRepairHere) or not canRepairHere then return end
    local cost, needed = GetRepairAllCost()
    if not Usable(cost) or not Usable(needed) or not needed or cost <= 0 then return end
    local money = CurrentMoney()
    if not money then return end
    if money < cost then
        ns.Print(("Repairs would cost %s, which is more than you are carrying."):format(ns.Money(cost)))
        return
    end
    RepairAllItems()
    return cost
end

---------------------------------------------------------------------------
-- Selling junk
---------------------------------------------------------------------------

local sellTicker

-- The grey items in the bags that a vendor will pay for.
local function JunkSlots()
    local slots = {}
    for bag = FIRST_BAG, LAST_BAG do
        local count = C_Container.GetContainerNumSlots(bag)
        for slot = 1, (Usable(count) and count or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if Usable(info) and Usable(info.quality) and info.quality == JUNK_QUALITY
                and not info.hasNoValue and not info.isLocked then
                slots[#slots + 1] = { bag, slot }
            end
        end
    end
    return slots
end

-- Sells the junk. Returns how many items were (or are being) sold.
local function SellJunk()
    local merchant = C_MerchantFrame
    if merchant and merchant.SellAllJunkItems and merchant.GetNumJunkItems then
        local enabled = not merchant.IsSellAllJunkEnabled or merchant.IsSellAllJunkEnabled()
        local count = merchant.GetNumJunkItems()
        if not Usable(enabled) or not enabled or not Usable(count) or count <= 0 then return 0 end
        merchant.SellAllJunkItems()
        return count
    end

    -- No built-in: one item at a time, as if each were right-clicked.
    local slots = JunkSlots()
    if #slots == 0 then return 0 end
    local index = 0
    if sellTicker then sellTicker:Cancel() end
    sellTicker = C_Timer.NewTicker(SELL_INTERVAL, function(ticker)
        index = index + 1
        local entry = slots[index]
        if not entry or not ns.merchantOpen then
            ticker:Cancel()
            return
        end
        C_Container.UseContainerItem(entry[1], entry[2])
    end)
    return #slots
end

---------------------------------------------------------------------------

local function OnMerchantShow()
    ns.merchantOpen = true
    local db = ns.db
    -- Shift held: leave everything as it is this time.
    if IsShiftKeyDown() then return end

    local before = CurrentMoney()
    local repairCost = db.repair and Repair() or nil
    local sold = db.sellJunk and SellJunk() or 0

    if not db.report or (sold == 0 and not repairCost) then return end
    -- The money arrives a moment after the items go, so look again shortly.
    C_Timer.After(REPORT_SECONDS, function()
        local after = CurrentMoney()
        local parts = {}
        if sold > 0 then
            local earned = before and after and (after - before + (repairCost or 0)) or nil
            if earned and earned > 0 then
                parts[#parts + 1] = ("Sold %d junk item%s for %s."):format(sold, sold == 1 and "" or "s", ns.Money(earned))
            else
                parts[#parts + 1] = ("Sold %d junk item%s."):format(sold, sold == 1 and "" or "s")
            end
        end
        if repairCost then
            parts[#parts + 1] = ("Repaired for %s."):format(ns.Money(repairCost))
        end
        ns.Print(table.concat(parts, " "))
    end)
end

local function OnMerchantClosed()
    ns.merchantOpen = false
    if sellTicker then
        sellTicker:Cancel()
        sellTicker = nil
    end
end

local function Describe()
    local db = ns.db
    local doing = {}
    if db.sellJunk then doing[#doing + 1] = "sells junk" end
    if db.repair then doing[#doing + 1] = "repairs" end
    if #doing == 0 then
        return "At a vendor it does nothing."
    end
    return ("At a vendor it %s%s."):format(table.concat(doing, " and "),
        db.report and ", and says what it did" or ", silently")
end

SLASH_VENDORMATE1 = "/vendormate"
SLASH_VENDORMATE2 = "/vmate"
SlashCmdList.VENDORMATE = function(msg)
    local command = (msg or ""):lower():match("^%s*(%S*)")
    if command == "" or command == "options" then
        ns.ToggleOptions()
        return
    elseif command == "junk" then
        ns.db.sellJunk = not ns.db.sellJunk
    elseif command == "repair" then
        ns.db.repair = not ns.db.repair
    elseif command == "report" then
        ns.db.report = not ns.db.report
    elseif command == "worn" then
        ns.db.durabilityWarn = not ns.db.durabilityWarn
        ns.UpdateDurability()
        ns.Print("The worn-gear warning is " .. (ns.db.durabilityWarn and ("on, below %d%%."):format(ns.db.durabilityLevel) or "off."))
        ns.RefreshOptions()
        return
    else
        ns.Print("/vendormate - open the options")
        ns.Print("/vendormate junk - sell grey items when a vendor opens, on or off")
        ns.Print("/vendormate repair - repair when a vendor who can opens, on or off")
        ns.Print("/vendormate report - say in chat what was sold and repaired, on or off")
        ns.Print("/vendormate worn - warn on screen when gear is wearing out, on or off")
        ns.Print("Hold Shift while opening a vendor to skip both that time.")
        return
    end
    ns.Print(Describe())
    ns.RefreshOptions()
end

-- Entry in the minimap's addon list.
function VendorMate_OnAddonCompartmentClick()
    ns.ToggleOptions()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_CLOSED")
frame:SetScript("OnEvent", function(self, event, loaded)
    if event == "ADDON_LOADED" then
        if loaded ~= addonName then return end
        VendorMateDB = VendorMateDB or {}
        for key, value in pairs(defaults) do
            if VendorMateDB[key] == nil then
                VendorMateDB[key] = value
            end
        end
        ns.db = VendorMateDB
        self:UnregisterEvent("ADDON_LOADED")
    elseif not ns.db then
        return
    elseif event == "MERCHANT_SHOW" then
        -- This runs on its own with the player's bags and money, so a
        -- surprise from the game must not leave an error on screen.
        local ok, problem = pcall(OnMerchantShow)
        if not ok then
            ns.Print("Something went wrong at this vendor, so nothing more was done: " .. tostring(problem))
        end
    else
        OnMerchantClosed()
    end
end)
