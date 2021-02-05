#!/usr/bin/env bash

# A script to rip a CD to flac

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

usage() {
    cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] -d cd_device -o output_path

Rip a cd and place the files in <output_path>

Files will be placed in an Artist/Album/ folder.
Files will be named XX_track_title.flac where XX is the zero prefixed track number.

Available options:

-h, --help      Print this help and exit
-d, --device    Cdrom device, e.g. /dev/sr0
-o, --output    Output directory.
EOF
    exit
}

cleanup() {
    trap - SIGINT SIGTERM ERR EXIT
    # script cleanup here
    
    #Remove any folders abcde left behind
    find . -type d -name "abcde.*" -exec rm -rf {} +
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
    cd_device=''
    output_dir=''

    while :; do
        case "${1-}" in
        -h | --help) usage;;
        -d | --device) 
            cd_device="${2-}"
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
    [[ -z "${cd_device-}" ]] && die "Missing required parameter: device"
    [[ -z "${output_dir-}" ]] && die "Missing required parameter: output"
    #[[ ${#args[@]} -eq 0 ]] && die "Missing output directory argument."

    return 0
}

parse_params "$@"

# script logic here
msg "Using device: ${cd_device}"
msg "Writing output to: ${output_dir}"
#msg "Called with arguments: ${args[*]-}"

cd ${output_dir}

# create temporary abcde.conf
cat << EOF > abcde.conf
OUTPUTDIR=${output_dir}
OUTPUTFORMAT='\${ARTISTFILE}/\${ALBUMFILE}/\${TRACKNUM}-\${TRACKFILE}'
VAOUTPUTFORMAT='Various/\${ALBUMFILE}/\${TRACKNUM}-\${TRACKFILE}'
INTERACTIVE=n
ACTIONS=cddb,read,getalbumart,normalizer,encode,tag,replaygain,clean
CDROM=${cd_device}
OUTPUTTYPE=flac
MAXPROCS=$(nproc)
BATCHNORM=y
PADTRACKS=y
EOF

abcde -c abcde.conf

# abcde \
#     -c abcde.conf
#     -a cddb,read,getalbumart,normalizer,encode,tag,replaygain,clean \
#     -d ${cd_device} \
#     -N \
#     -o flac \
#     -p

