local Players = game:GetService("Players")
local Player = Players.LocalPlayer

return {
	getScript = function()
		return Player.Backpack:FindFirstChild("PickaxeClientScript", true) or Player.Character:FindFirstChild("PickaxeClientScript", true)
	end,
	hashes = {"d23a648c", "489f3688"}
}