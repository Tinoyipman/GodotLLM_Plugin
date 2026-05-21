## PortkeyProvider.gd
## LLM provider that routes requests through the Portkey AI gateway.
## Portkey supports OpenAI-compatible chat completions format.
##
## Usage:
##   var p = PortkeyProvider.new()
##   p.api_key = "your-portkey-key"
##   p.model   = "@openrouter/google/gemini-2.0-flash-lite"  # any Portkey route
##   LLMManager.add_provider(p)

class_name PortkeyProvider
extends LLMProvider

## Your Portkey API key.
var api_key: String = ""

## The model/route string understood by Portkey (e.g. "@openrouter/...").
var model: String = ""

const _URL := "https://api.portkey.ai/v1/chat/completions"

func _init() -> void:
	provider_name = "Portkey"


func send_request(parent_node: Node, prompt: String) -> void:
	if api_key.is_empty() or model.is_empty():
		request_failed.emit("Portkey api_key or model is not configured.")
		return

	var http := HTTPRequest.new()
	parent_node.add_child(http)

	var headers := [
		"Content-Type: application/json",
		"x-portkey-api-key: " + api_key,
	]
	var body := JSON.stringify({
		"model": model,
		"messages": [{"role": "user", "content": prompt}],
	})

	http.request_completed.connect(_on_completed.bind(http))
	http.request(_URL, headers, HTTPClient.METHOD_POST, body)


func _on_completed(_result: int, response_code: int, _headers: PackedStringArray,
		body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	var json := _parse_json(body)

	if response_code == 200 and json.has("choices"):
		var text: String = json["choices"][0]["message"]["content"]
		response_received.emit(text)
	else:
		var msg := "HTTP %d" % response_code
		if json.has("error"):
			msg += " – " + str(json["error"])
		push_warning("[Portkey] Request failed: %s" % msg)
		request_failed.emit(msg)
