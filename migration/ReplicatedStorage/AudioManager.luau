-- ReplicatedStorage/AudioManager
-- Authoritative Local Audio State Manager

local AudioManager = {}

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local SFX_FOLDER = workspace:WaitForChild("sfx to use")
local SCYTHE_SFX = ReplicatedStorage:WaitForChild("scythe sfx")
local BATTLE_MUSIC_FOLDER = workspace:WaitForChild("battle music")

local DEFAULT_FADE = 0.5

-- States
local States = {
	Lobby = "Lobby",
	BattleIntro = "BattleIntro",
	Battle = "Battle"
}
AudioManager.States = States

-- Publicly accessible properties (for intro logic)
AudioManager.currentState = States.Lobby
AudioManager.currentOpponentUserId = 0

-- Private state
local activeTracks = {} -- [Name] = Sound
local volumeTweens = {}

local DAILY_SOUND_TEMPLATES = {} -- Cache for templates

local soundDefinitions = {
	LobbyMusic = { folder = SFX_FOLDER, names = {"Game Lobby music"} },
	ArenaMusic = { folder = SFX_FOLDER, names = {"arena music"} },
	BattleIntroMusic = { folder = SFX_FOLDER, names = {"battle intro"} },
	
	-- Combat SFX
	Clash = { folder = SFX_FOLDER, names = {"clash"} },
	Grapple = { folder = SFX_FOLDER, names = {"Grapple Hook sfx", " Grapple Hook sfx"} },
	Dash = { folder = SFX_FOLDER, names = {"Dash sfx"} },
	AirJump = { folder = SFX_FOLDER, names = {"air jump sfx (2nd jump)"} },
	
	-- Scythe SFX
	ScytheM1_1 = { folder = SCYTHE_SFX, names = {"Scythe m1 one"} },
	ScytheM1_2 = { folder = SCYTHE_SFX, names = {"Scythe m1 two"} },
	ScytheM1_3 = { folder = SCYTHE_SFX, names = {"Scythe m1 three"} },
	ScytheM1_4 = { folder = SCYTHE_SFX, names = {"Scythe m1 four"} },
	ScytheSpin = { folder = SCYTHE_SFX, names = {"scythe spinning"} },
	ScytheThrow = { folder = SCYTHE_SFX, names = {"scythe throw"} },
	AirSlash = { folder = SCYTHE_SFX, names = {"air slash"} },
}

local function findSoundTemplate(name)
	if DAILY_SOUND_TEMPLATES[name] then return DAILY_SOUND_TEMPLATES[name] end
	
	local definition = soundDefinitions[name]
	if not definition then return nil end

	for _, possibleName in ipairs(definition.names) do
		local obj = definition.folder:FindFirstChild(possibleName)
		if obj and obj:IsA("Sound") then 
			DAILY_SOUND_TEMPLATES[name] = obj
			return obj 
		end
	end
	return nil
end

