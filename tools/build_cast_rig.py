"""Shared skeleton, one body builder, seven characters, four clips.

Run inside Blender. Each character is the same bones with their own
parts and colors. Walk, climb, hit, and death are keyed once.
"""

import math
import os

import bmesh
import bpy
from mathutils import Vector

ROOT = r"c:\Users\sudol\arenaOfStonksness"
BLEND = os.path.join(ROOT, "assets", "models", "cast_rig.blend")
OUT_DIR = os.path.join(ROOT, "assets", "characters")

SKIN = {
	"punk": (0.86, 0.7, 0.62, 1),
	"hobo": (0.58, 0.4, 0.32, 1),
	"dreads": (0.4, 0.24, 0.15, 1),
	"lazy": (0.9, 0.73, 0.58, 1),
	"collector": (0.8, 0.64, 0.52, 1),
	"broker": (0.82, 0.67, 0.55, 1),
	"king": (0.84, 0.7, 0.6, 1),
}


def mat(name, color):
	found = bpy.data.materials.get(name)
	if found:
		return found
	made = bpy.data.materials.new(name)
	made.use_nodes = True
	made.diffuse_color = color
	bsdf = made.node_tree.nodes.get("Principled BSDF")
	if bsdf:
		bsdf.inputs["Base Color"].default_value = color
		bsdf.inputs["Roughness"].default_value = 0.88
	return made


def clear_scene():
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.object.delete(use_global=False)
	for bank in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.actions, bpy.data.collections):
		for item in list(bank):
			if item.users == 0:
				bank.remove(item)


def add_bone(arm, name, head, tail, parent):
	bone = arm.edit_bones.new(name)
	bone.head = Vector(head)
	bone.tail = Vector(tail)
	bone.use_deform = True
	if parent:
		bone.parent = arm.edit_bones[parent]
	return bone


def build_armature():
	data = bpy.data.armatures.new("SharedRig")
	arm = bpy.data.objects.new("SharedRig", data)
	bpy.context.scene.collection.objects.link(arm)
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.mode_set(mode="EDIT")
	add_bone(data, "root", (0, 0, 0.9), (0, 0, 1.02), None)
	add_bone(data, "spine", (0, 0, 1.02), (0, 0, 1.24), "root")
	add_bone(data, "chest", (0, 0, 1.24), (0, 0, 1.46), "spine")
	add_bone(data, "neck", (0, 0, 1.46), (0, 0, 1.56), "chest")
	add_bone(data, "head", (0, 0, 1.56), (0, 0, 1.78), "neck")
	for side, sign in (("L", 1), ("R", -1)):
		add_bone(data, f"shoulder.{side}", (0.08 * sign, 0, 1.42), (0.18 * sign, 0, 1.42), "chest")
		add_bone(data, f"upper_arm.{side}", (0.18 * sign, 0, 1.42), (0.36 * sign, 0, 1.14), f"shoulder.{side}")
		add_bone(data, f"forearm.{side}", (0.36 * sign, 0, 1.14), (0.48 * sign, 0, 0.9), f"upper_arm.{side}")
		add_bone(data, f"hand.{side}", (0.48 * sign, 0, 0.9), (0.56 * sign, 0, 0.82), f"forearm.{side}")
		add_bone(data, f"thigh.{side}", (0.11 * sign, 0, 0.9), (0.13 * sign, 0.02, 0.48), "root")
		add_bone(data, f"shin.{side}", (0.13 * sign, 0.02, 0.48), (0.13 * sign, 0.02, 0.08), f"thigh.{side}")
		add_bone(data, f"foot.{side}", (0.13 * sign, 0.02, 0.08), (0.13 * sign, -0.16, 0.03), f"shin.{side}")
	bpy.ops.object.mode_set(mode="OBJECT")
	return arm


def bone_parent(obj, arm, bone_name):
	bpy.context.view_layer.update()
	world = obj.matrix_world.copy()
	obj.parent = arm
	obj.parent_type = "BONE"
	obj.parent_bone = bone_name
	obj.matrix_world = world


def _active(obj):
	bpy.ops.object.select_all(action="DESELECT")
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj


def _smooth(obj, bevel=0.0):
	_active(obj)
	if bevel > 0.001:
		mod = obj.modifiers.new("Bevel", "BEVEL")
		mod.width = bevel
		mod.segments = 2
		mod.limit_method = "ANGLE"
		mod.angle_limit = math.radians(50)
		bpy.ops.object.modifier_apply(modifier="Bevel")
	try:
		bpy.ops.object.shade_smooth()
	except RuntimeError:
		bpy.ops.object.shade_flat()


def _taper(obj, top, bottom):
	if abs(top - 1.0) < 0.01 and abs(bottom - 1.0) < 0.01:
		return
	zs = [vertex.co.z for vertex in obj.data.vertices]
	low = min(zs)
	span = max(max(zs) - low, 0.001)
	for vertex in obj.data.vertices:
		blend = (vertex.co.z - low) / span
		width = bottom + (top - bottom) * blend
		vertex.co.x *= width
		vertex.co.y *= width


def _shape_head(obj):
	for vertex in obj.data.vertices:
		if vertex.co.z < -0.01:
			vertex.co.x *= 0.78
			vertex.co.y *= 0.86
		if vertex.co.y < -0.03:
			vertex.co.y -= 0.012
	obj.data.update()


def _finish(obj, arm, bone, color, name, bevel=0.0, smooth=True):
	if smooth:
		_smooth(obj, bevel)
	else:
		_active(obj)
		bpy.ops.object.shade_flat()
	obj.name = name
	obj.data.materials.append(mat(name, color))
	bone_parent(obj, arm, bone)
	return obj


def _puff(obj):
	_active(obj)
	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.mesh.select_all(action="SELECT")
	bpy.ops.mesh.subdivide(number_cuts=2)
	bpy.ops.mesh.vertices_smooth(factor=0.55, repeat=6)
	bpy.ops.object.mode_set(mode="OBJECT")


