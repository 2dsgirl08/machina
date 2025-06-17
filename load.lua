-- Make sure these are identical to the ones in `config.json`.
getgenv().MACHINA_WEBSOCKET_PORT = 8765
getgenv().MACHINA_WEBSERVER_PORT = 8766

-- Do not edit below, unless you know what you're doing.

local HttpService = game:GetService("HttpService")
local ModuleCache = {}

local function try(addresses)
	for _, address in addresses do
		local success, result = pcall(request, {Url = "http://" .. address .. ":" .. MACHINA_WEBSERVER_PORT, Method = "GET"})

		if success and result and result.Success then
			getgenv().MACHINA_HOST = address
			return HttpService:JSONDecode(result.Body)
		end
	end
end

local response = try({"127.0.0.1", "10.0.2.2"})

if not response then
	error("Failed to connect to Machina.", 0)
end

getgenv().MACHINA_PATH = response.path
getgenv().MACHINA_CONFIG = response.config

get_machina_module = function(path)
	if ModuleCache[path] then
		return ModuleCache[path]
	end

	local parts = {}

	for part in string.gmatch(path, "[^/]+") do
		table.insert(parts, part)
	end

	local node = MACHINA_PATH

	for _, part in parts do
		if node.children then
			node = node.children[part]
		else
			node = node[part]
		end

		if not node then
			error("File not found: " .. path)
		end
	end

	if node.type ~= "file" then
		error("Path is a directory: " .. path)
	end

	local module = loadstring(node.contents)()
	ModuleCache[path] = module

	return module
end

if not MACHINA_CONFIG.debug then
	getgenv().print = function() end
end

getgenv().MACHINA_INSTANCE = HttpService:GenerateGUID(); task.wait(1)
loadstring(MACHINA_PATH["main.lua"].contents)()