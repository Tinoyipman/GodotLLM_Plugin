@tool
extends EditorPlugin

const AUTOLOAD_NAME := "LLMManager"
const AUTOLOAD_PATH := "res://addons/llm_chatbot/autoload/LLMManager.gd"

func _enter_tree() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	print("[LLM Chatbot] Plugin enabled. LLMManager autoload registered.")

func _exit_tree() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
	print("[LLM Chatbot] Plugin disabled.")
