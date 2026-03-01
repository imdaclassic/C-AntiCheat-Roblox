-- Anti-Speed Hack Script with Adaptive Physics Calculations
-- Place this in ServerScriptService

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Create or get RemoteEvent
local remoteEvent = ReplicatedStorage:FindFirstChild("ClassicAC_COMS")
if not remoteEvent then
	remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = "ClassicAC_COMS"
	remoteEvent.Parent = ReplicatedStorage
	print("[Anti-Speed] Created ClassicAC_COMS RemoteEvent")
else
	print("[Anti-Speed] Found existing ClassicAC_COMS RemoteEvent")
end

-- Physics Constants
local GRAVITY = 196.2 -- Roblox gravity in studs/s²
local CHECK_INTERVAL = 0.1 -- Check every 0.1 seconds (10 times per second)
local LENIENCY = 5 -- Extra studs of leniency
local LATENCY_BUFFER = 1.05 -- 5% buffer for network latency

-- Player data storage
local playerData = {}

-- Global API for external control
_G.ClassicAC = {
	toggleTP = function(username)
		local player = Players:FindFirstChild(username)
		if not player then
			warn("[Anti-Speed] Player not found:", username)
			return false
		end

		local char = player.Character
		if not char then
			warn("[Anti-Speed] Character not found for:", username)
			return false
		end

		local canTP = char:GetAttribute("can_tp")
		char:SetAttribute("can_tp", not canTP)

		return not canTP
	end,

	setAllowedWalkSpeed = function(username, speed)
		local player = Players:FindFirstChild(username)
		if not player then
			warn("[Anti-Speed] Player not found:", username)
			return false
		end

		local char = player.Character
		if not char then
			warn("[Anti-Speed] Character not found for:", username)
			return false
		end

		char:SetAttribute("studs_second", speed)
		print(string.format("[Anti-Speed] Set walk speed for %s to %.2f studs/s", username, speed))
		return true
	end,

	setAllowedJumpPower = function(username, jumpPower)
		local player = Players:FindFirstChild(username)
		if not player then
			warn("[Anti-Speed] Player not found:", username)
			return false
		end

		local char = player.Character
		if not char then
			warn("[Anti-Speed] Character not found for:", username)
			return false
		end

		char:SetAttribute("jump_power", jumpPower)
		print(string.format("[Anti-Speed] Set jump power for %s to %.2f", username, jumpPower))
		return true
	end,

	getPlayerStatus = function(username)
		local player = Players:FindFirstChild(username)
		if not player or not player.Character then
			return nil
		end

		local char = player.Character
		return {
			canTP = char:GetAttribute("can_tp") or false,
			walkSpeed = char:GetAttribute("studs_second") or 16,
			jumpPower = char:GetAttribute("jump_power") or 50,
			violations = playerData[player.UserId] and playerData[player.UserId].violations or 0
		}
	end,

	hasViolated = function(username, timeout)
		local player = Players:FindFirstChild(username)
		if not player then
			warn("[Anti-Speed] Player not found:", username)
			return nil
		end

		local data = playerData[player.UserId]
		if not data then
			warn("[Anti-Speed] Player data not initialized:", username)
			return nil
		end

		timeout = timeout or 1 -- Default 1 second timeout (10 checks at 0.1s interval)
		local startTime = tick()
		local initialViolationCount = data.violations

		print(string.format("[Anti-Speed] Monitoring %s for violations (Current: %d)...", username, initialViolationCount))

		-- Wait and monitor for violations
		while tick() - startTime < timeout do
			-- Check if violation count increased
			if data.violations > initialViolationCount then
				print(string.format("[Anti-Speed] VIOLATION DETECTED for %s! (Violations: %d -> %d)", 
					username, initialViolationCount, data.violations))
				return true -- TRUE means they VIOLATED
			end

			task.wait(0.05) -- Check twice per interval for faster detection
		end

		-- No violations detected within timeout
		print(string.format("[Anti-Speed] No violations for %s (Clean)", username))
		return false -- FALSE means they're CLEAN
	end
}

print("[Anti-Speed] Global API loaded:")
print("  _G.ClassicAC.toggleTP(username)")
print("  _G.ClassicAC.setAllowedWalkSpeed(username, speed)")
print("  _G.ClassicAC.setAllowedJumpPower(username, jumpPower)")
print("  _G.ClassicAC.getPlayerStatus(username)")
print("  _G.ClassicAC.hasViolated(username, timeout?) - Returns: true=VIOLATED, false=clean, nil=error")

