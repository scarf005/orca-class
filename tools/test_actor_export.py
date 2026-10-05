"""Exercise real Blender edits, export, and rejection of invalid source parts.

blender --background --python-exit-code 1 --python tools/test_actor_export.py
"""

import hashlib
import json
import struct
import sys
import tempfile
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from export_actors import ROOT, export_actor


def read_glb(path):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data)
    assert (magic, version, length) == (b"glTF", 2, len(data))
    size, kind = struct.unpack_from("<II", data, 12)
    assert kind == 0x4E4F534A
    document = json.loads(data[20 : 20 + size])
    bin_size, bin_kind = struct.unpack_from("<II", data, 20 + size)
    assert bin_kind == 0x004E4942
    return document, data[28 + size : 28 + size + bin_size]


def values(document, binary, accessor):
    a = document["accessors"][accessor]
    view = document["bufferViews"][a["bufferView"]]
    assert a["componentType"] == 5126  # FLOAT, no quantization of authored coordinates.
    width = {"VEC3": 3, "VEC4": 4}[a["type"]]
    offset = view.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = view.get("byteStride", width * 4)
    return [struct.unpack_from("<" + "f" * width, binary, offset + i * stride) for i in range(a["count"])]


def check_rejected(source, destination, message):
    try:
        export_actor(source, destination)
    except ValueError:
        return
    raise AssertionError(message)


def run():
    original = ROOT / "art/actors/tank.blend"
    before = hashlib.sha256(original.read_bytes()).hexdigest()
    (ROOT / "builds").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=ROOT / "builds", prefix="actor-export-") as folder:
        folder = Path(folder)
        edited = folder / "tank.blend"
        destination = folder / "tank.glb"
        bpy.ops.wm.open_mainfile(filepath=str(original))
        hull = bpy.data.objects["hull"].data
        hull.vertices[0].co.x += 0.125
        expected = tuple(hull.vertices[0].co)
        hull.color_attributes["Color"].data[0].color = (0.25, 0.5, 0.75, 1.0)
        # Authoring layout, including quaternion rotation, must not move runtime pivots.
        obj = bpy.data.objects["hull"]
        obj.rotation_mode = "QUATERNION"
        obj.rotation_quaternion = (0.5, 0.5, 0.5, 0.5)
        obj.location = (20, 30, 40)
        obj.scale = (2, 3, 4)
        bpy.ops.wm.save_as_mainfile(filepath=str(edited))
        edited_hash = hashlib.sha256(edited.read_bytes()).hexdigest()
        export_actor(edited, destination)
        document, binary = read_glb(destination)
        node = next(node for node in document["nodes"] if node["name"] == "hull")
        assert node.get("translation", [0, 0, 0]) == [0, 0, 0], "layout moved the runtime pivot"
        assert node.get("rotation", [0, 0, 0, 1]) == [0, 0, 0, 1], "layout rotated the runtime part"
        assert node.get("scale", [1, 1, 1]) == [1, 1, 1], "layout resized the runtime part"
        mesh = next(mesh for mesh in document["meshes"] if mesh["name"] == "hull")
        positions, colors = [], []
        for primitive in mesh["primitives"]:
            positions.extend(values(document, binary, primitive["attributes"]["POSITION"]))
            colors.extend(values(document, binary, primitive["attributes"]["COLOR_0"]))
        assert (expected[0], expected[2], -expected[1]) in positions, "edited vertex did not reach GLB"
        assert any(color[:3] == (0.25, 0.5, 0.75) for color in colors), "edited color did not reach GLB"
        assert hashlib.sha256(edited.read_bytes()).hexdigest() == edited_hash, "export overwrote the artist's source"
        assert hashlib.sha256(original.read_bytes()).hexdigest() == before, "test modified original source"
        # A typo cannot silently remove a runtime part or change its shader role.
        bpy.ops.wm.open_mainfile(filepath=str(edited))
        bpy.data.objects["hull"].name = "misspelled_hull"
        bpy.ops.wm.save_as_mainfile(filepath=str(edited))
        check_rejected(edited, destination, "renamed part was accepted")
        bpy.ops.wm.open_mainfile(filepath=str(original))
        bpy.data.materials["lit"].name = "unknown_shader"
        bpy.ops.wm.save_as_mainfile(filepath=str(edited))
        check_rejected(edited, destination, "unknown material role was accepted")
    print("PASS: edited Blender geometry/colors exported; sources untouched; invalid part/role rejected")


run()
