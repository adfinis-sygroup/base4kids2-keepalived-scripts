################################################################################
# Makefile - Makefile for installing base4kids2-keepalived scripts
################################################################################
#
# Copyright (C) 2019 Adfinis SyGroup AG
#                    https://adfinis-sygroup.ch
#                    info@adfinis-sygroup.ch
#
# This program is free software: you can redistribute it and/or
# modify it under the terms of the GNU Affero General Public 
# License as published  by the Free Software Foundation, version
# 3 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public
# License  along with this program.
# If not, see <http://www.gnu.org/licenses/>.
#
# Please submit enhancements, bugfixes or comments via:
# https://github.com/adfinis-sygroup/base4kids2-keepalived-scripts
#
# Authors:
#  Christian Affolter <christian.affolter@adfinis-sygroup.ch>

PN = base4kids2-keepalived-scripts

# Standard commands according to
# https://www.gnu.org/software/make/manual/html_node/Makefile-Conventions.html
SHELL = /bin/sh
INSTALL = /usr/bin/install
INSTALL_PROGRAM = $(INSTALL)
INSTALL_DATA = $(INSTALL) -m 644

# Standard directories according to
# https://www.gnu.org/software/make/manual/html_node/Directory-Variables.html#Directory-Variables
prefix = /usr/local
exec_prefix = $(prefix)
bindir = $(exec_prefix)/bin
datarootdir = $(prefix)/share
datadir = $(datarootdir)
docrootdir = $(datarootdir)/doc
docdir = $(docrootdir)/$(PN)
sbindir = $(exec_prefix)/sbin
sysconfdir = $(prefix)/etc
libdir = $(exec_prefix)/lib
libexecdir = $(exec_prefix)/libexec
localstatedir = $(prefix)/var
runstatedir = $(localstatedir)/run

# libexecdir for Keepalived
keepalivedlibexecdir = $(libexecdir)/keepalived


.PHONY: all
all: keepalived-check-ldap

.PHONY: keepalived-check-ldap
keepalived-check-ldap:
	sed -e 's|^\(confDir\)=.*|\1=$(sysconfdir)|' \
		libexec/keepalived-check-ldap.sh > \
		libexec/keepalived-check-ldap.sh.tmp


.PHONY: installdirs
installdirs:
	$(INSTALL) --directory \
		$(DESTDIR)$(sysconfdir) \
		$(DESTDIR)$(docdir) \
		$(DESTDIR)$(keepalivedlibexecdir) \
		$(DESTDIR)$(datadir)/$(PN)


.PHONY: install
install: all installdirs
	$(INSTALL_PROGRAM) libexec/keepalived-check-ldap.sh.tmp \
		$(DESTDIR)$(keepalivedlibexecdir)/keepalived-check-ldap.sh
	
	$(INSTALL_PROGRAM) libexec/keepalived-check-process.sh \
		$(DESTDIR)$(keepalivedlibexecdir)/keepalived-check-process.sh
	
	$(INSTALL_DATA) share/* \
			$(DESTDIR)$(datadir)/$(PN)/
	
	$(INSTALL_DATA) README.md $(DESTDIR)$(docdir)/
	
	$(INSTALL) -m 600 etc/keepalived-check-ldap.passwd \
			$(DESTDIR)/$(sysconfdir)/


.PHONY: uninstall
uninstall:
	rm --force \
		$(DESTDIR)$(keepalivedlibexecdir)/keepalived-check-*.sh \
		$(DESTDIR)$(datadir)/$(PN)/* \
		$(DESTDIR)$(docdir)/README.md \
		$(DESTDIR)/$(sysconfdir)/keepalived-check-ldap.passwd
	
	rmdir --ignore-fail-on-non-empty \
		$(DESTDIR)$(keepalivedlibexecdir) \
		$(DESTDIR)$(libexecdir) \
		$(DESTDIR)$(docdir) \
		$(DESTDIR)$(docrootdir) \
		$(DESTDIR)$(datadir)/$(PN) \
		$(DESTDIR)$(datadir) \
		$(DESTDIR)$(sysconfdir) \
		$(DESTDIR)$(exec_prefix)
	
# Usually $(prefix) is equal to $(exec_prefix) which was already
# removed, test for the directory existence to prevent errors.		
	test -d $(DESTDIR)$(prefix) && \
		rmdir --ignore-fail-on-non-empty $(DESTDIR)$(exec_prefix) || \
		true

.PHONY: clean
clean:
	rm --force libexec/keepalived-check-ldap.sh.tmp
