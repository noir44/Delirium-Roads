-- Delirium Roads - picking cracked tiles to mend one by one, like vanilla's
-- tree chopping (ISChopTreeCursor): "Mend cracks" on a crack starts the
-- cursor, every left click on a cracked tile queues a repair there, right
-- click or Esc ends it. Queued tiles stay marked until mended.
--
-- Client code, but it lives in server/: it derives ISBuildingObject, a
-- vanilla server/ file, which client/ cannot require when connecting to a
-- server (see E:\mods\CLAUDE.md).

if isServer() then return end

require "BuildingObjects/ISBuildingObject"

DR_RepairCursor = ISBuildingObject:derive("DR_RepairCursor")

local function keyOf(square)
	return DelRoads.tileKey(square:getX(), square:getY(), square:getZ())
end

function DR_RepairCursor:create(x, y, z, north, sprite)
	local square = getCell():getGridSquare(x, y, z)
	if not self:isValid(square) then return end
	if luautils.walkAdj(self.character, square, true) then
		ISTimedActionQueue.add(DR_RepairAction:new(self.character, square))
		self.queued[keyOf(square)] = square
	end
end

function DR_RepairCursor:isValid(square)
	if not square or self.queued[keyOf(square)] then return false end
	if not DelRoads.canMend(square) then return false end
	return DelRoads.whyNot(self.character, square:getX(), square:getY()) == nil
		and DelRoads.missingMaterial(self.character) == nil
end

function DR_RepairCursor:render(x, y, z, square)
	if self.character:getVehicle() then
		getCell():setDrag(nil, self.player)
		return
	end
	-- Queued tiles: forget them once mended or when the queue was cancelled.
	local busy = ISTimedActionQueue.hasActionType(self.character, "DR_RepairAction")
	local done = {}
	for key, sq in pairs(self.queued) do
		if not busy or DelRoads.isMended(sq:getX(), sq:getY(), sq:getZ()) then
			table.insert(done, key)
		else
			self:getFloorCursorSprite():RenderGhostTileColor(sq:getX(), sq:getY(), sq:getZ(), 1.0, 0.75, 0.1, 0.6)
		end
	end
	for _, key in ipairs(done) do self.queued[key] = nil end

	local hc = getCore():getBadHighlitedColor()
	if square and self:isValid(square) then hc = getCore():getGoodHighlitedColor() end
	self:getFloorCursorSprite():RenderGhostTileColor(x, y, z, hc:getR(), hc:getG(), hc:getB(), 0.8)
end

function DR_RepairCursor:getAPrompt()
	if self.canBeBuild then return getText("IGUI_DelRoads_Repair") end
	return nil
end

function DR_RepairCursor:new(character)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o:init()
	o:setSprite("")
	o:setNorthSprite("")
	o.character = character
	o.player = character:getPlayerNum()
	o.noNeedHammer = true
	o.skipBuildAction = true
	-- The base class would walk there first with luautils.walkAdj, which
	-- clears the queue; create() walks itself and keeps it.
	o.skipWalk2 = true
	o.queued = {}
	return o
end
