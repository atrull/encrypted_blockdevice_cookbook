# 
# Cookbook Name:: encrypted_blockdevice
# Attributes:: default
#
# Copyright 2013, Alex Trull
# Copyright 2013, Medidata Worldwide    
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,  
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# This is used to create the encrypted block devices themselves, see examples in the README.
default[:encrypted_blockdevices] = Hash.new

# the [:encrypted_blockdevice] key is used for settings.

# Does this even matter ? 
# If the last encrypted_blockdevice is removed, setting this true will uninstall cryptsetup
default[:encrypted_blockdevice][:uninstall_cryptsetup_iflast] = false

# Is this even necessary ? Whatever happened to paths in the environment "lol" ?
# Path to the cryptdisks_start and cryptdisks_stop files
default[:encrypted_blockdevice][:cryptdisks_path] = "/sbin" unless node.platform?("ubuntu")
default[:encrypted_blockdevice][:cryptdisks_path] = "/usr/sbin" if node.platform?("ubuntu")
default[:encrypted_blockdevice][:cryptdisks_start] = "#{node[:encrypted_blockdevice][:cryptdisks_path]}/cryptdisks_start"
default[:encrypted_blockdevice][:cryptdisks_stop] = "#{node[:encrypted_blockdevice][:cryptdisks_path]}/cryptdisks_stop"
