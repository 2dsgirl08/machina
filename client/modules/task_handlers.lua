local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Constants = get_machina_module("modules/constants.lua")
local Signal = get_machina_module("modules/signal.lua")

local Player = Players.LocalPlayer

local TaskHandlers = {}
local CurrentTasks = {}

function TaskHandlers.cancel()
	TaskHandlers.mine(false); CurrentTasks = {}
end

function TaskHandlers.getWorld()
	for worldName, id in Constants.GameInformation.worldsToPlaceIds do
		if id == game.PlaceId then
			return worldName
		end
	end
end

function TaskHandlers.getGotOreSignal()
	local signal = Signal.new()

	for _, variant in {"normal", "ionized", "spectral"} do
		for _, ore in Player.PlayerGui.InventoryUI.InventoryWrapper.Inventory.Contents[variant]:GetChildren() do
			if not ore:FindFirstChild("Count") then
				continue
			end

			ore.Count.Changed:Connect(function()
				signal:Fire(ore.Name)
			end)
		end
	end

	return signal
end

function TaskHandlers.travelToSurface(humanoid, origin)
	local taskId = HttpService:GenerateGUID()
	CurrentTasks[taskId] = true

	local path = PathfindingService:CreatePath()
	path:ComputeAsync(origin, Vector3.new(math.random(-2, 2) * 6, 20006, math.random(-2, 2) * 6))

	if path.Status ~= Enum.PathStatus.Success then
		return false
	end

	for _, waypoint in path:GetWaypoints() do
		local startedMoving = os.clock()
		local completed = false

		humanoid:MoveTo(waypoint.Position)

		task.spawn(function()
			humanoid.MoveToFinished:Wait()
			completed = true
		end)

		while not completed and os.clock() - startedMoving < 1 do
			task.wait()
		end

		if not completed or not CurrentTasks[taskId] then
			return false
		end
	end

	return true
end

function TaskHandlers.getOptimalWorldOrderFromExclusives(goal)
	local order = {}
	local worldData = {}

	for ore, amount in goal.normal do
		local data = Constants.GameInformation.ores[ore]

		if data.tier.tierNum ~= 1 then
			continue
		end
		
		for world, _ in data.spawnInfo.locations do
			if not worldData[world] then
				worldData[world] = {world = world, ores = {}, value = 0}
				table.insert(order, worldData[world])
			end
			
			worldData[world].ores[ore] = amount
		end
	end

	table.sort(order, function(a, b)
		return a.value > b.value
	end)

	return order
end

function TaskHandlers.getOptimalLayerOrder(goal)
	local layers = {}
	local accountedOres = {}

	for region, data in Constants.Regions do
		local tbl = {layer = region, ores = {}, buffer = 0}

		for ore, _ in data.ores do
			if goal.normal[ore] or goal.ionized[ore] then
				table.insert(tbl.ores, ore)
			end
		end

		if #tbl.ores > 0 then
			table.insert(layers, tbl)
		end
	end
	
	table.sort(layers, function(a, b)
		return #a.ores > #b.ores
	end)

	local layersToRemove = {}
	local layerOrder = {}

	for _, layer in layers do
		for _, ore in layer.ores do
			if table.find(accountedOres, ore) then
				layer.buffer -= 1

				if #layer.ores + layer.buffer <= 0 then
					table.insert(layersToRemove, layer)
					break
				end
			end

			table.insert(accountedOres, ore)
		end
	end

	for _, layer in layers do
		if table.find(layersToRemove, layer) then
			continue
		end

		table.insert(layerOrder, layer.layer)
	end

	return layerOrder
end

function TaskHandlers.getLayerToMineIn(goal)
	for _, layer in TaskHandlers.getOptimalLayerOrder(goal) do
		if TaskHandlers.hasCompletedLayer(layer, goal) then
			continue
		end
		
		return layer
	end
end

function TaskHandlers.getWorldToMineIn(goal)
	for _, world in TaskHandlers.getOptimalWorldOrderFromExclusives(goal) do
		for ore, amt in world.ores do
			if TaskHandlers.getOreAmount(ore).normal < amt then
				return world.world
			end
		end
	end
end

function TaskHandlers.getLayersFromWorld(world)
	local layers = {}

	for region, _ in Constants.GameInformation.regions[world] do
		table.insert(layers, region)
	end

	return layers
end

function TaskHandlers.getOreAmount(ore)
	local data = {}

	for _, variant in {"normal", "ionized", "spectral"} do
		local amount = string.gsub(Player.PlayerGui.InventoryUI.InventoryWrapper.Inventory.Contents[variant][ore].Count.Text, ",", "")
		data[variant] = tonumber(amount)
	end

	return data
end

