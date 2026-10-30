# Renders a Meshy GLB as a PZ 2x tile frame (128x256), rendered at 4x.
#   blender --background --factory-startup --python render_meshy.py -- <model.glb> <rotation_deg> <out.png> [foot] [max_h]
#
# The model is centred on the tile, its base put on the floor and scaled so
# its footprint (at any of the four facings) fits `foot` tile units (default
# 0.92), its height capped at `max_h` units. Camera and light as
# render_bench.py (and Delirium-Casino/art/render_table.py): orthographic
# 2:1 dimetric, 128 px = tile diagonal, tile centre 96 px below the frame
# centre. Blender -Y is PZ south; rotation 0 must leave the front at -Y
# (per-model yaw is in build_benches.py).
import bpy, sys, math, os
from mathutils import Vector, Euler, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
glb = os.path.abspath(argv[0])
rot = math.radians(float(argv[1]))
out = os.path.abspath(argv[2])
FOOT = float(argv[3]) if len(argv) > 3 else 0.92
MAX_H = float(argv[4]) if len(argv) > 4 else 1.7
SCALE = 4
PX_PER_UNIT = 128 / math.sqrt(2)

sc = bpy.context.scene
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)

bpy.ops.import_scene.gltf(filepath=glb)
meshes = [o for o in sc.objects if o.type == "MESH"]
root = bpy.data.objects.new("Bench", None)
sc.collection.objects.link(root)

# world-space bounds of every mesh vertex
pts = []
for o in meshes:
    for v in o.data.vertices:
        pts.append(o.matrix_world @ v.co)
mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
size = mx - mn
s = min(FOOT / max(size.x, size.y), MAX_H / size.z)
centre = Matrix.Translation(Vector((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z)))
fit = Matrix.Scale(s, 4) @ centre
for o in meshes:
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = fit @ mw
    o.parent = root
    for slot in o.material_slots:
        m = slot.material
        if m and m.node_tree:
            bsdf = m.node_tree.nodes.get("Principled BSDF")
            if bsdf:
                bsdf.inputs["Roughness"].default_value = 0.75
                bsdf.inputs["Metallic"].default_value = 0.15
for o in [o for o in sc.objects if o.type != "MESH" and o is not root]:
    bpy.data.objects.remove(o, do_unlink=True)
root.rotation_euler = (0, 0, rot)
print("FIT size", tuple(round(c * s, 3) for c in size))

cam_data = bpy.data.cameras.new("Cam")
cam_data.type = "ORTHO"
cam_data.sensor_fit = "VERTICAL"
cam_data.ortho_scale = 256 / PX_PER_UNIT
cam_data.shift_y = 96 / 256
cam = bpy.data.objects.new("Cam", cam_data)
sc.collection.objects.link(cam)
cam.rotation_euler = Euler((math.radians(60), 0, math.radians(45)))
fwd = cam.rotation_euler.to_matrix() @ Vector((0, 0, -1))
right = cam.rotation_euler.to_matrix() @ Vector((1, 0, 0))
up = cam.rotation_euler.to_matrix() @ Vector((0, 1, 0))
cam.location = -fwd * 20
sc.camera = cam

sun_data = bpy.data.lights.new("Sun", "SUN")
sun_data.energy = 3.8
sun = bpy.data.objects.new("Sun", sun_data)
sc.collection.objects.link(sun)
frm = (-right * 0.7 + up * 0.9 - fwd * 0.5).normalized()
sun.rotation_euler = (-frm).to_track_quat("-Z", "Y").to_euler()

world = bpy.data.worlds.new("W")
sc.world = world
try:
    world.use_nodes = True
except Exception:
    pass
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.15

r = sc.render
r.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 48
r.resolution_x = 128 * SCALE
r.resolution_y = 256 * SCALE
r.resolution_percentage = 100
r.film_transparent = True
r.image_settings.file_format = "PNG"
r.image_settings.color_mode = "RGBA"
sc.view_settings.view_transform = "Standard"
r.filepath = out
bpy.ops.render.render(write_still=True)
print("RENDERED", out)
