# Unnamed Travel Social Application

## Product

Create a native iPhone application for discovering European and North American destinations through real short videos and practical travel guides, planning personal journeys, and communicating with travelers. The owner delegated the visual direction and fifth feature and selected an independent Supabase project in the 139 organization. App name and IAP identifiers will be supplied later.

## Navigation and behavior

1. **Shorts:** immersive vertically paged real footage, one active AVPlayer, pause/resume, progress, search and destination filters, publisher details, likes, comments/replies, saves, sharing, report/block and personal video upload with title/caption/license consent. Uploaded videos remain pending actual review. Never fabricate live broadcasting or engagement.
2. **Explore:** MapKit destination pins plus a list; regional/category/search filtering; place details with photographs, practical original-English guides, source links, saved-place state, directions in Maps, share and Add to journey. Cover distinctive European and North American attractions. Do not hard-code volatile opening hours or ticket prices as guarantees.
3. **Journeys:** private day-by-day itineraries, place selection/reordering/removal, trip dates, checklists, estimated budget and notes. Save changes to the authenticated owner's backend; do not invent bookings or AI responses. Empty personal journeys stay empty until created.
4. **Chats:** empty first inbox; discover actual public member profiles by name/ID; create direct or group conversations, real persistent messages, replies and read state, realtime refresh/reconnect, drafts, pinned/muted/archived state, search/filter, photo attachments, profile navigation and safety actions. Unavailable RTC calls must state their actual limitation and never show a connected call.
5. **Me:** own avatar, name, biography, truthful counts, works/liked/saved/pending collections; wallet and transaction history; edit profile; blocked/reported lists, media credits, agreements, logout and own-account deletion. Wallet starts at zero, missing products are unavailable and prices come from StoreKit only. No fake payment or client-controlled balance.

## Entry and visual design

Cold launches show a travel welcome and explicit consent/login action. Restore the real guest identity securely, and authenticate only after explicit entry. Explain guest access loss. Persist consent version after successful write. All app-owned text uses packaged custom fonts; large editorial headings and handwritten accents evoke a travel journal. Generated raster icon family and generated watercolor/paper backgrounds use cream, deep teal and warm ochre. Real photographs and footage provide the content. Five-tab floating dock hides on pushed details; safe areas and keyboard avoidance remain native. Accessible labels, at least 44pt tap targets, Dynamic Type and Reduce Motion are required.

## Architecture and evidence

iOS 16+, Swift 5, UIKit and AVFoundation. New source is separated into shell/design, features and Supabase-backed store. The verified Teto archive is extracted outside the app as a reference; Bibi and Toti are read-only references for detail and safety behavior. Never copy their private data or integration identity. Backend stage A only: independent project, guest authentication, RLS, actual business data and media, chat subscriptions and versioned PDF agreements. No AI is required.

Compilation, typechecking, app launch, simulator use and runtime tests are not authorized. Produce static evidence separately from bounded backend API evidence and leave device acceptance open. Name, Bundle ID registration, team, legal operator details, final product IDs and actual Apple purchase verification remain release dependencies.
