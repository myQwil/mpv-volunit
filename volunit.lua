local o = {
	dBmin = -60,        -- silence threshold in decibels
	duration = 1,       -- display duration in seconds
	custom_bar = false, -- display a volume bar that linearly reflects dB values
}
(require 'mp.options').read_options(o)
local dBmin = o.dBmin
local osd = o.custom_bar and 'no-osd' or 'osd-bar'
local aof = (mp.get_property('ao') == 'pulse') and 60 or 20
local volmax = mp.get_property_number('volume-max', 100)
local sfmax = 60 * math.log(volmax / 100, 10)
local linmax = (volmax / 100) ^ 3

local function msg(ao, s)
	mp.osd_message(string.format(ao:upper()..'Volume: %s%s', s,
		mp.get_property_bool(ao..'mute') and ' (Muted)' or ''), o.duration)
end

local function round(x)
	x = x >= 0 and math.floor(x + 0.5) or math.ceil(x - 0.5)
	return x == -0 and 0 or x
end

local function set_fmt_vol(prec, fmt, vol)
	if not fmt then
		local i = prec:find('%.')
		fmt = i and ('.'..prec:sub(i + 1):len()..'f') or 'g'
	end
	prec = tonumber(prec)
	prec = (prec and prec ~= 0) and math.abs(prec) or 1
	vol = round(vol / prec) * prec
	return fmt, vol
end

local function perform_dB(op, v, prec, fmt, ao)
	local prop = ao..'volume'
	local vol = mp.get_property_number(prop)
	if not vol then
		return
	end

	local k, dBmax
	if ao == '' then k = 60  ; dBmax = sfmax
	else             k = aof ; dBmax = 0
	end
	local dB = k * math.log(vol / 100, 10)

	if op == 'add' then
		dB = math.min(math.max(dBmin, dB) + (tonumber(v) or 0), dBmax)
	elseif op == 'set' then
		dB = (v == '-inf') and dBmin or math.min(tonumber(v) or dB, dBmax)
	else
		mp.commandv(osd, 'add', prop, 0)
		msg(ao, ((vol == 0) and '-∞' or string.format('%+'..(op or 'g'), dB))..' dB')
		return dB, dBmax
	end

	fmt, dB = set_fmt_vol(prec or v or '', fmt, dB)
	mp.commandv(osd, 'set', prop, (dB <= dBmin) and 0 or 10 ^ (2 + dB / k))
	msg(ao, ((dB <= dBmin) and '-∞' or string.format('%+'..fmt, dB))..' dB')
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
		mp.commandv('osd-bar', 'add', prop, 0)
		return msg(ao, string.format('%'..(op or 'g'), vol)..'%')
	end

	fmt, vol = set_fmt_vol(prec or v or '', fmt, vol)
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
		mp.commandv('osd-bar', 'add', prop, 0)
		return msg(ao, string.format('%'..(op or 'g'), rms))
	end

	fmt, rms = set_fmt_vol(prec or v or '', fmt, rms)
	mp.commandv('osd-bar', 'set', prop, rms ^ (1 / 3) * 100)
	msg(ao, string.format('%'..fmt, rms))
end


if o.custom_bar then
	local assdraw = require('mp.assdraw')
	local b = {
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
		w=0, h=0, x=0, y=0,
		win_w=0, win_h=0,
		sf=0, ao=0, -- 100% volume markers
		sx=0, sy=0, -- speaker symbol position
	}
	b.half = b.bord * 0.5

	b.to_dimen = mp.add_timeout(0.15, function()
		b.win_w = b.win_w * (b.osd.res_y / b.win_h)
		b.win_h = b.osd.res_y
		b.w = b.win_w * 0.75
		b.h = b.win_h * 0.03125
		b.x = (b.win_w - b.w) * 0.5
		b.y = (b.win_h - b.h) * 0.75
		b.sx = b.x - b.h * 0.25
		b.sy = b.y + b.h * 0.5
		b.sf = (b.w - b.bord) * (0 - dBmin) / (sfmax - dBmin) + b.half
		b.ao = b.w - b.half
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
		local pos0 = (ao == '') and self.sf or self.ao
		local draw = assdraw.ass_new()
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
