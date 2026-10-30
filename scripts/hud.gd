class_name Hud
extends CanvasLayer
## All UI: HUD panels, building windows, title / pause / victory screens.
## UI never edits the simulation directly; it queues commands through main.queue_cmd().

const C_TEXT := Color("#ece6d6")
const C_MUTED := Color("#a59f90")
const C_TITLE := Color("#ffe3b3")
const C_AMBER := Color("#f5a524")
const C_OK := Color("#6cbf4a")
const C_BAD := Color("#e2503b")
const C_CYAN := Color("#5fd4ff")

var main
var th: Theme
var F := {}
var root: Control
var hud_root: Control
var tracker_box: VBoxContainer
var power_lbl: Label
var power_lbl2: Label
var power_bar: ProgressBar
var hover_panel: PanelContainer
var hover_rt: RichTextLabel
var hp_bar: ProgressBar
var hp_lbl: Label
var craftq: HBoxContainer
var hint_rt: RichTextLabel
var quick_btns: Array = []
var mm_rect: TextureRect
var mm_base: Image
var mm_tex: ImageTexture
var toasts: VBoxContainer
var win: PanelContainer
var win_title: Label
var win_body: VBoxContainer
var win_scroll: ScrollContainer
var panel := {}
var sig := ""
var track_sig := ""
var cq_sig := ""
var ui_t := 0.0
var mm_t := 0.0
var hub_tab := "ms"
var title_ov: Control
var menu_ov: Control
var victory_ov: Control
var death_ov: Control
var cont_btn: Button
var menu_note: Label
var victory_lbl: Label
var new_armed := false
var m_dyn: VBoxContainer
var m_clock: HSlider
var m_clock_lbl: Label
var m_shards: HBoxContainer
var m_dsig := ""
var setup_ov: Control
var join_ov: Control
var setup_title: Label
var seed_edit: LineEdit
var setting_btns := {}
var draft := {}
var setup_mode := "single"
var preview_rect: TextureRect
var preview_info: RichTextLabel
var preview_due := 0.0
var host_row: VBoxContainer
var host_name: LineEdit
var host_port: LineEdit
var setup_go: Button
var host_load_btn: Button
var setup_err: Label
var join_name: LineEdit
var join_addr: LineEdit
var join_port: LineEdit
var join_status: Label
var menu_save: Button
var menu_load: Button
var menu_leave: Button
var players_panel: PanelContainer
var players_box: VBoxContainer
var players_sig := ""
var intro: Control
var intro_tw: Tween
var ui_scale := 1.0
var world_name_edit: LineEdit
# loading screen
var load_ov: Control
var load_title: Label
var load_steps: VBoxContainer
var load_bar: ProgressBar
var load_tip: Label
var load_rows: Array = []
var load_tip_t := 0.0
# saves list and settings
var saves_ov: Control
var saves_list: VBoxContainer
var settings_ov: Control
var settings_from_menu := false
var delete_armed := ""
# chat, pings, hints
var chat_box: VBoxContainer
var chat_edit: LineEdit
var chat_lines: Array = []
var pings: Array = []
var hint_panel: PanelContainer
var hint_body: RichTextLabel
var hint_sig := ""
var tracker_panel: PanelContainer

