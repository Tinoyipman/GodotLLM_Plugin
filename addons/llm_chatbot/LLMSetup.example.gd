## LLMSetup.gd — Example project-level setup script
##
## Attach this to an autoload node (or any persistent scene node) to configure
## LLMManager before any ChatController tries to send a query.
##
## This file is NOT part of the plugin itself — copy it into your project and
## edit the credentials and model names to match your accounts.

extends Node

func _ready() -> void:
	# ── Provider 1: Portkey (primary) ──────────────────────────────────────
	# Portkey acts as a gateway/router and supports many model providers.
	# Get your key through Fontys ICT
	var portkey := PortkeyProvider.new()
	portkey.api_key = "YOUR_PORTKEY_API_KEY"      # ← replace
	portkey.model   = "@openrouter/google/gemini-2.0-flash-lite"  # ← replace
	LLMManager.add_provider(portkey)

	# ── Provider 2: Google AI Studio (fallback) ────────────────────────────
	# Used automatically if Portkey fails.
	# Get your key at https://aistudio.google.com/app/apikey
	var google := GoogleAIProvider.new()
	google.api_key = "YOUR_GOOGLE_AI_STUDIO_KEY"  # ← replace
	google.model   = "gemini-2.0-flash-lite"       # ← replace
	LLMManager.add_provider(google)

	print("[LLMSetup] Providers configured.")
