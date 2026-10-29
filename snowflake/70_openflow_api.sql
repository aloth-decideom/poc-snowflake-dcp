-- =====================================================================
-- Flux Openflow « API REST » via DCP : table cible des clients lus sur http://api.dcp.lab:8000/customers
-- Le flux NiFi tourne dans le runtime DCP_RT, sous le rôle OPENFLOW_DCP_RT_EXECUTE_AS_RL.
-- =====================================================================
use role ACCOUNTADMIN;
create schema if not exists DCP_POC.FOURNIL_API comment = 'POC DCP : données lues sur l''API REST locale par Openflow';
grant usage on schema DCP_POC.FOURNIL_API to role OPENFLOW_DCP_RT_EXECUTE_AS_RL;
create or replace table DCP_POC.FOURNIL_API.CUSTOMERS (
    CUSTOMER_ID  number,
    FIRST_NAME   varchar,
    CITY         varchar,
    LOYALTY_TIER varchar,
    -- TIMESTAMP_NTZ (UTC) : le driver JDBC Snowflake ne sait pas lier le type TIMESTAMP_WITH_TIMEZONE (2014)
    CREATED_AT   timestamp_ntz
);
grant select, insert on table DCP_POC.FOURNIL_API.CUSTOMERS to role OPENFLOW_DCP_RT_EXECUTE_AS_RL;
grant create table, create pipe on schema DCP_POC.FOURNIL_API to role OPENFLOW_DCP_RT_EXECUTE_AS_RL;
