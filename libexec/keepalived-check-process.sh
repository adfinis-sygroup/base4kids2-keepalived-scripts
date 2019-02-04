#!/bin/bash
################################################################################
# keepalived-check-process.sh - Checks acess to a PID
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
#  Andreas Gruhler <andreas.gruhler@adfinis-sygroup.ch>
#
# Description:
# This script is intended to be used together with Keepalived as a
# VRRP tracking script. It checks the access to a process by means 
# of a SIGNULL (NULL) 'signal'. No actual signal is sent but it is 
# checked if the caller would be allowed to send a signal and if 
# the process exists, see 'man 2 kill'.
# 
# It returns 0 on success or a non-zero exit status on failures.
# 
# The script expects the name of the process or service to perform
# the check on to be passed by argument or environment variable.
#
# See also:
# http://www.keepalived.org/
# https://github.com/adfinis-sygroup/base4kids2-keepalived-scripts
#
# Usage:
# ./keepalived-check-process.sh KEEPALIVED_CHECK_PROCESS_NAME
#
# See keepalived-check-process.sh -h for further options
#

# Enable pipefail:
# The return value of a pipeline is the value of the last (rightmost) command
# to exit with a non-zero status, or zero if all commands in the pipeline exit
# successfully.
set -o pipefail

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

    for optionName in d h v; do
        optionFlags[${optionName}]=false
    done

    # Set default action
    action="CheckProcess"

    while getopts ":dhv" option; do
        debugMsg "Processing option '${option}'"

        case "$option" in
            d )
                # Enable debug messages
                export DEBUG="yes"
                debugMsg "Enabling debug messages"
            ;;

            h )
                action="PrintUsage"
            ;;

            v )
                action="PrintVersion"
            ;;

            \? )
                errorMsg "Invalid option '-${OPTARG}' specified"
                action="PrintUsageWithError"
            ;;

            : )
                errorMsg "Missing argument for '-${OPTARG}'"
                action="PrintUsageWithError"
            ;;
        esac

        optionFlags[${option}]=true # Option was provided
    done
    shift $((OPTIND-1))

    # The name of the process to check
    processName="${1:-${KEEPALIVED_CHECK_PROCESS_NAME}}"
    if [ -z "${processName}" ]
    then
        errorMsg "No process name supplied"
        action="PrintUsageWithError"
    else
        debugMsg "Process name set to: '${processName}'"
        debugMsg "Action:               ${action}"
    fi
}

# Displays the help message
#
# actionPrintUsage
function actionPrintUsage ()
{
    cat << EOF

Usage: $( basename "$0" ) [-dhv] KEEPALIVED_CHECK_PROCESS_NAME

    -d   Enable debug messages
    -h   Display this help and exit
    -v   Display the version and exit

Note, that the process name is also overridable via environment variables.
EOF
}

# Displays the help message and exit with error
#
# actionPrintUsage
function actionPrintUsageWithError ()
{
    actionPrintUsage
    exit 1
}

# Displays the version of this script
#
# actionPrintVersion
function actionPrintVersion ()
{
    cat << EOF
Copyright (C) 2019 Adfinis SyGroup AG

$( basename "$0" ) ${_VERSION}

License AGPLv3: GNU Affero General Public License version 3
                https://www.gnu.org/licenses/agpl-3.0.html
EOF
}


# Checks if the process PID can be accessed
#
# actionCheckProcess
actionCheckProcess ()
{
    killall -0 "${processName}"
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
