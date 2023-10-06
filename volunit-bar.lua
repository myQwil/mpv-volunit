local o = {
	dBmin = -60, -- silence threshold in decibels
	duration = 1 -- display duration in seconds
}
(require 'mp.options').read_options(o)
local dBmin = o.dBmin
local assdraw = require 'mp.assdraw'

local color = {
	font = '3aH00\\3cH000000\\1aH00\\1cHFFFFFF',
	fill = '1aH00\\1cHA0FFFF',
	back = '1aH80\\1cH400000',
	pos  = '3aH00\\3cH00A0FF'
}

local border = 3
local bhalf = border / 2
local dent = border * 1.3
local osd = mp.create_osd_overlay('ass-events')
local to_osd = mp.add_timeout(o.duration, function() osd:remove() end)
local aomax, sfmax = 0, 60 * math.log(mp.get_property_number('volume-max') / 100, 10)
local aof = mp.get_property('ao') == 'pulse' and 60 or 20

local win_w ,win_h ,w ,h ,x ,y ,sx ,sy ,sfpos ,aopos
=     0     ,0     ,0 ,0 ,0 ,0 ,0  ,0  ,0     ,0
local to_dimen = mp.add_timeout(0.15, function()
	local ratio = osd.res_y / win_h
	win_w, win_h = win_w * ratio, win_h * ratio
	w, h = win_w * 0.75, win_h * 0.03125
	x, y = (win_w - w) * 0.5, (win_h - h) * 0.75
	sx, sy = x - h * 0.25, y + h * 0.5
	sfpos = (w - border) * ((0 - dBmin) / (sfmax - dBmin)) + bhalf
	aopos = (w - border) * ((0 - dBmin) / (aomax - dBmin)) + bhalf
end)
to_dimen:kill()
mp.observe_property('osd-dimensions', 'native', function(_, win)
	to_dimen:kill()
	win_w, win_h = win.w, win.h
	if win_h ~= 0 then
		to_dimen:resume()
	end
end)

local function perform_dB(op, v, fmt, ao)
	to_osd:kill()
	local prop = ao..'volume'
	local vol = mp.get_property_number(prop)
	if not vol then
		return
	end
	local f, dBmax, pos0
	if ao == '' then
		f = 60  ; dBmax = sfmax ; pos0 = sfpos
	else
		f = aof ; dBmax = aomax ; pos0 = aopos
	end
	local dB = f * math.log(vol / 100, 10)
	if op == 'add' then
		dB = math.min(math.max(dBmin, (dB == -math.huge and dBmin or dB) + v), dBmax)
		mp.commandv('no-osd', 'set', prop, dB <= dBmin and 0 or 10^(2 + dB / f))
	elseif op == 'set' then
		dB = (v == '-inf') and dBmin or tonumber(v)
		mp.commandv('no-osd', 'set', prop, dB <= dBmin and 0 or 10^(2 + dB / f))
	else
		fmt = op
	end

	local s = dB <= dBmin and '-∞' or string.format(fmt or '%+g',
		math.floor(dB * 0x1p2 + 0.5) * 0x1p-2)
	mp.osd_message(string.format(ao:upper()..'Volume: %s dB%s', s,
		mp.get_property_bool(ao..'mute') and ' (Muted)' or ''), o.duration)

	local pos = (w - border) * ((dB - dBmin) / (dBmax - dBmin)) + bhalf
	local draw = assdraw.ass_new()
	draw:append(string.format('{\\an6\\bord%g\\%s\\pos(%g,%g)'
		..'\\fnmpv-osd-symbols}', border, color.font, sx, sy))

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

	draw:move_to(pos0 + dent, 0)
	draw:line_to(pos0, dent)
	draw:line_to(pos0 - dent, 0)
	draw:move_to(pos0 - dent, h)
	draw:line_to(pos0, h - dent)
	draw:line_to(pos0 + dent, h)
	draw:draw_stop()

	draw:append(string.format('\n{\\bord%g\\%s\\pos(%g,%g)}',
		bhalf, color.pos, x, y))
	draw:draw_start() -- position marker
	draw:move_to(pos, 0)
	draw:line_to(pos, h)
	draw:draw_stop()

	osd.data = draw.text
	osd:update()
	to_osd:resume()
end
mp.register_script_message('dB',
	function(op, v, fmt) perform_dB(op, v, fmt, '') end)
mp.register_script_message('ao-dB',
	function(op, v, fmt) perform_dB(op, v, fmt, 'ao-') end)
