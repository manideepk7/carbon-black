#!/bin/bash
# Copyright (c) 2018-2020 VMware, Inc. All rights reserved.
#
# Configure and register the PSC agent.
#

shopt -s extglob
umask 077

TYPE_AMAZON="amazon"
TYPE_CENTOS="centos"
TYPE_ORACLE="ol"
TYPE_REDHAT="rhel"
TYPE_SUSE="suse"
TYPE_UBUNTU="ubuntu"
TYPE_DEBIAN="debian"

AMAZON_VARIANTS=( "amz" )
CENTOS_VARIANTS=( "centos" "cent" )
ORACLE_VARIANTS=( "os" )
REDHAT_VARIANTS=( "rhel" "redhat" "red hat" )
SUSE_VARIANTS=( "suse" "opensuse" "sles" "sled" )

TYPE_UNKNOWN="unknown"
VERSION_UNKNOWN="unknown"

ERROR_FILE="/var/opt/carbonblack/tmp/cberror"
CIPHER_FILE="/var/opt/carbonblack/tmp/cbcipher"
PROP_FILE="/var/opt/carbonblack/tmp/cbpropfile"

echo_log() {
  echo "$@" 1>&2
}

#=============================================================================
# Parses a string in an effort to determine the type of Linux distribution
# Parameters:
#   - distro_name_str: a string containing information about the distro (from
#       /etc/os-release, lsb_release, etc.)
# Result:
#   Success: (0) returns the distribution TYPE
#   Failure: (1) returns TYPE_UNKNOWN
#=============================================================================
parse_distro_type() {
  local distro_name_str="$1"

  distro_name_str="$(echo $distro_name_str | tr '[:upper:]' '[:lower:]')"

  # check variants of amazon
  for variant in "${AMAZON_VARIANTS[@]}"; do
    case "$distro_name_str" in
        *"$variant"* )
         echo "$TYPE_AMAZON"
         exit 0
         ;;
    esac
  done

  # check variants of redhat
  for variant in "${REDHAT_VARIANTS[@]}"; do
    case "$distro_name_str" in
        *"$variant"* )
         echo "$TYPE_REDHAT"
         exit 0
         ;;
    esac
  done

  # check variants of centos
  for variant in "${CENTOS_VARIANTS[@]}"; do
    case "$distro_name_str" in
        *"$variant"* )
         echo "$TYPE_CENTOS"
         exit 0
         ;;
    esac
  done

   # check variants of suse
   for variant in "${SUSE_VARIANTS[@]}"; do
     case "$distro_name_str" in
        *"$variant"* )
         echo "$TYPE_SUSE"
         exit 0
         ;;
     esac
   done

    #check ubuntu
    if [ "$distro_name_str" = "$TYPE_UBUNTU" ]; then
        echo "$TYPE_UBUNTU"
        return 0
    fi

    #check debian
    if [ "$distro_name_str" = "$TYPE_DEBIAN" ]; then
        echo "$TYPE_DEBIAN"
        return 0
    fi
    
    #check oracle
    if [ "$distro_name_str" = "$TYPE_ORACLE" ]; then
        echo "$TYPE_ORACLE"
        return 0
    fi

  # No variants found!
  echo "$TYPE_UNKNOWN"
  return 1
}

#=============================================================================
# Sets the package type for known distros
#=============================================================================
parse_package_type() {

  DISTRO_IS_RPM=false
  DISTRO_IS_DEB=false

  if [ "$DISTRIBUTION_TYPE" = "$TYPE_UBUNTU" ]; then
        DISTRO_IS_DEB=true
  elif [ "$DISTRIBUTION_TYPE" = "$TYPE_DEBIAN" ]; then
        DISTRO_IS_DEB=true
  elif [ "$DISTRIBUTION_TYPE" = "$TYPE_AMAZON" ]; then
        DISTRO_IS_RPM=true
  elif [ "$DISTRIBUTION_TYPE" = "$TYPE_CENTOS" ]; then
        DISTRO_IS_RPM=true
  elif [ "$DISTRIBUTION_TYPE" = "$TYPE_ORACLE" ]; then
        DISTRO_IS_RPM=true
  elif [ "$DISTRIBUTION_TYPE" = "$TYPE_REDHAT" ]; then
        DISTRO_IS_RPM=true
  elif [ "$DISTRIBUTION_TYPE" = "$TYPE_SUSE" ]; then
        DISTRO_IS_RPM=true
  fi
}


