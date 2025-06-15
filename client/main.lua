local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local SocketModule = get_machina_module("modules/socket.lua")

local Player = Players.LocalPlayer
local Socket = SocketModule.connect("ws://" .. MACHINA_HOST .. ":" .. MACHINA_WEBSOCKET_PORT)
local GameInfo = ReplicatedStorage.Modules:FindFirstChild("GameInformation") and require(ReplicatedStorage.Modules.GameInformation) or {}

local tasks = {}

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

		table.insert(tasks, task)

		Socket:send({packet = "success"})
	end
end)

-- while true do task.wait(1);
-- 	if tasks[1] then
-- 		print(game:GetService("HttpService"):JSONEncode(tasks[1]))
-- 	end
-- end