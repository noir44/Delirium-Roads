-- Delirium Roads - showing a work order's area: its border highlighted on
-- the ground and a frame on the world map, for the orders this player
-- tracks (an order accepted by them is tracked at once; the orders window
-- toggles it).
--
-- addAreaHighlightForPlayer lasts one frame, vanilla calls it from a UI
-- render (ISAddDesignationAnimalZoneUI), so a 1x1 element does it every
-- frame - a screen-sized one would break dropping items on the floor (see
-- E:\mods\CLAUDE.md).

if isServer() then return end

require "ISUI/ISUIElement"
require "ISUI/Maps/ISWorldMap"
require "DR_Client"

DelRoads.tracked = DelRoads.tracked or {}

local highlighter = nil

-- Tracked orders that still exist and are not done; drops the rest.
local function trackedOrders()
	local out, gone = {}, {}
	local orders = DelRoads.getOrders()
	for id, _ in pairs(DelRoads.tracked) do
		local order = orders and orders.list[id]
		if order and order.status ~= DelRoads.DONE then
			table.insert(out, order)
		else
			table.insert(gone, id)
		end
	end
	for _, id in ipairs(gone) do DelRoads.tracked[id] = nil end
	return out
end

DelRoadsHighlighter = ISUIElement:derive("DelRoadsHighlighter")

function DelRoadsHighlighter:prerender()
	local player = getPlayer()
	local list = trackedOrders()
	if not player or #list == 0 then
		self:removeFromUIManager()
		highlighter = nil
		return
	end
	local playerNum = player:getPlayerNum()
	local z = math.floor(player:getZ())
	for _, o in ipairs(list) do
		local r, g, b, a = 1.0, 0.8, 0.1, 0.55
		addAreaHighlightForPlayer(playerNum, o.x1, o.y1, o.x2 + 1, o.y1 + 1, z, r, g, b, a)
		addAreaHighlightForPlayer(playerNum, o.x1, o.y2, o.x2 + 1, o.y2 + 1, z, r, g, b, a)
		addAreaHighlightForPlayer(playerNum, o.x1, o.y1 + 1, o.x1 + 1, o.y2, z, r, g, b, a)
		addAreaHighlightForPlayer(playerNum, o.x2, o.y1 + 1, o.x2 + 1, o.y2, z, r, g, b, a)
	end
end

local function ensureHighlighter()
	if highlighter or #trackedOrders() == 0 then return end
	highlighter = DelRoadsHighlighter:new(0, 0, 1, 1)
	highlighter:initialise()
	highlighter:setConsumeMouseEvents(false)
	highlighter:addToUIManager()
end

function DelRoads.isTracked(id)
	return DelRoads.tracked[id] == true
end

function DelRoads.setTracked(id, on)
	DelRoads.tracked[id] = on and true or nil
	ensureHighlighter()
end

-- Opens the world map on the order's area and tracks it.
function DelRoads.showOnMap(player, id)
	local orders = DelRoads.getOrders()
	local order = orders and orders.list[id]
	if not order then return end
	DelRoads.setTracked(id, true)
	local cx, cy = (order.x1 + order.x2 + 1) / 2, (order.y1 + order.y2 + 1) / 2
	ISWorldMap.ShowWorldMap(player:getPlayerNum(), cx, cy, 16.0)
	if ISWorldMap_instance then ISWorldMap_instance.mapAPI:centerOn(cx, cy) end
end

-- After a reconnect: the orders this player accepted and still works on.
local trackedOnLogin = false

function DelRoads.trackOwnOrders()
	local player = getPlayer()
	local orders = DelRoads.getOrders()
	if trackedOnLogin or not player or not orders then return end
	trackedOnLogin = true
	for id, order in pairs(orders.list) do
		if order.status == DelRoads.ACCEPTED and order.acceptedBy == player:getUsername() then
			DelRoads.tracked[id] = true
		end
	end
	ensureHighlighter()
end

-- ---------------------------------------------------------------------------
-- World map frame
-- ---------------------------------------------------------------------------

local originalRender = ISWorldMap.render

function ISWorldMap:render()
	originalRender(self)
	for _, o in ipairs(trackedOrders()) do
		local api = self.mapAPI
		local x1, y1, x2, y2 = o.x1, o.y1, o.x2 + 1, o.y2 + 1
		local ax, ay = api:worldToUIX(x1, y1), api:worldToUIY(x1, y1)
		local bx, by = api:worldToUIX(x2, y1), api:worldToUIY(x2, y1)
		local cx, cy = api:worldToUIX(x2, y2), api:worldToUIY(x2, y2)
		local dx, dy = api:worldToUIX(x1, y2), api:worldToUIY(x1, y2)
		local r, g, b, a = 1.0, 0.7, 0.0, 1.0
		self.javaObject:DrawLine(nil, ax, ay, bx, by, 3, r, g, b, a)
		self.javaObject:DrawLine(nil, bx, by, cx, cy, 3, r, g, b, a)
		self.javaObject:DrawLine(nil, cx, cy, dx, dy, 3, r, g, b, a)
		self.javaObject:DrawLine(nil, dx, dy, ax, ay, 3, r, g, b, a)
		local mx, my = api:worldToUIX((x1 + x2) / 2, (y1 + y2) / 2), api:worldToUIY((x1 + x2) / 2, (y1 + y2) / 2)
		self:drawTextCentre(o.title or "", mx, my - getTextManager():getFontHeight(UIFont.Medium) / 2,
			1.0, 0.85, 0.2, 1.0, UIFont.Medium)
	end
end
