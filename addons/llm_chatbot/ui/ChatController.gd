## ChatController.gd
##
## Drop-in Control node that wires a chat UI to LLMManager.
## All game-specific values (persona, node paths, textures) are exposed as
## @export properties so they can be set in the Inspector without touching code.
##
## ── Minimum Setup ────────────────────────────────────────────────────────────
##
##   1. Add a node that extends ChatController to your scene.
##   2. Assign the required UI node exports in the Inspector:
##        • input_field_path  → your LineEdit node
##        • send_button_path  → your Button node
##        • response_label_path → your RichTextLabel or Label node
##   3. Set system_prompt to describe your AI character.
##   4. Make sure LLMManager has at least one provider (see LLMManager.gd).
##
## ── Optional Features ────────────────────────────────────────────────────────
##   • Typewriter effect  — enable use_typewriter_effect, set typing_speed
##   • Character sprite   — assign character_sprite and fill character_textures
##   • Question cap       — set max_questions (0 = unlimited)
##   • Char count label   — assign char_count_label_path
##   • Cloud logging      — connect to conversation_saved signal or override
##                          _save_conversation()
##
## ── Triggering from game code ─────────────────────────────────────────────
##   $ChatController.trigger_event("Player picked up health item",
##                                 "Briefly comment on this.")
##
## ─────────────────────────────────────────────────────────────────────────────

class_name ChatController
extends Control

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Raw AI response text, emitted every time the LLM replies.
signal ai_responded(text: String)

## Emitted when a conversation batch is ready to be saved/logged.
## [param log_entries] is an Array[String] of "Speaker: message" lines.
signal conversation_saved(log_entries: Array)

## Emitted when the question cap is reached.
signal question_limit_reached()

# ---------------------------------------------------------------------------
# Inspector Exports — UI Node Paths
# ---------------------------------------------------------------------------

@export_group("Required UI Nodes")
@export var input_field_path: NodePath
@export var send_button_path: NodePath
@export var response_label_path: NodePath

@export_group("Optional UI Nodes")
@export var char_count_label_path: NodePath

# ---------------------------------------------------------------------------
# Inspector Exports — AI Persona
# ---------------------------------------------------------------------------

@export_group("AI Persona")

## The system / identity prompt prepended to every query.
## Example: "You are Ada, a helpful wizard. Keep replies under 30 words."
@export_multiline var system_prompt: String = \
	"You are a helpful assistant. Keep responses concise."

## Label used for the AI in conversation history, e.g. "Erwin" or "Ada".
@export var ai_speaker_name: String = "AI"

## Label used for the player in conversation history.
@export var player_speaker_name: String = "Player"

## Placeholder text shown while waiting for the AI reply.
@export var thinking_text: String = "Thinking..."

## Text shown on the send button after the first message is sent.
@export var send_button_active_label: String = "Send"

# ---------------------------------------------------------------------------
# Inspector Exports — Typewriter Effect
# ---------------------------------------------------------------------------

@export_group("Typewriter Effect")
@export var use_typewriter_effect: bool = true
@export var allow_skipping: bool = true
## Characters revealed per second.
@export var typing_speed: float = 30.0

# ---------------------------------------------------------------------------
# Inspector Exports — Input Limits
# ---------------------------------------------------------------------------

@export_group("Input Limits")
## Maximum characters allowed in the input field. 0 = unlimited.
@export var char_limit: int = 280
## Maximum number of questions the player may ask. 0 = unlimited.
@export var max_questions: int = 0

## Message appended to the prompt once the question cap is hit.
@export_multiline var question_limit_prompt_suffix: String = \
	" The user has reached their question limit. Politely let them know you cannot help further right now."

# ---------------------------------------------------------------------------
# Inspector Exports — Character Sprite
# ---------------------------------------------------------------------------

@export_group("Character Sprite")
## Optional animated character sprite. Leave blank to disable.
@export var character_sprite: Sprite2D
## Texture keys: "neutral", "talking". Any extra keys are yours to use.
@export var character_textures: Dictionary = {}

# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _input_field: LineEdit
var _send_button: Button
var _response_label: Label        # also accepts RichTextLabel
var _char_count_label: Label

var _conversation_history: Array[String] = []
var _log_history: Array[String] = []
var _questions_asked: int = 0
var _is_first_message: bool = true
var _max_reached: bool = false
var _typing_tween: Tween
var _sprite_root_position: Vector2

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_resolve_nodes()
	_connect_signals()

	if character_sprite:
		_sprite_root_position = character_sprite.position

	if char_limit > 0 and _input_field:
		_input_field.max_length = char_limit
		_update_char_count(0)

	if LLMManager.response_received.is_connected(_on_ai_responded):
		LLMManager.response_received.disconnect(_on_ai_responded)
	LLMManager.response_received.connect(_on_ai_responded)

	LLMManager.all_providers_failed.connect(_on_all_providers_failed)


func _process(_delta: float) -> void:
	if _max_reached and _send_button:
		_send_button.disabled = true
		if _input_field:
			_input_field.editable = false


func _input(event: InputEvent) -> void:
	if allow_skipping and use_typewriter_effect \
			and event is InputEventMouseButton and event.pressed:
		if _typing_tween and _typing_tween.is_running():
			_typing_tween.kill()
			_set_label_full_text()
			_reset_input_state()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Send a message as if the player typed it.
func send_message(text: String) -> void:
	if text.is_empty():
		return
	_submit_query(text)