def add_box(arm, bone, name, loc, scale, color, rot=(0, 0, 0), top=1.0, bottom=1.0, soft=True):
	bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
	obj = bpy.context.active_object
	obj.scale = scale
	bpy.ops.object.transform_apply(rotation=True, scale=True)
	_taper(obj, top, bottom)
	if soft and min(scale) > 0.12:
		_puff(obj)
	bevel = min(scale) * 0.08 if soft else 0.0
	return _finish(obj, arm, bone, color, name, bevel, soft)


def add_sphere(arm, bone, name, loc, scale, color, shape=False):
	bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=0.5, location=loc)
	obj = bpy.context.active_object
	obj.scale = scale
	bpy.ops.object.transform_apply(scale=True)
	if shape:
		_shape_head(obj)
	return _finish(obj, arm, bone, color, name)


def add_cone(arm, bone, name, loc, scale, color, rot=(0, 0, 0), sharp=False):
	bpy.ops.mesh.primitive_cone_add(vertices=6 if sharp else 20, radius1=0.5, depth=1, location=loc, rotation=rot)
	obj = bpy.context.active_object
	obj.scale = scale
	bpy.ops.object.transform_apply(rotation=True, scale=True)
	return _finish(obj, arm, bone, color, name, 0.0, not sharp)


def add_cyl(arm, bone, name, head, tail, radius, color):
	start = Vector(head)
	end = Vector(tail)
	direction = end - start
	if direction.length > 0.02:
		pad = direction.normalized() * radius * 0.85
		start = start - pad
		end = end + pad
		direction = end - start
	mid = (start + end) * 0.5
	rot = direction.to_track_quat("Z", "Y").to_euler()
	bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=radius, depth=direction.length, location=mid, rotation=rot)
	obj = bpy.context.active_object
	bpy.ops.object.transform_apply(rotation=True)
	return _finish(obj, arm, bone, color, name, radius * 0.15, True)


def _link_mesh(name, bm):
	bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
	mesh = bpy.data.meshes.new(name)
	bm.to_mesh(mesh)
	bm.free()
	obj = bpy.data.objects.new(name, mesh)
	bpy.context.scene.collection.objects.link(obj)
	return obj


def add_loft(arm, bone, name, sections, color, sides=16, front=1.0):
	bm = bmesh.new()
	rings = []
	for sx, sy, sz, rx, ry in sections:
		ring = []
		for index in range(sides):
			ang = (index / sides) * math.tau
			ring.append(bm.verts.new((sx + math.cos(ang) * rx, sy + math.sin(ang) * ry, sz)))
		rings.append(ring)
	for lower, upper in zip(rings, rings[1:]):
		for index in range(sides):
			ang = ((index + 0.5) / sides) * math.tau
			if math.sin(ang) < front:
				continue
			nxt = (index + 1) % sides
			try:
				bm.faces.new((lower[index], upper[index], upper[nxt], lower[nxt]))
			except ValueError:
				pass
	if front <= -0.99:
		try:
			bm.faces.new(rings[0])
			bm.faces.new(list(reversed(rings[-1])))
		except ValueError:
			pass
	obj = _link_mesh(name, bm)
	return _finish(obj, arm, bone, color, name)


def add_cape(arm, bone, name, color, profile):
	# profile is (z, back_y, half_width) from the collar down to the hem.
	# The cloth sits on that back surface instead of hanging as a free board.
	bm = bmesh.new()
	cols = 13
	rows = len(profile)

	def sheet(lift):
		grid = []
		for row, (z, back_y, half_w) in enumerate(profile):
			down = row / max(1, rows - 1)
			line = []
			for col in range(cols):
				across = col / (cols - 1) - 0.5
				fold = math.sin(across * math.tau * 2.0) * (0.008 + down * 0.018)
				y = back_y + 0.015 + fold + lift
				x = across * 2.0 * half_w
				zz = z - (0.25 - across * across) * 0.1 * down
				line.append(bm.verts.new((x, y, zz)))
			grid.append(line)
		return grid

	outer = sheet(0.0)
	inner = sheet(-0.012)

	def quads(grid, flip):
		for row in range(rows - 1):
			for col in range(cols - 1):
				quad = (grid[row][col], grid[row][col + 1], grid[row + 1][col + 1], grid[row + 1][col])
				bm.faces.new(tuple(reversed(quad)) if flip else quad)

	quads(outer, False)
	quads(inner, True)
	for row in range(rows - 1):
		bm.faces.new((outer[row][0], inner[row][0], inner[row + 1][0], outer[row + 1][0]))
		bm.faces.new((outer[row][-1], outer[row + 1][-1], inner[row + 1][-1], inner[row][-1]))
	for col in range(cols - 1):
		bm.faces.new((outer[0][col], outer[0][col + 1], inner[0][col + 1], inner[0][col]))
		bm.faces.new((outer[-1][col], inner[-1][col], inner[-1][col + 1], outer[-1][col + 1]))
	obj = _link_mesh(name, bm)
	return _finish(obj, arm, bone, color, name)


def add_cowl(arm, bone, name, color):
	# Open at the top so the head comes out. The cloth sits on the shoulders.
	bm = bmesh.new()
	cols = 18
	rings = []
	for z, sy, rx, ry, drop in (
		(1.6, -0.02, 0.12, 0.1, 0.0),
		(1.57, -0.01, 0.2, 0.16, 0.05),
		(1.38, 0.0, 0.34, 0.24, 0.14),
	):
		ring = []
		for index in range(cols):
			ang = (index / cols) * math.tau
			front = max(0.0, -math.sin(ang))
			ring.append(bm.verts.new((
				math.cos(ang) * rx,
				sy + math.sin(ang) * ry,
				z - front * drop,
			)))
		rings.append(ring)
	for lower, upper in zip(rings, rings[1:]):
		for index in range(cols):
			nxt = (index + 1) % cols
			bm.faces.new((lower[index], upper[index], upper[nxt], lower[nxt]))
	obj = _link_mesh(name, bm)
	return _finish(obj, arm, bone, color, name)