function TaskHandlers.hasCompletedLayer(layer, goal)
	for ore, _ in Constants.Regions[layer].ores do
		local amount = TaskHandlers.getOreAmount(ore)

		if goal.normal[ore] and goal.normal[ore] > amount.normal then
			return false
		end

		if goal.ionized[ore] and goal.ionized[ore] > amount.ionized then
			return false
		end
	end

	return true
end

function TaskHandlers.equipTool(humanoid, tool)
	if not tool then
		return
	end

	humanoid:UnequipTools(); task.wait()
	humanoid:EquipTool(tool)
end

function TaskHandlers.getOre(origin, direction)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {workspace.Mine}
	raycastParams.FilterType = Enum.RaycastFilterType.Include

	local ray = workspace:Raycast(origin, direction * 1000, raycastParams)

	return ray and ray.Instance or nil
end

function TaskHandlers.getOreInQueue()
	for _, tier in Constants.MINE_QUEUE_ORDER do
		local ore = nil

		if table.find(Constants.VALUABLE_TIERS, tier) then
			ore = Constants.MINE_QUEUE[tier]:peek()

			if ore then
				task.spawn(function()
					while ore.Parent do
						task.wait()
					end

					Constants.MINE_QUEUE[tier]:get()
				end)
			end
		else
			ore = Constants.MINE_QUEUE[tier]:get()
		end

		if ore then
			return ore
		end
	end
end

function TaskHandlers.inMine(position)
	return position.Y < 20000
end

function TaskHandlers.mine(origin, direction, forceOre)
	if not origin then
		ReplicatedStorage.Remotes.SetDirectionalRaycast:FireServer(false)
	else
		local ore = forceOre or TaskHandlers.getOreInQueue() or TaskHandlers.getOre(origin, direction)
		ReplicatedStorage.Remotes.SetDirectionalRaycast:FireServer(ore, origin, direction)
	end
end

function TaskHandlers.getLayerIn(position)
	for layer, _ in Constants.GameInformation.regions[TaskHandlers.getWorld()] do
		if math.abs(Constants.Regions[layer].centroid.Y - position.Y) <= 2600 then
			return layer
		end
	end
end

function TaskHandlers.getWorldFromLayer(layer)
	for _, world in Constants.Worlds do
		for l, _ in Constants.GameInformation.regions[world] do
			if l == layer then
				return world
			end
		end
	end
end

function TaskHandlers.teleportToSurface()
	local Character = Player.Character

	if not Character then
		return
	end

	Character:PivotTo(Constants.GameConstants.surfaceTeleportPositions[TaskHandlers.getWorld()])
end

function TaskHandlers.getMoney()
	local count = string.gsub(string.sub(Player.PlayerGui.TopBar.TopBar.Cash.Text.Text, 2), ",", "")
	return tonumber(count)
end

function TaskHandlers.isGoalCompleted(goal)
	for ore, amount in goal.normal do
		if TaskHandlers.getOreAmount(ore).normal < amount then
			return false
		end
	end

	for ore, amount in goal.ionized do
		if TaskHandlers.getOreAmount(ore).ionized < amount then
			return false
		end
	end

	return true
end

function TaskHandlers.getToLayer(layer)
	local taskId = HttpService:GenerateGUID()

	CurrentTasks[taskId] = true

	local Character = Player.Character
	local Humanoid = Character:FindFirstChild("Humanoid")
	local HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart")

	local yLevel = Constants.Regions[layer].centroid.Y

	if TaskHandlers.getLayerIn(HumanoidRootPart.Position) == layer then
		return
	end

	if TaskHandlers.getWorld() ~= "luna_refuge" and TaskHandlers.getMoney() > 15 and yLevel < 14000 then
		return ReplicatedStorage.Remotes.GenerateTP:FireServer(layer) and task.wait(3)
	end

	if HumanoidRootPart.Position.Y < yLevel or not TaskHandlers.inMine(HumanoidRootPart.Position) then
		TaskHandlers.teleportToSurface()
		TaskHandlers.travelToSurface(Humanoid, HumanoidRootPart.Position)
		TaskHandlers.mine(HumanoidRootPart.Position, Vector3.new(0, -1, 0))
		task.wait(1)
	end

	while TaskHandlers.getLayerIn(HumanoidRootPart.Position) ~= layer and CurrentTasks[taskId] do task.wait(1);
		if not TaskHandlers.inMine(HumanoidRootPart.Position) then
			return false
		end

		Humanoid:MoveTo(Vector3.new(
			math.floor(HumanoidRootPart.Position.X / 6 + 0.5) * 6,
			0,
			math.floor(HumanoidRootPart.Position.Z / 6 + 0.5) * 6
		))

		TaskHandlers.mine(HumanoidRootPart.Position, Vector3.new(0, -1, 0))
	end

	CurrentTasks[taskId] = false
end

return TaskHandlers