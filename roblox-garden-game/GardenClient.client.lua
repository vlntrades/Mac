-- GardenClient (LocalScript)
-- Put this in: StarterPlayer > StarterPlayerScripts
-- Name it: GardenClient
--
-- Builds the whole on-screen UI: coins, backpack, seed hotbar, menu buttons,
-- the seed shop window, popup messages and the weather event banner.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("GardenConfig"))
local remotes = ReplicatedStorage:WaitForChild("GardenRemotes")

local StateUpdate = remotes:WaitForChild("StateUpdate")
local ShopUpdate = remotes:WaitForChild("ShopUpdate")
local Notify = remotes:WaitForChild("Notify")
local EventUpdate = remotes:WaitForChild("EventUpdate")
local OpenShop = remotes:WaitForChild("OpenShop")
local RequestState = remotes:WaitForChild("RequestState")
local BuySeed = remotes:WaitForChild("BuySeed")
local SelectSeed = remotes:WaitForChild("SelectSeed")
local ExpandGarden = remotes:WaitForChild("ExpandGarden")
local TeleportTo = remotes:WaitForChild("TeleportTo")

local FONT = Enum.Font.FredokaOne
local PANEL = Color3.fromRGB(30, 35, 45)
local GREEN = Color3.fromRGB(70, 190, 90)
local GOLD = Color3.fromRGB(255, 200, 40)
local RED = Color3.fromRGB(200, 70, 70)
local GREY = Color3.fromRGB(90, 90, 100)
local WHITE = Color3.new(1, 1, 1)

local state = {
	Coins = 0,
	Seeds = {},
	FruitCount = 0,
	FruitWorth = 0,
	Selected = nil,
	ExpandCost = nil,
	DoubleCoins = false,
}
local shopStock = {}
local restockDeadline = os.clock()
local eventDeadline = nil

---------------------------------------------------------------------------
-- UI helpers
---------------------------------------------------------------------------
local function new(className, props, children)
	local inst = Instance.new(className)
	for key, value in pairs(props or {}) do
		if key ~= "Parent" then
			inst[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius or 10) })
end

local function stroke(color, thickness)
	return new("UIStroke", {
		Color = color or Color3.new(0, 0, 0),
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

-- Like new("TextLabel") but with game defaults. MaxTextSize caps the scaled text.
local function label(props)
	local maxTextSize = props.MaxTextSize or 28
	props.MaxTextSize = nil
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or WHITE
	props.TextScaled = true
	local textLabel = new("TextLabel", props)
	new("UITextSizeConstraint", { MaxTextSize = maxTextSize, Parent = textLabel })
	return textLabel
end

local function button(props, onClick)
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or WHITE
	props.TextScaled = true
	props.AutoButtonColor = true
	local btn = new("TextButton", props, { corner(10), stroke(Color3.new(0, 0, 0), 2) })
	new("UITextSizeConstraint", { MaxTextSize = 22, Parent = btn })
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		Parent = btn,
	})
	if onClick then
		btn.Activated:Connect(onClick)
	end
	return btn
end

---------------------------------------------------------------------------
-- Screen
---------------------------------------------------------------------------
local gui = new("ScreenGui", {
	Name = "GardenUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

-- Coins
local coinsFrame = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.fromOffset(240, 46),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.15,
	Parent = gui,
}, { corner(12), stroke(GOLD, 2) })
local coinsLabel = label({
	Size = UDim2.new(1, -16, 1, -8),
	Position = UDim2.fromOffset(8, 4),
	Text = "💰 0",
	TextColor3 = GOLD,
	Parent = coinsFrame,
})

-- Backpack
local backpackLabel = label({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 60),
	Size = UDim2.fromOffset(340, 24),
	Text = "🎒 0/" .. Config.MaxFruits,
	MaxTextSize = 20,
	TextStrokeTransparency = 0.3,
	Parent = gui,
})

-- Weather event banner
local eventBanner = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 90),
	Size = UDim2.new(0.9, 0, 0, 34),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.1,
	Visible = false,
	Parent = gui,
}, { corner(10), new("UISizeConstraint", { MaxSize = Vector2.new(520, 34) }) })
local eventStroke = stroke(WHITE, 2)
eventStroke.Parent = eventBanner
local eventLabel = label({
	Size = UDim2.new(1, -12, 1, -6),
	Position = UDim2.fromOffset(6, 3),
	Text = "",
	MaxTextSize = 20,
	Parent = eventBanner,
})
local eventMessage = ""

