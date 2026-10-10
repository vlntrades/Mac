-- GardenConfig (ModuleScript)
-- Put this in: ReplicatedStorage
-- Name it exactly: GardenConfig
--
-- This is the "settings" file for the whole game. Change prices, grow times,
-- seeds, events and Robux products here. You don't need to touch the other
-- scripts to balance the game.

local Config = {}

---------------------------------------------------------------------------
-- Economy / progression
---------------------------------------------------------------------------
Config.StartingCoins = 20
Config.StartingSeeds = { Carrot = 3 }

Config.RestockInterval = 300 -- seconds between seed shop restocks (5 minutes)
Config.MaxFruits = 300 -- backpack size

Config.StartTiles = 12 -- soil tiles unlocked for new players
Config.TilesPerExpansion = 6 -- tiles unlocked per expansion
Config.MaxTiles = 24 -- total tiles on a plot (do not raise above 24)
Config.ExpansionCosts = { 2500, 75000 } -- cost of each expansion, in order

Config.AutosaveInterval = 120 -- seconds

---------------------------------------------------------------------------
-- Seeds
--   Price       = cost of one seed in the shop
--   GrowTime    = seconds until the first harvest
--   Regrow      = seconds between harvests (nil = plant disappears after harvest)
--   Value       = base coins per harvested fruit
--   Weight      = base fruit weight in kg (just for show)
--   StockChance = chance (0-1) the seed shows up on a restock
--   StockMin/Max= how many are in stock when it shows up
--   FruitCount  = how many fruit balls show on the plant when ready
--   FruitSize   = size of each fruit ball (studs)
---------------------------------------------------------------------------
Config.Seeds = {
	{
		Name = "Carrot", Rarity = "Common", Price = 10, GrowTime = 10, Regrow = nil,
		Value = 22, Weight = 0.25, Color = Color3.fromRGB(255, 140, 30),
		StockChance = 1, StockMin = 10, StockMax = 25, FruitCount = 1, FruitSize = 1.2,
	},
	{
		Name = "Strawberry", Rarity = "Common", Price = 50, GrowTime = 30, Regrow = 20,
		Value = 15, Weight = 0.05, Color = Color3.fromRGB(230, 30, 60),
		StockChance = 0.9, StockMin = 5, StockMax = 15, FruitCount = 4, FruitSize = 0.8,
	},
	{
		Name = "Blueberry", Rarity = "Uncommon", Price = 400, GrowTime = 45, Regrow = 25,
		Value = 40, Weight = 0.02, Color = Color3.fromRGB(60, 80, 220),
		StockChance = 0.75, StockMin = 3, StockMax = 10, FruitCount = 5, FruitSize = 0.6,
	},
	{
		Name = "Tomato", Rarity = "Uncommon", Price = 1200, GrowTime = 60, Regrow = 30,
		Value = 110, Weight = 0.3, Color = Color3.fromRGB(240, 50, 40),
		StockChance = 0.6, StockMin = 2, StockMax = 8, FruitCount = 3, FruitSize = 1.1,
	},
	{
		Name = "Pumpkin", Rarity = "Rare", Price = 3000, GrowTime = 120, Regrow = nil,
		Value = 6000, Weight = 8, Color = Color3.fromRGB(255, 120, 0),
		StockChance = 0.45, StockMin = 1, StockMax = 5, FruitCount = 1, FruitSize = 3,
	},
	{
		Name = "Corn", Rarity = "Rare", Price = 8000, GrowTime = 90, Regrow = 40,
		Value = 600, Weight = 0.5, Color = Color3.fromRGB(255, 220, 50),
		StockChance = 0.35, StockMin = 1, StockMax = 4, FruitCount = 2, FruitSize = 1.3,
	},
	{
		Name = "Watermelon", Rarity = "Epic", Price = 20000, GrowTime = 300, Regrow = nil,
		Value = 45000, Weight = 12, Color = Color3.fromRGB(40, 170, 60),
		StockChance = 0.25, StockMin = 1, StockMax = 3, FruitCount = 1, FruitSize = 3.5,
	},
	{
		Name = "Mango", Rarity = "Epic", Price = 60000, GrowTime = 180, Regrow = 60,
		Value = 3500, Weight = 0.4, Color = Color3.fromRGB(255, 170, 40),
		StockChance = 0.15, StockMin = 1, StockMax = 2, FruitCount = 3, FruitSize = 1.2,
	},
	{
		Name = "Dragon Fruit", Rarity = "Legendary", Price = 200000, GrowTime = 300, Regrow = 90,
		Value = 12000, Weight = 0.6, Color = Color3.fromRGB(255, 60, 170),
		StockChance = 0.08, StockMin = 1, StockMax = 2, FruitCount = 3, FruitSize = 1.4,
	},
	{
		Name = "Starfruit", Rarity = "Mythic", Price = 1000000, GrowTime = 600, Regrow = 120,
		Value = 50000, Weight = 0.3, Color = Color3.fromRGB(255, 240, 90),
		StockChance = 0.03, StockMin = 1, StockMax = 1, FruitCount = 4, FruitSize = 1.2,
	},
}

