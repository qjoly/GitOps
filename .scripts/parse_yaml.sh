#!/bin/bash
if ! command -v yq &> /dev/null; then
    echo "yq command not found. Please install yq to use this script." >&2
    exit 1
fi

tempfile=$(mktemp)

yq eval '.. | select((tag == "!!map" or tag == "!!seq") | not) | (path | join("_")) + "=" + .' $1 | awk '!/=$/{print }' > $tempfile
if [ "$?" -eq 0 ]; then
    mv $tempfile .env
else
    exit 1  
fi