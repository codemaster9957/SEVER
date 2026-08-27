-- ReplicatedStorage/AudioManager
-- Authoritative Local Audio State Manager

local AudioManager = {}

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local ASSET_WAIT_TIMEOUT = 5

local function findOrWait(parent, name)
	local object = parent:FindFirstChild(name) or parent:WaitForChild(name, ASSET_WAIT_TIMEOUT)
	if not object then
		warn(string.format("[AudioManager] Missing audio container %s.%s", parent:GetFullName(), name))
	end
	return object
end

-- Never block module initialization forever because an optional audio folder was
-- renamed, streamed late, or absent in a development place.
local SFX_FOLDER = findOrWait(workspace, "sfx to use")
local SCYTHE_SFX = findOrWait(ReplicatedStorage, "scythe sfx")
local BATTLE_MUSIC_FOLDER = findOrWait(workspace, "battle music")

local DEFAULT_FADE = 0.5

local States = {
	Lobby = "Lobby",
	BattleIntro = "BattleIntro",
	Battle = "Battle",
}
AudioManager.States = States
AudioManager.currentState = States.Lobby
AudioManager.currentOpponentUserId = 0

local activeTracks = {}
local volumeTweens = {}
local SOUND_TEMPLATES = {}
local warnedMissingSounds = {}

local soundDefinitions = {
	LobbyMusic = { folder = SFX_FOLDER, names = {"Game Lobby music"} },
	ArenaMusic = { folder = SFX_FOLDER, names = {"arena music"} },
	BattleIntroMusic = { folder = SFX_FOLDER, names = {"battle intro"} },
	Clash = { folder = SFX_FOLDER, names = {"clash"} },
	Grapple = { folder = SFX_FOLDER, names = {"Grapple Hook sfx", " Grapple Hook sfx"} },
	Dash = { folder = SFX_FOLDER, names = {"Dash sfx"} },
	AirJump = { folder = SFX_FOLDER, names = {"air jump sfx (2nd jump)"} },
	ScytheM1_1 = { folder = SCYTHE_SFX, names = {"Scythe m1 one"} },
	ScytheM1_2 = { folder = SCYTHE_SFX, names = {"Scythe m1 two"} },
	ScytheM1_3 = { folder = SCYTHE_SFX, names = {"Scythe m1 three"} },
	ScytheM1_4 = { folder = SCYTHE_SFX, names = {"Scythe m1 four"} },
	ScytheSpin = { folder = SCYTHE_SFX, names = {"scythe spinning"} },
	ScytheThrow = { folder = SCYTHE_SFX, names = {"scythe throw"} },
	AirSlash = { folder = SCYTHE_SFX, names = {"air slash"} },
}

local function warnMissingSound(name)
	if warnedMissingSounds[name] then return end
	warnedMissingSounds[name] = true
	warn("[AudioManager] Could not find sound template:", name)
end

local function findSoundTemplate(name)
	local cached = SOUND_TEMPLATES[name]
	if cached and cached.Parent then return cached end

	local definition = soundDefinitions[name]
	if not definition or not definition.folder then
		warnMissingSound(name)
		return nil
	end

	for _, possibleName in ipairs(definition.names) do
		local object = definition.folder:FindFirstChild(possibleName)
		if object and object:IsA("Sound") then
			SOUND_TEMPLATES[name] = object
			return object
		end
	end

	warnMissingSound(name)
	return nil
end

