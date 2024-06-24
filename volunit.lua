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

local function set_precision(x, prec)
	local prec = tonumber(prec)
	prec = (prec and prec ~= 0) and math.abs(prec) or 1
	return math.floor(x / prec + 0.5) * prec
end

local function set_format(prec)
	local i = prec:find('%.')
	return i and ('.'..prec:sub(i + 1):len()..'f') or 'g'
end

local function perform_dB(op, v, prec, fmt, ao)
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

	prec = prec or v
	fmt = fmt or set_format(prec)
	dB = set_precision(dB, prec)
	mp.commandv(osd, 'set', prop, dB <= dBmin and 0 or math.exp(k * dB + ln100))
	msg(ao, (dB <= dBmin and '-∞' or string.format('%+'..fmt, dB))..' dB')
	return dB, dBmax
end

local function perform_cubic(op, v, prec, fmt, ao)
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

local function perform_linear(op, v, prec, fmt, ao)
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
			font = '1cH000000\\3cH808080',
			back = '1aHD0\\1cHFFFFFF',
			fill = '1cH000000',
			pos  = '3cHFFFFFF',
			max  = '3aH98\\3cHFFFF00',
			line = '1aHFF\\3cH808080',
		},
		bord = 4,
		win_w=0, win_h=0, w=0, h=0,
		x=0, y=0, sx=0, sy=0,
		sfpos=0, aopos=0,
	}
	b.half = b.bord * 0.5

	b.to_dimen = mp.add_timeout(0.15, function()
		b.win_w = b.win_w * (b.osd.res_y / b.win_h)
		b.win_h = b.osd.res_y
		b.w = b.win_w * 0.75
		b.h = b.win_h * 0.03125
		b.x = (b.win_w - b.w) * 0.5
		b.y = (b.win_h - b.h) * 0.75

		-- dent the bar at the 100% volume position
		b.dent = b.h * 0.25
		b.sfpos = (b.w - b.bord) * (0 - dBmin) / (sfmax - dBmin) + b.half
		b.aopos = b.w - b.half

		-- speaker symbol is anchored to this position
		b.sx = b.x - b.h * 0.25
		b.sy = b.y + b.h * 0.5
	end, true)

	mp.observe_property('osd-dimensions', 'native', function(_, win)
		b.to_dimen:kill()
		b.win_w, b.win_h = win.w, win.h
		if b.win_h ~= 0 then
			b.to_dimen:resume()
		end
	end)

	function ass_draw(ass, fn, bord, color, x, y, w, h)
		ass:append(string.format('\n{\\bord%g\\%s\\pos(%g,%g)}', bord, color, x, y))
		ass:draw_start()
		fn(ass, w, h)
		ass:draw_stop()
	end

	function rect(ass, w, h)
		ass:rect_cw(0, 0, w, h)
	end

	function marker(ass, pos, h)
		ass:move_to(pos, 0)
		ass:line_to(pos, h)
	end

	function b:draw_bar(dB, dBmax, ao)
		local color = self.color
		local bord, half = self.bord, self.half
		local x, y, w, h = self.x, self.y, self.w, self.h
		local pos = (w - bord) * ((math.max(dBmin, dB) - dBmin) / (dBmax - dBmin)) + half
		local pos0 = (ao == '') and self.sfpos or self.aopos
		local draw = self.assdraw.ass_new()
		draw:append(string.format('{\\an6\\bord%g\\%s\\pos(%g,%g)'
			..'\\fnmpv-osd-symbols}', bord, color.font, self.sx, self.sy))

		ass_draw(draw, rect, 0, color.back, x, y, w, h)        -- back area
		ass_draw(draw, rect, 0, color.fill, x, y, pos, h)      -- filled area
		ass_draw(draw, marker, half, color.pos, x, y, pos, h)  -- position marker
		ass_draw(draw, marker, half, color.max, x, y, pos0, h) -- 100% marker
		ass_draw(draw, rect, bord, color.line, x, y, w, h)     -- outline

		self.osd.data = draw.text
		self.osd:update()
	end

	b.to_osd = mp.add_timeout(o.duration, function() b.osd:remove() end, true)

	function b:perform(op, v, fmt, prec, ao)
		self.to_osd:kill()
		local dB, dBmax = perform_dB(op, v, fmt, prec, ao)
		if dB then
			self:draw_bar(dB, dBmax, ao)
		end
		self.to_osd:resume()
	end

	mp.register_script_message('dB',
		function(op, v, prec, fmt) b:perform(op, v, prec, fmt, '') end)
	mp.register_script_message('ao-dB',
		function(op, v, prec, fmt) b:perform(op, v, prec, fmt, 'ao-') end)
else
	mp.register_script_message('dB',
		function(op, v, prec, fmt) perform_dB(op, v, prec, fmt, '') end)
	mp.register_script_message('ao-dB',
		function(op, v, prec, fmt) perform_dB(op, v, prec, fmt, 'ao-') end)
end

mp.register_script_message('cubic',
	function(op, v, prec, fmt) perform_cubic(op, v, prec, fmt, '') end)
mp.register_script_message('ao-cubic',
	function(op, v, prec, fmt) perform_cubic(op, v, prec, fmt, 'ao-') end)

mp.register_script_message('linear',
	function(op, v, prec, fmt) perform_linear(op, v, prec, fmt, '') end)
mp.register_script_message('ao-linear',
	function(op, v, prec, fmt) perform_linear(op, v, prec, fmt, 'ao-') end)
