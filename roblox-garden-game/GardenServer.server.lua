-- GardenServer (Script)
-- Put this in: ServerScriptService
-- Name it: GardenServer
--
-- Builds the map (gardens, seed shop, sell stand), and runs all game logic:
-- planting, growing, harvesting, selling, the seed shop, weather events,
-- saving, and Robux purchases.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage:WaitForChild("GardenConfig"))

---------------------------------------------------------------------------
-- DataStore (saving). Works in a published game, or in Studio when
-- "Enable Studio Access to API Services" is turned on.
---------------------------------------------------------------------------
local store = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("GardenData_v1")
	end)
	if ok then
		store = result
	else
		warn("[Garden] DataStore unavailable, progress will not save: " .. tostring(result))
	end
end

---------------------------------------------------------------------------
-- Remotes (created here so you don't have to make them by hand)
---------------------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "GardenRemotes"

local function makeRemote(name)
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotes
	return remote
end

local StateUpdate = makeRemote("StateUpdate") -- server -> client: coins, seeds, backpack
local ShopUpdate = makeRemote("ShopUpdate") -- server -> client: shop stock + restock timer
local Notify = makeRemote("Notify") -- server -> client: popup message
local EventUpdate = makeRemote("EventUpdate") -- server -> client: weather event started/ended
local OpenShop = makeRemote("OpenShop") -- server -> client: open the seed shop window
local RequestState = makeRemote("RequestState") -- client -> server: send me everything
local BuySeed = makeRemote("BuySeed") -- client -> server
local SelectSeed = makeRemote("SelectSeed") -- client -> server
local ExpandGarden = makeRemote("ExpandGarden") -- client -> server
local TeleportTo = makeRemote("TeleportTo") -- client -> server

remotes.Parent = ReplicatedStorage

---------------------------------------------------------------------------
-- Player state
---------------------------------------------------------------------------
local Data = {} -- [player] = saved data table
local CanSave = {} -- [player] = true if data loaded correctly
local PlotOf = {} -- [player] = plot record
local Selected = {} -- [player] = selected seed name
local Bought = {} -- [player] = { [seedName] = amount bought this restock }
local HasDoubleCoins = {} -- [player] = true if they own the gamepass

local ShopStock = {} -- [seedName] = amount in stock this restock
local NextRestock = 0

local CurrentEvent = nil
local EventEndsAt = 0

local function notify(player, text, color)
	Notify:FireClient(player, text, color)
end

local function notifyAll(text, color)
	Notify:FireAllClients(text, color)
end

---------------------------------------------------------------------------
-- World building
---------------------------------------------------------------------------
local SOIL_COLOR = Color3.fromRGB(105, 70, 45)
local LOCKED_COLOR = Color3.fromRGB(90, 90, 90)
local WOOD_COLOR = Color3.fromRGB(150, 105, 65)
local LEAF_COLOR = Color3.fromRGB(60, 170, 60)

local world = Instance.new("Folder")
world.Name = "GardenWorld"
world.Parent = workspace

local function makePart(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		p[key] = value
	end
	p.Parent = parent
	return p
end

local function makeBillboard(adornee, text, color, studsOffset, size)
	local gui = Instance.new("BillboardGui")
	gui.Size = size or UDim2.fromScale(14, 3)
	gui.StudsOffset = studsOffset or Vector3.new(0, 8, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Adornee = adornee
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = adornee
	return gui, label
end

-- Grass field on top of the baseplate
makePart({
	Name = "Field",
	Size = Vector3.new(420, 1, 340),
	Position = Vector3.new(0, -0.45, 0),
	Material = Enum.Material.Grass,
	Color = Color3.fromRGB(100, 175, 75),
}, world)

-- Gardens: 6 plots, 3 on each side of the center path
local PLOT_POSITIONS = {
	Vector3.new(-80, 0, -65),
	Vector3.new(0, 0, -65),
	Vector3.new(80, 0, -65),
	Vector3.new(-80, 0, 65),
	Vector3.new(0, 0, 65),
	Vector3.new(80, 0, 65),
}

local Plots = {}
local onTileClicked -- defined further down

for plotIndex, pos in ipairs(PLOT_POSITIONS) do
	local zDir = pos.Z < 0 and 1 or -1 -- direction toward the center path

	local model = Instance.new("Model")
	model.Name = "Plot" .. plotIndex
	model.Parent = world

	makePart({
		Name = "Base",
		Size = Vector3.new(70, 1, 50),
		Position = pos + Vector3.new(0, 0.1, 0),
		Material = Enum.Material.Grass,
		Color = Color3.fromRGB(80, 150, 60),
	}, model)

	-- Fence-ish border
	for _, info in ipairs({
		{ Vector3.new(70, 1.5, 1), Vector3.new(0, 1.3, 25) },
		{ Vector3.new(70, 1.5, 1), Vector3.new(0, 1.3, -25) },
		{ Vector3.new(1, 1.5, 50), Vector3.new(35, 1.3, 0) },
		{ Vector3.new(1, 1.5, 50), Vector3.new(-35, 1.3, 0) },
	}) do
		makePart({
			Name = "Border",
			Size = info[1],
			Position = pos + info[2],
			Material = Enum.Material.WoodPlanks,
			Color = WOOD_COLOR,
			CanCollide = false,
		}, model)
	end

	-- Sign facing the center path
	local signPos = pos + Vector3.new(0, 5, zDir * 28)
	local sign = makePart({
		Name = "Sign",
		Size = Vector3.new(18, 4, 0.6),
		CFrame = CFrame.lookAt(signPos, signPos + Vector3.new(0, 0, zDir)),
		Material = Enum.Material.WoodPlanks,
		Color = WOOD_COLOR,
	}, model)
	makePart({
		Name = "SignPost",
		Size = Vector3.new(1, 3, 1),
		Position = signPos - Vector3.new(0, 3.5, 0),
		Material = Enum.Material.Wood,
		Color = WOOD_COLOR,
	}, model)
	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Front
	signGui.LightInfluence = 0
	signGui.Parent = sign
	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.fromScale(1, 1)
	signLabel.BackgroundTransparency = 1
	signLabel.Font = Enum.Font.FredokaOne
	signLabel.TextScaled = true
	signLabel.TextColor3 = Color3.new(1, 1, 1)
	signLabel.TextStrokeTransparency = 0
	signLabel.Text = "Empty Garden"
	signLabel.Parent = signGui

	-- Soil tiles: 6 columns x 4 rows. Row 1 is closest to the path, so
	-- expansions unlock rows further back.
	local tiles = {}
	local index = 0
	for row = 1, 4 do
		for col = 1, 6 do
			index += 1
			local tileIndex = index
			local tileModel = Instance.new("Model")
			tileModel.Name = "Tile" .. tileIndex
			tileModel.Parent = model

			local soil = makePart({
				Name = "Soil",
				Size = Vector3.new(8, 1, 8),
				Position = pos + Vector3.new((col - 3.5) * 10, 0.8, zDir * (2.5 - row) * 10),
				Material = Enum.Material.Ground,
				Color = SOIL_COLOR,
			}, tileModel)

			local click = Instance.new("ClickDetector")
			click.MaxActivationDistance = 80
			click.Parent = tileModel
			click.MouseClick:Connect(function(player)
				onTileClicked(plotIndex, tileIndex, player)
			end)

			local gui, label = makeBillboard(soil, "", Color3.new(1, 1, 1), Vector3.new(0, 7, 0), UDim2.fromScale(8, 2.4))
			gui.Enabled = false
			gui.MaxDistance = 70

			tiles[tileIndex] = {
				Index = tileIndex,
				Model = tileModel,
				Soil = soil,
				Gui = gui,
				Label = label,
				Visual = nil,
				Stage = nil,
				Seed = nil,
			}
		end
	end

	local spawnPos = pos + Vector3.new(0, 4, zDir * 22)
	Plots[plotIndex] = {
		Index = plotIndex,
		Owner = nil,
		Tiles = tiles,
		SignLabel = signLabel,
		SpawnCFrame = CFrame.lookAt(spawnPos, Vector3.new(pos.X, spawnPos.Y, pos.Z)),
	}
end

-- Market stands in the middle of the map
local function buildStand(name, pos, roofColor, title, actionText)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = world

	local counter = makePart({
		Name = "Counter",
		Size = Vector3.new(14, 4, 4),
		Position = pos + Vector3.new(0, 2, 0),
		Material = Enum.Material.WoodPlanks,
		Color = WOOD_COLOR,
	}, model)
	for _, x in ipairs({ -6.5, 6.5 }) do
		makePart({
			Name = "Post",
			Size = Vector3.new(1, 10, 1),
			Position = pos + Vector3.new(x, 5, -1.5),
			Material = Enum.Material.Wood,
			Color = WOOD_COLOR,
		}, model)
	end
	local roof = makePart({
		Name = "Roof",
		Size = Vector3.new(16, 1, 8),
		Position = pos + Vector3.new(0, 10.5, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = roofColor,
	}, model)
	makeBillboard(roof, title, Color3.new(1, 1, 1), Vector3.new(0, 4, 0), UDim2.fromScale(16, 4))

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = title
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter

	-- where players get teleported to (in front of the counter, facing it)
	local standPos = pos + Vector3.new(0, 4, 0)
	local front = Vector3.new(0, 0, pos.Z >= 0 and 8 or -8)
	return prompt, CFrame.lookAt(standPos + front, standPos)
end

local shopPrompt, ShopCFrame = buildStand("SeedShop", Vector3.new(-30, 0, 0), Color3.fromRGB(70, 190, 90), "SEED SHOP", "Open Shop")
local sellPrompt, SellCFrame = buildStand("SellStand", Vector3.new(30, 0, 0), Color3.fromRGB(240, 180, 40), "SELL FRUIT", "Sell All")

---------------------------------------------------------------------------
-- Saving / loading
---------------------------------------------------------------------------
local function defaultData()
	return {
		Coins = Config.StartingCoins,
		Seeds = table.clone(Config.StartingSeeds),
		Fruits = {},
		Plants = {}, -- ["tileIndex"] = { s = seedName, p = startTime, r = readyTime, g = alreadyGrown }
		Tiles = Config.StartTiles,
	}
end

local function loadData(player)
	if not store then
		return defaultData(), false
	end
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return store:GetAsync("player_" .. player.UserId)
		end)
		if ok then
			local data = type(result) == "table" and result or defaultData()
			for key, value in pairs(defaultData()) do
				if data[key] == nil then
					data[key] = value
				end
			end
			return data, true
		end
		warn("[Garden] Load failed (attempt " .. attempt .. "): " .. tostring(result))
		task.wait(2)
	end
	return defaultData(), false
end

local function saveData(player)
	local data = Data[player]
	if not (store and data and CanSave[player]) then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync("player_" .. player.UserId, data)
	end)
	if not ok then
		warn("[Garden] Save failed for " .. player.Name .. ": " .. tostring(err))
	end
end

---------------------------------------------------------------------------
-- State syncing
---------------------------------------------------------------------------
local function expansionCost(data)
	local step = math.floor((data.Tiles - Config.StartTiles) / Config.TilesPerExpansion) + 1
	if data.Tiles >= Config.MaxTiles then
		return nil
	end
	return Config.ExpansionCosts[step]
end

local function pushState(player)
	local data = Data[player]
	if not data then
		return
	end
	local worth = 0
	for _, fruit in ipairs(data.Fruits) do
		worth += fruit.v
	end
	if HasDoubleCoins[player] then
		worth *= 2
	end
	StateUpdate:FireClient(player, {
		Coins = data.Coins,
		Seeds = data.Seeds,
		FruitCount = #data.Fruits,
		FruitWorth = worth,
		Selected = Selected[player],
		Tiles = data.Tiles,
		ExpandCost = expansionCost(data),
		DoubleCoins = HasDoubleCoins[player] == true,
	})
end

local function pushShop(player)
	local bought = Bought[player] or {}
	local stock = {}
	for _, seed in ipairs(Config.Seeds) do
		stock[seed.Name] = math.max(0, (ShopStock[seed.Name] or 0) - (bought[seed.Name] or 0))
	end
	ShopUpdate:FireClient(player, stock, math.max(0, NextRestock - os.time()))
end

local function pushEvent(player)
	if CurrentEvent then
		EventUpdate:FireClient(player, CurrentEvent.Name, CurrentEvent.Message, EventEndsAt - os.time())
	else
		EventUpdate:FireClient(player, nil)
	end
end

local function addCoins(player, amount)
	local data = Data[player]
	if not data then
		return
	end
	data.Coins = math.max(0, data.Coins + amount)
	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild("Coins")
	if coins then
		coins.Value = data.Coins
	end
end

---------------------------------------------------------------------------
-- Plants
---------------------------------------------------------------------------
local function clearVisual(tile)
	if tile.Visual then
		tile.Visual:Destroy()
	end
	tile.Visual = nil
	tile.Stage = nil
	tile.Seed = nil
end

-- stage 0-3 = growing (bigger each stage), 4 = ready with fruit
local function buildVisual(tile, seed, stage)
	clearVisual(tile)
	local visual = Instance.new("Model")
	visual.Name = "Plant"

	local base = tile.Soil.Position + Vector3.new(0, 0.5, 0)
	local height = 1 + math.min(stage, 3) * 1.3

	makePart({
		Name = "Stem",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, 0.5, 0.5),
		CFrame = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.SmoothPlastic,
		Color = LEAF_COLOR,
		CanCollide = false,
	}, visual)

	local leafSize = 1 + math.min(stage, 3) * 0.6
	for i = 0, 1 do
		makePart({
			Name = "Leaf",
			Size = Vector3.new(leafSize * 1.6, 0.2, leafSize * 0.8),
			CFrame = CFrame.new(base + Vector3.new(0, height * 0.7, 0))
				* CFrame.Angles(0, math.rad(90 * i + 45), math.rad(20)),
			Material = Enum.Material.SmoothPlastic,
			Color = LEAF_COLOR,
			CanCollide = false,
		}, visual)
	end

	if stage >= 4 then
		local count = seed.FruitCount
		for i = 1, count do
			local angle = (i / count) * math.pi * 2
			local radius = count > 1 and 1.3 or 0
			local fruitPos = base
				+ Vector3.new(math.cos(angle) * radius, height + seed.FruitSize / 2 - 0.3, math.sin(angle) * radius)
			local fruit = makePart({
				Name = "Fruit",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(seed.FruitSize, seed.FruitSize, seed.FruitSize),
				Position = fruitPos,
				Material = Enum.Material.SmoothPlastic,
				Color = seed.Color,
				CanCollide = false,
			}, visual)
			if i == 1 then
				local sparkle = Instance.new("Sparkles")
				sparkle.SparkleColor = seed.Color
				sparkle.Parent = fruit
			end
		end
	end

	visual.Parent = tile.Model
	tile.Visual = visual
	tile.Stage = stage
	tile.Seed = seed.Name
end

local function refreshTile(tile, data, now)
	local plant = data and data.Plants[tostring(tile.Index)]
	local seed = plant and Config.SeedsByName[plant.s]
	if not seed then
		if tile.Visual then
			clearVisual(tile)
		end
		tile.Gui.Enabled = false
		return
	end

	local remaining = plant.r - now
	local stage
	if remaining <= 0 then
		stage = 4
	elseif plant.g then
		stage = 3 -- already-grown plant regrowing its fruit
	else
		local total = math.max(1, plant.r - plant.p)
		stage = math.clamp(math.floor((now - plant.p) / total * 4), 0, 3)
	end

	if tile.Stage ~= stage or tile.Seed ~= seed.Name then
		buildVisual(tile, seed, stage)
	end

	tile.Gui.Enabled = true
	if remaining <= 0 then
		tile.Label.Text = seed.Name .. "\nREADY!"
		tile.Label.TextColor3 = Color3.fromRGB(120, 255, 120)
	else
		tile.Label.Text = seed.Name .. "\n" .. Config.FormatTime(remaining)
		tile.Label.TextColor3 = Color3.new(1, 1, 1)
	end
end

local function refreshPlot(plot)
	local data = plot.Owner and Data[plot.Owner]
	local now = os.time()
	for _, tile in ipairs(plot.Tiles) do
		local locked = data ~= nil and tile.Index > data.Tiles
		tile.Soil.Color = locked and LOCKED_COLOR or SOIL_COLOR
		tile.Soil.Material = locked and Enum.Material.Slate or Enum.Material.Ground
		refreshTile(tile, data, now)
	end
end

local function rollMutation()
	for _, mutation in ipairs(Config.Mutations) do
		if math.random() < mutation.Chance then
			return mutation.Name, mutation.Multiplier
		end
	end
	if CurrentEvent and math.random() < CurrentEvent.Chance then
		return CurrentEvent.Mutation, CurrentEvent.Multiplier
	end
	return nil, 1
end

local function harvest(player, data, tile, plant, seed)
	if #data.Fruits >= Config.MaxFruits then
		notify(player, "Your backpack is full! Go sell your fruit.", Color3.fromRGB(255, 120, 120))
		return
	end

	local now = os.time()
	local huge = math.random() < Config.HugeChance
	local sizeMult = huge and (2 + math.random() * 2) or (0.8 + math.random() * 0.6)
	local mutation, mult = rollMutation()
	local value = math.floor(seed.Value * sizeMult * mult + 0.5)
	local weight = math.floor(seed.Weight * sizeMult * 100 + 0.5) / 100

	table.insert(data.Fruits, { n = seed.Name, w = weight, m = mutation, v = value })

	if seed.Regrow then
		plant.p = now
		plant.r = now + seed.Regrow
		plant.g = true
	else
		data.Plants[tostring(tile.Index)] = nil
	end

	local fullName = (huge and "Huge " or "") .. (mutation and (mutation .. " ") or "") .. seed.Name
	local color = mutation and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(150, 255, 150)
	notify(player, "+ " .. fullName .. " (" .. weight .. "kg) worth " .. Config.Format(value), color)

	if mutation == "Rainbow" or (huge and mutation) then
		notifyAll(player.DisplayName .. " harvested a " .. fullName .. "!", Color3.fromRGB(255, 120, 255))
	end

	refreshTile(tile, data, now)
	pushState(player)
end

onTileClicked = function(plotIndex, tileIndex, player)
	local plot = Plots[plotIndex]
	local data = Data[player]
	if not data then
		return
	end
	if plot.Owner ~= player then
		notify(player, "This isn't your garden!", Color3.fromRGB(255, 120, 120))
		return
	end
	if tileIndex > data.Tiles then
		notify(player, "Expand your garden to unlock this soil!", Color3.fromRGB(255, 200, 120))
		return
	end

	local tile = plot.Tiles[tileIndex]
	local key = tostring(tileIndex)
	local now = os.time()
	local plant = data.Plants[key]

	if plant then
		local seed = Config.SeedsByName[plant.s]
		if not seed then
			data.Plants[key] = nil
			refreshTile(tile, data, now)
			return
		end
		if now >= plant.r then
			harvest(player, data, tile, plant, seed)
		else
			notify(player, seed.Name .. " will be ready in " .. Config.FormatTime(plant.r - now))
		end
		return
	end

	local seedName = Selected[player]
	if not seedName then
		notify(player, "Pick a seed from your hotbar first!", Color3.fromRGB(255, 200, 120))
		return
	end
	local owned = data.Seeds[seedName] or 0
	local seed = Config.SeedsByName[seedName]
	if owned <= 0 or not seed then
		Selected[player] = nil
		notify(player, "You're out of " .. seedName .. " seeds! Buy more at the Seed Shop.", Color3.fromRGB(255, 200, 120))
		pushState(player)
		return
	end

	owned -= 1
	data.Seeds[seedName] = owned > 0 and owned or nil
	if owned <= 0 then
		Selected[player] = nil
	end
	data.Plants[key] = { s = seedName, p = now, r = now + seed.GrowTime }

	refreshTile(tile, data, now)
	pushState(player)
end

---------------------------------------------------------------------------
-- Seed shop
---------------------------------------------------------------------------
local function restock(byName)
	local rare = {}
	for _, seed in ipairs(Config.Seeds) do
		if math.random() <= seed.StockChance then
			ShopStock[seed.Name] = math.random(seed.StockMin, seed.StockMax)
			if Config.AnnounceRarities[seed.Rarity] then
				table.insert(rare, seed.Name)
			end
		else
			ShopStock[seed.Name] = 0
		end
	end
	NextRestock = os.time() + Config.RestockInterval

	for _, player in ipairs(Players:GetPlayers()) do
		Bought[player] = {}
		pushShop(player)
	end

	if byName then
		notifyAll(byName .. " restocked the Seed Shop for everyone!", Color3.fromRGB(120, 255, 120))
	else
		notifyAll("The Seed Shop has restocked!", Color3.fromRGB(120, 255, 120))
	end
	for _, name in ipairs(rare) do
		notifyAll(name .. " is in stock at the Seed Shop!", Config.RarityColors[Config.SeedsByName[name].Rarity])
	end
end

BuySeed.OnServerEvent:Connect(function(player, seedName)
	if typeof(seedName) ~= "string" then
		return
	end
	local seed = Config.SeedsByName[seedName]
	local data = Data[player]
	local bought = Bought[player]
	if not (seed and data and bought) then
		return
	end
	local left = (ShopStock[seedName] or 0) - (bought[seedName] or 0)
	if left <= 0 then
		notify(player, seedName .. " is out of stock! Wait for the restock.", Color3.fromRGB(255, 120, 120))
		return
	end
	if data.Coins < seed.Price then
		notify(player, "Not enough coins!", Color3.fromRGB(255, 120, 120))
		return
	end
	addCoins(player, -seed.Price)
	bought[seedName] = (bought[seedName] or 0) + 1
	data.Seeds[seedName] = (data.Seeds[seedName] or 0) + 1
	if not Selected[player] then
		Selected[player] = seedName
	end
	pushShop(player)
	pushState(player)
end)

shopPrompt.Triggered:Connect(function(player)
	pushShop(player)
	OpenShop:FireClient(player)
end)

---------------------------------------------------------------------------
-- Selling
---------------------------------------------------------------------------
local function sellAll(player)
	local data = Data[player]
	if not data then
		return
	end
	local count = #data.Fruits
	if count == 0 then
		notify(player, "You have no fruit to sell! Harvest your plants first.", Color3.fromRGB(255, 200, 120))
		return
	end
	local total = 0
	for _, fruit in ipairs(data.Fruits) do
		total += fruit.v
	end
	if HasDoubleCoins[player] then
		total *= 2
	end
	data.Fruits = {}
	addCoins(player, total)
	notify(player, "Sold " .. count .. " fruit for " .. Config.Format(total) .. " coins!", Color3.fromRGB(255, 215, 0))
	pushState(player)
end

sellPrompt.Triggered:Connect(sellAll)

---------------------------------------------------------------------------
-- Other client requests
---------------------------------------------------------------------------
SelectSeed.OnServerEvent:Connect(function(player, seedName)
	if seedName == nil then
		Selected[player] = nil
	elseif typeof(seedName) == "string" and Config.SeedsByName[seedName] then
		Selected[player] = seedName
	end
	pushState(player)
end)

ExpandGarden.OnServerEvent:Connect(function(player)
	local data = Data[player]
	if not data then
		return
	end
	local cost = expansionCost(data)
	if not cost then
		notify(player, "Your garden is already fully expanded!")
		return
	end
	if data.Coins < cost then
		notify(player, "You need " .. Config.Format(cost) .. " coins to expand!", Color3.fromRGB(255, 120, 120))
		return
	end
	addCoins(player, -cost)
	data.Tiles = math.min(data.Tiles + Config.TilesPerExpansion, Config.MaxTiles)
	if PlotOf[player] then
		refreshPlot(PlotOf[player])
	end
	notify(player, "Garden expanded! You now have " .. data.Tiles .. " soil tiles.", Color3.fromRGB(120, 255, 120))
	pushState(player)
end)

local lastTeleport = {}
TeleportTo.OnServerEvent:Connect(function(player, where)
	if lastTeleport[player] and os.clock() - lastTeleport[player] < 1 then
		return
	end
	lastTeleport[player] = os.clock()
	local character = player.Character
	if not (character and character:FindFirstChild("HumanoidRootPart")) then
		return
	end
	local target
	if where == "Garden" and PlotOf[player] then
		target = PlotOf[player].SpawnCFrame
	elseif where == "Shop" then
		target = ShopCFrame
	elseif where == "Sell" then
		target = SellCFrame
	end
	if target then
		character:PivotTo(target)
	end
end)

RequestState.OnServerEvent:Connect(function(player)
	if Data[player] then
		pushState(player)
		pushShop(player)
		pushEvent(player)
	end
end)

---------------------------------------------------------------------------
-- Robux purchases
---------------------------------------------------------------------------
MarketplaceService.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not (player and Data[player]) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if info.ProductId == Config.Products.RestockShop.Id then
		restock(player.DisplayName)
	elseif info.ProductId == Config.Products.CoinPack.Id then
		addCoins(player, Config.Products.CoinPack.Amount)
		notify(player, "+" .. Config.Format(Config.Products.CoinPack.Amount) .. " coins! Thanks for the support!", Color3.fromRGB(255, 215, 0))
		pushState(player)
	else
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	saveData(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if purchased and passId == Config.GamePasses.DoubleCoins and passId ~= 0 then
		HasDoubleCoins[player] = true
		notify(player, "2x Coins unlocked! All fruit now sells for double.", Color3.fromRGB(255, 215, 0))
		pushState(player)
	end
end)

---------------------------------------------------------------------------
-- Players joining / leaving
---------------------------------------------------------------------------
local function teleportToPlot(player, character)
	local plot = PlotOf[player]
	if not plot then
		return
	end
	character:WaitForChild("HumanoidRootPart", 10)
	task.wait(0.1)
	if character.Parent then
		character:PivotTo(plot.SpawnCFrame)
	end
end

local function onPlayerAdded(player)
	local data, ok = loadData(player)
	if not player.Parent then
		return -- left while loading
	end

	-- find a free garden
	local plot = nil
	for _, candidate in ipairs(Plots) do
		if not candidate.Owner then
			plot = candidate
			break
		end
	end
	if not plot then
		player:Kick("This server is full. Please join another server!")
		return
	end

	Data[player] = data
	CanSave[player] = ok
	Bought[player] = {}
	PlotOf[player] = plot
	plot.Owner = player
	plot.SignLabel.Text = player.DisplayName .. "'s Garden"

	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local coins = Instance.new("NumberValue")
	coins.Name = "Coins"
	coins.Value = data.Coins
	coins.Parent = stats
	stats.Parent = player

	if Config.GamePasses.DoubleCoins ~= 0 then
		local owns, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, Config.GamePasses.DoubleCoins)
		end)
		HasDoubleCoins[player] = owns and result == true
	end

	-- pick a seed for them so they can start planting right away
	for _, seed in ipairs(Config.Seeds) do
		if (data.Seeds[seed.Name] or 0) > 0 then
			Selected[player] = seed.Name
			break
		end
	end

	refreshPlot(plot)

	player.CharacterAdded:Connect(function(character)
		teleportToPlot(player, character)
	end)
	if player.Character then
		task.spawn(teleportToPlot, player, player.Character)
	end

	pushState(player)
	pushShop(player)
	pushEvent(player)

	-- welcome messages
	local now = os.time()
	local ready = 0
	for _, plant in pairs(data.Plants) do
		if plant.r <= now then
			ready += 1
		end
	end
	task.delay(2, function()
		if not player.Parent then
			return
		end
		if not ok and store then
			notify(player, "Couldn't load your save. Progress this session won't be saved, please rejoin.", Color3.fromRGB(255, 80, 80))
		end
		if ready > 0 then
			notify(player, "Welcome back! " .. ready .. " plants grew while you were away!", Color3.fromRGB(120, 255, 120))
		elseif next(data.Plants) == nil then
			notify(player, "Pick a seed in your hotbar, then click the soil in your garden to plant it!", Color3.fromRGB(150, 220, 255))
		end
	end)
