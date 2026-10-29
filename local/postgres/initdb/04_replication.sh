#!/bin/sh
# CDC Openflow : utilisateur de réplication et publication des tables de Fournil & Co.
# Mot de passe lu dans le secret Docker, jamais écrit dans le repo.
set -e
pw=$(cat /run/secrets/pg_repl_password)
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v pw="$pw" <<'SQL'
create role openflow_repl login replication password :'pw';
grant usage on schema public to openflow_repl;
grant select on all tables in schema public to openflow_repl;
create publication fournil_pub for table customers, products, orders with (publish_via_partition_root = true);
SQL
