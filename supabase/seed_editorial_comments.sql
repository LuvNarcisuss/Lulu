-- One original note per editorial collection and catalog film. Stable IDs preserve replies and reports on reseed.
with film_notes(clip_id, european_note, north_american_note) as (
    values
    ('2a6010ca-0b3d-52c2-ab82-4dec259e49f7', 'Try watching the rooftops instead of the Eiffel Tower for a moment. The city feels much bigger.', 'The tower makes a handy reference point while everything around it speeds up.'),
    ('aed38460-97a8-5a45-b4d1-37b49896c113', 'The parked bicycles give this little street its own rhythm.', 'The doorways caught my eye before the bikes did. Which detail stood out to you?'),
    ('c52902cf-48cc-56b9-b1c8-8d6d06065b04', 'The signs changing overhead have a different rhythm from the people crossing below.', 'Watch just one corner of Times Square on the replay. It feels like a different shot.'),
    ('2b74173e-3cf8-5fb5-afbb-f8dff2456846', 'The outline of Tower Bridge is easiest to pick out just as the sky starts to darken.', 'The river takes on the evening colors a little at a time. That was my favorite part.'),
    ('15f81b6b-0939-5df5-ba13-b35c172cf106', 'Keeping the clock face in view makes the passing clouds feel surprisingly fast.', 'The pale stone changes tone as the clouds go by. Worth a second look.'),
    ('56c2065b-7db4-522e-b7ce-2814ab72608a', 'This narrow passage gives a better sense of walking through Venice than a skyline shot would.', 'The next bend keeps the view a surprise, even on a short walk like this.'),
    ('d2374b56-154c-5e13-8bc0-8dca2b479c3a', 'The little bridge ties both sides of the canal together in one frame.', 'Try following the reflections below the boats. The water gives the buildings a second outline.'),
    ('cb4a45fb-ecca-5d91-a72e-0c1851797170', 'Following one row of arches helps you see how sharply the Colosseum curves.', 'The street at the edge of the frame brings the scale of the stonework into focus.'),
    ('7fd817fd-1b8c-506e-a164-ebfbae922fa6', 'From above you can follow the stream right up to the drop.', 'The white water is easy to follow against the darker ground. Where did your eye go first?'),
    ('a1747570-9624-5d85-b92f-4010a2036bd9', 'Look for the train first, then follow the slope up to the peak.', 'The train gives those snowfields a scale that the mountain alone never could.'),
    ('7e460225-9c44-5918-a660-e5afd55c29d4', 'The falling water keeps changing shape against the same patch of rock.', 'On a replay, watch the spray at the base of the falls instead of the top.'),
    ('36aeba40-bcc7-5b77-b46d-40c752da41e3', 'The people crossing beneath Elizabeth Tower make its height much easier to judge.', 'There is a whole street scene going on below the clock. The wide view is worth keeping.'),
    ('f70c2836-512e-58ee-b4a4-a88abf11e0c8', 'The cables keep drawing the eye back to the stone arch.', 'Watch the wooden planks as the camera moves. They give this Brooklyn Bridge walk its pace.'),
    ('a7647473-1256-5bcf-aea0-9f3d033435c4', 'The moving patches of sunlight bring out different rows of arches.', 'Watching the visitors cross the plaza makes the amphitheater feel even larger.')
)
insert into public.comments(id, clip_id, user_id, body)
select md5('lulu:editorial-comment:' || f.clip_id || ':' || p.id::text)::uuid,
       f.clip_id::uuid, p.id, note.body
from film_notes f
cross join lateral (values
    ('470f3e27-4b1c-5a4c-ae90-c3d0fe9cb291'::uuid, f.european_note),
    ('ae1fe04b-4e55-5710-b478-aa2a6f32f7d4'::uuid, f.north_american_note)
) as note(author_id, body)
join public.profiles p on p.id = note.author_id and p.user_id is null and p.data->>'is_editorial' = 'true'
on conflict (id) do nothing;