# ------------------------------------------------------------------ theme
func _sb(bg: Color, border := Color.BLACK, bw := 1, pad := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_content_margin_all(pad)
	return s

func _btn_styles(type: String, bg: Color, hover: Color, fg: Color, fg_hover: Color, pad_x := 14, pad_y := 4) -> void:
	if type != "Button":
		th.set_type_variation(type, "Button")
	var n := _sb(bg, Color("#111111"), 1, 0)
	n.content_margin_left = pad_x
	n.content_margin_right = pad_x
	n.content_margin_top = pad_y
	n.content_margin_bottom = pad_y
	n.border_width_top = 1
	var h := n.duplicate()
	h.bg_color = hover
	var p := n.duplicate()
	p.bg_color = hover.darkened(0.1)
	var d := n.duplicate()
	d.bg_color = bg.darkened(0.45)
	var f := StyleBoxEmpty.new()
	th.set_stylebox("normal", type, n)
	th.set_stylebox("hover", type, h)
	th.set_stylebox("pressed", type, p)
	th.set_stylebox("disabled", type, d)
	th.set_stylebox("focus", type, f)
	for k in ["font_color", "font_focus_color"]:
		th.set_color(k, type, fg)
	for k in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		th.set_color(k, type, fg_hover)
	th.set_color("font_disabled_color", type, Color(fg, 0.45))

func make_theme() -> void:
	F.r = load("res://assets/fonts/titillium-web-latin-400-normal.woff2")
	F.s = load("res://assets/fonts/titillium-web-latin-600-normal.woff2")
	F.b = load("res://assets/fonts/titillium-web-latin-700-normal.woff2")
	F.k = load("res://assets/fonts/titillium-web-latin-900-normal.woff2")
	F.m = load("res://assets/fonts/ibm-plex-mono-latin-500-normal.woff2")
	th = Theme.new()
	th.default_font = F.s
	th.default_font_size = 15
	var pnl := _sb(Color("#313031"), Color.BLACK, 1, 10)
	pnl.shadow_color = Color(0, 0, 0, 0.45)
	pnl.shadow_size = 8
	th.set_stylebox("panel", "PanelContainer", pnl)
	th.set_type_variation("Inset", "PanelContainer")
	th.set_stylebox("panel", "Inset", _sb(Color("#1f1e1f"), Color("#0a0a0a"), 1, 10))
	th.set_type_variation("Card", "PanelContainer")
	th.set_stylebox("panel", "Card", _sb(Color("#2b2a2b"), Color.BLACK, 1, 10))
	var clear := StyleBoxEmpty.new()
	th.set_type_variation("Bare", "PanelContainer")
	th.set_stylebox("panel", "Bare", clear)
	_btn_styles("Button", Color("#959495"), Color("#eaa53c"), Color("#111111"), Color("#111111"))
	_btn_styles("GoButton", Color("#6cbf4a"), Color("#8fd96a"), Color("#111111"), Color("#111111"))
	_btn_styles("TabOn", Color("#eaa53c"), Color("#f6bb55"), Color("#111111"), Color("#111111"))
	_btn_styles("SlotButton", Color("#7b7a7b"), Color("#eaa53c"), Color.WHITE, Color.WHITE, 0, 0)
	_btn_styles("SlotSel", Color("#eaa53c"), Color("#f6bb55"), Color.WHITE, Color.WHITE, 0, 0)
	_btn_styles("SlotEmpty", Color("#2a292a"), Color("#3d3c3d"), Color.WHITE, Color.WHITE, 0, 0)
	_btn_styles("RecipeButton", Color("#444344"), Color("#eaa53c"), C_TEXT, Color("#111111"), 8, 4)
	_btn_styles("RecipeOn", Color("#eaa53c"), Color("#f6bb55"), Color("#111111"), Color("#111111"), 8, 4)
	th.set_color("font_color", "Label", C_TEXT)
	th.set_color("default_color", "RichTextLabel", C_TEXT)
	th.set_font("normal_font", "RichTextLabel", F.s)
	th.set_font("bold_font", "RichTextLabel", F.b)
	th.set_font("mono_font", "RichTextLabel", F.m)
	th.set_font_size("normal_font_size", "RichTextLabel", 14)
	th.set_font_size("bold_font_size", "RichTextLabel", 15)
	th.set_font_size("mono_font_size", "RichTextLabel", 13)
	th.set_stylebox("background", "ProgressBar", _sb(Color("#151415"), Color("#000000"), 0, 0))
	var fill := _sb(C_AMBER, C_AMBER, 0, 0)
	th.set_stylebox("fill", "ProgressBar", fill)
	for v in [["OkBar", C_OK], ["HpBar", Color("#d9473a")], ["PowerBar", Color("#6cbf4a")], ["OverBar", C_BAD]]:
		th.set_type_variation(v[0], "ProgressBar")
		th.set_stylebox("fill", v[0], _sb(v[1], v[1], 0, 0))
	var sl := _sb(Color("#151415"), Color.BLACK, 1, 0)
	sl.content_margin_top = 3
	sl.content_margin_bottom = 3
	th.set_stylebox("slider", "HSlider", sl)
	th.set_stylebox("grabber_area", "HSlider", _sb(C_AMBER, C_AMBER, 0, 0))
	th.set_stylebox("grabber_area_highlight", "HSlider", _sb(Color("#f6bb55"), C_AMBER, 0, 0))
	th.set_stylebox("panel", "TooltipPanel", _sb(Color("#1f1e1f"), Color.BLACK, 1, 6))
	th.set_color("font_color", "TooltipLabel", C_TEXT)

# ------------------------------------------------------------------ helpers
func lbl(text: String, size := 15, col := C_TEXT, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func cap(text: String) -> Label:
	return lbl(text.to_upper(), 11, C_MUTED, F.b)

func rt(bb: String, width := 0) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if width > 0:
		r.custom_minimum_size.x = width
	r.text = bb
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func ii(k: String, s := 22) -> String:
	return "[img=%dx%d]res://assets/items/%s.png[/img]" % [s, s, k]

func vbox(sep := 6) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b

func hbox(sep := 8) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b

func inset(title := "") -> Array:
	var p := PanelContainer.new()
	p.theme_type_variation = "Inset"
	var v := vbox(8)
	p.add_child(v)
	if title != "":
		v.add_child(cap(title))
	return [p, v]

func btn(text: String, cb: Callable, enabled := true, variation := "") -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_NONE
	if variation != "":
		b.theme_type_variation = variation
	b.button_down.connect(_click)
	b.button_down.connect(cb)
	return b

func _click() -> void:
	if main.audio:
		main.audio.play("ui_click", -10.0, 0.08)

func icon_rect(k: String, s := 22) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Data.icon(k)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(s, s)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

func slot(tex: Texture2D, count: String, cb = null, tip := "", variation := "SlotButton", size := 44) -> Button:
	var b := Button.new()
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(size, size)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	if tex:
		var t := TextureRect.new()
		t.texture = tex
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		t.offset_left = 4; t.offset_top = 4; t.offset_right = -4; t.offset_bottom = -4
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(t)
	if count != "":
		var l := lbl(count, 13, Color.WHITE, F.b)
		l.add_theme_constant_override("outline_size", 4)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		l.grow_vertical = Control.GROW_DIRECTION_BEGIN
		l.offset_right = -2
		l.offset_bottom = 2
		b.add_child(l)
	if cb != null:
		b.button_down.connect(_click)
		b.button_down.connect(cb)
	return b

func item_slot(k: String, n: int, cb = null, tip_extra := "") -> Button:
	var s := ("%.1fk" % (n / 1000.0)) if n >= 1000 else str(n)
	return slot(Data.icon(k), s, cb, Data.item_name(k) + tip_extra)

func bar(v: float, variation := "", h := 6) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.min_value = 0
	b.max_value = 1
	b.value = clampf(v, 0, 1)
	b.custom_minimum_size.y = h
	if variation != "":
		b.theme_type_variation = variation
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

func pill(st: String) -> PanelContainer:
	var names := {"work": "WORKING", "input": "WAITING FOR INPUT", "full": "OUTPUT FULL", "nopower": "NO POWER", "norecipe": "NO RECIPE", "idle": "IDLE"}
	var cols := {"work": C_OK, "input": Color("#e8c33a"), "full": Color("#e8c33a"), "nopower": C_BAD, "norecipe": C_BAD, "idle": Color("#e8c33a")}
	var p := PanelContainer.new()
	var s := _sb(cols.get(st, C_MUTED), Color.BLACK, 1, 0)
	s.content_margin_left = 8; s.content_margin_right = 8; s.content_margin_top = 1; s.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", s)
	p.add_child(lbl(names.get(st, st), 11, Color.WHITE if st in ["nopower", "norecipe"] else Color("#111111"), F.b))
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return p

func fmt(n: float) -> String:
	return str(int(round(n))) if n >= 100 else str(snappedf(n, 0.1))

func rcp(k: String, clock := 100) -> String:
	var R: Dictionary = Data.RECIPES[k]
	var f: float = 60.0 / R["t"] * clock / 100.0
	var a := []
	for i in R["in"]:
		a.append("%s [font_size=13]%s[/font_size]" % [ii(i), fmt(R["in"][i] * f)])
	var b := []
	for i in R["out"]:
		b.append("%s [font_size=13]%s[/font_size]" % [ii(i), fmt(R["out"][i] * f)])
	return " + ".join(a) + "  [color=#a59f90]→[/color]  " + " + ".join(b) + "[color=#a59f90]/min[/color]"

func sim() -> Sim:
	return main.sim

func pid() -> int:
	return main.pid

func cmd(c: Dictionary) -> void:
	main.queue_cmd(c)

# ------------------------------------------------------------------ setup
func setup(m) -> void:
	main = m
	make_theme()
	root = Control.new()
	root.theme = th
	root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	root.size = get_viewport().get_visible_rect().size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	hud_root = Control.new()
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.visible = false
	root.add_child(hud_root)
	_build_tracker()
	_build_power()
	_build_status()
	_build_quickbar()
	_build_minimap()
	toasts = vbox(6)
	toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toasts.position.y = 14
	toasts.custom_minimum_size.x = 440
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toasts)
	_build_window()
	death_ov = ColorRect.new()
	death_ov.color = Color(0.45, 0.02, 0.0, 0.35)
	death_ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dl := lbl("ENGINEER DOWN\nRedeploying at the HUB", 30, Color("#ffd4c8"), F.k)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_ov.add_child(dl)
	death_ov.visible = false
	root.add_child(death_ov)
	_build_players()
	_build_title()
	_build_setup()
	_build_join()
	_build_menu()
	_build_victory()
	_build_saves()
	_build_settings()
	_build_chat()
	_build_hints()
	_build_loading()
	_build_intro()

# ---- intro: continues from the boot splash, then reveals the title screen
func _build_intro() -> void:
	intro = ColorRect.new()
	intro.color = Color(0.078, 0.067, 0.051)
	intro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	intro.mouse_filter = Control.MOUSE_FILTER_STOP
	var img := TextureRect.new()
	img.texture = load("res://assets/splash.png")
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intro.add_child(img)
	# a band of light that sweeps across once, like a factory floodlight passing
	var sweep := TextureRect.new()
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 0.85, 0.55, 0.0))
	gr.set_color(1, Color(1, 0.85, 0.55, 0.0))
	gr.add_point(0.5, Color(1, 0.85, 0.55, 0.14))
	gt.gradient = gr
	gt.width = 256
	gt.height = 4
	sweep.texture = gt
	sweep.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sweep.stretch_mode = TextureRect.STRETCH_SCALE
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sweep.anchor_top = 0
	sweep.anchor_bottom = 1
	sweep.size.x = 420
	sweep.rotation = 0.0
	intro.add_child(sweep)
	intro.gui_input.connect(_intro_input)
	root.add_child(intro)
	var vw := root.get_viewport_rect().size.x
	sweep.position = Vector2(-500, 0)
	intro_tw = intro.create_tween()
	intro_tw.tween_property(sweep, "position:x", vw + 100, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_delay(0.3)
	intro_tw.tween_interval(0.5)
	intro_tw.tween_property(intro, "modulate:a", 0.0, 0.6)
	intro_tw.tween_callback(_free_intro)

func _intro_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		end_intro()

func intro_active() -> bool:
	return intro != null

func end_intro() -> void:
	if intro == null:
		return
	if intro_tw:
		intro_tw.kill()
	intro_tw = intro.create_tween()
	intro_tw.tween_property(intro, "modulate:a", 0.0, 0.25)
	intro_tw.tween_callback(_free_intro)

func _free_intro() -> void:
	if intro:
		intro.queue_free()
		intro = null

func _corner_panel(preset: int, pos: Vector2, w := 0) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_and_offsets_preset(preset)
	if w > 0:
		p.custom_minimum_size.x = w
	match preset:
		Control.PRESET_TOP_RIGHT:
			p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_BOTTOM_LEFT:
			p.grow_vertical = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_BOTTOM_RIGHT:
			p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_left += pos.x
	p.offset_right += pos.x
	p.offset_top += pos.y
	p.offset_bottom += pos.y
	hud_root.add_child(p)
	return p

func _build_tracker() -> void:
	var p := _corner_panel(Control.PRESET_TOP_LEFT, Vector2(16, 12), 290)
	tracker_panel = p
	tracker_box = vbox(4)
	p.add_child(tracker_box)

func _build_power() -> void:
	var p := _corner_panel(Control.PRESET_TOP_RIGHT, Vector2(-16, 12), 260)
	var v := vbox(5)
	p.add_child(v)
	var r := hbox()
	r.add_child(cap("Power grid"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(sp)
	power_lbl2 = lbl("", 12, C_MUTED, F.m)
	r.add_child(power_lbl2)
	v.add_child(r)
	power_bar = bar(0, "PowerBar", 10)
	v.add_child(power_bar)
	power_lbl = lbl("", 13, C_TEXT, F.m)
	v.add_child(power_lbl)
	hover_panel = _corner_panel(Control.PRESET_TOP_RIGHT, Vector2(-16, 112), 260)
	hover_rt = rt("", 238)
	hover_panel.add_child(hover_rt)
	hover_panel.visible = false

func _build_status() -> void:
	var p := _corner_panel(Control.PRESET_BOTTOM_LEFT, Vector2(16, -12), 290)
	var v := vbox(6)
	p.add_child(v)
	var r := hbox()
	r.add_child(cap("Engineer"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(sp)
	hp_lbl = lbl("100", 12, C_TEXT, F.m)
	r.add_child(hp_lbl)
	v.add_child(r)
	hp_bar = bar(1, "HpBar", 10)
	v.add_child(hp_bar)
	craftq = hbox(3)
	v.add_child(craftq)
	hint_rt = rt("", 268)
	v.add_child(hint_rt)

func _build_quickbar() -> void:
	var p := PanelContainer.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_top -= 12
	p.offset_bottom -= 12
	var s := _sb(Color("#313031"), Color.BLACK, 1, 5)
	p.add_theme_stylebox_override("panel", s)
	hud_root.add_child(p)
	var h := hbox(2)
	p.add_child(h)
	for i in Data.QUICK.size():
		var t: String = Data.QUICK[i]
		var b := slot(Data.tex("icons/" + t), "", func(): main.select_quick(i), "%s\n%s" % [Data.BUILD[t]["n"], Data.cost_str(Data.BUILD[t]["cost"])])
		if i < 10:
			var k := lbl(str((i + 1) % 10), 10, Color("#222222"), F.b)
			k.position = Vector2(3, -1)
			b.add_child(k)
		h.add_child(b)
		quick_btns.append(b)

func _build_minimap() -> void:
	var p := _corner_panel(Control.PRESET_BOTTOM_RIGHT, Vector2(-16, -12))
	var s := _sb(Color("#313031"), Color.BLACK, 1, 5)
	p.add_theme_stylebox_override("panel", s)
	mm_rect = TextureRect.new()
	mm_rect.custom_minimum_size = Vector2(176, 176)
	mm_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mm_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mm_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(mm_rect)
	rebuild_minimap()

func rebuild_minimap() -> void:
	mm_base = World.preview_image(false)
	mm_tex = ImageTexture.create_from_image(mm_base)
	if mm_rect:
		mm_rect.texture = mm_tex

func _build_window() -> void:
	win = PanelContainer.new()
	win.custom_minimum_size = Vector2(760, 0)
	win.visible = false
	root.add_child(win)
	var v := vbox(8)
	win.add_child(v)
	var h := hbox(10)
	win_title = lbl("", 18, C_TITLE, F.b)
	h.add_child(win_title)
	var grip := TextureRect.new()
	var img := Image.create(4, 14, false, Image.FORMAT_RGBA8)
	for y in 14:
		for x in 4:
			img.set_pixel(x, y, Color("#454445") if x < 2 else Color("#262526"))
	grip.texture = ImageTexture.create_from_image(img)
	grip.stretch_mode = TextureRect.STRETCH_TILE
	grip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grip.custom_minimum_size = Vector2(20, 14)
	grip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(grip)
	h.add_child(btn("X", close_panel))
	v.add_child(h)
	win_scroll = ScrollContainer.new()
	win_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win_scroll.custom_minimum_size = Vector2(0, 120)
	v.add_child(win_scroll)
	win_body = vbox(10)
	win_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	win_scroll.add_child(win_body)

func _overlay() -> Array:
	var o := Control.new()
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := TextureRect.new()
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(0.047, 0.039, 0.031, 0.94))
	gr.set_color(1, Color(0.047, 0.039, 0.031, 0.12))
	gr.add_point(0.46, Color(0.047, 0.039, 0.031, 0.8))
	gt.gradient = gr
	gt.width = 256
	gt.height = 4
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 96)
	m.add_theme_constant_override("margin_top", 40)
	m.add_theme_constant_override("margin_bottom", 40)
	o.add_child(m)
	var v := vbox(18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.custom_minimum_size.x = 560
	v.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	m.add_child(v)
	var stripe := TextureRect.new()
	var img := Image.create(320, 10, false, Image.FORMAT_RGBA8)
	for y in 10:
		for x in 320:
			img.set_pixel(x, y, C_AMBER if posmod(x + y, 20) < 10 else Color("#17140f"))
	stripe.texture = ImageTexture.create_from_image(img)
	stripe.custom_minimum_size = Vector2(320, 10)
	stripe.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(stripe)
	root.add_child(o)
	return [o, v]

func _brand(a: String, b: String, size := 88) -> VBoxContainer:
	var v := vbox(-int(size * 0.5))
	v.add_child(lbl(a, size, Color("#f1e6cf"), F.k))
	if b != "":
		v.add_child(lbl(b, size, C_AMBER, F.k))
	return v

func _build_title() -> void:
	var r := _overlay()
	title_ov = r[0]
	var v: VBoxContainer = r[1]
	v.add_child(_brand("FERRUM", "FRONTIER"))
	var tag := lbl("You are dropped on an uncharted world with a HUB and a pack of parts. Tap the resource nodes, belt everything together, overclock what you can, and build the Space Elevator. Alone or with friends.", 18, Color("#d4ccb9"), F.r)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.custom_minimum_size.x = 520
	v.add_child(tag)
	var row := hbox(10)
	row.add_child(btn("New game", func(): open_setup("single"), true, "GoButton"))
	row.add_child(btn("Host game", func(): open_setup("host")))
	row.add_child(btn("Join game", func(): open_join()))
	row.add_child(btn("Load game", func(): open_saves()))
	row.add_child(btn("Settings", func(): open_settings(false)))
	cont_btn = btn("Continue", func(): main.load_and_play(main.latest_save_path()))
	cont_btn.visible = main.latest_save_path() != ""
	row.add_child(cont_btn)
	v.add_child(row)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 6)
	for pair in [["W A S D", "Walk. Your zapper fires on its own at wildlife in range."], ["1 – 0  ·  click bar", "Pick a building. R rotates, Q picks up or clears."], ["Left click", "Place, or open a building. Drag to lay belts. Hold on an ore node to mine by hand."], ["Hold F", "Grab items off belts around you and under the cursor."], ["Hold right click", "Deconstruct. You get the full cost back."], ["E  ·  Esc  ·  Alt", "Inventory and crafting · menu · toggle recipe icons"], ["Mouse wheel", "Zoom"]]:
		g.add_child(lbl(pair[0], 14, C_AMBER, F.b))
		var d := lbl(pair[1], 14, Color("#cfc7b4"), F.r)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 380
		g.add_child(d)
	v.add_child(g)

func _line(text: String, width := 220, placeholder := "") -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.custom_minimum_size.x = width
	e.add_theme_stylebox_override("normal", _sb(Color("#1f1e1f"), Color("#0a0a0a"), 1, 6))
	e.add_theme_stylebox_override("focus", _sb(Color("#1f1e1f"), C_AMBER, 1, 6))
	e.add_theme_color_override("font_color", C_TEXT)
	e.add_theme_color_override("caret_color", C_AMBER)
	return e

func typing() -> bool:
	return root.get_viewport().gui_get_focus_owner() is LineEdit

# ---- world setup (new game / host)
func _build_setup() -> void:
	var r := _overlay()
	setup_ov = r[0]
	var v: VBoxContainer = r[1]
	setup_title = lbl("", 40, Color("#f1e6cf"), F.k)
	v.add_child(setup_title)
	var cols := hbox(28)
	v.add_child(cols)
	var left := vbox(10)
	cols.add_child(left)
	var seed_row := hbox(8)
	seed_row.add_child(_fixed(lbl("Seed", 14, C_AMBER, F.b), 130))
	seed_edit = _line("", 200, "number or any word")
	seed_edit.text_changed.connect(func(_t): _setup_changed())
	seed_row.add_child(seed_edit)
	seed_row.add_child(btn("Random", func():
		seed_edit.text = str(randi() % 1000000000)
		_setup_changed()))
	left.add_child(seed_row)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 5)
	for d in Data.SETTING_DEFS:
		g.add_child(_fixed(lbl(d.label, 14, C_AMBER, F.b), 130))
		var h := hbox(2)
		var key: String = d.key
		var bs := []
		for i in d.options.size():
			var idx: int = i
			var b := btn(d.options[i], func():
				draft[key] = idx
				_setup_changed())
			b.add_theme_font_size_override("font_size", 13)
			b.custom_minimum_size.x = 74
			bs.append(b)
			h.add_child(b)
		setting_btns[key] = bs
		g.add_child(h)
	left.add_child(g)
	var wr := hbox(8)
	wr.add_child(_fixed(lbl("World name", 14, C_AMBER, F.b), 130))
	world_name_edit = _line("", 280, "used for the save file")
	wr.add_child(world_name_edit)
	left.add_child(wr)
	var nr := hbox(8)
	nr.add_child(_fixed(lbl("Your name", 14, C_AMBER, F.b), 130))
	host_name = _line(str(main.pref("name", "Engineer")), 200)
	nr.add_child(host_name)
	left.add_child(nr)
	host_row = vbox(8)
	var pr := hbox(8)
	pr.add_child(_fixed(lbl("Port", 14, C_AMBER, F.b), 130))
	host_port = _line(str(main.pref("port", Data.DEFAULT_PORT)), 100)
	pr.add_child(host_port)
	host_row.add_child(pr)
	left.add_child(host_row)
	var br := hbox(10)
	br.add_child(btn("Back", func(): show_title()))
	setup_go = btn("Start", _setup_start, true, "GoButton")
	br.add_child(setup_go)
	left.add_child(br)
	setup_err = lbl("", 14, C_BAD, F.s)
	left.add_child(setup_err)
	var right := vbox(8)
	cols.add_child(right)
	right.add_child(cap("Map preview"))
	var pf := PanelContainer.new()
	pf.theme_type_variation = "Inset"
	preview_rect = TextureRect.new()
	preview_rect.custom_minimum_size = Vector2(320, 320)
	preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pf.add_child(preview_rect)
	right.add_child(pf)
	preview_info = rt("", 320)
	right.add_child(preview_info)
	setup_ov.visible = false

func _fixed(c: Control, w: int) -> Control:
	c.custom_minimum_size.x = w
	return c

func open_setup(mode: String) -> void:
	setup_mode = mode
	draft = Data.default_settings()
	draft.seed = randi() % 1000000000
	seed_edit.text = str(draft.seed)
	setup_title.text = "HOST A GAME" if mode == "host" else "NEW WORLD"
	setup_go.text = "Host" if mode == "host" else "Start"
	host_row.visible = mode == "host"
	host_name.text = main.player_name()
	world_name_edit.text = ""
	setup_err.text = ""
	title_ov.visible = false
	join_ov.visible = false
	setup_ov.visible = true
	_setup_changed()

func _setup_changed() -> void:
	draft.seed = Data.parse_seed(seed_edit.text) if seed_edit.text.strip_edges() != "" else 0
	for key in setting_btns:
		var bs: Array = setting_btns[key]
		for i in bs.size():
			bs[i].theme_type_variation = "TabOn" if int(draft.get(key, 0)) == i else ""
	preview_due = 0.35

func _regen_preview() -> void:
	World.generate(draft)
	main.reset_demo()
	preview_rect.texture = ImageTexture.create_from_image(World.preview_image())
	var counts := {"iron_ore": 0, "copper_ore": 0, "limestone": 0, "coal": 0}
	var pure := 0
	for n in World.nodes:
		counts[n.res] += 1
		if n.pur == 200:
			pure += 1
	preview_info.text = "%s %d   %s %d   %s %d   %s %d   [color=#a59f90]· %d pure[/color]\n[color=#ff6a52]■[/color] %d burrows   [color=#d79bff]■[/color] %d crash pods   [color=#f5a524]■[/color] HUB" % [ii("iron_ore", 18), counts.iron_ore, ii("copper_ore", 18), counts.copper_ore, ii("limestone", 18), counts.limestone, ii("coal", 18), counts.coal, pure, World.nests.size(), World.pods.size()]

func _setup_start() -> void:
	preview_due = 0
	setup_ov.visible = false
	var pname := host_name.text.strip_edges().substr(0, 20)
	if pname == "":
		pname = "Engineer"
	main.set_pref("name", pname)
	var wname := world_name_edit.text.strip_edges().substr(0, 40)
	if setup_mode == "host":
		var port := host_port.text.to_int()
		if port < 1024 or port > 65535:
			port = Data.DEFAULT_PORT
		main.set_pref("port", port)
		var err: String = main.start_host(draft.duplicate(), pname, port, wname)
		if err != "":
			setup_ov.visible = true
			setup_err.text = err
	else:
		main.start_offline(draft.duplicate(), pname, wname)

# ---- join
func _build_join() -> void:
	var r := _overlay()
	join_ov = r[0]
	var v: VBoxContainer = r[1]
	v.add_child(lbl("JOIN A GAME", 40, Color("#f1e6cf"), F.k))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	g.add_child(_fixed(lbl("Your name", 14, C_AMBER, F.b), 130))
	join_name = _line(main.player_name(), 220)
	g.add_child(join_name)
	g.add_child(_fixed(lbl("Host address", 14, C_AMBER, F.b), 130))
	join_addr = _line(str(main.pref("addr", "127.0.0.1")), 220, "IP address or hostname")
	g.add_child(join_addr)
	g.add_child(_fixed(lbl("Port", 14, C_AMBER, F.b), 130))
	join_port = _line(str(main.pref("port", Data.DEFAULT_PORT)), 100)
	g.add_child(join_port)
	v.add_child(g)
	var br := hbox(10)
	br.add_child(btn("Back", func():
		main.net.shutdown()
		show_title()))
	br.add_child(btn("Connect", _join_go, true, "GoButton"))
	v.add_child(br)
	join_status = lbl("Both players need the same game version (%s). The host may need to open the port in their firewall or router." % Data.VERSION, 14, C_MUTED, F.r)
	join_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	join_status.custom_minimum_size.x = 520
	v.add_child(join_status)
	main.net.status.connect(func(m): join_status.text = m)
	join_ov.visible = false

func open_join() -> void:
	join_name.text = main.player_name()
	title_ov.visible = false
	setup_ov.visible = false
	join_ov.visible = true

func _join_go() -> void:
	var pname := join_name.text.strip_edges()
	if pname == "":
		pname = "Engineer"
	var addr := join_addr.text.strip_edges()
	var port := join_port.text.to_int()
	if port <= 0:
		port = Data.DEFAULT_PORT
	main.set_pref("name", pname)
	main.set_pref("addr", addr)
	main.set_pref("port", port)
	var err: String = main.start_join(addr, port, pname)
	if err != "":
		join_status.text = err

## Returns true if the join screen showed the error itself.
func on_dropped(msg: String) -> bool:
	if join_ov.visible:
		join_status.text = msg
		return true
	return false

func show_title() -> void:
	setup_ov.visible = false
	join_ov.visible = false
	menu_ov.visible = false
	victory_ov.visible = false
	hud_root.visible = false
	close_panel()
	cont_btn.visible = main.latest_save_path() != ""
	saves_ov.visible = false
	settings_ov.visible = false
	title_ov.visible = true

func back_to_title() -> bool:
	if setup_ov.visible or join_ov.visible:
		main.net.shutdown()
		show_title()
		return true
	return false

func _build_menu() -> void:
	var r := _overlay()
	menu_ov = r[0]
	var v: VBoxContainer = r[1]
	v.add_child(_brand("PAUSED", "", 56))
	var row := hbox(10)
	row.add_child(btn("Resume", func(): main.toggle_menu(), true, "GoButton"))
	menu_save = btn("Save", func(): main.save_game(false))
	row.add_child(menu_save)
	row.add_child(btn("Settings", func(): open_settings(true)))
	var nb := Button.new()
	nb.focus_mode = Control.FOCUS_NONE
	menu_leave = nb
	var disarm := func():
		new_armed = false
		nb.text = "Leave game" if main.is_net() else "Main menu"
	var leave_cb := func():
		if not new_armed:
			new_armed = true
			nb.text = "Click again to confirm"
			get_tree().create_timer(3.0).timeout.connect(disarm)
			return
		disarm.call()
		if main.net.mode != "client":
			main.save_game(true)
		main.to_title()
	nb.button_down.connect(leave_cb)
	row.add_child(nb)
	var quit_cb := func():
		if main.net.mode != "client":
			main.save_game(true)
		get_tree().quit()
	row.add_child(btn("Quit", quit_cb))
	v.add_child(row)
	menu_note = lbl("", 14, C_MUTED, F.r)
	menu_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_note.custom_minimum_size.x = 520
	v.add_child(menu_note)
	menu_ov.visible = false

# ---- player list
func _build_players() -> void:
	players_panel = _corner_panel(Control.PRESET_BOTTOM_RIGHT, Vector2(-16, -212), 250)
	players_box = vbox(3)
	players_panel.add_child(players_box)
	players_panel.visible = false

func _addr_row(label: String, addr: String) -> Control:
	var v := vbox(1)
	v.add_child(lbl(label.to_upper(), 10, C_MUTED, F.b))
	var h := hbox(6)
	var a := lbl(addr, 13, C_TEXT, F.m)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(a)
	var copy_cb := func():
		DisplayServer.clipboard_set(addr)
		toast("Copied %s. Send it to your friend." % addr, "good")
	var b := btn("Copy", copy_cb)
	b.add_theme_font_size_override("font_size", 12)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	h.add_child(b)
	v.add_child(h)
	return v

func _note(text: String, tip := "") -> Label:
	var l := lbl(text, 11, C_MUTED, F.r)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if tip != "":
		l.tooltip_text = tip
		l.mouse_filter = Control.MOUSE_FILTER_STOP
	return l

func on_upnp() -> void:
	var n = main.net
	if n.upnp_state == "open":
		toast("Port %d opened automatically. Friends on the internet can join at %s:%d" % [n.host_port, n.public_ip, n.host_port], "good")
	else:
		toast(n.upnp_msg, "")

func _update_players() -> void:
	var on: bool = main.is_net()
	players_panel.visible = on
	if not on:
		return
	var s := sim()
	var rows := []
	for qid in s.players:
		var ping := ""
		if main.net.mode == "host" and qid != pid():
			ping = "%d ms" % main.net.ping_ms(qid)
		elif main.net.mode == "client" and qid == pid():
			ping = "%d ms" % main.net.ping_ms(1)
		rows.append([s.players[qid].get("name", "?") + (" (you)" if qid == pid() else ""), ping, qid == 1])
	var psig := str(rows, main.net.mode, main.net.desyncs, main.net.upnp_state, main.net.public_ip)
	if psig == players_sig:
		return
	players_sig = psig
	for ch in players_box.get_children():
		ch.queue_free()
	players_box.add_child(cap("Players · %s" % ("hosting" if main.net.mode == "host" else "connected")))
	for rw in rows:
		var h := hbox(6)
		var n := lbl(("★ " if rw[2] else "• ") + rw[0], 13, C_TEXT, F.s)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.clip_text = true
		h.add_child(n)
		h.add_child(lbl(rw[1], 12, C_MUTED, F.m))
		players_box.add_child(h)
	if main.net.mode == "host":
		var port: int = main.net.host_port
		players_box.add_child(HSeparator.new())
		var ips: Array = main.net.lan_ips()
		if ips.size():
			players_box.add_child(_addr_row("Same network", "%s:%d" % [ips[0], port]))
		match main.net.upnp_state:
			"working":
				players_box.add_child(_note("Opening the port on your router..."))
			"open":
				players_box.add_child(_addr_row("Internet", "%s:%d" % [main.net.public_ip, port]))
			"failed":
				players_box.add_child(_note("Internet: not reachable automatically. Hover for details.", main.net.upnp_msg))
	if main.net.desyncs > 0:
		players_box.add_child(lbl("Resynced %d time(s)" % main.net.desyncs, 11, C_MUTED, F.r))

func _build_victory() -> void:
	var r := _overlay()
	victory_ov = r[0]
	var v: VBoxContainer = r[1]
	v.add_child(_brand("ELEVATOR", "LAUNCHED", 64))
	victory_lbl = lbl("", 18, Color("#d4ccb9"), F.r)
	victory_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	victory_lbl.custom_minimum_size.x = 520
	v.add_child(victory_lbl)
	var row := hbox(10)
	row.add_child(btn("Keep building", func(): main.begin(), true, "GoButton"))
	row.add_child(btn("Main menu", func(): main.to_title()))
	v.add_child(row)
	victory_ov.visible = false

# ------------------------------------------------------------------ overlay state
func show_play() -> void:
	setup_ov.visible = false
	join_ov.visible = false
	title_ov.visible = false
	menu_ov.visible = false
	victory_ov.visible = false
	hud_root.visible = true

func show_menu(on: bool) -> void:
	menu_ov.visible = on
	hud_root.visible = not on
	if on:
		var mode: String = main.net.mode
		menu_save.disabled = mode == "client"
		new_armed = false
		menu_leave.text = "Leave game" if mode != "offline" else "Main menu"
		if mode == "offline":
			menu_note.text = "Saving to \"%s\". The game also autosaves every minute and keeps the last three autosaves." % main.world_name
		elif mode == "host":
			menu_note.text = "The world keeps running while this menu is open; it's multiplayer. Leaving ends the session for everyone. The game saves every minute."
		else:
			menu_note.text = "The world keeps running while this menu is open. Only the host can save."
		close_panel()

func show_victory() -> void:
	var s := sim()
	var m := s.tick / 3600
	victory_lbl.text = "The orbital tether is complete after %dh %dm of game time, with %d structures on the ground and %d alternate recipes in use." % [m / 60, m % 60, s.ents.size(), s.alts.size()]
	victory_ov.visible = true
	hud_root.visible = false
	close_panel()

func toast(msg: String, kind := "") -> void:
	var p := PanelContainer.new()
	var s := _sb(Color(0.118, 0.114, 0.118, 0.94), Color.BLACK, 1, 8)
	s.border_width_left = 4
	s.border_color = {"good": C_OK, "bad": C_BAD, "cy": C_CYAN}.get(kind, C_AMBER)
	p.add_theme_stylebox_override("panel", s)
	var l := lbl(msg, 15, C_TEXT, F.s)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 420
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.add_child(p)
	toasts.move_child(p, 0)
	while toasts.get_child_count() > 4:
		var last := toasts.get_child(toasts.get_child_count() - 1)
		toasts.remove_child(last)
		last.queue_free()
	var tw := p.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.25)
	tw.tween_callback(p.queue_free)

# ------------------------------------------------------------------ per frame
func frame(delta: float) -> void:
	root.size = root.get_viewport_rect().size / ui_scale
	var vp := root.size
	_frame_extra(delta)
	toasts.position = Vector2((vp.x - toasts.size.x) / 2, 14)
	if win.visible:
		win_scroll.custom_minimum_size.y = minf(win_body.get_combined_minimum_size().y, vp.y - 160)
		win.reset_size()
		win.position = ((vp - win.get_combined_minimum_size()) / 2).floor()
	if preview_due > 0:
		preview_due -= delta
		if preview_due <= 0:
			_regen_preview()
	if not main.started:
		return
	var me: Dictionary = sim().players.get(pid(), {})
	death_ov.visible = not me.is_empty() and me.dead > 0
	ui_t += delta
	if ui_t > 0.2 and not me.is_empty():
		ui_t = 0
		_update_hud()
		_update_players()
		_update_hints()
		refresh_panel()
	mm_t += delta
	if mm_t > (0.25 if pings.size() else 0.5):
		mm_t = 0
		_update_minimap()

func _update_hud() -> void:
	var s := sim()
	if not s.players.has(pid()):
		return
	var p: Dictionary = s.players[pid()]
	# milestone tracker
	var parts := []
	var ready := true
	var rows := []
	if s.milestone < Data.MILESTONES.size():
		var ms: Dictionary = Data.MILESTONES[s.milestone]
		var mreq := s.ms_req(s.milestone)
		for k in mreq:
			var hv := s.have(pid(), k)
			if hv < mreq[k]:
				ready = false
			rows.append([k, mini(hv, mreq[k]), mreq[k]])
		parts = ["MILESTONE %d OF %d" % [s.milestone + 1, Data.MILESTONES.size()], ms.n]
	elif s.elevator.phase < Data.PHASES.size():
		var ph: Dictionary = Data.PHASES[s.elevator.phase]
		var preq := s.phase_req(s.elevator.phase)
		for k in preq:
			rows.append([k, s.elevator.del.get(k, 0), preq[k]])
		parts = ["SPACE ELEVATOR", ph.n]
		ready = false
	else:
		parts = ["SPACE ELEVATOR", "Launched"]
		ready = false
	var tsig := str(parts, rows, ready, s.elev_ent != null)
	if tsig != track_sig:
		track_sig = tsig
		for ch in tracker_box.get_children():
			ch.queue_free()
		tracker_box.add_child(cap(parts[0]))
		tracker_box.add_child(lbl(parts[1], 17, C_TITLE, F.b))
		if parts[0] == "SPACE ELEVATOR" and s.elev_ent == null and rows.size():
			var hint := lbl("Build the Space Elevator and belt project parts into it.", 13, C_MUTED, F.r)
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tracker_box.add_child(hint)
		for r in rows:
			var h := hbox(6)
			h.add_child(icon_rect(r[0], 22))
			var n := lbl(Data.item_name(r[0]), 14)
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(n)
			h.add_child(lbl("%d/%d" % [r[1], r[2]], 12, C_TEXT, F.m))
			tracker_box.add_child(h)
			tracker_box.add_child(bar(float(r[1]) / r[2], "OkBar" if r[1] >= r[2] else "", 5))
		if parts[0].begins_with("MILESTONE"):
			var h2 := hbox(6)
			var hl := lbl("Counts the HUB and your pockets", 12, C_MUTED, F.r)
			hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h2.add_child(hl)
			h2.add_child(btn("Submit", func(): cmd({"t": "submit_ms"}), ready, "GoButton" if ready else ""))
			tracker_box.add_child(h2)
	# power
	var hov: Sim.Ent = main.hover_ent()
	var best = null
	if hov != null and hov.net and s.nets.has(hov.net):
		best = s.nets[hov.net]
	if best == null:
		for id in s.nets:
			if best == null or s.nets[id].cap > best.cap:
				best = s.nets[id]
	var capk: int = best.cap if best else 0
	var demk: int = best.dem if best else 0
	power_bar.theme_type_variation = "OverBar" if demk > capk else "PowerBar"
	power_bar.value = 1.0 if demk > capk else (float(demk) / capk if capk > 0 else 0.0)
	var on_gens := 0
	for g in s.gens:
		if g.on:
			on_gens += 1
	power_lbl.text = "%s / %s MW   %s" % [fmt(demk / 1000.0), fmt(capk / 1000.0), ("overloaded %d%%" % (capk * 100 / demk)) if demk > capk else "%d generators" % on_gens]
	power_lbl2.text = "hovered" if (hov != null and hov.net) else "largest"
	# hover
	var hv := _hover_text(hov)
	hover_panel.visible = hv != ""
	if hv != "" and hover_rt.text != hv:
		hover_rt.text = hv
	# status
	hp_lbl.text = str(ceili(p.hp / 1000.0))
	hp_bar.value = p.hp / 100000.0
	var qsig := str(p.craft_q.slice(0, 8), p.craft_t / 6)
	if qsig != cq_sig:
		cq_sig = qsig
		for ch in craftq.get_children():
			ch.queue_free()
		for i in mini(8, p.craft_q.size()):
			var k: String = p.craft_q[i]
			var b := slot(Data.icon(Data.recipe_icon(k)), "", func(): cmd({"t": "cancel_craft", "i": i}), "Cancel " + Data.RECIPES[k]["n"], "SlotButton", 34)
			if i == 0:
				var pr := bar(float(p.craft_t) / (int(Data.RECIPES[k]["t"]) * 24), "OkBar", 3)
				pr.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
				pr.offset_top = -3
				b.add_child(pr)
			craftq.add_child(b)
	var hint := ""
	if main.hand != "":
		hint = "Holding [b]%s[/b] · R rotate · Q clear\n[color=#a59f90]%s[/color]" % [Data.BUILD[main.hand]["n"], Data.cost_str(Data.BUILD[main.hand]["cost"])]
	else:
		hint = "[color=#a59f90]E inventory · hold F to grab from belts · click a building to open it · hold right click to remove[/color]"
	if hint_rt.text != hint:
		hint_rt.text = hint
	for i in quick_btns.size():
		var t: String = Data.QUICK[i]
		var b: Button = quick_btns[i]
		var unlocked := s.unlock_b.has(t)
		b.theme_type_variation = "SlotSel" if main.hand == t else ("SlotButton" if unlocked else "SlotEmpty")
		var ic: TextureRect = b.get_child(0)
		ic.modulate = Color(1, 1, 1, 0.15) if not unlocked else (Color(1, 1, 1, 1) if s.afford(pid(), Data.BUILD[t]["cost"]) else Color(1, 1, 1, 0.55))

func _hover_text(e: Sim.Ent) -> String:
	var s := sim()
	if not main.started or main.paused:
		return ""
	if e != null:
		var d: Dictionary = Data.BUILD[e.type]
		var t := "[b][color=#ffe3b3]%s[/color][/b]\n" % d.n
		if Data.is_belt(e.type):
			t += "[color=#a59f90]Throughput[/color] %d/min\n[color=#a59f90]Carrying[/color] %d" % [d.speed * 60 * 60 / Data.BELT_SP, e.items.size()]
		elif Data.is_miner(e.type):
			var nd: Dictionary = World.nodes[e.node]
			t += "%s\n[color=#a59f90]%s %s[/color]\n%s/min · %s MW · %d%%" % [_st(e.st), Data.PUR_NAME[nd.pur], Data.item_name(nd.res), fmt(3600.0 / s.miner_required(e) * 100 * e.clock / 100.0), fmt(s.power_kw(e) / 1000.0), e.clock]
		elif Data.is_machine(e.type):
			t += _st(e.st) + "\n"
			if Data.RECIPES.has(e.recipe):
				t += "[color=#a59f90]%s[/color]\n%s\n" % [Data.RECIPES[e.recipe]["n"], rcp(e.recipe, e.clock)]
			else:
				t += "[color=#a59f90]Click to choose a recipe[/color]\n"
			t += "%s MW · %d%% clock" % [fmt(s.power_kw(e) / 1000.0), e.clock]
		elif e.type == "coalgen":
			t += "[color=#a59f90]Coal[/color] %d/50\n[color=#a59f90]%s%s[/color]" % [e.fuel, "Online" if e.on else "Out of coal", "" if e.net else " · no pole in range"]
		elif e.type == "pole":
			if s.nets.has(e.net):
				t += "%s / %s MW" % [fmt(s.nets[e.net].dem / 1000.0), fmt(s.nets[e.net].cap / 1000.0)]
			else:
				t += "[color=#a59f90]No generator on this grid[/color]"
		elif e.type == "crate":
			var n := 0
			for k in e.store:
				n += e.store[k]
			t += "%d/800 items\n[color=#a59f90]Belts pointing away from any side pull from it[/color]" % n
		elif e.type == "hub":
			t += "[color=#a59f90]Accepts any item from belts. Click for milestones, research and storage.[/color]"
		elif e.type == "elevator":
			t += "[color=#a59f90]Belt project parts in. Click for the current phase.[/color]"
		elif e.type == "tunnel":
			if e.partner == 0:
				t += "[color=#e2503b]Not connected.[/color] [color=#a59f90]Place another underground belt up to 5 tiles ahead, facing the same way.[/color]"
			elif e.role == 1:
				t += "[color=#a59f90]Entrance · carrying %d item(s) underground[/color]" % e.tq.size()
			else:
				t += "[color=#a59f90]Exit · items come out the front[/color]"
		else:
			t += "[color=#a59f90]%s[/color]" % ("Sends items forward, left and right in turn" if e.type == "splitter" else "Joins three inputs into one")
		return t
	var mt: Vector2i = main.mouse_tile()
	var ni := World.node_at(mt.x, mt.y)
	if ni >= 0:
		var nd: Dictionary = World.nodes[ni]
		return "[b][color=#ffe3b3]%s %s node[/color][/b]\n[color=#a59f90]Miner Mk.1[/color] %s/min · [color=#a59f90]Mk.2[/color] %s/min\n[color=#a59f90]Hold left click nearby to mine by hand[/color]" % [Data.PUR_NAME[nd.pur], Data.item_name(nd.res), fmt(30 * nd.pur / 100.0), fmt(60 * nd.pur / 100.0)]
	var mw: Vector2 = main.mouse_world() / 32.0 * 1000.0
	for n in s.nests:
		if n.alive and Vector2(n.x, n.y).distance_to(mw) < 1200:
			return "[b][color=#ffe3b3]Scuttler Burrow[/color][/b]\n[color=#a59f90]Walk close and your zapper will fire. Destroying it yields a Power Shard.[/color]"
	for pd in s.pods:
		if not pd.taken and Vector2(pd.x, pd.y).distance_to(mw) < 1200:
			return "[b][color=#ffe3b3]Crash Pod[/color][/b]\n[color=#a59f90]Walk into it to salvage a Data Drive and a Power Shard.[/color]"
	return ""

func _st(st: String) -> String:
	var names := {"work": "Working", "input": "Waiting for input", "full": "Output full", "nopower": "No power", "norecipe": "No recipe", "idle": "Idle"}
	var cols := {"work": "#6cbf4a", "input": "#e8c33a", "full": "#e8c33a", "nopower": "#e2503b", "norecipe": "#e2503b", "idle": "#e8c33a"}
	return "[color=%s][b]%s[/b][/color]" % [cols.get(st, "#a59f90"), names.get(st, st)]

func _update_minimap() -> void:
	var s := sim()
	var img := mm_base.duplicate()
	for id in s.ents:
		var e: Sim.Ent = s.ents[id]
		var col := Color("#c9a84a") if Data.is_belt(e.type) else (Color("#f5a524") if e.type == "hub" else (Color("#7a5a34") if e.type == "pole" else Color("#8fa6b8")))
		img.fill_rect(Rect2i(e.x, e.y, e.n, e.n), col)
	for n in s.nests:
		if n.alive:
			img.fill_rect(Rect2i(n.x / 1000 - 1, n.y / 1000 - 1, 3, 3), Color("#ff3b2a"))
	for pd in s.pods:
		if not pd.taken:
			img.fill_rect(Rect2i(pd.x / 1000 - 1, pd.y / 1000 - 1, 3, 3), Color("#d79bff"))
	var vsz: Vector2 = main.view.get_viewport_rect().size / main.view.cam.zoom / 32.0
	var c: Vector2 = main.view.cam.get_screen_center_position() / 32.0
	var r := Rect2i(int(c.x - vsz.x / 2), int(c.y - vsz.y / 2), int(vsz.x), int(vsz.y))
	for x in range(r.position.x, r.end.x):
		for y in [r.position.y, r.end.y]:
			if x >= 0 and y >= 0 and x < Data.MW and y < Data.MH:
				img.set_pixel(x, y, Color(1, 1, 1, 0.8))
	for y in range(r.position.y, r.end.y):
		for x in [r.position.x, r.end.x]:
			if x >= 0 and y >= 0 and x < Data.MW and y < Data.MH:
				img.set_pixel(x, y, Color(1, 1, 1, 0.8))
	for qid in s.players:
		var q: Dictionary = s.players[qid]
		img.fill_rect(Rect2i(q.x / 1000 - 1, q.y / 1000 - 1, 3, 3), Color.WHITE if qid == pid() else C_CYAN)
	var blink := (Time.get_ticks_msec() / 250) % 2 == 0
	for pg in pings:
		if blink:
			for d in [Vector2i(-2, -2), Vector2i(2, -2), Vector2i(-2, 2), Vector2i(2, 2), Vector2i(0, -3), Vector2i(0, 3), Vector2i(-3, 0), Vector2i(3, 0)]:
				var px: int = pg.x + d.x
				var py: int = pg.y + d.y
				if px >= 0 and py >= 0 and px < Data.MW and py < Data.MH:
					img.set_pixel(px, py, C_CYAN)
	mm_tex.update(img)

# ------------------------------------------------------------------ windows
func open_panel(kind: String, id: int) -> void:
	panel = {"kind": kind, "id": id}
	main.hand = ""
	sig = ""
	m_dsig = ""
	win.visible = true
	refresh_panel()

func close_panel() -> void:
	panel = {}
	if win:
		win.visible = false

func panel_kind() -> String:
	return panel.get("kind", "")

func _clear_body() -> void:
	for ch in win_body.get_children():
		win_body.remove_child(ch)
		ch.queue_free()

func refresh_panel() -> void:
	if panel.is_empty():
		return
	var s := sim()
	var kind: String = panel.kind
	var e: Sim.Ent = null
	if kind != "inv":
		e = s.ents.get(panel.id, null)
		if e == null:
			close_panel()
			return
	match kind:
		"machine": _machine_panel(e)
		"gen": _simple_panel(str(e.fuel, e.energy / 24000, e.net, s.nets.get(e.net, {}), s.players[pid()].inv.get("coal", 0)), "Coal Generator", func(): _gen_body(e))
		"crate": _simple_panel(str(e.store), "Storage Crate", func(): _crate_body(e))
		"logi": _simple_panel(str(e.buf.size()), Data.BUILD[e.type]["n"], func(): _logi_body(e))
		"hub": _simple_panel(str(hub_tab, s.hub, s.milestone, s.research, s.alts, s.players[pid()].inv), "The HUB", func(): _hub_body())
		"elevator": _simple_panel(str(s.elevator, s.players[pid()].inv), "Space Elevator", func(): _elev_body())
		"inv": _simple_panel(str(s.players[pid()].inv, s.unlock_r.size()), "Inventory", func(): _inv_body())

func _simple_panel(new_sig: String, title: String, build: Callable) -> void:
	if new_sig == sig:
		return
	sig = new_sig
	win_title.text = title
	var keep := win_scroll.scroll_vertical
	_clear_body()
	build.call()
	win_scroll.set_deferred("scroll_vertical", keep)

func _machine_panel(e: Sim.Ent) -> void:
	var s := sim()
	var full_sig := str(e.id, e.recipe, e.shards, s.unlock_r.size())
	if full_sig != sig:
		sig = full_sig
		m_dsig = ""
		win_title.text = Data.BUILD[e.type]["n"]
		_clear_body()
		if Data.is_miner(e.type):
			var nd: Dictionary = World.nodes[e.node]
			var r := inset("Resource node")
			var h := hbox(10)
			h.add_child(icon_rect(nd.res, 32))
			h.add_child(rt("[b]%s %s[/b]\n[color=#a59f90]Base rate %s/min. Nodes never run out.[/color]" % [Data.PUR_NAME[nd.pur], Data.item_name(nd.res), fmt(3600.0 / s.miner_required(e) * 100 / 100.0)], 500))
			r[1].add_child(h)
			win_body.add_child(r[0])
		else:
			var r := inset("Recipe")
			var g := GridContainer.new()
			g.columns = 3
			g.add_theme_constant_override("h_separation", 3)
			g.add_theme_constant_override("v_separation", 3)
			for k in s.recipes_for(e.type):
				var b := Button.new()
				b.theme_type_variation = "RecipeOn" if e.recipe == k else "RecipeButton"
				b.focus_mode = Control.FOCUS_NONE
				b.custom_minimum_size = Vector2(232, 40)
				b.icon = Data.icon(Data.recipe_icon(k))
				b.expand_icon = false
				b.add_theme_constant_override("icon_max_width", 26)
				b.text = Data.RECIPES[k]["n"] + ("  · ALT" if Data.RECIPES[k].get("alt", false) else "")
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				b.button_down.connect(func(): cmd({"t": "recipe", "id": e.id, "k": k}))
				g.add_child(b)
			r[1].add_child(g)
			win_body.add_child(r[0])
		m_dyn = vbox(8)
		var di := inset()
		di[1].add_child(m_dyn)
		win_body.add_child(di[0])
		var ck := inset("Clock speed · overclocking")
		var row := hbox(12)
		var col := vbox(4)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		m_clock = HSlider.new()
		m_clock.min_value = 1
		m_clock.max_value = 100 + 50 * e.shards
		m_clock.step = 1
		m_clock.focus_mode = Control.FOCUS_NONE
		m_clock.set_value_no_signal(e.clock)
		m_clock.value_changed.connect(func(v): cmd({"t": "clock", "id": e.id, "v": int(v)}); m_clock_lbl.text = "%d%%" % int(v))
		col.add_child(m_clock)
		var lr := hbox()
		m_clock_lbl = lbl("%d%%" % e.clock, 13, C_TEXT, F.m)
		m_clock_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lr.add_child(m_clock_lbl)
		lr.add_child(lbl("max %d%%" % (100 + 50 * e.shards), 13, C_MUTED, F.m))
		col.add_child(lr)
		row.add_child(col)
		m_shards = hbox(3)
		for i in 3:
			if i < e.shards:
				m_shards.add_child(slot(Data.icon("power_shard"), "", func(): cmd({"t": "shard_rem", "id": e.id}), "Remove Power Shard"))
			else:
				var add_cb := func():
					if s.inv_count(pid(), "power_shard") > 0:
						cmd({"t": "shard_add", "id": e.id})
					else:
						toast("No Power Shards. Destroy burrows or salvage crash pods.", "bad")
				m_shards.add_child(slot(null, "+" if s.inv_count(pid(), "power_shard") > 0 else "", add_cb, "Insert a Power Shard (%d carried)" % s.inv_count(pid(), "power_shard"), "SlotEmpty"))
		row.add_child(m_shards)
		ck[1].add_child(row)
		var note := lbl("Underclock to save power. Each Power Shard raises the limit by 50%. Power use grows faster than speed.", 13, C_MUTED, F.r)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ck[1].add_child(note)
		win_body.add_child(ck[0])
	if not m_clock.has_focus() and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		m_clock.set_value_no_signal(e.clock)
		m_clock_lbl.text = "%d%%" % e.clock
	var dsig := str(e.st, e.inp, e.out, e.prog * 50 / maxi(1, _req(e)), e.clock, e.net)
	if dsig == m_dsig:
		return
	m_dsig = dsig
	for ch in m_dyn.get_children():
		ch.queue_free()
	var top := hbox()
	top.add_child(pill(e.st))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(lbl("%s MW%s" % [fmt(s.power_kw(e) / 1000.0), "" if e.net else " · no pole in range"], 13, C_TEXT, F.m))
	m_dyn.add_child(top)
	m_dyn.add_child(bar(float(e.prog) / maxi(1, _req(e)), "", 8))
	if Data.is_miner(e.type):
		var res: String = World.nodes[e.node].res
		var h := hbox()
		h.add_child(item_slot(res, e.out.get(res, 0)))
		h.add_child(lbl("%s/min" % fmt(3600.0 / s.miner_required(e) * 100 * e.clock / 100.0), 13, C_TEXT, F.m))
		h.add_child(btn("Take", func(): cmd({"t": "take_out", "id": e.id}), e.out.get(res, 0) > 0))
		m_dyn.add_child(h)
	elif Data.RECIPES.has(e.recipe):
		var R: Dictionary = Data.RECIPES[e.recipe]
		var cols := HBoxContainer.new()
		cols.add_theme_constant_override("separation", 24)
		for side in [["Input", R["in"], e.inp, "Insert from inventory", "fill_in"], ["Output", R["out"], e.out, "Take output", "take_out"]]:
			var v := vbox(6)
			v.add_child(cap(side[0]))
			var g := hbox(2)
			for k in side[1]:
				g.add_child(item_slot(k, side[2].get(k, 0), null, " — %d per craft" % side[1][k]))
			v.add_child(g)
			var act: String = side[4]
			v.add_child(btn(side[3], func(): cmd({"t": act, "id": e.id})))
			cols.add_child(v)
		m_dyn.add_child(cols)
		m_dyn.add_child(rt(rcp(e.recipe, e.clock), 700))
	else:
		m_dyn.add_child(rt("[color=#a59f90]Choose a recipe. Belt ingredients into any side; output leaves through the arrow.[/color]", 700))

func _req(e: Sim.Ent) -> int:
	if Data.is_miner(e.type):
		return sim().miner_required(e)
	if Data.RECIPES.has(e.recipe):
		return int(Data.RECIPES[e.recipe]["t"]) * 6000
	return 1

func _gen_body(e: Sim.Ent) -> void:
	var s := sim()
	var r := inset("Fuel")
	var h := hbox(10)
	h.add_child(item_slot("coal", e.fuel))
	var v := vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(bar(e.energy / 240000.0, "", 8))
	var n := lbl("Burns 15 coal/min at full load and throttles down with demand. Belt coal into any side.", 13, C_MUTED, F.r)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(n)
	h.add_child(v)
	var have := s.inv_count(pid(), "coal")
	h.add_child(btn("Add coal (%d)" % have, func(): cmd({"t": "fuel", "id": e.id}), have > 0))
	r[1].add_child(h)
	win_body.add_child(r[0])
	var g := inset("Grid")
	if e.net and s.nets.has(e.net):
		g[1].add_child(lbl("%s MW used of %s MW available" % [fmt(s.nets[e.net].dem / 1000.0), fmt(s.nets[e.net].cap / 1000.0)], 13, C_TEXT, F.m))
	else:
		g[1].add_child(lbl("Not connected. Place a Power Pole within 3 tiles.", 14, C_MUTED, F.r))
	win_body.add_child(g[0])

func _crate_body(e: Sim.Ent) -> void:
	var n := 0
	for k in e.store:
		n += e.store[k]
	var r := inset("Contents · %d/800" % n)
	var g := HFlowContainer.new()
	g.add_theme_constant_override("h_separation", 2)
	g.add_theme_constant_override("v_separation", 2)
	for k in e.store:
		g.add_child(item_slot(k, e.store[k], func(): cmd({"t": "crate_take", "id": e.id, "k": k}), " — click to take"))
	if e.store.is_empty():
		g.add_child(lbl("Empty. Point a belt into it to fill it.", 14, C_MUTED, F.r))
	r[1].add_child(g)
	win_body.add_child(r[0])
	var row := hbox(10)
	row.add_child(btn("Take everything", func(): cmd({"t": "crate_take", "id": e.id, "k": ""}), n > 0))
	var note := lbl("Belts pointing into the crate fill it. Belts pointing away from any side pull from it.", 13, C_MUTED, F.r)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(note)
	win_body.add_child(row)

func _logi_body(e: Sim.Ent) -> void:
	var r := inset()
	var t := "Splits one input three ways: forward, left and right, in turn. Unconnected outputs are skipped." if e.type == "splitter" else "Takes items from the back and both sides and sends them forward."
	r[1].add_child(rt(t + "\n[color=#a59f90]Holding %d item(s). Press R while hovering to rotate.[/color]" % e.buf.size(), 700))
	win_body.add_child(r[0])

func _hub_body() -> void:
	var s := sim()
	var tabs := hbox(2)
	for t in [["ms", "Milestones"], ["rs", "Research"], ["st", "Storage"]]:
		var key: String = t[0]
		tabs.add_child(btn(t[1], func(): hub_tab = key; sig = ""; refresh_panel(), true, "TabOn" if hub_tab == key else ""))
	win_body.add_child(tabs)
	var r := inset()
	var v: VBoxContainer = r[1]
	win_body.add_child(r[0])
	if hub_tab == "ms":
		for i in Data.MILESTONES.size():
			var m: Dictionary = Data.MILESTONES[i]
			var done := i < s.milestone
			var cur := i == s.milestone
			var ready := cur
			var row := hbox(12)
			row.modulate = Color(1, 1, 1, 0.5) if not done and not cur else Color.WHITE
			var num := lbl(str(i + 1), 22, C_OK if done else (C_AMBER if cur else C_MUTED), F.k)
			num.custom_minimum_size.x = 28
			num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			row.add_child(num)
			var col := vbox(4)
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.add_child(lbl(m.n, 16, C_TITLE, F.b))
			var req := ""
			var mreq := s.ms_req(i)
			for k in mreq:
				var hv := s.have(pid(), k)
				if hv < mreq[k]:
					ready = false
				req += "%s %d/%d    " % [ii(k), mreq[k] if done else mini(hv, mreq[k]), mreq[k]]
			col.add_child(rt(req, 600))
			var un := "[color=#a59f90]Unlocks:[/color] "
			var bits := []
			for b in m.ub:
				bits.append("[img=18x18]res://assets/icons/%s.png[/img] %s" % [b, Data.BUILD[b]["n"]])
			for rr in m.ur:
				bits.append("%s %s" % [ii(Data.recipe_icon(rr), 18), Data.RECIPES[rr]["n"]])
			if m.get("research", false):
				bits.append("%s Data Drive analysis" % ii("data_drive", 18))
			col.add_child(rt(un + "   ".join(bits), 600))
			if cur:
				col.add_child(btn("Submit milestone", func(): cmd({"t": "submit_ms"}), ready, "GoButton" if ready else ""))
			row.add_child(col)
			v.add_child(row)
			v.add_child(HSeparator.new())
		v.add_child(lbl("After the last milestone, the Space Elevator takes over as your goal.", 13, C_MUTED, F.r))
	elif hub_tab == "rs":
		if s.milestone < 2:
			v.add_child(rt("Complete [b]Field Logistics[/b] to analyse Data Drives. You find drives in crash pods; follow the purple marks on the minimap.", 700))
		else:
			if s.research.offer.size():
				v.add_child(cap("Choose one alternate recipe"))
				var h := hbox(10)
				for k in s.research.offer:
					var R: Dictionary = Data.RECIPES[k]
					var c := PanelContainer.new()
					c.theme_type_variation = "Card"
					c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					var cv := vbox(8)
					c.add_child(cv)
					cv.add_child(lbl(R.n, 16, Color("#d8a8ff"), F.b))
					cv.add_child(lbl("%s · %ss per craft" % [Data.MNAME[R.m], R.t], 13, C_MUTED, F.r))
					var ins := []
					for i in R["in"]:
						ins.append("%d× %s" % [R["in"][i], ii(i)])
					var outs := []
					for i in R["out"]:
						outs.append("%d× %s" % [R["out"][i], ii(i)])
					cv.add_child(rt(" + ".join(ins) + "  →  " + " + ".join(outs), 320))
					var key: String = k
					cv.add_child(btn("Choose", func(): cmd({"t": "pick_alt", "k": key}), true, "GoButton"))
					h.add_child(c)
				v.add_child(h)
			elif s.alts.size() >= Data.ALTS.size():
				v.add_child(lbl("Every alternate recipe is unlocked.", 15))
			else:
				var c := s.research_cost()
				var can := true
				var line := ""
				for k in c:
					if s.have(pid(), k) < c[k]:
						can = false
					line += "%s %d/%d %s    " % [ii(k), mini(s.have(pid(), k), c[k]), c[k], Data.item_name(k)]
				v.add_child(cap("Analyse a Data Drive"))
				v.add_child(rt(line, 700))
				v.add_child(btn("Analyse", func(): cmd({"t": "research"}), can, "GoButton" if can else ""))
				v.add_child(lbl("Analysis offers two alternate recipes. Pick one; the other goes back into the pool.", 13, C_MUTED, F.r))
			if s.alts.size():
				var t := "[color=#a59f90]Unlocked alternates:[/color] "
				var bits := []
				for k in s.alts:
					bits.append("%s %s · %s" % [ii(Data.recipe_icon(k), 18), Data.RECIPES[k]["n"], Data.MNAME[Data.RECIPES[k]["m"]]])
				v.add_child(rt(t + "   ".join(bits), 700))
	else:
		v.add_child(cap("Stored in the HUB"))
		var g := HFlowContainer.new()
		g.add_theme_constant_override("h_separation", 2)
		g.add_theme_constant_override("v_separation", 2)
		for k in Data.ITEM_KEYS:
			if s.hub.get(k, 0) > 0:
				g.add_child(item_slot(k, s.hub[k], func(): cmd({"t": "hub_take", "k": k}), " — click to take all"))
		if g.get_child_count() == 0:
			g.add_child(lbl("Nothing yet. Belt items into any side of the HUB.", 14, C_MUTED, F.r))
		v.add_child(g)
		var row := hbox(10)
		row.add_child(btn("Deposit my inventory", func(): cmd({"t": "hub_dep"})))
		row.add_child(lbl("Keeps Power Shards and Data Drives in your pockets.", 13, C_MUTED, F.r))
		v.add_child(row)

func _elev_body() -> void:
	var s := sim()
	var r := inset()
	var v: VBoxContainer = r[1]
	win_body.add_child(r[0])
	if s.elevator.phase >= Data.PHASES.size():
		v.add_child(lbl("All phases launched. The tether is up.", 15))
		return
	var ph: Dictionary = Data.PHASES[s.elevator.phase]
	v.add_child(cap("%s · %d of %d" % [ph.n, s.elevator.phase + 1, Data.PHASES.size()]))
	var full := true
	var preq := s.phase_req(s.elevator.phase)
	for k in preq:
		var d: int = s.elevator.del.get(k, 0)
		if d < preq[k]:
			full = false
		var h := hbox(6)
		h.add_child(icon_rect(k))
		var n := lbl(Data.item_name(k), 14)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		h.add_child(lbl("%d/%d" % [d, preq[k]], 12, C_TEXT, F.m))
		v.add_child(h)
		v.add_child(bar(float(d) / preq[k], "OkBar" if d >= preq[k] else "", 5))
	var row := hbox(10)
	row.add_child(btn("Deliver from inventory", func(): cmd({"t": "elev_dep"})))
	row.add_child(btn("Launch phase", func(): cmd({"t": "elev_launch"}), full, "GoButton" if full else ""))
	v.add_child(row)

func _inv_body() -> void:
	var s := sim()
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	var a := inset("Carrying")
	a[0].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var g := HFlowContainer.new()
	g.add_theme_constant_override("h_separation", 2)
	g.add_theme_constant_override("v_separation", 2)
	var inv: Dictionary = s.players[pid()].inv
	for k in Data.ITEM_KEYS:
		if inv.get(k, 0) > 0:
			g.add_child(item_slot(k, inv[k]))
	if g.get_child_count() == 0:
		g.add_child(lbl("Empty pockets.", 14, C_MUTED, F.r))
	a[1].add_child(g)
	cols.add_child(a[0])
	var b := inset("Hand crafting")
	b[0].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in s.unlock_r:
		var R: Dictionary = Data.RECIPES[k]
		if R.m != "constructor":
			continue
		var ok := true
		var ins := []
		for i in R["in"]:
			if s.inv_count(pid(), i) < R["in"][i]:
				ok = false
			ins.append("%d %s" % [R["in"][i], Data.item_name(i)])
		var bt := Button.new()
		bt.theme_type_variation = "RecipeButton"
		bt.focus_mode = Control.FOCUS_NONE
		bt.icon = Data.icon(Data.recipe_icon(k))
		bt.add_theme_constant_override("icon_max_width", 26)
		bt.alignment = HORIZONTAL_ALIGNMENT_LEFT
		bt.text = "%s   %s → %d" % [R.n, ", ".join(ins), R["out"].values()[0]]
		bt.tooltip_text = "Shift-click to queue five"
		bt.modulate = Color.WHITE if ok else Color(1, 1, 1, 0.5)
		bt.button_down.connect(func(): cmd({"t": "craft", "k": k, "n": 5 if Input.is_key_pressed(KEY_SHIFT) else 1}))
		b[1].add_child(bt)
	var note := lbl("Hand crafting is slow and uses only Constructor recipes.", 13, C_MUTED, F.r)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b[1].add_child(note)
	cols.add_child(b[0])
	win_body.add_child(cols)


# ================================================================== Phase 1 UI
func set_ui_scale(sc: float) -> void:
	ui_scale = clampf(sc, 0.75, 2.0)
	scale = Vector2(ui_scale, ui_scale)
	if root:
		root.size = root.get_viewport_rect().size / ui_scale

func _frame_extra(delta: float) -> void:
	# loading tips rotate
	if load_ov and load_ov.visible:
		load_tip_t += delta
		if load_tip_t > 4.0:
			load_tip_t = 0.0
			load_tip.text = TIPS[randi() % TIPS.size()]
	# chat lines fade unless the chat box is open
	var now := Time.get_ticks_msec()
	for ln in chat_lines:
		var age := (now - int(ln.get_meta("t"))) / 1000.0
		ln.modulate.a = 1.0 if chat_open() else clampf(1.0 - (age - 10.0) / 2.0, 0.0, 1.0)
	pings = pings.filter(func(pg): return now - pg.t < 6000)
	if hint_panel and tracker_panel:
		hint_panel.position = Vector2(16, tracker_panel.position.y + tracker_panel.size.y + 8)

# ---- loading screen
const TIPS := [
	"Tip: Miners only go on resource nodes. Pure nodes give twice the ore of normal ones.",
	"Tip: Hold F near a belt to grab what's on it.",
	"Tip: Shift + right click copies a machine's recipe and clock; Shift + left click pastes it.",
	"Tip: Underground belts carry items under other buildings. Place an entrance, then an exit up to 5 tiles ahead.",
	"Tip: Press G or click the middle mouse button to ping a spot for other players.",
	"Tip: Press Enter to chat in multiplayer.",
	"Tip: Overclock with Power Shards from burrows and crash pods. Power use climbs faster than speed.",
	"Tip: Belts pointing away from any side of a crate pull items out of it.",
	"Tip: Alt toggles the recipe icons drawn over machines.",
]

func _build_loading() -> void:
	load_ov = ColorRect.new()
	load_ov.color = Color(0.078, 0.067, 0.051)
	load_ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	load_ov.mouse_filter = Control.MOUSE_FILTER_STOP
	# only the factory half of the splash, behind the right side of the screen
	var bg := TextureRect.new()
	var at := AtlasTexture.new()
	at.atlas = load("res://assets/splash.png")
	at.region = Rect2(880, 200, 1040, 700)
	bg.texture = at
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bg.anchor_left = 0.45
	bg.anchor_right = 1.0
	bg.anchor_top = 0.0
	bg.anchor_bottom = 1.0
	bg.modulate = Color(1, 1, 1, 0.35)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	load_ov.add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 96)
	load_ov.add_child(m)
	var v := vbox(14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.custom_minimum_size.x = 560
	v.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	m.add_child(v)
	var stripe := TextureRect.new()
	var img := Image.create(320, 10, false, Image.FORMAT_RGBA8)
	for y in 10:
		for x in 320:
			img.set_pixel(x, y, C_AMBER if posmod(x + y, 20) < 10 else Color("#17140f"))
	stripe.texture = ImageTexture.create_from_image(img)
	stripe.custom_minimum_size = Vector2(320, 10)
	stripe.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(stripe)
	load_title = lbl("", 40, Color("#f1e6cf"), F.k)
	v.add_child(load_title)
	load_steps = vbox(7)
	v.add_child(load_steps)
	load_bar = bar(0, "", 10)
	load_bar.custom_minimum_size.x = 520
	load_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(load_bar)
	load_tip = lbl("", 14, C_MUTED, F.r)
	load_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	load_tip.custom_minimum_size.x = 520
	v.add_child(load_tip)
	load_ov.visible = false
	root.add_child(load_ov)

func show_loading(title: String, steps: Array) -> void:
	for o in [title_ov, setup_ov, join_ov, saves_ov, settings_ov, menu_ov, victory_ov]:
		o.visible = false
	close_panel()
	load_title.text = title
	for ch in load_steps.get_children():
		ch.queue_free()
	load_rows.clear()
	for st in steps:
		var h := hbox(10)
		var mark := ColorRect.new()
		mark.custom_minimum_size = Vector2(10, 10)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mark.color = Color("#4a4540")
		h.add_child(mark)
		var l := lbl(st, 16, C_MUTED, F.s)
		h.add_child(l)
		load_steps.add_child(h)
		load_rows.append([mark, l, st])
	load_bar.value = 0
	load_tip.text = TIPS[randi() % TIPS.size()]
	load_tip_t = 0.0
	load_ov.visible = true

## Marks steps before i as done and step i as active, with progress f (0..1) inside it.
func loading_step(i: int, f := 0.0) -> void:
	if load_rows.is_empty():
		return
	for k in load_rows.size():
		var row: Array = load_rows[k]
		if k < i:
			row[0].color = C_OK
			row[1].add_theme_color_override("font_color", C_TEXT)
			row[1].text = row[2]
		elif k == i:
			row[0].color = C_AMBER
			row[1].add_theme_color_override("font_color", C_TITLE)
			row[1].text = row[2] + ("…  %d%%" % int(f * 100) if f > 0.0 and f < 1.0 else "…")
		else:
			row[0].color = Color("#4a4540")
			row[1].add_theme_color_override("font_color", C_MUTED)
			row[1].text = row[2]
	load_bar.value = (i + clampf(f, 0.0, 1.0)) / float(load_rows.size())

func hide_loading() -> void:
	if load_ov:
		load_ov.visible = false

func loading_visible() -> bool:
	return load_ov != null and load_ov.visible

# ---- saved worlds
func _build_saves() -> void:
	var r := _overlay()
	saves_ov = r[0]
	var v: VBoxContainer = r[1]
	v.add_child(lbl("LOAD GAME", 40, Color("#f1e6cf"), F.k))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(640, 420)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	saves_list = vbox(6)
	saves_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(saves_list)
	v.add_child(sc)
	var back := btn("Back", func(): show_title())
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(back)
	saves_ov.visible = false

func open_saves() -> void:
	title_ov.visible = false
	delete_armed = ""
	_fill_saves()
	saves_ov.visible = true

func _fill_saves() -> void:
	for ch in saves_list.get_children():
		ch.queue_free()
	var list: Array = main.list_saves()
	if list.is_empty():
		saves_list.add_child(lbl("No saved worlds yet. Start a new game; it saves every minute.", 15, C_MUTED, F.r))
		return
	for sv in list:
		var p := PanelContainer.new()
		p.theme_type_variation = "Card"
		var h := hbox(12)
		p.add_child(h)
		var info := vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(lbl(str(sv.get("name", "World")), 18, C_TITLE, F.b))
		var when := Time.get_datetime_string_from_unix_time(int(sv.get("saved_at", 0)) + _tz_bias(), true)
		var ms := int(sv.get("milestone", 0))
		var prog := "Space Elevator phase %d" % (int(sv.get("phase", 0)) + 1) if ms >= Data.MILESTONES.size() else "Milestone %d of %d" % [ms + 1, Data.MILESTONES.size()]
		info.add_child(lbl("%s · seed %d · %s" % [when, int(sv.get("seed", 0)), prog], 13, C_MUTED, F.r))
		var path: String = sv.path
		var autos := hbox(4)
		var ai := 1
		for ap in sv.autos:
			var apath: String = ap
			var ab := btn("Autosave %d" % ai, func(): main.load_and_play(apath))
			ab.add_theme_font_size_override("font_size", 12)
			autos.add_child(ab)
			ai += 1
		if sv.autos.size():
			info.add_child(autos)
		h.add_child(info)
		h.add_child(btn("Play", func(): main.load_and_play(path), true, "GoButton"))
		h.add_child(btn("Host", func(): _host_save(path)))
		var sl: String = sv.slot
		h.add_child(btn("Delete" if delete_armed != sl else "Really delete?", func(): _delete(sl)))
		saves_list.add_child(p)

func _tz_bias() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60

func _host_save(path: String) -> void:
	var err: String = main.start_host({}, main.player_name(), int(main.pref("port", Data.DEFAULT_PORT)), "", path)
	if err != "":
		toast(err, "bad")

func _delete(sl: String) -> void:
	if delete_armed != sl:
		delete_armed = sl
		_fill_saves()
		return
	main.delete_slot(sl)
	delete_armed = ""
	_fill_saves()
	toast("World deleted", "")

# ---- settings
func _build_settings() -> void:
	var r := _overlay()
	settings_ov = r[0]
	var v: VBoxContainer = r[1]
	v.add_child(lbl("SETTINGS", 40, Color("#f1e6cf"), F.k))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 10)
	v.add_child(g)
	g.add_child(_fixed(lbl("Player name", 14, C_AMBER, F.b), 150))
	var ne := _line(main.player_name(), 240)
	ne.max_length = 20
	ne.text_changed.connect(func(t): main.set_pref("name", t.strip_edges()))
	g.add_child(ne)
	settings_ov.set_meta("name_edit", ne)
	for vol in [["Master volume", "vol_master", 80], ["Music", "vol_music", 60], ["Sound effects", "vol_sfx", 80]]:
		g.add_child(_fixed(lbl(vol[0], 14, C_AMBER, F.b), 150))
		var row := hbox(8)
		var sl := HSlider.new()
		sl.min_value = 0
		sl.max_value = 100
		sl.step = 1
		sl.custom_minimum_size.x = 240
		sl.focus_mode = Control.FOCUS_NONE
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.value = float(main.pref(vol[1], vol[2]))
		var vl := lbl("%d%%" % int(sl.value), 13, C_TEXT, F.m)
		var key: String = vol[1]
		sl.value_changed.connect(func(x):
			vl.text = "%d%%" % int(x)
			main.set_pref(key, int(x))
			main.audio.apply_volumes())
		row.add_child(sl)
		row.add_child(vl)
		g.add_child(row)
	for tg in [["Fullscreen", "fullscreen", false], ["VSync", "vsync", true], ["Show hints", "hints", true]]:
		g.add_child(_fixed(lbl(tg[0], 14, C_AMBER, F.b), 150))
		var cb := CheckButton.new()
		cb.focus_mode = Control.FOCUS_NONE
		cb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			cb.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		cb.button_pressed = bool(main.pref(tg[1], tg[2]))
		var key2: String = tg[1]
		cb.toggled.connect(func(on):
			main.set_pref(key2, on)
			main.apply_display_settings())
		g.add_child(cb)
	g.add_child(_fixed(lbl("Interface size", 14, C_AMBER, F.b), 150))
	var sr := hbox(2)
	var scale_btns := []
	for sc in [0.9, 1.0, 1.15, 1.3, 1.5]:
		var val: float = sc
		var b := btn("%d%%" % int(round(sc * 100)), func():
			main.set_pref("ui_scale", val)
			main.apply_display_settings()
			_mark_scale(scale_btns))
		b.custom_minimum_size.x = 64
		scale_btns.append(b)
		sr.add_child(b)
	_mark_scale(scale_btns)
	g.add_child(sr)
	var row2 := hbox(10)
	row2.add_child(btn("Back", func(): close_sub_overlay(), true, "GoButton"))
	row2.add_child(btn("Open saves and logs folder", func(): OS.shell_open(ProjectSettings.globalize_path("user://"))))
	v.add_child(row2)
	var note := lbl("A new name shows for others the next time you start, host or join a game. If something goes wrong, send ferrum.log and logs/godot.log from that folder.", 13, C_MUTED, F.r)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 560
	v.add_child(note)
	settings_ov.visible = false

