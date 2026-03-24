#!/bin/bash

INPUT_FILE="pgList"
DB_USER="postgres"

# find tables where relhasoids is true to generate the alter statement
QUERY=$(cat <<EOF
SELECT 
    'ALTER TABLE ' || quote_ident(n.nspname) || '.' || quote_ident(c.relname) || ' SET WITHOUT OIDS;'
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r' 
  AND c.relhasoids = true
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY n.nspname, c.relname;
EOF
)

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: $INPUT_FILE not found."
    exit 1
fi

while IFS=":" read -r host port; do
    [[ -z "$host" || -z "$port" ]] && continue
    echo "--- Scanning for OID Columns on Host: $host Port: $port ---"

    # Get the list of databases
    DB_LIST=$(psql -h "$host" -p "$port" -U "$DB_USER" -d postgres -t -A -c \
        "SELECT datname FROM pg_database WHERE datistemplate = false AND datallowconn = true;")

    if [[ $? -ne 0 ]]; then
        echo "  [!] Error: Connection failed for $host."
        continue
    fi

    for dbname in $DB_LIST; do
        OUTPUT_FILE="alter_oids.${host}.${port}.${dbname}.sql"
        
        # run query against the specific database
        RESULT=$(psql -h "$host" -p "$port" -U "$DB_USER" -d "$dbname" -t -A -c "$QUERY" 2>/dev/null)

        if [[ -z "$RESULT" ]]; then
            echo "  [-] $dbname: No tables with OIDs found."
        else
            echo "-- SQL to convert tables to WITHOUT OIDS for Postgres 18 compatibility" > "$OUTPUT_FILE"
            echo "\\connect $dbname" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            
            echo "$RESULT" >> "$OUTPUT_FILE"
            echo "  [+] $dbname: OID removal script generated. Saved to $OUTPUT_FILE"
        fi
    done
done < "$INPUT_FILE"

echo "Check complete."
