# GodotAI

An AI coding assistant built directly into the Godot editor. Chat with Claude, ChatGPT, any OpenRouter model, or local models via Ollama — without leaving Godot. Already have a **Claude Pro or Max subscription**? The built-in proxy lets you use it directly with no API billing. Prefer fully offline? Connect to Ollama, LM Studio, or any local model — no API key or internet required.

## Features

- **Chat panel** docked at the bottom of the Godot editor
- **Multi-provider:** Anthropic (Claude), OpenAI (ChatGPT), OpenRouter (500+ models), Local (Ollama, LM Studio, llama.cpp)
- **Built-in Claude Proxy** — use your Claude Pro or Max subscription directly; start/stop from within Godot with no API key or separate billing
- **Local model support** — run fully offline with Ollama, LM Studio, llama.cpp, or any OpenAI-compatible server; no API key or internet required
- **Streaming responses** — text appears as it is generated, not all at once
- **Markdown rendering** with syntax-highlighted code blocks
- **Insert at Cursor** — click any code block to insert it into the active script
- **Context-aware** — automatically includes your active script and scene tree in the prompt
- **Chat history** — conversations are saved per project and restored on next open
- **Configurable shortcuts** — focus chat, send selected code, send message
- **Full settings dialog** — API key, model, temperature, max tokens, system prompt per provider

## Example

<p align="center">
  <img src="screenshots/editor-view_05x.png" />
</p>

## Requirements

- Godot 4.5 or later
- An API key from at least one of:
  - [Anthropic](https://console.anthropic.com/) (Claude models)
  - [OpenAI](https://platform.openai.com/) (GPT models)
  - [OpenRouter](https://openrouter.ai/) (500+ models from many providers)
  - **None** — if using a local server (Ollama, LM Studio, llama.cpp, etc.) or Claude Proxy

## Installation

### From the Godot Asset Library (recommended)

1. Open your Godot project.
2. Go to **AssetLib** tab at the top of the editor.
3. Search for **GodotAI**.
4. Click **Download**, then **Install**.
5. Enable the plugin: **Project → Project Settings → Plugins → GodotAI → Enable**.

### Manual installation

1. Download or clone this repository.
2. Copy the `addons/godot_ai/` folder into your project's `addons/` directory.
3. Enable the plugin: **Project → Project Settings → Plugins → GodotAI → Enable**.

## Setup

1. After enabling the plugin, a **GodotAI** panel appears at the bottom of the editor.
2. Click the **Settings** button (gear icon) in the panel.
3. Select your provider (Anthropic, OpenAI, OpenRouter, or Local).
4. Enter your **API key** for that provider. (Not required for local servers or Claude Proxy.)
5. Choose a model (or type a custom model ID).
6. Click **Save**.
7. Start chatting.

## Providers

| Provider   | Models                              | Notes                              |
|------------|-------------------------------------|------------------------------------|
| Anthropic  | Claude Sonnet 4, Claude Haiku 4, etc. | Best for code; recommended default |
| OpenAI     | GPT-4o, GPT-4 Turbo, GPT-3.5, etc. | —                                  |
| OpenRouter | 500+ models                         | Model list fetched live from API   |
| Local      | Ollama, LM Studio, llama.cpp, Claude Proxy | Any OpenAI-compatible server; see [OLLAMA_SETUP.md](./OLLAMA_SETUP.md) or [CLAUDE_PROXY_SETUP.md](./CLAUDE_PROXY_SETUP.md) |

## Free Options: Claude Proxy & Local Models

GodotAI can run without any API key or subscription cost using two built-in options.

### Claude Proxy — Use Your Claude Subscription

If you have a **Claude Pro or Max subscription**, you already have access to the Claude Code CLI. The bundled proxy bridges GodotAI to your CLI session, giving you Claude Sonnet, Opus, and Haiku with no per-token billing.

**Quick start:**
1. Install [Claude Code](https://claude.ai/code) and sign in (`claude --version` to verify).
2. Open **Settings → Local tab** in the GodotAI panel.
3. Select **Claude Proxy** from the Server Preset dropdown.
4. Click **Start** — the proxy launches in the background and the status turns green.
5. Pick a model and start chatting.

For full setup details and troubleshooting, see [CLAUDE_PROXY_SETUP.md](./CLAUDE_PROXY_SETUP.md).

### Local Models — Fully Offline & Free

Run open-source models on your own hardware with [Ollama](https://ollama.com), [LM Studio](https://lmstudio.ai), [llama.cpp](https://github.com/ggml-org/llama.cpp), or any OpenAI-compatible server. No API key, no internet, no cost.

**Quick start with Ollama:**
1. Install Ollama and pull a model: `ollama pull llama3.2`
2. Open **Settings → Local tab** in the GodotAI panel.
3. Select **Ollama** from the Server Preset dropdown.
4. Click **Refresh** — available models load automatically.
5. Pick a model and start chatting.

For model recommendations and full setup, see [OLLAMA_SETUP.md](./OLLAMA_SETUP.md).

## Keyboard Shortcuts

Default shortcuts (configurable in Settings → Shortcuts):

| Action               | Default           |
|----------------------|-------------------|
| Focus chat input     | `Ctrl+/`          |
| Send selected code   | `Ctrl+Shift+/`    |
| Send message         | `Enter`           |

## Usage Tips

- **Claude Proxy:** If you have a Claude Pro or Max subscription, you can use it directly via the bundled Python proxy — no separate API billing required. Select **Claude Proxy** in the Local tab of Settings, then click **Start** to launch it without leaving Godot. See [CLAUDE_PROXY_SETUP.md](./CLAUDE_PROXY_SETUP.md) for full setup details.
- **Local Models:** Install Ollama and pull a model (`ollama pull llama3.2`), then select the **Ollama** preset in the Local tab — GodotAI auto-detects available models. See [OLLAMA_SETUP.md](./OLLAMA_SETUP.md) for other local server options.
- **Send selected code:** Select code in a script editor, then press `Ctrl+Shift+/` to paste it into the chat input automatically.
- **Insert at Cursor:** In any AI response, hover over a code block and click the **Insert** button to paste the code into the script currently open in the editor.
- **Context:** GodotAI automatically includes your active script content and scene tree structure in the system prompt so the AI understands your project.

## License

Custom proprietary license free to use in personal and commercial Godot projects. Redistribution or resale of the plugin itself is not permitted. See [LICENSE](./LICENSE) for full terms.
