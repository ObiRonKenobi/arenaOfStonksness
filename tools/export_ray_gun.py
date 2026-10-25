import bpy
import os

path = r"C:\Users\sudol\OneDrive\Documents\Game Assets\Blends-20261023T215704Z-1-001\Blends\Ray Gun.blend"
bpy.ops.wm.open_mainfile(filepath=path)

for obj in bpy.data.objects:
    if obj.type != "MESH":
        continue
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    print(
        "MESH",
        obj.name,
        "x", round(min(xs), 3), round(max(xs), 3),
        "y", round(min(ys), 3), round(max(ys), 3),
        "z", round(min(zs), 3), round(max(zs), 3),
    )

def connect_principled(mat):
    if not mat.use_nodes or mat.node_tree is None:
        return
    nt = mat.node_tree
    principled = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    diffuse = next((n for n in nt.nodes if n.type == "BSDF_DIFFUSE"), None)
    color = None
    if principled is not None:
        color = [round(c, 3) for c in principled.inputs["Base Color"].default_value]
    elif diffuse is not None:
        color = [round(c, 3) for c in diffuse.inputs["Color"].default_value]
        principled = nt.nodes.new("ShaderNodeBsdfPrincipled")
        principled.inputs["Base Color"].default_value = diffuse.inputs["Color"].default_value
        principled.inputs["Roughness"].default_value = 0.45
    print("MAT", mat.name, color)
    if principled is None:
        return
    outputs = [n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"]
    if not outputs:
        return
    primary = next((n for n in outputs if n.name == "Material Output"), outputs[0])
    surface = primary.inputs["Surface"]
    for link in list(surface.links):
        nt.links.remove(link)
    nt.links.new(principled.outputs["BSDF"], surface)
    primary.is_active_output = True

for mat in bpy.data.materials:
    connect_principled(mat)

bpy.ops.object.select_all(action="SELECT")
dest = r"c:\Users\sudol\arenaOfStonksness\assets\weapons\ray_gun.glb"
bpy.ops.export_scene.gltf(
    filepath=dest,
    export_format="GLB",
    use_selection=True,
    export_yup=True,
    export_animations=False,
)
print("EXPORTED", os.path.getsize(dest))
