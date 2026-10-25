"""Rig the T-pose source meshes with a T rest so sleeves stay on the arms.

Run inside Blender: fit("punk") imports assets/sources/punk_t.glb and builds
punk_body + punk_rig with every clip. Heroes get Hold1H and Hold2H, enemies get
Hit. Clips are bone rotations only. Mesh vertices are never edited beyond the
uniform scale and placement on import. Does not touch build_cast_rig.main().
"""
import json
import math
import os
import struct

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = r"c:\Users\sudol\arenaOfStonksness"
SRC = os.path.join(ROOT, "assets", "sources")
OUT = os.path.join(ROOT, "assets", "characters")
HEIGHT = 1.8
FPS = 30

HEROES = ("punk", "hobo", "dreads", "lazy")
ENEMIES = ("collector", "broker", "king")
HERO_CLIPS = ("Idle", "Walk", "Run", "Jump", "Climb", "Death", "Hold1H", "Hold2H")
ENEMY_CLIPS = ("Idle", "Walk", "Run", "Jump", "Climb", "Death", "Hit")

# Guns import 1 m long with the muzzle on local +Y and the grip hanging toward -Z.
# Each entry: scale, grip centre in local space, half the grip width in metres after scaling.
GUNS = {
	"pipe_pistol": (0.28, Vector((0.0, -0.39, -0.18)), 0.026),
	"street_smg": (0.48, Vector((0.0, -0.11, -0.06)), 0.0165),
	"rent_rifle": (0.68, Vector((0.0, -0.22, -0.05)), 0.013),
}
# The mitten's palm surface sits on the hand bone line; grips sink this far into it.
GRIP_SINK = 0.004

ARM = ("shoulder", "upper_arm", "forearm", "hand")
LEG = ("thigh", "shin", "foot")
ORDER = ["root", "spine", "chest", "neck", "head"]
for _side in ("L", "R"):
	ORDER += [n + "." + _side for n in ARM]
for _side in ("L", "R"):
	ORDER += [n + "." + _side for n in LEG]


def V(x, y, z):
	return Vector((x, y, z)).normalized()


def down(fwd=0.0, out=0.0, sx=1.0):
	"""Straight down, swung forward (toward -Y) by fwd degrees and outward by out degrees."""
	f = math.radians(fwd)
	o = math.radians(out)
	return Vector((sx * math.sin(o), -math.sin(f) * math.cos(o), -math.cos(f) * math.cos(o)))


# ---------------------------------------------------------------- import


def _import(path):
	if bpy.context.mode != "OBJECT":
		bpy.ops.object.mode_set(mode="OBJECT")
	before = set(bpy.data.objects)
	bpy.ops.import_scene.gltf(filepath=path)
	new = [o for o in bpy.data.objects if o not in before]
	names = [o.name for o in new]
	meshes = [o for o in new if o.type == "MESH"]
	if not meshes:
		raise RuntimeError("no mesh in " + path)
	for o in meshes:
		mw = o.matrix_world.copy()
		o.parent = None
		o.matrix_world = mw
	bpy.ops.object.select_all(action="DESELECT")
	for o in meshes:
		o.select_set(True)
	bpy.context.view_layer.objects.active = meshes[0]
	if len(meshes) > 1:
		bpy.ops.object.join()
	obj = bpy.context.view_layer.objects.active
	for name in names:
		other = bpy.data.objects.get(name)
		if other is not None and other != obj:
			bpy.data.objects.remove(other, do_unlink=True)
	obj.data.transform(obj.matrix_world)
	obj.matrix_world = Matrix.Identity(4)
	return obj


def _bounds(obj):
	vs = [v.co for v in obj.data.vertices]
	lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
	hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
	return lo, hi


def _faces_minus_y(obj):
	vs = [v.co for v in obj.data.vertices]
	shin = [v.y for v in vs if 0.18 < v.z < 0.3]
	feet = [v.y for v in vs if v.z < 0.06]
	if not shin or not feet:
		return True
	mid = (min(shin) + max(shin)) / 2
	return (mid - min(feet)) >= (max(feet) - mid)


def normalize(char_id):
	obj = _import(os.path.join(SRC, char_id + "_t.glb"))
	obj.name = char_id + "_body"
	obj.data.name = char_id + "_body"
	lo, hi = _bounds(obj)
	span = hi - lo
	if span.z < span.y or span.x < span.y:
		raise RuntimeError(char_id + " is not a Z-up T-pose " + str(tuple(round(s, 3) for s in span)))
	obj.data.transform(Matrix.Scale(HEIGHT / span.z, 4))
	lo, hi = _bounds(obj)
	obj.data.transform(Matrix.Translation(Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z))))
	if not _faces_minus_y(obj):
		obj.data.transform(Matrix.Rotation(math.pi, 4, "Z"))
		print("TURNED", char_id)
	obj.data.update()
	return obj


# ---------------------------------------------------------------- measure


