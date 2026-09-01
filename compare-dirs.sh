#!/bin/bash

# Check if exactly two arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <directory1> <directory2>"
    exit 1
fi

DIR1="$1"
DIR2="$2"

# Check if both arguments are valid directories
if [ ! -d "$DIR1" ] || [ ! -d "$DIR2" ]; then
    echo "Error: Both arguments must be valid directories."
    exit 1
fi

echo "=========================================="
echo " Files in '$DIR1' but missing in '$DIR2'"
echo "=========================================="
# Find files in DIR1, get only the filename (%f), sort them, and compare
comm -23 <(find "$DIR1" -maxdepth 1 -type f -printf "%f\n" | sort) \
         <(find "$DIR2" -maxdepth 1 -type f -printf "%f\n" | sort)

echo ""
echo "=========================================="
echo " Files in '$DIR2' but missing in '$DIR1'"
echo "=========================================="
comm -13 <(find "$DIR1" -maxdepth 1 -type f -printf "%f\n" | sort) \
         <(find "$DIR2" -maxdepth 1 -type f -printf "%f\n" | sort)