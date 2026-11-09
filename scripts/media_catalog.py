#!/usr/bin/env python3
"""Build the inspected public travel catalog and content-addressed media manifest."""
from pathlib import Path
import hashlib
import json
import subprocess
import uuid
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'Assets'
NAMESPACE = uuid.UUID('20549c13-4554-4a93-87c7-9bbb1ce4525c')
def stable(kind, slug):
    return str(uuid.uuid5(NAMESPACE, kind + ':' + slug))
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def probe(path):
    data = json.loads(subprocess.check_output(['ffprobe', '-v', 'quiet', '-print_format', 'json', '-show_streams', '-show_format', str(path)]))
    video = next(s for s in data['streams'] if s['codec_type'] == 'video')
    return {'width': video['width'], 'height': video['height'], 'duration': float(data['format']['duration']), 'codec': video['codec_name'], 'frame_rate': video['avg_frame_rate']}

# Original editorial text, informed by the linked primary visitor sources.
PLACE_DATA = [
('paris', 'Paris by the Seine', 'Paris', 'France', 'Europe', 'City', 48.8584, 2.2945,
 'Riverside walks, grand avenues and small neighborhood streets make a Paris day worth leaving open-ended.',
 'Paris je t\'aime', 'https://parisjetaime.com/eng/', 'Choose your season, then check attraction availability.',
 'Group nearby sights into one walk and leave room for a neighborhood stop.',
 'A day with room to wander', 'Start with one landmark, then follow the river rather than racing between distant attractions. Pair a monument with a small neighborhood walk for a more varied day.',
 'Plan the practical details', 'The official tourism office links district walks, transport options and accessibility information. Confirm arrangements for each attraction directly before you go; booking and access can change.'),
('rome', 'Colosseum and Ancient Rome', 'Rome', 'Italy', 'Europe', 'Heritage', 41.8902, 12.4922,
 'Roman stonework and the surrounding archaeological landscape tell a story far larger than one amphitheater.',
 'Parco archeologico del Colosseo', 'https://colosseo.it/en/opening-times-and-tickets/', 'Check the current seasonal schedule before booking.',
 'Reserve through the official ticketing link and check your assigned entrance time.',
 'Build around your entry slot', 'Begin with the official archaeological park website and choose the visit that matches your interests. Colosseum entry uses a reserved time, so plan other stops around that commitment.',
 'Give the wider site time', 'The Roman Forum and Palatine form a much broader visit than a quick photograph outside the arena. Read what your selected ticket includes and allow time for walking between areas.'),
('venice', 'Venice Canal Walks', 'Venice', 'Italy', 'Europe', 'Waterfront', 45.4408, 12.3155,
 'Quiet canal corners and weathered bridges reward a slow route through Venice beyond the busiest passages.',
 'Venezia Unica', 'https://www.veneziaunica.it/en/sustainable-venice/enjoy-respect-venezia', 'Consider an off-peak visit and check city visitor requirements.',
 'Keep narrow walking routes clear and follow the city\'s visitor guidance.',
 'Move at the city\'s pace', 'Use smaller streets to discover artisan workshops and everyday corners of Venice. On narrow routes, walk to the right in single file so residents and other visitors can pass.',
 'Respect a living place', 'Choose proper rest areas, look after waterways and historic spaces, and sort waste responsibly. Check the official city site for current access requirements rather than relying on an old itinerary.'),
('lisbon', 'Lisbon Hills and Trams', 'Lisbon', 'Portugal', 'Europe', 'City', 38.7223, -9.1393,
 'Trams, tiled streets and hilltop viewpoints give Lisbon an inviting rhythm for a flexible city day.',
 'Turismo de Lisboa', 'https://www.visitlisboa.com/en', 'Choose dates around the events and experiences you want.',
 'Pair one hilltop viewpoint with nearby streets instead of repeatedly crossing the city.',
 'Choose a small area', 'Build a walk around one Lisbon neighborhood, adding a viewpoint or cultural stop along the way. The official tourism site organizes experiences by area and interest.',
 'Plan the connections', 'Consult the official getting-around information before combining trams, walking and farther-away sights. Keep time for slopes and pauses; a short map distance can still make a full afternoon.'),
('swiss-alps', 'Swiss Alps', 'Swiss Alps', 'Switzerland', 'Europe', 'Mountains', 46.5775, 8.0056,
 'Mountain rail journeys, snowy ridges and walking routes offer different ways into Switzerland\'s Alpine landscapes.',
 'Switzerland Tourism', 'https://www.myswitzerland.com/en-us/experiences/summer-autumn/hiking/', 'Match the season to the route and verify mountain conditions.',
 'Choose a route suited to your experience and check transport and weather before setting out.',
 'Pick the right kind of day', 'Choose between a scenic rail journey, a valley walk and a demanding mountain route before adding stops. Distances on a map do not describe the effort of an Alpine trail.',
 'Leave a flexible margin', 'Use the official hiking information to compare routes and preparation. Mountain weather and service availability affect plans, so keep another activity available if conditions change.'),
('london', 'Tower Bridge and the Thames', 'London', 'United Kingdom', 'Europe', 'Waterfront', 51.5055, -0.0754,
 'Blue suspension spans, riverside paths and a working bridge create an absorbing London riverside stop.',
 'Tower Bridge', 'https://www.towerbridge.org.uk/', 'Check current exhibition access and bridge lift information.',
 'Treat the public bridge crossing and the indoor visitor experience as separate plans.',
 'See it from both banks', 'A riverside walk gives space to appreciate the towers and suspension spans. If you want to go inside, consult the official visitor page and book the experience that fits your day.',
 'Look beyond the photograph', 'The visitor experience includes high-level walkways and the Victorian Engine Rooms. Check accessibility information and current bridge lift details before arranging a tightly timed visit.'),
('barcelona', 'Park Guell, Barcelona', 'Barcelona', 'Spain', 'Europe', 'Architecture', 41.4145, 2.1527,
 'Curving architecture, planted slopes and city views turn Park Guell into a distinctive Barcelona walk.',
 'Park Guell Official Website', 'https://parkguell.barcelona/en/planifica-la-teva-visita', 'Check the seasonal opening schedule and ticket availability.',
 'Book through the official site and plan a sustainable route to the park.',
 'Plan before the climb', 'The park limits visitor capacity, so check availability before setting your day\'s route. Its opening times change with the season; use current official information for your date.',
 'Slow down inside', 'Leave time to notice details and the relationship between architecture and planting. The official site offers route, services, transport and guided-visit information to help shape a comfortable visit.'),
('santorini', 'Santorini Caldera Villages', 'Santorini', 'Greece', 'Europe', 'Coast', 36.3932, 25.4615,
 'Whitewashed settlements, volcanic cliffs and the Aegean horizon reveal Santorini\'s layered island landscape.',
 'Greek National Tourism Organisation', 'https://www.visitgreece.gr/en/islands/cyclades/santorini', 'Check seasonal transport and local conditions before choosing dates.',
 'Add a village or food stop alongside the caldera view.',
 'Look beyond one viewpoint', 'Fira and Oia sit within a wider volcanic island landscape. Combine a caldera view with another settlement or one of the island\'s contrasting beaches rather than building a day around a single image.',
 'Taste the landscape', 'The island\'s volcanic soil supports distinctive crops, including vines, small tomatoes and yellow split peas. Use the official destination information to explore food and cultural stops at an unhurried pace.'),
('iceland', 'Iceland Waterfalls', 'Iceland', 'Iceland', 'Europe', 'Nature', 64.9631, -19.0208,
 'A countrywide starting point for waterfall journeys. The photograph shows Dynjandi; video locations remain as credited by their creators.',
 'Visit Iceland', 'https://www.visiticeland.com/article/safe-travel-in-iceland/', 'Plan around daylight, road conditions and changing weather.',
 'Check SafeTravel and stay on marked paths, behind barriers and away from slippery edges.',
 'Let conditions set the route', 'Weather can change quickly, and a beautiful scene does not show whether a road or path is suitable today. Consult current travel conditions before committing to a long drive.',
 'Keep the view at a distance', 'Waterfall rocks can be slippery and some hazards are difficult to see. Respect signs, fences and marked paths. For longer independent outdoor trips, prepare suitable equipment and leave a travel plan.'),
('new-york', 'New York City', 'New York', 'United States', 'North America', 'City', 40.7580, -73.9855,
 'Street-level energy and skyline views make New York a city best explored one neighborhood at a time.',
 'NYC Tourism + Conventions', 'https://www.nyctourism.com/', 'Choose dates for your preferred neighborhood and cultural experiences.',
 'Choose one area for a walk before adding another borough or a timed attraction.',
 'Think in neighborhoods', 'Pick a neighborhood as the anchor for a morning or afternoon. A small number of nearby stops leaves more time for streets, food and unexpected discoveries.',
 'Keep exploring', 'The city extends across five boroughs. Consult the official tourism site for current ideas and practical planning, then check the individual venue\'s own information for reservations and access.'),
('yosemite', 'Yosemite Valley', 'Yosemite National Park', 'United States', 'North America', 'National Park', 37.7456, -119.5936,
 'Granite walls, waterfalls, forests and the Merced River frame an extraordinary Sierra Nevada valley.',
 'National Park Service', 'https://www.nps.gov/yose/planyourvisit/index.htm', 'Check current roads, weather and entry arrangements for your date.',
 'Save official park information offline and keep plans flexible around traffic and conditions.',
 'Prepare before arriving', 'Use the National Park Service planning pages for current conditions, road access and reservation requirements. Lodging and camping need advance thought, while mobile coverage can be limited.',
 'Stay with the landscape', 'Observe wildlife from a distance and never feed it. Near rivers and waterfalls, stay back from fast water and slippery rocks. Choose a walk that matches your preparation and available daylight.'),
('banff', 'Moraine Lake, Banff', 'Banff National Park', 'Canada', 'North America', 'National Park', 51.3217, -116.1860,
 'Turquoise water and the Valley of the Ten Peaks make Moraine Lake a memorable Canadian Rockies destination.',
 'Parks Canada', 'https://parks.canada.ca/pn-np/ab/banff/visit/parkbus/louise', 'Check the seasonal shuttle operating dates and lake access conditions.',
 'Plan transport in advance; consult Parks Canada for current access and reservations.',
 'Start with access', 'Lake Louise and Moraine Lake are popular and need planning. The official Parks Canada page explains available transport and shuttle reservations; confirm the arrangements for your own travel date.',
 'Make room in the day', 'Allow time for connections and potential queues rather than packing a lake visit between tight commitments. Separate park entry from transport planning and use the official information for current requirements.')
]

