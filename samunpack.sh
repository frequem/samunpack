#!/bin/bash

usage() {
	echo "Usage: $0 <input file> [<output_dir>]"
	echo "  e.g. $0 fw.zip fw_out"
}

process_file() {
	mkdir -p "$(dirname -- $3)"
	if [[ "$1" == *".zip" ]]; then
		echo "Unzipping $(basename -- $1) ..."
		unzip -P "\n" -q "$1" -d "$2"
		process_dir "$2" "$3"
	elif [[ "$1" == *".tar" || "$1" == *".tar.md5" ]]; then
		echo "Untaring $(basename -- $1) ..."
		mkdir -p "$2"
		tar --file "$1" --extract --directory "$2"
		process_dir "$2" "$3"
	elif [[ "$1" == *".lz4" ]] || ( [[ "$(basename -- $1)" == "ramdisk" ]] && (file --brief "$1" | grep --quiet --extended-regexp "^LZ4 compressed data") ); then
		echo "Unlz4ing $(basename -- $1) ..."
		mkdir -p "$2"
		filename=$(basename -- "$1")
		lz4 -dc "$1" > "$2/${filename%.lz4}"
		process_dir "$2" "$3"
	elif [[ "$(basename -- $1)" == "ramdisk" ]] && (file --brief "$1" | grep --quiet --extended-regexp "^ASCII cpio archive"); then
		echo "Uncpioing ramdisk ..."
		mkdir -p "$2"
		cpio --extract --file="$1" --directory="$2" > /dev/null
		process_dir "$2" "$3"
	elif [[ "$1" == *".img" ]] && (file --brief "$1" | grep --quiet --extended-regexp "^Android sparse image"); then
		echo "Converting sparse image $(basename -- $1) ..."
		mkdir -p "$2"
		simg2img "$1" "$2/$(basename -- $1)"
		process_dir "$2" "$3"
	elif [[ "$1" == *".img" ]] && (file --brief "$1" | grep --quiet --extended-regexp "^Android bootimg"); then
		echo "Unpacking boot image $(basename -- $1) ..."
		unpack_bootimg --boot_img "$1" --out "$2" > /dev/null
		process_dir "$2" "$3"
	elif [[ "$1" == *".img" ]] && (file --brief "$1" | grep --quiet --extended-regexp "ext[234] filesystem data"); then
		echo "Extracting ext image $(basename -- $1) ..."
		ext2rd "$1" "./:$2"
		process_dir "$2" "$3"
	elif [[ "$1" == *".img" ]] && (file --brief "$1" | grep --quiet --extended-regexp "^F2FS filesystem"); then
		echo "Extracting f2fs image $(basename -- $1) ..."
		mkdir -p "$2_mnt"
		sudo mount "$1" "$2_mnt" > /dev/null
		sudo cp -Rf "$2_mnt" "$2"
		sudo umount "$2_mnt"
		rmdir "$2_mnt"
		sudo chown -R $USER:$USER "$2"
		process_dir "$2" "$3"
	elif [[ "$(basename -- $1)" == "super.img" ]]; then
		echo "Lpunpacking super.img ..."
		mkdir -p "$2"
		lpunpack "$1" "$2" > /dev/null
		process_dir "$2" "$3"
	else
		echo "Moving $(basename -- $1) ..."
		mv "$1" "$3"
	fi
}

process_dir() {
	mkdir -p "$2"
	files=("$1"/*)
	for f in "${files[@]}"; do
		process_path "$f" "$1/$(xxd -l16 -ps /dev/urandom)" "$2/$(basename -- $f)"
	done
}

process_path() {
	if [[ -L "$1" ]]; then
		echo "Moving symlink $(basename -- $1) ..."
		mv "$1" "$3"
	elif [[ -f "$1" ]]; then
		process_file "$1" "$2" "$3"
	elif [[ -d "$1" ]]; then
		mkdir -p "$2"
		mkdir -p "$3"
		files=("$1"/*)
		for f in "${files[@]}"; do
			process_path "$f" "$2/$(xxd -l16 -ps /dev/urandom)" "$3/$(basename -- $f)"
		done
	else
		echo "Error: \"$1\" is not a file or directory." >&2
	fi
}

shopt -s nullglob
sudo true

if [[ -z "$1" ]]; then
	echo "Error: No input file specified." >&2
	usage
	exit 1
fi

out_dir="${2:-out-$(xxd -l16 -ps /dev/urandom)}"
if [[ -e "$out_dir" ]]; then
	echo "Error: output directory \"$out_dir\" exists." >&2
	usage
	exit 1
fi

tmp_dir=".samunpack-$(xxd -l16 -ps /dev/urandom)"
process_path "$1" "$tmp_dir" "$out_dir/$(basename -- $1)"
rm -Rf "$tmp_dir"
