#!/bin/sh
# Renders the 16 bench frames from the Meshy models (art/meshy/*.glb) into
# art/frames (128x256), then the tile pack is built from art/tiles.json:
#   powershell -File E:\mods\tools\TilePack\build-tilepack.ps1 -Spec tiles.json -Media <mod>\42\media
# Index = bench * 4 + facing (S, E, N, W); foot = footprint in tile units.
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
A="E:/mods/Delirium-Roads/art"
i=0
for spec in crusher:0.92 kiln:0.9 mill:1.0 kettle:1.0; do
	kind=${spec%%:*}; foot=${spec##*:}
	for r in 0 90 180 270; do
		"$B" --background --factory-startup --python "$A/render_meshy.py" -- "$A/meshy/$kind.glb" $r "$A/raw/m/delroads_01_$i.png" $foot 2>&1 | grep -E "RENDERED|Error"
		i=$((i + 1))
	done
done
python -c "
from PIL import Image
for i in range(16):
    Image.open(r'$A/raw/m/delroads_01_%d.png' % i).resize((128, 256), Image.LANCZOS).save(r'$A/frames/delroads_01_%d.png' % i)
"
