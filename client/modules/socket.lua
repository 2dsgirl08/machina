local HttpService = game:GetService("HttpService")
local Signal = get_machina_module("modules/signal.lua")

local Socket = {}
Socket.__index = Socket

function Socket.connect(address)
	local self = setmetatable({}, Socket)

	self.address = address
	self.socket = WebSocket.connect(address)
	self.onMessage = Signal.new()

	self.socket.OnMessage:Connect(function(message)
		self.onMessage:Fire(HttpService:JSONDecode(message))
	end)

	return self
end

function Socket:send(data)
	return self.socket:Send(HttpService:JSONEncode(data))
end

function Socket:invoke(data)
	local response = self.socket:Send(data) and self.onMessage:Wait()
	return response
end

function Socket:disconnect()
	self.socket:Close()
end

return Socket