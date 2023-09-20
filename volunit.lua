local o = {
	dBmin = -60, -- silence threshold in decibels
	duration = 1 -- display duration in seconds
}
(require 'mp.options').read_options(o)
local dBmin = o.dBmin

local aof = mp.get_property('ao') == 'pulse' and 60 or 20
local sfmax = 60 * math.log(mp.get_property_number('volume-max') / 100, 10)
local aomax = 0

local function perform_dB(op, v, fmt, ao)
	local f, dBmax
	if ao == '' then
		f = 60  ; dBmax = sfmax
	else
		f = aof ; dBmax = aomax
	end
	local dB = f * math.log(mp.get_property_number(ao..'volume') / 100, 10)
	if op == 'add' then
		dB = math.min(math.max(dBmin, (dB == -math.huge and dBmin or dB) + v), dBmax)
		mp.commandv('osd-bar', 'set', ao..'volume', dB <= dBmin and 0 or 10^(2 + dB / f))
	elseif op == 'set' then
		dB = (v == '-inf') and dBmin or tonumber(v)
		mp.commandv('osd-bar', 'set', ao..'volume', dB <= dBmin and 0 or 10^(2 + dB / f))
	else
		fmt = op
	end

	local vol = dB <= dBmin and '-∞' or string.format(fmt or '%+g',
		math.floor(dB * 0x1p2 + 0.5) * 0x1p-2)
	mp.osd_message(string.format(ao:upper()..'Volume: %s dB%s', vol,
		mp.get_property_bool(ao..'mute') and ' (Muted)' or ''), o.duration)
end

mp.register_script_message('dB',
	function(op, v, fmt) perform_dB(op, v, fmt, '') end)
mp.register_script_message('ao-dB',
	function(op, v, fmt) perform_dB(op, v, fmt, 'ao-') end)
