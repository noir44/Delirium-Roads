# Delirium Roads

Build 42 mod for the Delirium server. Requires **Delirium Economy** (and through it Delirium Shops).

City Hall staff mend the roads that four years of erosion have cracked.

- Right-click a cracked road tile: **Mend the cracks** turns on a cursor, like chopping trees: every left click on a cracked tile queues a repair there, right click or Esc ends it.
- Needs a mason's trowel and a bag of **asphalt mix** (15 tiles a bag; the bar shows what is left).
- **Laying asphalt**: build menu, *Outdoors* - *Asphalt*, next to the gravel floor. A mason's trowel and 3 uses of a bag of mix per tile; anyone can lay it.
- Pallets of asphalt mix hold 18, 12 or 6 bags (three layers, two, one): pallet + 2 ropes + the bags, only full bags.

## Road works benches

Built in the crafting menu (tab *Road works*, welding: blowtorch and mask), placed like any furniture, four facings. They work only with **electricity** on their square: a generator in range, or the grid indoors. Right-click a bench for its recipes ("all" queues as many runs as you can afford). Materials are taken from your inventory first, then from crates and the floor on the squares around the bench; the products go to your inventory.

| Bench | Recipe |
|---|---|
| Stone crusher | boulder + empty sack, or 6 stones + empty sack -> gravel bag (any empty sack a shovel can fill) |
| Electric kiln | 2 limestone + clay -> 2 clinker; any car tyre -> bitumen |
| Ball mill | 3 clinker -> bag of cement |
| Asphalt kettle | full gravel bag + cement + bitumen + empty sack -> 2 bags of asphalt mix |

Bitumen comes from car tyres rendered in the kiln (abandoned cars have them everywhere); it is also found in concrete, gravel and masonry crates and construction workers' toolboxes.

- Staff, mayors and admins may mend. Staff are paid their monthly salary by Delirium Economy.
- A mended tile cracks again after about `RepairLastsDays` game days (120 by default, give or take a quarter).
- **Road work orders** are paid contracts between City Halls. The customer hall's mayor marks the area from the context menu - two corners on the ground, or **on the world map** (two clicks) - then a title and a price; a side may be up to 1000 tiles. Staff or the mayor of another hall (the contractor) accept it, mend the roads and press **Done**: the price goes at once from the customer's treasury to the contractor's (if the treasury can't pay, the order stays in progress). The contractor's mayor pays the staff as usual.
- An accepted order's area is outlined on the ground and on the world map (Show the area / On the map in the orders window).
- An organization may have at most `MaxOrdersPerHall` orders in progress (2 by default); it takes the next one after reporting one done or giving it back.
- With `RequireOrder` on, staff mend only inside an order their City Hall has accepted.

## Sandbox options (page DelRoads)

| Option | Default | |
|---|---|---|
| `RepairLastsDays` | 120 | game days until a mended tile cracks again |
| `RequireOrder` | false | mend only inside work orders |
| `MaxOrdersPerHall` | 2 | work orders one organization may have in progress at once (0 = no limit) |
| `RepairTime` | 150 | length of the action, in action ticks |
