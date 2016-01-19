# 
# Cookbook Name:: encrypted_blockdevice
# Attributes:: default
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

# The [:encrypted_blockdevices] key is used to create the encrypted block devices themselves from attributes, see examples in the README. We recalculate the hash each run.
default[:encrypted_blockdevices] = Hash.new

# The [:encrypted_blockdevice] key is used for settings - don't confuse this with the one above.

# The default keystore's name
default[:encrypted_blockdevice][:keystore_databag_name] = "encrypted_blockdevice_keystore"

# The following attributes are good for debian and ubuntu - they are provided for extension to other distros.
default[:encrypted_blockdevice][:cryptsetup_package] = "cryptsetup"
default[:encrypted_blockdevice][:cryptdisks_service] = "cryptdisks"