places, guides = [], []
for slug, name, city, country, region, category, latitude, longitude, summary, source_name, source_url, best_time, practical_tip, h1, b1, h2, b2 in PLACE_DATA:
    places.append(dict(id=stable('place',slug), name=name, city=city, country=country, region=region, category=category, latitude=latitude, longitude=longitude, summary=summary, photo_path=f'catalog/places/{slug}.jpg', source_url=source_url, best_time=best_time, practical_tip=practical_tip))
    guides.append(dict(id=stable('guide',slug), place_id=stable('place',slug), title=name + ': Field Notes', intro=summary, sections=[dict(title=h1,body=b1),dict(title=h2,body=b2)],source_name=source_name,source_url=source_url,reading_minutes=2))

profiles = [dict(id=stable('publisher','europe'),display_name='European Field Notes',bio='An editorial travel collection. Original footage creators are credited on each film; this publisher is not a traveler account.',avatar_path='',is_editorial=True,source_url='https://www.pexels.com/license/',consent_version='editorial-2026-11-03'),dict(id=stable('publisher','north-america'),display_name='North American Field Notes',bio='An editorial destination collection with creator credits and official planning links. This publisher is not a traveler account.',avatar_path='',is_editorial=True,source_url='https://www.nps.gov/aboutus/disclaimer.htm',consent_version='editorial-2026-11-03')]
CLIP_DATA = {
'paris-skyline':('Paris in Passing','A recorded daytime time-lapse of the Eiffel Tower and its surrounding cityscape.','paris','Architecture'),
'paris-street':('A Paris Side Street','Bicycles, neighborhood facades and a calm recorded street scene in Paris.','paris','City'),
'venice-canal':('A Quiet Venetian Canal','A recorded canal corner with old facades, boats and a narrow bridge in Venice.','venice','Waterfront'),
'venice-alley':('Between the Canals','A slow recorded walk through a narrow Venetian passage.','venice','City'),
'london-tower-bridge':('The Thames at Dusk','A recorded time-lapse of Tower Bridge as daylight gives way to evening.','london','Architecture'),
'london-big-ben':('Clouds Above Westminster','A recorded close view of London\'s clock tower with passing clouds.','london','Architecture'),
'new-york-times-square':('A New York Minute','Recorded daytime street movement in Times Square. Visible signs belong to the location; no endorsement is implied.','new-york','City'),
'rome-colosseum':('Rome in Stone','A recorded portrait view of the Colosseum and surrounding streets in Rome.','rome','Heritage'),
'iceland-waterfall':('Water over Iceland','Recorded aerial footage in Iceland. The creator does not identify the exact waterfall.','iceland','Nature'),
'swiss-alpine-train':('A Train through the Alps','Recorded snow-covered Swiss Alpine scenery and a mountain train, with the Matterhorn visible.','swiss-alps','Mountains'),
'yosemite-waterfall':('Yosemite in Motion','A recorded waterfall view in Yosemite National Park, excerpted from public-domain National Park Service footage.','yosemite','National Park')}

