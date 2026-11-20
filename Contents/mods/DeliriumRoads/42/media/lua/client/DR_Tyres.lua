-- Delirium Roads - cracked asphalt wears the tyres. The driver's client looks
-- at the square under the car twice a second; on a crack, at speed, it rolls
-- the chance and asks the server to take a point off one tyre. Mended tiles
-- have no crack sprite (DR_Client strips it), so they are safe.
--
-- The client decides: the cracks it sees are the ones laid by its own
-- erosion, and the server has no reliable copy of them. It only harms the
-- sender's own car.

if isServer() then return end

require "DR_Shared"

local CHECK_MS = 500
local nextCheck = 0

local function onTick()
	local now = getTimestampMs()
	if now < nextCheck then return end
	nextCheck = now + CHECK_MS
	if not DelRoads.tyreWearOn() then return end
	local player = getPlayer()
	local vehicle = player and player:getVehicle()
	if not vehicle or not vehicle:isDriver(player) then return end
	local speed = math.abs(vehicle:getCurrentSpeedKmHour())
	if speed < DelRoads.TYRE_MIN_SPEED then return end
	if not DelRoads.hasCracks(vehicle:getSquare()) then return end
	if ZombRandFloat(0, 1) < DelRoads.tyreWearChance(speed) then DelRoads.send("tyreWear", {}) end
end
Events.OnTick.Add(onTick)
