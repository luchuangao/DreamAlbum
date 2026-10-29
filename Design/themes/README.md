# Theme design references

Current build 18 defaults to 原生银灰 / Native Silver and offers 雾蓝晨光 / Morning Blue and 蓝紫珍珠 / Blue Pearl. 冰蓝薄荷 / Ice Mint has been removed; saved iceMint values resolve to Native Silver. The original images below are historical design references, including the retired mint concept, and are not runtime assets.

## Original selections — build 14

- `mist-blue.jpg`: first ideation set, second displayed result; 雾蓝晨光 / Morning Blue. Default.
- `ice-mint.jpg`: second ideation set, first displayed result; 冰蓝薄荷 / Ice Mint.
- `blue-pearl.jpg`: second ideation set, second displayed result; 蓝紫珍珠 / Blue Pearl.

Selected by the user on 2026-10-28. Generated UI references, not user photos. Native SwiftUI colors/gradients and SF Symbols implement the appearance; these full-screen images are design references, not runtime page backgrounds. Actual photo and screenshot content is never recolored.

Selection lives in device UserDefaults under `dream_album.appearance_theme.v1`; it is separate from existing dream background keys, dream JSON and iCloud backups. Unknown and retired values fall back to Native Silver. Switch in 我的 → 背景主题 (Me → Background theme).

Build 15 adjusts these initial palettes after the user's real-phone feedback: stronger blue, mint and blue/lavender background colors throughout each gradient, with darker accents and secondary text. The images above remain the original selected concepts; `AppTheme.swift` defines the current native palette. Theme IDs and saved selections are unchanged.
