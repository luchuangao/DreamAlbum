# Project workflow

- Preserve the native SwiftUI / PhotoKit app, iOS 17+, iPad, Mac Catalyst, existing dream data, widgets and iCloud formats.
- Keep Chinese and English UI copy concise.
- After each version update, run checks relevant to the changes, commit the project source and documentation, and push to https://github.com/luchuangao/DreamAlbum. The user explicitly requested this workflow on 2026-10-27. Preserve remote history; never force-push.
- Include the build number and validation in the commit / handoff. Do not publish an App Store release unless requested.
- Exclude DerivedData, archives, device data, private user photos, signing credentials, and raw local test artifacts from commits. Keep local test evidence under .ui-checks/ and summarize useful results in VALIDATION.md.
