## LLMProvider.gd
## Abstract base class for all LLM providers.
##
## To add a custom provider:
##   1. Create a new script that extends LLMProvider.
##   2. Override _send_request() to implement the API call.
##   3. Emit response_received(text) on success or error_occurred(message) on failure.
##   4. Register it via LLMManager.add_provider().

class_name LLMProvider
extends RefCounted

## Emitted when the provider returns a successful text response.
signal response_received(text: String)

## Emitted when this provider fails, so the manager can fall back.
signal request_failed(error_message: String)

## Human-readable name shown in logs and debug output.
var provider_name: String = "BaseProvider"

## Override in subclass. Called by LLMManager with the full prompt string.
## Must emit either response_received or request_failed when done.
func send_request(_parent_node: Node, _prompt: String) -> void:
	push_error("[LLMProvider] send_request() not implemented in '%s'." % provider_name)
	request_failed.emit("send_request() not implemented.")


## Convenience: parse a raw UTF-8 body PackedByteArray to a Dictionary.
## Returns an empty Dictionary on parse failure.
func _parse_json(body: PackedByteArray) -> Dictionary:
	var text := body.get_string_from_utf8()
	var result = JSON.parse_string(text)
	if result is Dictionary:
		return result
	push_warning("[%s] Could not parse JSON response." % provider_name)
	return {}
