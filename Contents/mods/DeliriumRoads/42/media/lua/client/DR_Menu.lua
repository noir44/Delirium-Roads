-- Delirium Roads - world context menu: mend the cracks of a tile or of the
-- tiles around it, open the work orders, mark a new order (two corners),
-- and for admins a dump of the square (what erosion put on it).

if isServer() then return end

require "ISUI/ISToolTip"
require "ISUI/ISTextBox"
require "DR_Client"
require "TimedActions/DR_RepairAction"

-- Tiles around the clicked one mended in one go: (2 * AROUND + 1)^2.
local AROUND = 2

-- First corner of the order being marked: { x, y } or nil.
local corner = nil

local function disable(option, text)
	option.notAvailable = true
	local tip = ISToolTip:new()
	tip:initialise()
	tip:setVisible(false)
	tip.description = text
	option.toolTip = tip
end

-- Cracked tiles not mended yet, as far as this client knows.
local function canMend(square)
	if not square or not DelRoads.hasCracks(square) then return false end
	local x, y, z = square:getX(), square:getY(), square:getZ()
	return DelRoads.bucketLoaded(x, y) and not DelRoads.isMended(x, y, z)
end

local function queueRepairs(player, squares)
	local first = true
	for _, square in ipairs(squares) do
		if luautils.walkAdj(player, square, not first) then
			ISTimedActionQueue.add(DR_RepairAction:new(player, square))
			first = false
		end
	end
end

local function onRepair(player, squares)
	queueRepairs(player, squares)
end

local function onOrders(player)
	if DelRoadsOrdersUI then DelRoadsOrdersUI.open(player) end
end

local function onCornerA(player, square)
	corner = { x = square:getX(), y = square:getY() }
	player:setHaloNote(getText("IGUI_DelRoads_CornerSet", tostring(corner.x), tostring(corner.y)), 255, 255, 255, 300)
end

local function onCornerReset()
	corner = nil
end

-- Second prompt: the price, paid from the customer's treasury when the
-- contractor reports the order done. target carries the first answers.
local function onOrderPrice(target, button, playerNum)
	if button.internal ~= "OK" or not corner then return end
	DelRoads.send("createOrder", { hall = target.hallId, title = target.title, price = button.parent.entry:getText(),
		x1 = corner.x, y1 = corner.y, x2 = target.x2, y2 = target.y2 })
	corner = nil
end

local function onOrderTitle(target, button, hallId, x2, y2, playerNum)
	if button.internal ~= "OK" or not corner then return end
	local answers = { hallId = hallId, title = button.parent.entry:getText(), x2 = x2, y2 = y2 }
	local box = ISTextBox:new(0, 0, 320, 160, getText("IGUI_DelRoads_OrderPricePrompt"), "0", answers, onOrderPrice,
		playerNum, playerNum)
	box:initialise()
	box:addToUIManager()
end

local function onCornerB(player, square, hallId)
	if not corner then return end
	local hall = DelEcon.getHall(DelEcon.getState(), hallId)
	local box = ISTextBox:new(0, 0, 320, 160, getText("IGUI_DelRoads_OrderTitlePrompt", DelEcon.hallName(hall)), "",
		{}, onOrderTitle, player:getPlayerNum(), hallId, square:getX(), square:getY(), player:getPlayerNum())
	box:initialise()
	box:addToUIManager()
end

local function onDump(player, square)
	local lines = { string.format("DelRoads dump %d,%d,%d mended=%s bucketLoaded=%s", square:getX(), square:getY(),
		square:getZ(), tostring(DelRoads.isMended(square:getX(), square:getY(), square:getZ())),
		tostring(DelRoads.bucketLoaded(square:getX(), square:getY()))) }
	local objects = square:getObjects()
	for i = 0, objects:size() - 1 do
		local object = objects:get(i)
		local sprite = object:getSprite()
		table.insert(lines, string.format("  [%d] %s name=%s sprite=%s floor=%s", i, tostring(object:getObjectName()),
			tostring(object:getName()), tostring(sprite and sprite:getName()), tostring(object == square:getFloor())))
		local attached = object:getAttachedAnimSprite()
		if attached then
			for j = 0, attached:size() - 1 do
				local parent = attached:get(j):getParentSprite()
				table.insert(lines, string.format("      attached[%d] %s", j, tostring(parent and parent:getName())))
			end
		end
	end
	for _, line in ipairs(lines) do print(line) end
	player:setHaloNote(getText("IGUI_DelRoads_Dumped"), 255, 255, 255, 300)
end

local function onFill(playerNum, context, worldobjects, test)
	if test then return end
	local player = getSpecificPlayer(playerNum)
	local object = worldobjects and worldobjects[1]
	local square = object and object:getSquare()
	if not player or not square then return end

	if DelShops.hasAdminRights(player) then
		context:addOption(getText("IGUI_DelRoads_Dump"), player, onDump, square)
	end
	if not DelRoads.isAnyOfficial(player) then return end

	if canMend(square) then
		local x, y, z = square:getX(), square:getY(), square:getZ()
		local option = context:addOption(getText("IGUI_DelRoads_Repair"), player, onRepair, { square })
		local why = DelRoads.whyNot(player, x, y) or DelRoads.missingMaterial(player)
		if why then
			disable(option, getText(why))
		else
			local tip = ISToolTip:new()
			tip:initialise()
			tip:setVisible(false)
			tip.description = getText("IGUI_DelRoads_RepairTip", tostring(DelRoads.tilesPerBag()))
			option.toolTip = tip
		end
		if not why then
			local around = {}
			for dy = -AROUND, AROUND do
				for dx = -AROUND, AROUND do
					local other = getCell():getGridSquare(x + dx, y + dy, z)
					if canMend(other) and DelRoads.whyNot(player, x + dx, y + dy) == nil then
						table.insert(around, other)
					end
				end
			end
			if #around > 1 then
				context:addOption(getText("IGUI_DelRoads_RepairAround", tostring(#around)), player, onRepair, around)
			end
		end
	end

	context:addOption(getText("IGUI_DelRoads_Orders"), player, onOrders)

	local halls = DelRoads.managedHalls(player)
	if #halls > 0 then
		if not corner then
			context:addOption(getText("IGUI_DelRoads_CornerA"), player, onCornerA, square)
		else
			local parent = context:addOption(getText("IGUI_DelRoads_CornerB", tostring(corner.x), tostring(corner.y)))
			local sub = ISContextMenu:getNew(context)
			context:addSubMenu(parent, sub)
			local state = DelEcon.getState()
			for _, id in ipairs(halls) do
				sub:addOption(DelEcon.hallName(state.halls[id]), player, onCornerB, square, id)
			end
			context:addOption(getText("IGUI_DelRoads_CornerReset"), player, onCornerReset)
		end
	end
end
Events.OnFillWorldObjectContextMenu.Add(onFill)
