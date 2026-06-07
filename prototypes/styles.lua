-- GUI styles for the Mythos mod.
local styles = data.raw["gui-style"]["default"]

styles["mythos_resize_frame"] = {
	type                     = "frame_style",
	parent                   = "frame",
	horizontally_stretchable = "off",
}

styles["mythos_resize_inner"] = {
	type                     = "frame_style",
	parent                   = "inside_shallow_frame_with_padding",
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