-- Function to calculate max distances based on character attributes
local function calculateMaxDistances(walkSpeed, jumpPower)
	local TIME_TO_PEAK = jumpPower / GRAVITY
	local MAX_JUMP_HEIGHT = (jumpPower * jumpPower) / (2 * GRAVITY)

	-- Calculate distances for the 0.1 second interval
	local MAX_HORIZONTAL_DISTANCE = (walkSpeed * CHECK_INTERVAL) + LENIENCY
	local MAX_DIAGONAL_DISTANCE = math.sqrt(MAX_HORIZONTAL_DISTANCE^2 + MAX_JUMP_HEIGHT^2) + LENIENCY

	return {
		ground = MAX_HORIZONTAL_DISTANCE * LATENCY_BUFFER,
		airborne = MAX_DIAGONAL_DISTANCE * LATENCY_BUFFER,
		fallHorizontal = MAX_HORIZONTAL_DISTANCE * LATENCY_BUFFER
	}
end

-- Function to safely get character components
local function getCharacterAndRoot(player)
	local char = player.Character
	if not char then return nil, nil, nil end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local rootPart = char:FindFirstChild("HumanoidRootPart")

	if humanoid and rootPart and humanoid.Health > 0 then
		return char, rootPart, humanoid
	end

	return nil, nil, nil
end

-- Function to check if player is airborne
local function isAirborne(humanoid)
	local state = humanoid:GetState()
	return state == Enum.HumanoidStateType.Freefall or 
		state == Enum.HumanoidStateType.Flying or
		state == Enum.HumanoidStateType.Jumping
end

-- Function to safely notify player of violation
local function notifyPlayer(player, message)
	local success, err = pcall(function()
		remoteEvent:FireClient(player, "vio_msg", message)
	end)

	if not success then
		warn("[Anti-Speed] Failed to notify player", player.Name, ":", err)
	else
		print("[Anti-Speed] Notification sent to", player.Name)
	end
end

-- Function to setup character attributes
local function setupCharacterAttributes(character)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then return end

	-- Set studs_second attribute if it doesn't exist
	if character:GetAttribute("studs_second") == nil then
		character:SetAttribute("studs_second", humanoid.WalkSpeed)
	end

	-- Set jump_power attribute if it doesn't exist
	if character:GetAttribute("jump_power") == nil then
		character:SetAttribute("jump_power", humanoid.JumpPower)
	end

	-- Set can_tp attribute if it doesn't exist
	if character:GetAttribute("can_tp") == nil then
		character:SetAttribute("can_tp", false)
	end

	print(string.format(
		"[Anti-Speed] Attributes set for %s | WalkSpeed: %.2f | JumpPower: %.2f | CanTP: %s",
		character.Name,
		character:GetAttribute("studs_second"),
		character:GetAttribute("jump_power"),
		tostring(character:GetAttribute("can_tp"))
		))
end

-- Function to initialize player tracking
local function initializePlayer(player)
	print("[Anti-Speed] Initializing player:", player.Name)

	local function setupCharacter(character)
		-- Setup attributes first
		setupCharacterAttributes(character)

		local rootPart = character:WaitForChild("HumanoidRootPart", 10)
		if not rootPart then 
			warn("[Anti-Speed] Failed to find HumanoidRootPart for", player.Name)
			return 
		end

		-- Initialize player data
		playerData[player.UserId] = {
			lastPosition = rootPart.Position,
			lastCheckTime = tick(),
			teleportCooldown = 0,
			violations = 0,
			wasAirborne = false
		}

		print("[Anti-Speed] Character setup complete for:", player.Name)
	end

	if player.Character then
		setupCharacter(player.Character)
	end

	player.CharacterAdded:Connect(setupCharacter)
end