func _mark_scale(btns: Array) -> void:
	var cur := float(main.pref("ui_scale", 1.0))
	var vals := [0.9, 1.0, 1.15, 1.3, 1.5]
	for i in btns.size():
		btns[i].theme_type_variation = "TabOn" if absf(vals[i] - cur) < 0.01 else ""

func open_settings(from_menu: bool) -> void:
	settings_from_menu = from_menu
	var ne: LineEdit = settings_ov.get_meta("name_edit")
	ne.text = main.player_name()
	title_ov.visible = false
	menu_ov.visible = false
	settings_ov.visible = true

func sub_overlay_open() -> bool:
	return (settings_ov and settings_ov.visible) or (saves_ov and saves_ov.visible)

func close_sub_overlay() -> void:
	if settings_ov.visible:
		settings_ov.visible = false
		if settings_from_menu and main.started:
			menu_ov.visible = true
		else:
			show_title()
	elif saves_ov.visible:
		show_title()

# ---- chat
func _build_chat() -> void:
	chat_box = vbox(2)
	chat_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	chat_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	chat_box.offset_left = 16
	chat_box.offset_bottom = -215
	chat_box.custom_minimum_size.x = 420
	chat_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(chat_box)
	chat_edit = _line("", 420, "Say something. Enter to send, Esc to cancel")
	chat_edit.max_length = 200
	chat_edit.visible = false
	chat_edit.text_submitted.connect(_send_chat)
	chat_box.add_child(chat_edit)

