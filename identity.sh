#!/bin/bash

INPUT_FILE="pgList"
DB_USER="postgres"

# Query to identify tables needing Replica Identity adjustments
QUERY=$(cat <<EOF
SELECT
    CASE
        WHEN count(i.indisprimary) FILTER (WHERE i.indisprimary) > 0 THEN NULL
        WHEN count(i.indisunique) FILTER (WHERE i.indisunique) > 0 THEN
            'ALTER TABLE ' || quote_ident(n.nspname) || '.' || quote_ident(c.relname) ||
            ' REPLICA IDENTITY USING INDEX ' || quote_ident((
                SELECT indexrelid::regclass::text
                FROM pg_index ix
                WHERE ix.indrelid = c.oid AND ix.indisunique
                LIMIT 1
            )) || ';'
        ELSE
            'ALTER TABLE ' || quote_ident(n.nspname) || '.' || quote_ident(c.relname) ||
            ' REPLICA IDENTITY FULL;'
    END
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_index i ON i.indrelid = c.oid
WHERE c.relkind = 'r'
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
GROUP BY n.nspname, c.relname, c.oid
HAVING (count(i.indisprimary) FILTER (WHERE i.indisprimary) = 0)
ORDER BY n.nspname, c.relname;
EOF
)

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: $INPUT_FILE not found."
    exit 1
fi

while IFS=":" read -r host port; do
    [[ -z "$host" || -z "$port" ]] && continue
    echo "--- Analyzing Host: $host Port: $port ---"

    DB_LIST=$(psql -h "$host" -p "$port" -U "$DB_USER" -d postgres -t -A -c \
        "SELECT datname FROM pg_database WHERE datistemplate = false AND datallowconn = true;")

    if [[ $? -ne 0 ]]; then
        echo "  [!] Error: Connection failed for $host."
        continue
    fi

    for dbname in $DB_LIST; do
        OUTPUT_FILE="replica_identity.${host}.${port}.${dbname}.sql"
        
        # Execute query against the specific database
        RESULT=$(psql -h "$host" -p "$port" -U "$DB_USER" -d "$dbname" -t -A -c "$QUERY" 2>/dev/null | grep "ALTER")

        if [[ -z "$RESULT" ]]; then
            echo "-- All tables in $dbname are already optimized with Primary Keys." > "$OUTPUT_FILE"
            echo "  [-] $dbname: No adjustments needed."
        else
            # Create the file and inject the connection header
            echo "-- Replica Identity Fixes for $dbname" > "$OUTPUT_FILE"
            echo "\\connect $dbname" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            
            # Append the ALTER statements
            echo "$RESULT" >> "$OUTPUT_FILE"
            echo "  [!] $dbname: Fixes generated for tables lacking PKs. Saved to $OUTPUT_FILE"
        fi
    done
done < "$INPUT_FILE"

echo "Analysis complete."