def face(arm, cid, skin, sleepy=False, brows=True):
	add_sphere(arm, "head", f"{cid}_head", (0, -0.02, 1.66), (0.25, 0.26, 0.28), skin, True)
	eye = (0.012, 0.012, 0.008) if sleepy else (0.032, 0.02, 0.022)
	for sign in (-1, 1):
		add_sphere(arm, "head", f"{cid}_eye_{sign}", (0.048 * sign, -0.145, 1.69), eye, (0.95, 0.95, 0.96, 1))
		add_sphere(arm, "head", f"{cid}_pupil_{sign}", (0.048 * sign, -0.158, 1.688), (eye[0] * 0.45, eye[1] * 0.45, eye[2] * 0.45), (0.04, 0.03, 0.03, 1))
		if brows and not sleepy:
			tilt = 0.35 * sign
			add_box(arm, "head", f"{cid}_brow_{sign}", (0.05 * sign, -0.15, 1.745), (0.05, 0.012, 0.01), (0.08, 0.05, 0.04, 1), (0, 0, tilt), soft=False)
	add_sphere(arm, "head", f"{cid}_nose", (0, -0.16, 1.64), (0.028, 0.03, 0.04), skin)
	add_sphere(arm, "head", f"{cid}_mouth", (0, -0.15, 1.58), (0.04, 0.012, 0.012), (0.35, 0.16, 0.16, 1))


def hair_cap(arm, cid, color, z=1.78, scale=(0.26, 0.27, 0.16)):
	add_sphere(arm, "head", f"{cid}_hair", (0, 0.0, z), scale, color)


def limbs(arm, cid, pants, shoes, sleeve, skin, fat=1.0):
	for side, sign in (("L", 1), ("R", -1)):
		add_cyl(arm, f"upper_arm.{side}", f"{cid}_uarm_{side}", (0.18 * sign, 0, 1.42), (0.36 * sign, 0, 1.14), 0.055 * fat, sleeve)
		add_cyl(arm, f"forearm.{side}", f"{cid}_farm_{side}", (0.36 * sign, 0, 1.14), (0.48 * sign, 0, 0.9), 0.045 * fat, sleeve)
		add_sphere(arm, f"hand.{side}", f"{cid}_hand_{side}", (0.52 * sign, -0.02, 0.84), (0.075 * fat, 0.05, 0.09), skin)
		add_cyl(arm, f"thigh.{side}", f"{cid}_thigh_{side}", (0.11 * sign, 0, 0.9), (0.13 * sign, 0.02, 0.48), 0.07 * fat, pants)
		add_cyl(arm, f"shin.{side}", f"{cid}_shin_{side}", (0.13 * sign, 0.02, 0.48), (0.13 * sign, 0.02, 0.08), 0.055 * fat, pants)
		add_box(arm, f"foot.{side}", f"{cid}_shoe_{side}", (0.13 * sign, -0.06, 0.045), (0.1, 0.24, 0.08), shoes)


def begin_action(arm, name):
	if arm.animation_data is None:
		arm.animation_data_create()
	action = bpy.data.actions.new(name)
	arm.animation_data.action = action
	bpy.context.view_layer.objects.active = arm
	if bpy.context.object.mode != "POSE":
		bpy.ops.object.mode_set(mode="POSE")
	bpy.ops.pose.select_all(action="SELECT")
	bpy.ops.pose.transforms_clear()
	return action


def key_pose(arm, frame, pose):
	bpy.context.scene.frame_set(frame)
	for bone_name, rot in pose.items():
		bone = arm.pose.bones[bone_name]
		bone.rotation_mode = "XYZ"
		bone.rotation_euler = rot
		bone.keyframe_insert(data_path="rotation_euler", frame=frame)


def end_action(arm, action):
	data = arm.animation_data
	if getattr(data, "action_slot", None) is None and len(action.slots):
		data.action_slot = action.slots[0]
	try:
		action.frame_start = bpy.context.scene.frame_start
		action.frame_end = bpy.context.scene.frame_end
	except AttributeError:
		pass
	track = data.nla_tracks.new()
	track.name = action.name
	track.strips.new(action.name, 1, action)
	track.mute = True
	data.action = None
	bpy.ops.pose.transforms_clear()


def mirror(pose):
	flipped = {}
	for name, rot in pose.items():
		if name.endswith(".L"):
			flipped[name[:-2] + ".R"] = rot
		elif name.endswith(".R"):
			flipped[name[:-2] + ".L"] = rot
		else:
			flipped[name] = (rot[0], -rot[1], -rot[2])
	return flipped


