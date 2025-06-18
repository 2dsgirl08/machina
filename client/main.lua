local Self = MACHINA_INSTANCE

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local SocketModule = get_machina_module("modules/socket.lua")
local Queue = get_machina_module("modules/queue.lua")
local SHA1 = get_machina_module("modules/sha1.lua")
local Constants = get_machina_module("modules/constants.lua")
local TaskHandlers = get_machina_module("modules/task_handlers.lua")

local Socket = SocketModule.connect("ws://" .. MACHINA_HOST .. ":" .. MACHINA_WEBSOCKET_PORT)
local GameInfo = Constants.GameInformation

local Player = Players.LocalPlayer
local Mine = workspace:FindFirstChild("Mine")
local World = TaskHandlers.getWorld()
local WorldLayers = TaskHandlers.getLayersFromWorld(World)

local tasks = Queue.new()
local currentTask = nil

local miningDirections = {}

if MACHINA_CONFIG["verifyIntegrityOfScripts"] then
	for _, scriptName in {"PickaxeClientScript"} do
		local data = get_machina_module("integrity/" .. scriptName .. ".lua")
		local script = data.getScript(); print(script, script.ClassName)
		local scriptHash = script and SHA1(getscriptbytecode(script)):sub(1, 8)

		if not script or table.find(data.hashes, scriptHash) then
			return Player:Kick(Constants.INTEGRITY_KICK_MESSAGE:format(scriptName, scriptHash))
		end
	end
end

local function teleportToWorld(worldName)
	Socket:send({
		packet = "preserveTasks",
		data = {
			queue = tasks:tableize(),
			current = currentTask
		}
	})

	local message = Instance.new("Message")
	message.Parent = workspace
	message.Text = "Teleporting to " .. worldName .. "..."

	queue_on_teleport(`task.wait(10) loadstring(game:HttpGet("https://raw.githubusercontent.com/2dsgirl08/machina/refs/heads/main/load.lua"))()`)
	ReplicatedStorage.Remotes.TeleportToSubPlace:InvokeServer(Constants.GameInformation.worldsToPlaceIds[worldName], "ToReservedSelf")
end

local function equipGearsIfNone(override)
	local Character = Player.Character
	local Humanoid = Character and Character:FindFirstChild("Humanoid")

	if not Humanoid or (Character:FindFirstChild("Handle") and not override) then
		return
	end

	for _, item in Constants.mainHandOrder do
		local tool = Player.Backpack:FindFirstChild(item)

		if not tool then
			continue
		end

		TaskHandlers.equipTool(Humanoid, tool)
		tool:Activate()

		break
	end

	for _, item in Constants.offHandOrder do
		local tool = Player.Backpack:FindFirstChild(item)

		if not tool then
			continue
		end

		TaskHandlers.equipTool(Humanoid, tool)
		tool:Activate()

		break
	end
end

Socket.onMessage:Connect(function(packet)
	print(packet.packet)

	if packet.packet == "identified" then
		while Self == MACHINA_INSTANCE do task.wait(1.5);
			Socket:send({packet = "heartbeat"})
		end
	end

	if packet.packet == "retrieve_game_information" then
		Socket:send({
			packet = "retrieve_game_information",
			data = GameInfo
		})
	end

	if packet.packet == "preserveTasks" then
		for _, task in packet.data.queue do
			tasks:put(task)
		end

		currentTask = packet.data.current
	end

	if packet.packet == "grind" then
		local task = {
			type = packet.type,
			item_type = packet.item_type,
			item_name = packet.item_name,
			goal = packet.goal,
			layerOrder = TaskHandlers.getOptimalLayerOrder(packet.goal)
		}

		Socket:send({packet = "grind", status = currentTask and "queued" or "running"})
		tasks:put(task)
	end

	if packet.packet == "cancel" then
		currentTask = nil; TaskHandlers.cancel(currentTask)
	end
end)

Socket:send({
	packet = "identify",
	username = Player.Name
})

local mineResetListener = ReplicatedStorage.Remotes.MineStates.MineRegenerated.OnClientEvent:Connect(function()
	miningDirections = {}
end)

local gotOreListener = TaskHandlers.getGotOreSignal():Connect(function(ore)
	if not MACHINA_CONFIG.autoSell.enabled then
		return
	end
	
	if table.find(MACHINA_CONFIG.autoSell.blacklist, ore) or table.find(MACHINA_CONFIG.autoSell.blacklist, Constants.GameInformation.ores[ore].name) then
		return
	end

	if not table.find(Constants.SellableOres, ore) then
		return
	end

	if Constants.GameInformation.ores[ore].tier.tierNum > 8 then
		return
	end

	if Random.new():NextNumber(0, 1) < MACHINA_CONFIG.autoSell.rate then
		return
	end

	ReplicatedStorage.Remotes.SellOre:FireServer(ore, 1)
end)

