# base4kids2-keepalived-scripts
[Keepalived](http://www.keepalived.org/) notify, alerts and check scripts for
[Base4Kids](http://www.base4kids.ch).

## Keepalived LDAP multi-master check
The [`keepalived-check-ldap.sh`](libexec/keepalived-check-ldap.sh) script is
intended to be used together with an LDAP multi-master setup which resides
behind a common virtual IP address coordinated by Keepalived and VRRP.

It tries to bind to an LDAP service and modifies a certain attribute in order
to check if the service is available. It returns 0 on success or a non-zero
exit status on failures, so it can be easily integrated as a Keepalived
tracking script.

The script needs to be installed on all LDAP multi-master systems and
referenced by the local Keepalived. It was tested on a [389
directory](https://directory.fedoraproject.org/) multi-master setup.

A dedicated service user will be used to bind to the directory and perform the
periodic LDAP modify operations. Every LDAP master has a dedicated LDAP leaf
entry corresponding to its hostname, such as:
* `cn=keepalived-ldap-01,ou=Monitoring,dc=example,dc=com`
* `cn=keepalived-ldap-02,ou=Monitoring,dc=example,dc=com`

On the above entries the `description` attribute (by default) will be change to
the following value:
`<SCRIPT-NAME>: Last update from <HOSTNAME> on <YYYY>-<MM>-<DD>T<HH>:<MM>:<SS>+00:00`.

In case the `ldapmodify` operation fails, Keepalived will remove a possible
active VRRP virtual IP from this host.

## Usage
### General usage instructions
To use the keepalived scripts, install [Keepalived](http://www.keepalived.org/)
from your distribution's package repository (or build it from source), clone
this repository and use the provided [Makefile](Makefile) to configure and
install the files. It is assumed, that you already have a working LDAP
multi-master setup up and running.
```bash
# install keepalived (example for RedHat/CentOS based systems)
yum install keepalived

# Clone the repository (either via HTTPS or SSH)
git clone https://github.com/adfinis-sygroup/base4kids2-keepalived-scripts.git
git clone git@github.com:adfinis-sygroup/base4kids2-keepalived-scripts.git

# Install the provided scripts and configuration
cd base4kids2-keepalived-scripts
make install prefix=/usr sysconfdir=/etc

# If you don't feel comfortable to install directly into /usr, make sure to
# install at least the scripts into the Keepalived libexec folder (this will
# ensure, that possible SELinux contexts will be applied correctly).
cd base4kids2-keepalived-scripts
make install keepalivedlibexecdir=/usr/libexec/keepalived
```

### Usage instructions for Keepalived LDAP multi-master check
Follow the general usage instructions above. Afterwards, you will have to
create an LDAP service user as well as the basic DIT structure required for the
service check.

The following example LDIFs are provided, you need to modify them to suite your
environment.
* [`keepalived-service-user.ldif`](share/keepalived-service-user.ldif)
* [`keepalived-check-ldap.ldif`](share/keepalived-check-ldap.ldif)

Those were also installed and are available at
`<PREFIX>/share/base4kids2-keepalived-scripts`.

Create the service user:
```bash
# Modify the service user LDIF to suite your environment (DN and userPassword)
vi share/keepalived-service-user.ldif

# Load the LDIF (adapt the bind DN and LDAP URI)
ldapadd -f share/keepalived-service-user.ldif \
        -x \
        -D "cn=Directory Manager" \
        -W \
        -H ldaps://ldap-01.example.com
```

Create the basis entries for the check script:
```bash
# Modify the keepalived check ldap LDIF to suite your environment (DN and
# hostnames for all LDAP multi master hosts)
vi share/keepalived-check-ldap.ldif

# Load the LDIF (adapt the bind DN and LDAP URI)
ldapadd -f share/keepalived-check-ldap.ldif \
        -x \
        -D "cn=Directory Manager" \
        -W \
        -H ldaps://ldap-01.example.com
```

Write the LDAP service user's password to the LDAP passwd file (make sure that
there is no trailing newline).
```bash
echo -n "changeme" > <PREFIX>/etc/keepalived-check-ldap.passwd
```

Configure Keepalived to include the script on all nodes (make sure to adapt the
host names, interface, IP addresses and VRRP secret accordingly).
```bash
vi /etc/keepalived/keepalived.conf
```
```
vrrp_script check_simple_ip_failover {
  script "/usr/libexec/keepalived/keepalived-check-ldap.sh -b dc=example,dc=com -H ldaps://ldap-01.example.com" 
  interval 15
  fall 2
  rise 2
}

vrrp_instance VI_1 {
  state MASTER
  interface ens33
  virtual_router_id 34
  priority 100
  advert_int 1
  authentication {
    auth_type PASS
    auth_pass MY-VRRP-SECRET
  }

  unicast_src_ip 192.168.0.11
  unicast_peer {
    192.168.0.12
  }
    

  virtual_ipaddress {
    192.168.0.10/24
  }
  track_script {
   check_simple_ip_failover
  }
}
```

Restart Keepalived:
```bash
systemctl restart keepalived.service
journalctl -f -u keepalived.service
```

Script usage:
```bash
./libexec/keepalived-check-ldap.sh -h
```
```
Usage: keepalived-check-ldap.sh [-a ATTRIBUTE] [-b LDAPBASEDN] [-D LDAPBASEDN]
                                [-H LDAPURI] [-p PASSWDFILE] [-k CHECKDN] [-dhv]

    -a ATTRIBUTE    The LDAP attribute to read or update during the check,
                    defaults to 'description'
    -b LDAPBASEDN   The LDAP base DN to use as a suffix for DN buildings,
                    defaults to 'dc=example,dc=com'
    -D LDAPBINDDN   The LDAP bind DN to use, defaults to
                    'uid=keepalived-service,ou=Special Users,dc=example,dc=com'
    -H LDAPURI      The LDAP URI of the LDAP server, defaults to
                    'ldap://localhost:389'
    -d              Enable debug messages
    -p PASSWDFILE   The LDAP passwd file to use, defaults to
                    '/etc/keepalived-check-ldap.passwd'
    -k CHECKDN      The DN of the Keepalived check related LDAP leaf entry,
                    defaults to 'cn=keepalived-ldap-01,ou=Monitoring,dc=example,dc=com'
    -h              Display this help and exit
    -v              Display the version and exit

Note, that all options are also overridable via environment variables.

The bind password is expected within the PASSWDFILE (-p). Reading the bind
password from a file, rather than passing it via an input option, prevents the
password from beeing exposed to other processes or users.
```

## License
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by the
Free Software Foundation, version 3 of the License.

## Copyright
Copyright (c) 2019 [Adfinis SyGroup AG](https://adfinis-sygroup.ch)
