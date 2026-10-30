# Delirium Roads

Build 42 mod for the Delirium server. Requires **Delirium Economy** (and through it Delirium Shops).

City Hall staff mend the roads that four years of erosion have cracked.

- Right-click a cracked road tile: **Mend the cracks**, or **Mend the cracks around** for the 5x5 tiles around it.
- Needs a mason's trowel, a bag of cement and a bag of gravel; one bag of each lasts 25 tiles (sandbox `TilesPerBag`).
- Staff, mayors and admins may mend. Staff are paid their monthly salary by Delirium Economy.
- A mended tile cracks again after about `RepairLastsDays` game days (120 by default, give or take a quarter).
- **Road work orders** are paid contracts between City Halls. The customer hall's mayor marks the area from the context menu (first corner, second corner, title, price). Staff or the mayor of another hall (the contractor) accept it, mend the roads and press **Done**: the price goes at once from the customer's treasury to the contractor's (if the treasury can't pay, the order stays in progress). The contractor's mayor pays the staff as usual.
- An accepted order's area is outlined on the ground and on the world map (Show the area / On the map in the orders window).
- With `RequireOrder` on, staff mend only inside an order their City Hall has accepted.

## Sandbox options (page DelRoads)

| Option | Default | |
|---|---|---|
| `TilesPerBag` | 25 | tiles per bag of cement and bag of gravel |
| `RepairLastsDays` | 120 | game days until a mended tile cracks again |
| `RequireOrder` | false | mend only inside work orders |
| `RepairTime` | 150 | length of the action, in action ticks |
