FRONT = defines.rail_direction.front
BACK = defines.rail_direction.back
CONNECTION_DIRECTIONS = {
	defines.rail_connection_direction.straight,
	defines.rail_connection_direction.left,
	defines.rail_connection_direction.right,
}

---@param dir defines.rail_direction
---@return defines.rail_direction
function flip(dir) if dir == FRONT then return BACK else return FRONT end end

---Generate a unique key for a rail end (segment + direction)
---@param re LuaRailEnd
---@return number
function key(re)
	return re.rail.unit_number * 2 + (re.direction == FRONT and 1 or 0)
end

--- Get signal inbetween two rail sections
---@param re      LuaRailEnd # first RE of the next segment
---@param prev_re LuaRailEnd # last RE of the previous segment
---@param reverse boolean    # When false, return the signal facing into the next segment. When true, return the signal facing back towards the previous segment.
---@return LuaEntity?
function get_signals_from_last_rail(re, prev_re, reverse)
	return re.rail.get_rail_segment_signal(flip(re.direction), not reverse) or prev_re.rail.get_rail_segment_signal(prev_re.direction, reverse)
end

--- Get the furthest reserved rail end of a train
function get_train_furthest_reserved_re(re, path)
	if path then
		for i = path.current + 1, path.size do -- follow reserved path
			if path.rails[i - 1] == re.rail then
				for _, dir in pairs(CONNECTION_DIRECTIONS) do
					local next_re = re.make_copy()
					if next_re.move_forward(dir) and next_re.rail == path.rails[i] then
						local signal = get_signals_from_last_rail(next_re, re, false)
						if signal and (signal.signal_state ~= defines.signal_state.reserved) then -- if theres a signal, only follow if it is reserved.
							return re
						end
						re = next_re
						re.move_to_segment_end()
						break
					end
				end
			end
		end
	end

	rendering.draw_circle({
		color = { 0, 1, 1 },
		width = 3,
		radius = 0.5,
		target = re.location.position,
		surface = re.rail.surface,
		time_to_live = 60,
	})
	return re
end