end

local function onPlayerRemoving(player)
	saveData(player)
	local plot = PlotOf[player]
	if plot then
		plot.Owner = nil
		plot.SignLabel.Text = "Empty Garden"
	end
	Data[player] = nil
	CanSave[player] = nil
	PlotOf[player] = nil
	Selected[player] = nil
	Bought[player] = nil
	HasDoubleCoins[player] = nil
	lastTeleport[player] = nil
	if plot then
		refreshPlot(plot)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

game:BindToClose(function()
	local pending = 0
	for _, player in ipairs(Players:GetPlayers()) do
		pending += 1
		task.spawn(function()
			saveData(player)
			pending -= 1
		end)
	end
	local started = os.clock()
	while pending > 0 and os.clock() - started < 25 do
		task.wait(0.1)
	end
end)

---------------------------------------------------------------------------
-- Loops
---------------------------------------------------------------------------
-- First restock (nobody is online yet, so no announcement spam)
for _, seed in ipairs(Config.Seeds) do
	ShopStock[seed.Name] = math.random() <= seed.StockChance and math.random(seed.StockMin, seed.StockMax) or 0
end
NextRestock = os.time() + Config.RestockInterval

-- Growth + restock timer
task.spawn(function()
	while true do
		local now = os.time()
		if now >= NextRestock then
			restock(nil)
		end
		for _, plot in ipairs(Plots) do
			if plot.Owner and Data[plot.Owner] then
				local data = Data[plot.Owner]
				for _, tile in ipairs(plot.Tiles) do
					refreshTile(tile, data, now)
				end
			end
		end
		task.wait(1)
	end
end)

-- Weather events
task.spawn(function()
	local normalClock = Lighting.ClockTime
	local normalAmbient = Lighting.OutdoorAmbient
	while true do
		task.wait(Config.EventInterval)
		local event = Config.Events[math.random(1, #Config.Events)]
		CurrentEvent = event
		EventEndsAt = os.time() + Config.EventDuration
		Lighting.ClockTime = event.ClockTime
		Lighting.OutdoorAmbient = event.Ambient
		EventUpdate:FireAllClients(event.Name, event.Message, Config.EventDuration)

		task.wait(Config.EventDuration)
		CurrentEvent = nil
		Lighting.ClockTime = normalClock
		Lighting.OutdoorAmbient = normalAmbient
		EventUpdate:FireAllClients(nil)
		notifyAll("The " .. event.Name .. " has ended.")
	end
end)

-- Autosave
task.spawn(function()
	while true do
		task.wait(Config.AutosaveInterval)
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(saveData, player)
		end
	end
end)