func open_chat() -> void:
	if not main.started:
		return
	chat_edit.visible = true
	chat_edit.text = ""
	chat_edit.grab_focus()

func close_chat() -> void:
	chat_edit.visible = false
	chat_edit.release_focus()

func chat_open() -> bool:
	return chat_edit != null and chat_edit.visible

func _send_chat(t: String) -> void:
	t = t.strip_edges()
	if t != "":
		cmd({"t": "chat", "msg": t})
	close_chat()

func add_chat(who: String, msg: String, mine: bool) -> void:
	var r := rt("[b][color=%s]%s[/color][/b]  %s" % ["#f5a524" if mine else "#5fd4ff", who.xml_escape(), msg.xml_escape()], 420)
	r.add_theme_constant_override("outline_size", 4)
	r.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	r.set_meta("t", Time.get_ticks_msec())
	chat_box.add_child(r)
	chat_box.move_child(chat_edit, chat_box.get_child_count() - 1)
	chat_lines.append(r)
	while chat_lines.size() > 8:
		var old: Control = chat_lines.pop_front()
		old.queue_free()

# ---- pings on the minimap
func add_ping(x: int, y: int) -> void:
	pings.append({"x": x, "y": y, "t": Time.get_ticks_msec()})

# ---- first-time hints
func _build_hints() -> void:
	hint_panel = PanelContainer.new()
	var s2 := _sb(Color(0.12, 0.11, 0.1, 0.94), Color.BLACK, 1, 10)
	s2.border_width_left = 4
	s2.border_color = C_AMBER
	hint_panel.add_theme_stylebox_override("panel", s2)
	hint_panel.custom_minimum_size.x = 290
	var v := vbox(4)
	var h := hbox(6)
	var c := cap("Getting started")
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(c)
	var x := btn("Hide", func():
		main.set_pref("hints", false)
		hint_panel.visible = false)
	x.add_theme_font_size_override("font_size", 11)
	h.add_child(x)
	v.add_child(h)
	hint_body = rt("", 268)
	v.add_child(hint_body)
	hint_panel.add_child(v)
	hint_panel.visible = false
	hud_root.add_child(hint_panel)

