local o = {
	dBmin = -60,  -- silence threshold in decibels
	duration = 1, -- display duration in seconds
}
(require 'mp.options').read_options(o)
local dBmin = o.dBmin
local sfmax = 60 * math.log(mp.get_property_number('volume-max', 100) / 100, 10)
local aof = (mp.get_property('ao') == 'pulse') and 60 or 20

local function print_dB(ao, dB, fmt)
	dB = (dB <= dBmin) and '-∞' or string.format('%+'..fmt, dB)
	mp.osd_message(string.format(ao:upper()..'Volume: %s dB%s', dB,
		mp.get_property_bool(ao..'mute') and ' (Muted)' or ''), o.duration)
end

local function round(x)
	return x >= 0 and math.floor(x + 0.5) or math.ceil(x - 0.5)
end

local function perform_dB(op, v, ao)
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
		local inc = tonumber(v) or 0
		local prec = (inc ~= 0) and math.abs(inc) or 1
		dB = math.min(math.max(dBmin, dB) + inc, dBmax)
		dB = round(dB / prec) * prec
	elseif op == 'set' then
		dB = (v == '-inf') and dBmin or math.min(tonumber(v) or dB, dBmax)
	else
		mp.commandv('osd-bar', 'add', prop, 0)
		return print_dB(ao, dB, op or 'g')
	end
	mp.commandv('osd-bar', 'set', prop, (dB <= dBmin) and 0 or 10 ^ (2 + dB / k))

	local i = v and v:find('%.')
	print_dB(ao, dB, i and ('.'..v:sub(i + 1):len()..'f') or 'g')
end

mp.register_script_message('dB'   , function(op, v) perform_dB(op, v, '')    end)
mp.register_script_message('ao-dB', function(op, v) perform_dB(op, v, 'ao-') end)