## Trigger a query from game code without player input.
## [param game_event]   describes what happened, e.g. "Player found key".
## [param instruction]  how the AI should react, e.g. "Comment briefly."
func trigger_event(game_event: String, instruction: String) -> void:
	var entry := "Event: %s | Instruction: %s" % [game_event, instruction]
	_conversation_history.append(entry)
	_log_history.append(entry)
	_dispatch_query(instruction)


## Clear the full conversation history.
func reset_conversation() -> void:
	_conversation_history.clear()
	_log_history.clear()
	_questions_asked = 0
	_is_first_message = true
	_max_reached = false
	if _send_button:
		_send_button.disabled = false
	if _input_field:
		_input_field.editable = true

# ---------------------------------------------------------------------------
# Internal — UI wiring
# ---------------------------------------------------------------------------

func _resolve_nodes() -> void:
	if input_field_path:
		_input_field = get_node_or_null(input_field_path)
	if send_button_path:
		_send_button = get_node_or_null(send_button_path)
	if response_label_path:
		_response_label = get_node_or_null(response_label_path)
	if char_count_label_path:
		_char_count_label = get_node_or_null(char_count_label_path)

	for label in ["_input_field", "_send_button", "_response_label"]:
		if get(label) == null:
			push_warning("[ChatController] Required node not assigned: %s" % label)


func _connect_signals() -> void:
	if _send_button:
		_send_button.pressed.connect(_on_send_pressed)
	if _input_field:
		_input_field.text_submitted.connect(_on_text_submitted)
		if char_limit > 0:
			_input_field.text_changed.connect(_on_text_changed)


func _on_text_changed(new_text: String) -> void:
	if char_limit > 0 and new_text.length() > char_limit:
		_input_field.text = new_text.left(char_limit)
		_input_field.caret_column = char_limit
	_update_char_count(_input_field.text.length())


func _update_char_count(current: int) -> void:
	if not _char_count_label:
		return
	_char_count_label.text = "%d / %d" % [current, char_limit]
	if char_limit > 0 and current > char_limit * 0.75:
		_char_count_label.modulate = Color.RED
	else:
		_char_count_label.modulate = Color.WHITE


func _on_text_submitted(_text: String) -> void:
	if _send_button and not _send_button.disabled:
		_on_send_pressed()


func _on_send_pressed() -> void:
	if not _input_field:
		return
	var text := _input_field.text.strip_edges()
	if text.is_empty():
		return
	_input_field.text = ""
	_update_char_count(0)
	send_message(text)


func _submit_query(user_text: String) -> void:
	_conversation_history.append("%s: %s" % [player_speaker_name, user_text])
	_log_history.append("%s: %s" % [player_speaker_name, user_text])
	_dispatch_query("")


func _dispatch_query(extra_instruction: String) -> void:
	if _is_first_message:
		_is_first_message = false
		if _send_button:
			_send_button.text = send_button_active_label

	var history_str := "\n".join(_conversation_history)
	var prompt := system_prompt \
		+ "\n\nConversation History:\n" + history_str \
		+ "\n" + ai_speaker_name + ":"

	if max_questions > 0 and _questions_asked >= max_questions:
		prompt += question_limit_prompt_suffix
		if not extra_instruction.is_empty():
			prompt += " " + extra_instruction
		_max_reached = true
		question_limit_reached.emit()
	elif not extra_instruction.is_empty():
		prompt += " " + extra_instruction

	if _response_label:
		_response_label.text = thinking_text
	if _send_button:
		_send_button.disabled = true

	_questions_asked += 1
	LLMManager.query(prompt)


func _on_ai_responded(ai_text: String) -> void:
	_conversation_history.append("%s: %s" % [ai_speaker_name, ai_text])
	_log_history.append("%s: %s" % [ai_speaker_name, ai_text])

	ai_responded.emit(ai_text)

	if use_typewriter_effect:
		_start_typewriter(ai_text)
	else:
		if _response_label:
			_response_label.text = ai_text
		_reset_input_state()

	_flush_log()


func _on_all_providers_failed(error: String) -> void:
	if _response_label:
		_response_label.text = "Error: Could not reach AI. Please try again."
	if _send_button:
		_send_button.disabled = false
	push_error("[ChatController] All LLM providers failed: %s" % error)

# ---------------------------------------------------------------------------
# Internal — Typewriter
# ---------------------------------------------------------------------------

func _start_typewriter(full_text: String) -> void:
	_set_sprite_texture("talking")

	if _response_label:
		_response_label.text = full_text
		_response_label.visible_characters = 0

	if _typing_tween:
		_typing_tween.kill()

	_typing_tween = create_tween()
	var duration : float = full_text.length() / max(typing_speed, 1.0)
	_typing_tween.tween_property(
		_response_label, "visible_characters", full_text.length(), duration
	)
	_typing_tween.finished.connect(_reset_input_state, CONNECT_ONE_SHOT)


func _set_label_full_text() -> void:
	if _response_label:
		_response_label.visible_characters = -1


func _reset_input_state() -> void:
	if _send_button and not _max_reached:
		_send_button.disabled = false
	_set_sprite_texture("neutral")

# ---------------------------------------------------------------------------
# Internal — Character sprite helpers
# ---------------------------------------------------------------------------

func _set_sprite_texture(key: String) -> void:
	if character_sprite and character_textures.has(key):
		character_sprite.texture = character_textures[key]

# ---------------------------------------------------------------------------
# Internal — Logging
# ---------------------------------------------------------------------------

## Called after every AI response. Override to customise persistence behaviour.
## Default implementation emits conversation_saved with the current batch.
func _flush_log() -> void:
	if _log_history.is_empty():
		return
	conversation_saved.emit(_log_history.duplicate())
	_log_history.clear()