def animate(arm):
	bpy.context.scene.render.fps = 30
	step = {
		"thigh.L": (0.7, 0, 0),
		"shin.L": (0.15, 0, 0),
		"foot.L": (-0.2, 0, 0),
		"thigh.R": (-0.35, 0, 0),
		"shin.R": (0.9, 0, 0),
		"foot.R": (0.15, 0, 0),
		"upper_arm.L": (-0.55, 0, 0),
		"forearm.L": (0.25, 0, 0),
		"upper_arm.R": (0.45, 0, 0),
		"forearm.R": (0.55, 0, 0),
		"spine": (0.06, 0.12, 0),
		"chest": (0.04, 0, 0.05),
	}
	passing = {
		"thigh.L": (0.1, 0, 0),
		"shin.L": (0.35, 0, 0),
		"thigh.R": (0.1, 0, 0),
		"shin.R": (0.2, 0, 0),
		"upper_arm.L": (0.05, 0, 0),
		"upper_arm.R": (-0.05, 0, 0),
		"spine": (0.04, 0, 0),
	}
	bpy.context.scene.frame_start = 1
	bpy.context.scene.frame_end = 24
	walk = begin_action(arm, "Walk")
	key_pose(arm, 1, step)
	key_pose(arm, 7, passing)
	key_pose(arm, 13, mirror(step))
	key_pose(arm, 19, mirror(passing))
	key_pose(arm, 25, step)
	end_action(arm, walk)

	bpy.context.scene.frame_start = 1
	bpy.context.scene.frame_end = 40
	idle = begin_action(arm, "Idle")
	key_pose(arm, 1, {"chest": (0.02, 0, 0), "upper_arm.L": (0.08, 0, 0.08), "upper_arm.R": (0.08, 0, -0.08)})
	key_pose(arm, 20, {"chest": (0.05, 0.04, 0), "upper_arm.L": (0.12, 0, 0.1), "upper_arm.R": (0.12, 0, -0.1), "head": (0.06, 0, 0)})
	key_pose(arm, 40, {"chest": (0.02, 0, 0), "upper_arm.L": (0.08, 0, 0.08), "upper_arm.R": (0.08, 0, -0.08)})
	end_action(arm, idle)

	bpy.context.scene.frame_start = 1
	bpy.context.scene.frame_end = 32
	climb = begin_action(arm, "Climb")
	key_pose(arm, 1, {"upper_arm.L": (0.2, 0, 0), "upper_arm.R": (0.2, 0, 0)})
	key_pose(arm, 10, {
		"upper_arm.L": (-2.3, 0.2, -0.4),
		"upper_arm.R": (-2.3, -0.2, 0.4),
		"forearm.L": (0.5, 0, 0),
		"forearm.R": (0.5, 0, 0),
		"chest": (0.5, 0, 0),
		"thigh.L": (0.9, 0, 0),
		"shin.L": (1.1, 0, 0),
		"thigh.R": (0.4, 0, 0),
	})
	key_pose(arm, 20, {
		"upper_arm.L": (-1.2, 0.4, -0.6),
		"upper_arm.R": (-1.2, -0.4, 0.6),
		"chest": (1.1, 0, 0),
		"spine": (0.5, 0, 0),
		"thigh.L": (1.3, 0, 0),
		"shin.L": (1.4, 0, 0),
		"thigh.R": (1.1, 0, 0),
		"shin.R": (1.2, 0, 0),
	})
	key_pose(arm, 32, {"chest": (0.15, 0, 0), "spine": (0.05, 0, 0)})
	end_action(arm, climb)

	bpy.context.scene.frame_start = 1
	bpy.context.scene.frame_end = 16
	hit = begin_action(arm, "Hit")
	key_pose(arm, 1, {"upper_arm.R": (-0.4, 0, 0.4), "forearm.R": (0.8, 0, 0), "chest": (0, -0.15, 0)})
	key_pose(arm, 7, {"upper_arm.R": (-1.5, 0, -1.0), "forearm.R": (0.3, 0, 0), "chest": (0.1, 0.25, 0), "spine": (0.1, 0.15, 0)})
	key_pose(arm, 16, {"upper_arm.R": (0.1, 0, 0), "chest": (0, 0, 0)})
	end_action(arm, hit)

	bpy.context.scene.frame_start = 1
	bpy.context.scene.frame_end = 20
	death = begin_action(arm, "Death")
	key_pose(arm, 1, {"spine": (0, 0, 0)})
	key_pose(arm, 8, {"root": (0.7, 0, 0), "spine": (0.3, 0, 0), "upper_arm.L": (0.4, 0, 0.6), "upper_arm.R": (0.4, 0, -0.6)})
	key_pose(arm, 20, {"root": (1.45, 0, 0), "spine": (0.2, 0, 0), "thigh.L": (0.3, 0, 0), "thigh.R": (-0.2, 0, 0)})
	end_action(arm, death)
	bpy.ops.object.mode_set(mode="OBJECT")


def sculpt_king(arm, spec, skin):
	cid = "king"
	limbs(arm, cid, spec["pants"], spec["shoes"], spec["sleeve"], skin, 1.0)
	add_loft(arm, "root", f"{cid}_robe", [
		(0, 0.02, 0.06, 0.62, 0.48),
		(0, 0.0, 0.45, 0.5, 0.38),
		(0, -0.02, 0.9, 0.34, 0.26),
		(0, -0.02, 1.28, 0.26, 0.2),
		(0, 0.0, 1.5, 0.2, 0.16),
	], spec["robe"], sides=20, front=-1.0)
	add_box(arm, "chest", f"{cid}_gold", (0, -0.23, 1.32), (0.2, 0.025, 0.26), spec["shirt"], soft=False)
	# Back of the robe, from the fur collar to the hem, so the cape is worn.
	add_cape(arm, "chest", f"{cid}_cape", spec["cape"], [
		(1.5, 0.12, 0.18),
		(1.38, 0.18, 0.26),
		(1.12, 0.2, 0.3),
		(0.82, 0.26, 0.36),
		(0.48, 0.38, 0.42),
		(0.16, 0.5, 0.48),
		(0.0, 0.54, 0.5),
	])
	add_sphere(arm, "neck", f"{cid}_fur", (0, -0.02, 1.5), (0.4, 0.32, 0.14), (0.82, 0.82, 0.84, 1))
	add_loft(arm, "head", f"{cid}_crown", [
		(0, -0.01, 1.84, 0.15, 0.15),
		(0, -0.01, 1.9, 0.13, 0.13),
	], (0.9, 0.72, 0.18, 1), sides=12, front=-1.0)
	for index in range(5):
		ang = (index / 5) * math.tau
		add_cone(arm, "head", f"{cid}_point_{index}", (math.cos(ang) * 0.1, -0.02 + math.sin(ang) * 0.1, 1.96), (0.035, 0.035, 0.09), (0.92, 0.2, 0.16, 1), sharp=True)
	face(arm, cid, skin, False, True)
	hair_cap(arm, cid, (0.9, 0.9, 0.92, 1), 1.78, (0.27, 0.28, 0.16))
	add_sphere(arm, "head", f"{cid}_beard", (0, -0.12, 1.54), (0.12, 0.08, 0.1), (0.78, 0.78, 0.8, 1))


def sculpt_lazy(arm, spec, skin):
	cid = "lazy"
	limbs(arm, cid, spec["pants"], spec["shoes"], spec["sleeve"], skin, 1.35)
	add_loft(arm, "spine", f"{cid}_body", [
		(0, 0.0, 0.82, 0.26, 0.2),
		(0, -0.06, 1.02, 0.36, 0.32),
		(0, -0.1, 1.18, 0.34, 0.3),
		(0, -0.04, 1.38, 0.3, 0.24),
		(0, 0.0, 1.52, 0.22, 0.18),
	], spec["shirt"], front=-1.0)
	add_cowl(arm, "chest", f"{cid}_hood", spec["shirt"])
	add_sphere(arm, "chest", f"{cid}_hoodfold", (0, 0.28, 1.4), (0.28, 0.1, 0.08), spec["shirt"])
	string = (0.05, 0.05, 0.05, 1)
	add_cyl(arm, "chest", f"{cid}_string_l", (-0.03, -0.3, 1.46), (-0.035, -0.36, 1.16), 0.008, string)
	add_cyl(arm, "chest", f"{cid}_string_r", (0.03, -0.3, 1.46), (0.035, -0.36, 1.16), 0.008, string)
	face(arm, cid, skin, True, False)
	hair_cap(arm, cid, (0.08, 0.06, 0.05, 1), 1.78, (0.24, 0.24, 0.14))