def _fit_line(pts):
	"""Least squares v = a + b * t over (t, v) pairs."""
	n = len(pts)
	if n == 0:
		return 0.0, 0.0
	st = sum(t for t, _ in pts)
	sv = sum(v for _, v in pts)
	stt = sum(t * t for t, _ in pts)
	stv = sum(t * v for t, v in pts)
	den = n * stt - st * st
	if n < 2 or abs(den) < 1e-9:
		return sv / n, 0.0
	b = (n * stv - st * sv) / den
	return (sv - b * st) / n, b


def measure(obj):
	vs = [v.co.copy() for v in obj.data.vertices]
	top = max(v.z for v in vs)
	tip_z = max(vs, key=lambda v: abs(v.x)).z
	ribs = [abs(v.x) for v in vs if abs(v.z - (tip_z - 0.2)) < 0.05]
	torso = max(0.12, min(max(ribs) if ribs else 0.18, 0.27))
	m = {"top": top, "torso": torso}
	for side, sx in (("L", 1.0), ("R", -1.0)):
		reach = max(sx * v.x for v in vs)
		span = reach - torso
		zs, ys, thick = [], [], []
		x = torso + span * 0.15
		while x <= torso + span * 0.8:
			band = [v for v in vs if abs(sx * v.x - x) < 0.012 and v.z > tip_z - 0.3]
			if len(band) >= 4:
				lo = min(v.z for v in band)
				hi = max(v.z for v in band)
				zs.append((x, (lo + hi) / 2))
				ys.append((x, (min(v.y for v in band) + max(v.y for v in band)) / 2))
				thick.append((hi - lo) / 2)
			x += 0.015
		za, zb = _fit_line(zs)
		ya, yb = _fit_line(ys)
		thick.sort()
		m["arm" + side] = {
			"reach": reach, "za": za, "zb": zb, "ya": ya, "yb": yb,
			"r": thick[len(thick) // 2] if thick else 0.06,
		}
	m["sh_z"] = sum(m["arm" + s]["za"] + m["arm" + s]["zb"] * torso for s in "LR") / 2

	center = [v.z for v in vs if abs(v.x) < 0.015 and 0.25 < v.z < 1.2]
	crotch = min(center) if center else 0.0
	hip = crotch + 0.05 if crotch > HEIGHT * 0.36 else m["sh_z"] * 0.62
	m["crotch"] = crotch
	m["hip_z"] = max(HEIGHT * 0.42, min(hip, HEIGHT * 0.56))
	for side, sx in (("L", 1.0), ("R", -1.0)):
		xs, ys = [], []
		z = 0.15
		while z < m["hip_z"] - 0.12:
			band = [v for v in vs if abs(v.z - z) < 0.012 and sx * v.x > 0.012 and abs(v.x) < torso + 0.12]
			if len(band) >= 4:
				xs.append((z, (min(v.x for v in band) + max(v.x for v in band)) / 2))
				ys.append((z, (min(v.y for v in band) + max(v.y for v in band)) / 2))
			z += 0.03
		xa, xb = _fit_line(xs)
		ya, yb = _fit_line(ys)
		toe = min((v.y for v in vs if v.z < 0.08 and sx * v.x > 0.0), default=-0.12)
		m["leg" + side] = {"xa": xa, "xb": xb, "ya": ya, "yb": yb, "toe": toe}

	best, neck = 9.0, m["sh_z"] + 0.12
	z = m["sh_z"] + 0.03
	while z < min(m["sh_z"] + 0.24, top - 0.12):
		band = [v.x for v in vs if abs(v.z - z) < 0.01 and abs(v.x) < torso * 0.85]
		if len(band) > 6 and max(band) - min(band) < best:
			best, neck = max(band) - min(band), z
		z += 0.01
	m["neck"] = neck

	px = torso * 0.6
	near = [v.y for v in vs if abs(v.x + px) < 0.04 and abs(v.z - (m["sh_z"] - 0.04)) < 0.04]
	m["front"] = min(near) if near else -0.12

	reach_r = m["armR"]["reach"]
	hand = [v for v in vs if -v.x > reach_r - 0.1]
	ey = max(v.y for v in hand) - min(v.y for v in hand)
	ez = max(v.z for v in hand) - min(v.z for v in hand)
	m["palm_down"] = ez <= ey
	return m


# ---------------------------------------------------------------- rig


def _bone(ed, name, head, tail, parent, up):
	b = ed.new(name)
	b.head = Vector(head)
	b.tail = Vector(tail)
	if parent is not None:
		b.parent = parent
		b.use_connect = (b.head - parent.tail).length < 1e-4
	b.align_roll(Vector(up))
	return b


def build_armature(obj, m):
	data = bpy.data.armatures.new(obj.name.replace("_body", "_rig"))
	arm = bpy.data.objects.new(data.name, data)
	bpy.context.scene.collection.objects.link(arm)
	arm.show_in_front = False
	bpy.ops.object.select_all(action="DESELECT")
	arm.select_set(True)
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.mode_set(mode="EDIT")
	ed = data.edit_bones
	up = (0.0, 0.0, 1.0)
	fwd = (0.0, -1.0, 0.0)
	hip = m["hip_z"]
	sh = m["sh_z"]
	torso = m["torso"]
	# root sits a little above the hip joint so Death tips the body onto the Godot floor drop
	root = _bone(ed, "root", (0, 0, hip + 0.03), (0, 0, hip + 0.11), None, fwd)
	spine = _bone(ed, "spine", root.tail, (0, 0, (root.tail.z + sh) / 2), root, fwd)
	chest = _bone(ed, "chest", spine.tail, (0, 0, sh), spine, fwd)
	neck = _bone(ed, "neck", (0, 0, m["neck"] - 0.04), (0, 0, m["neck"] + 0.05), chest, fwd)
	_bone(ed, "head", neck.tail, (0, 0, m["top"] - 0.02), neck, fwd)
	for side, sx in (("L", 1.0), ("R", -1.0)):
		a = m["arm" + side]

		def along(x):
			return Vector((sx * x, a["ya"] + a["yb"] * x, a["za"] + a["zb"] * x))

		start = along(torso)
		tip = along(a["reach"])
		shoulder = _bone(ed, "shoulder." + side, (sx * torso * 0.35, start.y, start.z), start, chest, up)
		upper = _bone(ed, "upper_arm." + side, start, start.lerp(tip, 0.46), shoulder, up)
		fore = _bone(ed, "forearm." + side, upper.tail, start.lerp(tip, 0.77), upper, up)
		_bone(ed, "hand." + side, fore.tail, tip, fore, up)

		g = m["leg" + side]

		def leg(z):
			return Vector((g["xa"] + g["xb"] * z, g["ya"] + g["yb"] * z, z))

		ankle = 0.07
		knee = ankle + (hip - ankle) * 0.48
		thigh = _bone(ed, "thigh." + side, leg(hip), leg(knee), root, fwd)
		shin = _bone(ed, "shin." + side, thigh.tail, leg(ankle), thigh, fwd)
		_bone(ed, "foot." + side, shin.tail, (shin.tail.x, g["toe"] * 0.7, 0.02), shin, up)
	bpy.ops.object.mode_set(mode="OBJECT")
	return arm


def _seg_dist(p, a, b):
	ab = b - a
	den = ab.length_squared
	t = 0.0 if den < 1e-9 else max(0.0, min(1.0, (p - a).dot(ab) / den))
	return (p - (a + ab * t)).length


def _smooth(e0, e1, x):
	t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
	return t * t * (3.0 - 2.0 * t)


def _nearest(p, segs, cands):
	scored = sorted((_seg_dist(p, *segs[n]), n) for n in cands)[:2]
	raw = [1.0 / max(d, 0.015) for d, _ in scored]
	total = sum(raw)
	return [(name, w / total) for (_, name), w in zip(scored, raw)]


def weight(obj, arm, m):
	"""Sleeves go to the arm chain, everything inside the ribcage stays on the spine.

	The shoulder blends from chest to arm over a few centimetres so a raised arm
	stretches the armpit instead of tearing a flap off the jacket.
	"""
	for group in list(obj.vertex_groups):
		obj.vertex_groups.remove(group)
	segs = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in arm.data.bones}
	groups = {name: obj.vertex_groups.new(name=name) for name in segs}
	torso = m["torso"]
	hip = m["hip_z"]
	neck = m["neck"]
	sh = m["sh_z"]
	for v in obj.data.vertices:
		p = v.co
		ax = abs(p.x)
		side = "L" if p.x >= 0.0 else "R"
		if p.z > neck - 0.03 and ax < torso * 0.62:
			mix = _nearest(p, segs, ("head", "neck", "chest"))
		elif p.z < hip + 0.03 and ax > 0.025:
			mix = _nearest(p, segs, tuple(n + "." + side for n in LEG) + ("root",))
		else:
			a = m["arm" + side]
			underside = a["za"] + a["zb"] * ax - a["r"]
			reach_arm = _smooth(torso - 0.05, torso + 0.06, ax) * _smooth(underside - 0.07, underside + 0.005, p.z)
			if p.z < hip + 0.15:
				reach_arm = 0.0
			body = ("root", "spine", "chest")
			if p.z > sh - 0.12:
				body += ("neck", "shoulder." + side)
			mix = [(n, w * (1.0 - reach_arm)) for n, w in _nearest(p, segs, body)]
			if reach_arm > 0.0:
				limb = tuple(n + "." + side for n in ("upper_arm", "forearm", "hand"))
				mix += [(n, w * reach_arm) for n, w in _nearest(p, segs, limb)]
		for name, w in mix:
			if w > 1e-4:
				groups[name].add([v.index], w, "ADD")
	mod = obj.modifiers.get("Armature") or obj.modifiers.new("Armature", "ARMATURE")
	mod.object = arm
	obj.parent = arm
	obj.matrix_parent_inverse = Matrix.Identity(4)


