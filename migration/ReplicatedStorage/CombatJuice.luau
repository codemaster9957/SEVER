local CombatJuice = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_NAME = "CombatFeelRemote"

local function getOrCreateRemote()
	local remote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
	if remote then
		return remote
	end

	if not RunService:IsServer() then
		return ReplicatedStorage:WaitForChild(REMOTE_NAME)
	end

	remote = Instance.new("RemoteEvent")
	remote.Name = REMOTE_NAME
	remote.Parent = ReplicatedStorage
	return remote
end

function CombatJuice.GetRemote()
	return getOrCreateRemote()
end

function CombatJuice.Emit(action, data)
	if not RunService:IsServer() then
		return
	end

	getOrCreateRemote():FireAllClients(action, data or {})
end

function CombatJuice.EmitTo(player, action, data)
	if not RunService:IsServer() or not player then
		return
	end

	getOrCreateRemote():FireClient(player, action, data or {})
end

function CombatJuice.GetPlayerFromHumanoid(humanoid)
	if not humanoid or not humanoid.Parent then
		return nil
	end

	return game:GetService("Players"):GetPlayerFromCharacter(humanoid.Parent)
end

return CombatJuice
