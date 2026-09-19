# MCP Bridge - Godot EditorPlugin

> Part of [godot-mcp](https://github.com/Sods2/godot-mcp) &mdash; v1.2.0

A Godot 4.x editor plugin that exposes editor capabilities via a local TCP bridge using JSON-RPC over Content-Length framing.

## Installation

1. Copy the `addons/godot_mcp_bridge/` folder into your Godot project's `addons/` directory
2. Open your project in the Godot editor
3. Go to **Project > Project Settings > Plugins**
4. Enable **MCP Bridge**

The plugin starts a TCP server on `127.0.0.1:6008` when enabled.

## How it works

The plugin runs a TCP server inside the Godot editor process. The external MCP server (Node.js) connects to it and sends JSON-RPC commands to read and modify editor state in real time.

### Supported methods

#### Editor & Scene

| Method | Description |
|--------|-------------|
| `editor.status` | Get editor connection status and open scenes |
| `scene.get_tree` | Get the full scene tree structure (supports `max_depth` and `type_filter`) |
| `scene.get_selected` | Get currently selected nodes |
| `scene.add_node` | Add a new node to the scene |
| `scene.remove_node` | Remove a node from the scene |
| `scene.reparent_node` | Move a node to a new parent |
| `scene.rename_node` | Rename a node in the current scene |
| `scene.duplicate_node` | Duplicate a node in the current scene |
| `scene.move_node` | Reorder a node within its parent by sibling index |
| `scene.open` | Open a scene file |
| `scene.save` | Save the current scene |

#### Inspector

| Method | Description |
|--------|-------------|
| `inspector.get_properties` | Get all editor-visible properties of a node |
| `inspector.set_property` | Set a property on a node |

#### Scripts

| Method | Description |
|--------|-------------|
| `script.get_current` | Get the currently open script and cursor position |
| `script.get_open` | List all open scripts |
| `script.get_selected_code` | Get the selected text in the script editor |
| `script.insert_at_cursor` | Insert text at the cursor position |
| `script.create_and_attach` | Create a new script and attach it to a node |
| `script.detach` | Remove the script attached to a node |
| `script.get_for_node` | Get the script path attached to a node |

#### Signals

| Method | Description |
|--------|-------------|
| `signal.list` | List all signals exposed by a node |
| `signal.connect` | Connect a signal to a method on another node |
| `signal.disconnect` | Disconnect a signal connection between nodes |
| `signal.list_connections` | List all signal connections on a node |

#### Animation

| Method | Description |
|--------|-------------|
| `animation.list` | List all animations in an AnimationPlayer node |
| `animation.get` | Get detailed track and keyframe data for an animation |
| `animation.create` | Create a new animation with tracks and keyframes |

#### Resources

| Method | Description |
|--------|-------------|
| `resource.import` | Reimport assets in the editor |
| `resource.read` | Read a resource's properties |
| `resource.write` | Write properties to a resource |

#### Run

| Method | Description |
|--------|-------------|
| `run.play` | Play the current or a specific scene |
| `run.stop` | Stop the running scene |
| `run.is_running` | Check if a scene is running |
| `run.get_output` | Get captured output lines (supports `since_line` for polling) |

#### Screenshots

| Method | Description |
|--------|-------------|
| `screenshot.viewport` | Capture the editor viewport as base64 PNG |
| `screenshot.game` | Capture the running game window as base64 PNG |

#### Debugger

| Method | Description |
|--------|-------------|
| `debug.set_breakpoint` | Set a breakpoint at a file and line |
| `debug.remove_breakpoint` | Remove a breakpoint at a file and line |
| `debug.list_breakpoints` | List all active breakpoints |
| `debug.get_stack_trace` | Get the current stack trace when paused |
| `debug.get_locals` | Get local variables when paused at a breakpoint |
| `debug.step_over` | Step over the current line |
| `debug.step_into` | Step into the current function call |
| `debug.step_out` | Step out of the current function |
| `debug.continue_execution` | Continue execution after a breakpoint pause |

#### Profiler

| Method | Description |
|--------|-------------|
| `profiler.start` | Start capturing performance profiling data |
| `profiler.stop` | Stop profiling and return collected data |
| `profiler.get_data` | Get collected profiler frames without stopping |

## Requirements

- Godot 4.3 or later

## License

MIT — see [LICENSE](./LICENSE).