def sculpt_collector(arm, spec, skin):
	cid = "collector"
	limbs(arm, cid, spec["pants"], spec["shoes"], spec["sleeve"], skin, 1.0)
	add_loft(arm, "spine", f"{cid}_suit", [
		(0, 0.0, 0.86, 0.16, 0.12),
		(0, -0.01, 1.16, 0.18, 0.13),
		(0, -0.02, 1.42, 0.15, 0.11),
	], spec["pants"], sides=16, front=-1.0)
	add_box(arm, "chest", f"{cid}_shirt", (0, -0.16, 1.34), (0.08, 0.018, 0.16), spec["shirt"], soft=False)
	add_box(arm, "chest", f"{cid}_tie", (0, -0.175, 1.26), (0.022, 0.01, 0.22), spec["tie"], soft=False)
	add_loft(arm, "chest", f"{cid}_coat", [
		(0, 0.02, 0.28, 0.32, 0.22),
		(0, 0.0, 0.7, 0.28, 0.2),
		(0, -0.02, 1.15, 0.26, 0.18),
		(0, -0.02, 1.46, 0.3, 0.18),
	], spec["jacket"], sides=24, front=-0.86)
	for sign in (-1, 1):
		add_box(arm, "chest", f"{cid}_lining_{sign}", (0.1 * sign, -0.12, 0.95), (0.035, 0.012, 0.9), spec["lining"], soft=False)
	add_box(arm, "hand.L", f"{cid}_case", (0.58, -0.08, 0.7), (0.1, 0.32, 0.22), (0.06, 0.06, 0.07, 1), soft=True)
	face(arm, cid, skin, False, True)
	hair_cap(arm, cid, (0.06, 0.05, 0.05, 1))


def sculpt_hobo(arm, spec, skin):
	cid = "hobo"
	limbs(arm, cid, spec["pants"], spec["shoes"], spec["jacket"], skin, 1.0)
	add_loft(arm, "chest", f"{cid}_shirt", [
		(0, -0.02, 1.08, 0.13, 0.1),
		(0, -0.03, 1.28, 0.15, 0.11),
		(0, -0.02, 1.46, 0.12, 0.09),
	], spec["shirt"], sides=12, front=-1.0)
	add_loft(arm, "root", f"{cid}_coat", [
		(0, 0.04, 0.22, 0.38, 0.28),
		(0, 0.02, 0.6, 0.32, 0.24),
		(0, 0.0, 1.0, 0.26, 0.18),
		(0, -0.02, 1.28, 0.24, 0.16),
		(0, -0.01, 1.48, 0.28, 0.18),
	], spec["jacket"], sides=24, front=-0.85)
	face(arm, cid, skin, False, True)
	hair_cap(arm, cid, (0.28, 0.18, 0.1, 1), 1.78, (0.28, 0.28, 0.16))
	for index, x in enumerate((-0.06, 0, 0.07)):
		add_cone(arm, "head", f"{cid}_tuft_{index}", (x, -0.02, 1.86), (0.04, 0.04, 0.1), (0.28, 0.18, 0.1, 1))
	add_cone(arm, "head", f"{cid}_beard", (0, -0.1, 1.52), (0.16, 0.12, 0.18), (0.22, 0.14, 0.08, 1), (math.pi, 0, 0))


def sculpt_dreads(arm, spec, skin):
	cid = "dreads"
	limbs(arm, cid, spec["pants"], spec["shoes"], spec["jacket"], skin, 1.0)
	# Hips wider than the shoulders, waist pulled in, chest pushed forward.
	add_loft(arm, "spine", f"{cid}_jacket", [
		(0, 0.06, 0.78, 0.28, 0.22),
		(0, 0.0, 1.0, 0.15, 0.12),
		(0, -0.03, 1.16, 0.18, 0.14),
		(0, -0.08, 1.3, 0.22, 0.2),
		(0, -0.02, 1.46, 0.19, 0.14),
	], spec["jacket"], sides=20, front=-1.0)
	add_sphere(arm, "spine", f"{cid}_seat", (0, 0.16, 0.86), (0.3, 0.16, 0.14), spec["jacket"])
	stripe = (0.9, 0.72, 0.12, 1)
	add_box(arm, "chest", f"{cid}_stripe_l", (-0.06, -0.29, 1.3), (0.03, 0.01, 0.2), stripe, soft=False)
	add_box(arm, "chest", f"{cid}_stripe_r", (0.06, -0.29, 1.3), (0.03, 0.01, 0.2), stripe, soft=False)
	add_loft(arm, "spine", f"{cid}_belt", [
		(0, 0.0, 0.98, 0.17, 0.14),
		(0, 0.0, 1.04, 0.16, 0.13),
	], spec["belt"], sides=16, front=-1.0)
	face(arm, cid, skin, False, True)
	hair_cap(arm, cid, (0.06, 0.04, 0.03, 1), 1.8, (0.3, 0.32, 0.18))
	spots = ((-0.1, 0.02), (-0.04, 0.06), (0.04, 0.06), (0.1, 0.02), (-0.12, -0.02), (0.12, -0.02))
	for index, (x, y) in enumerate(spots):
		add_cyl(arm, "head", f"{cid}_lock_{index}", (x, y, 1.72), (x, y - 0.02, 1.22), 0.02, (0.05, 0.03, 0.02, 1))


