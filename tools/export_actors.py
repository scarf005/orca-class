"""Export edited actor .blend sources; never regenerate or save over them.

blender --background --python tools/export_actors.py -- [actor ...]
"""

import sys
from pathlib import Path

import bpy
from mathutils import Matrix

ROOT = Path(__file__).resolve().parents[1]
ROLES = ("lit", "glow", "flesh", "flesh_glow", "vivid_lit", "vivid_glow")


def export_actor(source, destination=None):
    bpy.ops.wm.open_mainfile(filepath=str(source))
    bpy.ops.object.select_all(action="DESELECT")
    parts = [obj for obj in bpy.data.objects if obj.get("orca_part")]
    if not parts:
        raise ValueError(f"{source}: no actor parts")
    for obj in parts:
        if obj.type != "MESH" or obj.name != obj["orca_part"]:
            raise ValueError(f"{source}: keep part names and types ({obj.name})")
        if obj.modifiers:
            raise ValueError(f"{obj.name}: apply modifiers before exporting")
        if any(slot.material is None or slot.material.name not in ROLES for slot in obj.material_slots):
            raise ValueError(f"{obj.name}: unknown material role")
        # Runtime owns the joints. Object transforms are only the authoring layout;
        # mesh-local coordinates are exported at identity, without changing the source.
        obj.parent = None
        obj.matrix_world = Matrix.Identity(4)
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.select_set(True)
    if destination is None:
        destination = ROOT / "assets" / "actors" / f"{source.stem}.glb"
    destination.parent.mkdir(parents=True, exist_ok=True)
    result = bpy.ops.export_scene.gltf(
        filepath=str(destination),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_normals=True,
        export_texcoords=False,
        export_tangents=False,
        export_attributes=False,
        export_materials="EXPORT",
        export_all_vertex_colors=True,
        export_animations=False,
        export_cameras=False,
        export_lights=False,
    )
    if result != {"FINISHED"}:
        raise RuntimeError(f"Export failed: {source}")
    print(f"Exported {source.name}: {len(parts)} parts -> {destination}")


if __name__ == "__main__":
    names = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sources = sorted((ROOT / "art" / "actors").glob("*.blend"))
    if names:
        known = {source.stem for source in sources}
        if set(names) - known:
            raise ValueError(f"Unknown actors: {set(names) - known}")
        sources = [source for source in sources if source.stem in names]
    for source in sources:
        export_actor(source)