-- Popup messages
local toastHolder = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 130),
	Size = UDim2.new(0.9, 0, 0, 200),
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	new("UISizeConstraint", { MaxSize = Vector2.new(520, 200) }),
	new("UIListLayout", {
		Padding = UDim.new(0, 4),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
local toastCount = 0

local function toast(text, color)
	toastCount += 1
	local item = label({
		Size = UDim2.new(1, 0, 0, 28),
		Text = text,
		TextColor3 = color or WHITE,
		TextStrokeTransparency = 0,
		MaxTextSize = 22,
		LayoutOrder = toastCount,
		Parent = toastHolder,
	})
	-- keep at most 5 on screen
	local items = {}
	for _, child in ipairs(toastHolder:GetChildren()) do
		if child:IsA("TextLabel") then
			table.insert(items, child)
		end
	end
	table.sort(items, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #items - 5 do
		items[i]:Destroy()
	end
	task.delay(3.5, function()
		if item.Parent then
			local tween = TweenService:Create(item, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 })
			tween:Play()
			tween.Completed:Wait()
			item:Destroy()
		end
	end)
end

---------------------------------------------------------------------------
-- Seed shop window
---------------------------------------------------------------------------
local shopFrame = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.9, 0.75),
	BackgroundColor3 = PANEL,
	Visible = false,
	ZIndex = 5,
	Parent = gui,
}, { corner(16), stroke(GREEN, 3), new("UISizeConstraint", { MaxSize = Vector2.new(480, 580) }) })

label({
	Position = UDim2.fromOffset(16, 8),
	Size = UDim2.new(1, -80, 0, 34),
	Text = "🌱 Seed Shop",
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 6,
	Parent = shopFrame,
})
local restockLabel = label({
	Position = UDim2.fromOffset(16, 42),
	Size = UDim2.new(1, -32, 0, 22),
	Text = "Restock in 5:00",
	TextColor3 = Color3.fromRGB(180, 230, 180),
	TextXAlignment = Enum.TextXAlignment.Left,
	MaxTextSize = 18,
	ZIndex = 6,
	Parent = shopFrame,
})
button({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 10),
	Size = UDim2.fromOffset(40, 40),
	Text = "X",
	BackgroundColor3 = RED,
	ZIndex = 6,
	Parent = shopFrame,
}, function()
	shopFrame.Visible = false
end)

local listTop = 70
if Config.Products.RestockShop.Id ~= 0 then
	button({
		Position = UDim2.fromOffset(16, 70),
		Size = UDim2.new(1, -32, 0, 36),
		Text = "⚡ Restock now for everyone (Robux)",
		BackgroundColor3 = Color3.fromRGB(0, 140, 220),
		ZIndex = 6,
		Parent = shopFrame,
	}, function()
		MarketplaceService:PromptProductPurchase(player, Config.Products.RestockShop.Id)
	end)
	listTop = 112
end

local shopList = new("ScrollingFrame", {
	Position = UDim2.fromOffset(10, listTop),
	Size = UDim2.new(1, -20, 1, -(listTop + 10)),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ZIndex = 6,
	Parent = shopFrame,
}, {
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	new("UIPadding", { PaddingRight = UDim.new(0, 10) }),
})

local shopEntries = {}

for _, seed in ipairs(Config.Seeds) do
	local entry = new("Frame", {
		Size = UDim2.new(1, 0, 0, 78),
		BackgroundColor3 = Color3.fromRGB(45, 52, 65),
		LayoutOrder = seed.Order,
		ZIndex = 6,
		Parent = shopList,
	}, { corner(12), stroke(Config.RarityColors[seed.Rarity], 2) })

	new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(46, 46),
		BackgroundColor3 = seed.Color,
		ZIndex = 7,
		Parent = entry,
	}, { corner(23), stroke(Color3.new(0, 0, 0), 2) })

	label({
		Position = UDim2.fromOffset(66, 6),
		Size = UDim2.new(1, -186, 0, 26),
		Text = seed.Name,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 22,
		ZIndex = 7,
		Parent = entry,
	})
	label({
		Position = UDim2.fromOffset(66, 32),
		Size = UDim2.new(1, -186, 0, 18),
		Text = seed.Rarity,
		TextColor3 = Config.RarityColors[seed.Rarity],
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 16,
		ZIndex = 7,
		Parent = entry,
	})
	local info = "Grows " .. Config.FormatTime(seed.GrowTime) .. " • Sells ~" .. Config.Format(seed.Value)
	if seed.Regrow then
		info ..= " • Regrows!"
	end
	label({
		Position = UDim2.fromOffset(66, 52),
		Size = UDim2.new(1, -186, 0, 18),
		Text = info,
		TextColor3 = Color3.fromRGB(190, 190, 200),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 14,
		ZIndex = 7,
		Parent = entry,
	})

	local stockLabel = label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 6),
		Size = UDim2.fromOffset(105, 20),
		Text = "Out of stock",
		MaxTextSize = 15,
		ZIndex = 7,
		Parent = entry,
	})
	local buyButton = button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -8),
		Size = UDim2.fromOffset(105, 38),
		Text = "💰 " .. Config.Format(seed.Price),
		BackgroundColor3 = GREEN,
		ZIndex = 7,
		Parent = entry,
	}, function()
		BuySeed:FireServer(seed.Name)
	end)

	shopEntries[seed.Name] = { Stock = stockLabel, Buy = buyButton, Seed = seed }
