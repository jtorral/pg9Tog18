#!/bin/bash

INPUT_FILE="pgList"
DB_USER="postgres"

QUERY="SHOW shared_preload_libraries;"

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: $INPUT_FILE not found."
    exit 1
fi

while IFS=":" read -r host port; do
    [[ -z "$host" || -z "$port" ]] && continue

    echo "--- Checking Config on Host: $host Port: $port ---"

    OUTPUT_FILE="config.${host}.${port}.txt"

    # get the stringg from the show command
    LIBRARIES=$(psql -h "$host" -p "$port" -U "$DB_USER" -d postgres -t -A -c "$QUERY" 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        echo "  [!] Error: Connection failed for $host."
        continue
    fi

    if [[ -z "$LIBRARIES" || "$LIBRARIES" == "none" ]]; then
        echo "# No shared_preload_libraries defined on $host" > "$OUTPUT_FILE"
        echo "  [-] No libraries found."
    else
        echo "# Add the following to postgresql.conf on the target postgres 18 server:" > "$OUTPUT_FILE"
        echo "shared_preload_libraries = '$LIBRARIES'" >> "$OUTPUT_FILE"
        echo "  [+] Found: $LIBRARIES"
        echo "  [+] Configuration saved to $OUTPUT_FILE"
    fi

done < "$INPUT_FILE"

echo "Library scan complete."
