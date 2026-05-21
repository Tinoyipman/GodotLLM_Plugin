## GoogleAIProvider.gd
## LLM provider that calls the Google AI Studio (Gemini) REST API directly.
## Intended as a fallback when Portkey is unavailable, but works standalone too.
##
## Usage:
##   var g = GoogleAIProvider.new()
##   g.api_key = "your-google-ai-studio-key"
##   g.model   = "gemini-2.0-flash-lite"
##   LLMManager.add_provider(g)

class_name GoogleAIProvider
extends LLMProvider

## Your Google AI Studio API key.
var api_key: String = ""

## Gemini model name, e.g. "gemini-2.0-flash-lite" or "gemini-1.5-pro".
var model: String = "gemini-2.0-flash-lite"

const _BASE_URL := "https://generativelanguage.googleapis.com/v1beta/models/"

func _init() -> void:
	provider_name = "Google AI Studio"


func send_request(parent_node: Node, prompt: String) -> void:
	if api_key.is_empty() or model.is_empty():
		request_failed.emit("GoogleAIProvider api_key or model is not configured.")
		return

	var http := HTTPRequest.new()
	parent_node.add_child(http)

	var url := _BASE_URL + model + ":generateContent?key=" + api_key
	var headers := ["Content-Type: application/json"]
	var body := JSON.stringify({
		"contents": [{"parts": [{"text": prompt}]}],
	})

	http.request_completed.connect(_on_completed.bind(http))
	http.request(url, headers, HTTPClient.METHOD_POST, body)


func _on_completed(_result: int, response_code: int, _headers: PackedStringArray,
		body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	var json := _parse_json(body)

	if response_code == 200 and json.has("candidates"):
		var text: String = json["candidates"][0]["content"]["parts"][0]["text"]
		response_received.emit(text)
	else:
		var msg := "HTTP %d" % response_code
		if json.has("error"):
			msg += " – " + str(json["error"].get("message", ""))
		push_warning("[GoogleAI] Request failed: %s" % msg)
		request_failed.emit(msg)
