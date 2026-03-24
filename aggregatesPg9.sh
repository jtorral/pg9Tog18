#!/bin/bash

INPUT_FILE="pgList"
DB_USER="postgres"

# !!! IMPORTANT This is specific to postgres 9. 

QUERY=$(cat <<EOF
SELECT 
    n.nspname as schema_name,
    p.proname as aggregate_name,
    pg_catalog.format_type(p.prorettype, NULL) as return_type,
    pg_catalog.oidvectortypes(p.proargtypes) as argument_types,
    a.aggtransfn::regproc as sfunc,
    pg_catalog.format_type(a.aggtranstype, NULL) as stype,
    CASE WHEN a.aggfinalfn = 0 THEN NULL ELSE a.aggfinalfn::regproc END as ffunc,
    a.agginitval as initcond
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
JOIN pg_aggregate a ON a.aggfnoid = p.oid
WHERE p.proisagg = true
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY schema_name, aggregate_name;
EOF
)

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: $INPUT_FILE not found."
    exit 1
fi

while IFS=":" read -r host port; do
    [[ -z "$host" || -z "$port" ]] && continue

    echo "--- Extracting from Postgres 9 Host: $host Port: $port ---"

    # Get the list of databases
    DB_LIST=$(psql -h "$host" -p "$port" -U "$DB_USER" -d postgres -t -A -c \
        "SELECT datname FROM pg_database WHERE datistemplate = false AND datallowconn = true;")

    if [[ $? -ne 0 ]]; then
        echo "  [!] Error: Connection failed for $host."
        continue
    fi

    for dbname in $DB_LIST; do
        OUTPUT_FILE="aggregates.${host}.${port}.${dbname}.sql"

        # Connect to the specific database to pull its local aggregates
        RESULT=$(psql -h "$host" -p "$port" -U "$DB_USER" -d "$dbname" -t -A -F "|" -c "$QUERY" 2>/dev/null)

        if [[ -z "$RESULT" ]]; then
            echo "  [-] $dbname: No custom aggregates found."
        else
            # Create the file and inject the connection header immediately
            echo "-- Generated for Postgres 18 Migration (Source: v9)" > "$OUTPUT_FILE"
            echo "\\connect $dbname" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"

            # Format the metadata into CREATE AGGREGATE syntax
            echo "$RESULT" | awk -F "|" '{
                schema=$1; name=$2; rettype=$3; args=$4; sfunc=$5; stype=$6; ffunc=$7; init=$8;
                
                print "DROP AGGREGATE IF EXISTS " schema "." name "(" args ");";
                printf "CREATE AGGREGATE %s.%s(%s) (\n", schema, name, args;
                printf "  SFUNC = %s,\n", sfunc;
                printf "  STYPE = %s", stype;
                if (ffunc != "" && ffunc != "-") printf ",\n  FINALFUNC = %s", ffunc;
                if (init != "" && init != "-") printf ",\n  INITCOND = \047%s\047", init;
                printf "\n);\n\n";
            }' >> "$OUTPUT_FILE"

            echo "  [+] $dbname: Found aggregates! Saved to $OUTPUT_FILE"
        fi
    done

done < "$INPUT_FILE"

echo "Extraction complete."
