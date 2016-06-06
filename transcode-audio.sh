#!/bin/bash
#
# transcode-audio.sh
#
# Creates a lossy-compressed (e.g. MP3, Vorbis) copy of a tree of audio files.
# The source tree can be mixed lossless (e.g. FLAC) and lossy:
# - Any lossless files found are transcoded using into a configurable format
# - Any existing lossy files are hard-linked
# 
# Author: Dan Farmer
# URL: https://github.com/reedbug/transcode-audio.sh/
# Version: 0.3
# Licence: GPLv3+
#
# Copyright (C) 2016 Dan Farmer
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see https://www.gnu.org/licenses/.
#
# Exit codes:
#  0 :: Normal execution
#  1 :: Generic error
#  2 :: Bad arguments
#  3 :: Couldn't acquire lock on lockfile
# 10 :: Couldn't find source folder
# 11 :: Couldn't find destination folder
# 20 :: Couldn't find a decoding/encoding binary dependency
# 30 :: Something went wrong in transcoding

function main {
  handle_args "$@"  # Handle arguments, print help, exit if invalid
  checks            # Basic checks on source, dest path, encoder availability
  lock              # Lock on a lockfile
  if [[ $? -ne 0 ]]; then
    echo "Couldn't acquire lock on $LOCKFILE" 1>&2
    exit 3
  fi
  SECONDS=0         # Reset seconds since script start
  log INFO "$0 starting at $(/usr/bin/date "+%F %T")"
  transcode         # Do the actual work
  finish 0          # Log end of run and exit with success
}

