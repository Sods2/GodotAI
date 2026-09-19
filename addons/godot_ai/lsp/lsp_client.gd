@tool
class_name GodotLspClient
extends JsonRpcTcpClient

## Minimal client for Godot's built-in GDScript language server (Editor Settings >
## Network > Language Server, default TCP port 6005). GodotAI uses it to fetch
## diagnostics (errors/warnings) for the open script and feed them to the AI —
## either as passive context or via a tool call.
##
## This is a best-effort client: it performs the LSP handshake, opens/updates the
## current document, and caches the most recent publishDiagnostics per file. Any
## failure degrades to "no diagnostics" and never blocks the chat.

const DEFAULT_PORT := 6005

var _initialized: bool = false
var _next_id: int = 1
var _open_versions: Dictionary = {}       # uri -> int (document version)
var _diagnostics: Dictionary = {}         # uri -> Array (latest diagnostics)
var _diag_dirty: Dictionary = {}          # uri -> bool (updated since last read)

func _init() -> void:
	configure("127.0.0.1", DEFAULT_PORT)

## Availability probe for the settings UI.
func probe(timeout_sec: float = 0.6) -> bool:
	return await connect_and_wait(timeout_sec)

## Sync a script's contents to the language server and return its diagnostics as a
## formatted string (empty string if none, unreachable, or timed out).
## `res_path` is a res:// path; `source` is the current text.
func get_diagnostics_text(res_path: String, source: String) -> String:
	var diags := await get_diagnostics(res_path, source)
	if diags.is_empty():
		return ""
	var lines := PackedStringArray()
	for d in diags:
		var sev := _severity_label(int(d.get("severity", 1)))
		var line := int(d.get("range", {}).get("start", {}).get("line", 0)) + 1
		lines.append("- [%s] line %d: %s" % [sev, line, str(d.get("message", ""))])
	return "## GDScript diagnostics for `%s`\n%s" % [res_path, "\n".join(lines)]

## Sync a script and return the raw diagnostics array for it.
func get_diagnostics(res_path: String, source: String) -> Array:
	if not await _ensure_initialized():
		return []
	var uri := _to_uri(res_path)
	_sync_document(uri, source)
	# Wait briefly for the server to publish fresh diagnostics for this file.
	var elapsed := 0.0
	while elapsed < 0.6:
		if _diag_dirty.get(uri, false):
			break
		await get_tree().create_timer(0.05).timeout
		elapsed += 0.05
	_diag_dirty[uri] = false
	return _diagnostics.get(uri, [])

# ── LSP handshake & document sync ─────────────────────────────────────────────

func _ensure_initialized() -> bool:
	if _initialized and is_socket_connected():
		return true
	# Socket is down (first use, or the server restarted). Any prior handshake and
	# open-document state no longer apply to a fresh connection.
	_initialized = false
	_open_versions.clear()
	if not await connect_and_wait(1.0):
		return false

	var root_uri := _to_uri("res://")
	_send_request("initialize", {
		"processId": null,
		"rootUri": root_uri,
		"capabilities": {"textDocument": {"publishDiagnostics": {}}},
	})
	# Godot's LSP replies quickly; give the handshake a short window.
	var elapsed := 0.0
	while not _initialized and elapsed < 1.5:
		await get_tree().create_timer(0.05).timeout
		elapsed += 0.05
	return _initialized

func _sync_document(uri: String, source: String) -> void:
	if _open_versions.has(uri):
		var version: int = _open_versions[uri] + 1
		_open_versions[uri] = version
		_send_notification("textDocument/didChange", {
			"textDocument": {"uri": uri, "version": version},
			"contentChanges": [{"text": source}],
		})
	else:
		_open_versions[uri] = 1
		_send_notification("textDocument/didOpen", {
			"textDocument": {"uri": uri, "languageId": "gdscript", "version": 1, "text": source},
		})

func _on_message(msg: Dictionary) -> void:
	# Response to our initialize request.
	if msg.has("id") and msg.has("result") and not _initialized:
		_initialized = true
		_send_notification("initialized", {})
		return
	# Server notifications (no id).
	var method: String = msg.get("method", "")
	if method == "textDocument/publishDiagnostics":
		var params: Dictionary = msg.get("params", {})
		var uri: String = params.get("uri", "")
		if uri != "":
			_diagnostics[uri] = params.get("diagnostics", [])
			_diag_dirty[uri] = true

func _send_request(method: String, params: Dictionary) -> void:
	var id := _next_id
	_next_id += 1
	send_message({"jsonrpc": "2.0", "id": id, "method": method, "params": params})

func _send_notification(method: String, params: Dictionary) -> void:
	send_message({"jsonrpc": "2.0", "method": method, "params": params})

func close() -> void:
	super()
	_initialized = false
	_open_versions.clear()

# ── Helpers ───────────────────────────────────────────────────────────────────

## Convert a res:// path to a file:// URI the language server understands.
static func _to_uri(res_path: String) -> String:
	var absolute := ProjectSettings.globalize_path(res_path).replace("\\", "/")
	if not absolute.begins_with("/"):
		absolute = "/" + absolute  # Windows drive paths: C:/... -> /C:/...
	return "file://" + absolute

static func _severity_label(severity: int) -> String:
	match severity:
		1: return "error"
		2: return "warning"
		3: return "info"
		_: return "hint"
