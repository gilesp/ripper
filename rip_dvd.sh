#!/usr/bin/env bash

# A script to rip a CD to flac

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

usage() {
    cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] -d dvd_device -o output_path

Rip a dvd and place the files in <output_path>

The main feature of the dvd will be ripped and encoded with the 
Handbrake preset "Matroska/H.265 MKV 576p25". I am ripping PAL 
dvds, so this resolution is sufficient for my needs.

Available options:

-h, --help      Print this help and exit
-d, --device    DVD device, e.g. /dev/sr0
-o, --output    Output directory.
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
    dvd_device=''
    output_dir=''

    while :; do
        case "${1-}" in
        -h | --help) usage;;
        -d | --device) 
            dvd_device="${2-}"
            shift
            ;;
        -o | --output)
            output_dir="${2-}"
            shift
            ;;
        -?*) die "Unknown option: $1" ;;
        *) break ;;
        esac
        shift
    done

    args=("$@")

    # check required params arguments
    [[ -z "${dvd_device-}" ]] && die "Missing required parameter: device"
    [[ -z "${output_dir-}" ]] && die "Missing required parameter: output"
    #[[ ${#args[@]} -eq 0 ]] && die "Missing output directory argument."

    return 0
}

parse_params "$@"

# script logic here
msg "Using device: ${dvd_device}"
msg "Writing output to: ${output_dir}"

#use lsdvd to get title info
film_title=`lsdvd -c | grep "Disc Title" | gawk '{print $3}' | sed 's/.*/\L&/; s/[a-z]*/\u&/g'`

# Use handbrake to convert to h26[4|5]?
HandBrakeCLI --main-feature -i $dvd_device -o "$output_dir/$film_title.mkv" --preset "Matroska/H.265 MKV 576p25"

eject $dvd_device

