Description
===========

This cookbook contains an LWRP to manage individual encrypted block devices using the cryptsetup package.

Additionaly it contains a LWRP to create one or more encrypted block devices according to override attributes instead of recipe contents.

There are two types of storage possible: device storage and file storage.

Both types of storage get mapped back to the name of the encrypted block device given.

When this cookbook is run by a recipe, the default behaviour is to attempt to create the encrypted block devices from the encrypted_blockdevices key/attributes. See the Usage section and example recipe for how to use this key, and a few options on the attributes.

There are four kinds of `keystore` available, giving differing levels of security and bootability:

* `discard` Provides a one-time use block device with a randomly-generated key kept in RAM. Data will not be recoverable after reboot or cryptdisks shutdown/restart.

* `vault` Stores the key for the block device in a vault-encrypted databag on the chef server. When the cookbook/chef runs after reboot, the block device will be decrypted and mounted.

* `databag` Stores the key for the block device in a normal databag on the chef server. When the cookbook/chef runs after reboot, the block device will be decrypted and mounted.

* `local` Stores a local (on the filesystem - such as /etc/secrets/device.key) randomly-generated key file. This will be mounted by the system using the crypttab on reboot.

These modes are ordered from most secure (and hard to recover) to least secure (and easily recoverable).

Keystore Caveats
================

* In `discard` mode you must be absolutely sure you can lose the local copy of the data - backups are absolutely critical in this mode.

* In `vault` and `databag` mode we will use the Chef API as a keystore - this means the data should be recoverable once chef has run after a reboot, unless the key is delete from the chef server.

You should create the "encrypted_blockdevice_keystore" databag so that items can be put into it by this cookbook. This databag's name is set in the cookbook attributes and can be changed, but the items are named according to a pattern based upon the node name and device. Your node names must always be uniquely generated to avoid collisions/key sharing !

* In `local` mode, the key is kept in a file on the local filesystem, if the key is available after reboot, the data should be recoverable without intervention before chef runs.

Conventional wisdom and Cryptographic common sense is that you should not keep the keys for secrets next to the secrets they protect, consequently a `local` keystore with `keyfile` is not recommended when your secrets are dangerous if compromised.

Other Caveats
=============

The author of this cookbook believes cookbooks should not overlap in behaviour or ability. Each cookbook should do one thing and do it well.

Consequently this cookbook explicitely does not create filesystems themselves - all it does is encrypt underlying blocks and present them at an unencrypted location for use - you should use the filesystem cookbook to make use of the unencrypted location.

We include some examples that combine this cookbook with the filesystem cookbook below.

Requirements
============

## Platform

* Ubuntu 12.04 (original dev target in 2013)
* Ubuntu 14.04 (dev target in 2016)
* Probably other recent distros with the same tools (rhel releases have been partly tested).

## Packages
* The cryptsetup package, by one name or another.
* Openssl for key generation.

## Special Chef Permissions (to get past the 403 permission denied on databag upload)
* knife acl add group clients containers data create,update,delete
* knife acl add client 'hostname1,hostname2' container clients read
* knife group add client 'hostname1,hostname2' admins

We do not call the package manager directly, but use the chef 'package' abstraction. Attributes are provided to manage the package and service name if they differ.

Main Attributes
===============

##### `encrypted_blockdevices`
Hash of encrypted_blockdevices to setup.
##### `node[:encrypted_blockdevices]` keys:
Each encrypted block device's key is the `label`: This explains each key in a filesystems entry. The label should probably not exceed 12 characters.

We also let you use your own top-level key if you want - see the default recipe and example recipes.

Cookbook Attributes:

##### `node[:encrypted_blockdevice][:keystore_databag_name]` = "encrypted_blockdevice_keystore"
The name of the encrypted blockdevice keystore to use, if the keystore is of the databag type.

