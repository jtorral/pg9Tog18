#!/bin/bash

INPUT_FILE="pgList"
DB_USER="postgres"

QUERY=$(cat <<EOF
SELECT extname 
FROM pg_extension 
WHERE extname != 'plpgsql' 
ORDER BY extname;
EOF
)

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: $INPUT_FILE not found."
    exit 1
fi

while IFS=":" read -r host port; do
    [[ -z "$host" || -z "$port" ]] && continue

    echo "--- Scanning Host: $host Port: $port ---"

    # get database list 
    DB_LIST=$(psql -h "$host" -p "$port" -U "$DB_USER" -d postgres -t -A -c \
        "SELECT datname FROM pg_database WHERE datistemplate = false;")

    if [[ $? -ne 0 ]]; then
        echo "  [!] Error: Connection failed for $host."
        continue
    fi

    for dbname in $DB_LIST; do
        OUTPUT_FILE="extensions.${host}.${port}.${dbname}.sql"
        
        # put extension names into an array so we can use them and generate new ones
        EXT_NAMES=$(psql -h "$host" -p "$port" -U "$DB_USER" -d "$dbname" -t -A -c "$QUERY" 2>/dev/null)

        if [[ -z "$EXT_NAMES" ]]; then
            echo "-- No custom extensions found" > "$OUTPUT_FILE"
            echo "  [-] $dbname: No extensions."
        else
            # create the file
            echo "-- Migration commands for $dbname" > "$OUTPUT_FILE"
            
            # loop through each extension found and build the sql string 
            for ext in $EXT_NAMES; do
                echo "psql -h $host -p $port -U $DB_USER -d $dbname -c \"CREATE EXTENSION IF NOT EXISTS $ext;\"" >> "$OUTPUT_FILE"
            done
            
            echo "  [+] $dbname: Commands saved to $OUTPUT_FILE"
        fi
    done

done < "$INPUT_FILE"

echo "Command generation complete."