def sculpt_broker(arm, spec, skin):
	cid = "broker"
	limbs(arm, cid, spec["pants"], spec["shoes"], spec["sleeve"], skin, 1.0)
	add_box(arm, "spine", f"{cid}_hips", (0, 0, 0.98), spec["hips"], spec["pants"], soft=True)
	add_loft(arm, "chest", f"{cid}_jacket", [
		(0, 0.02, 0.86, 0.2, 0.15),
		(0, 0.0, 1.1, 0.22, 0.16),
		(0, -0.01, 1.32, 0.24, 0.16),
		(0, -0.02, 1.48, 0.26, 0.17),
	], spec["jacket"], sides=20, front=-0.9)
	add_box(arm, "chest", f"{cid}_shirt", (0, -0.08, 1.34), (0.16, 0.06, 0.28), spec["shirt"], soft=True)
	add_box(arm, "chest", f"{cid}_tie", (0, -0.12, 1.28), (0.04, 0.012, 0.3), spec["tie"], soft=False)
	add_box(arm, "hand.R", f"{cid}_case", (-0.58, -0.06, 0.78), (0.08, 0.2, 0.14), (0.05, 0.05, 0.06, 1), soft=True)
	face(arm, cid, skin, False, True)
	hair_cap(arm, cid, (0.06, 0.05, 0.05, 1))


def build_character(arm, spec):
	cid = spec["id"]
	skin = SKIN[cid]
	if cid == "king":
		sculpt_king(arm, spec, skin)
		return
	if cid == "lazy":
		sculpt_lazy(arm, spec, skin)
		return
	if cid == "collector":
		sculpt_collector(arm, spec, skin)
		return
	if cid == "broker":
		sculpt_broker(arm, spec, skin)
		return
	if cid == "hobo":
		sculpt_hobo(arm, spec, skin)
		return
	if cid == "dreads":
		sculpt_dreads(arm, spec, skin)
		return
	limbs(arm, cid, spec["pants"], spec["shoes"], spec["sleeve"], skin, spec.get("fat", 1.0))
	add_box(arm, "spine", f"{cid}_hips", (0, 0, 0.98), spec["hips"], spec["pants"])
	add_box(arm, "chest", f"{cid}_torso", (0, -0.01, 1.3), spec["torso"], spec["shirt"])
	if spec.get("jacket"):
		add_box(arm, "chest", f"{cid}_jacket", (0, 0.0, 1.3), spec["jacket_size"], spec["jacket"], top=spec.get("top", 1.08), bottom=spec.get("bottom", 1.05))
	if spec.get("lining"):
		add_box(arm, "chest", f"{cid}_lining", (0, -0.12, 1.22), spec["lining_size"], spec["lining"])
	if spec.get("tie"):
		add_box(arm, "chest", f"{cid}_tie", (0, -0.14, 1.28), (0.05, 0.02, 0.28), spec["tie"])
	if spec.get("belt"):
		add_box(arm, "spine", f"{cid}_belt", (0, -0.02, 1.02), (0.34, 0.16, 0.05), spec["belt"])
	if spec.get("gut"):
		add_sphere(arm, "spine", f"{cid}_gut", (0, -0.16, 1.08), spec["gut"], spec["shirt"])
	if spec.get("robe"):
		add_cone(arm, "root", f"{cid}_robe", (0, 0, 0.78), (1.15, 0.9, 1.35), spec["robe"])
		add_box(arm, "chest", f"{cid}_cape_l", (-0.28, 0.12, 1.15), (0.28, 0.05, 1.15), spec["cape"], (0, 0.15, 0.35))
		add_box(arm, "chest", f"{cid}_cape_r", (0.28, 0.12, 1.15), (0.28, 0.05, 1.15), spec["cape"], (0, -0.15, -0.35))
		add_sphere(arm, "neck", f"{cid}_fur", (0, -0.02, 1.48), (0.42, 0.34, 0.16), (0.78, 0.78, 0.8, 1))
		add_cyl(arm, "head", f"{cid}_crown", (0, -0.01, 1.86), (0, -0.01, 1.96), 0.13, (0.9, 0.72, 0.18, 1))
		for index, sign in enumerate((-0.08, 0, 0.08)):
			add_cone(arm, "head", f"{cid}_jewel_{index}", (sign, -0.08, 1.98), (0.035, 0.035, 0.08), (0.85, 0.15, 0.12, 1), sharp=True)
	face(arm, cid, skin, spec.get("sleepy", False), not spec.get("sleepy", False))
	if spec.get("mohawk"):
		for index, y in enumerate((-0.04, 0.0, 0.05)):
			add_cone(arm, "head", f"{cid}_hawk_{index}", (0, y, 1.9), (0.07, 0.08, 0.28), (0.05, 0.05, 0.05, 1), sharp=True)
	elif spec.get("dreads"):
		hair_cap(arm, cid, (0.06, 0.04, 0.03, 1), 1.8, (0.3, 0.32, 0.18))
		spots = ((-0.1, 0.02), (-0.04, 0.06), (0.04, 0.06), (0.1, 0.02), (-0.12, -0.02), (0.12, -0.02))
		for index, (x, y) in enumerate(spots):
			add_cyl(arm, "head", f"{cid}_lock_{index}", (x, y, 1.72), (x, y - 0.02, 1.28), 0.02, (0.05, 0.03, 0.02, 1))
		add_box(arm, "chest", f"{cid}_stripe_l", (-0.12, -0.15, 1.28), (0.025, 0.02, 0.42), (0.9, 0.72, 0.12, 1))
		add_box(arm, "chest", f"{cid}_stripe_r", (0.12, -0.15, 1.28), (0.025, 0.02, 0.42), (0.9, 0.72, 0.12, 1))
	elif spec.get("hood"):
		add_sphere(arm, "head", f"{cid}_hood", (0, 0.03, 1.7), (0.34, 0.36, 0.32), spec["shirt"])
		hair_cap(arm, cid, (0.08, 0.06, 0.05, 1), 1.8, (0.22, 0.22, 0.12))
	elif spec.get("messy"):
		hair_cap(arm, cid, (0.28, 0.18, 0.1, 1), 1.78, (0.28, 0.28, 0.16))
		for index, x in enumerate((-0.06, 0, 0.07)):
			add_cone(arm, "head", f"{cid}_tuft_{index}", (x, -0.02, 1.86), (0.04, 0.04, 0.1), (0.28, 0.18, 0.1, 1))
		add_cone(arm, "head", f"{cid}_beard", (0, -0.1, 1.52), (0.16, 0.12, 0.18), (0.22, 0.14, 0.08, 1), (math.pi, 0, 0))
	elif spec.get("white_hair"):
		hair_cap(arm, cid, (0.9, 0.9, 0.92, 1), 1.78, (0.27, 0.28, 0.16))
		add_cone(arm, "head", f"{cid}_beard", (0, -0.1, 1.52), (0.16, 0.12, 0.16), (0.75, 0.75, 0.78, 1), (math.pi, 0, 0))
	else:
		hair_cap(arm, cid, (0.08, 0.06, 0.05, 1))
	if spec.get("spikes"):
		for side, sign in (("L", 1), ("R", -1)):
			for index, z in enumerate((1.46, 1.4, 1.34)):
				add_cone(arm, f"shoulder.{side}", f"{cid}_spike_{side}_{index}", (0.16 * sign, -0.02, z), (0.05, 0.05, 0.1), (0.75, 0.75, 0.78, 1), (0, math.pi / 2 * sign, 0), sharp=True)
	if spec.get("case"):
		add_box(arm, "hand.L", f"{cid}_case", (0.62, -0.05, 0.72), spec["case"], (0.08, 0.07, 0.08, 1))


