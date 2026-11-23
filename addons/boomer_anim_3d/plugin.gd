@tool
extends EditorPlugin

const INSPECTOR_PLUGIN_SCRIPT: Script = preload("res://addons/boomer_anim_3d/inspector_plugin.gd")

var _inspector_plugin: EditorInspectorPlugin = null


func _enter_tree() -> void:
	_inspector_plugin = INSPECTOR_PLUGIN_SCRIPT.new() as EditorInspectorPlugin
	if is_instance_valid(_inspector_plugin):
		add_inspector_plugin(_inspector_plugin)


func _exit_tree() -> void:
	if is_instance_valid(_inspector_plugin):
		remove_inspector_plugin(_inspector_plugin)
	_inspector_plugin = null
