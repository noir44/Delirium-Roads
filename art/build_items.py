# Meshy GLBs of the materials (art/meshy/item_*.glb, from art/concept/item_*.jpg) -> PZ world
# meshes, textures, model script, previews. Mesh conversion is Delirium-Terminal/tools/pz_part.py.
#   python art/build_items.py
import os
import subprocess

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
MEDIA = os.path.join(ROOT, "Contents", "mods", "DeliriumRoads", "42", "media")
SRC = os.path.join(ROOT, "art", "meshy")
PZ_PART = r"E:\mods\Delirium-Terminal\tools\pz_part.py"
BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"

# model: glb, longest side m, height m, triangles. Real sizes lying on the floor.
SIZE = {
    "AsphaltMix": ("item_asphaltmix", 0.60, 0.22, 1200),
    "Bitumen": ("item_bitumen", 0.25, 0.11, 600),
    "Clinker": ("item_clinker", 0.18, 0.08, 1000),
}

mesh_dir = os.path.join(MEDIA, "models_X", "WorldItems")
tex_dir = os.path.join(MEDIA, "textures", "WorldItems")
prev_dir = os.path.join(SRC, "preview")
for d in (mesh_dir, tex_dir, prev_dir):
    os.makedirs(d, exist_ok=True)

script = ["module DelRoads", "{"]
for name, (glb, longest, height, tris) in SIZE.items():
    out = subprocess.run([BLENDER, "-b", "-P", PZ_PART, "--", os.path.abspath(os.path.join(SRC, glb + ".glb")),
                          os.path.abspath(os.path.join(mesh_dir, "DR_" + name + ".fbx")),
                          os.path.abspath(os.path.join(tex_dir, "DR_" + name + ".png")),
                          str(longest), str(height), str(tris), "keep",
                          os.path.abspath(os.path.join(prev_dir, name + ".png"))],
                         capture_output=True, text=True)
    line = [l for l in out.stdout.splitlines() if l.startswith("PART")]
    print(name, line[0] if line else "FAILED\n" + out.stdout[-1500:] + out.stderr[-1500:])
    # Node scale 100 (Blender's export), vertices in metres -> script scale 0.01.
    script += ["    model DR_%s" % name, "    {",
               "        mesh = WorldItems/DR_%s," % name,
               "        texture = WorldItems/DR_%s," % name,
               "        scale = 0.01,", "    }", ""]
script[-1] = "}"
with open(os.path.join(MEDIA, "scripts", "DR_Models.txt"), "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(script) + "\n")
