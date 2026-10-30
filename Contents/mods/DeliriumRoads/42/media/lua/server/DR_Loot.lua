-- Delirium Roads - bitumen in the loot: the binder of the asphalt mix has no
-- recipe, it is found where building materials are (vanilla's concrete
-- powder is only in CrateConcrete).

require "Items/ProceduralDistributions"

local LOOT = {
	CrateConcrete = 10,
	CrateGravelBags = 10,
	CrateMasonry = 6,
	ConstructionWorkerTools = 4,
	GarageTools = 1,
}

local function addLoot()
	for list, weight in pairs(LOOT) do
		local entry = ProceduralDistributions.list[list]
		if entry and entry.items then
			table.insert(entry.items, "DelRoads.Bitumen")
			table.insert(entry.items, weight)
		end
	end
end
Events.OnPreDistributionMerge.Add(addLoot)
