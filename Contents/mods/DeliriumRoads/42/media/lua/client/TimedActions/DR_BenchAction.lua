-- Delirium Roads - one run of a bench recipe (crusher, kiln, ball mill,
-- asphalt kettle). A client-side timer like DR_RepairAction: perform() asks
-- the server, which checks the bench, the power and the inputs again and
-- swaps the items.

if isServer() then return end

require "TimedActions/ISBaseTimedAction"
require "DR_Client"
require "DR_Benches"

DR_BenchAction = ISBaseTimedAction:derive("DR_BenchAction")

function DR_BenchAction:isValid()
	local _, kind = DelRoads.benchAt(self.square)
	return kind == self.recipe.bench and DelRoads.hasPower(self.square)
		and DelRoads.timesPossible(self.character:getInventory(), self.recipe) >= 1
end

function DR_BenchAction:waitToStart()
	self.character:faceLocation(self.square:getX(), self.square:getY())
	return self.character:shouldBeTurning()
end

function DR_BenchAction:update()
	self.character:faceLocation(self.square:getX(), self.square:getY())
	self.character:setMetabolicTarget(Metabolics.LightWork)
end

function DR_BenchAction:start()
	self:setActionAnim("Loot")
	self.character:SetVariable("LootPosition", "Mid")
end

function DR_BenchAction:stop()
	ISBaseTimedAction.stop(self)
end

function DR_BenchAction:perform()
	DelRoads.send("craft", { x = self.square:getX(), y = self.square:getY(), z = self.square:getZ(),
		recipe = self.recipe.id })
	-- needed to remove from queue / start next.
	ISBaseTimedAction.perform(self)
end

function DR_BenchAction:getDuration()
	if self.character:isTimedActionInstant() then return 1 end
	return self.recipe.time
end

function DR_BenchAction:new(character, square, recipe)
	local o = ISBaseTimedAction.new(self, character)
	o.square = square
	o.recipe = recipe
	o.maxTime = o:getDuration()
	return o
end