# ---------------------------------------------------------------- pose


def zero_pose(arm):
	for pb in arm.pose.bones:
		pb.rotation_mode = "QUATERNION"
		pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
		pb.location = (0.0, 0.0, 0.0)
		pb.scale = (1.0, 1.0, 1.0)
	bpy.context.view_layer.update()


def set_dir(pb, direction, z_hint=None):
	"""Turn the bone so it points along direction (armature space). z_hint fixes the twist."""
	pb.rotation_mode = "QUATERNION"
	pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
	bpy.context.view_layer.update()
	cur = (pb.tail - pb.head).normalized()
	want = Vector(direction).normalized()
	mat = cur.rotation_difference(want).to_matrix().to_4x4() @ pb.matrix
	if z_hint is not None:
		hint = Vector(z_hint)
		hint = hint - want * hint.dot(want)
		now = mat.col[2].xyz
		now = now - want * now.dot(want)
		if hint.length > 1e-4 and now.length > 1e-4:
			hint.normalize()
			now.normalize()
			ang = math.atan2(want.dot(now.cross(hint)), now.dot(hint))
			mat = Quaternion(want, ang).to_matrix().to_4x4() @ mat
	mat.translation = pb.head
	pb.matrix = mat
	bpy.context.view_layer.update()


def apply_pose(arm, pose):
	zero_pose(arm)
	for name in ORDER:
		spec = pose.get(name)
		if spec is None:
			continue
		if isinstance(spec, tuple) and len(spec) == 2:
			set_dir(arm.pose.bones[name], spec[0], spec[1])
		else:
			set_dir(arm.pose.bones[name], spec)


