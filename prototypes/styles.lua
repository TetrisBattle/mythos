-- GUI styles for the Mythos mod.
local styles = data.raw["gui-style"]["default"]

styles["mythos_resize_frame"] = {
	type                     = "frame_style",
	parent                   = "frame",
	horizontally_stretchable = "off",
}

styles["mythos_resize_field"] = {
	type   = "textbox_style",
	parent = "short_number_textfield",
	height = 28,
}

styles["mythos_resize_button"] = {
	type             = "button_style",
	parent           = "button",
	width            = 28,
	height           = 28,
	top_padding      = 0,
	bottom_padding   = 0,
	left_padding     = 0,
	right_padding    = 0,
	font             = "default-bold",
	horizontal_align = "center",
	vertical_align   = "center",
}

styles["mythos_gate_position_frame"] = {
	type                     = "frame_style",
	parent                   = "frame",
	horizontally_stretchable = "off",
}

styles["mythos_gate_position_button"] = {
	type           = "button_style",
	parent         = "slot_button",
	width          = 40,
	height         = 40,
	top_padding    = 0,
	bottom_padding = 0,
	left_padding   = 0,
	right_padding  = 0,
}

styles["mythos_gate_position_source_button"] = {
	type           = "button_style",
	parent         = "slot_button",
	width          = 40,
	height         = 40,
	top_padding    = 0,
	bottom_padding = 0,
	left_padding   = 0,
	right_padding  = 0,
}

styles["mythos_gate_position_trash_button"] = {
	type           = "button_style",
	parent         = "frame_action_button",
	width          = 24,
	height         = 24,
	top_padding    = 2,
	bottom_padding = 2,
	left_padding   = 2,
	right_padding  = 2,
}

styles["mythos_gate_position_label"] = {
	type             = "label_style",
	parent           = "label",
	font             = "default-bold",
	horizontal_align = "center",
}