#=============================================================================
# Parses a string to determine the major version of the Linux distribution
# Parameters:
#  - major_version_str: a string containing version information; expected to
#      begin with a numeric character
# Result:
#   Success: (0) return the identified version
#   Failure: (1) return VERSION_UNKNOWN
#=============================================================================
parse_distro_major_version() {
  local major_version_str="$1"
  major_version_str="$(echo $major_version_str | sed -rn 's/\s*([0-9]+).*/\1/p')"
  if [ -n "$major_version_str" ]; then
    echo "$major_version_str"
    return 0
  else
    echo "$VERSION_UNKNOWN"
    return 1
  fi
}

#=============================================================================
# Attempts to retrieve Linux distribution information from the OS
# Parameters:
#   None
# Result:
#   Success: (0) sets DISTRIBUTION_[BITS, TYPE, VERSION] to valid values
#   Failure: (1) sets 1 or more DISTRIBUTION_[BITS, TYPE, VERSION] to UNKNOWN
#=============================================================================
collect_distro_info() {
  local distro_type=""
  local distro_version=""

  # Get distribution type and major version
  if [ -f /etc/os-release ]; then
    source /etc/os-release
    distro_type="$ID"
    distro_version="$VERSION_ID"
  elif type lsb_release >/dev/null 2>&1; then
    distro_type="$(lsb_release -si)"
    distro_version="$(lsb_release -sr)"
  elif [ -f /etc/redhat-release ]; then
    distro_type="$(cat /etc/redhat-release)"
    # sed does not support non-greedy matching, must extract the version number
    distro_version="$(sed -rn 's/.*release ([0-9\.]+).*/\1/p' /etc/redhat-release)"
  elif [ -f /etc/system-release]; then
    distro_type="$(cat /etc/system-release)"
    distro_version="$(sed -rn '/.*release ([0-9\.]+).*/\1/p' /etc/system-release)"
  else
    distro_type="$TYPE_UNKNOWN"
    distro_version="$VERSION_UNKNOWN"
  fi

  DISTRIBUTION_TYPE=$(parse_distro_type "$distro_type")
  DISTRIBUTION_VERSION=$(parse_distro_major_version "$distro_version")
  DISTRIBUTION_BITS="$(getconf LONG_BIT)"
  parse_package_type

  if [ "$DISTRIBUTION_TYPE" = "$TYPE_UNKNOWN" ] ; then
    if rpm --version >/dev/null 2>&1; then
      export DISTRO_IS_RPM=true
    fi

    if dpkg-query --version >/dev/null 2>&1; then
      export DISTRO_IS_DEB=true
    fi
    
    if [ "$DISTRO_IS_RPM" = "$DISTRO_IS_DEB" ]; then
      echo_log "Failed: Unable to determine package type for unknown distribution."
      return 1 
    fi
  fi

  return 0
}

get_distribution_rpm() {
  if [ "$DISTRIBUTION_VERSION" = "6" ] || [ "$DISTRIBUTION_VERSION" = "7" ] || [ "$DISTRIBUTION_VERSION" = "8" ]; then

    rpm_file=$(ls -1 "$this_dir"/cb-psc-sensor-+([[:digit:]-.]).el"$DISTRIBUTION_VERSION".x86_64.rpm | tail -1)
  else
    rpm_file=$(ls -1 "$this_dir"/cb-psc-sensor-+([[:digit:]-.]).x86_64.rpm | tail -1)
  fi

  echo "$rpm_file"
}

get_distribution_deb() {
  deb_file=$(ls -1 "$this_dir"/cb-psc-sensor-+([[:digit:]-.]).x86_64.deb | tail -1)

  echo "$deb_file"
}