CAST = [
	{"id": "punk", "pants": (0.45, 0.45, 0.48, 1), "shoes": (0.08, 0.08, 0.08, 1), "sleeve": (0.06, 0.06, 0.06, 1), "shirt": (0.92, 0.92, 0.9, 1), "hips": (0.32, 0.18, 0.2), "torso": (0.34, 0.18, 0.36), "jacket": (0.07, 0.07, 0.08, 1), "jacket_size": (0.46, 0.26, 0.4), "top": 1.18, "bottom": 0.92, "mohawk": True, "spikes": True},
	{"id": "hobo", "pants": (0.28, 0.38, 0.52, 1), "shoes": (0.55, 0.48, 0.34, 1), "sleeve": (0.4, 0.4, 0.42, 1), "shirt": (0.08, 0.08, 0.08, 1), "hips": (0.3, 0.16, 0.18), "torso": (0.3, 0.16, 0.34), "jacket": (0.42, 0.43, 0.45, 1), "jacket_size": (0.5, 0.28, 0.72), "top": 1.12, "bottom": 1.22, "messy": True},
	{"id": "dreads", "pants": (0.06, 0.06, 0.07, 1), "shoes": (0.07, 0.07, 0.08, 1), "sleeve": (0.45, 0.46, 0.48, 1), "shirt": (0.06, 0.06, 0.07, 1), "hips": (0.32, 0.18, 0.18), "torso": (0.32, 0.18, 0.36), "jacket": (0.48, 0.49, 0.52, 1), "jacket_size": (0.42, 0.24, 0.38), "belt": (0.85, 0.68, 0.15, 1), "dreads": True},
	{"id": "lazy", "pants": (0.32, 0.33, 0.35, 1), "shoes": (0.08, 0.08, 0.09, 1), "sleeve": (0.34, 0.35, 0.37, 1), "shirt": (0.38, 0.39, 0.41, 1), "hips": (0.5, 0.32, 0.28), "torso": (0.62, 0.4, 0.48), "fat": 1.45, "gut": (0.55, 0.42, 0.42), "hood": True, "sleepy": True},
	{"id": "collector", "pants": (0.32, 0.33, 0.35, 1), "shoes": (0.06, 0.06, 0.07, 1), "sleeve": (0.07, 0.07, 0.08, 1), "shirt": (0.9, 0.9, 0.92, 1), "hips": (0.32, 0.18, 0.2), "torso": (0.32, 0.18, 0.38), "jacket": (0.06, 0.06, 0.07, 1), "jacket_size": (0.5, 0.26, 0.95), "top": 1.16, "bottom": 1.28, "lining": (0.9, 0.75, 0.1, 1), "lining_size": (0.28, 0.04, 0.7), "tie": (0.06, 0.06, 0.07, 1), "case": (0.12, 0.34, 0.24)},
	{"id": "broker", "pants": (0.55, 0.56, 0.58, 1), "shoes": (0.06, 0.06, 0.07, 1), "sleeve": (0.62, 0.63, 0.65, 1), "shirt": (0.92, 0.92, 0.94, 1), "hips": (0.32, 0.18, 0.2), "torso": (0.4, 0.2, 0.4), "jacket": (0.58, 0.59, 0.62, 1), "jacket_size": (0.48, 0.26, 0.46), "top": 1.14, "bottom": 0.94, "tie": (0.05, 0.05, 0.06, 1), "case": (0.08, 0.22, 0.16)},
	{"id": "king", "pants": (0.82, 0.62, 0.14, 1), "shoes": (0.9, 0.72, 0.18, 1), "sleeve": (0.7, 0.1, 0.12, 1), "shirt": (0.82, 0.62, 0.16, 1), "hips": (0.3, 0.18, 0.18), "torso": (0.3, 0.18, 0.34), "robe": (0.62, 0.08, 0.1, 1), "cape": (0.7, 0.1, 0.12, 1), "white_hair": True},
]


KEEP_TOKENS = ("_eye_", "_pupil_", "_brow_", "_nose", "_mouth", "_hair", "_tuft_", "_beard", "_lock_", "_hawk_", "_crown", "_point_", "_jewel_")
HEROES = {"punk", "hobo", "dreads", "lazy"}


def _segment_distance(point, start, end):
	line = end - start
	length2 = line.length_squared
	if length2 < 1e-8:
		return (point - start).length
	t = max(0.0, min(1.0, (point - start).dot(line) / length2))
	return (point - (start + line * t)).length


def _keep_detail(name):
	return any(token in name for token in KEEP_TOKENS)


def _body_group(obj):
	bone = obj.parent_bone or ""
	if bone.startswith(("upper_arm", "forearm", "hand", "shoulder")):
		return "arms"
	if bone.startswith(("thigh", "shin", "foot")):
		return "legs"
	return "torso"


