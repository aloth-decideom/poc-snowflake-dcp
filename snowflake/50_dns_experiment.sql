-- =====================================================================
-- Expérience : Snowflake valide-t-il en DNS PUBLIC les noms d'une règle DCP avant d'ouvrir le tunnel ?
-- *.localtest.me se résout publiquement en 127.0.0.1 ; dans le réseau Docker, ces noms sont des alias
-- des conteneurs : l'agent les résout donc vers la base et l'API. make dns-experiment
-- =====================================================================
use role ACCOUNTADMIN;

create or replace network rule DCP_POC.APPS.NR_DCP_PUBDNS
    mode = DATA_CONNECTIVITY_PROXY_EGRESS
    type = HOST_PORT
    value_list = ('pg.localtest.me:5432', 'api.localtest.me:8000')
    comment = 'POC DCP : noms résolvables publiquement (127.0.0.1), résolus par l''agent vers Docker';

create or replace external access integration DCP_PUBDNS_EAI
    allowed_network_rules = (DCP_POC.APPS.NR_DCP_PUBDNS)
    allowed_authentication_secrets = all
    enabled = TRUE;

alter data connectivity proxy <% dcp_name %> set external_access_integrations = (DCP_LAB_EAI, DCP_PUBDNS_EAI);
grant usage on integration DCP_PUBDNS_EAI to role DCP_TESTER;

use role DCP_TESTER;
use schema DCP_POC.APPS;

create or replace function HTTP_GET(url varchar)
returns variant
language python
runtime_version = '3.12'
packages = ('requests')
external_access_integrations = (DCP_PUBDNS_EAI)
handler = 'get'
as
$$
import requests


def get(url):
    r = requests.get(url, timeout=60)
    return {'status': r.status_code, 'body': r.text[:500]}
$$;
