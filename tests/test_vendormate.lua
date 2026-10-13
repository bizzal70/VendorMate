-- The game's side: a purse, a vendor, and bags.
MONEY = 50000
SHIFT = false
CAN_REPAIR, REPAIR_COST = true, 0
REPAIRS = 0
JUNK = 0            -- how many junk items the game says are in the bags
JUNK_VALUE = 0      -- what they are worth altogether
SELL_ENABLED = true
SELL_CALLS = 0
GetMoney = function() return MONEY end
IsShiftKeyDown = function() return SHIFT end
CanMerchantRepair = function() return CAN_REPAIR end
GetRepairAllCost = function() return REPAIR_COST, REPAIR_COST > 0 end
RepairAllItems = function() REPAIRS = REPAIRS + 1; MONEY = MONEY - REPAIR_COST; REPAIR_COST = 0 end
C_MerchantFrame = {
    IsSellAllJunkEnabled = function() return SELL_ENABLED end,
    GetNumJunkItems = function() return JUNK end,
    -- Like the real game, the money arrives after the call returns.
    SellAllJunkItems = function() SELL_CALLS = SELL_CALLS + 1; PENDING = JUNK_VALUE; JUNK, JUNK_VALUE = 0, 0 end,
}
PENDING = 0
-- bag -> list of { quality =, hasNoValue =, isLocked = }
BAGS = { [0] = {}, {}, {}, {}, {} }
USED = {}
C_Container = {
    GetContainerNumSlots = function(bag) return #BAGS[bag] end,
    GetContainerItemInfo = function(bag, slot) return BAGS[bag][slot] end,
    UseContainerItem = function(bag, slot) USED[#USED + 1] = bag .. ":" .. slot end,
}

local ns = LoadAddon(ADDON_DIR, "VendorMate")
local function check(cond, what) if not cond then error("CHECK FAILED: " .. what, 2) end; io.write("pass  ", what, "\n") end
-- Opens a vendor, lets the money from selling arrive, then runs the delayed report.
local function visit()
    local printedBefore = #PRINTED
    Fire("MERCHANT_SHOW")
    MONEY = MONEY + PENDING; PENDING = 0
    local timers = AFTERS; AFTERS = {}
    for _, fn in ipairs(timers) do fn() end
    Fire("MERCHANT_CLOSED")
    local said = {}
    for i = printedBefore + 1, #PRINTED do said[#said + 1] = PRINTED[i] end
    return table.concat(said, " | ")
end

check(ns.Money(12345) == "1g 23s 45c" and ns.Money(500) == "5s" and ns.Money(0) == "0c" and ns.Money(10007) == "1g 7c", "money is written as gold, silver and copper")

Fire("MERCHANT_SHOW")
check(SELL_CALLS == 0 and REPAIRS == 0, "before its settings load, the addon does nothing at a vendor")
Fire("ADDON_LOADED", "VendorMate")
check(ns.db.sellJunk and ns.db.repair and ns.db.report, "settings start with selling, repairing and reporting on")

local said = visit()
check(SELL_CALLS == 0 and REPAIRS == 0 and said == "", "with nothing to sell or repair, it does and says nothing")

JUNK, JUNK_VALUE = 3, 1250
said = visit()
check(SELL_CALLS == 1 and MONEY == 51250, "junk is sold when a vendor opens")
check(said:find("Sold 3 junk items for 12s 50c.", 1, true) ~= nil, "and it says what the junk earned: " .. said)

REPAIR_COST = 3400
said = visit()
check(REPAIRS == 1 and MONEY == 47850 and said:find("Repaired for 34s.", 1, true) ~= nil, "gear is repaired and the cost reported: " .. said)

JUNK, JUNK_VALUE, REPAIR_COST = 1, 80, 500
said = visit()
check(said:find("Sold 1 junk item for 80c.", 1, true) ~= nil and said:find("Repaired for 5s.", 1, true) ~= nil, "selling and repairing together are reported correctly: " .. said)

JUNK, JUNK_VALUE, REPAIR_COST = 2, 100, 700
SHIFT = true
said = visit()
check(SELL_CALLS == 2 and REPAIRS == 2 and said == "", "holding Shift skips both")
SHIFT = false

REPAIR_COST, MONEY = 999999, 1000
said = visit()
check(REPAIRS == 2 and said:find("more than you are carrying", 1, true) ~= nil, "repairs that cannot be afforded are not attempted, and it says so")
check(SELL_CALLS == 3, "but the junk is still sold")
REPAIR_COST, MONEY = 0, 50000

CAN_REPAIR, REPAIR_COST = false, 700
visit()
check(REPAIRS == 2, "a vendor who cannot repair is not asked to")
CAN_REPAIR, REPAIR_COST = true, 0

SlashCmdList.VENDORMATE("junk")
JUNK, JUNK_VALUE = 4, 400
visit()
check(SELL_CALLS == 3 and not ns.db.sellJunk, "/vendormate junk turns selling off")
SlashCmdList.VENDORMATE("junk")
SlashCmdList.VENDORMATE("repair")
REPAIR_COST = 300
visit()
check(REPAIRS == 2 and SELL_CALLS == 4, "/vendormate repair turns repairing off, and selling carries on")
SlashCmdList.VENDORMATE("repair"); REPAIR_COST = 0
SlashCmdList.VENDORMATE("report")
JUNK, JUNK_VALUE = 2, 200
said = visit()
check(SELL_CALLS == 5 and said == "", "/vendormate report turns the chat line off")
SlashCmdList.VENDORMATE("report")

SELL_ENABLED = false; JUNK = 2
visit()
check(SELL_CALLS == 5, "where the game has junk selling disabled, nothing is sold")
SELL_ENABLED = true; JUNK = 0

-- a client without the built-in: grey items with a value are sold one by one
local sellAll = C_MerchantFrame.SellAllJunkItems
C_MerchantFrame.SellAllJunkItems = nil
BAGS[0] = { { quality = 0 }, { quality = 1 }, { quality = 0, hasNoValue = true }, { quality = 0, isLocked = true } }
BAGS[2] = { { quality = 2 }, { quality = 0 } }
TICKERS = {}
Fire("MERCHANT_SHOW")
local ticker = TICKERS[1]
local fake = { Cancel = function(self) self.cancelled = true end }
for _ = 1, 5 do if not fake.cancelled then ticker(fake) end end
check(table.concat(USED, " ") == "0:1 2:2" and fake.cancelled, "without it, only grey items a vendor will pay for are sold, then it stops")
USED = {}; TICKERS = {}
Fire("MERCHANT_SHOW"); Fire("MERCHANT_CLOSED")
fake = { Cancel = function(self) self.cancelled = true end }
TICKERS[1](fake)
check(#USED == 0 and fake.cancelled, "closing the vendor stops the selling at once")
C_MerchantFrame.SellAllJunkItems = sellAll
BAGS[0], BAGS[2] = {}, {}
AFTERS = {}

-- the game misbehaving must not leave an error on screen
GetRepairAllCost = function() error("something this client does differently") end
local ok = pcall(Fire, "MERCHANT_SHOW")
check(ok and PRINTED[#PRINTED]:find("Something went wrong at this vendor", 1, true) ~= nil, "a surprise from the game is reported in chat, not as an error")
GetRepairAllCost = function() return REPAIR_COST, REPAIR_COST > 0 end
Fire("MERCHANT_CLOSED"); AFTERS = {}

-- options window
SlashCmdList.VENDORMATE("")
check(VendorMateOptions:IsShown(), "/vendormate opens the options")
local rows = {}
for _, f in ipairs(Frames()) do
    if rawget(f, "Refresh") and f.__scripts.OnClick then rows[#rows + 1] = f end
end
check(#rows == 3, "the options have three controls")
for index, key in ipairs({ "sellJunk", "repair", "report" }) do
    rows[index].__scripts.OnClick(rows[index])
    local off = not ns.db[key]
    rows[index].__scripts.OnClick(rows[index])
    assert(off and ns.db[key], key)
end
check(true, "each one switches its setting off and on")
VendorMate_OnAddonCompartmentClick()
check(not VendorMateOptions:IsShown(), "the minimap addon list entry toggles the options")
SlashCmdList.VENDORMATE("help")
