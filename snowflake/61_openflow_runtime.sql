-- =====================================================================
-- Runtime Openflow relié au tunnel DCP, et secret du connecteur : make openflow-runtime
-- À lancer quand DCP_DEPLOYMENT est prêt (show openflow deployments). Script ré-exécutable.
-- Coût : un nœud MEDIUM tourne tant que le runtime existe (crédits SPCS).
-- =====================================================================
use role OPENFLOW_ADMIN;
use schema DCP_OPENFLOW.INFRA;

-- Mot de passe de l'utilisateur de réplication (secrets/pg_repl_password, non versionné, passé par -D)
create or replace secret PG_REPL_PASSWORD
    type = GENERIC_STRING
    secret_string = '<% pg_repl_password %>'
    comment = 'POC DCP : mot de passe de openflow_repl (base locale fournil)';
grant read on secret PG_REPL_PASSWORD to role OPENFLOW_DCP_RT_EXECUTE_AS_RL;

-- Le runtime sort par l'EAI DCP_LAB_EAI : règle DATA_CONNECTIVITY_PROXY_EGRESS, donc par l'agent local
create openflow runtime if not exists DCP_RT
    in deployment DCP_DEPLOYMENT
    node_type = MEDIUM
    min_nodes = 1
    max_nodes = 1
    execute_as_role = OPENFLOW_DCP_RT_EXECUTE_AS_RL
    external_access_integrations = (DCP_LAB_EAI)
    display_name = 'POC DCP runtime';
