local o = {
	dBmin = -60,        -- silence threshold in decibels
	duration = 1,       -- display duration in seconds
	custom_bar = false, -- display a volume bar that linearly reflects dB values
}
(require 'mp.options').read_options(o)
local dBmin = o.dBmin
local osd = o.custom_bar and 'no-osd' or 'osd-bar'

local ln10 = math.log(10)
local ln_ao = ln10 / (mp.get_property('ao') == 'pulse' and 60 or 20)
local ln_sf = ln10 / 60
local ln100 = ln10 * 2

local volmax = mp.get_property_number('volume-max', 100)
local linmax = (volmax / 100) ^ 3
local sfmax = (math.log(volmax) - ln100) / ln_sf
local aomax = 0

local function msg(ao, s)
	mp.osd_message(string.format(ao:upper()..'Volume: %s%s', s,
		mp.get_property_bool(ao..'mute') and ' (Muted)' or ''), o.duration)
end

local function set_precision(x, fmt)
	local prec = tonumber(fmt)
	prec = (prec and prec ~= 0) and math.abs(prec) or 1
	x = math.floor(x / prec + 0.5) * prec

	local i = fmt:find('%.')
	fmt = '.'..(i and fmt:sub(i + 1):len() or 0)..'f'
	return x, fmt
end

local function perform_dB(op, v, fmt, ao)
	local prop = ao..'volume'
	local vol = mp.get_property_number(prop)
	if not vol then
		return
	end

	local k, dBmax
	if ao == '' then k = ln_sf ; dBmax = sfmax
	else             k = ln_ao ; dBmax = aomax
	end

	local dB = (math.log(vol) - ln100) / k

	if op == 'add' then
		dB = math.min(math.max(dBmin, dB) + (tonumber(v) or 0), dBmax)
	elseif op == 'set' then
		dB = (v == '-inf') and dBmin or math.min(tonumber(v) or dB, dBmax)
	else
		msg(ao, (vol == 0 and '-∞' or string.format('%+'..(op or 'g'), dB))..' dB')
		return dB, dBmax
	end

	dB, fmt = set_precision(dB, fmt or v)
	mp.commandv(osd, 'set', prop, dB <= dBmin and 0 or math.exp(k * dB + ln100))
	msg(ao, (dB <= dBmin and '-∞' or string.format('%+'..fmt, dB))..' dB')
	return dB, dBmax
end

local function perform_cubic(op, v, fmt, ao)
	local prop = ao..'volume'
	local vol = mp.get_property_number(prop)
	if not vol then
		return
	end

	local max = (ao == '') and volmax or 100
	if op == 'add' then
		vol = math.min(math.max(0, vol + (tonumber(v) or 0)), max)
	elseif op == 'set' then
		vol = math.min(math.max(0, tonumber(v) or vol), max)
	else
		return msg(ao, string.format('%'..(op or 'g'), vol)..'%')
	end

	vol, fmt = set_precision(vol, fmt or v)
	mp.commandv('osd-bar', 'set', prop, vol)
	msg(ao, string.format('%'..fmt, vol)..'%')
end

local function perform_linear(op, v, fmt, ao)
	local prop = ao..'volume'
	local vol = mp.get_property_number(prop)
	if not vol then
		return
	end

	local max = (ao == '') and linmax or 1
	local rms = (vol / 100) ^ 3
	if op == 'add' then
		rms = math.min(math.max(0, rms + (tonumber(v) or 0)), max)
	elseif op == 'set' then
		rms = math.min(math.max(0, tonumber(v) or rms), max)
	else
		return msg(ao, string.format('%'..(op or 'g'), rms))
	end

	rms, fmt = set_precision(rms, fmt or v)
	mp.commandv('osd-bar', 'set', prop, rms ^ (1 / 3) * 100)
	msg(ao, string.format('%'..fmt, rms))
end