-- Picks a random battle track from the "battle music" folder.
local function getRandomBattleMusicTemplate()
	local sounds = {}
	for _, child in ipairs(BATTLE_MUSIC_FOLDER:GetChildren()) do
		if child:IsA("Sound") then
			table.insert(sounds, child)
		end
	end
	if #sounds == 0 then return nil end
	return sounds[math.random(1, #sounds)]
end

local function getSourceUserId(source)
	if not source then return 0 end
	if typeof(source) ~= "Instance" then return 0 end
	if source:IsA("Player") then return source.UserId end

	local character = source:IsA("Model") and source or source:FindFirstAncestorOfClass("Model")
	if not character then return 0 end

	local player = Players:GetPlayerFromCharacter(character)
	return player and player.UserId or 0
end

-- Permission Logic
local function isAllowed(name, sourceUserId, isMusic)
	if not RunService:IsClient() then return true end

	if AudioManager.currentState == States.Lobby then
		if isMusic then
			return name == "LobbyMusic"
		end
		-- Only allow local UI or non-combat system sounds
		return sourceUserId == 0
	
	elseif AudioManager.currentState == States.BattleIntro then
		if isMusic then
			return name == "BattleIntroMusic"
		end
		-- Mute every combat sound
		return false

	elseif AudioManager.currentState == States.Battle then
		if isMusic then
			return name == "ArenaMusic"
		end
		
		-- Allow own combat sounds, opponent's, and system sounds (0)
		local localId = Players.LocalPlayer and Players.LocalPlayer.UserId or 0
		return sourceUserId == 0 or sourceUserId == localId or sourceUserId == AudioManager.currentOpponentUserId
	end

	return false
end

local function cancelTween(sound)
	if volumeTweens[sound] then
		volumeTweens[sound]:Cancel()
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
			if destroyOnEnd then
				sound:Destroy()
			end
		end
		return
	end

	local tween = TweenService:Create(sound, TweenInfo.new(duration, Enum.EasingStyle.Sine), {Volume = targetVolume})
	volumeTweens[sound] = tween
	
	tween.Completed:Connect(function()
		volumeTweens[sound] = nil
		if targetVolume <= 0 then
			sound:Stop()
			if destroyOnEnd then
				sound:Destroy()
			end
		end
	end)
	
	tween:Play()
end

-- Shared track access for MatchAudioManager
AudioManager.ActiveTracks = activeTracks

function AudioManager:SetState(newState, opponentUserId)
	if not States[newState] then
		warn("[AudioManager] Invalid State:", newState)
		return
	end

	print("[AudioManager] Transitioning to State:", newState)
	AudioManager.currentState = newState
	AudioManager.currentOpponentUserId = tonumber(opponentUserId) or 0

	-- Force cleanup based on new state
	if AudioManager.currentState == States.Lobby then
		self:StopMusic("ArenaMusic")
		self:StopMusic("BattleIntroMusic")
		self:PlayMusic("LobbyMusic", true)
	elseif AudioManager.currentState == States.BattleIntro then
		self:StopMusic("LobbyMusic")
		self:StopMusic("ArenaMusic")
		self:PlayMusic("BattleIntroMusic", false)
	elseif AudioManager.currentState == States.Battle then
		self:StopMusic("LobbyMusic")
		self:StopMusic("BattleIntroMusic")
		self:PlayMusic("ArenaMusic", true)
	end
end

function AudioManager:PlayMusic(name, looped)
	if not isAllowed(name, 0, true) then 
		print("[AudioManager] Music Not Allowed in current state:", name)
		return 
	end
	
	local existing = activeTracks[name]
	if existing and existing.Parent and existing.IsPlaying then
		local volTemplate = (name == "ArenaMusic") and getRandomBattleMusicTemplate() or findSoundTemplate(name)
		fadeSound(existing, volTemplate and volTemplate.Volume or existing.Volume, DEFAULT_FADE)
		return existing
	end

	local template
	if name == "ArenaMusic" then
		template = getRandomBattleMusicTemplate()
	else
		template = findSoundTemplate(name)
	end
	if not template then 
		warn("[AudioManager] Could not find template for music:", name)
		return 
	end

	print("[AudioManager] Starting Music Track:", name)
	local sound = template:Clone()
	sound.Looped = looped == true
	sound.Volume = 0
	sound.Parent = SoundService
	sound:Play()
	
	activeTracks[name] = sound
	fadeSound(sound, template.Volume, DEFAULT_FADE)
	
	if not sound.Looped then
		sound.Ended:Connect(function()
			if activeTracks[name] == sound then
				activeTracks[name] = nil
			end
			sound:Destroy()
		end)
	end
	
	return sound
end

function AudioManager:StopMusic(name, fadeTime)
	local sound = activeTracks[name]
	if sound then
		print("[AudioManager] Stopping Music Track:", name)
		activeTracks[name] = nil
		fadeSound(sound, 0, fadeTime or DEFAULT_FADE, true)
	end
end

function AudioManager:PlaySFX(name, options)
	options = options or {}
	local sourceUserId = options.SourceUserId or getSourceUserId(options.Character or options.Parent)
	
	if not isAllowed(name, sourceUserId, false) then return end

	local template = findSoundTemplate(name)
	if not template then return end

	local sound = template:Clone()
	sound.Volume = options.Volume or template.Volume
	sound.PlaybackSpeed = options.PlaybackSpeed or template.PlaybackSpeed
	
	-- Spatial or local
	if options.Character or options.Parent then
		sound.Parent = options.Character and (options.Character:FindFirstChild("HumanoidRootPart") or options.Character.PrimaryPart) or options.Parent
	else
		sound.Parent = SoundService
	end
	
	sound:Play()
	
	if not sound.Looped then
		sound.Ended:Connect(function() sound:Destroy() end)
		task.delay(sound.TimeLength + 1, function() if sound.Parent then sound:Destroy() end end)
	end
	
	return sound
end

return AudioManager
