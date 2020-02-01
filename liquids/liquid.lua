--[[

	TechAge
	=======

	Copyright (C) 2019-2020 Joachim Stolberg

	GPL v3
	See LICENSE.txt for more information
	
	Liquid transportation API via Pipe(s) (peer, put, take)

]]--

local P2S = minetest.pos_to_string
local M = minetest.get_meta
local N = function(pos) return minetest.get_node(pos).name end
local LQD = function(pos) return (minetest.registered_nodes[techage.get_node_lvm(pos).name] or {}).liquid end
local Pipe = techage.LiquidPipe
local S = techage.S

local net_def = techage.networks.net_def
local networks = techage.networks

techage.liquid = {}

local LiquidDef = {}
local ContainerDef = {}

--
-- Networks
--

-- determine network ID (largest hash number of all pumps)
local function determine_netID(pos, outdir)
	local netID = 0
	networks.connection_walk(pos, outdir, Pipe, function(pos, indir, node)
		local ntype = net_def(pos, "pipe2").ntype
		if ntype and ntype == "pump" then
			local new = minetest.hash_node_position(pos) * 8 + outdir
			if netID <= new then
				netID = new
			end
		end
	end)
	return netID
end

-- store network ID on each pump like node
local function store_netID(pos, outdir, netID)
	networks.connection_walk(pos, outdir, Pipe, function(pos, indir, node)
		local ntype = net_def(pos, "pipe2").ntype
		if ntype and ntype == "pump" then
			local nvm = techage.get_nvm(pos)
			local outdir = networks.Flip[indir]
			nvm.pipe2 = nvm.pipe2 or {}
			nvm.pipe2.netIDs = nvm.pipe2.netIDs or {}
			nvm.pipe2.netIDs[outdir] = netID
		end
	end)
end

-- delete network and ID on each pump like node
local function delete_netID(pos, outdir)
	local netID = 0
	networks.connection_walk(pos, outdir, Pipe, function(pos, indir, node)
		local ntype = net_def(pos, "pipe2").ntype
		if ntype and ntype == "pump" then
			local nvm = techage.get_nvm(pos)
			local outdir = networks.Flip[indir]
			if nvm.pipe2 and nvm.pipe2.netIDs and nvm.pipe2.netIDs[outdir] then
				netID = nvm.pipe2.netIDs[outdir]
				nvm.pipe2.netIDs[outdir] = nil
			end
		end
	end)
	networks.delete_network("pipe2", netID)
end

local function get_netID(pos, outdir)
	local nvm = techage.get_nvm(pos)
	if not nvm.pipe2 or not nvm.pipe2.netIDs or not nvm.pipe2.netIDs[outdir] then
		local netID = determine_netID(pos, outdir)
		store_netID(pos, outdir, netID)
	end
	return nvm.pipe2 and nvm.pipe2.netIDs and nvm.pipe2.netIDs[outdir]
end

local function get_network_table(pos, outdir, ntype)
	local netID = get_netID(pos, outdir)
print(1)	
	if netID then
print(2)	
		local netw = networks.get_network("pipe2", netID)
		if not netw then
print(3)	
			netw = networks.collect_network_nodes(pos, outdir, Pipe)
			networks.set_network("pipe2", netID, netw)
		end
		print("netw", string.format("%012X", netID),  dump(netw))
		return netw[ntype] or {}
	end
print(4)	
	return {}
end


--
-- Client remote functions
--

-- Determine and return liquid 'name' from the
-- remote inventory.
function techage.liquid.peek(pos, outdir)
	for _,item in ipairs(get_network_table(pos, outdir, "tank")) do
		local liquid = LQD(item.pos)
		if liquid and liquid.peek then
			return liquid.peek(item.pos, item.indir)
		end
	end
end

