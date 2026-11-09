from pathlib import Path
import json
catalog=json.loads(Path('Assets/catalog.json').read_text())
def literal(value):
 if value is None: return 'null'
 return "'"+str(value).replace("'","''")+"'"
queries=['begin;']
for table,columns in [('profiles',['id']),('places',['id']),('clips',['id','place_id','publisher_id']),('guides',['id','place_id'])]:
 for item in catalog[table]:
  assert table!='profiles' or item.get('is_editorial') is True
  data={k:v for k,v in item.items() if k not in columns}
  vals=[literal(item.get(k)) for k in columns]+[literal(json.dumps(data,ensure_ascii=False))+'::jsonb']
  queries.append(f"insert into public.{table}({','.join(columns)},data) values({','.join(vals)}) on conflict(id) do nothing;")
queries.append('commit;')
Path('supabase/seed.sql').write_text('\n'.join(queries)+'\n')
print({k:len(v) for k,v in catalog.items() if isinstance(v,list)})
