# LLM Chatbot Plugin for Godot 4

A modular, provider-agnostic plugin for adding LLM-powered chatbots to any Godot 4 project. Drop in a chat UI, connect your API key, describe your character... done!

---

## Features

- **Waterfall fallback** — configure multiple providers; the plugin tries them in order until one succeeds.
- **Built-in providers** — Portkey (gateway/router) and Google AI Studio (Gemini) included out of the box.
- **Extensible** — add any REST-based LLM by extending `LLMProvider`.
- **Game-event triggers** — fire AI responses from code without player input.
- **Typewriter effect** — optional character-by-character reveal with skip support.
- **Question cap** — limit how many times a player can query the AI per session.
- **Character sprite** — swap textures between "neutral" and "talking" states automatically.
- **Conversation logging** — a signal fires with the transcript batch after every response.

---

## File Structure

```
addons/llm_chatbot/
├── plugin.cfg                   # Plugin manifest
├── plugin.gd                    # Registers the LLMManager autoload
├── autoload/
│   └── LLMManager.gd            # Singleton — send queries, get responses
├── providers/
│   ├── LLMProvider.gd           # Abstract base class
│   ├── PortkeyProvider.gd       # Portkey AI gateway
│   └── GoogleAIProvider.gd      # Google AI Studio (Gemini)
├── ui/
│   └── ChatController.gd        # Drop-in chat UI controller node
└── LLMSetup.example.gd          # Copy into your project to configure keys
```

---

## Installation

1. Copy the `addons/llm_chatbot/` folder into your project's `addons/` directory. (if the addons folder does not yet exist, manually add it inside of the res:// folder in your project)
2. Open **Project → Project Settings → Plugins** and enable **LLM Chatbot**.  
   This automatically registers `LLMManager` as a global autoload.
3. Copy `LLMSetup.example.gd` somewhere in your project (e.g. `res://autoloads/LLMSetup.gd`), add it as an **Autoload** (below `LLMManager` in the list), and fill in your API keys.

> ⚠️ **Never commit API keys to version control.** Use a `.env` file, Godot's `ProjectSettings` with a user-override file, or a secrets manager.

---

## Quick Start

### 1. Configure providers

```gdscript
# LLMSetup.gd (Autoload)
extends Node

func _ready() -> void:
    var portkey := PortkeyProvider.new()
    portkey.api_key = "pk-..."
    portkey.model   = "@openrouter/google/gemini-2.0-flash-lite"
    LLMManager.add_provider(portkey)

    var google := GoogleAIProvider.new()
    google.api_key = "AIza..."
    google.model   = "gemini-2.0-flash-lite"
    LLMManager.add_provider(google)   # fallback
```

### 2. Add a ChatController to your scene

1. Create a scene with your chat UI (LineEdit, Button, Label).
2. Add a Control node with the script `addons/llm_chatbot/ui/ChatController.gd`.
3. In the Inspector, assign:
   - **Input Field Path** → your `LineEdit`
   - **Send Button Path** → your `Button`
   - **Response Label Path** → your `Label` or `RichTextLabel`
   - **System Prompt** → your character's identity and rules
   - **Ai Speaker Name** → e.g. `"Erwin"` (used in conversation history)

That's it — the controller wires everything up automatically in `_ready()`.

---

## Inspector Reference

### Required UI Nodes

| Export | Type | Description |
|---|---|---|
| `input_field_path` | `NodePath` | The player's text input (`LineEdit`) |
| `send_button_path` | `NodePath` | The submit button |
| `response_label_path` | `NodePath` | Where AI responses are displayed |

### Optional UI Nodes

| Export | Type | Description |
|---|---|---|
| `char_count_label_path` | `NodePath` | Shows `current / max` character count |

### AI Persona

| Export | Default | Description |
|---|---|---|
| `system_prompt` | `"You are a helpful assistant..."` | Prepended to every query |
| `ai_speaker_name` | `"AI"` | AI label in conversation history |
| `player_speaker_name` | `"Player"` | Player label in conversation history |
| `thinking_text` | `"Thinking..."` | Shown while waiting for a response |
| `send_button_active_label` | `"Send"` | Button text after the first message |

### Typewriter Effect

| Export | Default | Description |
|---|---|---|
| `use_typewriter_effect` | `true` | Animate text character by character |
| `allow_skipping` | `true` | Click anywhere to skip the animation |
| `typing_speed` | `30.0` | Characters revealed per second |

### Input Limits

| Export | Default | Description |
|---|---|---|
| `char_limit` | `280` | Max input length. `0` = unlimited |
| `max_questions` | `0` | Max queries per session. `0` = unlimited |
| `question_limit_prompt_suffix` | *(see script)* | Appended to the prompt when cap is hit |

### Character Sprite

| Export | Type | Description |
|---|---|---|
| `character_sprite` | `Sprite2D` | Sprite to animate. Leave blank to disable |
| `character_textures` | `Dictionary` | Keys: `"neutral"`, `"talking"` (plus any custom keys) |

```gdscript
# Example — set in code instead of Inspector
$ChatController.character_textures = {
    "neutral": preload("res://art/guide_idle.png"),
    "talking": preload("res://art/guide_talk.png"),
}
```

---

## Signals

### ChatController

```gdscript
signal ai_responded(text: String)
signal conversation_saved(log_entries: Array)
signal question_limit_reached()
```

### LLMManager

```gdscript
signal response_received(text: String)
signal all_providers_failed(last_error: String)
```

---

## Triggering from Game Code

```gdscript
# Trigger a chat response when something happens in the game world
$ChatController.trigger_event(
    "Player picked up the rusty key",
    "React with mild surprise and hint at what it might unlock."
)

# Or send a message directly (bypasses the UI input field)
$ChatController.send_message("What should I do next?")

# Reset for a new playthrough / scene
$ChatController.reset_conversation()
```

---

## Conversation Logging

Every time the AI responds, `ChatController` emits `conversation_saved` with the batch of new lines as an `Array[String]`. Connect this signal to write logs however you like:

```gdscript
$ChatController.conversation_saved.connect(_on_log_ready)

func _on_log_ready(entries: Array) -> void:
    var text := " | ".join(entries)
    # Write to a file, send to your backend, call an Autoload, etc.
    FileAccess.open("user://chat_log.txt", FileAccess.WRITE).store_string(text)
```

---

## Adding a Custom Provider

1. Create `MyProvider.gd` anywhere in your project:

```gdscript
class_name MyProvider
extends LLMProvider

var api_key: String = ""

func _init() -> void:
    provider_name = "MyService"

func send_request(parent_node: Node, prompt: String) -> void:
    var http := HTTPRequest.new()
    parent_node.add_child(http)

    var headers := ["Authorization: Bearer " + api_key, "Content-Type: application/json"]
    var body := JSON.stringify({"prompt": prompt})

    http.request_completed.connect(_on_done.bind(http))
    http.request("https://api.myservice.com/generate", headers, HTTPClient.METHOD_POST, body)

func _on_done(_r, code, _h, body, http):
    http.queue_free()
    var json := _parse_json(body)
    if code == 200:
        response_received.emit(json["text"])
    else:
        request_failed.emit("HTTP " + str(code))
```

2. Register it:

```gdscript
var my = MyProvider.new()
my.api_key = "..."
LLMManager.add_provider(my)
```

---

## Security Notes

- Keep API keys out of version control. Use a `.gitignore`d config file or Godot's `user://` path to load them at runtime.
- The `question_limit_prompt_suffix` injection mitigates prompt-injection from the player trying to override the character's persona, but it is not a security boundary — do not rely on it alone for sensitive applications.
