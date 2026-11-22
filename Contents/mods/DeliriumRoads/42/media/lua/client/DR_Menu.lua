-- Delirium Roads - world context menu: mend cracks (a cursor to pick the
-- tiles, DR_RepairCursor), open the work orders, mark a new order (two
-- corners on the ground or on the world map), and for admins a dump of the
-- square (what erosion put on it).

if isServer() then return end

require "ISUI/ISToolTip"
require "ISUI/ISTextBox"
require "DR_Client"
require "TimedActions/DR_RepairAction"

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
function DelRoads.canMend(square)
	if not square or not DelRoads.hasCracks(square) then return false end
	local x, y, z = square:getX(), square:getY(), square:getZ()
	return DelRoads.bucketLoaded(x, y) and not DelRoads.isMended(x, y, z)
end

local function onRepair(player)
	getCell():setDrag(DR_RepairCursor:new(player), player:getPlayerNum())
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
-- contractor reports the order done. target carries the area and the title.
local function onOrderPrice(target, button)
	if button.internal ~= "OK" then return end
	DelRoads.send("createOrder", { hall = target.hallId, title = target.title, price = button.parent.entry:getText(),
		x1 = target.x1, y1 = target.y1, x2 = target.x2, y2 = target.y2 })
end

local function onOrderTitle(target, button, playerNum)
	if button.internal ~= "OK" then return end
	target.title = button.parent.entry:getText()
	local box = ISTextBox:new(0, 0, 320, 160, getText("IGUI_DelRoads_OrderPricePrompt"), "0", target, onOrderPrice,
		playerNum)
	box:initialise()
	box:addToUIManager()
end

-- The title and price prompts for an area marked out on the ground or on
-- the map; the server sorts the corners and checks the size.
function DelRoads.askOrder(player, hallId, x1, y1, x2, y2)
	local hall = DelEcon.getHall(DelEcon.getState(), hallId)
	local target = { hallId = hallId, x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
	local box = ISTextBox:new(0, 0, 320, 160, getText("IGUI_DelRoads_OrderTitlePrompt", DelEcon.hallName(hall)), "",
		target, onOrderTitle, player:getPlayerNum(), player:getPlayerNum())
	box:initialise()
	box:addToUIManager()
end

local function onCornerB(player, square, hallId)
	if not corner then return end
	local x1, y1 = corner.x, corner.y
	corner = nil
	DelRoads.askOrder(player, hallId, x1, y1, square:getX(), square:getY())
end

local function onMapOrder(player, hallId)
	corner = nil
	if DelRoads.startMapPick then DelRoads.startMapPick(player, hallId) end
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
	-- Mending and giving orders are separate activities: a customer
	-- organization without the road repair one still marks out orders.
	local official = DelRoads.isAnyOfficial(player)
	local halls = DelRoads.managedHalls(player)
	if not official and #halls == 0 then return end

	if official and DelRoads.canMend(square) then
		local x, y = square:getX(), square:getY()
		local option = context:addOption(getText("IGUI_DelRoads_Repair"), player, onRepair)
		local why = DelRoads.whyNot(player, x, y) or DelRoads.missingMaterial(player)
		if why then
			disable(option, getText(why))
		else
			local tip = ISToolTip:new()
			tip:initialise()
			tip:setVisible(false)
			tip.description = getText("IGUI_DelRoads_RepairTip")
			option.toolTip = tip
		end
	end

	context:addOption(getText("IGUI_DelRoads_Orders"), player, onOrders)

	if #halls > 0 then
		local state = DelEcon.getState()
		local mapParent = context:addOption(getText("IGUI_DelRoads_OrderOnMap"))
		local mapSub = ISContextMenu:getNew(context)
		context:addSubMenu(mapParent, mapSub)
		for _, id in ipairs(halls) do
			mapSub:addOption(DelEcon.hallName(state.halls[id]), player, onMapOrder, id)
		end
		if not corner then
			context:addOption(getText("IGUI_DelRoads_CornerA"), player, onCornerA, square)
		else
			local parent = context:addOption(getText("IGUI_DelRoads_CornerB", tostring(corner.x), tostring(corner.y)))
			local sub = ISContextMenu:getNew(context)
			context:addSubMenu(parent, sub)
			for _, id in ipairs(halls) do
				sub:addOption(DelEcon.hallName(state.halls[id]), player, onCornerB, square, id)
			end
			context:addOption(getText("IGUI_DelRoads_CornerReset"), player, onCornerReset)
		end
	end
end
Events.OnFillWorldObjectContextMenu.Add(onFill)
