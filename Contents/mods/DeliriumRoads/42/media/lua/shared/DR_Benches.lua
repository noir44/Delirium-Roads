-- Delirium Roads - the road works benches and what they make.
--
--   stone ----[crusher]----> gravel ----------------------------------.
--   limestone + clay --[kiln]--> clinker --[ball mill]--> cement ------+
--   tyre --[kiln, pyrolysis]--> bitumen (also loot) --------------------+--[asphalt kettle]--> asphalt mix
--
-- Benches are 1x1 furniture from the mod's tile pack (delroads_01, four
-- facings each), built by a craft recipe (scripts/DR_Recipes.txt) and placed
-- like any moveable. They work only with electricity on their square: a
-- generator in range, or the grid with the bench indoors - vanilla's test
-- for the car battery charger (ISWorldObjectContextMenu.lua:460). The
-- engine's own CraftBench energy channels are not used: no vanilla bench
-- takes energy, so there is no proof a generator feeds them.
--
-- The work is a timed action at the bench; the server checks the bench, the
-- power and the inputs, takes the inputs and gives the outputs.

require "DR_Shared"

DelRoads.TILESET = "delroads_01_"

-- Sprite index / 4 = bench number (S, E, N, W).
DelRoads.BENCH_KINDS = { "crusher", "kiln", "mill", "kettle" }

local function full(item)
	return item:getCurrentUsesFloat() >= 0.999
end

-- inputs: { type, count, test (optional), testKey (tooltip) }; instead of
-- type, types = { ... } takes any mix of them, named by nameKey; sack = true
-- takes any empty sack (see emptySack below).
-- time: action ticks (vanilla plastering a wall is 100).
--
-- An empty sack is not only Base.EmptySandbag: a dozen vanilla items are
-- called just "Sack" (wheat sacks, the treasure bag...), and a player
-- holding seven of them saw "Sack 0/1". Taken is whatever vanilla lets you
-- fill with a shovel: the HOLD_DIRT tag and nothing inside
-- (server/BuildingObjects/ISShovelGroundCursor.lua:4).
local SACK = { sack = true, count = 1, nameKey = "IGUI_DelRoads_EmptySack" }

DelRoads.RECIPES = {
	{ id = "CrushBoulder", bench = "crusher", time = 300,
		inputs = { { type = "Base.LargeStone", count = 1 }, SACK },
		outputs = { { type = "Base.Gravelbag", count = 1 } } },
	{ id = "CrushStones", bench = "crusher", time = 300,
		inputs = { { type = "Base.Stone2", count = 6 }, SACK },
		outputs = { { type = "Base.Gravelbag", count = 1 } } },
	{ id = "BurnClinker", bench = "kiln", time = 600,
		inputs = { { type = "Base.Limestone", count = 2 }, { type = "Base.Clay", count = 1 } },
		outputs = { { type = "DelRoads.Clinker", count = 2 } } },
	-- Old worlds run short of loot; abandoned cars have tyres everywhere.
	{ id = "BurnTyre", bench = "kiln", time = 400,
		inputs = { { types = { "Base.OldTire1", "Base.OldTire2", "Base.OldTire3", "Base.NormalTire1",
			"Base.NormalTire2", "Base.NormalTire3", "Base.ModernTire1", "Base.ModernTire2", "Base.ModernTire3" },
			count = 1, nameKey = "IGUI_DelRoads_AnyTyre" } },
		outputs = { { type = "DelRoads.Bitumen", count = 1 } } },
	-- No sack: vanilla's bag of cement is a plain item and never gives a sack
	-- back, so one taken here was lost for good (2026-11-22). Sacks only go
	-- into gravel and asphalt mix, and both turn back into a sack when spent.
	{ id = "GrindCement", bench = "mill", time = 400,
		inputs = { { type = "DelRoads.Clinker", count = 3 } },
		outputs = { { type = "Base.ConcretePowder", count = 1 } } },
	-- The gravel sack and the empty one are filled with the mix: two bags.
	{ id = "CookAsphalt", bench = "kettle", time = 500,
		inputs = { { type = "Base.Gravelbag", count = 1, test = full, testKey = "IGUI_DelRoads_FullBag" },
			{ type = "Base.ConcretePowder", count = 1 }, { type = "DelRoads.Bitumen", count = 1 },
			SACK },
		outputs = { { type = "DelRoads.AsphaltMix", count = 2 } } },
}

function DelRoads.recipe(id)
	for _, recipe in ipairs(DelRoads.RECIPES) do
		if recipe.id == id then return recipe end
	end
	return nil
end

function DelRoads.recipesOf(kind)
	local out = {}
	for _, recipe in ipairs(DelRoads.RECIPES) do
		if recipe.bench == kind then table.insert(out, recipe) end
	end
	return out
end

