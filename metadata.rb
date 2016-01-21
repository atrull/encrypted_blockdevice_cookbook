# 
# Cookbook Name:: encrypted_blockdevice
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

name             'encrypted_blockdevice'
maintainer       'Alex Trull'
maintainer_email 'encrypted_blockdevice.cookbooks.alex@trull.org'
license          'Apache v2.0'
description      'A cookbook and LWRPs to manage block device encryption, offering many options for different scenarios.'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '0.1.00'

%w/redhat centos xenserver ubuntu debian scientific amazon/.each do |os|
  supports os
end

depends 'chef-vault'

attribute'node[:encrypted_blockdevices]',
  :description => "Encrypted block devices to be created",
  :type => "hash",
  :required => "recommended"