clips, files = [], []
sources = json.loads((ASSETS/'video-sources.json').read_text())
reviews = {
'paris-skyline':'Daytime Eiffel Tower, clouds and surrounding buildings; no protected nighttime lighting. No added text or watermark.',
'paris-street':'Paris street with parked bicycles, facades and passing road users. Incidental street signage only; no added watermark.',
'venice-canal':'Venetian canal, ochre facades, moored boat and narrow stone bridge. No added text or watermark.',
'venice-alley':'Moving walking view along a narrow old Venice alley. No added text or watermark.',
'london-tower-bridge':'Distinctive Tower Bridge from the Thames at dusk into evening. No added text or watermark.',
'london-big-ben':'Elizabeth Tower clock face and clouds in daylight. No added text or watermark.',
'new-york-times-square':'Identifiable Times Square with yellow taxis, pedestrians and English advertising signs. Incidental location brands; no added watermark.',
'rome-colosseum':'Portrait panning view of the Colosseum facade, palm and surrounding streets. No added text or watermark.',
'iceland-waterfall':'Aerial view over a cascading river and mossy cliffs; source identifies Iceland only. No exact waterfall identification asserted. No added text or watermark.',
'swiss-alpine-train':'Snowy Alps, a mountain train and recognizable Matterhorn. Source identifies Switzerland. No added text or watermark.',
'yosemite-waterfall':'Yosemite waterfall and granite landscape. Public-domain NPS source; selected ten-second segment, reviewed independently.'}
for source in sources:
    slug=source['slug']
    path=ASSETS/'catalog/videos'/f'{slug}.mp4'
    meta=probe(path)
    cover=ASSETS/'catalog/covers'/f'{slug}.jpg'
    cover_time=meta['duration']/2
    subprocess.run(['ffmpeg','-y','-v','error','-ss',str(cover_time),'-i',str(path),'-frames:v','1','-q:v','2',str(cover)],check=True)
    title,caption,place_slug,category=CLIP_DATA[slug]
    clips.append(dict(id=stable('clip',slug), title=title, caption=caption, place_id=None if slug == 'iceland-waterfall' else stable('place',place_slug), publisher_id=stable('publisher','north-america' if place_slug in ['new-york','yosemite'] else 'europe'), video_path=f'catalog/videos/{slug}.mp4', cover_path=f'catalog/covers/{slug}.jpg',source_url=source['@id'].replace('#video',''),author=source.get('author'),duration=meta['duration'],category=category))
    review_times=[0.15,round(meta['duration']/2,3),round(meta['duration']-.3,3)]
    common=dict(source_url=source['@id'].replace('#video',''), download_url=source['contentUrl'], author=source.get('author'), license='Mixkit Stock Video Free License' if source['copyrightNotice'] == 'Free' else source['copyrightNotice'], license_url=source['license'], inspection={'reviewed_on':'2026-11-03','times_seconds':review_times,'scene':reviews[slug],'method':'Human visual review of extracted start, midpoint and end representative frames; not a full-frame audit.'})
    files.append(dict(path=f'catalog/videos/{slug}.mp4',local_file=str(path.relative_to(ROOT)),kind='video',sha256=digest(path),source_sha256=source.get('source_sha256'),bytes=path.stat().st_size,**meta,processing={'resize':'Aspect-preserving fit within 1280x720; H.264 CRF 24; original playback speed and frame rate.','source_start_seconds':source.get('source_start_seconds',0),'excerpt_seconds':source.get('excerpt_seconds'),'audio':'Preserved when present, encoded to AAC.','cover_time_seconds':cover_time},**common))
    im=Image.open(cover)
    files.append(dict(path=f'catalog/covers/{slug}.jpg',local_file=str(cover.relative_to(ROOT)),kind='video_cover',sha256=digest(cover),bytes=cover.stat().st_size,width=im.width,height=im.height,derived_from=f'catalog/videos/{slug}.mp4',**common))

