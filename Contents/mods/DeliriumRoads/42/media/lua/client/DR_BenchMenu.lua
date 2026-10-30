-- Delirium Roads - world context menu of a bench: a submenu with its
-- recipes, each with a tooltip of what it takes (have / need) and makes,
-- and "all" to queue as many runs as the inventory allows.

if isServer() then return end

require "ISUI/ISToolTip"
require "DR_Client"
require "DR_Benches"
require "TimedActions/DR_BenchAction"

local function itemName(fullType)
	return getItemNameFromFullType(fullType) or fullType
end

local function tooltip(player, recipe, powered)
	local inventory = player:getInventory()
	local lines = { getText("IGUI_DelRoads_Takes") }
	for _, input in ipairs(recipe.inputs) do
		local have = DelRoads.inputCount(inventory, input)
		local color = have >= input.count and "<RGB:0.4,1,0.4>" or "<RGB:1,0.4,0.4>"
		local name = input.nameKey and getText(input.nameKey) or itemName(input.type)
		if input.testKey then name = name .. " (" .. getText(input.testKey) .. ")" end
		table.insert(lines, string.format(" %s %s %d/%d <RGB:1,1,1> ", color, name, math.min(have, input.count), input.count))
	end
	table.insert(lines, " <LINE> " .. getText("IGUI_DelRoads_Makes"))
	for _, output in ipairs(recipe.outputs) do
		table.insert(lines, string.format(" %s x%d", itemName(output.type), output.count))
	end
	if not powered then table.insert(lines, " <LINE> <RGB:1,0.4,0.4> " .. getText("IGUI_DelRoads_NoPower")) end
	local tip = ISToolTip:new()
	tip:initialise()
	tip:setVisible(false)
	tip.description = table.concat(lines, " <LINE> ")
	return tip
end

local function queue(player, square, recipe, times)
	if not luautils.walkAdj(player, square, false) then return end
	for _ = 1, times do
		ISTimedActionQueue.add(DR_BenchAction:new(player, square, recipe))
	end
end

local function onFill(playerNum, context, worldobjects, test)
	if test then return end
	local player = getSpecificPlayer(playerNum)
	local object = worldobjects and worldobjects[1]
	local square = object and object:getSquare()
	if not player or not square then return end
	local bench, kind = DelRoads.benchAt(square)
	if not bench then return end

	local powered = DelRoads.hasPower(square)
	local parent = context:addOption(getText("IGUI_DelRoads_Bench_" .. kind))
	local sub = ISContextMenu:getNew(context)
	context:addSubMenu(parent, sub)
	for _, recipe in ipairs(DelRoads.recipesOf(kind)) do
		local times = DelRoads.timesPossible(player:getInventory(), recipe)
		local name = getText("IGUI_DelRoads_Recipe_" .. recipe.id)
		local option = sub:addOption(name, player, queue, square, recipe, 1)
		option.toolTip = tooltip(player, recipe, powered)
		if not powered or times < 1 then option.notAvailable = true end
		if powered and times > 1 then
			local all = sub:addOption(getText("IGUI_DelRoads_RecipeAll", name, tostring(times)), player, queue, square,
				recipe, times)
			all.toolTip = tooltip(player, recipe, powered)
		end
	end
end
Events.OnFillWorldObjectContextMenu.Add(onFill)
