# == Define: openvpn::client
#
# This define creates the client certs for a specified openvpn server as well
# as creating a tarball that can be directly imported into openvpn clients
#
#
# === Parameters
#
# [*server*]
#   String.  Name of the corresponding openvpn endpoint
#   Required
#
# [*compression*]
#   String.  Which compression algorithim to use
#   Default: comp-lzo
#   Options: comp-lzo or '' (disable compression)
#
# [*dev*]
#   String.  Device method
#   Default: tun
#   Options: tun (routed connections), tap (bridged connections)
#
# [*mute*]
#   Integer.  Set log mute level
#   Default: 20
#
# [*mute_replay_warnings*]
#   Boolean.  Silence duplicate packet warnings (common on wireless networks)
#   Default: true
#
# [*nobind*]
#   Boolean.  Whether or not to bind to a specific port number
#   Default: true
#
# [*persist_key*]
#   Boolean.  Try to retain access to resources that may be unavailable
#     because of privilege downgrades
#   Default: true
#
# [*persist_tun*]
#   Boolean.  Try to retain access to resources that may be unavailable
#     because of privilege downgrades
#   Default: true
#
# [*port*]
#   Integer.  The port the openvpn server service is running on
#   Default: 1194
#
# [*proto*]
#   String.  What IP protocol is being used.
#   Default: tcp
#   Options: tcp or udp
#
# [*remote_host*]
#   String.  The IP or hostname of the openvpn server service
#   Default: FQDN
#
# [*resolv_retry*]
#   Integer/String. How many seconds should the openvpn client try to resolve
#     the server's hostname
#   Default: infinite
#   Options: Integer or infinite
#
# [*verb*]
#   Integer.  Level of logging verbosity
#   Default: 3
#
# [*pam*]
#   DEPRECATED: Boolean, Enable/Disable.
#
# [*authuserpass*]
#   Boolean. Set if username and password required
#   Default: false
#
# === Examples
#
#   openvpn::client {
#     'my_user':
#       server      => 'contractors',
#       remote_host => 'vpn.mycompany.com'
#    }
#
# * Removal:
#     Manual process right now, todo for the future
#
#
# === Authors
#
# * Raffael Schmid <mailto:raffael@yux.ch>
# * John Kinsella <mailto:jlkinsel@gmail.com>
# * Justin Lambert <mailto:jlambert@letsevenup.com>
#
# === License
#
# Copyright 2013 Raffael Schmid, <raffael@yux.ch>
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
define openvpn::client(
  $server,
  $compression          = 'comp-lzo',
  $dev                  = 'tun',
  $mute                 = '20',
  $mute_replay_warnings = true,
  $nobind               = true,
  $persist_key          = true,
  $persist_tun          = true,
  $port                 = '1194',
  $proto                = 'tcp',
  $remote_host          = $::fqdn,
  $resolv_retry         = 'infinite',
  $verb                 = '3',
  $pam                  = false,
  $authuserpass         = false,
) {

  if $pam {
    warning('Using $pam is deprecated. Use $authuserpass instead!')
  }

  Openvpn::Server[$server] ->
  Openvpn::Client[$title]

  exec {
    "generate certificate for ${title} in context of ${server}":
      command  => ". ./vars && ./pkitool ${title}",
      cwd      => "/etc/openvpn/${server}/easy-rsa",
      creates  => "/etc/openvpn/${server}/easy-rsa/keys/${title}.crt",
      provider => 'shell';
  }

  file {
    [ "/etc/openvpn/${server}/download-configs/${title}",
      "/etc/openvpn/${server}/download-configs/${title}/keys"]:
        ensure  => directory;

    "/etc/openvpn/${server}/download-configs/${title}/keys/${title}.crt":
      ensure  => link,
      target  => "/etc/openvpn/${server}/easy-rsa/keys/${title}.crt",
      require => Exec["generate certificate for ${title} in context of ${server}"];

    "/etc/openvpn/${server}/download-configs/${title}/keys/${title}.key":
      ensure  => link,
      target  => "/etc/openvpn/${server}/easy-rsa/keys/${title}.key",
      require => Exec["generate certificate for ${title} in context of ${server}"];

    "/etc/openvpn/${server}/download-configs/${title}/keys/ca.crt":
      ensure  => link,
      target  => "/etc/openvpn/${server}/easy-rsa/keys/ca.crt",
      require => Exec["generate certificate for ${title} in context of ${server}"];

    "/etc/openvpn/${server}/download-configs/${title}/${title}.conf":
      owner   => root,
      group   => root,
      mode    => '0644',
      content => template('openvpn/client.erb'),
      notify  => Exec["tar the thing ${server} with ${title}"];
  }

  exec {
    "tar the thing ${server} with ${title}":
      cwd         => "/etc/openvpn/${server}/download-configs/",
      command     => "/bin/rm ${title}.tar.gz; tar --exclude=\\*.conf.d -chzvf ${title}.tar.gz ${title}",
      refreshonly => true,
      subscribe   => [  File["/etc/openvpn/${server}/download-configs/${title}/${title}.conf"],
                        File["/etc/openvpn/${server}/download-configs/${title}/keys/ca.crt"],
                        File["/etc/openvpn/${server}/download-configs/${title}/keys/${title}.key"],
                        File["/etc/openvpn/${server}/download-configs/${title}/keys/${title}.crt"]
                      ],
      notify      => Exec["generate ${title}.ovpn in ${server}"];
  }

  exec { 
    "tar the thing ${server} with ${title} as tblk":
      cwd         => "/etc/openvpn/${server}/download-configs/",
      command     => "/bin/rm ${title}_tblk.tar.gz; tar --exclude=\\*.conf.d --transform=\'s#${title}#${title}.tblk#\' -chzvf ${title}_tblk.tar.gz ${title}",
      refreshonly => true,
      subscribe   => [  File["/etc/openvpn/${server}/download-configs/${title}/${title}.conf"],
                        File["/etc/openvpn/${server}/download-configs/${title}/keys/ca.crt"],
                        File["/etc/openvpn/${server}/download-configs/${title}/keys/${title}.key"],
                        File["/etc/openvpn/${server}/download-configs/${title}/keys/${title}.crt"]
                      ],
      notify      => Exec["generate ${title}.ovpn in ${server}"];


  exec {
    "generate ${title}.ovpn in ${server}":
      cwd         => "/etc/openvpn/${server}/download-configs/",
      command     => "/bin/rm ${title}.ovpn; cat  ${title}/${title}.conf|perl -lne 'if(m|^ca keys/ca.crt|){ chomp(\$ca=`cat ${title}/keys/ca.crt`); print \"<ca>\n\$ca\n</ca>\"} elsif(m|^cert keys/${title}.crt|) { chomp(\$crt=`cat ${title}/keys/${title}.crt`); print \"<cert>\n\$crt\n</cert>\"} elsif(m|^key keys/${title}.key|){ chomp(\$key=`cat ${title}/keys/${title}.key`); print \"<key>\n\$key\n</key>\"} else { print} ' > ${title}.ovpn",
      refreshonly => true,
      subscribe   => [  File["/etc/openvpn/${server}/download-configs/${title}/${title}.conf"],
                        File["/etc/openvpn/${server}/download-configs/${title}/keys/ca.crt"],
                        File["/etc/openvpn/${server}/download-configs/${title}/keys/${title}.key"],
                        File["/etc/openvpn/${server}/download-configs/${title}/keys/${title}.crt"],
                      ],
  }

  file { "/etc/openvpn/${server}/download-configs/${title}.ovpn":
    mode    => '0400',
    require => Exec["generate ${title}.ovpn in ${server}"],
  }
}