photo_reviews={'paris':'Daytime Eiffel Tower seen from the Seine.','paris-skyline':'Daytime Eiffel Tower above Paris rooftops.','rome':'Colosseum arches with foreground greenery.','venice':'Narrow Venetian canal and historic facades.','lisbon':'Red historic tram turning through a tiled Lisbon street; incidental local signage is part of the real scene.','swiss-alps':'Rugged Swiss Alpine slopes; exact mountain not claimed.','london':'Close view of Tower Bridge stone towers and blue suspension elements.','barcelona':'Distinctive entrance building at Park Guell with Barcelona beyond.','santorini':'Blue church dome and whitewashed Santorini roof, sea beyond.','iceland':'Distinctive broad Dynjandi waterfall, supported by the source description.','new-york':'New York skyline and waterfront at sunset.','yosemite':'Yosemite Valley granite walls and river reflection.','banff':'Moraine Lake turquoise water and mountain backdrop.','banff-shore':'A distinct portrait view of Moraine Lake through trees.'}
for source in json.loads((ASSETS/'photo-sources.json').read_text()):
    slug=source['slug'];path=ASSETS/'catalog/places'/f'{slug}.jpg';im=Image.open(path)
    files.append(dict(path=f'catalog/places/{slug}.jpg',local_file=str(path.relative_to(ROOT)),kind='destination_photo',sha256=digest(path),bytes=path.stat().st_size,width=im.width,height=im.height,source_url=source['source_url'],download_url=source['download_url'],author=source['author'],license=source['license'],license_url=source['license_url'],processing='Pexels CDN compression, width 1600; original aspect ratio.',inspection={'reviewed_on':'2026-11-03','scene':photo_reviews[slug]+' No added caption or watermark.','method':'Human visual review of the actual downloaded image.'}))

(ASSETS/'catalog.json').write_text(json.dumps(dict(profiles=profiles,clips=clips,places=places,guides=guides),indent=2)+'\n')
(ASSETS/'media-manifest.json').write_text(json.dumps(dict(version=1,created_on='2026-11-03',purpose='Editorial travel discovery within the application; no stock redistribution service.',business_media_root='Assets/',bundle_policy='Business media is uploaded to Supabase Storage and is not included in the application target.',files=files,rejected=[{'source_id':'4049','reason':'Source category implied California, while actual cactus landscape was insufficient to establish that location.'},{'source_id':'3323','reason':'Canadian town not specifically identified; excluded to prefer destination-supported footage.'},{'source_id':'3384','reason':'Canadian mountain area not specifically identified; excluded to prefer destination-supported footage.'}],guide_sources=[dict(place_id=g['place_id'],source_name=g['source_name'],source_url=g['source_url'],checked_on='2026-11-03',copy='Original English paraphrase; verify current arrangements at the source.') for g in guides]),indent=2)+'\n')
print(json.dumps({'profiles':len(profiles),'clips':len(clips),'places':len(places),'guides':len(guides),'media_files':len(files),'media_bytes':sum(x['bytes'] for x in files)},indent=2))
