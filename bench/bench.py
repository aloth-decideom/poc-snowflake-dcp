# /// script
# requires-python = ">=3.11"
# dependencies = ["snowflake-connector-python==3.15.0", "psycopg[binary]==3.2.9", "requests==2.32.3"]
# ///
"""Mesures du POC DCP : latence, débit et concurrence, vus de Snowflake (via DCP) et en accès direct local.

Usage : uv run bench/bench.py latency|throughput|concurrency|all
Résultats en JSON dans bench/results/ (un fichier par mesure, horodaté).
"""
import json
import statistics
import sys
import time
from datetime import datetime
from pathlib import Path

import psycopg
import requests
import snowflake.connector

ROOT = Path(__file__).resolve().parent.parent
RESULTS = ROOT / "bench" / "results"
FQN = "DCP_POC.APPS"


def env():
    vals = {}
    for line in (ROOT / ".env").read_text().splitlines():
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            vals[k.strip()] = v.strip()
    return vals


def sf():
    return snowflake.connector.connect(connection_name=env()["SNOWFLAKE_CONNECTION"],
                                       role="DCP_TESTER", warehouse="WH_DCP", database="DCP_POC", schema="APPS")


def pg_local():
    pw = (ROOT / "secrets" / "pg_reader_password").read_text().strip()
    return psycopg.connect(host="127.0.0.1", dbname="fournil", user="dcp_reader", password=pw)


def save(name, data):
    RESULTS.mkdir(parents=True, exist_ok=True)
    path = RESULTS / f"{datetime.now():%Y%m%d_%H%M%S}_{name}.json"
    path.write_text(json.dumps(data, indent=2, default=str))
    print(json.dumps(data, indent=2, default=str))
    print(f"-> {path.relative_to(ROOT)}")


def stats(xs):
    xs = sorted(x * 1000 for x in xs)
    return {"n": len(xs), "min_ms": round(xs[0], 1), "p50_ms": round(statistics.median(xs), 1),
            "p95_ms": round(xs[int(0.95 * (len(xs) - 1))], 1), "max_ms": round(xs[-1], 1)}


def timed(fn):
    t = time.perf_counter()
    fn()
    return time.perf_counter() - t


def latency(n=50):
    """Mêmes mesures que la procédure NET_PING, côté Snowflake (via DCP) puis en direct sur le poste."""
    with sf() as conn:
        cur = conn.cursor()
        # Premier appel : démarrage à froid de la procédure (sandbox Python, paquets)
        t_cold = timed(lambda: cur.execute(f"call {FQN}.NET_PING(1)").fetchone())
        t = time.perf_counter()
        via_dcp = json.loads(cur.execute(f"call {FQN}.NET_PING({n})").fetchone()[0])
        t_call = time.perf_counter() - t
        # Coût d'une requête Snowflake sans DCP, pour comparaison
        sf_select1 = [timed(lambda: cur.execute("select 1").fetchone()) for _ in range(10)]

    s = requests.Session()
    with pg_local() as c:
        direct = {
            "pg_connect": stats([timed(lambda: pg_local().close()) for _ in range(n)]),
            "pg_select1": stats([timed(lambda: c.execute("select 1").fetchone()) for _ in range(n)]),
            "http_new_conn": stats([timed(lambda: requests.get("http://127.0.0.1:8000/health")) for _ in range(n)]),
            "http_keepalive": stats([timed(lambda: s.get("http://127.0.0.1:8000/health")) for _ in range(n)]),
        }
    save("latency", {"n": n, "via_dcp": via_dcp, "direct_local": direct,
                     "net_ping_cold_call_s": round(t_cold, 2), f"net_ping_{n}_call_s": round(t_call, 2),
                     "snowflake_select1_client": stats(sf_select1)})


def throughput(sizes=(10_000, 100_000, 1_000_000)):
    """Copie de N commandes Postgres -> table Snowflake (PG_COPY, via DCP), comparée à une lecture locale directe."""
    out = []
    with sf() as conn:
        cur = conn.cursor()
        for n in sizes:
            q = f"select * from orders order by order_id limit {n}"
            t = time.perf_counter()
            res = json.loads(cur.execute(f"call {FQN}.PG_COPY('{q}', 'ORDERS_{n}')").fetchone()[0])
            res["client_s"] = round(time.perf_counter() - t, 2)
            with pg_local() as c:
                t_local = timed(lambda: c.execute(q).fetchall())
            res.update({"n": n, "rows_per_s_fetch": round(n / res["fetch_s"]) if res["fetch_s"] else None,
                        "local_fetch_s": round(t_local, 3)})
            out.append(res)
            print(res)
    save("throughput", out)


def concurrency(rows=1000):
    """UDF API_GET appliquée à `rows` lignes : Snowflake parallélise, une connexion par processus Python."""
    with sf() as conn:
        cur = conn.cursor()
        sql = (f"select count(*), count_if(r:orders::int > 0) from ("
               f"select {FQN}.API_GET('/loyalty/' || seq4() % 10000 + 1) r "
               f"from table(generator(rowcount => {rows})))")
        t = time.perf_counter()
        total, ok = cur.execute(sql).fetchone()
        elapsed = time.perf_counter() - t
        qid = cur.sfqid
    save("concurrency", {"rows": rows, "ok": ok, "total": total, "elapsed_s": round(elapsed, 2),
                         "calls_per_s": round(rows / elapsed, 1), "query_id": qid})


if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    for name, fn in [("latency", latency), ("throughput", throughput), ("concurrency", concurrency)]:
        if what in (name, "all"):
            fn()