if o.custom_bar then
	local b = {
		assdraw = require('mp.assdraw'),
		osd = mp.create_osd_overlay('ass-events'),
		color = {
			font = '3aH00\\3cH000000\\1aH00\\1cHFFFFFF',
			fill = '1aH00\\1cHA0FFFF',
			back = '1aH80\\1cH400000',
			pos  = '3aH00\\3cH00A0FF'
		},
		border = 3,
		win_w=0, win_h=0, w=0, h=0,
		x=0, y=0, sx=0, sy=0,
		sfpos=0, aopos=0,
	}
	b.half = b.border / 2
	b.dent = b.border * 1.3

	b.to_dimen = mp.add_timeout(0.15, function()
		local ratio = b.osd.res_y / b.win_h
		b.win_w, b.win_h = b.win_w * ratio, b.win_h * ratio
		b.w, b.h = b.win_w * 0.75, b.win_h * 0.03125
		b.x, b.y = (b.win_w - b.w) * 0.5, (b.win_h - b.h) * 0.75
		b.sx, b.sy = b.x - b.h * 0.25, b.y + b.h * 0.5
		b.sfpos = (b.w - b.border) * ((0 - dBmin) / (sfmax - dBmin)) + b.half
		b.aopos = (b.w - b.border) * ((0 - dBmin) / (aomax - dBmin)) + b.half
	end, true)

	mp.observe_property('osd-dimensions', 'native', function(_, win)
		b.to_dimen:kill()
		b.win_w, b.win_h = win.w, win.h
		if b.win_h ~= 0 then
			b.to_dimen:resume()
		end
	end)

	function b:draw_bar(dB, dBmax, ao)
		local color = self.color
		local border, half, dent = self.border, self.half, self.dent
		local x, y, w, h = self.x, self.y, self.w, self.h
		local pos = (w - border) * ((math.max(dBmin, dB) - dBmin) / (dBmax - dBmin)) + half
		local draw = self.assdraw.ass_new()
		draw:append(string.format('{\\an6\\bord%g\\%s\\pos(%g,%g)'
			..'\\fnmpv-osd-symbols}', border, color.font, self.sx, self.sy))

		draw:append(string.format('\n{\\bord0\\%s\\pos(%g,%g)}', color.back, x, y))
		draw:draw_start() -- back area
		draw:rect_cw(0, 0, w, h)
		draw:draw_stop()

		draw:append(string.format('\n{\\bord0\\%s\\pos(%g,%g)}', color.fill, x, y))
		draw:draw_start() -- filled area
		draw:rect_cw(0, 0, pos, h)
		draw:draw_stop()

		draw:append(string.format('\n{\\bord%g\\%s\\pos(%g,%g)}',
			border, color.font, x, y))
		draw:draw_start()
		draw:rect_cw(-border, -border, w + border, h + border) -- the box
		draw:rect_ccw(0, 0, w, h) -- the "hole"

		if ao == '' then
			local pos0 = self.sfpos
			draw:move_to(pos0 + dent, 0)
			draw:line_to(pos0, dent)
			draw:line_to(pos0 - dent, 0)
			draw:move_to(pos0 - dent, h)
			draw:line_to(pos0, h - dent)
			draw:line_to(pos0 + dent, h)
			draw:draw_stop()
		end

		draw:append(string.format('\n{\\bord%g\\%s\\pos(%g,%g)}',
			half, color.pos, x, y))
		draw:draw_start() -- position marker
		draw:move_to(pos, 0)
		draw:line_to(pos, h)
		draw:draw_stop()

		self.osd.data = draw.text
		self.osd:update()
	end

	b.to_osd = mp.add_timeout(o.duration, function() b.osd:remove() end, true)

	function b:perform(op, v, fmt, ao)
		self.to_osd:kill()
		local dB, dBmax = perform_dB(op, v, fmt, ao)
		self:draw_bar(dB, dBmax, ao)
		self.to_osd:resume()
	end

	mp.register_script_message('dB',
		function(op, v, fmt) b:perform(op, v, fmt, '') end)
	mp.register_script_message('ao-dB',
		function(op, v, fmt) b:perform(op, v, fmt, 'ao-') end)
else
	mp.register_script_message('dB',
		function(op, v, fmt) perform_dB(op, v, fmt, '') end)
	mp.register_script_message('ao-dB',
		function(op, v, fmt) perform_dB(op, v, fmt, 'ao-') end)
end

mp.register_script_message('cubic',
	function(op, v, fmt) perform_cubic(op, v, fmt, '') end)
mp.register_script_message('ao-cubic',
	function(op, v, fmt) perform_cubic(op, v, fmt, 'ao-') end)

mp.register_script_message('linear',
	function(op, v, fmt) perform_linear(op, v, fmt, '') end)
mp.register_script_message('ao-linear',
	function(op, v, fmt) perform_linear(op, v, fmt, 'ao-') end)
