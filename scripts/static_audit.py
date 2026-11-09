#!/usr/bin/env python3
"""Inspect project configuration, resources, references and source without building."""
from pathlib import Path
import hashlib
import json
import plistlib
import re
import sys
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
app = root / 'TravelApp'
errors = []
checks = []

def require(condition, message):
    if condition:
        checks.append(message)
    else:
        errors.append(message)

info = plistlib.loads((app / 'Support/Info.plist').read_bytes())
identity = json.loads((app / 'Configuration/Identity.json').read_text())
project = (app / 'TravelApp.xcodeproj/project.pbxproj').read_text()
source_config = (app / 'project.yml').read_text()
require(info['CFBundleDisplayName'] == identity['displayName'] == '', 'App display name remains owner-unconfigured')
require(info['UIDeviceFamily'] == [1], 'Info.plist supports iPhone only')
require(info['UISupportedInterfaceOrientations'] == ['UIInterfaceOrientationPortrait'], 'App orientation is portrait')
for setting in ['SUPPORTS_MACCATALYST', 'SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD', 'SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD']:
    require(re.search(rf'{setting} = NO;', project) is not None, f'Generated project disables {setting}')
require('TARGETED_DEVICE_FAMILY = 1;' in project, 'Generated project selects iPhone device family')
require('SWIFT_VERSION = 5.0;' in project, 'Generated project selects Swift 5 language mode')
require('IPHONEOS_DEPLOYMENT_TARGET = 16.0;' in project, 'Generated project selects iOS 16 minimum')
require(identity['bundleIdentifier'] in project and identity['bundleIdentifier'] in source_config, 'Engineering Bundle ID agrees with configuration source')
schemes = [scheme for entry in info['CFBundleURLTypes'] for scheme in entry['CFBundleURLSchemes']]
require(schemes.count(identity['bundleIdentifier']) == 1 and schemes.count('travelapp') == 1, 'Release identity and friend URL schemes are present once')
for key in ['NSCameraUsageDescription', 'NSPhotoLibraryUsageDescription', 'NSMicrophoneUsageDescription']:
    require(isinstance(info.get(key), str) and bool(info[key].strip()), f'{key} is a nonempty English declaration')
for font in info['UIAppFonts']:
    require((app / 'Resources' / font).is_file(), f'Packaged custom font exists: {font}')
ET.parse(app / 'Support/LaunchScreen.storyboard')
checks.append('Launch storyboard XML parses')

assets = app / 'Resources/Assets.xcassets'
for manifest in assets.rglob('Contents.json'):
    data = json.loads(manifest.read_text())
    for item in data.get('images', []):
        if 'filename' in item:
            require((manifest.parent / item['filename']).is_file(), f'Asset file exists: {manifest.parent.name}/{item["filename"]}')
for swift in (app / 'Sources').rglob('*.swift'):
    content = swift.read_text()
    require(not re.search(r'[\u3400-\u9fff]', content), f'Authored Swift content is English: {swift.name}')
    require(not any(token in content for token in ['UIImage(systemName:', 'UIFont.systemFont', 'UIFont.boldSystemFont', 'UIHostingController', 'import SwiftUI']), f'Custom raster/font/UIKit discipline: {swift.name}')
    for icon in set(re.findall(r'"(icon-[a-z-]+)"', content)):
        require((assets / (icon + '.imageset')).is_dir(), f'Generated icon reference resolves: {icon}')
    require('service_role' not in content and 'sb_secret_' not in content, f'No privileged Supabase credential in client source: {swift.name}')

core = (app / 'Sources/Core/Application.swift').read_text()
for route in ['ShortsController', 'ExploreController', 'JourneysController', 'ChatsController', 'MeController']:
    require(route + '(store: store)' in core, f'Five-tab root route exists: {route}')
require('dock.distribution = .fillEqually' in core and len(re.findall(r'"icon-(?:shorts|explore|journeys|chats|profile)"', core)) >= 5, 'Dock uses five equal destinations')
payment = json.loads((app / 'Resources/PaymentCatalog.json').read_text())
require(len(payment['tiers']) == 7 and all(offer['productID'] == '' for offer in payment['tiers']), 'Seven wallet tiers have no inherited product IDs')
require('storeKitConfiguration' not in source_config, 'Scheme has no local StoreKit catalog masquerading as Apple availability')
require(not any(s in project for s in ['catalog/videos/', 'catalog/places/', 'catalog/covers/']), 'Business media is excluded from the application bundle')
for file in (app / 'Resources/Legal').glob('*.pdf'):
    require(file.read_bytes().startswith(b'%PDF-'), f'Bundled agreement is actual PDF: {file.name}')

summary = {
    'kind': 'Static source/configuration/resource audit only',
    'swift_files': len(list((app / 'Sources').rglob('*.swift'))),
    'passed_assertions': len(checks),
    'errors': errors,
    'identity_pending': ['app display name', 'registered Bundle ID', 'development team', 'owned IAP product IDs', 'operator details'],
    'runtime_performed': False,
    'limitations': ['No compilation or typechecking', 'No dependency resolution', 'No app, Simulator or Preview launch', 'No UI or StoreKit runtime tests', 'APNs signing capability remains unconfigured'],
}
(root / 'docs/static-audit.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))
sys.exit(bool(errors))
