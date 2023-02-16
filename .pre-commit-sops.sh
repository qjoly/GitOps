#!/bin/bash
filename="$1"
log_file="./pre-commit.log"
if [[ "$filename" =~ ^secret\..*\.ya?ml$ ]]; then
  echo "$filename matches pattern, encrypting..." | tee $log_file
  sops -e -i $filename
  git add $filename
else
  echo "$filename does not match pattern and will not be encrypted" | tee $log_file
fi