def _unparent(obj):
	_active(obj)
	bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")


def _join(objects, name):
	bpy.ops.object.mode_set(mode="OBJECT")
	bpy.ops.object.select_all(action="DESELECT")
	for obj in objects:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = objects[0]
	if len(objects) > 1:
		bpy.ops.object.join()
	joined = bpy.context.active_object
	joined.name = name
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	return joined


def _apply_modifier(obj, name):
	_active(obj)
	bpy.ops.object.modifier_apply(modifier=name)


def _smooth_group(obj, budget):
	sub = obj.modifiers.new("Sub", "SUBSURF")
	sub.levels = 1
	sub.render_levels = 1
	_apply_modifier(obj, "Sub")
	faces = len(obj.data.polygons)
	if faces > budget:
		dec = obj.modifiers.new("Decimate", "DECIMATE")
		dec.decimate_type = "COLLAPSE"
		dec.ratio = max(0.05, min(1.0, budget / float(faces)))
		_apply_modifier(obj, "Decimate")
	print("SOFT", obj.name, "faces", len(obj.data.polygons), "budget", budget)


def _weighted(mesh):
	if not mesh.vertex_groups:
		return False
	return all(vert.groups for vert in mesh.data.vertices)


def _force_weights(mesh, arm):
	world = mesh.matrix_world.copy()
	mesh.parent = None
	mesh.matrix_world = world
	mesh.modifiers.clear()
	mesh.vertex_groups.clear()
	bones = list(arm.data.bones)
	groups = {bone.name: mesh.vertex_groups.new(name=bone.name) for bone in bones}
	arm_inv = arm.matrix_world.inverted()
	for vert in mesh.data.vertices:
		co = arm_inv @ (mesh.matrix_world @ vert.co)
		scored = sorted(
			((bone.name, _segment_distance(co, bone.head_local, bone.tail_local)) for bone in bones),
			key=lambda item: item[1],
		)[:2]
		total = sum(1.0 / (dist + 0.04) for _, dist in scored)
		for name, dist in scored:
			groups[name].add([vert.index], (1.0 / (dist + 0.04)) / total, "REPLACE")
	mesh.parent = arm
	mod = mesh.modifiers.new("Armature", "ARMATURE")
	mod.object = arm


def _bind(mesh, arm):
	bpy.ops.object.mode_set(mode="OBJECT")
	bpy.ops.object.select_all(action="DESELECT")
	mesh.select_set(True)
	arm.select_set(True)
	bpy.context.view_layer.objects.active = arm
	try:
		bpy.ops.object.parent_set(type="ARMATURE_AUTO")
	except RuntimeError as exc:
		print("WEIGHT_FAIL", mesh.name, exc)
	if not _weighted(mesh):
		print("WEIGHT_FALLBACK", mesh.name)
		_force_weights(mesh, arm)


def soften(arm, cid, budget):
	groups = {"torso": [], "arms": [], "legs": []}
	shares = {"torso": 0.55, "arms": 0.25, "legs": 0.20}
	for child in list(arm.children):
		if child.type != "MESH" or not child.name.startswith(cid + "_"):
			continue
		if _keep_detail(child.name):
			continue
		groups[_body_group(child)].append(child)
	for name, pieces in groups.items():
		if not pieces:
			continue
		for piece in pieces:
			_unparent(piece)
		mesh = _join(pieces, f"{cid}_{name}")
		_smooth_group(mesh, max(200, int(budget * shares[name])))
		_bind(mesh, arm)


def clone_arm(master, name):
	bpy.ops.object.mode_set(mode="OBJECT")
	bpy.ops.object.select_all(action="DESELECT")
	master.hide_set(False)
	master.select_set(True)
	bpy.context.view_layer.objects.active = master
	bpy.ops.object.duplicate(linked=False)
	arm = bpy.context.active_object
	arm.name = name
	arm.location = (0.0, 0.0, 0.0)
	arm.hide_set(False)
	bpy.context.view_layer.update()
	return arm


def export_arm(arm, path):
	bpy.ops.object.mode_set(mode="OBJECT")
	bpy.ops.object.select_all(action="DESELECT")
	arm.select_set(True)
	for child in arm.children_recursive:
		child.select_set(True)
	bpy.context.view_layer.objects.active = arm
	if arm.animation_data:
		arm.animation_data.action = None
		for track in arm.animation_data.nla_tracks:
			track.mute = False
	props = bpy.ops.export_scene.gltf.get_rna_type().properties
	kwargs = {
		"filepath": path,
		"export_format": "GLB",
		"use_selection": True,
		"export_yup": True,
		"export_animations": True,
	}
	if "export_animation_mode" in props:
		idents = [item.identifier for item in props["export_animation_mode"].enum_items]
		print("ANIM_MODES", idents)
		if "NLA_TRACKS" in idents:
			kwargs["export_animation_mode"] = "NLA_TRACKS"
		elif "ACTIONS" in idents:
			kwargs["export_animation_mode"] = "ACTIONS"
	bpy.ops.export_scene.gltf(**kwargs)
	if arm.animation_data:
		for track in arm.animation_data.nla_tracks:
			track.mute = True
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.mode_set(mode="POSE")
	bpy.ops.pose.transforms_clear()
	bpy.ops.object.mode_set(mode="OBJECT")


def main():
	os.makedirs(OUT_DIR, exist_ok=True)
	os.makedirs(os.path.dirname(BLEND), exist_ok=True)
	clear_scene()
	master = build_armature()
	animate(master)
	master.hide_set(True)
	for index, spec in enumerate(CAST):
		arm = clone_arm(master, f"rig_{spec['id']}")
		build_character(arm, spec)
		budget = 6000 if spec["id"] in HEROES else 4000
		soften(arm, spec["id"], budget)
		export_arm(arm, os.path.join(OUT_DIR, f"{spec['id']}.glb"))
		arm.location.x = (index - 3) * 2.3
		print("EXPORTED", spec["id"], "children", len(list(arm.children)))
	bpy.ops.wm.save_as_mainfile(filepath=BLEND)
	print("CAST_RIG_OK", BLEND)


if __name__ == "__main__":
	main()
