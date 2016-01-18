#
# Cookbook Name:: encrypted_blockdevice
# Resource:: default
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

actions :create, :delete
default_action :create

# This is the eventual name of the block device under /dev/mapper/
attribute :name, :kind_of => String, :name_attribute => true

# Our two types of backing storage.
attribute :device, :kind_of => String
attribute :file, :kind_of => String

# Cipher and Hash - sensible defaults.
attribute :cipher, :kind_of => String, :default => "aes-cbc-essiv:sha256"

# Attributes to support the file backed storage. False sparse means slower file creation/time to converge.
attribute :size, :kind_of => Fixnum, :default => 100
attribute :sparse, :kind_of => [ TrueClass, FalseClass ], :default => true

# Keystore must be specified, keyfile is optional, only meaningful for 'local' keystore.
attribute :keystore, :kind_of => String, :required => true
# Admins should be specified if we are using the vault keystore
attribute :admins, :kind_of => String
# Keyfile is used to indicate where the key is kept if the keystore is 'local'
attribute :keyfile, :kind_of => String
# Keylength is only used in local, databag and vault keystores.
attribute :keylength, :kind_of => Fixnum, :default => 1024

# Additional arguments, "create" by default, might be needed for edgecases just like yours.
attribute :cryptsetup_args, :kind_of => String, :default => "create"

attr_accessor :exists
