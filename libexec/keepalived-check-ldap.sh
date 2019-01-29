#!/bin/bash
################################################################################
# keepalived-check-ldap.sh - Checks if an LDAP service is available
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
#
# Description:
# This script is intended to be used together with Keepalived as a VRRP
# tracking script. It tries to bind to an LDAP service and modifies a certain
# attribute in order to check if the service is available.
#
# It returns 0 on success or a non-zero exit status on failures.
#
# The script expects the LDAP URI, base DN and binding information to be passed
# by arguments or environment variables and uses sensitive defaults for all
# values. The bind password is expected within an LDAP passwd file for simple
# authentication.
#
# See also:
# http://www.keepalived.org/
# https://github.com/adfinis-sygroup/base4kids2-keepalived-scripts
#
# Usage:
# ./keepalived-check-ldap.sh
#
# See keepalived-check-ldap.sh -h for further options
#

# Enable pipefail:
# The return value of a pipeline is the value of the last (rightmost) command
# to exit with a non-zero status, or zero if all commands in the pipeline exit
# successfully.
set -o pipefail

# Check if all required external commands are available
for cmd in date \
           dirname \
           hostname \
           ldapmodify \
           ldapsearch \
           realpath
do
    command -v "${cmd}" >/dev/null 2>&1 || {
        echo >&2 "Missing command '${cmd}'"
        exit 1
    }

done


###
# Common settings
#
# The directory path to this script
scriptDir="$(dirname $(realpath "$0"))"

# The path to the configuration directory
confDir="$(realpath "${scriptDir}/../etc")"

# The short host name (without the domain suffix)
hostName="$(hostname --short)"


###
# LDAP related settings
#
# The URI of the LDAP server
# Overridable via input argument or LDAPURI env according to LDAP.CONF(5)
ldapUriDefault="ldap://localhost:389"
ldapUri="${LDAPURI:-${ldapUriDefault}}"

# The LDAP base DN to use
# Overridable via input argument or LDAPBASE env according to LDAP.CONF(5)
ldapBaseDefault="dc=example,dc=com"
ldapBase="${LDAPBASE:-${ldapBaseDefault}}"

# The LDAP bind DN to use
# Overridable via input argument or LDAPBINDDN env according to LDAP.CONF(5)
ldapBindDefault="uid=keepalived-service,ou=Special Users,${ldapBase}"
ldapBind="${LDAPBIND:-${ldapBindDefault}}"

# The LDAP passwd file to use
# This file contains the bind password for simple authentication
ldapPasswdFileDefault="${confDir}/keepalived-check-ldap.passwd"
ldapPasswdFile="${CHECK_LDAP_PASSWDFILE:-${ldapPasswdFileDefault}}"

# The DN of the Keepalived check related LDAP leaf entry
ldapKeepalivedDnDefault="cn=keepalived-${hostName},ou=Monitoring,${ldapBase}"
ldapKeepalivedDn="${CHECK_LDAP_KEEPALIVED_DN:-${ldapKeepalivedDnDefault}}"

# The attribute to read or update during the check
ldapAttributeDefault="description"
ldapAttribute="${CHECK_LDAP_ATTRIBUTE:-${ldapAttributeDefault}}"


# The LDAP network timeout (in seconds)
# Overridable via LDAPNETWORK_TIMEOUT env according to LDAP.CONF(5)
export LDAPNETWORK_TIMEOUT="${LDAPNETWORK_TIMEOUT:-"3"}"

# Timeout (in seconds) after which calls to LDAP APIs will abort if no response
# is received.
# Overridable via LDAPTIMEOUT env according to LDAP.CONF(5)
export LDAPTIMEOUT="${LDAPTIMEOUT:-"5"}"

# Checks to perform on server certificates in a TLS session
# Overridable via LDAPTLS_REQCERT env according to LDAP.CONF(5)
export LDAPTLS_REQCERT="${LDAPTLS_REQCERT:-"demand"}"


##
# Private variables, do not overwrite them
#
# Script Version

_VERSION="0.2.0"


##
# Helper functions
#

# Prints a debug message
#
# debugMsg MESSAGE
function debugMsg ()
{
    if [ "$DEBUG" = "yes" ]; then
        echo "[DEBUG] $1"
    fi
}


# Prints an info message
#
# infoMsg MESSAGE
function infoMsg ()
{
    echo "[INFO] $1"
}


# Prints an error message
#
# errorMsg MESSAGE
function errorMsg ()
{
    echo "[ERROR] $1" >&2
}


# Prints an error message and exists immediately with an non-zero exit code
#
# dieMsg MESSAGE
function dieMsg ()
{
    echo "[DIE] $1" >&2
    exit ${2:-1}
}

