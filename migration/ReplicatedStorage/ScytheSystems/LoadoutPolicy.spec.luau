local LoadoutPolicy = require(script.Parent:WaitForChild("LoadoutPolicy"))

local function assertEqual(actual, expected, message)
	assert(actual == expected, string.format("%s (expected %s, got %s)", message, tostring(expected), tostring(actual)))
end

local function assertSlots(actual, expected1, expected2, message)
	assert(type(actual) == "table", message .. " (expected table)")
	assertEqual(actual[1], expected1, message .. " slot 1")
	assertEqual(actual[2], expected2, message .. " slot 2")
end

assertSlots(
	LoadoutPolicy.Sanitize(nil, nil),
	"scythe_throw",
	"spin",
	"missing save data must fall back to the default loadout"
)

assertSlots(
	LoadoutPolicy.Sanitize("Soul Reap", "Throw"),
	"soul_reap",
	"scythe_throw",
	"legacy/display names must normalize to canonical move ids"
)

assertSlots(
	LoadoutPolicy.Sanitize("spin", "spin"),
	"spin",
	"scythe_throw",
	"duplicate saved moves must be repaired"
)

local swapped = LoadoutPolicy.Assign({ "scythe_throw", "spin" }, 1, "spin")
assertSlots(swapped, "spin", "scythe_throw", "equipping the other slot's move must swap slots")

local replaced = LoadoutPolicy.Assign({ "scythe_throw", "spin" }, 2, "soul_reap")
assertSlots(replaced, "scythe_throw", "soul_reap", "a new move must replace the selected slot")

local rejected, reason = LoadoutPolicy.Assign({ "scythe_throw", "spin" }, 3, "soul_reap")
assertEqual(rejected, nil, "invalid slot must be rejected")
assertEqual(reason, "InvalidSlot", "invalid slot rejection must be explicit")

local invalidMove, invalidReason = LoadoutPolicy.Assign({ "scythe_throw", "spin" }, 1, "not_a_move")
assertEqual(invalidMove, nil, "unknown moves must be rejected")
assertEqual(invalidReason, "InvalidMove", "invalid move rejection must be explicit")

assertEqual(LoadoutPolicy.IsEquipped({ "spin", "soul_reap" }, "Soul Reap"), true, "equipped checks must normalize aliases")
assertEqual(LoadoutPolicy.IsEquipped({ "spin", "soul_reap" }, "scythe_throw"), false, "unequipped moves must be rejected")

return true
