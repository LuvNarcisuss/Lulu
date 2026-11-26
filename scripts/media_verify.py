#!/usr/bin/env python3
"""Validate local media integrity and the public catalog without building the app."""
from datetime import date
from collections import Counter
from pathlib import Path
import hashlib
import json
import uuid
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
catalog = json.loads((ROOT/'Assets/catalog.json').read_text())
manifest = json.loads((ROOT/'Assets/media-manifest.json').read_text())
paths = {entry['path']:entry for entry in manifest['files']}
assert len(paths) == len(manifest['files']), 'Duplicate object paths'
assert len({x['sha256'] for x in manifest['files']}) == len(manifest['files']), 'Duplicate media bytes'
for entry in manifest['files']:
    local = ROOT/entry['local_file']
    assert local.is_file(), entry['local_file']
    assert hashlib.sha256(local.read_bytes()).hexdigest() == entry['sha256'], entry['local_file']
    assert local.stat().st_size == entry['bytes'], entry['local_file']
    assert entry['source_url'].startswith('https://') and entry['license_url'].startswith('https://')
    assert date.fromisoformat(entry['inspection']['reviewed_on']) >= date.fromisoformat(manifest['created_on'])
    if entry['kind'] == 'video':
        assert entry['source_sha256'], entry['path']
        assert all(0 <= t < entry['duration'] for t in entry['inspection']['times_seconds'])
        assert entry['codec'] == 'h264'
    else:
        image = Image.open(local)
        assert image.size == (entry['width'],entry['height'])

required = {
'profiles':set('id display_name bio avatar_path is_editorial source_url consent_version'.split()),
'clips':set('id title caption place_id publisher_id video_path cover_path source_url author duration category'.split()),
'places':set('id name city country region category latitude longitude summary photo_path source_url best_time practical_tip'.split()),
'guides':set('id place_id title intro sections source_name source_url reading_minutes'.split())}
ids={key:{row['id'] for row in rows} for key,rows in catalog.items()}
for key,rows in catalog.items():
    assert len(ids[key]) == len(rows), key
    for row in rows:
        uuid.UUID(row['id'])
        fields = set(row)
        if key == 'profiles':
            fields -= {'avatar_credit', 'avatar_is_illustrative'}
            if row['avatar_path'].startswith('catalog/'):
                assert row['avatar_path'] in paths, row['avatar_path']
        if key == 'clips' and 'feed_rank' in fields:
            assert type(row['feed_rank']) is int and row['feed_rank'] > 0
            fields.remove('feed_rank')
        assert fields == required[key], (key, fields^required[key])
        for field in ['photo_path','video_path','cover_path']:
            if field in row:
                assert row[field] in paths, row[field]
        if row.get('place_id'):
            assert row['place_id'] in ids['places']
        if row.get('publisher_id'):
            assert row['publisher_id'] in ids['profiles']
assert all(row['is_editorial'] for row in catalog['profiles'])
work_counts = Counter(clip['publisher_id'] for clip in catalog['clips'])
assert set(work_counts) == ids['profiles']
assert all(2 <= count <= 3 for count in work_counts.values())
assert {row['region'] for row in catalog['places']} == {'Europe','North America'}
icons='shorts explore journeys chats profile search add back close heart comment save share more location map calendar check wallet diamond settings edit camera photo send group pin mute trash report block phone video refresh route globe'.split()
asset_root=ROOT/'LuluApp/Resources/Assets.xcassets'
for name in icons:
    path=asset_root/('icon-'+name+'.imageset')/('icon-'+name+'.png')
    im=Image.open(path)
    assert im.mode == 'RGBA' and im.getextrema()[-1] == (0,255), name
    assert im.size == (160,160), name
for name in ['background-paper','background-welcome']:
    path=asset_root/(name+'.imageset')/(name+'.png')
    assert Image.open(path).size == (1024,1536)
app_icon=Image.open(asset_root/'AppIcon.appiconset/AppIcon.png')
assert app_icon.mode == 'RGB' and app_icon.size == (1024,1024)
assert not list((ROOT/'LuluApp/Resources').rglob('*.mp4'))
print(json.dumps({'result':'Static asset inspection passed','profiles':len(catalog['profiles']),'clips':len(catalog['clips']),'places':len(catalog['places']),'guides':len(catalog['guides']),'business_files':len(manifest['files']),'generated_icons':len(icons),'generated_backgrounds':2,'generated_app_icon':1,'checks':'UUIDs, flat DTO fields, references, bytes, SHA-256, dimensions, provenance, generated alpha and bundle separation','not_performed':'No app compilation, typecheck, launch, simulator, Preview or runtime acceptance.'},indent=2))
