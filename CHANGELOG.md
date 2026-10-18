# Changelog

## 1.1.0

Gotta Queue 'Em All is now a Group Finder suite: Mythic+, Raid and Mythic 0, in one window.

- **Raid:** this season's raids (Season 1 on request) at Normal, Heroic and Mythic. Cards
  with the group's killed bosses, size by role, item level and its members; filters for
  difficulty, bosses killed, group size, your role's spot, your item level, Lust and
  declines; your lockout on each raid. List your own raid group.
- **Mythic 0:** this season's dungeons on Mythic, no keystone: search, filter and list
  like in Mythic+, without your key in the title.
- **Title box in the window:** + Create shows Blizzard's own title box styled like the
  window (only you may type a title); it tells you clearly when a title is missing.
  Listing jumps to Your Group.
- **View: Role | Spec:** members as role glyphs in class color, or with their spec under
  each glyph. Raid cards show every member in one line.
- **Welcome screen** on the first start, with the three sections, your hotkey and the
  minimap button; `/gotta welcome` brings it back.
- Mythic+: the minimum leader rating now filters the groups already found at once.
- Tooltips list the open spots of a group.
- PvP announced in the header (coming soon).
- Bigger settings and close buttons with a larger click area.
- Fixes: listing again after a delist, searching after a delist, a section's results no
  longer show up in (or empty) another section, raid and dungeon picks from an older
  list, "Any" item level in Your Group's editor, the title box after Blizzard's window
  opened, steadier sorting.
- Faster: hidden pages no longer re-read every search, result updates redraw only when
  one of their groups changed.
- Removed the developer commands (`/gotta uidebug`); `/gotta keyprobe` stays for bug
  reports.

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
