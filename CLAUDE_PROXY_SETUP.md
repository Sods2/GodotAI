# Claude Proxy Setup

Use GodotAI with your **Claude Pro or Max subscription** — no API key or separate billing required.

Claude Pro/Max subscribers get access to the Claude Code CLI. The bundled proxy script translates GodotAI's requests into CLI calls, so you can use your existing subscription directly.

---

## Prerequisites

- **Claude Code CLI** installed and signed in ([claude.ai/code](https://claude.ai/code))
  - Verify: `claude --version` should print a version number
  - If not signed in: run `claude` once and follow the login prompts
- **Python 3.8+** (pre-installed on macOS; available on all platforms)

---

## 1. Start the Proxy

### From Godot (recommended)

1. Open the **GodotAI Settings** dialog (gear icon in the panel).
2. Switch to the **Local** tab.
3. Select **Claude Proxy** from the **Server Preset** dropdown.
4. Click the **Start** button that appears next to "Built-in Proxy".
5. The status label turns green when the proxy is running.

Click **Stop** to shut it down. The proxy is also stopped automatically when the plugin is disabled or the editor closes.

### From a terminal (alternative)

If you need custom options (e.g. a different port), start the proxy manually:

```bash
python3 tools/claude_proxy.py
```

The proxy runs at `http://localhost:8082` by default. Leave this terminal open while using GodotAI.

**Options:**

```bash
python3 tools/claude_proxy.py --port 8082    # custom port
python3 tools/claude_proxy.py --verbose      # log requests to stderr
```

---

## 2. Verify It Works

```bash
curl http://localhost:8082/v1/models
```

You should see a JSON list of Claude models. If you see an error, check the proxy terminal output.

---

## 3. Configure GodotAI

1. Open the **GodotAI Settings** dialog (gear icon in the panel).
2. Switch to the **Local** tab.
3. Select **Claude Proxy** from the **Server Preset** dropdown.
   - Endpoint URL auto-fills to `http://localhost:8082/v1`.
4. Click **Refresh** to load the model list.
5. Select a model (e.g., `sonnet` or `claude-sonnet-4-6`).
6. Leave **API Key** empty.
7. Click **Save**.

---

## 4. Available Models

| Alias | Full name |
|-------|-----------|
| `sonnet` | claude-sonnet-4-6 |
| `opus` | claude-opus-4-6 |
| `haiku` | claude-haiku-4-5 |

Use aliases for convenience or full model IDs for precision.

---

## Alternative: Third-Party Proxy

If you prefer not to run the bundled script, [`claude-code-proxy`](https://github.com/PallavAg/claude-code-proxy) is a popular npm alternative:

```bash
npx claude-code-proxy
```

It runs on port `8082` by default and is compatible with the Claude Proxy preset.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Connection refused` | Proxy is not running — start it with `python3 tools/claude_proxy.py` |
| `'claude' command not found` | Install Claude Code from [claude.ai/code](https://claude.ai/code) |
| `Not logged in` | Run `claude` in a terminal and complete the login flow |
| Model list empty | Click **Refresh** in settings, or check proxy terminal for errors |
| Slow first response | Normal — the Claude CLI has a short startup time on the first request |
| Port already in use | Use `--port 8083` (and update the endpoint URL in settings accordingly) |
