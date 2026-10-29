#!/bin/sh
# Utilisateur en lecture seule utilisé par Snowflake (via DCP) et par l'API.
# Mot de passe lu dans le secret Docker, jamais écrit dans le repo.
set -e
pw=$(cat /run/secrets/pg_reader_password)
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v pw="$pw" <<'SQL'
create role dcp_reader login password :'pw';
grant usage on schema public to dcp_reader;
grant select on all tables in schema public to dcp_reader;
SQL
