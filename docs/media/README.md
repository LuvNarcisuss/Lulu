# Travel media and visual assets

## Delivery

The public catalog contains 11 recorded travel films, 11 matching covers, 12 destination records, 12 original-English guides, and two explicitly editorial publishers. There are 14 destination photographs, including two optional alternate views. No engagement, member accounts, private collections or online status is seeded.

- `Assets/catalog.json`: flat records matching `docs/tasks/interfaces.md`; UUIDv5 identifiers remain stable when regenerated.
- `Assets/media-manifest.json`: every business-media object path, local file, SHA-256, byte count, dimensions, video duration/frame rate, source, creator where identified, license, processing and actual scene review.
- `Assets/video-sources.json` and `Assets/photo-sources.json`: selected upstream source metadata. An uncredited Mixkit creator remains null instead of being invented.
- The 36 catalog media files (49,924,918 bytes) are served from the dedicated Supabase project. The manifest `path` identifies each bucket and object, and `local_file` identifies its ignored staging path under `Assets/catalog/`. Keep catalog binaries out of the checkout, Git, and the application target.
- `TravelApp/Resources/Assets.xcassets/`: 36 generated transparent raster icons, two generated portrait backgrounds and one independently generated opaque AppIcon. These are bundled shell resources.
- `TravelApp/Resources/Fonts/`: licensed custom typography and OFL licenses. Exact font names and registration paths are recorded in `fonts.json`.

## Actual scene review

All downloaded photographs were opened in an actual-image contact sheet, `inspection/all-photos.jpg`. All published films were inspected at the beginning, middle and end through extracted representative frames; the selected NPS source was also sampled across its longer sequence. `inspection/all-videos.jpg` shows the final published clips, and individual `*-review.jpg` files preserve their frame triplets. The inspection images are local review artifacts and are excluded from Git. Representative-frame inspection is not a claim of viewing every frame.

Named scenes include the daytime Eiffel Tower, Venetian canals and alleys, Tower Bridge and Elizabeth Tower, Times Square, the Colosseum, a Swiss mountain train with the Matterhorn, and Yosemite National Park. The Iceland video source identifies the country but not the waterfall. Its clip therefore has a null `place_id`, and its caption does not assert a specific waterfall. The Iceland destination photograph is source-identified Dynjandi; that does not establish the video's location.

Three initially considered Mixkit films were excluded: a desert scene whose source category did not establish the implied California location, an unidentified Canadian town, and an unidentified Canadian mountain area. Their bytes are not in the project catalog. The final catalog favors source-supported locations.

No generated image substitutes for real destination photography or footage. Real-world signage in the Times Square and Lisbon scenes is incidental location content, not app-owned copy or an endorsement. The Eiffel Tower film is daytime footage; nighttime illumination footage was excluded.

## Sources and licenses

The item-level source and license links in the manifest are authoritative provenance records. The sources were accessed on 2026-11-03.

- [Pexels License](https://www.pexels.com/license/) allows use and modification in applications. Media is used here within editorial travel discovery and planning, with creator credits and primary planning links. It is not sold as unaltered stock, offered as a wallpaper library, or used to imply creator/brand endorsement.
- [Mixkit Stock Video Free License](https://mixkit.co/license/#videoFree) applies only to the seven selected Mixkit items whose source metadata and item pages explicitly mark the Free License. Restricted-license items were excluded. The full Free License modal response is preserved in `mixkit-video-free-license.html`; [Mixkit User Terms](https://mixkit.co/terms/) also apply.
- [Yosemite Stock Footage (2021)](https://www.nps.gov/media/video/view.htm?id=A45A7B7C-295C-4718-B5FA-FE30882C291F) explicitly identifies all footage in this source as public domain and usable for any purpose. One ten-second excerpt, source interval 114–124 seconds, is used and credited to the National Park Service. The source file's SHA-256 is recorded; the complete 12-minute source is not an app dependency or repository artifact.
- Guide paragraphs are original short paraphrases linked to official tourism, destination-operator, National Park Service or Parks Canada pages. They avoid fixed prices, opening-hour guarantees and future-year access claims. Current arrangements must be checked at the linked source.

## Generated shell imagery

The built-in `image_gen.imagegen` tool generated the icons and backgrounds. The tool does not disclose a model version, so no engine version is invented. Exact prompts, original generated file paths, workspace copies and processing are recorded in `Assets/generated/generation-record.json`. Design originals under `Assets/generated/` are excluded from Git. The application uses the processed copies in its asset catalog.

The 6x6 icon sheet follows the exact shared row-major contract. Each cell was alpha-cropped, fitted proportionally within 144x144 and centered on a transparent 160x160 PNG. The sheet's generated alpha is preserved; no icons were drawn in code. The AppIcon is a separate 1254x1254 model original downsampled to 1024x1024 RGB, with no baked corner mask. The two 1024x1536 background originals are copied without pixel changes. All selected originals were visually inspected, including their actual alpha, absence of app-name text and the icon ordering.

The welcome illustration is a watercolor collage, not a geographically literal destination photograph. It deliberately has no selected app brand or name. A separate opaque 1024x1024 travel-compass AppIcon is generated for this unnamed application. It carries no name or final brand; the owner-selected app name remains a release dependency.

## Fonts

| Registration file | UIKit PostScript name | Use |
| --- | --- | --- |
| `Fonts/Fraunces-TravelDisplay.ttf` | `FrauncesTravelDisplay-Semibold` | Display headings |
| `Fonts/Kalam-Regular.ttf` | `Kalam-Regular` | Body and controls |
| `Fonts/Kalam-Bold.ttf` | `Kalam-Bold` | Emphasis |

Kalam is unmodified upstream Google Fonts content. Fraunces is derived from its openly licensed variable font using fontTools 4.68.0: `wght=600`, `opsz=72`, `SOFT=50`, `WONK=1`. Its internal names identify this static instance. The unmodified variable source is retained outside bundled resources in `Assets/generated/Fraunces-variable-source.ttf`. Both fonts use SIL Open Font License 1.1; license texts remain beside the bundled font files. No machine-installed font or system-font rendering is required for this delivery.

## Verification boundary

For editorial maintenance, the local media scripts require temporarily staged copies at the manifest paths under `Assets/catalog/`. With those inputs, `python3 scripts/media_verify.py` checks file integrity, UUIDs, flat DTO field sets, object and relationship references, source/license links, video metadata, image dimensions, alpha and bundle separation. Its current result is preserved in `static-inspection.json`. `media_inspect.py` reproduces final representative-frame sheets. `media_catalog.py` regenerates the original editorial DTOs and manifest from the selected sources and current media; it is not a cloud deployment script.

Only static resource inspection and media processing were performed. No app compilation, typecheck, simulator, app launch, Preview, StoreKit check or app runtime acceptance was performed. Supabase upload and public-byte verification belong to the backend worker's separate deployment evidence. No claim of app runtime or production availability follows from this asset delivery.
