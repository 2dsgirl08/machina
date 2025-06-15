local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")

local SocketModule = get_machina_module("modules/socket.lua")
local Queue = get_machina_module("modules/queue.lua")

local Player = Players.LocalPlayer
local Socket = SocketModule.connect("ws://" .. MACHINA_HOST .. ":" .. MACHINA_WEBSOCKET_PORT)
local GameInfo = ReplicatedStorage.Modules:FindFirstChild("GameInformation") and require(ReplicatedStorage.Modules.GameInformation) or {}

local tasks = Queue.new()
local currentTask = nil

Socket:send({
	packet = "identify",
	username = Player.Name
})

Socket.onMessage:Connect(function(packet)
	if packet.packet == "retrieve_game_information" then
		Socket:send({
			packet = "retrieve_game_information",
			data = GameInfo
		})
	end

	if packet.packet == "grind" then
		local task = {
			type = packet.type,
			goal = packet.goal
		}

		Queue:put(task)
		Socket:send({packet = "success"})
	end

	if packet.packet == "cancel" then
		currentTask = nil
		Socket:send({packet = "success"})
	end
end)

while true do task.wait();
	if not currentTask then
		currentTask = tasks:get()
		continue
	end

	if currentTask.type == "recipe" then
		
	end
end