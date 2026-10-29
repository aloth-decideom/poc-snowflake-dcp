-- Rôle de test : crée et appelle les fonctions Python qui passent par DCP.
-- Rattaché au rôle propriétaire du projet (DCM_ADMIN, sous SYSADMIN), qui garde la main sur ses objets.
-- L'USAGE sur l'intégration d'accès externe est donné hors DCM (snowflake/20_network_eai.sql).

define role {{tester_role}} comment = 'POC DCP - fonctions Python via DCP (géré par DCM)';
grant role {{tester_role}} to role {{project_owner_role}};

grant usage, operate on warehouse {{warehouse}} to role {{tester_role}};

grant usage on database {{database}} to role {{tester_role}};
{% for schema in schemas %}
grant usage on schema {{database}}.{{schema}} to role {{tester_role}};
grant create table, create view, create stage, create secret, create procedure, create function
    on schema {{database}}.{{schema}} to role {{tester_role}};
grant ownership on future tables in schema {{database}}.{{schema}} to role {{tester_role}};
{% endfor %}

{% for u in users %}
grant role {{tester_role}} to user {{u}};
{% endfor %}
