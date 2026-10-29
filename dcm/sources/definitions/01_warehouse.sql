-- Warehouse unique du POC
define warehouse {{warehouse}}
with
    warehouse_size = '{{wh_size}}'
    auto_suspend = {{auto_suspend}}
    auto_resume = TRUE
    initially_suspended = TRUE
    comment = 'POC Data Connectivity Proxy - géré par DCM';