local oreAddedListener = Mine.ChildAdded:Connect(function(ore)
	if not GameInfo.ores[ore.Name] then
		return
	end

	if not currentTask then
		return
	end

	local oreData = GameInfo.ores[ore.Name]

	if not oreData or not oreData.tier then
		return
	end

	local tier = ore.Name == "tripmine" and "supernatural" or Constants.MINE_QUEUE_ORDER[math.max(9 - oreData.tier.tierNum, 1)]

	if (tier == "layer") and not currentTask.goal.normal[ore.Name] and not currentTask.goal.ionized[ore.Name] then
		return
	end

	if table.find(Constants.BaseOres, ore.Name) then
		return
	end

	Constants.MINE_QUEUE[tier]:put(ore)
end)

local playerIdledListener = Player.Idled:Connect(function()
	VirtualInputManager:SendMouseButtonEvent(0, 0, 1, true, game, 0)
	VirtualInputManager:SendMouseButtonEvent(0, 0, 1, false, game, 0)
end)

local __namecall; __namecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
	if checkcaller() or Self ~= MACHINA_INSTANCE then
		return __namecall(self, ...)
	end

	if getnamecallmethod() == "FireServer" and self == ReplicatedStorage.Remotes.SetDirectionalRaycast and currentTask and currentTask.type == "grind" then
		return
	end

	return __namecall(self, ...)
end))

task.spawn(function()
	while Self == MACHINA_INSTANCE do
		task.wait()
	end

	Socket:disconnect()
	TaskHandlers.cancel()
	oreAddedListener:Disconnect()
	gotOreListener:Disconnect()
	playerIdledListener:Disconnect()
end)

while Self == MACHINA_INSTANCE do task.wait();
	if not currentTask then
		currentTask = tasks:get()
		continue
	end

	local Task = currentTask

	local Character = Player.Character
	local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
	local Humanoid = Character and Character:FindFirstChild("Humanoid")

	if not Humanoid or not HumanoidRootPart then
		return
	end

	if Task.type == "grind" then
		equipGearsIfNone()

		if not Character:FindFirstChild("Pickaxe") then
			TaskHandlers.equipTool(Humanoid, Player.Backpack:FindFirstChild("Pickaxe"))
		end

		ReplicatedStorage.Remotes.ChangePin:FireServer(string.lower(Task.item_type) .. "s", Task.item_name)

		local completed = false

		while Self == MACHINA_INSTANCE and Task == currentTask do task.wait();
			local world = TaskHandlers.getWorldToMineIn(Task.goal)
			local layer = TaskHandlers.getLayerToMineIn(Task.goal, Task.layerOrder)
			local overrideLayerCompletionCheck = false

			if TaskHandlers.isGoalCompleted(Task.goal) then
				currentTask = nil
				completed = true
				break
			end

			if not layer then
				overrideLayerCompletionCheck = true
				layer = TaskHandlers.getLayersFromWorld(world)[1]
			end

			if World ~= TaskHandlers.getWorldFromLayer(layer) then
				teleportToWorld(TaskHandlers.getWorldFromLayer(layer))
				task.wait(999)
			end

			local miningDirection = Constants.MiningDirections[math.random(1, #Constants.MiningDirections)]

			if not miningDirections[layer] or #miningDirections[layer] > 3 then
				miningDirections[layer] = {}
			end

			while table.find(miningDirections[layer], miningDirection) do
				miningDirection = Constants.MiningDirections[math.random(1, #Constants.MiningDirections)]
			end

			table.insert(miningDirections[layer], miningDirection)

			local lastCompletionCheck = os.clock()

			while Self == MACHINA_INSTANCE and Task == currentTask do task.wait();
				if os.clock() - lastCompletionCheck > 5 then
					lastCompletionCheck = os.clock()

					if TaskHandlers.getLayerToMineIn(Task.goal, Task.layerOrder) ~= layer and not overrideLayerCompletionCheck then
						break
					end

					if overrideLayerCompletionCheck and TaskHandlers.isGoalCompleted(Task.goal) then
						break
					end
				end

				if TaskHandlers.getLayerIn(HumanoidRootPart.Position) ~= layer then
					TaskHandlers.getToLayer(layer)
				end

				TaskHandlers.mine(HumanoidRootPart.Position, Vector3.new(miningDirection.X, MACHINA_CONFIG.miningDirectionY, miningDirection.Y).Unit)
				Humanoid:MoveTo(HumanoidRootPart.Position + Vector3.new(miningDirection.X, 0, miningDirection.Y) * 30)
			end
		end

		if completed and ReplicatedStorage.Remotes.PurchaseItem:InvokeServer(Task.item_type:sub(1, 1):upper() .. Task.item_type:sub(2):lower(), Task.item_name) then
			ReplicatedStorage.Remotes.EquipItem:InvokeServer(Task.item_type:sub(1, 1):upper() .. Task.item_type:sub(2):lower(), Task.item_name)
			equipGearsIfNone(true)
		else
			print("Failed", completed, Task.item_type:sub(1, 1):upper() .. Task.item_type:sub(2):lower(), Task.item_name)
		end
	end
end