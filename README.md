# Delirium Roads

Build 42 mod for the Delirium server. Requires **Delirium Economy** (and through it Delirium Shops).

City Hall staff mend the roads that four years of erosion have cracked.

- Right-click a cracked road tile: **Mend the cracks**, or **Mend the cracks around** for the 5x5 tiles around it.
- Needs a mason's trowel and a bag of **asphalt mix** (25 tiles a bag; the bar shows what is left).

## Road works benches

Built in the crafting menu (tab *Road works*, welding: blowtorch and mask), placed like any furniture, four facings. They work only with **electricity** on their square: a generator in range, or the grid indoors. Right-click a bench for its recipes ("all" queues as many runs as you can afford).

| Bench | Recipe |
|---|---|
| Stone crusher | boulder + empty sack, or 6 stones + empty sack -> gravel bag |
| Electric kiln | 2 limestone + clay -> 2 clinker; any car tyre -> bitumen |
| Ball mill | 3 clinker + empty sack -> bag of cement |
| Asphalt kettle | full gravel bag + cement + bitumen + empty sack -> 2 bags of asphalt mix |

Bitumen comes from car tyres rendered in the kiln (abandoned cars have them everywhere); it is also found in concrete, gravel and masonry crates and construction workers' toolboxes.

- Staff, mayors and admins may mend. Staff are paid their monthly salary by Delirium Economy.
- A mended tile cracks again after about `RepairLastsDays` game days (120 by default, give or take a quarter).
- **Road work orders** are paid contracts between City Halls. The customer hall's mayor marks the area from the context menu (first corner, second corner, title, price). Staff or the mayor of another hall (the contractor) accept it, mend the roads and press **Done**: the price goes at once from the customer's treasury to the contractor's (if the treasury can't pay, the order stays in progress). The contractor's mayor pays the staff as usual.
- An accepted order's area is outlined on the ground and on the world map (Show the area / On the map in the orders window).
- With `RequireOrder` on, staff mend only inside an order their City Hall has accepted.

## Sandbox options (page DelRoads)

| Option | Default | |
|---|---|---|
| `RepairLastsDays` | 120 | game days until a mended tile cracks again |
| `RequireOrder` | false | mend only inside work orders |
| `RepairTime` | 150 | length of the action, in action ticks |
