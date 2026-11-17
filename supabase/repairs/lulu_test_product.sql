-- Add only the owner-selected test identifier to the existing product format.
alter table public.coin_products drop constraint coin_products_product_id_check;
alter table public.coin_products add constraint coin_products_product_id_check
    check (product_id ~ '^[a-z]{16}$' or product_id = 'neiku_30');
-- Retain the original product for previously purchased and pending transactions.
insert into public.coin_products(product_id, coins) values ('neiku_30', 400)
on conflict (product_id) do update set coins = excluded.coins;