-- Function to check player movement
local function checkPlayerMovement(player)
	local data = playerData[player.UserId]
	if not data then return end

	-- Check if on teleport cooldown
	if tick() < data.teleportCooldown then return end

	local char, rootPart, humanoid = getCharacterAndRoot(player)
	if not char or not rootPart or not humanoid then return end

	-- Check if player has TP bypass enabled
	local canTP = char:GetAttribute("can_tp")
	if canTP == true then
		-- Update position but don't check for violations
		data.lastPosition = rootPart.Position
		data.lastCheckTime = tick()
		return
	end

	local currentTime = tick()
	local timeDelta = currentTime - data.lastCheckTime

	-- Only check if enough time has passed
	if timeDelta >= CHECK_INTERVAL then
		-- Get character-specific limits
		local walkSpeed = char:GetAttribute("studs_second") or humanoid.WalkSpeed or 16
		local jumpPower = char:GetAttribute("jump_power") or humanoid.JumpPower or 50
		local maxDistances = calculateMaxDistances(walkSpeed, jumpPower)

		local currentPos = rootPart.Position
		local lastPos = data.lastPosition

		-- Calculate distances
		local totalDistance = (currentPos - lastPos).Magnitude
		local horizontalDelta = Vector3.new(currentPos.X - lastPos.X, 0, currentPos.Z - lastPos.Z)
		local horizontalDistance = horizontalDelta.Magnitude
		local verticalDistance = math.abs(currentPos.Y - lastPos.Y)
		local verticalDelta = currentPos.Y - lastPos.Y

		local airborne = isAirborne(humanoid)
		local isFalling = verticalDelta < -1 -- Falling significantly

		local violated = false
		local violationType = ""

		-- Check based on movement state
		if isFalling then
			-- When falling, allow large Y movement but restrict horizontal
			if horizontalDistance > maxDistances.fallHorizontal then
				violated = true
				violationType = "Horizontal speed while falling"
			end
		elseif airborne or data.wasAirborne then
			-- When airborne (jumping), use 3D distance with jump tolerance
			if totalDistance > maxDistances.airborne then
				violated = true
				violationType = "Airborne speed"
			end
		else
			-- On ground, check horizontal distance only
			if horizontalDistance > maxDistances.ground then
				violated = true
				violationType = "Ground speed"
			end
		end

		-- Handle violation
		if violated then
			data.violations = data.violations + 1

			warn(string.format(
				"[Anti-Speed] VIOLATION: %s for %s | Total: %.2f | Horizontal: %.2f | Vertical: %.2f | Time: %.3f s | Allowed: %.2f | Violations: %d",
				violationType,
				player.Name,
				totalDistance,
				horizontalDistance,
				verticalDistance,
				timeDelta,
				isFalling and maxDistances.fallHorizontal or (airborne and maxDistances.airborne or maxDistances.ground),
				data.violations
				))

			-- Teleport player back to last safe position
			rootPart.CFrame = CFrame.new(data.lastPosition)

			-- Set cooldown to prevent rapid teleports
			data.teleportCooldown = tick() + 0.2 -- Reduced cooldown for faster interval

			-- Notify player
			notifyPlayer(player, "You moved too fast or teleported, either your internet is unstable or you're using a third party script/software; please turn it off, or wait for your wifi to get stable.")

			-- Kick after multiple violations (adjusted for faster checking)
			if data.violations >= 10 then
				warn("[Anti-Speed] Kicking player for repeated violations:", player.Name)
				player:Kick("Classic Anti-Cheat: (2x"..player.UserId..") You have been kicked for too many violations on suspicion of speed hacking. If you believe this is your lag, then rejoin or wait for it to get stable.")
			end
		else
			-- Movement was legitimate, update last position
			data.lastPosition = currentPos
			data.lastCheckTime = currentTime
			data.wasAirborne = airborne
		end
	end
end

-- Initialize existing players
for _, player in ipairs(Players:GetPlayers()) do
	initializePlayer(player)
end

-- Handle new players
Players.PlayerAdded:Connect(initializePlayer)

-- Handle player removal
Players.PlayerRemoving:Connect(function(player)
	playerData[player.UserId] = nil
	print("[Anti-Speed] Removed data for:", player.Name)
end)

-- Main check loop
RunService.Heartbeat:Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local success, err = pcall(function()
			checkPlayerMovement(player)
		end)

		if not success then
			warn("[Anti-Speed] Error checking player", player.Name, ":", err)
		end
	end
end)

print("[Anti-Speed] Script initialized successfully!")
print(string.format("[Anti-Speed] Check interval: %.1f seconds (%.0f checks/sec)", CHECK_INTERVAL, 1/CHECK_INTERVAL))
print(string.format("[Anti-Speed] Leniency: %d studs", LENIENCY))
