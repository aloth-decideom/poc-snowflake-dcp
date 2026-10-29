-- =====================================================================
-- Règle réseau DCP + intégration d'accès externe (hors DCM), en ACCOUNTADMIN : make eai
-- MODE = DATA_CONNECTIVITY_PROXY_EGRESS : le trafic vers ces destinations part dans le tunnel de l'agent.
-- Les noms (pg.dcp.lab, api.dcp.lab) sont résolus par l'agent, dans son réseau Docker.
-- Script ré-exécutable.
-- =====================================================================
use role ACCOUNTADMIN;

create or replace network rule DCP_POC.APPS.NR_DCP_LAB
    mode = DATA_CONNECTIVITY_PROXY_EGRESS
    type = HOST_PORT
    value_list = ('pg.dcp.lab:5432', 'api.dcp.lab:8000')
    comment = 'POC DCP : destinations privées joignables par l''agent local';

create or replace external access integration DCP_LAB_EAI
    allowed_network_rules = (DCP_POC.APPS.NR_DCP_LAB)
    allowed_authentication_secrets = all
    enabled = TRUE
    comment = 'POC DCP : sortie vers le réseau local via l''agent';

alter data connectivity proxy <% dcp_name %> set external_access_integrations = (DCP_LAB_EAI);
-- Créé désactivé par défaut (enabled = false)
alter data connectivity proxy <% dcp_name %> set enabled = TRUE;

grant usage on integration DCP_LAB_EAI to role DCP_TESTER;

describe data connectivity proxy <% dcp_name %>;
