local o = {
	dBmin = -60,        -- silence threshold in decibels
	duration = 1,       -- display duration in seconds
	custom_bar = false, -- display a volume bar that linearly reflects dB values
}
(require "mp.options").read_options(o)
local osd = o.custom_bar and "no-osd" or "osd-bar"
local ao_is_cubic = (mp.get_property("ao") == "pulse")
local volmax = mp.get_property_number("volume-max", 100) / 100

local function round(x)
	x = x >= 0 and math.floor(x + 0.5) or math.ceil(x - 0.5)
	return x == -0 and 0 or x
end

local function msg(ao, s)
	mp.osd_message(string.format(ao:upper().."Volume: %s%s", s,
		mp.get_property_bool(ao.."mute") and " (Muted)" or ""), o.duration)
end

local function translate(scale, op, v, prec)
	local ao = scale.is_ao and "ao-" or ""
	local prop = ao.."volume"
	local vol = mp.get_property_number(prop)
	if not vol then
		return
	end

	local value, fmt
	if op == "add" then
		prec = prec or v or ""
		local i = prec:find("%.")
		fmt = i and ("."..prec:sub(i + 1):len().."f") or "g"
		prec = tonumber(prec)
		prec = (prec and prec ~= 0) and math.abs(prec) or 1

		value = math.max(scale.min, scale:from_volume(vol / 100)) + (tonumber(v) or 0)
		value = math.min(math.max(scale.min, round(value / prec) * prec), scale.max)
	elseif op == "set" then
		fmt = prec or "g"
		value = v == "-inf" and -math.huge or tonumber(v) or 0
	else
		mp.commandv(osd, "add", prop, 0)
		value = scale:from_volume(vol / 100)
		msg(ao, scale:to_string_any(value, op or "g"))
		return math.min(math.max(scale.min, value), scale.max)
	end

	mp.commandv(osd, "set", prop, scale:to_volume(value) * 100)
	msg(ao, scale:to_string(value, fmt))
	return value
end


--------------------------------------------------------------------------------
---------------------------------- Custom Bar ----------------------------------
local perform
if o.custom_bar then
	local assdraw = require("mp.assdraw")
	local bar = {
		osd = mp.create_osd_overlay("ass-events"),
		color = {
			font = "1cH000000\\3cH808080",
			back = "1aHD0\\1cHFFFFFF",
			pos  = "3cHFFFFFF",
			max  = "3aH98\\3cHFFFF00",
			line = "1aHFF\\3cH808080",
		},
		bord = 4,
		w=0, h=0, x=0, y=0,
		win_w=0, win_h=0,
		sx=0, sy=0, -- speaker symbol position
	}
	bar.half = bar.bord * 0.5

	bar.to_dimen = mp.add_timeout(0.15, function()
		bar.win_w = bar.win_w * (bar.osd.res_y / bar.win_h)
		bar.win_h = bar.osd.res_y

		bar.w = bar.win_w * 0.75
		bar.h = bar.win_h * 0.03125

		bar.x = (bar.win_w - bar.w) * 0.5  -- horizontally centered
		bar.y = (bar.win_h - bar.h) * 0.75 -- below vertical center

		bar.sx = bar.x - bar.h * 0.25 -- left of bar, with 1/4 bar height margin
		bar.sy = bar.y + bar.h * 0.5  -- vertically centered with bar
	end, true)

	mp.observe_property("osd-dimensions", "native", function(_, win)
		bar.to_dimen:kill()
		bar.win_w, bar.win_h = win.w, win.h
		if bar.win_h ~= 0 then
			bar.to_dimen:resume()
		end
	end)

	local function rect(ass, w, h)
		ass:rect_cw(0, 0, w, h)
	end

	local function marker(ass, pos, h)
		ass:move_to(pos, 0)
		ass:line_to(pos, h)
	end

	local function ass_draw(ass, fn, bord, color, x, y, w, h)
		ass:append(string.format("\n{\\bord%g\\%s\\pos(%g,%g)}", bord, color, x, y))
		ass:draw_start()
		fn(ass, w, h)
		ass:draw_stop()
	end

	local function normalized(scale, pos)
		return (pos - scale.min) / (scale.max - scale.min)
	end

	function bar:draw(scale, value)
		local color = self.color
		local bord, half = self.bord, self.half
		local x, y, w, h = self.x, self.y, self.w, self.h
		local pos = (w - bord) * normalized(scale, value) + half
		local pos0 = (w - bord) * normalized(scale, scale.full) + half

		local draw = assdraw.ass_new()
		draw:append(string.format("{\\an6\\bord%g\\%s\\pos(%g,%g)"
			.."\\fnmpv-osd-symbols}", bord, color.font, self.sx, self.sy))

		ass_draw(draw, rect, 0, color.back, x, y, w, h)        -- back area
		ass_draw(draw, rect, 0, scale.color, x, y, pos, h)     -- filled area
		ass_draw(draw, marker, half, color.pos, x, y, pos, h)  -- position marker
		ass_draw(draw, marker, half, color.max, x, y, pos0, h) -- 100% marker
		ass_draw(draw, rect, bord, color.line, x, y, w, h)     -- outline

		self.osd.data = draw.text
		self.osd:update()
	end

	bar.to_osd = mp.add_timeout(o.duration, function()
		bar.osd:remove()
	end, true)

	function bar:translate(scale, op, v, prec)
		self.to_osd:kill()
		local value = translate(scale, op, v, prec)
		if value then
			self:draw(scale, value)
		end
		self.to_osd:resume()
	end

	perform = function(scale, op, v, prec)
		bar:translate(scale, op, v, prec)
	end
