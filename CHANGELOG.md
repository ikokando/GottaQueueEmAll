# Changelog

## 1.0.0

A new addon: Gotta Queue 'Em All is now a Mythic+ group finder in its own window.
The sidebars on Blizzard's Premade Groups window, their presets and their settings are gone.

- **Browse:** season dungeon chips with your best keys, minimum leader rating with a
  histogram, spot for your role; a key-level range slider (each group's key is measured from
  its title) and sorting by key; cards with dungeon art, key, leader, roles in class color,
  Lust / B-Res, rating and age; hide groups by key, the leader's best in the dungeon,
  Lust / B-Res fit or a decline; sign up and cancel on the card; shows when the server
  found more groups than it sent.
- **Your Group:** your listing with art, key and requirements; edit requirements, delist;
  your party's slots; applicants with rating, item level, best run, Lust / B-Res and
  "looking for" marks; invite and decline; waiting count on the tab.
- **+ Create:** list your keystone with playstyle, minimum rating and item level, private
  group and own faction only. Blizzard prepares the listing's title first (12.1.5 only lets
  Blizzard's own code write it).
- Raider.IO profiles in tooltips and a "MAIN" tag for alts with a stronger main.
- Minimap button, hotkey (set from the window), addon compartment entry.
- Resizable window that remembers its size and position; closes when combat starts.
- New look: navy and gold, Barlow Semi Condensed, Blizzard's rating, key and class colors.
- Settings: Minimap button, Key Bindings, reset the window. Old settings are cleaned up.
- `/gotta help` lists the commands; `/gotta keyprobe` and `/gotta uidebug` check the key
  reader and + Create for bug reports.

## 0.5.1

- Fixed an "AddOn tried to call the protected function" error when building a Mythic+ listing. The "Playstyle in title" option was removed: Blizzard doesn't let addons change the group title, so it always uses Blizzard's own title (e.g. "+12 Relaxed").

## 0.5.0

First public release.

- Larger Premade Groups window with a docked search sidebar: dungeon tiles, roles, rating, difficulty and playstyle dropdowns, languages.
- "Fits my group" toggles (room for my party, Bloodlust, battle res, not declined), badges on every row and an "N of M groups match" counter.
- Leader's Mythic+ score and best key for that dungeon on every row.
- Named search presets (left-click loads and searches).
- Start a Group sidebar: listing presets, your own keystone, requirements, playstyle, and a one-click relist.
- Settings in Options > AddOns, `/gotta` or `/gqea`.
- Optional EllesmereUI look when its Blizzard skin is active.
