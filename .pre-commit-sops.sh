#!/bin/bash
log_file="./pre-commit.log"
for filename in "$@"
do
    echo "Checking.... $filename"
if [[ "$filename" =~ ^secret\..*\.ya?ml$ ]]; then
  echo "$filename matches pattern, encrypting..." >> $log_file
  sops -e -i $filename
  git add $filename
else
  echo "$filename does not match pattern and will not be encrypted" >> $log_file
fi
done


