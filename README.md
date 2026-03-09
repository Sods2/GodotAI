# GodotAI

An AI coding assistant built directly into the Godot editor. Chat with Claude, ChatGPT, or any OpenRouter model without leaving Godot get code suggestions, ask questions about your project, and insert AI-generated code straight into your scripts.

## Features

- **Chat panel** docked at the bottom of the Godot editor
- **Multi-provider:** Anthropic (Claude), OpenAI (ChatGPT), OpenRouter (500+ models)
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
3. Select your provider (Anthropic, OpenAI, or OpenRouter).
4. Enter your **API key** for that provider.
5. Choose a model (or type a custom model ID).
6. Click **Save**.
7. Start chatting.

## Providers

| Provider   | Models                              | Notes                              |
|------------|-------------------------------------|------------------------------------|
| Anthropic  | Claude 3.5 Sonnet, Claude 3 Haiku, etc. | Best for code; recommended default |
| OpenAI     | GPT-4o, GPT-4 Turbo, GPT-3.5, etc. | —                                  |
| OpenRouter | 500+ models                         | Model list fetched live from API   |

## Keyboard Shortcuts

Default shortcuts (configurable in Settings → Shortcuts):

| Action               | Default           |
|----------------------|-------------------|
| Focus chat input     | `Ctrl+/`          |
| Send selected code   | `Ctrl+Shift+/`    |
| Send message         | `Enter`           |

## Usage Tips

- **Send selected code:** Select code in a script editor, then press `Ctrl+Shift+/` to paste it into the chat input automatically.
- **Insert at Cursor:** In any AI response, hover over a code block and click the **Insert** button to paste the code into the script currently open in the editor.
- **Context:** GodotAI automatically includes your active script content and scene tree structure in the system prompt so the AI understands your project.

## License

Custom proprietary license free to use in personal and commercial Godot projects. Redistribution or resale of the plugin itself is not permitted. See [LICENSE](./LICENSE) for full terms.