def capture(arm):
	return {
		pb.name: ((pb.tail - pb.head).normalized(), pb.matrix.col[2].xyz.normalized())
		for pb in arm.pose.bones
	}


def reach(arm, side, wrist, pole):
	"""Two-bone arm solve: wrist lands on the target, elbow bends toward pole."""
	upper = arm.pose.bones["upper_arm." + side]
	fore = arm.pose.bones["forearm." + side]
	bpy.context.view_layer.update()
	start = upper.head.copy()
	l1 = upper.bone.length
	l2 = fore.bone.length
	d = Vector(wrist) - start
	dist = max(abs(l1 - l2) + 0.01, min(d.length, l1 + l2 - 0.002))
	dn = d.normalized()
	a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
	h = math.sqrt(max(l1 * l1 - a * a, 0.0))
	bend = Vector(pole) - dn * Vector(pole).dot(dn)
	bend.normalize()
	elbow = start + dn * a + bend * h
	set_dir(upper, elbow - start)
	set_dir(fore, start + dn * dist - elbow)
	return d.length - dist


def hand_z(m, side, direction, palm):
	"""Bone z that makes the flat of the hand face palm."""
	y = Vector(direction).normalized()
	palm = Vector(palm).normalized()
	if m["palm_down"]:
		return -palm
	x = -palm if side == "R" else palm
	return x.cross(y)


def palm_of(m, side, pb):
	if m["palm_down"]:
		return -pb.matrix.col[2].xyz.normalized()
	x = pb.matrix.col[0].xyz.normalized()
	return -x if side == "R" else x


def _mirror(pose):
	out = {}
	for name, spec in pose.items():
		if name.endswith(".L"):
			key = name[:-2] + ".R"
		elif name.endswith(".R"):
			key = name[:-2] + ".L"
		else:
			key = name
		if isinstance(spec, tuple) and len(spec) == 2:
			out[key] = tuple(Vector((-v[0], v[1], v[2])) for v in spec)
		else:
			out[key] = Vector((-spec[0], spec[1], spec[2]))
	return out


def _foot(arm, side, pitch):
	"""Rest foot direction pitched toes-down by pitch degrees."""
	b = arm.data.bones["foot." + side]
	rest = (b.tail_local - b.head_local).normalized()
	return Matrix.Rotation(math.radians(pitch), 3, "X") @ rest


# ---------------------------------------------------------------- clips


