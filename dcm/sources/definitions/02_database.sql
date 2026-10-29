-- Base du POC et ses schémas
define database {{database}}
    data_retention_time_in_days = {{data_retention_days}}
    comment = 'POC Data Connectivity Proxy - géré par DCM';

{% for schema in schemas %}
define schema {{database}}.{{schema}}
    comment = 'Schéma {{schema}} - géré par DCM';
{% endfor %}
