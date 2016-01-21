#
# Cookbook Name:: encrypted_blockdevice
# Provider:: default
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

  # We map some shorter attributes
  name = @new_resource.name
  cipher = @new_resource.cipher
  cryptsetup_args = @new_resource.cryptsetup_args

  if @new_resource.file
    # We create the file idempotently
    create_storagefile(new_resource.file, new_resource.size, new_resource.sparse)
    device = @new_resource.file
  else
    # Otherwise we are dealing with a device.
    device = @new_resource.device
  end

  # Ordering matters, depending on the argument given. See the cryptsetup documentation for further information.
  if @new_resource.cryptsetup_args =~ /create/
    # create uses the name then device order
    device_name_order = "#{name} #{device}"
  else
    # if we're not "create" (open, for instance) then we need the reverse order.
    device_name_order = "#{device} #{name}"
  end

  # discard (no keystore - just /dev/urandom)
  if ( @new_resource.keystore == "discard" )

    # We will read random bits from this for the key - the encrypted device will not survive reboot.
    keyfile = "/dev/urandom"

    # We call the cryptsetup command directly.
    `cryptsetup #{cryptsetup_args} #{device_name_order} --cipher #{cipher} --batch-mode --key-file=#{keyfile}`
    puts "Created #{name} and discarded the key"
    puts `cryptsetup status #{name}`

  elsif ( @new_resource.keystore == "local" )

    # We are going with crypttab style entries for the local key storage.

    # This is the only keystore supported at boot time, with or without network connectivity.

    # Local means we create the keyfile idempotently - it may already exist.
    keyfile = @new_resource.keyfile
    create_keyfile(keyfile, @new_resource.keylength)

    # verify that crypttab is present and secured (not everyone-readable, either)
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
      command "cryptdisks_start #{new_resource.name}"
      action :nothing
    end

  elsif ( @new_resource.keystore == "vault" || @new_resource.keystore == "databag" )

    # We should only get here if we're doing databag keystorage.

    # We will be using the cryptsetup command instead of the crypttab.

    # The item's name is deterministicaly for each host this cookbook provider is run on: nodename.blocklabel and periods and slashes cleaned up.
    keystore_item_name = "#{node.name}-#{new_resource.name}".gsub(/\./, "-").gsub(/\//, "-")

    # Our keystore databag name comes from attributes.
    keystore_databag_name = node[:encrypted_blockdevice][:keystore_databag_name]

    puts "Searching for keystore item #{keystore_item_name} in data bag #{keystore_databag_name}"
    # We search for the items we expect in the bag we configured - just referencing them can cause a failure - 404 not found etc.
    keystore_item_result = search(:"#{keystore_databag_name}", "id:#{keystore_item_name}" )

    # If we can't find the item for the device we're creating, the results should be empty or nil.
    if ( keystore_item_result == nil || keystore_item_result.empty? )

      # This is probably the first run of this cookbook on this node with this configured device.
      # So we set about creating a key, opening the device with the details we have and then saving the details to the keystore.

      # This is a new device - i.e. one for which we cannot find existing data, so we generate a new key.
      key = `openssl rand -hex #{@new_resource.keylength} | tr -d '\r\n'`

      puts "Generating #{@new_resource.keylength} byte key for #{name}"

      # We determine our 'keyfilesize' for --keyfile-size based on the 'keylength' in bytes doubled because the key is hex-encoded.
      keyfilesize = (new_resource.keylength * 2)

      # We flesh out the databag of the used settings and key for the keystore - rather useful after a reboot.
      new_deviceitem = {
        "id" => keystore_item_name,
        "name" => name,
        "device" => device,
        "cryptsetup_args" => cryptsetup_args,
        "keyfilesize" => keyfilesize,
        "cipher" => cipher,
        "key" => key
      }

      # Since we have two modes of databag storage, we have a minor divergence in behaviour - both save the settings/key to the keystore.
      if @new_resource.keystore == "vault"
        # We call chef-vault methods.

        vault_admins = @new_resource.admins

        puts "Encrypting device item for #{name}"

        chef_vault_secret "#{keystore_item_name}" do
          data_bag "#{keystore_databag_name}"
          raw_data(new_deviceitem)
          admins "#{vault_admins}"
          clients '*:*'
          search '*:*'
        end

      else
        # Unencrypted databag item.
        deviceitem = Chef::DataBagItem.new
        deviceitem.raw_data = new_deviceitem
        deviceitem.data_bag(keystore_databag_name)
        deviceitem.save
      end

      puts "Saved #{keystore_item_name} to keystore #{keystore_databag_name}"

      # We pass the key without a newline to the cryptsetup command with the necessary arguments.
      # We should find a way to pipe this in without it showing it in ps auxww or any logs.

      `echo -n #{key} | cryptsetup #{cryptsetup_args} #{device_name_order} --keyfile-size #{keyfilesize} --cipher #{cipher} --batch-mode --key-file=-`

      # Cryptsetup Status
      puts `cryptsetup status #{name}`

      # We probably created the device, so we go on to create the bag item.
      puts "created new device #{name}"


    else

      # Otherwise there is an item already, but no mapped device yet. We assume settings are correct for the device we have, so we use the old settings/key from the keystore to open the device.
      # We would expect to be here after a reboot.

      puts "Getting data from #{keystore_databag_name} for #{keystore_item_name}"
      # We get our key from the bag
      if @new_resource.keystore == "vault"
        existing_deviceitem = chef_vault_item(keystore_databag_name, keystore_item_name)
        puts "Decrypted device item for #{name}"
      else
        existing_deviceitem = data_bag_item keystore_databag_name, keystore_item_name
      end

      # We map to short attributes from the item.
      name = existing_deviceitem["name"]
      device = existing_deviceitem["device"]
      cryptsetup_args = existing_deviceitem["cryptsetup_args"]
      keyfilesize = existing_deviceitem["keyfilesize"]
      cipher = existing_deviceitem["cipher"]
      key = existing_deviceitem["key"]

      # We pass the key without a newline to the cryptsetup command with the necessary arguments.
      # We should find a way to pipe this in without it showing it in ps auxww or any logs.

      `echo -n #{key} | cryptsetup #{cryptsetup_args} #{device_name_order} --keyfile-size #{keyfilesize} --cipher #{cipher} --batch-mode --key-file=-`

      puts "Opened #{name}"
      puts `cryptsetup status #{name}`

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
  puts "Creating #{keyfile}"

  # We make sure a directory exists for the file to live in.
  directory ::File.dirname(keyfile) do
    recursive true
    mode "00700"
  end

  # Create file with the chef provider
  file keyfile do
    owner "root"
    group "root"
    mode "00600"
    action :create_if_missing
    notifies :run, "execute[create-keyfile-contents]", :immediately
  end

  # Create the key's contents with openssl - we use hex encoding and remove the garbage formatting.
  execute "create-keyfile-contents" do
    command "openssl rand -hex #{keylength} | tr -d '\r\n' > #{keyfile}"
    action :nothing
  end
end

def create_storagefile(file, size, sparse)
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
    notifies :run, "execute[growfiletosize]", :immediately
  end

  # We pick the file creation method
  if sparse
    # We default to speedy file creation.
    execute "growfiletosize" do
      command "dd bs=1M count=0 seek=#{size} of=#{file}"
      action :nothing
    end
  else
    # If not sparse we use zeros - this takes much longer.
    execute "growfiletosize" do
      command "dd bs=1M count=#{size} if=/dev/zero of=#{file}"
      action :nothing
    end
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
