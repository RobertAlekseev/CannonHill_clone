class_name SharedAssets
extends RefCounted
## Resolves engine-neutral assets by id through asset-manifests/assets.json.
## Files stay in the repository's shared/ and external-assets/ folders so Unity,
## Unreal and Godot read the same bytes; nothing is copied into godot/.
## Override the repository root with the CANNONHILL_ROOT environment variable.
const MANIFEST := "asset-manifests/assets.json"
var root := ""
var paths := {}
var problems: Array[String] = []

func _init() -> void:
	root = find_root()
	if root.is_empty():
		problems.append("manifest not found")
		return
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(root.path_join(MANIFEST)))
	if not manifest is Dictionary:
		problems.append("manifest unreadable")
		return
	var roots: Dictionary = manifest.get("roots", {})
	for entry in manifest.get("shared", []):
		register(entry, entry.get("path", ""))
	# USB packages: external-assets/<package>/<path>, see docs/USB_ASSETS.md.
	for package in manifest.get("packages", []):
		for entry in package.get("files", []):
			register(entry, str(roots.get("external", "external-assets")).path_join(str(package.get("name", ""))).path_join(str(entry.get("path", ""))))

static func find_root() -> String:
	var candidates: Array[String] = [OS.get_environment("CANNONHILL_ROOT"),
		ProjectSettings.globalize_path("res://").path_join(".."),
		OS.get_executable_path().get_base_dir()]
	for candidate in candidates:
		if not candidate.is_empty() and FileAccess.file_exists(candidate.path_join(MANIFEST)):
			return candidate.simplify_path()
	return ""

func register(entry: Dictionary, relative: String) -> void:
	var id := str(entry.get("id", ""))
	var path := root.path_join(relative).simplify_path()
	if id.is_empty() or relative.is_empty() or not FileAccess.file_exists(path):
		problems.append("missing " + id)
		return
	var expected := str(entry.get("sha256", ""))
	if not expected.is_empty() and FileAccess.get_sha256(path) != expected:
		problems.append("checksum " + id)
		return
	paths[id] = path

func has(id: String) -> bool:
	return paths.has(id)

## Returns null when the asset is absent; callers keep a procedural fallback.
func audio(id: String) -> AudioStream:
	if not has(id): return null
	match paths[id].get_extension().to_lower():
		"wav": return AudioStreamWAV.load_from_file(paths[id])
		"ogg": return AudioStreamOggVorbis.load_from_file(paths[id])
	return null

func texture(id: String) -> Texture2D:
	if not has(id): return null
	var image := Image.load_from_file(paths[id])
	return ImageTexture.create_from_image(image) if image else null
