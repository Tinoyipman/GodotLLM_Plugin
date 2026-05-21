## LLMManager.gd  (Autoload singleton: "LLMManager")
##
## Central hub for LLM queries. Maintains an ordered list of providers and
## tries them in sequence until one succeeds (waterfall fallback).
##
## ── Quick Start ──────────────────────────────────────────────────────────────
##
##   # In your project's _ready() or an autoload:
##   var portkey = PortkeyProvider.new()
##   portkey.api_key = "pk-..."
##   portkey.model   = "@openrouter/google/gemini-2.0-flash-lite"
##   LLMManager.add_provider(portkey)
##
##   var google = GoogleAIProvider.new()
##   google.api_key = "AIza..."
##   google.model   = "gemini-2.0-flash-lite"
##   LLMManager.add_provider(google)   # used as fallback
##
##   LLMManager.response_received.connect(_on_ai_response)
##   LLMManager.query("Hello!")
##
## ─────────────────────────────────────────────────────────────────────────────

extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted with the final AI text when any provider succeeds.
signal response_received(text: String)

## Emitted if every provider in the chain fails.
signal all_providers_failed(last_error: String)

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## Ordered list of LLMProvider instances. Tried top-to-bottom on each query.
var _providers: Array[LLMProvider] = []

## Index of the provider currently being tried during a query.
var _current_index: int = 0

## The prompt kept alive so fallback providers can reuse it.
var _active_prompt: String = ""

## Name of the provider that handled the last successful query (for logging).
var last_used_provider: String = ""

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Add a provider to the end of the fallback chain.
func add_provider(provider: LLMProvider) -> void:
	_providers.append(provider)
	print("[LLMManager] Provider registered: %s (position %d)" % [provider.provider_name, _providers.size()])


## Remove all registered providers.
func clear_providers() -> void:
	_providers.clear()


## Send a prompt through the provider chain.
## The response_received signal fires when any provider succeeds.
func query(prompt: String) -> void:
	if _providers.is_empty():
		push_error("[LLMManager] query() called but no providers are registered.")
		all_providers_failed.emit("No providers registered.")
		return

	_active_prompt = prompt
	_current_index = 0
	_try_provider(_current_index)


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _try_provider(index: int) -> void:
	if index >= _providers.size():
		push_error("[LLMManager] All providers exhausted.")
		all_providers_failed.emit("All providers failed.")
		return

	var provider: LLMProvider = _providers[index]
	print("[LLMManager] Trying provider [%d/%d]: %s" % [index + 1, _providers.size(), provider.provider_name])

	# Disconnect stale signals (safe to call even if not connected)
	if provider.response_received.is_connected(_on_provider_success):
		provider.response_received.disconnect(_on_provider_success)
	if provider.request_failed.is_connected(_on_provider_failed):
		provider.request_failed.disconnect(_on_provider_failed)

	provider.response_received.connect(_on_provider_success.bind(provider))
	provider.request_failed.connect(_on_provider_failed)

	provider.send_request(self, _active_prompt)


func _on_provider_success(text: String, provider: LLMProvider) -> void:
	last_used_provider = provider.provider_name
	print("[LLMManager] Success via %s." % provider.provider_name)

	# Disconnect this round's signals
	if provider.response_received.is_connected(_on_provider_success):
		provider.response_received.disconnect(_on_provider_success)
	if provider.request_failed.is_connected(_on_provider_failed):
		provider.request_failed.disconnect(_on_provider_failed)

	response_received.emit(text)


func _on_provider_failed(error: String) -> void:
	var failed_provider := _providers[_current_index]
	push_warning("[LLMManager] %s failed: %s. Trying next..." % [failed_provider.provider_name, error])

	if failed_provider.response_received.is_connected(_on_provider_success):
		failed_provider.response_received.disconnect(_on_provider_success)
	if failed_provider.request_failed.is_connected(_on_provider_failed):
		failed_provider.request_failed.disconnect(_on_provider_failed)

	_current_index += 1
	_try_provider(_current_index)
