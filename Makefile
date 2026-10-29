# POC Snowflake Data Connectivity Proxy (DCP)
# Les valeurs propres au compte (connexion, identifiant, utilisateur) sont dans .env, non versionné : cp .env.example .env
# Ordre sur un compte neuf : make manifest bootstrap create plan deploy
-include .env

CONN       ?= $(SNOWFLAKE_CONNECTION)
DCM_ROLE   ?= DCM_ADMIN
TARGET     ?= POC
DCM_DIR     = dcm

.PHONY: help env manifest check-connection bootstrap create plan deploy list-deployments check-secrets

help:
	@echo "--- socle Snowflake (DCM) ---"
	@echo "make manifest          Génère dcm/manifest.yml depuis dcm/manifest.yml.tmpl et .env"
	@echo "make check-connection  Teste la connexion \$$SNOWFLAKE_CONNECTION"
	@echo "make bootstrap         [1 fois] Rôle DCM_ADMIN et base PLATFORM_ADMIN (ACCOUNTADMIN)"
	@echo "make create            [1 fois] Crée l'objet projet DCM"
	@echo "make plan              Montre les changements, sans rien appliquer"
	@echo "make deploy            Applique les changements"
	@echo "make list-deployments  Historique des déploiements"
	@echo "--- repo public ---"
	@echo "make check-secrets     Cherche des secrets dans le repo (gitleaks, en conteneur)"

env:
	@test -f .env || { echo ".env absent : cp .env.example .env puis renseigner"; exit 1; }
	@test -n "$(SNOWFLAKE_CONNECTION)" -a -n "$(SNOWFLAKE_ACCOUNT_ID)" -a -n "$(SNOWFLAKE_USER)" || \
		{ echo "SNOWFLAKE_CONNECTION, SNOWFLAKE_ACCOUNT_ID et SNOWFLAKE_USER sont obligatoires dans .env"; exit 1; }

manifest: env
	@sed -e 's/{{ACCOUNT_ID}}/$(SNOWFLAKE_ACCOUNT_ID)/' -e 's/{{USER}}/$(SNOWFLAKE_USER)/' \
		$(DCM_DIR)/manifest.yml.tmpl > $(DCM_DIR)/manifest.yml
	@echo "$(DCM_DIR)/manifest.yml généré (non versionné)"

check-connection: env
	snow connection test -c $(CONN)

bootstrap: env
	snow sql -c $(CONN) --role ACCOUNTADMIN -f bootstrap/00_bootstrap.sql -D "deploy_user=$(SNOWFLAKE_USER)"

create: manifest
	snow dcm create -c $(CONN) --role $(DCM_ROLE) --from $(DCM_DIR) --target $(TARGET) --if-not-exists

plan: manifest
	snow dcm plan -c $(CONN) --role $(DCM_ROLE) --from $(DCM_DIR) --target $(TARGET) --save-output

deploy: manifest
	snow dcm deploy -c $(CONN) --role $(DCM_ROLE) --from $(DCM_DIR) --target $(TARGET)

list-deployments: manifest
	snow dcm list-deployments -c $(CONN) --role $(DCM_ROLE) --from $(DCM_DIR) --target $(TARGET)

# Fichiers suivis par git ET fichiers non ignorés : ce qui partirait au prochain push
check-secrets:
	git ls-files -z --cached --others --exclude-standard | xargs -0 cat | \
		docker run -i --rm zricethezav/gitleaks:v8.24.3 stdin --no-banner --redact
	@! git ls-files --cached --others --exclude-standard | xargs -r grep -il "$(SNOWFLAKE_ACCOUNT_ID)" 2>/dev/null \
		|| { echo "Identifiant du compte trouvé dans les fichiers ci-dessus"; exit 1; }
	@echo "Aucun secret ni identifiant de compte détecté"

# ---------------------------------------------------------------------
# Data Connectivity Proxy : hors DCM, en ACCOUNTADMIN
# ---------------------------------------------------------------------
DCP_NAME    ?= DCP_LOCAL
TOKEN_DAYS  ?= 7
TOKEN_FILE   = secrets/dcp-bootstrap-token

.PHONY: dcp dcp-status
dcp: env
	snow sql -c $(CONN) --role ACCOUNTADMIN -f snowflake/10_dcp_proxy.sql -D "dcp_name=$(DCP_NAME)"

dcp-status: env
	snow sql -c $(CONN) --role ACCOUNTADMIN -q "describe data connectivity proxy $(DCP_NAME)"

# ---------------------------------------------------------------------
# Environnement local (Docker) : Postgres + API, puis l'agent DCP
# ---------------------------------------------------------------------
COMPOSE = docker compose -f local/docker-compose.yml