end

local function updateShop()
	for name, entry in pairs(shopEntries) do
		local stock = shopStock[name] or 0
		if stock > 0 then
			entry.Stock.Text = "x" .. stock .. " in stock"
			entry.Stock.TextColor3 = Color3.fromRGB(150, 255, 150)
		else
			entry.Stock.Text = "Out of stock"
			entry.Stock.TextColor3 = Color3.fromRGB(255, 130, 130)
		end
		if stock <= 0 then
			entry.Buy.BackgroundColor3 = GREY
		elseif state.Coins < entry.Seed.Price then
			entry.Buy.BackgroundColor3 = RED
		else
			entry.Buy.BackgroundColor3 = GREEN
		end
	end
end

---------------------------------------------------------------------------
-- Left menu
---------------------------------------------------------------------------
local menu = new("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 10, 0.5, 0),
	Size = UDim2.fromOffset(150, 320),
	BackgroundTransparency = 1,
	Parent = gui,
}, { new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })

local function menuButton(order, text, color, onClick)
	return button({
		Size = UDim2.new(1, 0, 0, 46),
		Text = text,
		BackgroundColor3 = color,
		LayoutOrder = order,
		Parent = menu,
	}, onClick)
end

menuButton(1, "🌱 Seed Shop", GREEN, function()
	shopFrame.Visible = not shopFrame.Visible
	if shopFrame.Visible then
		RequestState:FireServer()
	end
end)
menuButton(2, "💰 Sell", GOLD, function()
	shopFrame.Visible = false
	TeleportTo:FireServer("Sell")
end)
menuButton(3, "🏡 Garden", Color3.fromRGB(120, 90, 60), function()
	shopFrame.Visible = false
	TeleportTo:FireServer("Garden")
end)
local expandButton = menuButton(4, "⬆ Expand", Color3.fromRGB(0, 140, 220), function()
	if state.ExpandCost then
		ExpandGarden:FireServer()
	else
		toast("Your garden is fully expanded!")
	end
end)

local doubleButton = nil
if Config.GamePasses.DoubleCoins ~= 0 then
	doubleButton = menuButton(5, "⭐ 2x Coins", Color3.fromRGB(170, 80, 220), function()
		MarketplaceService:PromptGamePassPurchase(player, Config.GamePasses.DoubleCoins)
	end)
end
if Config.Products.CoinPack.Id ~= 0 then
	menuButton(6, "💎 +" .. Config.Format(Config.Products.CoinPack.Amount), Color3.fromRGB(0, 170, 170), function()
		MarketplaceService:PromptProductPurchase(player, Config.Products.CoinPack.Id)
	end)
end

---------------------------------------------------------------------------
-- Seed hotbar
---------------------------------------------------------------------------
local hotbar = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -12),
	Size = UDim2.new(0.7, 0, 0, 76),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.3,
	Parent = gui,
}, { corner(14), new("UISizeConstraint", { MaxSize = Vector2.new(760, 76) }) })

local hotbarList = new("ScrollingFrame", {
	Position = UDim2.fromOffset(6, 6),
	Size = UDim2.new(1, -12, 1, -12),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.X,
	ScrollingDirection = Enum.ScrollingDirection.X,
	Parent = hotbar,
}, {
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}),
})

local hotbarOrder = {} -- seed names in the order they appear (for number keys)

local function selectSeed(name)
	if state.Selected == name then
		name = nil -- clicking the selected seed deselects it
	end
	state.Selected = name
	SelectSeed:FireServer(name)
end

