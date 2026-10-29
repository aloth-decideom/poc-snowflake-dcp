-- =====================================================================
-- Fonctions Python qui joignent la base et l'API locales via DCP : make functions
-- Rien de spécifique à DCP dans le code : seule l'intégration DCP_LAB_EAI fait passer le trafic par le tunnel.
-- =====================================================================
use role DCP_TESTER;
use warehouse WH_DCP;
use schema DCP_POC.APPS;

-- Exécute une requête sur la base locale et renvoie le résultat sous forme de table
create or replace procedure PG_QUERY(query varchar)
returns table()
language python
runtime_version = '3.12'
packages = ('snowflake-snowpark-python', 'psycopg2')
external_access_integrations = (DCP_LAB_EAI)
secrets = ('pg' = PG_READER)
handler = 'run'
as
$$
import _snowflake
import psycopg2


def run(session, query):
    cred = _snowflake.get_username_password('pg')
    with psycopg2.connect(host='pg.dcp.lab', port=5432, dbname='fournil',
                          user=cred.username, password=cred.password, connect_timeout=10) as conn:
        cur = conn.cursor()
        cur.execute(query)
        cols = [d[0].upper() for d in cur.description]
        rows = cur.fetchall()
    return session.create_dataframe(rows, schema=cols)
$$;

-- Copie le résultat d'une requête locale dans une table Snowflake, par lots, et renvoie les temps mesurés
create or replace procedure PG_COPY(query varchar, target_table varchar, batch_size integer default 50000)
returns variant
language python
runtime_version = '3.12'
packages = ('snowflake-snowpark-python', 'psycopg2', 'pandas')
external_access_integrations = (DCP_LAB_EAI)
secrets = ('pg' = PG_READER)
handler = 'run'
as
$$
import time

import _snowflake
import pandas as pd
import psycopg2


def run(session, query, target_table, batch_size):
    cred = _snowflake.get_username_password('pg')
    t0 = time.perf_counter()
    conn = psycopg2.connect(host='pg.dcp.lab', port=5432, dbname='fournil',
                            user=cred.username, password=cred.password, connect_timeout=10)
    t_connect = time.perf_counter() - t0
    rows, t_fetch, t_write, first = 0, 0.0, 0.0, True
    try:
        # Curseur côté serveur : les lignes arrivent par lots, sans tout charger en mémoire
        with conn.cursor(name='pg_copy') as cur:
            cur.itersize = batch_size
            cur.execute(query)
            while True:
                t = time.perf_counter()
                batch = cur.fetchmany(batch_size)
                t_fetch += time.perf_counter() - t
                if not batch:
                    break
                cols = [d[0].upper() for d in cur.description]
                t = time.perf_counter()
                session.write_pandas(pd.DataFrame(batch, columns=cols), target_table,
                                     auto_create_table=True, overwrite=first)
                t_write += time.perf_counter() - t
                rows, first = rows + len(batch), False
    finally:
        conn.close()
    return {'rows': rows, 'connect_s': round(t_connect, 3), 'fetch_s': round(t_fetch, 3),
            'write_s': round(t_write, 3), 'total_s': round(time.perf_counter() - t0, 3)}
$$;

-- Appel GET de l'API locale (HTTP en clair : DCP transporte du TCP, le chiffrement est assuré par le tunnel)
create or replace function API_GET(path varchar)
returns variant
language python
runtime_version = '3.12'
packages = ('requests')
external_access_integrations = (DCP_LAB_EAI)
handler = 'get'
as
$$
import requests

# Session réutilisée entre les lignes d'un même lot : une connexion TCP (donc un tunnel) par processus
_session = requests.Session()


def get(path):
    r = _session.get('http://api.dcp.lab:8000' + path, timeout=60)
    r.raise_for_status()
    return r.json()
$$;

-- Mesure de latence vue de Snowflake : n connexions + n requêtes Postgres, et n appels HTTP, chronométrés dans le tunnel
create or replace procedure NET_PING(n integer default 50)
returns variant
language python
runtime_version = '3.12'
packages = ('snowflake-snowpark-python', 'psycopg2', 'requests')
external_access_integrations = (DCP_LAB_EAI)
secrets = ('pg' = PG_READER)
handler = 'run'
as
$$
import statistics
import time

import _snowflake
import psycopg2
import requests


def stats(xs):
    xs = sorted(x * 1000 for x in xs)
    return {'n': len(xs), 'min_ms': round(xs[0], 1), 'p50_ms': round(statistics.median(xs), 1),
            'p95_ms': round(xs[int(0.95 * (len(xs) - 1))], 1), 'max_ms': round(xs[-1], 1)}


def timed(fn):
    t = time.perf_counter()
    fn()
    return time.perf_counter() - t


def run(session, n):
    cred = _snowflake.get_username_password('pg')
    connect = lambda: psycopg2.connect(host='pg.dcp.lab', port=5432, dbname='fournil',
                                       user=cred.username, password=cred.password, connect_timeout=10)
    # Nouvelle connexion à chaque fois : nouveau tunnel (DCP ne multiplexe pas)
    pg_connect = [timed(lambda: connect().close()) for _ in range(n)]
    # Connexion réutilisée : aller-retour SQL seul
    conn = connect()
    cur = conn.cursor()
    pg_query = [timed(lambda: (cur.execute('select 1'), cur.fetchone())) for _ in range(n)]
    conn.close()
    # HTTP : nouvelle connexion à chaque appel, puis session keep-alive
    http_new = [timed(lambda: requests.get('http://api.dcp.lab:8000/health', timeout=30)) for _ in range(n)]
    s = requests.Session()
    http_keepalive = [timed(lambda: s.get('http://api.dcp.lab:8000/health', timeout=30)) for _ in range(n)]
    return {'pg_connect': stats(pg_connect), 'pg_select1': stats(pg_query),
            'http_new_conn': stats(http_new), 'http_keepalive': stats(http_keepalive)}
$$;
