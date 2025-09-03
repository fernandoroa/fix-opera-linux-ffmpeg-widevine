#!/bin/bash

if [[ $(whoami) != "root" ]]; then
	printf 'Try to run it with sudo\n'
	exit 1
fi

if [[ $(uname -m) != "x86_64" ]]; then
	printf 'This script is intended for 64-bit systems\n'
	exit 1
fi

if ! which unzip > /dev/null; then
	printf '\033[1munzip\033[0m package must be installed to run this script\n'
	exit 1
fi

if ! which curl > /dev/null; then
	printf '\033[1mcurl\033[0m package must be installed to run this script\n'
	exit 1
fi

if ! which jq > /dev/null; then
	printf '\033[1mjq\033[0m package must be installed to run this script\n'
	exit 1
fi

if which pacman &> /dev/null; then
	ARCH_SYSTEM=true
fi

#Config section
readonly FIX_WIDEVINE=true
readonly FIX_DIR='/tmp/opera-fix'
readonly FFMPEG_SRC_MAIN='https://api.github.com/repos/Ld-Hagen/nwjs-ffmpeg-prebuilt/releases'
readonly FFMPEG_SRC_ALT='https://api.github.com/repos/Ld-Hagen/fix-opera-linux-ffmpeg-widevine/releases'
readonly WIDEVINE_VERSIONS='https://dl.google.com/widevine-cdm/versions.txt'
readonly FFMPEG_SO_NAME='libffmpeg.so'
readonly WIDEVINE_SO_NAME='libwidevinecdm.so'
readonly WIDEVINE_MANIFEST_NAME='manifest.json'

OPERA_VERSIONS=()

if [ -x "$(command -v opera)" ]; then
  OPERA_VERSIONS+=("opera")
fi

if [ -x "$(command -v opera-beta)" ]; then
  OPERA_VERSIONS+=("opera-beta")
fi

#Getting download links
printf 'Getting download links...\n'

##ffmpeg
readonly FFMPEG_URL_MAIN=$(curl -sL4 $FFMPEG_SRC_MAIN | jq -rS 'sort_by(.published_at) | .[-1].assets[0].browser_download_url')
readonly FFMPEG_URL_ALT=$(curl -sL4 $FFMPEG_SRC_ALT | jq -rS 'sort_by(.published_at) | .[-1].assets[0].browser_download_url')
[[ $(basename $FFMPEG_URL_ALT) < $(basename $FFMPEG_URL_MAIN) ]] && readonly FFMPEG_URL=$FFMPEG_URL_MAIN || readonly FFMPEG_URL=$FFMPEG_URL_ALT
if [[ -z $FFMPEG_URL ]]; then
  printf 'Failed to get ffmpeg download URL. Exiting...\n'
  exit 1
fi

##Widevine
#if $FIX_WIDEVINE; then
#  readonly WIDEVINE_LATEST=`curl -sL4 $WIDEVINE_VERSIONS | tail -n1`
#  readonly WIDEVINE_URL="https://dl.google.com/widevine-cdm/$WIDEVINE_LATEST-linux-x64.zip"
#fi

#Downloading files
printf 'Downloading files...\n'
mkdir -p "$FIX_DIR"
##ffmpeg

curl -L4 --progress-bar $FFMPEG_URL -o "$FIX_DIR/ffmpeg.zip"
if [ $? -ne 0 ]; then
  printf 'Failed to download ffmpeg. Check your internet connection or try later\n'
  exit 1
fi
##Widevine
if $FIX_WIDEVINE; then
  echo "Finding a working Widevine version..."
  # Get all versions, newest last
  versions=$(curl -sL4 "$WIDEVINE_VERSIONS")
  # Loop through in reverse order (newest first)
  for ver in $(echo "$versions" | tac); do
    test_url="https://dl.google.com/widevine-cdm/${ver}-linux-x64.zip"
    # Check if the URL exists (no 404)
    if curl --progress-bar --fail "$test_url" -o "$FIX_DIR/widevine.zip"; then
      WIDEVINE_LATEST="$ver"
      WIDEVINE_URL="$test_url"
      echo -e "Trying Widevine version $WIDEVINE_LATEST from $WIDEVINE_URL\n"
      break
    else
      echo "Widevine version $ver not available, trying older..."
    fi
  done

  if [[ -z "$WIDEVINE_URL" ]]; then
    echo "Failed to find a working Widevine version. Exiting..."
    exit 1
  fi
  #readonly WIDEVINE_LATEST
  #readonly WIDEVINE_URL
fi

#Extracting files
printf 'Extracting files...\n'
##ffmpeg
unzip -o "$FIX_DIR/ffmpeg.zip" -d $FIX_DIR > /dev/null
##Widevine
if $FIX_WIDEVINE; then
  echo "unzip -o \"$FIX_DIR/widevine.zip\" -d $FIX_DIR"
  unzip -o "$FIX_DIR/widevine.zip" -d $FIX_DIR > /dev/null
fi

for opera in ${OPERA_VERSIONS[@]}; do
  echo "Doing $opera"
  EXECUTABLE=$(command -v "$opera")
	if [[ "$ARCH_SYSTEM" == true ]]; then
		OPERA_DIR=$(dirname $(cat $EXECUTABLE | grep exec | cut -d ' ' -f 2))
	else
		OPERA_DIR=$(dirname $(readlink -f $EXECUTABLE))
	fi
  OPERA_LIB_DIR="$OPERA_DIR/lib_extra"
  OPERA_WIDEVINE_DIR="$OPERA_LIB_DIR/WidevineCdm"
  OPERA_WIDEVINE_SO_DIR="$OPERA_WIDEVINE_DIR/_platform_specific/linux_x64"
  OPERA_WIDEVINE_CONFIG="$OPERA_DIR/resources/widevine_config.json"

  #Removing old libraries and preparing directories
  printf 'Removing old libraries & making directories...\n'
  ##ffmpeg
  rm -f "$OPERA_LIB_DIR/$FFMPEG_SO_NAME"
  mkdir -p "$OPERA_LIB_DIR"
  ##Widevine
  if $FIX_WIDEVINE; then
    rm -rf "$OPERA_WIDEVINE_DIR"
    mkdir -p "$OPERA_WIDEVINE_SO_DIR"
  fi

  #Moving libraries to its place
  printf 'Moving libraries to their places...\n'
  ##ffmpeg
  cp -f "$FIX_DIR/$FFMPEG_SO_NAME" "$OPERA_LIB_DIR"
  chmod 0644 "$OPERA_LIB_DIR/$FFMPEG_SO_NAME"
  ##Widevine
  if $FIX_WIDEVINE; then
    cp -f "$FIX_DIR/$WIDEVINE_SO_NAME" "$OPERA_WIDEVINE_SO_DIR"
    chmod 0644 "$OPERA_WIDEVINE_SO_DIR/$WIDEVINE_SO_NAME"
    cp -f "$FIX_DIR/$WIDEVINE_MANIFEST_NAME" "$OPERA_WIDEVINE_DIR"
    chmod 0644 "$OPERA_WIDEVINE_DIR/$WIDEVINE_MANIFEST_NAME"
    printf "[\n      {\n         \"preload\": \"$OPERA_WIDEVINE_DIR\"\n      }\n]\n" > "$OPERA_WIDEVINE_CONFIG"
  fi
done

#Removing temporary files
printf 'Removing temporary files...\n'
rm -rf "$FIX_DIR"
