-- Delirium Roads - the server side: checks and records mended tiles, spends
-- the materials, keeps the work orders and lets mended tiles crack again.
--
-- Mended tiles: ModData "DelRoads_State", never transmitted whole - clients
-- ask for the buckets around them. They roll back with the world save, and
-- so do the materials spent on them, which is why no file of our own.
-- Work orders: ModData "DelRoads_Orders", small, sent to every client.
--
-- media/lua/server/ is also executed by connected clients, hence the guard
-- (see E:\mods\CLAUDE.md).
if isClient() then return end

require "DR_Shared"
require "DR_Benches"

local MODULE = DelRoads.MODULE
local STATE_KEY = "DelRoads_State"
local ORDERS_KEY = DelRoads.ORDERS_KEY

local Commands = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function log(msg)
	print("DelRoads: " .. msg)
	writeLog("DelRoads", msg)
end

local function trim(value)
	return (string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1"))
end

-- state = { buckets = { ["bx,by"] = { ["x,y,z"] = day it cracks again } },
--           worked = { [username] = tiles mended, ever }, lastPurge = day }
local function state()
	local s = ModData.getOrCreate(STATE_KEY)
	if type(s.buckets) ~= "table" then s.buckets = {} end
	if type(s.worked) ~= "table" then s.worked = {} end
	return s
end

-- Orders from before customers and contractors: open ones stay open,
-- closed ones count as done.
local function orders()
	local o = ModData.getOrCreate(ORDERS_KEY)
	if type(o.list) ~= "table" then o.list = {} end
	if o.nextId == nil then o.nextId = 1 end
	for _, order in pairs(o.list) do
		if order.status == nil then
			order.status = order.closed and DelRoads.DONE or DelRoads.OPEN
			order.closed = nil
			order.price = order.price or 0
		end
	end
	return o
end

local function transmitOrders()
	ModData.transmit(ORDERS_KEY)
end

local function reply(player, command, args)
	sendServerCommand(player, MODULE, command, args or {})
end

local function broadcast(command, args)
	sendServerCommand(MODULE, command, args or {})
end

-- The client renders the text in its own language.
local function notify(player, key, arg1)
	reply(player, "notify", { key = key, arg1 = arg1 })
end

local function removeItem(player, item)
	local container = item:getContainer()
	if not container then return end
	player:removeFromHands(item)
	container:DoRemoveItem(item)
	sendRemoveItemFromContainer(container, item)
end

-- One use of the asphalt mix bag per tile; an emptied bag turns into an
-- empty sack (ReplaceOnDeplete). worked counts tiles per player, for the log.
local function spend(s, player)
	local name = player:getUsername()
	s.worked[name] = (s.worked[name] or 0) + 1
	local mix = DelRoads.findMix(player:getInventory())
	if mix then mix:UseAndSync() end
end

-- About RepairLastsDays, give or take a quarter, so a mended street does
-- not crack all at once.
local function crackDay()
	local days = DelRoads.repairLastsDays()
	return DelRoads.today() + math.max(1, math.floor(days * (0.75 + ZombRandFloat(0.0, 0.5)) + 0.5))
end

-- ---------------------------------------------------------------------------
-- Commands: staff
-- ---------------------------------------------------------------------------

-- The buckets around the player: { list = { "bx,by", ... } }.
function Commands.getBuckets(player, args)
	if type(args.list) ~= "table" then return end
	local s = state()
	local out = {}
	local count = 0
	for _, key in ipairs(args.list) do
		if type(key) == "string" and count < 64 then
			count = count + 1
			local tiles = {}
			for tile, _ in pairs(s.buckets[key] or {}) do table.insert(tiles, tile) end
			out[key] = tiles
		end
	end
	reply(player, "buckets", { data = out })
end

-- { x, y, z }. The client has seen cracks there; the server does not look
-- for them (whether its erosion lays them too is not proven), so the cost
-- of a false report is only the player's own materials.
function Commands.repair(player, args)
	local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
	if not x or not y or not z then return end
	x, y, z = math.floor(x), math.floor(y), math.floor(z)
	if math.abs(player:getX() - (x + 0.5)) > DelRoads.REACH or math.abs(player:getY() - (y + 0.5)) > DelRoads.REACH
		or math.floor(player:getZ()) ~= z then
		return notify(player, "IGUI_DelRoads_TooFar")
	end
	local why = DelRoads.whyNot(player, x, y) or DelRoads.missingMaterial(player)
	if why then return notify(player, why) end
	local square = getCell():getGridSquare(x, y, z)
	if not square or not square:getFloor() then return end
	local s = state()
	local bkey = DelRoads.bucketKey(DelRoads.bucketOf(x, y))
	local key = DelRoads.tileKey(x, y, z)
	local bucket = s.buckets[bkey]
	if bucket and bucket[key] then return notify(player, "IGUI_DelRoads_AlreadyDone") end
	if not bucket then
		bucket = {}
		s.buckets[bkey] = bucket
	end
	bucket[key] = crackDay()
	spend(s, player)
	local o = orders()
	local inOrders = DelRoads.ordersAt(player, x, y)
	for _, id in ipairs(inOrders) do
		local order = o.list[id]
		order.done = (order.done or 0) + 1
	end
	broadcast("repaired", { bucket = bkey, tile = key })
	if #inOrders > 0 then transmitOrders() end
end

-- ---------------------------------------------------------------------------
-- Commands: benches
-- ---------------------------------------------------------------------------

-- { x, y, z, recipe }: one run of a bench recipe. Anyone may use a bench;
-- what is checked is the bench, the power and the inputs.
function Commands.craft(player, args)
	local recipe = DelRoads.recipe(args.recipe)
	local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
	if not recipe or not x or not y or not z then return end
	if math.abs(player:getX() - (x + 0.5)) > DelRoads.REACH or math.abs(player:getY() - (y + 0.5)) > DelRoads.REACH
		or math.floor(player:getZ()) ~= math.floor(z) then
		return notify(player, "IGUI_DelRoads_TooFar")
	end
	local square = getCell():getGridSquare(x, y, z)
	local _, kind = DelRoads.benchAt(square)
	if kind ~= recipe.bench then return end
	if not DelRoads.hasPower(square) then return notify(player, "IGUI_DelRoads_NoPower") end
	local inventory = player:getInventory()
	if DelRoads.timesPossible(inventory, recipe) < 1 then return notify(player, "IGUI_DelRoads_NoInputs") end
	for _, input in ipairs(recipe.inputs) do
		for _, item in ipairs(DelRoads.inputItems(inventory, input)) do removeItem(player, item) end
	end
	for _, output in ipairs(recipe.outputs) do
		for _ = 1, output.count do
			local item = instanceItem(output.type)
			if item then
				inventory:AddItem(item)
				sendAddItemToContainer(inventory, item)
			end
		end
	end
	log(string.format("Craft: %s %s at %d,%d,%d", player:getUsername(), recipe.id, x, y, z))
end

-- ---------------------------------------------------------------------------
-- Commands: work orders
-- ---------------------------------------------------------------------------

local function orderLabel(id, order)
	return string.format("%s '%s'", tostring(id), tostring(order.title or ""))
end

-- The customer hall's mayor or an admin. { hall, title, price, x1, y1, x2, y2 }
function Commands.createOrder(player, args)
	local hall = DelEcon.getHall(DelEcon.getState(), args.hall)
	if not DelEcon.canManage(hall, player) then return end
	local x1, y1, x2, y2 = tonumber(args.x1), tonumber(args.y1), tonumber(args.x2), tonumber(args.y2)
	if not x1 or not y1 or not x2 or not y2 then return end
	local price = DelShops.parseAmount(args.price)
	if not price or price < 0 then return notify(player, "IGUI_DelRoads_BadPrice") end
	x1, x2 = math.floor(math.min(x1, x2)), math.floor(math.max(x1, x2))
	y1, y2 = math.floor(math.min(y1, y2)), math.floor(math.max(y1, y2))
	if x2 - x1 + 1 > DelRoads.ORDER_MAX_SIDE or y2 - y1 + 1 > DelRoads.ORDER_MAX_SIDE then
		return notify(player, "IGUI_DelRoads_OrderTooBig", DelRoads.ORDER_MAX_SIDE)
	end
	local o = orders()
	local id = tostring(o.nextId)
	o.nextId = o.nextId + 1
	o.list[id] = { hall = args.hall, title = string.sub(trim(args.title), 1, 60), x1 = x1, y1 = y1, x2 = x2, y2 = y2,
		price = DelShops.round(price), by = player:getUsername(), created = DelRoads.today(), done = 0,
		status = DelRoads.OPEN }
	log(string.format("Order %s: %s hall %s price %s %d,%d-%d,%d", orderLabel(id, o.list[id]), player:getUsername(),
		tostring(args.hall), tostring(price), x1, y1, x2, y2))
	transmitOrders()
	notify(player, "IGUI_DelRoads_OrderCreated", id)
end

-- Staff or mayor of another hall takes an open order for that hall. { id, hall }
function Commands.acceptOrder(player, args)
	local o = orders()
	local id = tostring(args.id or "")
	local order = o.list[id]
	if not order or order.status ~= DelRoads.OPEN then return notify(player, "IGUI_DelRoads_OrderTaken") end
	local allowed = false
	for _, hallId in ipairs(DelRoads.contractorHalls(order, player)) do
		if hallId == args.hall then allowed = true end
	end
	if not allowed then return end
	order.status = DelRoads.ACCEPTED
	order.contractor = args.hall
	order.acceptedBy = player:getUsername()
	order.done = 0
	log(string.format("Order %s: accepted by %s for hall %s", orderLabel(id, order), player:getUsername(),
		tostring(args.hall)))
	transmitOrders()
	reply(player, "accepted", { id = id })
end

-- The contractor gives an accepted order back: open again for anyone.
function Commands.refuseOrder(player, args)
	local o = orders()
	local id = tostring(args.id or "")
	local order = o.list[id]
	if not order or not DelRoads.isContractor(order, player) then return end
	log(string.format("Order %s: given back by %s (hall %s)", orderLabel(id, order), player:getUsername(),
		tostring(order.contractor)))
	order.status = DelRoads.OPEN
	order.contractor, order.acceptedBy = nil, nil
	transmitOrders()
end

-- The contractor reports the order done and is paid at once from the
-- customer's treasury; not enough there - nothing moves, the order stays
-- accepted and can be reported again later.
function Commands.completeOrder(player, args)
	local o = orders()
	local id = tostring(args.id or "")
	local order = o.list[id]
	if not order or not DelRoads.isContractor(order, player) then return end
	local price = DelShops.round(order.price or 0)
	if price > 0 then
		local note = "#" .. id
		if not DelEcon.hallTransfer or not DelEcon.hallTransfer(order.hall, order.contractor, price,
			player:getUsername(), note) then
			log(string.format("Order %s: %s reported done, customer hall %s cannot pay %s", orderLabel(id, order),
				player:getUsername(), tostring(order.hall), tostring(price)))
			return notify(player, "IGUI_DelRoads_CustomerCannotPay")
		end
	end
	order.status = DelRoads.DONE
	order.doneBy = player:getUsername()
	order.finished = DelRoads.today()
	log(string.format("Order %s: done by %s, hall %s paid %s by hall %s, %d tiles", orderLabel(id, order),
		player:getUsername(), tostring(order.contractor), tostring(price), tostring(order.hall), order.done or 0))
	transmitOrders()
	notify(player, "IGUI_DelRoads_OrderPaid", Currency.format(price))
end

-- The customer hall's mayor or an admin, any status.
function Commands.deleteOrder(player, args)
	local o = orders()
	local id = tostring(args.id or "")
	local order = o.list[id]
	if not order or not DelEcon.canManage(DelEcon.getHall(DelEcon.getState(), order.hall), player) then return end
	o.list[id] = nil
	log(string.format("Order %s: %s deleted (status %s)", orderLabel(id, order), player:getUsername(),
		tostring(order.status)))
	transmitOrders()
end

-- ---------------------------------------------------------------------------
-- Cracking again: once a game day, tiles whose day has come are dropped and
-- every client forgets them; their cracks come back the next time the
-- square loads.
-- ---------------------------------------------------------------------------

local function purge()
	local s = state()
	local today = DelRoads.today()
	if s.lastPurge == today then return end
	s.lastPurge = today
	local expired, count = {}, 0
	for bkey, bucket in pairs(s.buckets) do
		local tiles = {}
		local left = false
		for key, day in pairs(bucket) do
			if type(day) ~= "number" or day <= today then
				table.insert(tiles, key)
			else
				left = true
			end
		end
		for _, key in ipairs(tiles) do bucket[key] = nil end
		if not left then s.buckets[bkey] = nil end
		if #tiles > 0 then
			expired[bkey] = tiles
			count = count + #tiles
		end
	end
	if count > 0 then
		log(string.format("Cracked again: %d tiles", count))
		broadcast("expired", { data = expired })
	end
end

-- ---------------------------------------------------------------------------

local function onInitGlobalModData()
	state()
	orders()
end
Events.OnInitGlobalModData.Add(onInitGlobalModData)
Events.EveryHours.Add(purge)

local function onClientCommand(module, command, player, args)
	if module ~= MODULE then return end
	local handler = Commands[command]
	if not handler then return end
	handler(player, args or {})
end
Events.OnClientCommand.Add(onClientCommand)
