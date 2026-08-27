--!strict
-- Shared canonical rules for the two-slot scythe special-move loadout.

local LoadoutPolicy = {}

LoadoutPolicy.WeaponId = "scythe"
LoadoutPolicy.DefaultSlots = table.freeze({ "scythe_throw", "spin" })
LoadoutPolicy.MoveOrder = table.freeze({ "scythe_throw", "spin", "soul_reap" })

LoadoutPolicy.Moves = table.freeze({
	scythe_throw = table.freeze({
		Id = "scythe_throw",
		Name = "Scythe Throw",
		Description = "Hurl the scythe across the lane and punish enemies at range.",
		Cooldown = 2,
	}),
	spin = table.freeze({
		Id = "spin",
		Name = "Spin",
		Description = "Spin the scythe around you for a sustained close-range attack.",
		Cooldown = 5,
	}),
	soul_reap = table.freeze({
		Id = "soul_reap",
		Name = "Soul Reap",
		Description = "Burst through the lane at extreme speed and reap anyone caught in the dash.",
		Cooldown = 8,
	}),
})

local ALIASES = table.freeze({
	["scythe_throw"] = "scythe_throw",
	["scythe throw"] = "scythe_throw",
	["throw"] = "scythe_throw",
	["throwing"] = "scythe_throw",
	["spin"] = "spin",
	["scythe spin"] = "spin",
	["soul_reap"] = "soul_reap",
	["soul reap"] = "soul_reap",
	["soulreap"] = "soul_reap",
})

local function normalizedText(value: any): string?
	if type(value) ~= "string" then
		return nil
	end
	local lowered = string.lower(value)
	lowered = string.gsub(lowered, "%-", " ")
	lowered = string.gsub(lowered, "_", " ")
	lowered = string.gsub(lowered, "%s+", " ")
	lowered = string.gsub(lowered, "^%s+", "")
	lowered = string.gsub(lowered, "%s+$", "")
	return lowered
end

function LoadoutPolicy.NormalizeMoveId(value: any): string?
	local text = normalizedText(value)
	if not text or text == "" then
		return nil
	end
	local direct = ALIASES[text]
	if direct then
		return direct
	end
	local underscored = string.gsub(text, " ", "_")
	if LoadoutPolicy.Moves[underscored] then
		return underscored
	end
	return nil
end

function LoadoutPolicy.IsValidMove(value: any): boolean
	return LoadoutPolicy.NormalizeMoveId(value) ~= nil
end

function LoadoutPolicy.Sanitize(move1: any, move2: any): {string}
	local first = LoadoutPolicy.NormalizeMoveId(move1) or LoadoutPolicy.DefaultSlots[1]
	local second = LoadoutPolicy.NormalizeMoveId(move2)

	if not second or second == first then
		for _, candidate in ipairs(LoadoutPolicy.MoveOrder) do
			if candidate ~= first then
				second = candidate
				break
			end
		end
	end

	return { first, second :: string }
end

function LoadoutPolicy.Assign(currentSlots: any, slotIndex: any, moveId: any): ({string}?, string?)
	local slot = tonumber(slotIndex)
	if slot ~= 1 and slot ~= 2 then
		return nil, "InvalidSlot"
	end

	local canonical = LoadoutPolicy.NormalizeMoveId(moveId)
	if not canonical then
		return nil, "InvalidMove"
	end

	local current = LoadoutPolicy.Sanitize(
		type(currentSlots) == "table" and currentSlots[1] or nil,
		type(currentSlots) == "table" and currentSlots[2] or nil
	)

	local other = if slot == 1 then 2 else 1
	if current[other] == canonical then
		current[other] = current[slot]
	end
	current[slot] = canonical

	return current, nil
end

function LoadoutPolicy.IsEquipped(currentSlots: any, moveId: any): boolean
	local canonical = LoadoutPolicy.NormalizeMoveId(moveId)
	if not canonical then
		return false
	end
	local current = LoadoutPolicy.Sanitize(
		type(currentSlots) == "table" and currentSlots[1] or nil,
		type(currentSlots) == "table" and currentSlots[2] or nil
	)
	return current[1] == canonical or current[2] == canonical
end

function LoadoutPolicy.GetMove(moveId: any)
	local canonical = LoadoutPolicy.NormalizeMoveId(moveId)
	return canonical and LoadoutPolicy.Moves[canonical] or nil
end

return LoadoutPolicy
