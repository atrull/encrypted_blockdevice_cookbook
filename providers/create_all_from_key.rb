#
# Cookbook Name:: encrypted_blockdevice
# Provider:: create_all_from_key
#
# Copyright 2013 Alex Trull
# Copyright 2013 Medidata Worldwide
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

action :create do

  # Our key is the new resource name or if not provided, not we go with "encrypted_blockdevices"
  key = @new_resource.name || "encrypted_blockdevices"

  # We get our encrypted_blockdevice from the key in node data
  encrypted_blockdevices_to_be_created = node[key]

  # For reach filesystem we want to make, we enter the main creation loop of calling the default filesystem provider.
  encrypted_blockdevices_to_be_created.each_key do |label|

    eb = encrypted_blockdevices_to_be_created[label]

    # We pass all possible arguments to the lwrp that encrypts the blockdevice.
    encrypted_blockdevice label do

      device eb["device"] if eb["device"]
      file eb["file"] if eb["file"]
      cipher eb["cipher"] if eb["cipher"]
      size eb["size"] if eb["size"]
      sparse eb["sparse"] if eb["sparse"]
      keystore eb["keystore"] if eb["keystore"]
      admins eb["admins"] if eb["admins"]
      keyfile eb["keyfile"] if eb["keyfile"]
      keylength eb["keylength"] if eb["keylength"]
      cryptsetup_args eb["cryptsetup_args"] if eb["cryptsetup_args"]
      action [:create]

    end

  end

  new_resource.updated_by_last_action(true)
end