#=============================================================================
# Installs the agent on the system
# Parameters:
#   - cipher_code: string representing v3 registration code
# Result:
#   Success: (0)
#   Failure: (1)
#=============================================================================
install_agent() {
  local cipher_code="$1"
  local force_pkg="$2"
  local dirname="$(dirname $0)"
  local this_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && /bin/pwd )"
  local rpm_file=""
  local deb_file=""
  local already_installed=0

  echo_log "Starting install of cbagentd at $(date)."

  # Cleanup any errors from a previous run
  rm -f "$ERROR_FILE"

  # Write the cipher file if needed
  if [ -n "$cipher_code" ]; then
    echo "$cipher_code" > "$CIPHER_FILE"
    chmod 400 "$CIPHER_FILE"
  fi

  # Write the proxy file if needed
  if [ -n "$PROXY_NAME" ]; then
    echo "ProxyServer=$PROXY_NAME" >> "$PROP_FILE"
    chmod 400 "$PROP_FILE"
  fi

  # Ignore distribution and use forced package
  if [ "$force_pkg" ]; then
    extension=${force_pkg: -3}
    if [ ${extension^^} = "RPM" ]; then
      rpm_file="$this_dir/$force_pkg"
      if [ ! -f "$rpm_file" ]; then
        echo_log "$rpm_file not found"
        return 1
      fi
    elif [ ${extension^^} = "DEB" ]; then
      deb_file="$this_dir/$force_pkg"
      if [ ! -f "$deb_file" ]; then
        echo_log "$deb_file not found"
        return 1
      fi
    else
        echo_log "$force_pkg is not a valid package type";
        return 1
    fi
  else
    # Reject non-64 bit distributions
    if [ "$DISTRIBUTION_BITS" != "64" ]; then
      echo_log "Failed: Only 64-bit operating systems are supported (detected: ${DISTRIBUTION_BITS}-bit)"
      return 1
    fi

    # Choose RPM for distribution
    if [ "$DISTRO_IS_RPM" = true ];
    then
      rpm_file="$(get_distribution_rpm)"
      if [ "$rpm_file" = "" ]; then
        echo_log "Failed RPM install: this installer does not support this distribution ($DISTRIBUTION_TYPE-$DISTRIBUTION_VERSION)"
        return 1
      fi

      if rpm --quiet -q cb-psc-sensor;then
        already_installed=1
      fi

    # Choose DEB for distribution
    elif [ "$DISTRO_IS_DEB" = true ];
    then
      deb_file="$(get_distribution_deb)"
      if [ "$deb_file" = "" ]; then
        echo_log "Failed DEB install: this installer does not support this distribution ($DISTRIBUTION_TYPE-$DISTRIBUTION_VERSION)"
        return 1
      fi

      if dpkg-query -f='${Status}' -W cb-psc-sensor | grep -qG "^install ok installed"; then
        already_installed=1
      fi
    fi
  fi

  if [ $already_installed = 1 ]; then
    echo_log "Failed: Agent is already installed. If attempting to manually upgrade, use dpkg -i against the deb file or rpm -U against the rpm file, depending on your distribution."
    return 1
  elif [ -d "$this_dir/blades" ]; then
    # Since these directories are created before agent install, we need to set the permissions correctly.
    mkdir -pm 755 "/opt/carbonblack/"
    mkdir -pm 700 "/opt/carbonblack/psc"

    /bin/bash "$this_dir/blades/bladesUnpack.sh"
    bladeRet=$?

    if [ $bladeRet -ne 0 ]; then
      return 1
    fi
  fi

  # Install the agent package
  if [ "$DISTRO_IS_RPM" = true ]; then
    echo_log "Installing agent from $rpm_file"
    if ! rpm -i "$rpm_file"; then
      echo_log "Failed: an error occurred while installing $rpm_file"
      return 1
    fi

    # Check for registration errors
    if [ -f "$ERROR_FILE" ]; then
      echo_log "An error occurred during registration ($(cat $ERROR_FILE))."
      echo_log "The agent ($(rpm -qa cb-psc-sensor)) will be uninstalled..."
      rpm -e cb-psc-sensor
      echo_log "The agent was uninstalled."
      return 1
    fi

  elif [ "$DISTRO_IS_DEB" = true ]; then
    echo_log "Installing agent from $deb_file"
    dpkg --purge cb-psc-sensor 2> /dev/null

    # deb bubbles up scriptlet error codes to dpkg -i command (whereas rpm does not)
    if ! dpkg -i --force-confold "$deb_file"; then
      echo_log "Failed: an error occurred while installing $deb_file. The package will be uninstalled."
      dpkg --purge cb-psc-sensor
      return 1
    fi

    # Check for registration errors
    if [ -f "$ERROR_FILE" ]; then
      echo_log "An error occurred during registration ($(cat $ERROR_FILE))."
      echo_log "The agent will be uninstalled..."
      dpkg --purge cb-psc-sensor
      echo_log "The agent was uninstalled."
      return 1
    fi
  else
    echo_log "Failed: Agent was unable to install."
    return 1
  fi

  return 0
}

