local o = {
	dBmin = -60, -- silence threshold in decibels
	duration = 1 -- display duration in seconds
}
(require 'mp.options').read_options(o)
local dBmin = o.dBmin

local aof = mp.get_property('ao') == 'pulse' and 60 or 20
local volmax = mp.get_property_number('volume-max', 100)
local linmax = (volmax / 100) ^ 3
local sfmax = 60 * math.log(volmax / 100, 10)
local aomax = 0

local function msg(ao, s)
	mp.osd_message(string.format(ao:upper()..'Volume: %s%s', s,
		mp.get_property_bool(ao..'mute') and ' (Muted)' or ''), o.duration)
end

local function perform_dB(op, v, fmt, ao)
	local prop = ao..'volume'
	local vol = mp.get_property_number(prop)
	if not vol then
		return
	end
	local f, dBmax
	if ao == '' then
		f = 60  ; dBmax = sfmax
	else
		f = aof ; dBmax = aomax
	end
	local dB = f * math.log(vol / 100, 10)
	if op == 'add' then
		dB = math.min((dB == -math.huge and dBmin or dB) + (tonumber(v) or 0), dBmax)
		mp.commandv('osd-bar', 'set', prop, dB <= dBmin and 0 or 10^(2 + dB / f))
	elseif op == 'set' then
		dB = (v == '-inf') and dBmin or tonumber(v) or dB
		mp.commandv('osd-bar', 'set', prop, dB <= dBmin and 0 or 10^(2 + dB / f))
	else
		fmt = op
	end
	msg(ao, (dB <= dBmin and '-∞' or string.format('%+'..(fmt or 'g'), dB))..' dB')
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
		mp.commandv('osd-bar', 'set', prop, vol)
	elseif op == 'set' then
		vol = math.min(math.max(0, tonumber(v) or vol), max)
		mp.commandv('osd-bar', 'set', prop, vol)
	else
		fmt = op
	end
	msg(ao, string.format('%'..(fmt or 'g'), vol)..'%')
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
		mp.commandv('osd-bar', 'set', prop, rms ^ (1 / 3) * 100)
	elseif op == 'set' then
		rms = math.min(math.max(0, tonumber(v) or rms), max)
		mp.commandv('osd-bar', 'set', prop, rms ^ (1 / 3) * 100)
	else
		fmt = op
	end
	msg(ao, string.format('%'..(fmt or 'g'), rms))
end


mp.register_script_message('dB',
	function(op, v, fmt) perform_dB(op, v, fmt, '') end)
mp.register_script_message('ao-dB',
	function(op, v, fmt) perform_dB(op, v, fmt, 'ao-') end)

mp.register_script_message('cubic',
	function(op, v, fmt) perform_cubic(op, v, fmt, '') end)
mp.register_script_message('ao-cubic',
	function(op, v, fmt) perform_cubic(op, v, fmt, 'ao-') end)

mp.register_script_message('linear',
	function(op, v, fmt) perform_linear(op, v, fmt, '') end)
mp.register_script_message('ao-linear',
	function(op, v, fmt) perform_linear(op, v, fmt, 'ao-') end)
