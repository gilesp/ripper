#!/usr/bin/env bash

# A script to rip a CD to flac

#set -Eeuo pipefail
#trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

usage() {
    cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] -d dvd_device -o output_path

Rip a dvd and place the files in <output_path>

The main feature of the dvd will be ripped and encoded with the
Handbrake preset "General/Fast 576p25". I am ripping PAL
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
    rm ${output_dir}/${film_title}.{vob,264,sub,idx,ac3}
    rm ${output_dir}/chapters.txt
}

msg() {
    echo >&2 -e "${1-}"
}

die() {
    local msg=$1
    local code=${2-1} # default exit status 1
    msg "Exiting. ${msg}"
    exit "${code}"
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

# dump dvd to iso, then work on that for remaining operations?
# dd if=${dvd_device} of=${output_dir}/dvd.iso bs=8192

#use lsdvd to get title info
dvd_info=`lsdvd -c ${dvd_device}`
film_title=`grep "Disc Title" <<< "${dvd_info}" | awk '{print $3}' | sed 's/.*/\L&/; s/[a-z]*/\u&/g'`
longest_track=`grep "Longest track" <<< "${dvd_info}" | awk '{print $3}' | sed 's/^0*//'`
dvd_info=`lsdvd -x -t ${longest_track} ${dvd_device}`

#english_audio_track=`lsdvd -s -t "$longest_track" ${dvd_device} | grep English | grep -m1 ac3 | awk '{print $21}'`
msg "Film title: ${film_title}"
msg "Longest track: ${longest_track}"

# Use handbrake to convert to h26[4|5]?
# HandBrakeCLI --main-feature -i $dvd_device -o "$output_dir/$film_title.mkv" --subtitle-lang-list "eng" --native-language "eng" --native-dub --preset "General/Fast 576p25"

# mplayer to dump dvd to single vob file
if [[ ! -f "${output_dir}/${film_title}.vob" ]]; then
    msg "Extracting vob"
    mplayer dvd://${longest_track} -dvd-device ${dvd_device} -dumpstream -dumpfile ${output_dir}/${film_title}.vob &> /dev/null
fi

# extract chapter information
if [[ ! -f "${output_dir}/chapters.txt" ]]; then
    msg "Extracting chapter information"
    dvdxchap -t ${longest_track} ${dvd_device} > ${output_dir}/chapters.txt
fi

# identify streams with ffmpeg
# ffmpeg -hide_banner -probesize 1000000000 -analyzeduration 1000000000  -ss 00:10:00 -t 00:00:02 -i Dvd_Video.vob

# Just grab the first subtitle stream (0x20 - 32), and hope for the best.

# The alternative is to grab all (english) subtitles, then merge them
# into the mkv. Would need to keep a list of the files generated in
# order to be able to generate the mkvmerge command with all of them.

# # extract all english subtitles
# if [[ ! -f "${output_dir}/${film_title}.idx" ]]; then
#     msg "Extracting english subtitles"

#     # This gets the hex stream id of all English subtitle tracks.
#     subtitle_info=`grep 'Subtitle:' <<< "${dvd_info}" | grep 'English' | awk '{print $11}'`
#     for subtitle_track in ${subtitle_info}
#     do
# 	IFS=',' read -r track_id <<< "${subtitle_track}"
# 	msg "Subtitle track ${track_id}"

# 	# Subtitles extraction only seems to work from the dvd, not a vob of the main feature.
# 	# Is this because of missing ifo file?
# 	# Would it work if I created a vob of the entire disk ?
# 	# mencoder ${output_dir}/${film_title}.vob \
#     	#      -nosound \
# 	#      -ovc copy \
# 	#      -o /dev/null \
# 	#      -vobsubout ${output_dir}/${film_title}_$((track_id)) \
# 	#      -sid $((track_id)) \
# 	#      -vobsuboutindex 0 \
# 	#      -vobsuboutid en &> /dev/null

# 	# ffmpeg can extract subtitles from single track vob and store
# 	# them in a mkv file, which mkvmerge can then combine into the
# 	# final output.
# 	fmpeg -probesize 2G \
# 	      -analyzeduration 1800M \
# 	      -hide_banner \
# 	      -notstats \
# 	      -i Dvd_Video.vob \
# 	      -map i:$((track_id)) \
# 	      -c:s dvdsub \
# 	      ${output_dir}/${film_title}_subtitles_$((track_id)).mkv
#     done
# fi

# Grab subtitle stream 0x20 (32) - which should be the first one.
if [[ ! -f "${output_dir}/${film_title}_subtitles.mkv" ]]; then
    msg "Extracting subtitles"
    ffmpeg -probesize 2G \
	  -analyzeduration 1800M \
	  -hide_banner \
	  -nostats \
	  -i ${output_dir}/${film_title}.vob \
	  -map i:32 \
	  -c:s dvdsub \
	  ${output_dir}/${film_title}_subtitles.mkv
fi

# Identify audio track.
# Preferences:
# English surround
# English stereo
# Other surround
# Other stero

if [[ ! -f "${output_dir}/${film_title}.ac3" ]]; then
    msg "Identifying audio track"
    # identify english 6 channel audio
    audio_info=`grep 'Audio:' <<< "${dvd_info}" | grep 'English' | grep 'Channels: 6' | head -1 | awk '{print $21 "," $6}'`
    msg "audio 1"

    if [ -z ${audio_info} ]; then
	# identify english 2 channel audio
	audio_info=`grep 'Audio:' <<< "${dvd_info}" | grep 'English' | grep 'Channels: 2' | head -1 | awk '{print $21 "," $6}'`
	msg "audio 2"
    fi

    if [ -z ${audio_info} ]; then
	# identify other 6 channel audio
	audio_info=`grep 'Audio:' <<< "${dvd_info}" | grep 'Channels: 6' | head -1 | awk '{print $21 "," $6}'`
	msg "audio 3"
    fi

    if [ -z ${audio_info} ]; then
	# identify other 2 channel audio
	audio_info=`grep 'Audio:' <<< "${dvd_info}" | grep 'Channels: 2' | head -1 | awk '{print $21 "," $6}'`
	msg "audio 4"
    fi

    IFS=',' read -r audio_track language <<<"$audio_info"
    audio_track_id=$((audio_track))
    msg "audio track id: ${audio_track_id}"

    # Using the audio track id number (1, 2, 3 etc.) from lsdvd

    # doesn't work wih ffmpeg, since the tracks could be in a
    # different order. Instead I need to use the stream id and the i:
    # map stream identifier format.
    # Dump audio track
    msg "Extracting audio track ${audio_track_id} (${language})"
    ffmpeg -hide_banner \
	   -loglevel error \
	   -nostats \
	   -r 25 \
	   -i ${output_dir}/${film_title}.vob \
	   -map i:${audio_track_id} \
	   -metadata:s:a:0 title="${language} audio" \
	   -codec:a copy \
	   ${output_dir}/${film_title}.ac3 \
	   2> /dev/null

    # mencoder
    #mencoder ${output_dir}/${film_title}.vob -aid $((${audio_track_id})) -of rawaudio -oac ac3 -ovc copy -o $mtitle/english.mp3
fi

if [[ ! -f ${output_dir}/${film_title}.264 ]]; then

    # crop detect
    msg "Detecting crop..."
    crop_filter=`ffmpeg -i ${output_dir}/${film_title}.vob -vf fps=1/2,cropdetect -ss 00:10:00 -t 00:00:02 -vsync vfr -f null - 2>&1 | awk '/crop/ { print $NF }' | tr ' ' '\n' | sort | uniq -c | sort -n | tail -1 | awk '{ print $NF }'`

    msg "Crop: ${crop_filter}"
    [[ -z "${crop_filter-}" ]] && die "Unable to determine crop."

    # extract video to h264
    msg "Extracting video track to h264"
    # single pass crf
    # ffmpeg -y \
    # 	   -vaapi_device /dev/dri/renderD128 \
    # 	   -i ${output_dir}/${film_title}.vob \
    # 	   -an \
    # 	   -sn \
    # 	   -c:v h264_vaapi \
    # 	   -vf ${crop_filter},format=nv12,hwupload \
    # 	   -preset slow \
    # 	   -tune film \
    # 	   ${output_dir}/${film_title}.264

    ###########
    # two pass
    ##########
    # First Pass
    msg "First pass..."
    ffmpeg -hide_banner \
	   -loglevel error \
	   -nostats \
	   -y \
	   -vaapi_device /dev/dri/renderD128 \
	   -i ${output_dir}/${film_title}.vob \
	   -an \
	   -sn \
	   -c:v h264_vaapi \
	   -vf ${crop_filter},format=nv12,hwupload \
	   -b:v 1200k \
	   -pass 1 \
	   -f null \
	   /dev/null

    # Second Pass
    msg "Second pass..."
    ffmpeg -hide_banner \
	   -loglevel error \
	   -nostats \
	   -y \
	   -vaapi_device /dev/dri/renderD128 \
	   -i ${output_dir}/${film_title}.vob \
	   -an \
	   -sn \
	   -c:v h264_vaapi \
	   -vf ${crop_filter},format=nv12,hwupload \
	   -b:v 1200k \
	   -pass 2 \
	   ${output_dir}/${film_title}.264
fi

#${language} \
if [[ ! -f ${output_dir}/${film_title}.mkv ]]; then
    # multiplex it all into an mkv
    msg "Multiplexing..."
    mkvmerge --title "${film_title}" \
             --chapters ${output_dir}/chapters.txt \
             --default-duration 0:25fps \
             --default-language ko \
             --clusters-in-meta-seek \
             -A ${output_dir}/${film_title}.264 \
	     ${output_dir}/${film_title}.ac3 \
	     ${output_dir}/${film_title}_subtitles.mkv \
             -o ${output_dir}/${film_title}.mkv
fi

msg "Done."
# Cleanup
cleanup

# Notes:
# HandBrakeCLI can't use vaapi acceleration, so it takes a long time to rip the dvd and encode it.
# Good results though, and usually gets main feature detection right.
#
# ffmpeg can use vaapi, and thus is much quicker to create an h264 file, but can't
# access dvd directly, so we need to use dvdbackup to first rip to VOBs. But then it's not clear
# how to automatically identify right streams to use for audio, video and subtitles.
#
# Could possibly use lsdvd or handbrake to anlyse the tracks more and identify approriate ones
# but I'm nost sure I fancy writing scripts to do that.
#
# Going to try makemkvcon (installed with snap - https://snapcraft.io/install/makemkv/debian)
#
# makemkvcon can't identify main title. Maybe use Handbrake or dvdbackup to identify title?
# then use makemkvcon to extract to mkv.


eject $dvd_device
