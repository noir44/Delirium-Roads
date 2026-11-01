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
-- type, types = { ... } takes any mix of them, named by nameKey.
-- time: action ticks (vanilla plastering a wall is 100).
DelRoads.RECIPES = {
	{ id = "CrushBoulder", bench = "crusher", time = 300,
		inputs = { { type = "Base.LargeStone", count = 1 }, { type = "Base.EmptySandbag", count = 1 } },
		outputs = { { type = "Base.Gravelbag", count = 1 } } },
	{ id = "CrushStones", bench = "crusher", time = 300,
		inputs = { { type = "Base.Stone2", count = 6 }, { type = "Base.EmptySandbag", count = 1 } },
		outputs = { { type = "Base.Gravelbag", count = 1 } } },
	-- One limestone, not two: limestone is scarce (forest boulders broken with a pickaxe, rare
	-- foraging and loot), user decision 2026-11-01.
	{ id = "BurnClinker", bench = "kiln", time = 600,
		inputs = { { type = "Base.Limestone", count = 1 }, { type = "Base.Clay", count = 1 } },
		outputs = { { type = "DelRoads.Clinker", count = 2 } } },
	-- Old worlds run short of loot; abandoned cars have tyres everywhere.
	{ id = "BurnTyre", bench = "kiln", time = 400,
		inputs = { { types = { "Base.OldTire1", "Base.OldTire2", "Base.OldTire3", "Base.NormalTire1",
			"Base.NormalTire2", "Base.NormalTire3", "Base.ModernTire1", "Base.ModernTire2", "Base.ModernTire3" },
			count = 1, nameKey = "IGUI_DelRoads_AnyTyre" } },
		outputs = { { type = "DelRoads.Bitumen", count = 1 } } },
	{ id = "GrindCement", bench = "mill", time = 400,
		inputs = { { type = "DelRoads.Clinker", count = 3 }, { type = "Base.EmptySandbag", count = 1 } },
		outputs = { { type = "Base.ConcretePowder", count = 1 } } },
	-- The gravel sack and the empty one are filled with the mix: two bags.
	{ id = "CookAsphalt", bench = "kettle", time = 500,
		inputs = { { type = "Base.Gravelbag", count = 1, test = full, testKey = "IGUI_DelRoads_FullBag" },
			{ type = "Base.ConcretePowder", count = 1 }, { type = "DelRoads.Bitumen", count = 1 },
			{ type = "Base.EmptySandbag", count = 1 } },
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

-- How many items the player has for one input.
function DelRoads.inputCount(inventory, input)
	local have = 0
	for _, fullType in ipairs(typesOf(input)) do
		have = have + inventory:getCountTypeEvalRecurse(fullType, input.test or anyItem)
	end
	return have
end

-- Items for one input, a Lua array of at most input.count of them.
function DelRoads.inputItems(inventory, input)
	local out = {}
	for _, fullType in ipairs(typesOf(input)) do
		local left = input.count - #out
		if left <= 0 then break end
		local items = inventory:getSomeTypeEvalRecurse(fullType, input.test or anyItem, left)
		for i = 0, items:size() - 1 do table.insert(out, items:get(i)) end
	end
	return out
end

-- How many times the player can run the recipe with what they carry.
function DelRoads.timesPossible(inventory, recipe)
	local times = nil
	for _, input in ipairs(recipe.inputs) do
		local n = math.floor(DelRoads.inputCount(inventory, input) / input.count)
		if not times or n < times then times = n end
	end
	return times or 0
end