local function rebuildHotbar()
	for _, child in ipairs(hotbarList:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	table.clear(hotbarOrder)

	for _, seed in ipairs(Config.Seeds) do
		local count = state.Seeds[seed.Name]
		if count and count > 0 then
			table.insert(hotbarOrder, seed.Name)
			local slotNumber = #hotbarOrder
			local selected = state.Selected == seed.Name
			local slot = new("TextButton", {
				Size = UDim2.fromOffset(92, 58),
				BackgroundColor3 = selected and Color3.fromRGB(80, 90, 60) or Color3.fromRGB(50, 56, 70),
				Text = "",
				AutoButtonColor = true,
				LayoutOrder = seed.Order,
				Parent = hotbarList,
			}, {
				corner(10),
				stroke(selected and GOLD or Config.RarityColors[seed.Rarity], selected and 3 or 1.5),
			})
			new("Frame", {
				Position = UDim2.fromOffset(6, 6),
				Size = UDim2.fromOffset(14, 14),
				BackgroundColor3 = seed.Color,
				Parent = slot,
			}, { corner(7) })
			if slotNumber <= 9 then
				label({
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -4, 0, 2),
					Size = UDim2.fromOffset(16, 16),
					Text = tostring(slotNumber),
					TextColor3 = Color3.fromRGB(170, 170, 180),
					MaxTextSize = 14,
					Parent = slot,
				})
			end
			label({
				Position = UDim2.fromOffset(4, 20),
				Size = UDim2.new(1, -8, 0, 18),
				Text = seed.Name,
				MaxTextSize = 16,
				Parent = slot,
			})
			label({
				Position = UDim2.fromOffset(4, 38),
				Size = UDim2.new(1, -8, 0, 16),
				Text = "x" .. count,
				TextColor3 = Color3.fromRGB(200, 200, 210),
				MaxTextSize = 14,
				Parent = slot,
			})
			slot.Activated:Connect(function()
				selectSeed(seed.Name)
			end)
		end
	end

	if #hotbarOrder == 0 then
		label({
			Size = UDim2.new(1, 0, 1, 0),
			Text = "No seeds! Buy some at the 🌱 Seed Shop",
			TextColor3 = Color3.fromRGB(200, 200, 210),
			MaxTextSize = 18,
			Parent = hotbarList,
		})
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	local numbers = {
		[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
		[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
		[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9,
	}
	local slot = numbers[input.KeyCode]
	if slot and hotbarOrder[slot] then
		selectSeed(hotbarOrder[slot])
		rebuildHotbar()
	end
end)

---------------------------------------------------------------------------
-- Server events
---------------------------------------------------------------------------
local lastCoins = nil

StateUpdate.OnClientEvent:Connect(function(newState)
	state = newState
	state.Seeds = state.Seeds or {}

	coinsLabel.Text = "💰 " .. Config.Format(state.Coins)
	if lastCoins and state.Coins ~= lastCoins then
		coinsFrame.Size = UDim2.fromOffset(256, 50)
		TweenService:Create(coinsFrame, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(240, 46) }):Play()
	end
	lastCoins = state.Coins

	local worthText = state.FruitCount > 0 and ("  •  worth 💰" .. Config.Format(state.FruitWorth)) or ""
	backpackLabel.Text = "🎒 " .. state.FruitCount .. "/" .. Config.MaxFruits .. worthText
	backpackLabel.TextColor3 = state.FruitCount >= Config.MaxFruits and Color3.fromRGB(255, 120, 120) or WHITE

	if state.ExpandCost then
		expandButton.Text = "⬆ Expand 💰" .. Config.Format(state.ExpandCost)
	else
		expandButton.Text = "⬆ Maxed!"
	end
	if doubleButton then
		doubleButton.Visible = not state.DoubleCoins
	end

	rebuildHotbar()
	updateShop()
end)

ShopUpdate.OnClientEvent:Connect(function(stock, secondsLeft)
	shopStock = stock
	restockDeadline = os.clock() + secondsLeft
	updateShop()
end)

Notify.OnClientEvent:Connect(function(text, color)
	toast(text, color)
end)

OpenShop.OnClientEvent:Connect(function()
	shopFrame.Visible = true
end)

EventUpdate.OnClientEvent:Connect(function(name, message, secondsLeft)
	if not name then
		eventBanner.Visible = false
		eventDeadline = nil
		return
	end
	local event
	for _, e in ipairs(Config.Events) do
		if e.Name == name then
			event = e
		end
	end
	eventMessage = message or name
	eventDeadline = os.clock() + (secondsLeft or 0)
	eventStroke.Color = event and event.Color or WHITE
	eventLabel.TextColor3 = event and event.Color or WHITE
	eventBanner.Visible = true
	toast(eventMessage, event and event.Color)
end)

-- Timers
task.spawn(function()
	while true do
		restockLabel.Text = "New seeds in " .. Config.FormatTime(restockDeadline - os.clock())
		if eventDeadline then
			eventLabel.Text = eventMessage .. "  (" .. Config.FormatTime(eventDeadline - os.clock()) .. ")"
		end
		task.wait(0.25)
	end
end)

RequestState:FireServer()
