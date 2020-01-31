--[[

	TechAge
	=======

	Copyright (C) 2019 Joachim Stolberg

	GPL v3
	See LICENSE.txt for more information

	TA4 Streetlamp Solar Cell
	
]]--

-- for lazy programmers
local P = minetest.string_to_pos
local M = minetest.get_meta
local S = techage.S

local CYCLE_TIME = 2
local PWR_PERF = 1
local PWR_CAPA = 30 * 20 -- default day

minetest.after(2, function()
	-- calculate the capacity depending on the day duration
	PWR_CAPA = math.max(minetest.get_gametime() / minetest.get_day_count() / 2, PWR_CAPA)
end)

local Cable = techage.ElectricCable
local power = techage.power

local function node_timer(pos, elapsed)
	local nvm = techage.get_nvm(pos)
	nvm.capa = nvm.capa or 0
	pos.y = pos.y + 1
	local light = minetest.get_node_light(pos) or 0
	pos.y = pos.y - 1
	
	if light >= (minetest.LIGHT_MAX - 1) then
		if nvm.providing then
			power.generator_stop(pos, nvm)
			nvm.providing = false
			nvm.provided = 0
		end
		nvm.capa = math.min(nvm.capa + PWR_PERF * 1.2, PWR_CAPA)
	else
		if nvm.capa > 0 then
			if not nvm.providing then
				power.generator_start(pos, nvm, PWR_PERF)
				nvm.providing = true
			end
			nvm.provided = power.generator_alive(pos, nvm)
			nvm.capa = nvm.capa - nvm.provided
		else
			power.generator_stop(pos, nvm)
			nvm.providing = false
			nvm.provided = 0
			nvm.capa = 0
		end
	end
	return true
end

minetest.register_node("techage:ta4_solar_minicell", {
	description = S("TA4 Streetlamp Solar Cell"),
	tiles = {
		-- up, down, right, left, back, front
		"techage_solar_cell_mini_top.png",
		"techage_solar_cell_mini_bottom.png",
		"techage_solar_cell_mini_side.png",
	},
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {
			{-14/32, -8/32, -14/32,  14/32, -6/32, 14/32},
			{-7/32, -16/32, -7/32,  7/32, -8/32, 7/32},
		},
	},
	paramtype2 = "facedir",
	groups = {cracky=2, crumbly=2, choppy=2},
	is_ground_content = false,
	on_timer = node_timer,
})

techage.power.register_node({"techage:ta4_solar_minicell"}, {
	power_network  = Cable,
	conn_sides = {"D"},
	after_place_node = function(pos)
		local meta = minetest.get_meta(pos)
		local number = techage.add_node(pos, "techage:ta4_solar_minicell")
		meta:set_string("node_number", number)
		meta:set_string("infotext", S("TA4 Streetlamp Solar Cell").." "..number)
		local nvm = techage.get_nvm(pos)
		nvm.capa = 0
		nvm.providing = false
		minetest.get_node_timer(pos):start(CYCLE_TIME)
	end,
	
	after_dig_node = function(pos)
		techage.remove_node(pos)
		techage.del_mem(pos)
	end,
})

techage.register_node({"techage:ta4_solar_minicell"}, {	
	on_recv_message = function(pos, src, topic, payload)
		local nvm = techage.get_nvm(pos)
		if topic == "state" then
			if nvm.providing then
				return "discharging"
			elseif (nvm.capa or 0) > 0 then
				return "charging"
			else
				return "unused"
			end
		else
			return "unsupported"
		end
	end,
	on_node_load = function(pos)
		local meta = M(pos)
		local number = meta:get_string("number") or ""
		if number ~= "" then
			meta:set_string("node_number", number)
			meta:set_string("number", nil)
		end
	end,
})

minetest.register_craft({
	output = "techage:ta4_solar_minicell",
	recipe = {
		{"", "techage:ta4_wlanchip", ""},
		{"techage:ta4_silicon_wafer", "techage:ta4_silicon_wafer", "techage:ta4_silicon_wafer"},
		{"default:tin_ingot", "techage:iron_ingot", "default:copper_ingot"},
	},
})