FreeSpaceMB() {
    FREE_SPACE_KB=$(df -Pk $1 | tail -1 | sed 's/  */ /g' | cut -f 4 -d ' ')
    echo $((FREE_SPACE_KB / 1024))
}

CheckDiskSpace() {
    local DIR_PATH="$1"
    local NEED_SIZE_MB="$2"

    while ! [ -d "$DIR_PATH" ]
    do
        DIR_PATH=$(dirname "$DIR_PATH")
    done

    local AVAIL_SPACE=$(FreeSpaceMB $DIR_PATH)

    if [ "$AVAIL_SPACE" -lt "$NEED_SIZE_MB" ]; then
        echo_log "Warning: '$DIR_PATH' has only ${AVAIL_SPACE}MB free space; at least ${NEED_SIZE_MB}MB recommended"
        echo_log "Warning: See sensor installation guide for resource requirements"
    fi
}

#=============================================================================
# Cleanup the temporary files created while parsing the options.
#=============================================================================
cleanup_temp_files() {
    # Remove the proxy details file
    if [ -f "$PROP_FILE" ]; then
        rm -f "$PROP_FILE"
    fi
}


#=============================================================================
# Main execution to install the agent.
# Parameters:
#   - cipher_code: string representing v3 registration code
#   - (optional) force_pkg: when set distribution detection is skipped and the
#     specified package file is installed
# Result:
#   Success: (0)
#   Failure: (1)
#=============================================================================
main() {
  local cipher_code="$1"
  local force_pkg="$2"
  local var_opt_cb_dir="/var/opt/carbonblack"
  local log_dir="/var/opt/carbonblack/psc/log"
  local tmp_dir="/var/opt/carbonblack/tmp"

  if [ -z "$force_pkg" ]; then
    # Collect distro information
    if ! collect_distro_info; then
      echo_log "Failed: Unable to gather enough info about this distribution to begin install."
      echo_log "(type: $DISTRIBUTION_TYPE; version: $DISTRIBUTION_VERSION; bits: $DISTRIBUTION_BITS)"
      return 1
    fi
  fi

  # Validate user is root
  if [ "$EUID" -ne 0 ]; then
    echo_log "Failed: Must be root to run this script."
    return 1
  fi

  # Warn if insufficient space is available
  CheckDiskSpace "/opt/carbonblack/psc"       "200"
  CheckDiskSpace "/var/opt/carbonblack/psc" "2000"

  # Perform the agent installation
  mkdir -p -m 700 "$var_opt_cb_dir"
  mkdir -p -m 700 "$log_dir" "$tmp_dir"

  if (! install_agent "$cipher_code" "$force_pkg" 2>&1 | cat -n | tee -a "${log_dir}/cbagentd-install.log"); then
    #
    # Cleanup the temporary files if any left behind
    #
    cleanup_temp_files
    echo_log "Failed: agent installation failed."
    return 1
  fi

  echo_log "Success: agent was successfully installed."

  return 0
}

usage() {
    echo -n "usage: $0 [--force-pkg PKGFILE] [-h|--help]"
    echo " [-p|--proxy 'PROXY_HOST:PROXY_PORT'] [COMPANY_CODE]"
    exit 1
}

# -e: Fail script if a command exits with non-zero
# -u: Fail script if undeclared variable is used
# -o pipefail: Piped command returns last non-zero exit

set -euo pipefail

CIPHER_CODE=""
PROXY_NAME=""

while [ "${1:-}" != "" ]; do
  case "${1:-}" in
    --force-pkg)
      FORCE_PKG="${2:-}"
      if [ -z "$FORCE_PKG" ]; then
        usage
      fi
      shift 2
      ;;
    -h | --help)
      usage
      ;;
    -p | --proxy)
      PROXY_NAME="${2:-}"
      if [ -z "$PROXY_NAME" ]; then
        usage
      fi
      shift 2
      ;;
    *)
      if [ -z "$CIPHER_CODE" ]; then
        CIPHER_CODE="${1:-}"
      else
        usage
      fi
      shift 1
      ;;
  esac
done

main "$CIPHER_CODE" "${FORCE_PKG:-}"