def body_clips(arm):
	def foot(side, pitch):
		return _foot(arm, side, pitch)

	hang = {
		"upper_arm.L": down(2, 8, 1), "forearm.L": down(10, 6, 1),
		"upper_arm.R": down(2, 8, -1), "forearm.R": down(10, 6, -1),
	}
	breathe = dict(hang)
	breathe.update({
		"chest": V(0, -0.04, 1), "head": V(0, -0.07, 1),
		"upper_arm.L": down(3, 11, 1), "upper_arm.R": down(3, 11, -1),
	})

	step = {
		"spine": V(0, -0.05, 1),
		"thigh.L": down(-35), "shin.L": down(-48), "foot.L": foot("L", 35),
		"thigh.R": down(20), "shin.R": down(-30), "foot.R": foot("R", 10),
		"upper_arm.L": down(28, 6, 1), "forearm.L": down(50, 4, 1),
		"upper_arm.R": down(-25, 6, -1), "forearm.R": down(-10, 4, -1),
	}
	passing = {
		"spine": V(0, -0.04, 1),
		"thigh.L": down(-5), "shin.L": down(-28), "foot.L": foot("L", 25),
		"thigh.R": down(-5), "shin.R": down(-12), "foot.R": foot("R", 0),
		"upper_arm.L": down(4, 7, 1), "forearm.L": down(15, 5, 1),
		"upper_arm.R": down(-2, 7, -1), "forearm.R": down(10, 5, -1),
	}

	lean = {"spine": V(0, -0.2, 1), "chest": V(0, -0.24, 1), "head": V(0, -0.05, 1)}
	stride = dict(lean)
	stride.update({
		"thigh.L": down(-38), "shin.L": down(-95), "foot.L": foot("L", 60),
		"thigh.R": down(50), "shin.R": down(5), "foot.R": foot("R", 5),
		"upper_arm.L": down(45, 10, 1), "forearm.L": down(135, 5, 1),
		"upper_arm.R": down(-45, 10, -1), "forearm.R": down(40, 5, -1),
	})
	run_pass = dict(lean)
	run_pass.update({
		"thigh.L": down(10), "shin.L": down(-70), "foot.L": foot("L", 40),
		"thigh.R": down(-8), "shin.R": down(-18), "foot.R": foot("R", 5),
		"upper_arm.L": down(5, 10, 1), "forearm.L": down(80, 5, 1),
		"upper_arm.R": down(-5, 10, -1), "forearm.R": down(80, 5, -1),
	})

	crouch = {
		"spine": V(0, -0.25, 1), "chest": V(0, -0.3, 1), "head": V(0, -0.1, 1),
		"thigh.L": down(40, 4, 1), "shin.L": down(-35), "foot.L": foot("L", 0),
		"thigh.R": down(40, 4, -1), "shin.R": down(-35), "foot.R": foot("R", 0),
		"upper_arm.L": down(-40, 10, 1), "forearm.L": down(-20, 8, 1),
		"upper_arm.R": down(-40, 10, -1), "forearm.R": down(-20, 8, -1),
	}
	launch = {
		"spine": V(0, 0.05, 1), "chest": V(0, 0.05, 1),
		"thigh.L": down(-5), "shin.L": down(-8), "foot.L": foot("L", 50),
		"thigh.R": down(-5), "shin.R": down(-8), "foot.R": foot("R", 50),
		"upper_arm.L": V(0.3, -0.35, 0.89), "forearm.L": V(0.15, -0.3, 0.94),
		"upper_arm.R": V(-0.3, -0.35, 0.89), "forearm.R": V(-0.15, -0.3, 0.94),
	}
	tuck = {
		"spine": V(0, -0.15, 1), "chest": V(0, -0.15, 1),
		"thigh.L": down(65, 6, 1), "shin.L": down(-20), "foot.L": foot("L", 25),
		"thigh.R": down(65, 6, -1), "shin.R": down(-20), "foot.R": foot("R", 25),
		"upper_arm.L": V(0.35, -0.75, 0.55), "forearm.L": V(0.1, -0.8, 0.6),
		"upper_arm.R": V(-0.35, -0.75, 0.55), "forearm.R": V(-0.1, -0.8, 0.6),
	}
	land = dict(hang)
	land.update({
		"spine": V(0, -0.15, 1), "chest": V(0, -0.15, 1),
		"thigh.L": down(25, 4, 1), "shin.L": down(-20), "foot.L": foot("L", 0),
		"thigh.R": down(25, 4, -1), "shin.R": down(-20), "foot.R": foot("R", 0),
	})

	grab = {
		"spine": V(0, -0.1, 1), "chest": V(0, -0.12, 1), "head": V(0, -0.1, 1),
		"upper_arm.L": V(0.22, -0.45, 0.87), "forearm.L": V(0.1, -0.45, 0.89), "hand.L": V(0.05, -0.6, 0.8),
		"upper_arm.R": V(-0.22, -0.45, 0.87), "forearm.R": V(-0.1, -0.45, 0.89), "hand.R": V(-0.05, -0.6, 0.8),
	}
	pull = {
		"spine": V(0, -0.35, 1), "chest": V(0, -0.45, 1), "head": V(0, -0.3, 1),
		"upper_arm.L": V(0.35, -0.6, -0.72), "forearm.L": V(0.1, -0.5, 0.86),
		"upper_arm.R": V(-0.35, -0.6, -0.72), "forearm.R": V(-0.1, -0.5, 0.86),
		"thigh.L": down(70, 5, 1), "shin.L": down(-10), "foot.L": foot("L", 20),
	}
	over = {
		"spine": V(0, -0.75, 0.66), "chest": V(0, -0.9, 0.44), "head": V(0, -0.8, 0.6),
		"upper_arm.L": V(0.25, -0.35, -0.9), "forearm.L": V(0.1, 0.0, -1),
		"upper_arm.R": V(-0.25, -0.35, -0.9), "forearm.R": V(-0.1, 0.0, -1),
		"thigh.L": down(-30), "shin.L": down(-90), "foot.L": foot("L", 40),
		"thigh.R": down(-45), "shin.R": down(-100), "foot.R": foot("R", 40),
	}
	settle = dict(hang)
	settle.update({"spine": V(0, -0.1, 1), "chest": V(0, -0.1, 1)})

	slump = {
		"root": V(0, -0.64, 0.77), "spine": V(0, -0.75, 0.66), "chest": V(0, -0.8, 0.6),
		"upper_arm.L": V(0.55, -0.65, -0.52), "forearm.L": V(0.4, -0.8, -0.45),
		"upper_arm.R": V(-0.55, -0.65, -0.52), "forearm.R": V(-0.4, -0.8, -0.45),
	}
	flat = {
		"root": V(0, -0.985, 0.17), "spine": V(0, -0.99, 0.12), "chest": V(0, -0.995, 0.08),
		"head": (V(0.25, -0.97, -0.05), V(0.6, 0, -0.8)),
		"upper_arm.L": V(0.5, -0.85, -0.15), "forearm.L": V(0.3, -0.95, -0.1),
		"upper_arm.R": V(-0.5, -0.85, -0.15), "forearm.R": V(-0.3, -0.95, -0.1),
		"thigh.L": V(0.1, 0.995, -0.03), "thigh.R": V(-0.08, 0.995, -0.03),
		"foot.L": V(0.05, 0.97, -0.2), "foot.R": V(-0.05, 0.97, -0.2),
	}

	return {
		"Idle": [(1, hang), (20, breathe), (40, hang)],
		"Walk": [(1, step), (7, passing), (13, _mirror(step)), (19, _mirror(passing)), (25, step)],
		"Run": [(1, stride), (5, run_pass), (9, _mirror(stride)), (13, _mirror(run_pass)), (17, stride)],
		"Jump": [(1, hang), (5, crouch), (9, launch), (14, tuck), (20, land), (26, hang)],
		"Climb": [(1, grab), (10, pull), (20, over), (32, settle)],
		"Death": [(1, hang), (8, slump), (20, flat)],
	}


