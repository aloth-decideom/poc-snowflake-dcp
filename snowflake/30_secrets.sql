-- =====================================================================
-- Identifiants de la base locale, stockés dans un SECRET Snowflake : make sf-secret
-- Le mot de passe vient de secrets/pg_reader_password (non versionné), passé par -D.
-- =====================================================================
use role DCP_TESTER;
use schema DCP_POC.APPS;

create or replace secret PG_READER
    type = PASSWORD
    username = 'dcp_reader'
    password = '<% pg_password %>'
    comment = 'POC DCP : utilisateur lecture seule de la base locale fournil';
