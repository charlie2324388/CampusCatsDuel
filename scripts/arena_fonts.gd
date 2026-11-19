extends RefCounted

const MOBILE_FONT: FontFile = preload("res://art/fonts/campus-ui.ttf")

static func interface_font(weight: int, numeric: bool=false) -> Font:
	if OS.has_feature("web"):
		var font:=FontVariation.new()
		font.base_font=MOBILE_FONT
		font.variation_opentype={TextServerManager.get_primary_interface().name_to_tag("wght"):float(weight)}
		return font
	var native:=SystemFont.new()
	if numeric:
		native.font_names=PackedStringArray(["Bahnschrift","Consolas","PingFang SC","Microsoft YaHei UI"])
	else:
		native.font_names=PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei","PingFang SC","Noto Sans CJK SC","SimHei"])
	native.font_weight=weight
	native.fallbacks=[MOBILE_FONT]
	return native