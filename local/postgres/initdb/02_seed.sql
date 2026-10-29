-- Données synthétiques, reproductibles (graine fixe). Volumes : 10 000 clients, 1 000 000 de commandes.
select setseed(0.42);

insert into products values
    (1, 'Baguette tradition', 'Pain',        1.30),
    (2, 'Pain de campagne',   'Pain',        3.90),
    (3, 'Croissant',          'Viennoiserie', 1.20),
    (4, 'Pain au chocolat',   'Viennoiserie', 1.40),
    (5, 'Chausson aux pommes','Viennoiserie', 1.90),
    (6, 'Éclair au café',     'Pâtisserie',  3.20),
    (7, 'Tarte aux fraises',  'Pâtisserie',  4.50),
    (8, 'Flan pâtissier',     'Pâtisserie',  2.80),
    (9, 'Sandwich jambon-beurre', 'Snacking', 4.90),
    (10,'Quiche lorraine',    'Snacking',    4.20);

insert into customers
select i,
       (array['Camille','Lou','Sacha','Alex','Charlie','Noa','Eden','Maxime','Jules','Andrea'])[1 + floor(random()*10)::int],
       (array['Lille','Lyon','Nantes','Rennes','Bordeaux','Toulouse','Nice','Dijon'])[1 + floor(random()*8)::int],
       (array['Bronze','Argent','Or'])[1 + floor(random()*3)::int],
       timestamptz '2024-01-01' + random() * interval '600 days'
from generate_series(1, 10000) i;

insert into orders
select i, c, p, q, q * pr.unit_price, ts
from (
    select i,
           1 + floor(random()*10000)::int as c,
           1 + floor(random()*10)::int    as p,
           1 + floor(random()*4)::int     as q,
           timestamptz '2025-01-01' + random() * interval '660 days' as ts
    from generate_series(1, 1000000) i
) g
join products pr on pr.product_id = g.p;

create index on orders (ordered_at);
analyze;