local function getRandomBattleMusicTemplate()
	if not BATTLE_MUSIC_FOLDER then
		warnMissingSound("ArenaMusic")
		return nil
	end

	local sounds = {}
	for _, child in ipairs(BATTLE_MUSIC_FOLDER:GetChildren()) do
		if child:IsA("Sound") then
			table.insert(sounds, child)
		end
	end
	if #sounds == 0 then
		warnMissingSound("ArenaMusic")
		return nil
	end
	return sounds[math.random(1, #sounds)]
end

local function getSourceUserId(source)
	if not source or typeof(source) ~= "Instance" then return 0 end
	if source:IsA("Player") then return source.UserId end

	local character = source:IsA("Model") and source or source:FindFirstAncestorOfClass("Model")
	if not character then return 0 end
	local player = Players:GetPlayerFromCharacter(character)
	return player and player.UserId or 0
end

local function isAllowed(name, sourceUserId, isMusic)
	if not RunService:IsClient() then return true end

	if AudioManager.currentState == States.Lobby then
		if isMusic then return name == "LobbyMusic" end
		return sourceUserId == 0
	elseif AudioManager.currentState == States.BattleIntro then
		if isMusic then return name == "BattleIntroMusic" end
		return false
	elseif AudioManager.currentState == States.Battle then
		if isMusic then return name == "ArenaMusic" end
		local localId = Players.LocalPlayer and Players.LocalPlayer.UserId or 0
		return sourceUserId == 0
			or sourceUserId == localId
			or sourceUserId == AudioManager.currentOpponentUserId
	end

	return false
end

local function cancelTween(sound)
	local tween = volumeTweens[sound]
	if tween then
		tween:Cancel()
		volumeTweens[sound] = nil
	end
end

local function fadeSound(sound, targetVolume, duration, destroyOnEnd)
	if not sound or not sound.Parent then return end
	cancelTween(sound)

	if duration <= 0 then
		sound.Volume = targetVolume
		if targetVolume <= 0 then
			sound:Stop()
			if destroyOnEnd then sound:Destroy() end
		end
		return
	end

	local tween = TweenService:Create(
		sound,
		TweenInfo.new(duration, Enum.EasingStyle.Sine),
		{Volume = targetVolume}
	)
	volumeTweens[sound] = tween
	tween.Completed:Connect(function()
		if volumeTweens[sound] == tween then
			volumeTweens[sound] = nil
		end
		if targetVolume <= 0 and sound.Parent then
			sound:Stop()
			if destroyOnEnd then sound:Destroy() end
		end
	end)
	tween:Play()
end

AudioManager.ActiveTracks = activeTracks

function AudioManager:SetState(newState, opponentUserId)
	if not States[newState] then
		warn("[AudioManager] Invalid State:", newState)
		return
	end

	AudioManager.currentState = newState
	AudioManager.currentOpponentUserId = tonumber(opponentUserId) or 0

	if newState == States.Lobby then
		self:StopMusic("ArenaMusic")
		self:StopMusic("BattleIntroMusic")
		self:PlayMusic("LobbyMusic", true)
	elseif newState == States.BattleIntro then
		self:StopMusic("LobbyMusic")
		self:StopMusic("ArenaMusic")
		self:PlayMusic("BattleIntroMusic", false)
	elseif newState == States.Battle then
		self:StopMusic("LobbyMusic")
		self:StopMusic("BattleIntroMusic")
		self:PlayMusic("ArenaMusic", true)
	end
end

function AudioManager:PlayMusic(name, looped)
	if not isAllowed(name, 0, true) then return nil end

	local existing = activeTracks[name]
	if existing and existing.Parent and existing.IsPlaying then
		local volumeTemplate = name == "ArenaMusic" and getRandomBattleMusicTemplate() or findSoundTemplate(name)
		fadeSound(existing, volumeTemplate and volumeTemplate.Volume or existing.Volume, DEFAULT_FADE)
		return existing
	end

	local template = name == "ArenaMusic" and getRandomBattleMusicTemplate() or findSoundTemplate(name)
	if not template then return nil end

	local sound = template:Clone()
	sound.Looped = looped == true
	sound.Volume = 0
	sound.Parent = SoundService
	sound:Play()

	activeTracks[name] = sound
	fadeSound(sound, template.Volume, DEFAULT_FADE)

	if not sound.Looped then
		sound.Ended:Connect(function()
			if activeTracks[name] == sound then activeTracks[name] = nil end
			if sound.Parent then sound:Destroy() end
		end)
	end

	return sound
end

function AudioManager:StopMusic(name, fadeTime)
	local sound = activeTracks[name]
	if sound then
		activeTracks[name] = nil
		fadeSound(sound, 0, fadeTime or DEFAULT_FADE, true)
	end
end

function AudioManager:PlaySFX(name, options)
	options = options or {}
	local sourceUserId = options.SourceUserId or getSourceUserId(options.Character or options.Parent)
	if not isAllowed(name, sourceUserId, false) then return nil end

	local template = findSoundTemplate(name)
	if not template then return nil end

	local sound = template:Clone()
	sound.Volume = options.Volume or template.Volume
	sound.PlaybackSpeed = options.PlaybackSpeed or template.PlaybackSpeed

	if options.Character or options.Parent then
		local parent = options.Character
			and (options.Character:FindFirstChild("HumanoidRootPart") or options.Character.PrimaryPart)
			or options.Parent
		if not parent then
			sound:Destroy()
			return nil
		end
		sound.Parent = parent
	else
		sound.Parent = SoundService
	end

	sound:Play()

	if not sound.Looped then
		sound.Ended:Connect(function()
			if sound.Parent then sound:Destroy() end
		end)
		-- TimeLength can still be 0 before the asset loads, so use a conservative
		-- fallback instead of destroying new sounds after one second.
		task.delay(math.max(sound.TimeLength + 1, 10), function()
			if sound.Parent then sound:Destroy() end
		end)
	end

	return sound
end

return AudioManager