# Process all arguments passed to this script
#
# processArguments
function processArguments ()
{
    # Define all options as unset by default
    declare -A optionFlags

    for optionName in a b d D h H k p r v; do
        optionFlags[${optionName}]=false
    done

    # Set default action (there is only one at the moment)
    action="CheckLdap"

    while getopts ":a:b:D:H:k:p:r:dhv" option; do
        debugMsg "Processing option '${option}'"

        case "$option" in
            a )
                # The LDAP attribute to read or update during the check  
                if ! [[ "${OPTARG}" =~ ^[[:alnum:]]+$ ]]
                then
                    dieMsg "Invalid LDAP attribute specified"
                fi

                ldapAttribute="${OPTARG}"
                debugMsg "ldapAttribute set to: '${ldapAttribute}'"
            ;;

            b )
                # The base DN to be used
                # Cheap DN validation
                if ! [[ "${OPTARG}" =~ ^[[:alnum:]]+=[[:print:]]+$ ]]
                then
                    dieMsg "Invalid LDAP base DN specified"
                fi

                ldapBase="${OPTARG}"
                debugMsg "ldapBase set to: '${ldapBase}'"
            ;;

            D )
                # The Bind DN to be used
                # Cheap DN validation
                if ! [[ "${OPTARG}" =~ ^[[:alnum:]]+=[[:print:]]+$ ]]
                then
                    dieMsg "Invalid LDAP bind DN specified"
                fi

                ldapBind="${OPTARG}"
                debugMsg "ldapBind set to: '${ldapBind}'"
            ;;

            H )
                # The LDAP URI of the LDAP server
                # Cheap LDAP URI validation
                if ! [[ "${OPTARG}" =~ \
                    ^ldap(s|i)?://([[:alnum:]]|[[:punct:]])+$ ]]
                then
                    dieMsg "Invalid LDAP URI specified"
                fi

                ldapUri="${OPTARG}"
                debugMsg "ldapUri set to: '${ldapUri}'"
            ;;

            p )
                # The LDAP passwd file to use
                # File path validation happens later on
                ldapPasswdFile="${OPTARG}"
                debugMsg "ldapPasswdFile set to: '${ldapPasswdFile}'"
            ;;

            k )
                # The DN of the Keepalived check related LDAP leaf entry 
                # Cheap DN validation
                if ! [[ "${OPTARG}" =~ ^[[:alnum:]]+=[[:print:]]+$ ]]
                then
                    dieMsg "Invalid Keepalived check DN specified"
                fi

                ldapKeepalivedDn="${OPTARG}"
                debugMsg "ldapKeepalivedDn set to: '${ldapKeepalivedDn}'"
            ;;

            d )
                # Enable debug messages
                export DEBUG="yes"
                debugMsg "Enabling debug messages"
            ;;

            h )
                printUsage
                exit 0
            ;;

            v )
                printVersion
                exit 0
            ;;

            \? )
                errorMsg "Invalid option '-${OPTARG}' specified"
                printUsage
                exit 1
            ;;

            : )
                errorMsg "Missing argument for '-${OPTARG}'"
                printUsage
                exit 1
            ;;
        esac

        optionFlags[${option}]=true # Option was provided
    done

    test -r "${ldapPasswdFile}" || \
    dieMsg "Non-existent or unreadable LDAP passwd file '${ldapPasswdFile}'"

    debugMsg "Action: ${action}"
}

# Displays the help message
#
# printUsage
function printUsage ()
{
    cat << EOF

Usage: $( basename "$0" ) [-a ATTRIBUTE] [-b LDAPBASEDN] [-D LDAPBASEDN]
                                [-H LDAPURI] [-p PASSWDFILE] [-k CHECKDN] [-dhv]

    -a ATTRIBUTE    The LDAP attribute to read or update during the check,
                    defaults to '${ldapAttributeDefault}'
    -b LDAPBASEDN   The LDAP base DN to use as a suffix for DN buildings,
                    defaults to '${ldapBaseDefault}'
    -D LDAPBINDDN   The LDAP bind DN to use, defaults to
                    '${ldapBindDefault}'
    -H LDAPURI      The LDAP URI of the LDAP server, defaults to
                    '${ldapUri}'
    -d              Enable debug messages
    -p PASSWDFILE   The LDAP passwd file to use, defaults to
                    '${ldapPasswdFileDefault}'
    -k CHECKDN      The DN of the Keepalived check related LDAP leaf entry,
                    defaults to '${ldapKeepalivedDn}'
    -h              Display this help and exit
    -v              Display the version and exit

Note, that all options are also overridable via environment variables.

The bind password is expected within the PASSWDFILE (-p). Reading the bind
password from a file, rather than passing it via an input option, prevents the
password from beeing exposed to other processes or users.
EOF
}


# Displays the version of this script
#
# printVersion
function printVersion ()
{
    cat << EOF
Copyright (C) 2019 Adfinis SyGroup AG

$( basename "$0" ) ${_VERSION}

License AGPLv3: GNU Affero General Public License version 3
                https://www.gnu.org/licenses/agpl-3.0.html
EOF
}


# Checks if the LDAP service is available
#
# actionCheckLdap
actionCheckLdap ()
{
    local ldapModifyOpts="-x -y "${ldapPasswdFile}""
    local ldapDebugOpt=""

    local scriptName="$( basename "$0" )"
    local utcDateTime="$(date --utc --iso-8601="seconds")"

    local ldapValue="${scriptName}: Last update from ${hostName} on ${utcDateTime}"
    debugMsg "Modifying LDAP attribute '${ldapAttribute}': ${ldapValue}"
    [ "$DEBUG" = "yes" ] && ldapDebugOpt="-d -1 -vvv"

    ldapmodify ${ldapDebugOpt} \
               -x \
               -D "${ldapBind}" \
               -y "${ldapPasswdFile}" \
               -H "${ldapUri}" << EO_LDIF
dn: ${ldapKeepalivedDn}
changetype: modify
replace: ${ldapAttribute}
${ldapAttribute}: ${ldapValue}
-
EO_LDIF

    return $?
}


# The main function of this script
#
# Processes the passed command line options and arguments,
# checks the environment and calls the action.
#
# main $@
main() {
    processArguments "$@"

    # Uppercase the first letter of the action name and call the function
    action${action^}

    exit $?
}


# Calling the main function and passing all parameters to it
main "$@"