Config.SeedsByName = {}
for order, seed in ipairs(Config.Seeds) do
	seed.Order = order
	Config.SeedsByName[seed.Name] = seed
end

Config.RarityColors = {
	Common = Color3.fromRGB(200, 200, 200),
	Uncommon = Color3.fromRGB(90, 220, 90),
	Rare = Color3.fromRGB(70, 150, 255),
	Epic = Color3.fromRGB(180, 90, 255),
	Legendary = Color3.fromRGB(255, 190, 40),
	Mythic = Color3.fromRGB(255, 70, 110),
}

-- Rarities that get a server-wide "X is in stock!" announcement
Config.AnnounceRarities = { Legendary = true, Mythic = true }

---------------------------------------------------------------------------
-- Mutations (rolled on every harvest, multiply the fruit's value)
---------------------------------------------------------------------------
Config.Mutations = {
	{ Name = "Rainbow", Multiplier = 50, Chance = 0.001, Color = Color3.fromRGB(255, 120, 255) },
	{ Name = "Gold", Multiplier = 20, Chance = 0.01, Color = Color3.fromRGB(255, 215, 0) },
}

-- Chance a harvested fruit is "Huge" (2x-4x size and value)
Config.HugeChance = 0.02

---------------------------------------------------------------------------
-- Weather events: a random one starts every EventInterval seconds and lasts
-- EventDuration seconds. While active, every harvest has `Chance` to get the
-- event's mutation.
---------------------------------------------------------------------------
Config.EventInterval = 480
Config.EventDuration = 120

Config.Events = {
	{
		Name = "Rain", Mutation = "Wet", Multiplier = 2, Chance = 0.3,
		Message = "It's raining! Harvests can become Wet (x2)",
		Color = Color3.fromRGB(90, 150, 255), ClockTime = 17.5,
		Ambient = Color3.fromRGB(90, 100, 130),
	},
	{
		Name = "Frost", Mutation = "Frozen", Multiplier = 4, Chance = 0.15,
		Message = "A frost rolls in! Harvests can become Frozen (x4)",
		Color = Color3.fromRGB(170, 230, 255), ClockTime = 8,
		Ambient = Color3.fromRGB(150, 190, 230),
	},
	{
		Name = "Blood Moon", Mutation = "Bloodlit", Multiplier = 6, Chance = 0.1,
		Message = "The Blood Moon rises! Harvests can become Bloodlit (x6)",
		Color = Color3.fromRGB(255, 60, 60), ClockTime = 0,
		Ambient = Color3.fromRGB(150, 30, 30),
	},
}

---------------------------------------------------------------------------
-- Robux (optional). Create these on the Creator Dashboard and paste the IDs.
-- Leave an ID at 0 to hide that button.
---------------------------------------------------------------------------
Config.GamePasses = {
	DoubleCoins = 0, -- Game Pass: sell fruit for 2x coins
}

Config.Products = {
	RestockShop = { Id = 0 }, -- Developer Product: restock the seed shop for the whole server
	CoinPack = { Id = 0, Amount = 25000 }, -- Developer Product: instant coins
}

---------------------------------------------------------------------------
-- Helpers used by both scripts
---------------------------------------------------------------------------
local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

function Config.Format(n)
	n = math.floor(n)
	if n < 1000 then
		return tostring(n)
	end
	local i = 1
	local v = n
	while v >= 1000 and i < #SUFFIXES do
		v = v / 1000
		i += 1
	end
	return string.format("%.1f%s", v, SUFFIXES[i])
end

function Config.FormatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

return Config
