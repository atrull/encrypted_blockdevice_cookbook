# 
# Cookbook Name:: encrypted_blockdevice
# Recipe:: default
#
# Copyright 2013, Neil Schelly
# Copyright 2013, Dyn, Inc.    
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

# Install cryptsetup
package "#{node[:encrypted_blockdevice][:cryptsetup_package]}" do
  action [ :install, :upgrade ]
end

case node['platform_family']
when 'debian'

  # Ensure service is enabled and started.
  service "#{node[:encrypted_blockdevice][:cryptdisks_service]}" do
    action [ :enable, :start ]
  end

when 'rhel'

  # no init script on this platform

end

# We are using chef-vault for some functionality including encryption.
include_recipe 'chef-vault'

# Disabling what should be default behaviour, for now
# If we have contents at the default location, we try to make the encrypted_blockdevice with the LWRP.
encrypted_blockdevice_create_all_from_key "encrypted_blockdevices" do
  action :create
  not_if { node[:encrypted_blockdevices] == nil || node[:encrypted_blockdevices].empty? }
end

