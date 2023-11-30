@tool
extends EditorPlugin


var _scripts_tab_container: TabContainer
var _scripts_item_list: ItemList
var _scenes_tab_bar: TabBar
var _switcher: Switcher

var _base_sh_key


func _enter_tree() -> void:
	if OS.has_feature("macos"):
		_base_sh_key = KEY_ALT
	else:
		_reset_default_tabs_shortcuts()
		_base_sh_key = KEY_CTRL
	
	scene_changed.connect(_on_scene_changed)
	
	var script_editor = get_editor_interface().get_script_editor()
	_scripts_tab_container = _first_or_null(script_editor.find_children(
			"*", "TabContainer", true, false
		)
	)
	_scripts_item_list = _first_or_null(script_editor.find_children(
		"*", "ItemList", true, false
	))
	_scenes_tab_bar = _get_scenes_tab_bar()

	if _scripts_tab_container:
		_scripts_tab_container.tab_changed.connect(_on_script_tab_changed)
	
	_switcher = Switcher.new()
	_switcher.editor_interface = get_editor_interface()
	_switcher.scripts_tab_container = _scripts_tab_container
	_switcher.base_sh_key = _base_sh_key
	get_editor_interface().get_base_control().add_child(_switcher)


func _exit_tree() -> void:
	scene_changed.disconnect(_on_scene_changed)
	if _scripts_tab_container:
		_scripts_tab_container.tab_changed.disconnect(_on_script_tab_changed)	


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var base_sh_key_pressed = Input.is_key_pressed(_base_sh_key)
		if base_sh_key_pressed and event.keycode in [KEY_TAB, KEY_BACKTAB]:
			if not _switcher.visible:
				_switcher.raise()


func _on_scene_changed(node: Node):
	var path
	if node:
		path = node.scene_file_path
	if path:
		_add_to_history(HistoryItemScene.new(
			path,
			_scenes_tab_bar.get_tab_icon(_scenes_tab_bar.current_tab),
			get_editor_interface()
		))


func _get_scenes_tab_bar():
	var _main_screen
	for c in get_editor_interface().get_base_control().find_children("*", "VBoxContainer", true, false):
		if c.name == "MainScreen":
			_main_screen = c
			break
	if _main_screen:
		var central_screen_box = _main_screen.get_parent().get_parent()
		return _first_or_null(central_screen_box.find_children("*", "TabBar", true, false))
	return null


func _on_script_tab_changed(idx):
	_add_to_history(HistoryItemScript.new(
		weakref(_scripts_tab_container.get_tab_control(idx)),
		_scripts_tab_container,
		_scripts_item_list
	))


func _reset_default_tabs_shortcuts():
	var default_sh = get_editor_interface().get_editor_settings().get("shortcuts") as Array
	var check_sh = func(sh_name):
		if len(default_sh.filter(func(x): return x.name == sh_name)) == 0:
			get_editor_interface().get_editor_settings().set(
				"shortcuts", 
				[{ "name": sh_name, "shortcuts": []}]
			)
	check_sh.call("editor/next_tab")
	check_sh.call("editor/prev_tab")


func _add_to_history(el: HistoryItem):
	_switcher.add_to_history(el)


func _first_or_null(arr):
	if len(arr) == 0:
		return null
	return arr[0]


class Switcher extends AcceptDialog:
	var editor_interface: EditorInterface
	var scripts_tab_container: TabContainer
	var base_sh_key
	
	var _history_tree: Tree
	var _root: TreeItem
	var _check_boxes: HBoxContainer
	
	var _history: Array[HistoryItem] = []
	var _filter_types = []
	
	func _init() -> void:
		title = "Switcher"
		
		var vb = VBoxContainer.new()
		
		_history_tree = Tree.new()
		_history_tree.hide_root = true
		_history_tree.hide_folding = true
		_history_tree.item_activated.connect(_handle_confirmed)
		_history_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_history_tree.focus_mode = Control.FOCUS_NONE
		_root = _history_tree.create_item()
		vb.add_child(_history_tree)
		
		_check_boxes = HBoxContainer.new()
		_check_boxes.alignment = BoxContainer.ALIGNMENT_END
		_add_filter_checkbox("script", true, _add_filter("script"))
		_add_filter_checkbox("scene", true, _add_filter("scene"))
		_add_filter_checkbox("doc", true, _add_filter("doc"))
		vb.add_child(_check_boxes)

		add_child(vb)
		
		get_ok_button().hide()
	
	func _ready() -> void:
		set_process_input(false)
	
	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.keycode == base_sh_key:
			if not event.pressed:
				_handle_confirmed()
				return
		
		var k = event as InputEventKey
		if k and k.pressed:
			if k.keycode in [KEY_PAGEUP, KEY_UP]:
				_select_prev()
			if k.keycode in [KEY_PAGEDOWN, KEY_DOWN, KEY_BACKTAB]:
				_select_next()
			if k.keycode == KEY_TAB:
				if k.shift_pressed:
					_select_prev()
				else:
					_select_next()

	func add_to_history(el: HistoryItem):
		el.add_to(_history)
		if len(_history) > 20:
			_history.resize(20)
	
	func raise():
		popup_centered_ratio(0.3)
		set_process_input.bind(true).call_deferred()
		_update_tree()
	
	func _select_next():
		var selected = _history_tree.get_selected()
		if not selected or _root.get_child_count() == 0:
			return
		var idx = selected.get_index()
		idx = wrapi(idx + 1, 0, _root.get_child_count())
		_root.get_child(idx).select(0)
		_history_tree.ensure_cursor_is_visible()
	
	func _select_prev():
		var selected = _history_tree.get_selected()
		if not selected or _root.get_child_count() == 0:
			return
		var idx = selected.get_index()
		idx = wrapi(idx - 1, 0, _root.get_child_count())
		_root.get_child(idx).select(0)
		_history_tree.ensure_cursor_is_visible()
	
	func _handle_confirmed():
		var selected = _history_tree.get_selected()
		if selected and selected.has_meta("ref"):
			selected.get_meta("ref").open()
		hide()
	
	func _update_tree():
		_clear_tree_item_children(_root)

		var first_history_item: HistoryItem
		var item_to_select: TreeItem
		for el in _history.duplicate():
			if el.is_valid() and el.has_filter(_filter_types):
				var item = _history_tree.create_item(_root)
				el.fill(item)
				item.set_meta("ref", el)
				
				if not first_history_item:
					first_history_item = el
				else:
					if not item_to_select and first_history_item.has_same_type_as(el):
						item_to_select = item
			if not el.is_valid():
				_history.erase(el)
		
		if item_to_select:
			item_to_select.select(0)
		elif _root.get_child_count() > 1:
			_root.get_child(1).select(0)
		elif _root.get_child_count() > 0:
			_root.get_child(0).select(0)
		_history_tree.ensure_cursor_is_visible()

	func _clear_tree_item_children(item):
		if not item: 
			return
		for child in item.get_children():
			item.remove_child(child)
			child.free()
	
	func _add_filter(filter_name):
		return func(toggled):
			var found_filter_idx = _filter_types.find(filter_name)
			if found_filter_idx != -1:
				_filter_types.remove_at(found_filter_idx)
			if toggled:
				_filter_types.append(filter_name)
			_update_tree()
	
	func _add_filter_checkbox(cname, button_pressed, on_toggled):
		var check_box = CheckBox.new()
		check_box.text = cname
		check_box.toggled.connect(on_toggled)
		check_box.button_pressed = button_pressed
		_check_boxes.add_child(check_box)


