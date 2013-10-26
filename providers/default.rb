#
# Cookbook Name:: encrypted_blockdevice
# Provider:: default
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


def whyrun_supported?
  true
end


action :create do
  if @current_resource.exists
    Chef::Log.info "#{ @new_resource } already exists - nothing to do."
  else
    converge_by("Create #{ @new_resource }") do
      create_encrypted_blockdevice
    end
    new_resource.updated_by_last_action(true)
  end
end


action :delete do
  if @current_resource.exists
    converge_by("Delete #{ @new_resource }") do
      delete_encrypted_blockdevice
    end
    new_resource.updated_by_last_action(true)
  else
    Chef::Log.info "#{ @current_resource } doesn't exist - can't delete."
  end
end


def load_current_resource
  @current_resource = Chef::Resource::EncryptedBlockdevice.new(@new_resource.name)
  @current_resource.name(@new_resource.name)
  if encrypted_blockdevice_exists?(@current_resource.name)
    @current_resource.exists = true
  end
end    

#######################################################

def create_encrypted_blockdevice

  if @new_resource.file
    # We create the file idempotently
    create_backingfile(new_resource.file, new_resource.size, new_resource.sparse)
    device = @new_resource.file
  else
    # Otherwise we are dealing with a device.
    device = @new_resource.device
  end 

  # Two kinds of keystore - discard (no keystore) and local (local keystore) used crypttab.
  
  if ( @new_resource.keystore == "discard" || @new_resource.keystore == "local" )

    # We are going with crypttab style entries for these.

    if @new_resource.keystore == "discard"
      # Discard means we never record the key.
      keyfile = "/dev/urandom"
    else
      # Local means we create the keyfile idempotently - it may already exist.
      create_keyfile(keyfile, @new_resource.keylength)
      keyfile = @new_resource.keyfile
    end

    # verify that crypttab is present and secured (not everyone-readable?)
    file "/etc/crypttab" do
      owner "root"
      group "root"
      mode "0640"
      action :create_if_missing
    end

    # create entry in /etc/crypttab
    ruby_block "add_crypttab_#{new_resource.name}" do
      block do
        if ( !(encrypted_blockdevice_crypttab_exists?(new_resource.name)) )
          Chef::Log.info("#{new_resource.name} wasn't found in /etc/crypttab")
          encrypted_blockdevice_crypttab_add(new_resource.name, device, keyfile, new_resource.cipher)
        end
      end
      notifies :run, "execute[cryptdisks_start]", :immediately
    end
  
    # Provide service to notify, in order to reload crypttab
    execute "cryptdisks_start" do
      command "#{node[:encrypted_blockdevice][:cryptdisks_start]} #{new_resource.name}"
      action :nothing
    end

  elsif ( @new_resource.keystore == "encrypted_databag" || @new_resource.keystore == "databag" ) && ( ! ::File.exists?("/dev/mapper/#{new_resource.name}")  )
    
    # We should only get here if we're doing databag keystorage and there is no mapped device.

    # The item's name is deterministicaly for each host this cookbook provider is run on: nodename.blocklabel
    keystore_item_name = "#{node.name}-#{new_resource.name}".gsub(/\./, "-").gsub(/\//, "-")


    puts "Encrypted Blockdevices searching for keystore item #{keystore_item_name}"
    # We search for the items we expect in the bag we configured - just referencing them can cause a failure - 404 not found etc.
    keystore_item_result = search(:encrypted_blockdevice_keystore, "id:#{keystore_item_name}" ) 

    # If we can't find the item for the device we're creating, the results should be empty or nil.
    if ( keystore_item_result == nil || keystore_item_result.empty? )

      puts "We found no item #{keystore_item_name} so we shall attempt to create it"

      # This is probably the first run of this cookbook on this node
      # So we set about creating a key, creating a key and settings, opening the device and then saving the details to the keystore. 
      
      # We map to shorter attributes
      name = @new_resource.name
      device = device
      keylength = @new_resource.keylength
      cipher = @new_resource.cipher
      cryptsetup_args = @new_resource.cryptsetup_args
      # We generate a new key.
      key = `openssl rand -base64 #{@new_resource.keylength} | tr -d '\r\n'`

      # We pass the key without a newline to the cryptsetup command with the necessary arguments.
      # We should find a way to pipe this in without it showing it in ps auxww or any logs

      open_device=`echo -n #{key} | cryptsetup create #{name} #{device} --cipher #{cipher} --batch-mode --key-file=- #{cryptsetup_args}`

      # Then flesh out the databag of the used settings and key for the keystore - rather useful after a reboot.
      new_deviceitem = {
        "id" => keystore_item_name,
        "name" => name,
        "device" => device,
        "keylength" => keylength,
        "cipher" => cipher,
        "cryptsetup_args" => cryptsetup_args,
        "key" => key
      }

      puts "Saving #{keystore_item_name}"
      # Since we have two modes of databag storage, we have a minor divergence in behaviour - both save the settings/key to the keystore. 
      if @new_resource.keystore == "encrypted_databag"
        # Encrypted databag item.
        deviceitem = Chef::EncryptedDataBagItem.new
        deviceitem.data_bag("encrypted_blockdevice_keystore")
        deviceitem.encrypt_data_bag_item(new_deviceitem)
        deviceitem.save 
      elsif @new_resource.keystore == "databag"
        # Unencrypted databag item.
        deviceitem = Chef::DataBagItem.new
        deviceitem.data_bag("encrypted_blockdevice_keystore")
        deviceitem.raw_data = new_deviceitem
        deviceitem.save
      end 
       
    else

      # Otherwise there is an item already, but no mapped device yet. We assume settings are correct for the device we have, so we use the old settings/key from the keystore to open the device.
      # We would expect to be here after a reboot.

      # We get our key from the bag
      if @new_resource.keystore == "encrypted_databag"
        existing_deviceitem = Chef::EncryptedDataBagItem.load("encrypted_blockdevice_keystore", keystore_item_name)
      elsif @new_resource.keystore == "databag"
        existing_deviceitem = data_bag_item "encrypted_blockdevice_keystore", keystore_item_name
      end

      # We map to shorter attributes
      name = existing_deviceitem["name"]
      device = existing_deviceitem["device"]
      keylength = existing_deviceitem["keylength"]
      cipher = existing_deviceitem["cipher"]
      cryptsetup_args = existing_deviceitem["cryptsetup_args"]
      key = existing_deviceitem["key"]

      # We pass the key without a newline to the cryptsetup command with the necessary arguments.
      # We should find a way to pipe this in without it showing it in ps auxww or any logs
     
      open_device=`echo -n #{key} | cryptsetup create #{name} #{device} --cipher #{cipher} --batch-mode --key-file=- #{cryptsetup_args}`      

    end
     
  end
 
end

def encrypted_blockdevice_crypttab_add(name, device, keyfile, cipher)
  # Append newline for the new encrypted_blockdevice to the /etc/crypttab
  newline = "#{name} \t#{device}\t#{keyfile} \tcipher=#{cipher},noearly\n"
  ::File.open("/etc/crypttab", "a") do |crypttab|
    crypttab.puts(newline)
  end
end

def create_keyfile(keyfile, keylength)
  # We make sure a directory exists for the file to live in.
#  directory ::File.dirname(keyfile) do
#    recursive true
#  end

  # Create file with the chef provider
  file keyfile do
    owner "root"
    group "root"
    mode "00600"
    action :create_if_missing
    only_if "which openssl"
    notifies :run, "execute[create-keyfile-contents]", :immediately
  end

  # Create the key's contents with openssl - we use base64 encoding and remove the garbage formatting.
  execute "create-keyfile-contents" do
    command "openssl rand -base64 #{keylength} | tr -d '\r\n' > #{keyfile}"
    only_if "which openssl"
    action :nothing
  end
end

def create_backingfile(file, size, sparse)
  # We make sure a directory exists for the file to live in.
  directory ::File.dirname(file) do
    recursive true
  end

  # create file for loop block device
  file file do
    owner "root"
    group "root"
    mode "00600"
    action :create_if_missing
    notifies :run, "execute[setfilesize]", :immediately
  end

  # We pick the file creation method
  if sparse
    # We default to speedy file creation.
    setfilesizecmd = "dd bs=1M count=0 seek=#{size} of=\"#{file}\""
  else
    # If not sparse we use zeros - this takes much longer.
    setfilesizecmd = "dd bs=1M count=#{size} if=/dev/zero of=\"#{file}\""
  end

  # Set file size for loop file
  execute "setfilesize" do
    command "#{setfilesizecmd}"
    action :nothing
  end
end

def delete_encrypted_blockdevice
  # Unmount and remove entry from fstab
  mount @new_resource.name do
    device "/dev/mapper/#{new_resource.name}"
    action [ :umount, :disable ]
  end
  
  # deactivate encrypted filesystem
  execute "remove-encrypted_blockdevice" do
    command "/sbin/cryptsetup remove #{new_resource.name}"       
    action :run      
  end
  
  # remove encrypted filesystem from crypttab
  ruby_block "delete_crypttab_#{new_resource.name}" do
    block do
      if ( encrypted_blockdevice_crypttab_exists?(new_resource.name) )
        encrypted_blockdevice_crypttab_delete(new_resource.name)
      end
    end
  end

  if @new_resource.file  
    # delete file for loop block device
    file @new_resource.file do
      action :delete
    end  
  end

  # Uninstall cryptsetup packages if configured to do so
  ruby_block "uninstall_cryptsetup" do
    block do
      uninstall_cryptfs if node[:encrypted_blockdevice][:uninstall_cryptsetup_iflast]
    end
  end
end


def uninstall_cryptfs
  # Scan for there non-blank, non-comment lines in crypttab
  ::File.readlines("/etc/crypttab").reverse_each do |line|
    if (!(line =~ /^#/ or line =~ /^\s*$/ ))
      Chef::Log.info("Not removing cryptsetup because crypttab contains encrypted volumes.")
      return
    end
  end

  # Didn't find any non-blank, non-comment lines in crypttab
  Chef::Log.info("Removing cryptsetup package because crypttab is empty.")
  package "cryptsetup" do
    action :remove
  end
  
  # Debian only uses the cryptsetup package, but Ubuntu has both.
  package "cryptsetup-bin" do
    action :remove
  end
end

def encrypted_blockdevice_exists?(name)
  # Return code of 0 only when the name exists and is active.
  return system("/sbin/cryptsetup status #{name}")
end


def encrypted_blockdevice_crypttab_exists?(name)
  # If crypttab doesn't exist, then we know #{name} isn't in it.
  if (! ::File.exists?( "/etc/crypttab" ))
    return false
  end
  
  # Scan through crypttab
  ::File.foreach("/etc/crypttab") do |line|
    # Return true if we find a line beginning with #{name}
    return true if ( line =~ /^#{name} / )
  end
  
  # Failed to find #{name} in crypttab
  return false
end


def encrypted_blockdevice_crypttab_delete(name)
  # contents will be a list of lines to _keep_ in the file when we rewrite it.
  contents = []
  ::File.readlines("/etc/crypttab").reverse_each do |line|
    if (!(line =~ /^#{name} / ))
      contents << line
    else
      # Skip copying the deleted encrypted_blockdevice into the contents array
      Chef::Log.info("#{@new_resource} is removed from crypttab")
    end
  end
  
  # Write out the contents array as lines in a new /etc/crypttab.
  ::File.open("/etc/crypttab", "w") do |crypttab|
    contents.reverse_each { |line| crypttab.puts line }
  end
end

