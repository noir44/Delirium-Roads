-- Delirium Roads - definitions shared by client and server.
--
-- City Hall staff (Delirium Economy) mend the cracked roads: a timed action
-- on a cracked tile, a mason's trowel, cement and gravel (one bag of each per
-- sandbox DelRoads.TilesPerBag tiles). Staff are paid their monthly salary by
-- Economy; this mod pays nothing itself. A mended tile cracks again after
-- about DelRoads.RepairLastsDays game days. A mayor can mark road work
-- orders (a rectangle of the map); with DelRoads.RequireOrder on, staff may
-- mend only inside an open order of their own hall.
--
-- The cracks are the engine's erosion (zombie.erosion.categories.StreetCracks):
-- an attached sprite d_streetcracks_1_* on the floor object, laid by
-- ErosionMain.LoadGridsquare on the client too, every time a square loads.
-- Removing it on the server would not reach the clients, so every client
-- strips it itself from the mended tiles the server lists (DR_Client.lua).

require "DE_Shared"

DelRoads = DelRoads or {}
DelRoads.MODULE = "DelRoads"
DelRoads.ORDERS_KEY = "DelRoads_Orders"
DelRoads.CRACK_PREFIX = "d_streetcracks"
-- Mended tiles are kept and sent in buckets of BUCKET x BUCKET tiles.
DelRoads.BUCKET = 100
-- How far from the tile the player may stand when the server checks.
DelRoads.REACH = 3
-- Largest side of a work order, in tiles.
DelRoads.ORDER_MAX_SIDE = 400

DelRoads.TROWEL = "Base.MasonsTrowel"
DelRoads.CEMENT = "Base.ConcretePowder"
DelRoads.GRAVEL = "Base.Gravelbag"

-- ---------------------------------------------------------------------------
-- Sandbox: read at the point of use, never at file scope (see E:\mods\CLAUDE.md).
-- ---------------------------------------------------------------------------

local function sandbox()
	return SandboxVars and SandboxVars.DelRoads or {}
end

function DelRoads.tilesPerBag()
	return math.max(1, math.floor(tonumber(sandbox().TilesPerBag) or 25))
end

function DelRoads.repairLastsDays()
	return math.max(1, tonumber(sandbox().RepairLastsDays) or 120)
end

function DelRoads.requireOrder()
	return sandbox().RequireOrder == true
end

function DelRoads.repairTime()
	return math.max(1, math.floor(tonumber(sandbox().RepairTime) or 150))
end

-- ---------------------------------------------------------------------------
-- Tiles and buckets
-- ---------------------------------------------------------------------------

function DelRoads.tileKey(x, y, z)
	return tostring(math.floor(x)) .. "," .. tostring(math.floor(y)) .. "," .. tostring(math.floor(z))
end

function DelRoads.parseTileKey(key)
	local x, y, z = string.match(tostring(key or ""), "^(-?%d+),(-?%d+),(-?%d+)$")
	if not x then return nil end
	return tonumber(x), tonumber(y), tonumber(z)
end

function DelRoads.bucketOf(x, y)
	return math.floor(x / DelRoads.BUCKET), math.floor(y / DelRoads.BUCKET)
end

function DelRoads.bucketKey(bx, by)
	return tostring(bx) .. "," .. tostring(by)
end

function DelRoads.today()
	return math.floor(getGameTime():getWorldAgeHours() / 24)
end