class HistoryItem:
	func add_to(history: Array[HistoryItem]):
		var copy = history.duplicate()
		for el in copy:
			if el.equals(self):
				history.erase(el)
		history.push_front(self)
	
	func equals(another) -> bool:
		return false
	
	func fill(item: TreeItem):
		pass
	
	func is_valid() -> bool:
		return false
	
	func open():
		pass
	
	func has_filter(types) -> bool:
		return true
	
	func has_same_type_as(another) -> bool:
		return false


class HistoryItemScene extends HistoryItem:
	var _editor_interface
	var _scene_path: String
	var _icon
	
	func _init(scene_path, icon, editor_interface) -> void:
		_scene_path = scene_path
		_icon = icon
		_editor_interface = editor_interface

	func equals(another) -> bool:
		if not another is HistoryItemScene:
			return false
		return self._scene_path == another._scene_path
	
	func fill(item: TreeItem):
		item.set_text(0, _scene_path.get_file().get_basename())
		item.set_icon(0, _icon)
	
	func is_valid() -> bool:
		return self._scene_path in _editor_interface.get_open_scenes()
	
	func open():
		if is_valid():
			_editor_interface.open_scene_from_path(self._scene_path)
	
	func has_filter(types) -> bool:
		return "scene" in types
	
	func has_same_type_as(another) -> bool:
		return another is HistoryItemScene


class HistoryItemScript extends HistoryItem:
	var _scripts_tab_container: TabContainer
	var _scripts_item_list: ItemList
	var _control: WeakRef
	
	func _init(control, scripts_tab_container, scripts_item_list) -> void:
		_control = control
		_scripts_tab_container = scripts_tab_container
		_scripts_item_list = scripts_item_list

	func equals(another) -> bool:
		if not another is HistoryItemScript:
			return false
		return self._control.get_ref() == another._control.get_ref()
	
	func fill(item: TreeItem):
		var control: Control = _control.get_ref()
		if control:
			var tab_idx = _scripts_tab_container.get_tab_idx_from_control(control)
			var list_item_idx = _find_item_list_idx_by_tab_idx(tab_idx)
			if list_item_idx != -1:
				item.set_text(0, _scripts_item_list.get_item_text(list_item_idx))
				item.set_icon(0, _scripts_item_list.get_item_icon(list_item_idx))

	func is_valid() -> bool:
		return self._control.get_ref() != null
	
	func open():
		var control: Control = _control.get_ref()
		if control:
			var tab_idx = _scripts_tab_container.get_tab_idx_from_control(control)
			var item_idx = _find_item_list_idx_by_tab_idx(tab_idx)
			if item_idx != -1:
				if not _scripts_item_list.is_selected(item_idx):
					_scripts_item_list.select(item_idx)
					_scripts_item_list.item_selected.emit(item_idx)
	
	func has_filter(types) -> bool:
		var control: Control = _control.get_ref()
		if not control:
			return false
		if "EditorHelp" in str(control):
			return "doc" in types
		else:
			return "script" in types
	
	func _find_item_list_idx_by_tab_idx(tab_idx) -> int:
		for i in _scripts_item_list.item_count:
			var metadata = _scripts_item_list.get_item_metadata(i)
			if metadata == tab_idx:
				return i
		return -1
	
	func has_same_type_as(another) -> bool:
		return another is HistoryItemScript
