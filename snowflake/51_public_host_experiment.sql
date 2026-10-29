-- Expérience : une règle DCP vers un hôte PUBLIC (httpbin.org). Depuis une UDF Python, le trafic passe-t-il
-- par l'agent (visible dans DCP_CLIENT_CONNECTION_HISTORY), en sortie directe, ou pas du tout ?
use role ACCOUNTADMIN;
create or replace network rule DCP_POC.APPS.NR_DCP_PUBLIC
    mode = DATA_CONNECTIVITY_PROXY_EGRESS type = HOST_PORT value_list = ('httpbin.org:443');
create or replace external access integration DCP_PUBLIC_EAI
    allowed_network_rules = (DCP_POC.APPS.NR_DCP_PUBLIC) enabled = TRUE;
alter data connectivity proxy <% dcp_name %> set external_access_integrations = (DCP_LAB_EAI, DCP_PUBDNS_EAI, DCP_PUBLIC_EAI);
grant usage on integration DCP_PUBLIC_EAI to role DCP_TESTER;

use role DCP_TESTER;
use schema DCP_POC.APPS;
create or replace function HTTP_GET_PUBLIC(url varchar)
returns variant language python runtime_version = '3.12' packages = ('requests')
external_access_integrations = (DCP_PUBLIC_EAI) handler = 'get'
as
$$
import requests


def get(url):
    r = requests.get(url, timeout=60)
    return {'status': r.status_code, 'body': r.text[:300]}
$$;
