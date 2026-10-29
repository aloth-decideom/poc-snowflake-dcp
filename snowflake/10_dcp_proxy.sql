-- =====================================================================
-- Objet Data Connectivity Proxy (hors DCM), en ACCOUNTADMIN : make dcp
-- L'intégration d'accès externe est associée plus tard (20_network_eai.sql).
-- Script ré-exécutable.
-- =====================================================================
use role ACCOUNTADMIN;

create data connectivity proxy if not exists <% dcp_name %>
    comment = 'POC DCP : agent Docker local';

-- Certificats TLS du compte : émission asynchrone.
-- La première fois sur un compte, attendre au moins 30 min avant de démarrer l'agent.
select SYSTEM$ISSUE_PER_ACCOUNT_CERTIFICATES();

describe data connectivity proxy <% dcp_name %>;
