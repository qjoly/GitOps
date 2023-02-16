#!/bin/bash
filename="$1"
if [[ "$filename" =~ ^secret\..*\.ya?ml$ ]]; then
  echo "$filename matches pattern, encrypting..."
  sops -e -i $filename
  git add $filename
else
  echo "$filename does not match pattern and will not be encrypted"
fi

