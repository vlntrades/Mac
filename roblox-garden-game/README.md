# Garden Tycoon: an idle farming game for Roblox

Plant seeds, wait for them to grow, harvest the fruit, sell it, and buy rarer seeds.
Plants keep growing while you're offline. Everything is built by script, so you don't need any models.

## Setup (about 5 minutes)

1. Open **Roblox Studio**, then **New**, then **Baseplate**.
2. Make **3 scripts**. The names and locations must match exactly.

| File in this folder | Studio location | What to insert | Name it |
|---|---|---|---|
| `GardenConfig.lua` | **ReplicatedStorage** | ModuleScript | `GardenConfig` |
| `GardenServer.server.lua` | **ServerScriptService** | Script | `GardenServer` |
| `GardenClient.client.lua` | **StarterPlayer > StarterPlayerScripts** | LocalScript | `GardenClient` |

   To add each one, hover over the location in the Explorer, click **+**, pick the type, rename it,
   delete the default `print("Hello world!")`, and paste in the whole file.

3. Press **Play**. You'll spawn in your garden with 3 Carrot seeds.

### Turn on saving
Go to **File, then Publish to Roblox**. Then open **Game Settings, then Security** and turn on
**Enable Studio Access to API Services**. Without this the game still works, but progress resets.

### Set the server size
Each server has 6 gardens. Go to **Game Settings, then Places** (or the Creator Dashboard) and set **Max Players = 6**.

## How to play
- **Hotbar** (bottom): pick a seed. On PC you can also press keys 1 to 9.
- **Click soil** in your garden to plant. Click a plant marked READY to harvest it.
- **Sell**: walk to the yellow SELL FRUIT stand, or use the 💰 Sell button.
- **Seed Shop**: the green stand or the 🌱 button. Stock is random and **restocks every 5 minutes**.
  Rare seeds only show up sometimes, and the whole server gets an alert when they do.
- **Expand** unlocks more soil tiles.
- **Multi-harvest plants** (Strawberry, Tomato, Mango and others) keep producing fruit forever.
- **Mutations**: Gold (x20) and Rainbow (x50) can happen on any harvest. Weather events (Rain, Frost, Blood Moon)
  happen every 8 minutes and add their own mutations. **Huge** fruit are worth 2x to 4x.

## Making money with Robux (optional)
On the Creator Dashboard, create:
- a **Game Pass** "2x Coins"
- a **Developer Product** "Restock Shop" (restocks the shop for the whole server, which players love buying)
- a **Developer Product** "Coin Pack"

Paste their IDs into the bottom of `GardenConfig` (`Config.GamePasses` / `Config.Products`). Their buttons
appear automatically. While an ID is 0, its button stays hidden.

## Tweaking the game
Everything you'd want to balance is in `GardenConfig`: seed prices, grow times, values, stock chances,
restock timer, expansion costs, mutations and events. To add a new seed, copy one of the seed blocks
and change its values.