-- Index of the first crack sprite attached to the floor, or nil.
function DelRoads.crackIndex(floor)
	if not floor then return nil end
	local sprites = floor:getAttachedAnimSprite()
	if not sprites then return nil end
	for i = 0, sprites:size() - 1 do
		local sprite = sprites:get(i):getParentSprite()
		local name = sprite and sprite:getName()
		if name and string.sub(name, 1, #DelRoads.CRACK_PREFIX) == DelRoads.CRACK_PREFIX then return i end
	end
	return nil
end

function DelRoads.hasCracks(square)
	return square ~= nil and DelRoads.crackIndex(square:getFloor()) ~= nil
end

-- ---------------------------------------------------------------------------
-- Who may mend: staff, mayor of a City Hall or an admin
-- ---------------------------------------------------------------------------

local function isStaff(hall, player)
	return type(hall) == "table" and type(hall.staff) == "table" and hall.staff[player:getUsername()] ~= nil
end

-- Staff, mayor or admin of this hall.
function DelRoads.isOfficial(hall, player)
	if not hall or not player then return false end
	return DelEcon.canManage(hall, player) or isStaff(hall, player)
end

function DelRoads.isAnyOfficial(player)
	if not player then return false end
	if DelShops.hasAdminRights(player) then return true end
	local state = DelEcon.getState()
	for _, id in ipairs(DelEcon.hallIds(state)) do
		if DelRoads.isOfficial(state.halls[id], player) then return true end
	end
	return false
end

-- Hall ids this player may give work orders for (mayor or admin).
function DelRoads.managedHalls(player)
	local out = {}
	local state = DelEcon.getState()
	for _, id in ipairs(DelEcon.hallIds(state)) do
		if DelEcon.canManage(state.halls[id], player) then table.insert(out, id) end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Work orders
-- ---------------------------------------------------------------------------

-- orders = { nextId, list = { [id] = { hall, title, x1, y1, x2, y2, by,
--                                      created (game day), done, closed } } }
function DelRoads.getOrders()
	local orders = ModData.get(DelRoads.ORDERS_KEY)
	if type(orders) ~= "table" or type(orders.list) ~= "table" then return nil end
	return orders
end

function DelRoads.orderContains(order, x, y)
	return x >= order.x1 and x <= order.x2 and y >= order.y1 and y <= order.y2
end

-- Ids sorted by number, open ones first.
function DelRoads.orderIds(orders)
	local ids = {}
	if not orders then return ids end
	for id, _ in pairs(orders.list) do table.insert(ids, id) end
	table.sort(ids, function(a, b)
		local oa, ob = orders.list[a], orders.list[b]
		if (oa.closed == true) ~= (ob.closed == true) then return ob.closed == true end
		return (tonumber(a) or 0) < (tonumber(b) or 0)
	end)
	return ids
end

-- Open orders covering the tile whose hall this player works for.
function DelRoads.ordersAt(player, x, y)
	local out = {}
	local orders = DelRoads.getOrders()
	if not orders then return out end
	local state = DelEcon.getState()
	for _, id in ipairs(DelRoads.orderIds(orders)) do
		local order = orders.list[id]
		if not order.closed and DelRoads.orderContains(order, x, y)
			and DelRoads.isOfficial(DelEcon.getHall(state, order.hall), player) then
			table.insert(out, id)
		end
	end
	return out
end

-- nil when the player may mend this tile, otherwise a translation key.
function DelRoads.whyNot(player, x, y)
	if not DelRoads.isAnyOfficial(player) then return "IGUI_DelRoads_NotStaff" end
	if DelRoads.requireOrder() and not DelShops.hasAdminRights(player) and #DelRoads.ordersAt(player, x, y) == 0 then
		return "IGUI_DelRoads_NeedOrder"
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Materials
-- ---------------------------------------------------------------------------

local function notEmpty(item)
	return item:getCurrentUsesFloat() > 0
end

function DelRoads.findTrowel(inventory)
	return inventory:getFirstTypeRecurse(DelRoads.TROWEL)
end

function DelRoads.findCement(inventory)
	return inventory:getFirstTypeRecurse(DelRoads.CEMENT)
end

function DelRoads.findGravel(inventory)
	return inventory:getFirstTypeEvalRecurse(DelRoads.GRAVEL, notEmpty)
end

-- nil when everything is there, otherwise a translation key.
function DelRoads.missingMaterial(player)
	local inventory = player:getInventory()
	if not DelRoads.findTrowel(inventory) then return "IGUI_DelRoads_NeedTrowel" end
	if not DelRoads.findCement(inventory) then return "IGUI_DelRoads_NeedCement" end
	if not DelRoads.findGravel(inventory) then return "IGUI_DelRoads_NeedGravel" end
	return nil
end