def hit_clip(hang):
	windup = dict(hang)
	windup.update({
		"chest": (V(0, -0.03, 1), V(-0.3, -0.95, 0)),
		"upper_arm.R": V(-0.55, 0.45, -0.7), "forearm.R": V(-0.25, -0.55, 0.8),
	})
	strike = dict(hang)
	strike.update({
		"spine": V(0, -0.12, 1), "chest": (V(0, -0.1, 1), V(0.35, -0.94, 0)),
		"upper_arm.R": V(0.1, -0.97, 0.12), "forearm.R": V(0.2, -0.97, 0.05), "hand.R": V(0.15, -0.98, 0),
	})
	return [(1, windup), (7, strike), (16, hang)]


def hold1(m, hang):
	"""One hand: right arm out front, hand upright with the palm facing in, left arm down."""
	hand = V(0, -1, -0.08)
	return {
		"spine": V(0, -0.06, 1),
		"shoulder.R": V(-0.78, -0.59, 0.2),
		"upper_arm.R": V(-0.35, -0.75, -0.15),
		"forearm.R": V(0.15, -0.95, -0.12),
		"hand.R": (hand, hand_z(m, "R", hand, (1, 0, 0))),
		"upper_arm.L": hang["upper_arm.L"],
		"forearm.L": hang["forearm.L"],
	}


def hold2(arm, m, rifle):
	"""Shouldered rifle. Returns the pose, the rifle world matrix, and how far each wrist fell short."""
	foot_l = _foot(arm, "L", 0)
	foot_r = _foot(arm, "R", 0)
	base = {
		"spine": (V(0, -0.08, 1), V(-0.17, -0.98, 0)),
		"chest": (V(0, -0.1, 1), V(-0.42, -0.91, 0)),
		"neck": (V(-0.05, -0.2, 1), V(0.1, -1, -0.1)),
		"head": (V(-0.14, -0.32, 0.94), V(0.2, -1, -0.25)),
		"shoulder.R": V(-0.97, 0.0, 0.24),
		"shoulder.L": V(0.7, -0.7, 0.1),
		"thigh.L": down(9, 3, 1), "shin.L": down(5, 3, 1), "foot.L": foot_l,
		"thigh.R": down(-9, 3, -1), "shin.R": down(-12, 3, -1), "foot.R": foot_r,
	}
	apply_pose(arm, base)
	chest = arm.pose.bones["chest"]
	pocket = Vector((-m["torso"] * 0.6, m["front"], m["sh_z"] + 0.03))
	pocket = chest.matrix @ chest.bone.matrix_local.inverted() @ pocket
	scale, grip, half = GUNS["rent_rifle"]
	turn = Matrix.Rotation(math.pi, 4, "Z")
	offset = turn.to_3x3() @ (rifle["butt"] * scale)
	world = Matrix.Translation(pocket - offset) @ turn @ Matrix.Diagonal((scale, scale, scale, 1.0))
	grip_w = world @ grip
	fore_w = world @ rifle["fore"]
	hand_r = V(0, -0.8, -0.6)
	hand_l = V(-0.35, -0.93, 0.05)
	short_r = reach(arm, "R", grip_w - hand_r * 0.06 - Vector((1, 0, 0)) * (half - GRIP_SINK), (-1, 0.15, -0.35))
	set_dir(arm.pose.bones["hand.R"], hand_r, hand_z(m, "R", hand_r, (1, 0, 0)))
	short_l = reach(arm, "L", fore_w - hand_l * 0.06 - Vector((0, 0, 1)) * (0.01 - GRIP_SINK), (0.45, 0.1, -1))
	set_dir(arm.pose.bones["hand.L"], hand_l, hand_z(m, "L", hand_l, (0, 0, 1)))
	return capture(arm), world, (short_r, short_l)