function handle_args {
  # Handle arguments, print help if requested, override defaults from
  # arguments, set source and destination folders. Any exits from this function
  # are through 'exit' rather than 'finish'.
  # Default values
  TRANSCODE_LIST="\.flac$"
  TRANSCODE_FMT="vorbis"
  PURGE=false
  LOCKFILE=/var/tmp/transcode-audio.lock
  # Overwrite defaults with command line args
  while getopts ":hl:f:o:pL:" OPT; do
    case "$OPT" in
      h) printhelp;;
      t) TRANSCODE_LIST=$OPTARG;;
      f) if ([[ $OPTARG = "vorbis" ]] || [[ $OPTARG = "mp3" ]]); then
           TRANSCODE_FMT="$OPTARG"
         else
           echo "Transcode format must be one of \"vorbis\" or \"mp3\"" 1>&2
           exit 2
         fi;;
      o) ENCODER_OPTS=$OPTARG;;
      p) PURGE=true;;
      l) LOCKFILE=$OPTARG;;
      \?) echo "Invalid option: -$OPTARG" 1>&2
          exit 2;;
      :) echo "Option -$OPTARG requires an argument" 1>&2
         exit 2;;
    esac
  done
  # Fail if we don't have exactly 2 arguments left for $SOURCE and $DEST
  if [[ ! $(( $# - $OPTIND )) = 1 ]]; then
    echo "Usage: $0 [OPTS] SRC DEST" 1>&2
    echo "$0 -h for more usage information" 1>&2
    exit 2
  fi
  # If $ENCODER_OPTS hasn't been set, fill it with default values according to $TRANSCODE_FMT
  if [[ -z "$ENCODER_OPTS" ]]; then
    if [[ $TRANSCODE_FMT = "vorbis" ]]; then
      ENCODER_OPTS="-q4"
    elif [[ $TRANSCODE_FMT = "mp3" ]]; then
      ENCODER_OPTS="-V 4 --noreplaygain"
    fi
  fi
  # Finally, set $SOURCE and $DEST from the last two (positional, non-optional) arguments
  SOURCE=${@:$OPTIND:1}
  DEST=${@:$OPTIND+1:1}
}

function checks {
  # Any exits from this function are through 'exit' rather than 'finish'
  # Check if $SOURCE exists
  if [[ ! -d "$SOURCE" ]]; then
    echo "Couldn't find SOURCE \"$SOURCE\"" 1>&2
    exit 10
  fi 
  # Check if $DEST exists
  if [[ ! -d "$DEST" ]]; then
    echo "Couldn't find DEST \"$DEST\"" 1>&2
    exit 11
  fi
  # Check we have a binary for our chosen $ENCODER_FMT
  if [[ $TRANSCODE_FMT = "vorbis" ]]; then
    if ! which oggenc &>/dev/null; then
      echo "Couldn't find \'oggenc\' binary for requested vorbis transcoding" 1>&2
      exit 20
    fi
  elif [[ $TRANSCODE_FMT = "mp3" ]]; then
    if ! which lame &>/dev/null; then
      echo "Couldn't find \'lame\' binary for requested mp3 transcoding" 1>&2
      exit 20
    elif ! which flac &>/dev/null; then
      # For mp3 transcoding, we also need the flac binary for decoding
      echo "Couldn't find \'flac\' binary (required for mp3 transcoding)" 1>&2
      exit 20
    fi
  fi
}

function lock {
  exec 200>$LOCKFILE
  flock -n 200 && return 0 || return 1
}

function transcode {
  # Set field separator to newline
  OLDIFS=$IFS
  IFS=$'\n'
  # Initialise counters
  FILES_EXAMINED=0
  FILES_LINKED=0
  FILES_TRANSCODED=0
  # Find all files in $SOURCE, loop over them
  for SOURCE_FILE in $(find $SOURCE -type f | sort); do
    DEST_FILE="${SOURCE_FILE/$SOURCE/$DEST}"
    if (echo "$SOURCE_FILE" | egrep -q "$TRANSCODE_LIST"); then
      # If $SOURCE_FILE matches our regex of patterns (i.e. extensions) to
      # transcode, then transcode it.
      # Substitute the file extension as appropriate.
      if [[ $TRANSCODE_FMT = "vorbis" ]]; then
        DEST_FILE_TRANS="${DEST_FILE/%.flac/.ogg}"
      elif [[ $TRANSCODE_FMT = "mp3" ]]; then
        DEST_FILE_TRANS="${DEST_FILE/%.flac/.mp3}"
      fi
      if [[ $SOURCE_FILE -nt $DEST_FILE_TRANS ]]; then
        # If $SOURCE_FILE is newer than $DEST_FILE_TRANS (or $DEST_FILE_TRANS
        # doesn't exist).
        log INFO "Transcoding $SOURCE_FILE"
        if [[ $TRANSCODE_FMT = "vorbis" ]]; then
          # oggenc reads flac source files and will handle the metadata for us
          oggenc -Q "$ENCODER_OPTS" "$SOURCE_FILE" -o "$DEST_FILE_TRANS"
        elif [[ $TRANSCODE_FMT = "mp3" ]]; then
          if [[ ! -d "$DEST_DIR" ]]; then
            # If $DEST_DIR doesn't exist, create it as lame won't create for us
            DEST_DIR=$(dirname "$DEST_FILE_TRANS")
            log INFO "Creating $DEST_DIR"
            mkdir -p "$DEST_DIR"
          fi
          # lame can only read WAV or raw waveform, so pull metadata from
          # $SOURCE_FILE manually
          ARTIST=$(metaflac "$SOURCE_FILE" --show-tag=ARTIST | sed "s|^.*=||")
          TITLE=$(metaflac "$SOURCE_FILE" --show-tag=TITLE | sed "s|^.*=||")
          ALBUM=$(metaflac "$SOURCE_FILE" --show-tag=ALBUM | sed "s|^.*=||")
          GENRE=$(metaflac "$SOURCE_FILE" --show-tag=GENRE | sed "s|^.*=||")
          TRACKNUMBER=$(metaflac "$SOURCE_FILE" --show-tag=TRACKNUMBER \
                        | sed "s|^.*=||")
          YEAR=$(metaflac "$SOURCE_FILE" --show-tag=DATE | sed "s|^.*=||" \
                 | cut -c1-4)
          # flac decode source file to stdout, pipe to stdin of lame
          flac -s -c -d "$SOURCE_FILE" | \
            lame --quiet --id3v2-only "$ENCODER_OPTS" - "$DEST_FILE_TRANS" \
                 --ta "$ARTIST" \
                 --tt "$TITLE" \
                 --tl "$ALBUM" \
                 --tg "$GENRE" \
                 --tn "$TRACKNUMBER" \
                 --ty "$YEAR"
        fi
        TRANSCODE_RETURN=$?
        if [[ ! $TRANSCODE_RETURN = 0 ]]; then
          # Warn if something went wrong with our transcode
          log WARN "Error $TRANSCODE_RETURN when transcoding $SOURCE_FILE"
          # Delete the partially-transcoded file
          log INFO "Deleting partial file $DEST_FILE_TRANS"
          rm -f "$DEST_FILE_TRANS"
        else
          ((FILES_TRANSCODED++))
        fi
      fi
    else
      # All other files get hard-linked, using the original file extension
      if [[ ! -e $DEST_FILE ]]; then
        log INFO "Linking $SOURCE_FILE"
        ln $SOURCE_FILE $DEST_FILE
        ((FILES_LINKED++))
      fi
    fi
    ((FILES_EXAMINED++))
    if [[ -t 1 ]]; then
      # If output is a TTY, print a running counter
      echo -ne "Files examined/transcoded/linked: $FILES_EXAMINED / $FILES_TRANSCODED / $FILES_LINKED\r"
    fi
  done
  # Restore IFS
  IFS=$OLDIFS
  unset -v OLDIFS
}

function log {
  if [[ -t 1 ]]; then
    # If stdout is a TTY, store control characters for pretty formatting in
    # variables. Otherwise, variables are empty so this won't make parsing logs
    # hard.
    INFO_STDOUT_FMT='\e[1;32m'  # Bold, green
    RESET_STDOUT_FMT='\e[0m'    # Unset formatting ctrl chars
  fi
  if [[ -t 2 ]]; then
    # If stdout is a TTY, store control characters for pretty
    # formatting in variables. Otherwise, variables are empty so
    # this won't make parsing logs hard
    ERR_STDERR_FMT='\e[1;31m'   # Bold, red
    WARN_STDERR_FMT='\e[1;33m'  # Bold, yellow
    RESET_STDERR_FMT='\e[0m'    # Unset formatting ctrl chars
  fi
  LOGTIME=$(/usr/bin/date "+%T" | /usr/bin/tr -d "\n")
  if ([[ $1 == "ERR" ]] && [[ ! -z $2 ]] && [[ ! -t 1 ]]); then
    # If stdout is a TTY, store control characters for pretty formatting in
    # variables. Otherwise, variables are empty so this won't make parsing logs
    # hard.
    echo -e "$LOGTIME ${ERR_STDERR_FMT}ERROR:${RESET_STDERR_FMT} $2" | \
      tee > /dev/stderr
  elif ([[ $1 == "ERR" ]] && [[ ! -z $2 ]]); then
    # If stdout is a terminal, just send our errors to stderr
    echo -e "$LOGTIME ${ERR_STDERR_FMT}ERROR:${RESET_STDERR_FMT} $2" 1>&2
  elif ([[ $1 == "WARN" ]] && [[ ! -z $2 ]] && [[ ! -t 1 ]]); then
    echo -e "$LOGTIME ${WARN_STDERR_FMT}WARN:${RESET_STDERR_FMT} $2" | \
      tee > /dev/stderr
  elif ([[ $1 == "WARN" ]] && [[ ! -z $2 ]]); then
    echo -e "$LOGTIME ${WARN_STDERR_FMT}WARN:${RESET_STDERR_FMT} $2" 1>&2
  elif ([[ $1 == "INFO" ]] && [[ ! -z $2 ]]); then
    echo -e "$LOGTIME ${INFO_STDOUT_FMT}INFO:${RESET_STDOUT_FMT} $2"
  else
    echo -e "$LOGTIME ${ERR_STDERR_FMT}ERROR:${RESET_STDERR_FMT} Logging err" \
      1>&2 && finish 1
  fi
}

function printhelp {
  echo "transcode-audio.sh"
  echo "Create a lossy-compressed copy of a tree of audio files."
  echo
  echo "Usage:"
  echo "transcode-audio.sh -h, --help       Show this message"
  echo "transcode-audio.sh [OPTS] SRC DEST  Transcode from source directory to destination directory"
  echo
  echo "Options:"
  echo "  -t <regex>                        Regex of file patterns to transcode (any non-matching file"
  echo "                                    will be hard-linked)"
  echo "                                    Default: \"\\.flac\$\""
  echo "  -f <mp3|vorbis>                   Transcode format. Default: \"vorbis\""
  echo "  -o <options>                      Arguments to encoding binary"
  echo "                                    Default for vorbis (oggenc): \"-q4\""
  echo "                                    Default for mp3 (lame): \"-V 4 --noreplaygain\""
  echo "  -p                                Purge any files and directories in destination tree that"
  echo "                                    don\'t have a corresponding source file (currently not"
  echo "                                    implemented)"
  echo "  -l <file>                         Lockfile name. Default: \"/var/tmp/transcode-audio.lock\""
  echo
  exit 1
}

function finish {
  DURATION=$SECONDS
  log INFO "$0 finishing at $(/usr/bin/date "+%F %T")"
  log INFO "Time elapsed: $(($DURATION / 3600))h $(((($DURATION / 60)) % 60))m $(($DURATION % 60))s."
  log INFO "Files examined/transcoded/linked: $FILES_EXAMINED / $FILES_TRANSCODED / $FILES_LINKED"
  if [[ -n $1 ]]; then
    exit $1
  else
    exit 1
  fi
}

main "$@"

trap finish EXIT SIGHUP SIGINT SIGTERM