-- The bench object on this square and its kind, or nil.
function DelRoads.benchAt(square)
	if not square then return nil end
	local objects = square:getObjects()
	for i = 0, objects:size() - 1 do
		local object = objects:get(i)
		local sprite = object:getSprite()
		local name = sprite and sprite:getName()
		if name and string.sub(name, 1, #DelRoads.TILESET) == DelRoads.TILESET then
			local index = tonumber(string.sub(name, #DelRoads.TILESET + 1))
			local kind = index and DelRoads.BENCH_KINDS[math.floor(index / 4) + 1]
			if kind then return object, kind end
		end
	end
	return nil
end

function DelRoads.hasPower(square)
	return square ~= nil and (square:haveElectricity() or (square:hasGridPower() and square:getRoom() ~= nil))
end

local function anyItem()
	return true
end

local function typesOf(input)
	return input.types or { input.type }
end

local function emptySack(item)
	if not instanceof(item, "InventoryContainer") then return false end
	local inside = item:getInventory()
	return inside ~= nil and inside:isEmpty()
end

-- Where a bench takes its inputs from: the player's inventory first, then
-- the crates and the floor on the 3x3 around the bench - the same squares
-- and rules as vanilla's loot window (ISInventoryPage.lua:1667-1758): same
-- floor, reachable through walls, safehouse loot allowed, no thumpables
-- locked to someone else. A bag on the floor counts as a container, the
-- floor items themselves as a plain list. The client builds it for the
-- tooltip, the server again for the craft.
-- { containers = { ItemContainer... }, floor = { InventoryItem... } }
function DelRoads.sources(player, benchSquare)
	local src = { containers = { player:getInventory() }, floor = {} }
	if not benchSquare then return src end
	local cell = getCell()
	local bx, by, bz = benchSquare:getX(), benchSquare:getY(), benchSquare:getZ()
	for dy = -1, 1 do
		for dx = -1, 1 do
			local sq = cell:getGridSquare(bx + dx, by + dy, bz)
			if sq and (sq == benchSquare or benchSquare:canReachTo(sq)) and SafeHouse.isSafehouseAllowLoot(sq, player) then
				local wobs = sq:getWorldObjects()
				for i = 0, wobs:size() - 1 do
					local item = wobs:get(i):getItem()
					if item then
						table.insert(src.floor, item)
						if instanceof(item, "InventoryContainer") and item:getInventory() then
							table.insert(src.containers, item:getInventory())
						end
					end
				end
				local objects = sq:getObjects()
				for i = 0, objects:size() - 1 do
					local o = objects:get(i)
					if not (instanceof(o, "IsoThumpable") and o:isLockedToCharacter(player)) then
						for c = 0, o:getContainerCount() - 1 do
							table.insert(src.containers, o:getContainerByIndex(c))
						end
					end
				end
			end
		end
	end
	return src
end

-- Does a loose floor item fit one input?
local function fits(item, input)
	if input.sack then return item:hasTag(ItemTag.HOLD_DIRT) and emptySack(item) end
	for _, fullType in ipairs(typesOf(input)) do
		if item:getFullType() == fullType then return (input.test or anyItem)(item) end
	end
	return false
end

-- How many items there are for one input.
function DelRoads.inputCount(src, input)
	local have = 0
	for _, container in ipairs(src.containers) do
		if input.sack then
			have = have + container:getCountTagEvalRecurse(ItemTag.HOLD_DIRT, emptySack)
		else
			for _, fullType in ipairs(typesOf(input)) do
				have = have + container:getCountTypeEvalRecurse(fullType, input.test or anyItem)
			end
		end
	end
	for _, item in ipairs(src.floor) do
		if fits(item, input) then have = have + 1 end
	end
	return have
end

-- Items for one input, a Lua array of at most input.count of them,
-- inventory first.
function DelRoads.inputItems(src, input)
	local out = {}
	local function add(items)
		for i = 0, items:size() - 1 do table.insert(out, items:get(i)) end
	end
	for _, container in ipairs(src.containers) do
		if input.sack then
			local left = input.count - #out
			if left <= 0 then return out end
			add(container:getSomeTagEvalRecurse(ItemTag.HOLD_DIRT, emptySack, left))
		else
			for _, fullType in ipairs(typesOf(input)) do
				local left = input.count - #out
				if left <= 0 then return out end
				add(container:getSomeTypeEvalRecurse(fullType, input.test or anyItem, left))
			end
		end
	end
	for _, item in ipairs(src.floor) do
		if #out >= input.count then return out end
		if fits(item, input) then table.insert(out, item) end
	end
	return out
end

-- How many times the recipe can run with what there is.
function DelRoads.timesPossible(src, recipe)
	local times = nil
	for _, input in ipairs(recipe.inputs) do
		local n = math.floor(DelRoads.inputCount(src, input) / input.count)
		if not times or n < times then times = n end
	end
	return times or 0
end
