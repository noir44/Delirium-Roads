# Blender: a clean printed label on the front of the asphalt mix sack. Meshy re-paints the
# concept's lettering through its own UV layout and garbles it, so the front gets a plain sack
# panel with our lettering, projected from the front (-Y) and baked back into the texture on
# the mesh's own UVs. The mesh is not touched.
#   blender -b --factory-startup --python sack_label.py -- <model.fbx> <texture.png> <preview.png>
# Run after build_items.py (which rewrites the texture from Meshy's).
import bpy, sys, os, math, random
from mathutils import Vector

FBX, TEX, PREVIEW = sys.argv[sys.argv.index("--") + 1:][:3]
SIZE = 512
LW, LH = 400, 580  # label image = the front of the bounding box, 1 px ~ 1 mm

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
bpy.ops.import_scene.fbx(filepath=FBX)
o = [x for x in sc.objects if x.type == "MESH"][0]
me = o.data
base_uv = me.uv_layers.active.name
base = bpy.data.images.load(TEX)

# Sack colour: the median of the texture (most of it is bare sack).
px = list(base.pixels)
lum = sorted((0.3 * px[i] + 0.59 * px[i + 1] + 0.11 * px[i + 2], i) for i in range(0, len(px), 4 * 7))
i = lum[len(lum) // 2][1]
sack = (px[i], px[i + 1], px[i + 2])

# Label image: plain sack weave with the lettering, alpha = where it covers.
lab = bpy.data.images.new("label", LW, LH, alpha=True)
rng = random.Random(7)
data = [0.0] * (LW * LH * 4)


def inside(x, y):
    # feathered panel: x 4..96 %, y (from the bottom) 6..80 %
    fx = min(x / LW - 0.04, 0.96 - x / LW) / 0.05
    fy = min(y / LH - 0.06, 0.80 - y / LH) / 0.05
    return max(0.0, min(1.0, fx, fy))


# lettering mask from a PIL-free raster: render text with Blender's own font into an image is
# awkward in batch, so the mask comes from sack_label_text.png (made by sack_label_text.py).
mask = bpy.data.images.load(os.path.join(os.path.dirname(os.path.abspath(__file__)), "sack_label_text.png"))
mp = list(mask.pixels)
for y in range(LH):
    for x in range(LW):
        k = (y * LW + x) * 4
        a = inside(x, y)
        n = 1.0 + (rng.random() - 0.5) * 0.08 + (0.03 if (x + y) % 3 == 0 else 0.0)
        ink = mp[k + 3]  # text alpha
        c = [sack[j] * n * (1 - ink * 0.9) for j in range(3)]
        data[k:k + 4] = [c[0], c[1], c[2], a]
lab.pixels = data

# Planar projection from the front: u along X, v along Z, over the bounding box.
pts = [o.matrix_world @ v.co for v in me.vertices]
lo = Vector([min(p[j] for p in pts) for j in range(3)])
hi = Vector([max(p[j] for p in pts) for j in range(3)])
print("BBOX", tuple(round(c, 3) for c in hi - lo), "rot", [round(c, 2) for c in o.matrix_world.to_euler()], "scale", [round(c, 3) for c in o.matrix_world.to_scale()])
proj = me.uv_layers.new(name="front")
front = me.color_attributes.new("facing", "FLOAT_COLOR", "CORNER")
rot = o.matrix_world.to_3x3().normalized()
for poly in me.polygons:
    n = (rot @ poly.normal).normalized()
    w = max(0.0, min(1.0, (-n.y - 0.05) / 0.3))
    for li in poly.loop_indices:
        p = pts[me.loops[li].vertex_index]
        proj.data[li].uv = ((p.x - lo.x) / (hi.x - lo.x), (p.z - lo.z) / (hi.z - lo.z))
        front.data[li].color = (w, w, w, 1)
me.uv_layers.active = me.uv_layers[base_uv]

m = bpy.data.materials.new("bake")
nt = m.node_tree
for n in list(nt.nodes):
    nt.nodes.remove(n)
uv0 = nt.nodes.new("ShaderNodeUVMap"); uv0.uv_map = base_uv
uv1 = nt.nodes.new("ShaderNodeUVMap"); uv1.uv_map = "front"
tb = nt.nodes.new("ShaderNodeTexImage"); tb.image = base
tl = nt.nodes.new("ShaderNodeTexImage"); tl.image = lab; tl.extension = "CLIP"
attr = nt.nodes.new("ShaderNodeAttribute"); attr.attribute_name = "facing"
mul = nt.nodes.new("ShaderNodeMath"); mul.operation = "MULTIPLY"
mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"
emit = nt.nodes.new("ShaderNodeEmission")
outn = nt.nodes.new("ShaderNodeOutputMaterial")
L = nt.links.new
L(uv0.outputs["UV"], tb.inputs["Vector"])
L(uv1.outputs["UV"], tl.inputs["Vector"])
L(tl.outputs["Alpha"], mul.inputs[0])
L(attr.outputs["Fac"], mul.inputs[1])
# Mix has float, vector and colour sockets under the same names: the colour ones by index.
L(mul.outputs["Value"], mix.inputs[0])
L(tb.outputs["Color"], mix.inputs[6])
L(tl.outputs["Color"], mix.inputs[7])
L(mix.outputs[2], emit.inputs["Color"])
L(emit.outputs["Emission"], outn.inputs["Surface"])
out = bpy.data.images.new("out", SIZE, SIZE)
target = nt.nodes.new("ShaderNodeTexImage"); target.image = out
nt.nodes.active = target
me.materials.clear(); me.materials.append(m)
bpy.ops.object.select_all(action="DESELECT"); o.select_set(True)
bpy.context.view_layer.objects.active = o
sc.cycles.samples = 4
sc.render.bake.margin = 8
sc.view_settings.view_transform = "Standard"
bpy.ops.object.bake(type="EMIT")
out.filepath_raw = TEX
out.file_format = "PNG"
out.save()
print("BAKED", TEX)

# Preview: the baked texture as the game will draw it, from the PZ camera direction.
pm = bpy.data.materials.new("preview")
bsdf = pm.node_tree.nodes["Principled BSDF"]; bsdf.inputs["Roughness"].default_value = 0.9
pt = pm.node_tree.nodes.new("ShaderNodeTexImage"); pt.image = out
pm.node_tree.links.new(pt.outputs["Color"], bsdf.inputs["Base Color"])
me.materials.clear(); me.materials.append(pm)
sc.render.film_transparent = True
sc.render.resolution_x = sc.render.resolution_y = 384
sc.cycles.samples = 32
w = bpy.data.worlds.new("w"); sc.world = w
w.use_nodes = True; w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = max(hi - lo) * 1.4
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sun.data.energy = 3.0
sc.collection.objects.link(sun)
ctr = (lo + hi) / 2
d = Vector((0.6, -1.0, 0.7))
cam.location = ctr + d.normalized() * 3
cam.rotation_euler = (ctr - cam.location).to_track_quat("-Z", "Y").to_euler()
sun.rotation_euler = (d + Vector((-0.5, 0, 0.8))).to_track_quat("Z", "Y").to_euler()
sc.render.filepath = PREVIEW
bpy.ops.render.render(write_still=True)
print("PREVIEW", PREVIEW)
