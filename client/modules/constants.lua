local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Queue = get_machina_module("modules/queue.lua")

local Constants = {}

Constants.INTEGRITY_KICK_MESSAGE = "[ MACHINA ANTI-BAN SYSTEM ]\nFailed to verify integrity of scripts, contact 2dsgirl08 or disable `verifyIntegrityOfScripts` in `config.json` (not recommended).\n%s: %s"
Constants.MINE_QUEUE = {}
Constants.VALUABLE_TIERS = {"supernatural", "mythic", "surreal", "master", "rare", "uncommon"}
Constants.MINE_QUEUE_ORDER = {
	"supernatural",
	"mythic",
	"surreal",
	"master",
	"rare",
	"uncommon",
	"common",
	"layer"
}

for _, tier in Constants.MINE_QUEUE_ORDER do
	Constants.MINE_QUEUE[tier] = Queue.new()
end

Constants.Worlds = {"natura", "lucernia", "luna_refuge", "aesteria", "caverna"}
Constants.GameInformation = ReplicatedStorage.Modules:FindFirstChild("GameInformation") and require(ReplicatedStorage.Modules.GameInformation) or {}
Constants.GameConstants = ReplicatedStorage.Modules:FindFirstChild("GameInformation") and require(ReplicatedStorage.Modules.GameInformation.GameConstants) or {}
Constants.Regions = {}
Constants.BaseOres = {}
Constants.SellableOres = {}
Constants.MiningDirections = {Vector2.new(0, 1), Vector2.new(0, -1), Vector2.new(1, 0), Vector2.new(-1, 0)}
Constants.AbilityTable = {}
Constants.NotableItems = {
	"miners_mallet",
	"stone_ravager",
	"speed_coil",
	"big_slammer",
	"core_frag",
	"sugarcoated_candycrusher",
	"poison_pick",
	"matterbomb",
	"blazuine_molotov",
	"accretium_fireball",
	"luminatite_lantern",
	"erodimium_bomb",
	"lustrous_ribbon",
	"57_leaf_clover",
	"trinity_claymore",
	"cybernetium_radar",
	"t1_terraformer",
	"coronal_carpetbomb",
	"soul_scythe",
	"moon_scepter",
	"obliveracy_obliterator",
	"elementonic",
	"vitriol_vigor",
	"prism_of_chaos",
	"shimmering_starsearcher",
	"rgb_c4",
	"vaporwave_vaporizer",
	"lucidium_locator",
	"cube_collector",
	"subspace_tripmine",
}
Constants.mainHandOrder = {
	"illuminyx_illuminator",
	"elementonic",
	"vitriol_vigor",
	"candilium_candle",
	"ambrosia_salad",
	"lustrous_ribbon",
	"acceleratium_coil",
	"winged_coil",
	"frost_coil",
	"thundarian_coil",
	"speed_coil",
	"jump_coil"
}
Constants.offHandOrder = {
	"subspace_tripmine",
	"phantasm_lantern",
	"the_inktorb",
	"cube_collector",
	"heartbreaker",
	"freeze_frag",
	"rgb_c4",
	"obliveracy_obliterator",
	"paradise_parasol",
	"t1_terraformer",
	"coronal_carpetbomb",
	"polarium_tunneler",
	"soundstrocity_subwoofer",
	"erodimium_bomb",
	"shattering_heart",
	"luminatite_lantern",
	"witches_brew",
	"spiral_striker",
	"coal_smokebomb",
	"accretium_fireball",
	"blazuine_molotov",
	"matterbomb",
	"lutetium_superball",
	"temporum_timebomb",
	"sugarcoated_candycrusher",
	"core_frag"
}

for ore, data in Constants.GameInformation.ores do
	if table.find(MACHINA_CONFIG.autoSell.blacklist, ore) then
		continue
	end

	if data.tier.tierNum < 6 then
		continue
	end

	table.insert(Constants.SellableOres, ore)
end

for _, name in Constants.NotableItems do
	local item = Constants.GameInformation.pickaxes[name] or Constants.GameInformation.gears[name]
	
	if not item then
		continue
	end
	
	for ore, _ in item.recipe.normal do
		table.remove(Constants.SellableOres, table.find(Constants.SellableOres, ore))
	end

	for ore, _ in item.recipe.ionized do
		table.remove(Constants.SellableOres, table.find(Constants.SellableOres, ore))
	end
end

for _, world in Constants.Worlds do
	for region, data in Constants.GameInformation.regions[world] do
		Constants.Regions[region] = data
		table.insert(Constants.BaseOres, data.baseOre)
	end
end

for _, object in getgc() do
	if type(object) ~= "function" then
		continue
	end

	local info = debug.getinfo(object)

	if info.name == "processManualPickaxeInput" then
		Constants.AbilityTable = debug.getupvalues(object)[3]
		print("Got ability table")
	end

	if info.name == "genericManualUpdate" then
		Constants.GenericManualUpdate = object
		print("Got GenericManualUpdate function")
	end

	if info.name == "abilityTriggerVerificationCheck" then
		hookfunction(object, function()
			return true
		end)
	end
end

return Constants