-- Add given amount of liquid to the remote inventory.
-- return leftover amount
function techage.liquid.put(pos, outdir, name, amount, player_name)
	for _,item in ipairs(get_network_table(pos, outdir, "tank")) do
		local liquid = LQD(item.pos)
		if liquid and liquid.put and liquid.peek then
			-- wrong items?
			local peek = liquid.peek(item.pos, item.indir)
			if peek and peek ~= name then return amount or 0 end
			if player_name then
				local num = techage.get_node_number(pos) or "000"
				techage.mark_position(player_name, item.pos, "("..num..") put", "", 1)
			end
			amount = liquid.put(item.pos, item.indir, name, amount)
			if not amount or amount == 0 then break end
		end
	end
	return amount or 0
end

-- Take given amount of liquid for the remote inventory.
-- return taken amount and item name
function techage.liquid.take(pos, outdir, name, amount, player_name)
	local taken = 0
	local item_name = nil
	for _,item in ipairs(get_network_table(pos, outdir, "tank")) do
		local liquid = LQD(item.pos)
		if liquid and liquid.take then
			if player_name then
				local num = techage.get_node_number(pos)
				techage.mark_position(player_name, item.pos, "("..num..") take", "", 1)
			end
			local val, name = liquid.take(item.pos, item.indir, name, amount - taken)
			if val and name then
				taken = taken + val
				item_name = name
				if amount - taken == 0 then break end
			end
		end
	end
	return taken, item_name
end

--
-- Server local functions
--

function techage.liquid.srv_peek(pos, indir)
	local nvm = techage.get_nvm(pos)
	nvm.liquid = nvm.liquid or {}
	return nvm.liquid.name
end

function techage.liquid.srv_put(pos, indir, name, amount)
	local nvm = techage.get_nvm(pos)
	nvm.liquid = nvm.liquid or {}
	amount = amount or 0
	if not nvm.liquid.name then
		nvm.liquid.name = name
		nvm.liquid.amount = amount
		return 0
	elseif nvm.liquid.name == name then
		nvm.liquid.amount = nvm.liquid.amount or 0
		local capa = LQD(pos).capa
		if nvm.liquid.amount + amount <= capa then
			nvm.liquid.amount = nvm.liquid.amount + amount
			return 0
		else
			local rest = nvm.liquid.amount + amount - capa
			nvm.liquid.amount = capa
			return rest
		end
	end
	return amount
end

function techage.liquid.srv_take(pos, indir, name, amount)
	local nvm = techage.get_nvm(pos)
	nvm.liquid = nvm.liquid or {}
	amount = amount or 0
	if not name or nvm.liquid.name == name then
		name = nvm.liquid.name
		nvm.liquid.amount = nvm.liquid.amount or 0
		if nvm.liquid.amount > amount then
			nvm.liquid.amount = nvm.liquid.amount - amount
			return amount, name
		else 
			local rest = nvm.liquid.amount
			local name = nvm.liquid.name
			nvm.liquid.amount = 0
			nvm.liquid.name = nil
			return rest, name
		end
	end
	return 0
end

--
-- Further API functions
-- 

-- like: register_liquid("techage:ta3_barrel_oil", "techage:ta3_barrel_empty", 10, "techage:oil")
function techage.register_liquid(full_container, empty_container, container_size, inv_item)
	LiquidDef[full_container] = {container = empty_container, size = container_size, inv_item = inv_item}
	ContainerDef[empty_container] = ContainerDef[empty_container] or {}
	ContainerDef[empty_container][inv_item] = full_container
end

function techage.liquid.get_liquid_def(full_container)
	return LiquidDef[full_container]
end
	
function techage.liquid.is_container_empty(container_name)
	return ContainerDef[container_name]
end

function techage.liquid.get_full_container(empty_container, inv_item)
	return ContainerDef[empty_container] and ContainerDef[empty_container][inv_item]
end

-- To be called from each node via 'tubelib2_on_update2'
-- 'output' is optional and only needed for nodes with dedicated
-- pipe sides (e.g. pumps).
function techage.liquid.update_network(pos, outdir)
	networks.node_connections(pos, Pipe)
	delete_netID(pos, outdir)
end