.PHONY: secrets up down agent-up agent-down agent-logs
# Mots de passe Postgres générés localement (secrets/, non versionné).
# Le dossier est en 700 ; les fichiers en 644 pour être lisibles par les conteneurs (uid différent).
secrets:
	@mkdir -p secrets && chmod 700 secrets
	@for f in pg_admin_password pg_reader_password pg_repl_password; do \
		test -s secrets/$$f || ( umask 077 && openssl rand -hex 24 > secrets/$$f && chmod 644 secrets/$$f && echo "secrets/$$f créé" ) ; \
	done

up: secrets
	$(COMPOSE) up -d --build --wait postgres api

down:
	$(COMPOSE) --profile agent down -v

agent-up:
	@test -s $(TOKEN_FILE) || { echo "$(TOKEN_FILE) absent : make token"; exit 1; }
	$(COMPOSE) --profile agent up -d dcp-agent

agent-down:
	$(COMPOSE) stop dcp-agent

agent-logs:
	$(COMPOSE) logs -f dcp-agent

# ---------------------------------------------------------------------
# Côté Snowflake : token de l'agent, règle réseau + EAI, secret, fonctions Python
# ---------------------------------------------------------------------
.PHONY: token eai sf-secret functions
# Token d'amorçage de l'agent (JWT, TOKEN_DAYS jours, 90 max) : écrit dans $(TOKEN_FILE), jamais affiché.
# Rotation : relancer make token, l'agent relit le fichier sans redémarrer (mv atomique).
token: env
	@mkdir -p secrets && chmod 700 secrets
	@umask 077 && snow sql -c $(CONN) --role ACCOUNTADMIN --format json \
		-q "select SYSTEM\$$GENERATE_DATA_CONNECTIVITY_PROXY_BOOTSTRAP_TOKEN('$(DCP_NAME)', $(TOKEN_DAYS)) as TOKEN" > $(TOKEN_FILE).json \
		|| { cat $(TOKEN_FILE).json ; rm -f $(TOKEN_FILE).json ; exit 1 ; }
	@python3 -c 'import json, sys; open(sys.argv[2], "w").write(json.load(open(sys.argv[1]))[0]["TOKEN"].strip() + "\n")' \
		$(TOKEN_FILE).json $(TOKEN_FILE).new ; rc=$$? ; rm -f $(TOKEN_FILE).json ; [ $$rc = 0 ] || exit 1
	@chmod 644 $(TOKEN_FILE).new && mv $(TOKEN_FILE).new $(TOKEN_FILE)
	@echo "Token $(DCP_NAME) ($(TOKEN_DAYS) j) écrit dans $(TOKEN_FILE)"

eai: env
	snow sql -c $(CONN) --role ACCOUNTADMIN -f snowflake/20_network_eai.sql -D "dcp_name=$(DCP_NAME)"

# Sortie masquée : la requête affichée contiendrait le mot de passe
sf-secret: env secrets
	@snow sql -c $(CONN) -f snowflake/30_secrets.sql -D "pg_password=$$(cat secrets/pg_reader_password)" > /dev/null \
		&& echo "Secret DCP_POC.APPS.PG_READER créé"

functions: env
	snow sql -c $(CONN) -f snowflake/40_functions.sql

# ---------------------------------------------------------------------
# Mesures (bench/results/)
# ---------------------------------------------------------------------
BENCH ?= all
.PHONY: bench
bench:
	uv run bench/bench.py $(BENCH)

.PHONY: scenario
scenario:
	@test -n "$(S)" || { echo "ex. make scenario S=agent-kill (agent-stop agent-kill net-cut netem pg-stop)"; exit 1; }
	bench/scenarios/scenario.sh $(S)

.PHONY: dns-experiment
dns-experiment: env
	snow sql -c $(CONN) --role ACCOUNTADMIN -f snowflake/50_dns_experiment.sql -D "dcp_name=$(DCP_NAME)"

# ---------------------------------------------------------------------
# Openflow gen 2 (chemin officiel de DCP) : hors DCM
# ---------------------------------------------------------------------
.PHONY: openflow-deployment
openflow-deployment: env
	snow sql -c $(CONN) --role ACCOUNTADMIN -f snowflake/60_openflow_deployment.sql -D "deploy_user=$(SNOWFLAKE_USER)"

.PHONY: openflow-runtime
# Sortie masquée : la requête affichée contiendrait le mot de passe
openflow-runtime: env secrets
	@snow sql -c $(CONN) -f snowflake/61_openflow_runtime.sql -D "pg_repl_password=$$(cat secrets/pg_repl_password)" > out/openflow_runtime.log 2>&1 \
		&& echo "Secret et runtime DCP_RT créés" || { grep -iE "error|│" out/openflow_runtime.log | grep -v secret_string ; exit 1 ; }

.PHONY: outage
# Coupures sur le flux CDC Openflow : make outage S=agent-kill|net-cut [DUREE=120]
DUREE ?= 120
outage:
	@test -n "$(S)" || { echo "ex. make outage S=agent-kill DUREE=120"; exit 1; }
	bench/scenarios/openflow_outage.sh $(S) $(DUREE)
