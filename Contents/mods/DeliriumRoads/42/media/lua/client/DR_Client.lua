-- Delirium Roads - client: the copy of mended tiles around the player, the
-- cracks stripped from them, the work orders copy and the context menu.
--
-- Erosion lays the crack sprite on the client every time a square loads
-- (ErosionMain.LoadGridsquare has no client guard, checked with javap), and
-- IsoChunk.doLoadGridsquare fires the Lua LoadGridsquare event right after
-- it. So a mended square is stripped in that event, and disableErosion()
-- keeps erosion from laying it again while the square stays loaded.

if isServer() then return end

require "DR_Shared"
require "DE_Client"

local MODULE = DelRoads.MODULE

function DelRoads.send(command, args)
	local player = getPlayer()
	if not player then return end
	sendClientCommand(player, MODULE, command, args or {})
end

-- Windows register here to be refreshed when the orders change.
DelRoads.windows = DelRoads.windows or {}

local function refreshWindows()
	for _, window in pairs(DelRoads.windows) do
		if window.refresh then window:refresh() end
	end
end

-- ---------------------------------------------------------------------------
-- Mended tiles around the player
-- ---------------------------------------------------------------------------

-- cache[bucketKey] = { ["x,y,z"] = true }; pending[bucketKey] = request time.
local cache = {}
local pending = {}
-- Buckets this far from the player (in tiles) are asked for, twice that
-- are forgotten. A client loads about 100 tiles around the player.
local RADIUS = 150
local RETRY_MS = 30000

local function strip(square)
	local floor = square:getFloor()
	if not floor then return end
	square:disableErosion()
	local index = DelRoads.crackIndex(floor)
	while index do
		floor:RemoveAttachedAnim(index)
		index = DelRoads.crackIndex(floor)
	end
end

function DelRoads.isMended(x, y, z)
	local bucket = cache[DelRoads.bucketKey(DelRoads.bucketOf(x, y))]
	return bucket ~= nil and bucket[DelRoads.tileKey(x, y, z)] == true
end

-- nil while the bucket has not arrived: the menu waits rather than offer
-- a tile that may be mended already.
function DelRoads.bucketLoaded(x, y)
	return cache[DelRoads.bucketKey(DelRoads.bucketOf(x, y))] ~= nil
end

local function stripLoaded(key)
	local x, y, z = DelRoads.parseTileKey(key)
	if not x then return end
	local square = getCell():getGridSquare(x, y, z)
	if square then strip(square) end
end

local function onLoadGridsquare(square)
	local bucket = cache[DelRoads.bucketKey(DelRoads.bucketOf(square:getX(), square:getY()))]
	if not bucket then return end
	if bucket[DelRoads.tileKey(square:getX(), square:getY(), square:getZ())] then strip(square) end
end
Events.LoadGridsquare.Add(onLoadGridsquare)

local function requestAround()
	if not isClient() then return end
	local player = getPlayer()
	if not player then return end
	local px, py = player:getX(), player:getY()
	local bx1, by1 = DelRoads.bucketOf(px - RADIUS, py - RADIUS)
	local bx2, by2 = DelRoads.bucketOf(px + RADIUS, py + RADIUS)
	local now = getTimestampMs()
	local list = {}
	for bx = bx1, bx2 do
		for by = by1, by2 do
			local key = DelRoads.bucketKey(bx, by)
			if not cache[key] and (not pending[key] or now - pending[key] > RETRY_MS) then
				pending[key] = now
				table.insert(list, key)
			end
		end
	end
	-- Far buckets: their squares are not loaded, they are asked for again
	-- when the player comes back.
	local size = DelRoads.BUCKET
	for key, _ in pairs(cache) do
		local bx, by = string.match(key, "^(-?%d+),(-?%d+)$")
		bx, by = tonumber(bx), tonumber(by)
		if bx and (math.abs((bx + 0.5) * size - px) > RADIUS * 2 + size
			or math.abs((by + 0.5) * size - py) > RADIUS * 2 + size) then
			cache[key] = nil
		end
	end
	if #list > 0 then DelRoads.send("getBuckets", { list = list }) end
end
Events.OnGameStart.Add(requestAround)
Events.EveryOneMinute.Add(requestAround)

-- ---------------------------------------------------------------------------
-- Work orders: read-only copy of the server's ModData
-- ---------------------------------------------------------------------------

local ordersReceived = false

local function requestOrders()
	if not isClient() or ordersReceived then return end
	ModData.request(DelRoads.ORDERS_KEY)
end

local function retryOrders()
	if ordersReceived then
		Events.EveryOneMinute.Remove(retryOrders)
		return
	end
	requestOrders()
end

Events.OnGameStart.Add(requestOrders)
Events.OnCreatePlayer.Add(function() requestOrders() end)
Events.EveryOneMinute.Add(retryOrders)

local function onReceiveGlobalModData(key, data)
	if key ~= DelRoads.ORDERS_KEY or type(data) ~= "table" then return end
	ModData.remove(key)
	ModData.add(key, data)
	ordersReceived = true
	refreshWindows()
end
Events.OnReceiveGlobalModData.Add(onReceiveGlobalModData)

-- ---------------------------------------------------------------------------
-- Server replies
-- ---------------------------------------------------------------------------

local Replies = {}

function Replies.notify(args)
	local player = getPlayer()
	if not player or type(args.key) ~= "string" then return end
	local text
	if args.arg1 ~= nil then
		text = getText(args.key, tostring(args.arg1))
	else
		text = getText(args.key)
	end
	player:setHaloNote(text, 255, 255, 255, 300)
end

-- { data = { ["bx,by"] = { "x,y,z", ... } } }
function Replies.buckets(args)
	if type(args.data) ~= "table" then return end
	for bkey, tiles in pairs(args.data) do
		local bucket = {}
		for _, key in ipairs(tiles) do
			bucket[key] = true
			stripLoaded(key)
		end
		cache[bkey] = bucket
		pending[bkey] = nil
	end
end

-- Sent to everyone; only a bucket we hold matters.
function Replies.repaired(args)
	local bucket = cache[args.bucket or ""]
	if bucket then bucket[args.tile] = true end
	stripLoaded(args.tile)
end

-- The cracks come back the next time those squares load.
function Replies.expired(args)
	if type(args.data) ~= "table" then return end
	for bkey, tiles in pairs(args.data) do
		local bucket = cache[bkey]
		if bucket then
			for _, key in ipairs(tiles) do bucket[key] = nil end
		end
	end
end

local function onServerCommand(module, command, args)
	if module ~= MODULE then return end
	local handler = Replies[command]
	if handler then handler(args or {}) end
end
Events.OnServerCommand.Add(onServerCommand)
