local state = nil
local o = {
	gap = 20,    -- number of pixels between steps
	step = 1,    -- step factor
	dBmin = -60, -- silence threshold in decibels
	fmt = '.3g'  -- number format
}
(require 'mp.options').read_options(o)
local dBmin, dBmax = o.dBmin, 0
local f = mp.get_property('ao') == 'pulse' and 60 or 20

local function drag(_, pos)
	local dif = math.floor((state.pos.y - pos.y) / o.gap + 0.5)
	if state.dif ~= dif then
		state.dif = dif
		local dB = math.min(state.dB + (dif * o.step), dBmax)
		local s = (dB <= dBmin and '-∞' or string.format('%+'..o.fmt, dB))..' dB'
		mp.commandv('osd-bar', 'set', 'ao-volume', dB <= dBmin and 0 or 10 ^ (2 + dB / f))
		mp.osd_message(string.format('AO-Volume: %s%s', s,
			mp.get_property_bool('ao-mute') and ' (Muted)' or ''), 1)
	end
end

local function click(t)
	if t.event == 'down' then
		local pos = mp.get_property_native('mouse-pos')
		local vol = mp.get_property_number('ao-volume')
		if not (pos and vol) then
			return
		end
		state = { pos=pos, dif=0, dB=math.max(dBmin, f * math.log(vol / 100, 10)) }
		mp.observe_property('mouse-pos', 'native', drag)
	elseif t.event == 'up' then
		mp.unobserve_property(drag)
	end
end

mp.add_key_binding('mbtn_mid', click, {complex=true})