# ---------------------------------------------------------------- keys


def key_clips(arm, clips):
	bpy.context.scene.render.fps = FPS
	mods = [mod for child in arm.children for mod in getattr(child, "modifiers", []) if mod.type == "ARMATURE"]
	for mod in mods:
		mod.show_viewport = False
	try:
		_key_clips(arm, clips)
	finally:
		for mod in mods:
			mod.show_viewport = True


def _key_clips(arm, clips):
	ad = arm.animation_data_create()
	ad.action = None
	for track in list(ad.nla_tracks):
		ad.nla_tracks.remove(track)
	for clip, keys in clips.items():
		name = arm.name + "_" + clip
		old = bpy.data.actions.get(name)
		if old is not None:
			bpy.data.actions.remove(old)
		action = bpy.data.actions.new(name)
		last = {}
		for frame, pose in keys:
			ad.action = None
			apply_pose(arm, pose)
			quats = {}
			for pb in arm.pose.bones:
				q = pb.rotation_quaternion.copy()
				prev = last.get(pb.name)
				if prev is not None and prev.dot(q) < 0.0:
					q.negate()
				quats[pb.name] = q
				last[pb.name] = q
			ad.action = action
			if getattr(ad, "action_slot", None) is None and len(getattr(action, "slots", [])):
				ad.action_slot = action.slots[0]
			for pb in arm.pose.bones:
				pb.rotation_mode = "QUATERNION"
				pb.rotation_quaternion = quats[pb.name]
				pb.keyframe_insert("rotation_quaternion", frame=frame)
		ad.action = None
		track = ad.nla_tracks.new()
		track.name = clip
		strip = track.strips.new(clip, int(action.frame_range[0]), action)
		if hasattr(strip, "action_slot") and strip.action_slot is None and len(action.slots):
			try:
				strip.action_slot = action.slots[0]
			except (AttributeError, TypeError, RuntimeError):
				pass
		track.mute = True
	zero_pose(arm)


def clips_for(char_id, arm, m):
	clips = body_clips(arm)
	hang = clips["Idle"][0][1]
	if char_id in HEROES:
		one = hold1(m, hang)
		two, world, short = hold2(arm, m, rifle_points())
		arm["rifle_world"] = [v for row in world for v in row]
		arm["reach_short"] = list(short)
		clips["Hold1H"] = [(1, one), (16, one)]
		clips["Hold2H"] = [(1, two), (16, two)]
	else:
		clips["Hit"] = hit_clip(hang)
	return clips


def _cleanup(char_id):
	hide_guns()
	for name in (char_id + "_body", char_id + "_rig"):
		old = bpy.data.objects.get(name)
		if old is not None:
			bpy.data.objects.remove(old, do_unlink=True)
	for act in list(bpy.data.actions):
		if act.name.startswith(char_id + "_rig_") and act.users == 0:
			bpy.data.actions.remove(act)
	for mesh in list(bpy.data.meshes):
		if mesh.name.startswith(char_id + "_body") and mesh.users == 0:
			bpy.data.meshes.remove(mesh)
	for data in list(bpy.data.armatures):
		if data.name.startswith(char_id + "_rig") and data.users == 0:
			bpy.data.armatures.remove(data)


def fit(char_id, clips=True):
	if bpy.context.mode != "OBJECT":
		bpy.ops.object.mode_set(mode="OBJECT")
	_cleanup(char_id)
	obj = normalize(char_id)
	m = measure(obj)
	arm = build_armature(obj, m)
	weight(obj, arm, m)
	arm["fit"] = json.dumps({k: v for k, v in m.items() if isinstance(v, (int, float, bool))})
	if clips:
		key_clips(arm, clips_for(char_id, arm, m))
	return arm, m


def fit_clips(char_id):
	"""Re-key the clips on an existing rig without refitting the mesh."""
	arm = bpy.data.objects[char_id + "_rig"]
	body = bpy.data.objects[char_id + "_body"]
	m = measure_rest(body)
	key_clips(arm, clips_for(char_id, arm, m))
	return arm, m


def measure_rest(body):
	return measure(body)


# ---------------------------------------------------------------- guns and preview


def load_guns():
	for gun in GUNS:
		name = "prev_" + gun
		if bpy.data.objects.get(name) is None:
			obj = _import(os.path.join(SRC, gun + ".glb"))
			obj.name = name
			obj.hide_set(True)


def rifle_points():
	load_guns()
	vs = [v.co for v in bpy.data.objects["prev_rent_rifle"].data.vertices]
	back_y = min(v.y for v in vs)
	back = [v for v in vs if v.y < back_y + 0.05]
	butt = Vector((0.0, back_y, (min(v.z for v in back) + max(v.z for v in back)) / 2))
	mid = [v for v in vs if 0.08 < v.y < 0.22]
	fore = Vector((0.0, 0.08, min(v.z for v in mid) + 0.01))
	return {"butt": butt, "fore": fore}


