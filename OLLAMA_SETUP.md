# Ollama Setup for Local Model Testing

## 1. Install Ollama

### macOS
```bash
brew install ollama
```
Or download the installer from [ollama.com](https://ollama.com/download).

## 2. Start the Ollama Server

```bash
ollama serve
```

Ollama runs at `http://localhost:11434` by default. Leave this terminal open, or run it as a background service:

```bash
# Run in background (macOS launchd — starts automatically on login after brew install)
brew services start ollama
```

## 3. Pull a Model

Choose a model based on your hardware:

| Model | Size | RAM Required | Notes |
|-------|------|-------------|-------|
| `llama3.2:3b` | ~2 GB | 4 GB | Fastest, good for testing |
| `llama3.2` | ~5 GB | 8 GB | Balanced |
| `llama3.1:8b` | ~5 GB | 8 GB | Strong general purpose |
| `mistral` | ~4 GB | 8 GB | Good for code |
| `codellama:7b` | ~4 GB | 8 GB | Code-focused |
| `llama3.1:70b` | ~40 GB | 64 GB | Best quality, needs high-end GPU |

```bash
# Recommended for testing on a typical machine
ollama pull llama3.2:3b

# Or for better quality
ollama pull llama3.2
```

## 4. Verify the Model Works

```bash
ollama run llama3.2:3b "Hello, are you working?"
```

## 5. Configure GodotAI Plugin

In the GodotAI settings dialog, use these values for the **OpenAI Compatible** provider:

- **Base URL:** `http://localhost:11434/v1`
- **API Key:** `ollama` (any non-empty string works)
- **Model:** `llama3.2:3b` (or whatever model you pulled)

> Ollama exposes an OpenAI-compatible `/v1/chat/completions` endpoint, so the OpenAI Compatible provider works directly.

## 6. List Installed Models

```bash
ollama list
```

## 7. Remove a Model

```bash
ollama rm llama3.2:3b
```

## Troubleshooting

- **Connection refused:** Make sure `ollama serve` is running.
- **Model not found:** Run `ollama pull <model-name>` first.
- **Slow responses:** Use a smaller model (e.g., `3b` instead of `8b`).
- **Out of memory:** Switch to a smaller model or enable GPU acceleration if available.

## Useful Commands

```bash
ollama list          # Show downloaded models
ollama ps            # Show running models
ollama serve         # Start server manually
ollama run <model>   # Interactive chat in terminal
```
