-- Fournil & Co : chaîne de boulangeries FICTIVE. Toutes les données sont générées ci-dessous.
create table customers (
    customer_id  integer primary key,
    first_name   text not null,
    city         text not null,
    loyalty_tier text not null,
    created_at   timestamptz not null
);

create table products (
    product_id integer primary key,
    name       text not null,
    category   text not null,
    unit_price numeric(6,2) not null
);

create table orders (
    order_id    bigint primary key,
    customer_id integer not null references customers,
    product_id  integer not null references products,
    quantity    integer not null,
    amount      numeric(10,2) not null,
    ordered_at  timestamptz not null
);
