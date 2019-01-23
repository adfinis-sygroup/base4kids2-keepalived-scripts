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
# The script expects the LDAP server, base DN and binding information within a
# LDAP configuration file according to LDAP.CONF(5). The bind password is
# expected within an LDAP passwd file for simple authentication. The path to
# both files can be changed from their default values if needed, either by
# environment variables or script options.
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


###
# LDAP related settings
#
# The LDAP configuration file to use
# See LDAP.CONF(5)
ldapConfigDefault="${confDir}/check-ldap.ldaprc"
ldapConfig="${LDAPCONF:-${ldapConfigDefault}}"

# The LDAP passwd file to use
# This file contains the bind password for simple authentication
ldapPasswdFileDefault="${confDir}/check-ldap.passwd"
ldapPasswdFile="${CHECK_LDAP_PASSWDFILE:-${ldapPasswdFileDefault}}"

# The relative base DN of the check related LDAP leaf entry
ldapRdnDefault="cn=keepalived-$(hostname --short)"
ldapRdn="${CHECK_LDAP_RDN:-${ldapRdnDefault}}"

# The attribute to read or update during the check
ldapAttributeDefault="description"
ldapAttribute="${CHECK_LDAP_ATTRIBUTE:-${ldapAttributeDefault}}"


##
# Private variables, do not overwrite them
#
# Script Version

_VERSION="0.1.0"


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

    for optionName in a c d p h r v; do
        optionFlags[${optionName}]=false
    done

    # Set default action (there is only one at the moment)
    action="CheckLdap"

    while getopts ":a:c:p:r:dhv" option; do
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

            c )
                # The LDAP configuration file to use
                # File path validation happens later on
                ldapConfig="${OPTARG}"
                debugMsg "ldapConfig set to: '${ldapConfig}'"
            ;;

            p )
                # The LDAP passwd file to use
                # File path validation happens later on
                ldapPasswdFile="${OPTARG}"
                debugMsg "ldapPasswdFile set to: '${ldapPasswdFile}'"
            ;;

            r )
                # The relative base DN of the check related LDAP leaf entry 
                # Cheap RDN validation
                if ! [[ "${OPTARG}" =~ ^[[:alnum:]]+=[[:print:]]+$ ]]
                then
                    dieMsg "Invalid relative LDAP DN specified"
                fi

                ldapRdn="${OPTARG}"
                debugMsg "ldapRdn set to: '${ldapRdn}'"
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

    test -r "${ldapConfig}" || \
    dieMsg "Non-existent or unreadable LDAP config '${ldapConfig}'"

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

Usage: $( basename "$0" ) [-a ATTRIBUTE] [-c LDAPCONF] [-p PASSWDFILE]
                          [-r RDN] [-dhv]

    -a ATTRIBUTE    The LDAP attribute to read or update during the check
                    defaults to '${ldapAttributeDefault}'
    -c LDAPCONF     The LDAP configuration file to use, defaults to
                    '${ldapConfigDefault}'
    -d              Enable debug messages
    -p PASSWDFILE   The LDAP passwd file to use, defaults to
                    '${ldapPasswdFileDefault}'
    -r RDN          The relative base DN of the check related LDAP leaf entry
                    defaults to '${ldapRdnDefault}'
    -h              Display this help and exit
    -v              Display the version and exit

Note, that the LDAPCONF (-c) file must be in the format of LDAPCONF(5) with at
least the following configuration options set: URI, BASE and BINDDN.

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
    local hostName="$(hostname --short)"
    local utcDateTime="$(date --utc --iso-8601="seconds")"

    local ldapValue="${scriptName}: Last update from ${hostName} on ${utcDateTime}"
    debugMsg "Modifying LDAP attribute '${ldapAttribute}': ${ldapValue}"

    [ "$DEBUG" = "yes" ] && ldapDebugOpt="-d -1 -vvv"

    ldapmodify ${ldapDebugOpt} -x -y "${ldapPasswdFile}" << EO_LDIF
dn: ${ldapRdn}
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
