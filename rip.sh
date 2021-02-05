#!/usr/bin/env bash
#
# A script to call either rip_cd.sh or rip_dvd.sh depending on the argument it's called with.
#

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

usage() {
    cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [CD|DVD]

Invoke either the cd or dvd rip script by passing in the arguments
CD or DVD repectively.


Available options:

-h, --help      Print this help and exit
EOF
    exit
}

cleanup() {
    trap - SIGINT SIGTERM ERR EXIT
    # script cleanup here
}

msg() {
    echo >&2 -e "${1-}"
}

die() {
    local msg=$1
    local code=${2-1} # default exit status 1
    msg "$msg"
    exit "$code"
}

parse_params() {
  # default values of variables set from params
  flag=0
  param=''

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  # check required params and arguments
  [[ ${#args[@]} -eq 0 ]] && die "You must specify CD or DVD"

  return 0
}

parse_params "$@"

# script logic here
msg "Called with: ${args[0]}"

if [[ ${args[0]} == "CD" ]]; then
  # Rip CD
  msg "Ripping CD"
  . "$script_dir/rip_cd.sh" -d "/dev/sr0"
elif [[ ${args[0]} == "DVD" ]]; then
  # Rip DVD
  msg "Ripping DVD"
  . "$script_dir/rip_cd.sh"
else
  # Error
  die "Unknown argument. Valid options are CD or DVD."
fi