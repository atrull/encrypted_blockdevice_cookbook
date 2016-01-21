#
# Cookbook Name:: encrypted_blockdevice
# Recipe:: example
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

# We are using chef-vault for some default behaviour.
include_recipe 'chef-vault'

# If we have contents at the default location, we try to make the encrypted_blockdevice with the LWRP.
encrypted_blockdevice_create_all_from_key "encrypted_blockdevices" do
  action :create
  not_if ( node[:encrypted_blockdevices] == nil || node[:encrypted_blockdevices].empty? )
end

# Maybe we want to use a different location key for the encrypted block devices ?

encrypted_blockdevice_create_all_from_key "my_little_encrypted_blockdevices" do
  action :create
  not_if ( node[:my_little_encrypted_blockdevices] == nil || node[:my_little_encrypted_blockdevices].empty? )
end

# Some examples using the encrypted_blockdevice provider directly:

# We don't make filesystems with the LWRPs in this cookbook, so we import the filesystem cookbook and use its default provider to do that for these examples.
include_recipe "filesystem"

# A simple local file - we will lose the key after a reboot, so you had better have redundant copies of the data elsewhere, like backups or other cluster members..
# But at least we know that the data will never survive machine termination/decomissioning.
encrypted_blockdevice "datacrypt" do
  size 512
  keystore discard
  file "/datacrypt.file"
end

# And a filesystem to go on top.
filesystem "datacrypt" do
  fstype ext4
  mount "/datacrypt"
end

# A device gets encrypted, using a key stored local to the machine, not that secure, but whatever floats your boat. Maybe your local disk or secrets folder is on a disk you know is watched over by an armed guard, with another armed guard to watch that armed guard ?
# Keys kept next to secrets means secrets are lost with ease.
encrypted_blockdevice "data2" do
  device "/dev/xvdd"
  keystore local
  keyfile "/etc/secrets/data2.key"
  keylength 2048
end

# And again a filesystem to sit on it.
filesystem "data2" do
  fstype ext3
  mount "/data2"
end

# A local raid device gets labelled "data3" - we store the key in a databag in the chef API. Maybe you trust the chef API to be your keystore ? Maybe. The device is only good if the key is recoverable, so deleting the key from the keystore denies attackers if they haven't comprimised the running machine.
encrypted_blockdevice "data3" do
  device "/dev/md0"
  keystore vault
  admins bob,janet
  keylength 4096
end

# If you use EC2 with Chef, I recommend checking that your encrypted databag key isn't sneaking back into the the chef API via Ohai's (excellent, if overzealous? I mean who needs the userdata? really, come on.) ec2 cloud plugin pulling the bootstrap userdata where some people happen to put the key.
# Why ? Keys shouldn't kept next to the secrets they protect.

# And derp, a filesystem go on it.
filesystem "data3" do
  # this device line is redundant, but kept for style.
  device "dev/mapper/data3"
  fstype xfs
  mount "/data3"
end