##### `node[:encrypted_blockdevice][:cryptsetup_package]` = "cryptsetup"
##### `node[:encrypted_blockdevice][:cryptdisks_service]` = "cryptdisks"
The following attributes are good for debian and ubuntu - they are provided for extension to other distros.


Backing Location Options
========================

##### `device`
Path to the device to create the filesystem upon.
##### `file`
Path to the file-backed storage to be used for a loopback device. If the `file` is not present it will be created, a size is needed if you want to have a device larger than 100 Megabytes.

Keystore Options
================

##### `keystore` discard|vault|databag|local
Key store to use for creating the filesystem's key.
##### `admins` johnny,sarah
Chef admins of the vault keystore - only to be used with the vault keystore.. not databag.
##### `keyfile` /path/to/secret
File location to use for creating the filesystem's key in `local` keystore mode.

Encryption Options
==================

##### `keylength` the encryption key's length (default: 1024)
Used when the key is generated.
##### `cipher` the cipher to use. (default "aes-cbc-essiv:sha256")
Used when the filesystem is encrypted for us.

File Backing Options
====================

##### `size` 10000
The size in Megabytes, only used for `file` Backed storage.
##### `sparse` Boolean (default: true)
Sparse file creation, used by the `file` storage, by default we use this for speed, but you may not want that. Set to false in that case.

Other Options
=============

##### `cryptsetup_args` cryptsetup arguments to use. (default "create") - when not "create" we reverse the device/name order given to the cryptsetup command.
Can be used to specify additional or different arguments. Recent versions of cryptsetup this should be changed to "open -type type" where type is luks, plain, loopaes and tcrypt. See the cryptsetup man page.

Recipes
=======
## default
This recipe will install the package, start the service and make available in encrypted form any block devices found at the expected key (encrypted_blockdevices)

## example
This represents an example of creating a few small encrypted filesystems, or using the create_all_from_key LWRP on a different key information.

Usage: Direct Resource/Provider
===============================

    include_recipe "encrypted_blockdevice"

    encrypted_blockdevice "cryptfs" do
      size 1000
      file "/mnt/cryptfs.file"
      keystore "local"
      keyfile "/etc/secrets/cryptfs.key"
      action :create
    end

    include_recipe "filesystem"

    filesystem "cryptfs" do
      fstype "ext4"
      mount "/mnt/cryptfs"
      noenable true
    end

Usage: Attribute Key
====================

Runlist: `encrypted_blockdevice`

````JSON
{
  "encrypted_blockdevices": {
    "raidcrypt": {
      "device": "/dev/md0",
      "keystore": "vault",
      "admins" : "alex"
    },
    "local": {
      "file": "/local.file",
      "keystore": "local",
      "keyfile": "/etc/secrets/local.key",
      "size": 10000
    },
    "supersecret": {
      "file": "/mnt/notsparse.file",
      "sparse": false,
      "keystore": "discard",
      "size": 1000
    }
  }
}
````

Getting a usable filesystem
===========================

If you want filesystems, use the filesystem cookbook with the filesystems key:

Runlist: `encrypted_blockdevice, filesystem`

````JSON
{
  "encrypted_blockdevices": {
    "raidcrypt": {
      "device": "/dev/md0",
      "keystore": "vault",
      "admins" : "alex"
    }
  },
  "filesystems": {
    "raidcrypt": {
      "device": "/dev/mapper/raidcrypt",
      "fstype": "xfs",
      "mount": "/mnt"
    }
  }
}
````

Links
=====

* Cookbook Development
https://github.com/atrull/encrypted_blockdevice_cookbook

* Cryptsetup Development
http://code.google.com/p/cryptsetup/

License and Authors
===================
Author - Databag and Vault pieces and current mainainer:
Alex Trull (@AlexanderTrull) partly on behalf of Medidata Solutions.
Original Author/Sponsor: Neil Schelly (@neilschelly)
Copyright 2013, Dyn, Inc (@DynInc)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,  
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
