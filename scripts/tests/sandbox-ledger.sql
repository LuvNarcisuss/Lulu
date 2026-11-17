-- Run only inside a transaction that is rolled back. All identities are disposable.
do $$
declare
 a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); p record; n integer := 0;
 total bigint; state jsonb; rejected boolean; g record; member_guide uuid := gen_random_uuid();
begin
 insert into auth.users(id) values(a),(b);
 for p in select * from (values
 ('iltpkpefqtjskxel',400),('eweerqrczkwsjyjn',800),('bfktecvbuyjzwxtp',2450),
 ('zsadvhodvgamjqqp',5150),('qtqrufubdpyvzjzs',10800),('ipcijraguygtcpsa',17000),
 ('azjrhiwubtjsrbzh',29400),('qjcdfljcmzajynnd',42700),('rzeethasxinmprew',63700)) t(product,coins)
 loop
  n := n + 1;
  perform public.travel_credit_sandbox_coins(a, '991611160000000' || n, p.product, 'com.lulu.tourtravel');
  perform public.travel_credit_sandbox_coins(a, '991611160000000' || n, p.product, 'com.lulu.tourtravel');
  if (select amount from public.sandbox_wallet_activity where owner_id=a order by created_at desc, id limit 1) is null then raise exception 'Missing ledger entry'; end if;
  if not exists(select 1 from public.sandbox_coin_deliveries d join public.coin_products c on c.product_id=d.product_id
     where d.owner_id=a and d.transaction_id='991611160000000'||n and c.coins=p.coins) then raise exception 'Incorrect tier mapping'; end if;
 end loop;
 select sum(amount),count(*) into total,n from public.sandbox_wallet_activity where owner_id=a;
 if total <> 172400 or n <> 9 then raise exception 'Duplicate or incorrect credit: %, %',total,n; end if;
 if exists(select 1 from public.wallet_activity where owner_id=a) or exists(select 1 from public.coin_apple_deliveries where owner_id=a) then raise exception 'Production ledger contamination'; end if;
 rejected := false;
 begin perform public.travel_credit_sandbox_coins(b,'9916111600000001','iltpkpefqtjskxel','com.lulu.tourtravel');
 exception when others then rejected := true; end;
 if not rejected then raise exception 'Cross-account replay accepted'; end if;
 rejected := false;
 begin perform public.travel_credit_sandbox_coins(a,'9916111600000001','eweerqrczkwsjyjn','com.lulu.tourtravel');
 exception when others then rejected := true; end;
 if not rejected then raise exception 'Wrong-product replay accepted'; end if;
 perform set_config('request.jwt.claim.sub', a::text, true);
 state := public.travel_sandbox_coin_state('com.lulu.tourtravel');
 if (state->>'balance')::bigint <> 172400 then raise exception 'Wallet state mismatch'; end if;
 select guide_id,price_coins into g from public.guide_offers where status='published' and author_id is null and price_coins>0 order by guide_id limit 1;
 if g.guide_id is not null then
  perform public.travel_unlock_sandbox_guide(g.guide_id,g.price_coins,'com.lulu.tourtravel');
  perform public.travel_unlock_sandbox_guide(g.guide_id,g.price_coins,'com.lulu.tourtravel');
  state := public.travel_sandbox_coin_state('com.lulu.tourtravel');
  if (state->>'balance')::bigint <> 172400-g.price_coins or jsonb_array_length(state->'guides')<>1 then raise exception 'Sandbox spending or access failed'; end if;
  if exists(select 1 from public.guide_unlocks where owner_id=a) then raise exception 'Production entitlement contamination'; end if;
 end if;
 -- Sandbox credits cannot buy a real member's paid work.
 insert into public.guides(id,place_id,data) select member_guide,place_id,'{"title":"Member-owned test work"}'::jsonb from public.guide_offers where guide_id=g.guide_id;
 insert into public.guide_offers(guide_id,place_id,author_id,title,preview,price_coins,status)
 select member_guide,place_id,b,'Member-owned test work','A private regression fixture.',100,'published' from public.guide_offers where guide_id=g.guide_id;
 rejected := false;
 begin perform public.travel_unlock_sandbox_guide(member_guide,100,'com.lulu.tourtravel');
 exception when others then rejected := true; end;
 if not rejected then raise exception 'Sandbox coins unlocked member content'; end if;
 insert into public.sandbox_guide_unlocks(owner_id,bundle_id,guide_id,price_coins) values(a,'com.lulu.tourtravel',member_guide,100);
 state := public.travel_sandbox_coin_state('com.lulu.tourtravel');
 if jsonb_array_length(state->'guides')<>1 then raise exception 'Sandbox exposed member content'; end if;
 perform set_config('request.jwt.claim.sub', b::text, true);
 state := public.travel_sandbox_coin_state('com.lulu.tourtravel');
 if (state->>'balance')::bigint <> 0 or jsonb_array_length(state->'guides')<>0 then raise exception 'Account isolation failed'; end if;
 if has_function_privilege('authenticated','public.travel_credit_sandbox_coins(uuid,text,text,text)','EXECUTE') or has_function_privilege('anon','public.travel_sandbox_coin_state(text)','EXECUTE') then raise exception 'Unsafe function grants'; end if;
 -- The owner-authorized test app has its own verified sandbox balance.
 perform set_config('request.jwt.claim.sub', a::text, true);
 perform public.travel_credit_sandbox_coins(a,'9916111600000001','neiku_30','im.seex.sao2');
 perform public.travel_credit_sandbox_coins(a,'9916111600000001','neiku_30','im.seex.sao2');
 state := public.travel_sandbox_coin_state('im.seex.sao2');
 if (state->>'balance')::bigint <> 400 then raise exception 'Test bundle duplicate credit'; end if;
 if jsonb_array_length(state->'guides') <> 0 then raise exception 'Entitlement crossed bundle boundary'; end if;
 perform public.travel_unlock_sandbox_guide(g.guide_id,g.price_coins,'im.seex.sao2');
 state := public.travel_sandbox_coin_state('im.seex.sao2');
 if (state->>'balance')::bigint <> 400-g.price_coins then raise exception 'Test bundle spend failed'; end if;
 state := public.travel_sandbox_coin_state('com.lulu.tourtravel');
 if (state->>'balance')::bigint <> 172400-g.price_coins then raise exception 'Formal sandbox balance changed'; end if;
 rejected := false;
 begin perform public.travel_credit_sandbox_coins(b,'9916111600000001','neiku_30','im.seex.sao2');
 exception when others then rejected := true; end;
 if not rejected then raise exception 'Test bundle owner replay accepted'; end if;
 rejected := false;
 begin perform public.travel_sandbox_coin_state('com.other.app');
 exception when others then rejected := true; end;
 if not rejected then raise exception 'Unapproved bundle accepted'; end if;
 rejected := false;
 begin perform public.travel_sandbox_coin_state(null);
 exception when others then rejected := true; end;
 if not rejected then raise exception 'Null bundle accepted'; end if;
 if exists(select 1 from public.wallet_activity where owner_id=a) then raise exception 'Production balance changed'; end if;
end;
$$;
select 'passed' as result, 9 as tested_tiers, 172400 as expected_total, 'rolled_back' as fixture_lifecycle;
