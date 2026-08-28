--!strict
-- Regression contract for arena selection.
-- Any usable child of workspace.Arenas must be eligible while free; arena names are not a whitelist.

local Policy = require(script.Parent:WaitForChild("ArenaSelectionPolicy"))

type ArenaStub = { Name: string, Usable: boolean }

local arenas: {ArenaStub} = {
	{Name = "Arena1", Usable = true},
	{Name = "Arena2", Usable = true},
	{Name = "Arena3", Usable = true},
	{Name = "Arena4", Usable = true},
	{Name = "Arena5", Usable = true},
	{Name = "ArenaFuture", Usable = true},
	{Name = "BrokenArena", Usable = false},
}

local locked: {[string]: boolean} = {
	Arena2 = true,
	Arena4 = true,
}

local available = Policy.FilterAvailable(
	arenas,
	function(arena: ArenaStub): boolean
		return locked[arena.Name] == true
	end,
	function(arena: ArenaStub): boolean
		return arena.Usable
	end
)

assert(#available == 4, "all and only usable, unlocked arenas should be eligible")
assert(available[1].Name == "Arena1", "Arena1 must not be excluded by arena selection")
assert(available[2].Name == "Arena3", "Arena3 must not be excluded by arena selection")
assert(available[3].Name == "Arena5", "Arena5 must not be excluded by arena selection")
assert(available[4].Name == "ArenaFuture", "future arena names must automatically be eligible")

local pickedLast = Policy.ChooseRandom(available, function(minimum: number, maximum: number): number
	assert(minimum == 1, "random selection should start at the first eligible arena")
	assert(maximum == #available, "random selection should span every eligible arena")
	return maximum
end)
assert(pickedLast == available[#available], "the random picker must be able to select the final eligible arena")

assert(Policy.ChooseRandom({}, function(): number
	return 1
end) == nil, "no eligible arenas should return nil")