def hide_guns():
	for gun in GUNS:
		obj = bpy.data.objects.get("prev_" + gun)
		if obj is not None:
			world = obj.matrix_world.copy()
			obj.parent = None
			obj.matrix_world = world
			obj.hide_set(True)


def _parent_keep(obj, arm, bone, world):
	obj.parent = arm
	obj.parent_type = "BONE"
	obj.parent_bone = bone
	obj.matrix_parent_inverse = Matrix.Identity(4)
	bpy.context.view_layer.update()
	obj.matrix_world = world
	obj.hide_set(False)
	bpy.context.view_layer.update()


def show_clip(arm, clip, frame=1):
	ad = arm.animation_data
	for track in ad.nla_tracks:
		track.mute = True
	action = bpy.data.actions[arm.name + "_" + clip]
	ad.action = action
	if getattr(ad, "action_slot", None) is None and len(action.slots):
		ad.action_slot = action.slots[0]
	bpy.context.scene.frame_set(frame)
	bpy.context.view_layer.update()
	try:
		bpy.ops.wm.redraw_timer(type="DRAW_WIN_SWAP", iterations=1)
	except RuntimeError:
		pass


def bones_visible(arm, flag):
	"""Hide the bone drawing but keep the rig evaluated, unlike hiding the object."""
	arm.hide_set(False)
	coll = arm.data.collections.get("rig") or arm.data.collections.new("rig")
	for bone in arm.data.bones:
		coll.assign(bone)
	coll.is_visible = flag


def clear_clip(arm):
	ad = arm.animation_data
	if ad is not None:
		ad.action = None
	zero_pose(arm)


def attach_1h(arm, m, gun):
	obj = bpy.data.objects["prev_" + gun]
	scale, grip, half = GUNS[gun]
	pb = arm.pose.bones["hand.R"]
	mw = arm.matrix_world
	head = mw @ pb.head
	y = (mw.to_3x3() @ (pb.tail - pb.head)).normalized()
	palm = (mw.to_3x3() @ palm_of(m, "R", pb)).normalized()
	x = y.cross(Vector((0, 0, 1))).normalized()
	z = x.cross(y).normalized()
	rot = Matrix((x, y, z)).transposed().to_4x4()
	point = head + y * 0.06 + palm * (half - GRIP_SINK)
	world = Matrix.Translation(point - rot.to_3x3() @ (grip * scale)) @ rot @ Matrix.Diagonal((scale, scale, scale, 1.0))
	_parent_keep(obj, arm, "hand.R", world)
	return obj


def attach_2h(arm):
	obj = bpy.data.objects["prev_rent_rifle"]
	flat = list(arm["rifle_world"])
	world = Matrix([flat[0:4], flat[4:8], flat[8:12], flat[12:16]])
	_parent_keep(obj, arm, "hand.R", arm.matrix_world @ world)
	return obj


def preview(char_id, clip, gun=None, frame=1):
	arm = bpy.data.objects[char_id + "_rig"]
	body = bpy.data.objects[char_id + "_body"]
	hide_guns()
	arm.hide_set(False)
	body.hide_set(False)
	show_clip(arm, clip, frame)
	m = json.loads(arm["fit"])
	if clip == "Hold1H" and gun:
		attach_1h(arm, m, gun)
	elif clip == "Hold2H":
		attach_2h(arm)
	return arm


def show_only(names):
	keep = set(names)
	for obj in bpy.data.objects:
		obj.hide_set(obj.name not in keep)


# ---------------------------------------------------------------- export


def export(char_id):
	arm = bpy.data.objects[char_id + "_rig"]
	body = bpy.data.objects[char_id + "_body"]
	hide_guns()
	clear_clip(arm)
	arm.location = (0.0, 0.0, 0.0)
	if bpy.context.mode != "OBJECT":
		bpy.ops.object.mode_set(mode="OBJECT")
	arm.hide_set(False)
	body.hide_set(False)
	bpy.ops.object.select_all(action="DESELECT")
	arm.select_set(True)
	body.select_set(True)
	bpy.context.view_layer.objects.active = arm
	ad = arm.animation_data
	for track in ad.nla_tracks:
		track.mute = False
	path = os.path.join(OUT, char_id + ".glb")
	props = bpy.ops.export_scene.gltf.get_rna_type().properties
	kwargs = {
		"filepath": path,
		"export_format": "GLB",
		"use_selection": True,
		"export_yup": True,
		"export_animations": True,
	}
	if "export_animation_mode" in props:
		kwargs["export_animation_mode"] = "NLA_TRACKS"
	try:
		bpy.ops.export_scene.gltf(**kwargs)
	finally:
		for track in ad.nla_tracks:
			track.mute = True
		clear_clip(arm)
	return path


def glb_animations(path):
	with open(path, "rb") as f:
		data = f.read()
	size = struct.unpack_from("<I", data, 12)[0]
	doc = json.loads(data[20:20 + size])
	return [(a.get("name"), len(a.get("channels", []))) for a in doc.get("animations", [])]
