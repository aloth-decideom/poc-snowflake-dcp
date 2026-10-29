-- =====================================================================
-- Bootstrap DCM : à exécuter UNE FOIS, en ACCOUNTADMIN :
--   make bootstrap
-- Crée le rôle propriétaire du projet et le conteneur du projet DCM.
-- Ces objets ne sont PAS gérés par DCM (évite que le projet se supprime lui-même).
-- Script ré-exécutable.
-- =====================================================================
use role ACCOUNTADMIN;

-- Rôle propriétaire du projet DCM, rattaché à SYSADMIN
create role if not exists DCM_ADMIN comment = 'Propriétaire du projet DCM du POC DCP';
grant role DCM_ADMIN to role SYSADMIN;

-- Privilèges compte nécessaires aux objets définis dans dcm/sources/definitions
grant create database  on account to role DCM_ADMIN;
grant create warehouse on account to role DCM_ADMIN;
grant create role      on account to role DCM_ADMIN;
grant manage grants    on account to role DCM_ADMIN;

-- Conteneur du projet DCM
create database if not exists PLATFORM_ADMIN comment = 'Administration plateforme (hors DCM)';
create schema   if not exists PLATFORM_ADMIN.DCM comment = 'Objets projet DCM';
grant ownership on database PLATFORM_ADMIN     to role DCM_ADMIN copy current grants;
grant ownership on schema   PLATFORM_ADMIN.DCM to role DCM_ADMIN copy current grants;

-- L'utilisateur du POC déploie lui-même (pas d'utilisateur de service)
grant role DCM_ADMIN to user <% deploy_user %>;
