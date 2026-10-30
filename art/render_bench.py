# Renders one road-works bench as a PZ 2x tile frame (128x256), rendered at 4x.
#   blender --background --factory-startup --python render_bench.py -- <kind> <rotation_deg> <out.png>
# kind: crusher | kiln | mill | kettle
#
# Camera as Delirium-Casino/art/render_table.py: orthographic, 2:1 dimetric
# (elevation 30, azimuth 45), 128 px = tile diagonal, tile centre 96 px below
# the frame centre. Blender -Y is PZ south: a model faces -Y at rotation 0
# (Facing S); +90 turns it to face +X (E), 180 N, 270 W.
import bpy, sys, math, os
from mathutils import Vector, Euler

argv = sys.argv[sys.argv.index("--") + 1:]
kind = argv[0]
rot = math.radians(float(argv[1]))
out = os.path.abspath(argv[2])
SCALE = 4
PX_PER_UNIT = 128 / math.sqrt(2)

sc = bpy.context.scene
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)


def material(name, color, rough=0.55, metal=0.3, grime=0.35, emit=None):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    # paint darkened by noise grime
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 9.0
    noise.inputs["Detail"].default_value = 8.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (color[0] * (1 - grime), color[1] * (1 - grime), color[2] * (1 - grime), 1)
    ramp.color_ramp.elements[1].position = 0.7
    ramp.color_ramp.elements[1].color = (*color, 1)
    coord = nt.nodes.new("ShaderNodeTexCoord")
    nt.links.new(coord.outputs["Object"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1)
        bsdf.inputs["Emission Strength"].default_value = 4.0
    return m


root = bpy.data.objects.new("Bench", None)
sc.collection.objects.link(root)


def add(obj, mat):
    obj.data.materials.append(mat)
    obj.parent = root
    return obj


def box(sx, sy, sz, x, y, z, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, z))
    o = bpy.context.object
    o.scale = (sx, sy, sz)
    return add(o, mat)


def cyl(r, depth, x, y, z, mat, axis="z", verts=32):
    rotation = {"z": (0, 0, 0), "x": (0, math.pi / 2, 0), "y": (math.pi / 2, 0, 0)}[axis]
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, vertices=verts, location=(x, y, z), rotation=rotation)
    return add(bpy.context.object, mat)


def frustum(r1, r2, depth, x, y, z, mat, verts=4):
    bpy.ops.mesh.primitive_cone_add(radius1=r1, radius2=r2, depth=depth, vertices=verts, location=(x, y, z),
                                    rotation=(0, 0, math.pi / 4))
    return add(bpy.context.object, mat)


steel = material("Steel", (0.18, 0.19, 0.2), rough=0.45, metal=0.8)
rust = material("Rust", (0.32, 0.17, 0.08), rough=0.85, metal=0.2, grime=0.5)
yellow = material("Yellow", (0.75, 0.52, 0.05), rough=0.5, metal=0.2)
motor = material("Motor", (0.16, 0.3, 0.2), rough=0.5, metal=0.4)
enamel = material("Enamel", (0.62, 0.6, 0.55), rough=0.4, metal=0.1, grime=0.25)
blue = material("Blue", (0.12, 0.22, 0.38), rough=0.5, metal=0.4)
black = material("Black", (0.035, 0.035, 0.035), rough=0.3, metal=0.1, grime=0.1)
red = material("Lamp", (0.6, 0.05, 0.02), emit=(1.0, 0.15, 0.05))
green = material("LampG", (0.05, 0.5, 0.1), emit=(0.2, 1.0, 0.25))

if kind == "crusher":
    # jaw crusher: yellow body on a steel skid, hopper, flywheels, motor, chute
    box(0.86, 0.7, 0.1, 0, 0, 0.05, steel)
    box(0.5, 0.52, 0.62, 0, 0.02, 0.41, yellow)
    frustum(0.34, 0.56, 0.34, 0, 0.02, 0.89, yellow)
    box(0.36, 0.36, 0.02, 0, 0.02, 1.055, black)       # hopper mouth
    for sx in (-1, 1):
        cyl(0.27, 0.06, sx * 0.31, 0.06, 0.52, rust, axis="x")
        cyl(0.05, 0.1, sx * 0.31, 0.06, 0.52, steel, axis="x")
    box(0.38, 0.06, 0.2, 0, -0.29, 0.22, steel)         # chute
    box(0.3, 0.12, 0.04, 0, -0.33, 0.12, rust)
    cyl(0.12, 0.3, 0.0, 0.3, 0.24, motor, axis="x")      # motor at the back
    box(0.12, 0.08, 0.1, 0.25, -0.22, 0.6, black)       # switch box
    box(0.03, 0.01, 0.03, 0.25, -0.265, 0.62, red)