else
	perform = function(scale, op, v, prec)
		translate(scale, op, v, prec)
	end
end


--------------------------------------------------------------------------------
------------------------------- Decibel Scaling --------------------------------
local decibel = {
	from_volume = function(self, vol)
		return vol <= 0 and -math.huge or (math.log(vol) / self.k)
	end,
	to_volume = function(self, dB)
		return dB <= self.min and 0 or math.exp(dB * self.k)
	end,
	to_string = function(self, dB, fmt)
		return (dB <= self.min and "-∞" or string.format("%+"..fmt, dB)).." dB"
	end,
	to_string_any = function(self, dB, fmt)
		return (dB == -math.huge and "-∞" or string.format("%+"..fmt, dB)).." dB"
	end,
	k = math.log(10) / 60,
	min = o.dBmin,
	full = 0,
	is_ao = false,
	color = "1cH000020",
}
decibel.max = decibel:from_volume(volmax)

local decibel_ao = setmetatable({
	k = math.log(10) / (ao_is_cubic and 60 or 20),
	max = 0,
	is_ao = true,
}, { __index = decibel })

mp.register_script_message("dB",
	function(op, v, prec) perform(decibel, op, v, prec) end)
mp.register_script_message("ao-dB",
	function(op, v, prec) perform(decibel_ao, op, v, prec) end)


--------------------------------------------------------------------------------
-------------------------------- Linear Scaling --------------------------------
local linear = {
	from_volume = function(self, vol)
		return vol ^ self.k
	end,
	to_volume = function(self, lin)
		return lin ^ (1 / self.k)
	end,
	to_string = function(self, lin, fmt)
		return string.format("%"..fmt, lin)
	end,
	k = 3,
	min = 0,
	full = 1,
	is_ao = false,
	color = "1cH002000",
}
linear.max = linear:from_volume(volmax)
linear.to_string_any = linear.to_string

local linear_ao = setmetatable({
	k = ao_is_cubic and 3 or 1,
	max = 1,
	is_ao = true,
}, { __index = linear })

mp.register_script_message("linear",
	function(op, v, prec) perform(linear, op, v, prec) end)
mp.register_script_message("ao-linear",
	function(op, v, prec) perform(linear_ao, op, v, prec) end)


--------------------------------------------------------------------------------
-------------------------------- Cubic Scaling ---------------------------------
local cubic = {
	from_volume = linear.to_volume,
	to_volume = linear.from_volume,
	to_string = function(self, cube, fmt)
		return string.format("%"..fmt, cube).."³"
	end,
	k = 1,
	min = 0,
	max = volmax,
	full = 1,
	is_ao = false,
	color = "1cH200000",
}
cubic.to_string_any = cubic.to_string

local cubic_ao = setmetatable({
	k = ao_is_cubic and 1 or 3,
	max = 1,
	is_ao = true,
}, { __index = cubic })

mp.register_script_message("cubic",
	function(op, v, prec) perform(cubic, op, v, prec) end)
mp.register_script_message("ao-cubic",
	function(op, v, prec) perform(cubic_ao, op, v, prec) end)
