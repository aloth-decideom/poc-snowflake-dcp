-- =====================================================================
-- Openflow gen 2 sur Snowflake (SPCS) : chemin officiel de DCP. make openflow-deployment
-- Les procédures Python ne passent pas par le tunnel (cf. article) ; un connecteur Openflow, si.
-- Script ré-exécutable.
-- =====================================================================
use role ACCOUNTADMIN;

-- Droits gen 2 du rôle d'administration Openflow (le rôle existe peut-être déjà, en gen 1)
create role if not exists OPENFLOW_ADMIN;
grant role OPENFLOW_ADMIN to role ACCOUNTADMIN;
grant role OPENFLOW_ADMIN to user <% deploy_user %>;
grant create openflow deployment on account to role OPENFLOW_ADMIN;
grant create database             on account to role OPENFLOW_ADMIN;
grant create integration          on account to role OPENFLOW_ADMIN;
grant create compute pool         on account to role OPENFLOW_ADMIN;

-- Base des objets Openflow (runtime, connecteur, secret), distincte de la base de destination DCP_POC
use role OPENFLOW_ADMIN;
create database if not exists DCP_OPENFLOW comment = 'POC DCP : objets Openflow (hors DCM)';
create schema   if not exists DCP_OPENFLOW.INFRA;
grant create openflow runtime   on schema DCP_OPENFLOW.INFRA to role OPENFLOW_ADMIN;
grant create openflow connector on schema DCP_OPENFLOW.INFRA to role OPENFLOW_ADMIN;

-- Rôle d'exécution du runtime : ce que le connecteur peut faire dans Snowflake
use role ACCOUNTADMIN;
create role if not exists OPENFLOW_DCP_RT_EXECUTE_AS_RL comment = 'POC DCP : rôle d''exécution du runtime Openflow';
grant role OPENFLOW_DCP_RT_EXECUTE_AS_RL to role OPENFLOW_ADMIN;
grant usage on database DCP_OPENFLOW       to role OPENFLOW_DCP_RT_EXECUTE_AS_RL;
grant usage on schema   DCP_OPENFLOW.INFRA to role OPENFLOW_DCP_RT_EXECUTE_AS_RL;
-- Tunnel DCP : l'EAI (règle DATA_CONNECTIVITY_PROXY_EGRESS) au rôle d'exécution et à l'admin Openflow
grant usage on integration DCP_LAB_EAI to role OPENFLOW_DCP_RT_EXECUTE_AS_RL;
grant usage on integration DCP_LAB_EAI to role OPENFLOW_ADMIN;
-- Destination de la CDC : DCP_POC (DCM), warehouse WH_DCP
grant usage, create schema on database DCP_POC to role OPENFLOW_DCP_RT_EXECUTE_AS_RL;
grant usage, operate on warehouse WH_DCP to role OPENFLOW_DCP_RT_EXECUTE_AS_RL;

-- Déploiement Openflow géré par Snowflake (SPCS)
use role OPENFLOW_ADMIN;
create openflow deployment if not exists DCP_DEPLOYMENT
    deployment_type = SNOWFLAKE
    display_name = 'POC DCP';

show openflow deployments;
