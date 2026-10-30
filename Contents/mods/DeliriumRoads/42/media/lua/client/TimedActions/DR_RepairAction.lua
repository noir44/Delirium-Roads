-- Delirium Roads - mending the cracks of one road tile.
--
-- A client-side timer like the vanilla info actions (no complete()): when
-- it ends, perform() asks the server, which checks rights and materials,
-- spends them and tells every client to strip the cracks.

if isServer() then return end

require "TimedActions/ISBaseTimedAction"
require "DR_Client"

DR_RepairAction = ISBaseTimedAction:derive("DR_RepairAction")

function DR_RepairAction:isValid()
	local square = self.square
	return square ~= nil and DelRoads.hasCracks(square)
		and not DelRoads.isMended(square:getX(), square:getY(), square:getZ())
		and DelRoads.missingMaterial(self.character) == nil
end

function DR_RepairAction:waitToStart()
	self.character:faceLocation(self.square:getX(), self.square:getY())
	return self.character:shouldBeTurning()
end

function DR_RepairAction:update()
	self.character:faceLocation(self.square:getX(), self.square:getY())
	self.character:setMetabolicTarget(Metabolics.MediumWork)
end

function DR_RepairAction:start()
	self:setActionAnim("Loot")
	self.character:SetVariable("LootPosition", "Low")
	self.sound = self.character:playSound("Plastering")
end

function DR_RepairAction:stop()
	if self.sound then self.character:stopOrTriggerSound(self.sound) end
	ISBaseTimedAction.stop(self)
end

function DR_RepairAction:perform()
	if self.sound then self.character:stopOrTriggerSound(self.sound) end
	DelRoads.send("repair", { x = self.square:getX(), y = self.square:getY(), z = self.square:getZ() })
	-- needed to remove from queue / start next.
	ISBaseTimedAction.perform(self)
end

function DR_RepairAction:getDuration()
	if self.character:isTimedActionInstant() then return 1 end
	return DelRoads.repairTime()
end

function DR_RepairAction:new(character, square)
	local o = ISBaseTimedAction.new(self, character)
	o.square = square
	o.maxTime = o:getDuration()
	o.caloriesModifier = 4
	return o
end
