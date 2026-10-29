# POC Snowflake Data Connectivity Proxy (DCP)

Snowflake peut-il joindre une base Postgres et une API REST **locales**, sans aucun port entrant, depuis de simples
**procédures et fonctions Python**, grâce à [Data Connectivity Proxy](https://docs.snowflake.com/en/user-guide/data-connectivity-proxy) ?
Ce repo contient le banc de test et l'article qui en rend compte (`article/`).

Toutes les données sont **fictives** (générées en SQL, graine fixe). Aucun identifiant de compte ni secret n'est versionné :
ils sont dans `.env` et `secrets/`, tous deux ignorés par git.

## Prérequis
- Un compte Snowflake avec ACCOUNTADMIN, et Snowflake CLI (`snow`) configuré
- Docker et Docker Compose, sous Linux (noyau 5.x ou plus pour l'agent)

## Mise en route
```sh
cp .env.example .env          # connexion, identifiant du compte, utilisateur
make bootstrap create plan deploy   # socle Snowflake via DCM : WH_DCP, DCP_POC (RAW, APPS), rôle DCP_TESTER
make dcp                      # proxy DCP_LOCAL + certificats du compte (1re fois : attendre 30 min)
make up                       # Postgres (1 M de commandes) + API, en local
make eai sf-secret functions  # règle réseau DCP + EAI, secret Postgres, fonctions Python
make token agent-up           # token d'amorçage, puis démarrage de l'agent
make dcp-status               # agent_health = HEALTHY attendu
```

Puis, côté Snowflake (rôle `DCP_TESTER`) :
```sql
call DCP_POC.APPS.PG_QUERY('select count(*) from orders');
select DCP_POC.APPS.API_GET('/customers/42');
```

## Openflow (chemin officiel de DCP)
Les procédures Python ne passent pas par le tunnel : DCP ne sert aujourd'hui qu'à Openflow.
```sh
make openflow-deployment      # rôles, base DCP_OPENFLOW, déploiement Openflow (ACCOUNTADMIN, ~9 min)
make openflow-runtime         # secret de réplication + runtime DCP_RT relié à l'EAI DCP (~4 min)
```
- **Connecteur PostgreSQL CDC** : créé par `create openflow connector ... from definition OPENFLOW_POSTGRES_CDC`,
  configuré une fois via l'assistant (driver JDBC `openflow/drivers/`, non versionné). La configuration obtenue,
  sans secret, est dans `openflow/pg_fournil_config.json` ; on peut la réutiliser avec `PUT` sur
  `snow://openflow_connector/<connecteur>/versions/live/` puis `alter openflow connector ... commit`.
- **Flux API REST** : `snowflake/70_openflow_api.sql` (table cible), puis importer la définition de flux NiFi
  `openflow/api_rest_fournil_flow.json` dans le canevas du runtime (glisser un Process Group, « Upload »).
  Le flux arrive arrêté : activer ses services (connexion Snowflake, lecteur JSON, dialecte), puis démarrer.

## Arborescence
| Dossier | Contenu |
|---|---|
| `bootstrap/`, `dcm/` | Socle Snowflake (DCM). `dcm/manifest.yml` est généré depuis `manifest.yml.tmpl` par `make manifest` |
| `snowflake/` | Objets hors DCM : proxy, règle réseau + EAI, secret, fonctions Python, Openflow |
| `openflow/` | Configuration du connecteur CDC, définition du flux NiFi « API REST » (archive) |
| `local/` | `docker compose` : Postgres, API FastAPI, agent DCP |
| `bench/` | Scripts de mesure et scénarios de coupure, résultats |
| `article/` | Article Medium et journal de bord |

## Avant chaque commit
`make check-secrets` : gitleaks sur les fichiers qui partiraient au push, plus une recherche de l'identifiant du compte.

## Nettoyage
`make down`, puis `drop data connectivity proxy DCP_LOCAL` et, si besoin, `drop database DCP_POC`.
