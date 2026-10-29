"""API REST de Fournil & Co (fictive), appelée depuis Snowflake via DCP."""
import os
import time

import psycopg
from fastapi import FastAPI, HTTPException

app = FastAPI(title="Fournil & Co API (POC DCP)")


def connect():
    with open(os.environ["PG_PASSWORD_FILE"]) as f:
        password = f.read().strip()
    return psycopg.connect(
        host=os.environ["PG_HOST"], dbname=os.environ["PG_DB"],
        user=os.environ["PG_USER"], password=password,
    )


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/customers")
def customers(limit: int = 100, offset: int = 0):
    """Liste paginée des clients : source du flux Openflow « API REST » (InvokeHTTP)."""
    with connect() as conn:
        rows = conn.execute(
            "select customer_id, first_name, city, loyalty_tier, created_at from customers "
            "order by customer_id limit %s offset %s",
            (min(limit, 10_000), offset),
        ).fetchall()
    cols = ["customer_id", "first_name", "city", "loyalty_tier", "created_at"]
    return [dict(zip(cols, r)) for r in rows]


@app.get("/customers/{customer_id}")
def customer(customer_id: int):
    with connect() as conn:
        row = conn.execute(
            "select customer_id, first_name, city, loyalty_tier from customers where customer_id = %s",
            (customer_id,),
        ).fetchone()
    if row is None:
        raise HTTPException(404, "client inconnu")
    return dict(zip(["customer_id", "first_name", "city", "loyalty_tier"], row))


@app.get("/loyalty/{customer_id}")
def loyalty(customer_id: int):
    """Score de fidélité « calculé » côté API : sert aux tests de concurrence (un appel par ligne)."""
    with connect() as conn:
        row = conn.execute(
            "select count(*), coalesce(sum(amount), 0) from orders where customer_id = %s",
            (customer_id,),
        ).fetchone()
    return {"customer_id": customer_id, "orders": row[0], "total": float(row[1])}


@app.get("/slow")
def slow(ms: int = 1000):
    """Réponse volontairement lente : requêtes longues pour les tests de coupure."""
    time.sleep(min(ms, 600_000) / 1000)
    return {"slept_ms": ms}


@app.get("/payload")
def payload(kb: int = 100):
    """Réponse de taille choisie : mesure du débit HTTP à travers le tunnel."""
    return {"data": "x" * (min(kb, 100_000) * 1024)}
