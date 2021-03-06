#
# Cookbook Name:: storm
# Recipe:: default
# 

package "zip"
include_recipe "maven"

group node["storm"]["group"]

user node["storm"]["user"] do
	gid node["storm"]["group"]
end

ark "storm" do
	version node["storm"]["version"]
	url node["storm"]["download_url"]
	checksum node["storm"]["checksum"]
	home_dir node["storm"]["home_dir"]
	action :install
end

directory ::File.join(node['storm']['home_dir'], "storm-#{node["storm"]["version"]}") do
	owner node["storm"]["user"]
	group node["storm"]["group"]
	recursive true
end

execute "delete log and conf dirs" do
	command "rm -rf logs conf"
	cwd ::File.join(node["storm"]["home_dir"], "storm-#{node["storm"]["version"]}")
	not_if { %w(logs conf).inject(true) { |a, dir| a and
		::File.symlink?(::File.join(node["storm"]["home_dir"], "storm-#{node["storm"]["version"]}", dir))}}
end

[node["storm"]["local_dir"], node["storm"]["log_dir"]].each do |dir|
	directory dir do
		owner node["storm"]["user"]
		group node["storm"]["group"]
		mode 00755
		action :create
	end
end

directory node["storm"]["conf_dir"] do
	mode 00755
	action :create
end

link ::File.join(node["storm"]["home_dir"], "storm-#{node["storm"]["version"]}", "conf") do
	to node["storm"]["conf_dir"]
end

link ::File.join(node["storm"]["home_dir"], "storm-#{node["storm"]["version"]}", "logs") do
	to node["storm"]["log_dir"]
end

if Chef::Config[:solo]
	Chef::Log.warn "Chef solo does not support search, assuming Zookeeper, Nimbus and if set then drpc are on this node"
	nimbus = node
	zk_nodes = [node]
	if node['storm']['drpc']['switch'] 
		drpc_servers = [node]
	end
else
	nimbus = if node.recipe? "storm::nimbus"
		node
	else
		nimbus_nodes = search(:node, "recipes:storm\\:\\:nimbus AND storm_cluster_name:#{node["storm"]["cluster_name"]} AND chef_environment:#{node.chef_environment}")
		raise RuntimeError, "Nimbus node not found" if nimbus_nodes.empty?
		nimbus_nodes.sort{|a, b| a.name <=> b.name}.first
	end
	zk_nodes = search(:node, "zookeeper_cluster_name:#{node["storm"]["zookeeper"]["cluster_name"]} AND chef_environment:#{node.chef_environment}").sort{|a, b| a.name <=> b.name}
	raise RuntimeError, "No zookeeper nodes nodes found" if zk_nodes.empty?
	raise RuntimeError, "This script will not work with chef client and drpc servers." if node['storm']['drpc']['switch']
end

template ::File.join(node["storm"]["conf_dir"], "storm.yaml") do
	mode 00644
	variables :zookeeper_nodes => zk_nodes, :nimbus => nimbus, :drpc_servers => drpc_servers
end