elif kind == "kiln":
    # electric kiln: enamel cabinet, door, control panel, vent pipe
    box(0.78, 0.66, 0.06, 0, 0, 0.03, steel)
    box(0.72, 0.6, 0.98, 0, 0.02, 0.55, enamel)
    box(0.5, 0.03, 0.62, -0.06, -0.29, 0.5, steel)     # door
    box(0.04, 0.05, 0.22, 0.17, -0.32, 0.52, black)    # handle
    box(0.16, 0.04, 0.34, 0.26, -0.29, 0.78, black)    # control panel
    cyl(0.04, 0.02, 0.26, -0.315, 0.86, enamel, axis="y")
    box(0.03, 0.01, 0.03, 0.26, -0.315, 0.74, red)
    box(0.03, 0.01, 0.03, 0.26, -0.315, 0.68, green)
    cyl(0.07, 0.42, -0.18, 0.12, 1.25, rust)           # vent pipe
    cyl(0.1, 0.05, -0.18, 0.12, 1.48, rust)
    for i in range(4):                                  # vent slots
        box(0.3, 0.01, 0.02, -0.06, -0.31, 0.92 - i * 0.04, black)
elif kind == "mill":
    # ball mill: horizontal drum on two pedestals, ring gear, motor
    for sx in (-1, 1):
        box(0.12, 0.42, 0.42, sx * 0.34, 0, 0.21, steel)
    cyl(0.3, 0.62, 0, 0, 0.62, blue, axis="x", verts=40)
    cyl(0.34, 0.05, 0.12, 0, 0.62, rust, axis="x", verts=48)   # ring gear
    for sx in (-1, 1):
        cyl(0.1, 0.12, sx * 0.36, 0, 0.62, steel, axis="x")
    box(0.18, 0.02, 0.14, -0.08, -0.29, 0.66, steel)           # hatch
    cyl(0.11, 0.26, 0.2, 0.34, 0.16, motor, axis="x")          # motor behind
    box(0.12, 0.08, 0.1, -0.3, -0.25, 0.08, black)
    box(0.03, 0.01, 0.03, -0.3, -0.295, 0.1, red)
elif kind == "kettle":
    # electric asphalt kettle: tar-stained tank on a frame, lid, spout, control box
    box(0.84, 0.66, 0.08, 0, 0, 0.18, steel)
    for sx in (-1, 1):
        for sy in (-1, 1):
            cyl(0.07, 0.04, sx * 0.34, sy * 0.25, 0.07, black, axis="x")
    cyl(0.33, 0.62, 0, 0.03, 0.54, black, verts=40)
    cyl(0.35, 0.06, 0, 0.03, 0.86, rust, verts=40)
    cyl(0.25, 0.04, 0, 0.03, 0.9, steel, verts=40)             # lid
    box(0.04, 0.2, 0.04, 0, 0.03, 0.94, black)                 # lid handle
    cyl(0.05, 0.22, 0.0, -0.36, 0.38, steel, axis="y")         # spout
    box(0.12, 0.04, 0.1, 0.0, -0.46, 0.38, steel)
    box(0.16, 0.12, 0.22, 0.34, -0.22, 0.4, yellow)            # control box
    box(0.03, 0.01, 0.03, 0.34, -0.285, 0.46, green)
    box(0.03, 0.01, 0.03, 0.38, -0.285, 0.46, red)
    cyl(0.06, 0.5, -0.28, 0.24, 0.98, rust)                    # fume pipe
else:
    raise SystemExit("unknown kind " + kind)

root.rotation_euler = (0, 0, rot)

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
sun_data.energy = 3.0
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
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9

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
