# transcode-audio.sh
Create a transcoded copy of a tree of [FLAC](https://xiph.org/flac/) lossless audio files, and a hard-link of any non-FLAC files.

## Description
Creates a complete copy of a tree of audio files:
- Any FLAC files are transcoded to vorbis (ogg) or optionally mp3
- Any non-FLAC files (existing .ogg, mp3 audio, jpeg folder art, etc) are hard-linked for space-efficiency

## Usage
```
./transcode-audio.sh SOURCE-FOLDER DESTINATION-FOLDER
./transcode-audio.sh --help
```

## Features
- Transcodes to [vorbis/ogg](https://xiph.org/vorbis/) (default) or mp3 (option)
- Default flags to encoder binary can be overridden (e.g. different quality levels)
- Audio metadata (tags) are copied to transcoded file - see 'Audio File Metadata' below for more information on fields
- Any non-FLAC files (existing .ogg, mp3 audio, jpeg folder art, etc) are hard-linked for space-efficiency
- Incremental updates to the destination folder - i.e. only files in the destination that don't exist or are older than the source file are transcoded/linked. This makes transcode-audio.sh suitable for running interactively or on a scheduled basis (cron job).
- Handles errors from the encoding binary and cleans up partially-transcoded files
- Intelligent progress reporting and log output/formatting for:
  1. Interactive (TTY) execution - e.g. pretty logs and give real-time feedback on progress
  2. Non-interactive (cron) execution - e.g. give a summary and don't spam the logs

## Limitations
- Currently only handles FLAC source files for transcoding (no other lossless formats)

## Requirements
1. bash (version TBC) (makes moderate to heavy use of bashisms, won't execute with pure POSIX shells)
2. For vorbis encoding (default), an 'oggenc' binary that is built against libFLAC.so. Your distribution's oggenc binary is likely suitable.
3. For mp3 encoding, 'flac' and 'lame' binaries
4. The filesystem must allow hard linking

## Audio File Metadata
Audio metadata (FLAC tags aka Vorbis comments) are copied to transcoded file:
- For vorbis/ogg encoding, all tags found by 'oggenc' are copied to the transcoded file
- For mp3 encoding, the following tags are copied as id3v2 tags to the transcoded file
  - ARTIST
  - TITLE
  - ALBUM
  - GENRE
  - TRACKNUMBER
  - Year portion of DATE
  - transcode-audio.sh can be trivially extended to copy other tags (or pull requests welcome)
