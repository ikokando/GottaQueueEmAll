# Changelog

## 1.3.0

- **Invite card:** when a leader invites you, a card at the top of the screen shows the
  dungeon's art, the key, the leader with rating and best run, the group with your spot in
  gold and the role you join as. Accept or Decline right there, no Blizzard window.
- **Several invites at once** stack below the card; a click brings one into it, so you pick
  the group you want instead of the first one that came in.
- **No second confirmation:** Blizzard's "You have joined a group" with its OK is closed; a
  short message at the top says it and fades by itself.
- Settings: "Answer invites in our card" (on). Off: Blizzard's invite window as before.
  Preview shows the card.
- Fix: the "You" mark under the minimum leader rating no longer runs into "0" or "3600".

## 1.2.1

- Ready for patch 12.1.7: the addon is listed as up to date there too.
- Also on Wago Addons from now on.

## 1.2.0

- **Keystone Deserter:** Blizzard's mark for leaving Mythic+ runs early, shown as a rose
  DESERTER tag with a soft shine: on group cards (the leader, or "1 DESERTER IN GROUP"), on
  applicants in Your Group, and next to your own name in the footer when it's you (with a
  tooltip on how to lose it). Shown, never filtered.
- **Your applications:** a bar above the list in Mythic+, Raid and Mythic 0 while you wait on
  groups: dungeon art, key, leader, how long you've waited, an × to cancel, invites in gold.
  It stays through new searches. At 5 / 5 the Sign up buttons say so.
- **Alerts:** when you're invited or someone applies to the group you lead, a soft gold edge
  on the screen, a short message at the top (click: Your Group), a sound and the taskbar
  icon flashing while WoW is in the background. No applicant alerts in someone else's group;
  the message goes away once you join.
- **Settings in the window:** the gear (and the minimap button's right-click, `/gotta
  settings`) opens a settings page in the window: alerts with a preview, the group list,
  the footer, minimap button, hotkey, size.
- **Great Vault in the footer:** this week's Mythic+ runs with the three vault slots, their
  key and item level in the tooltip (a click opens the Great Vault), and this week's affixes
  as icons.
- **Listed a while:** Mythic+ groups listed for 20 minutes or more with 2 players or fewer get
  a quiet hint; they stay in the list.
- Fixes: opening the window while the Group Finder's data is restricted no longer errors;
  the dungeon chips notice when a best key turns from over time to in time.

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