## The first step that isn't done yet, judged from the live world state.
func _hint_text() -> String:
	var s := sim()
	var any_miner := s.miners.size() > 0
	var gen_on := false
	for g in s.gens:
		if g.on:
			gen_on = true
	var powered := false
	for list in [s.miners, s.machines]:
		for e in list:
			if e.st == "work":
				powered = true
	var smelting := false
	for e in s.machines:
		if e.type == "smelter" and e.st == "work":
			smelting = true
	var steps := [
		[any_miner, "[b]1 · Place a miner[/b]\nPress [b]6[/b] and click a resource node near the HUB. Rocks in clusters are nodes; hover one to see what it gives."],
		[gen_on, "[b]2 · Make power[/b]\nPress [b]0[/b] for a Coal Generator. Fill it with coal: hold left click on the dark coal node to mine by hand, then open the generator and add coal."],
		[powered, "[b]3 · Connect it[/b]\nPress [b]5[/b] for Power Poles. Machines inside a pole's blue square get power. Drag to lay a line of poles."],
		[smelting, "[b]4 · Smelt the ore[/b]\nPress [b]7[/b] for a Smelter, then [b]1[/b] and drag belts from the miner's arrow into it."],
		[s.hub.get("iron_ingot", 0) > 0, "[b]5 · Feed the HUB[/b]\nBelt the smelter's output into any side of the HUB. The tracker top left counts what's arrived."],
		[s.milestone >= 1, "[b]6 · Submit the milestone[/b]\nWhen the tracker bars are full, click [b]Submit[/b]. Each milestone unlocks new buildings."],
	]
	for st in steps:
		if not st[0]:
			return st[1]
	return ""

func _update_hints() -> void:
	if not bool(main.pref("hints", true)) or not main.started:
		hint_panel.visible = false
		return
	var t := _hint_text()
	hint_panel.visible = t != ""
	if t != hint_sig:
		hint_sig = t
		hint_body.text = t
