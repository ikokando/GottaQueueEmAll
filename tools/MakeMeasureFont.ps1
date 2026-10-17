param([string]$Dir)
# Builds media/fonts/GQEA-Measure.ttf, the invisible font UI/KeyRead.lua
# measures titles with:
#   powershell -File tools\MakeMeasureFont.ps1 -Dir media\fonts
# Glyphs: 0 .notdef (advance 0), 1 every other character of U+0000..U+2FFF
# and U+FF00..U+FFEF (empty, advance 0), 2 '+' (PLUS), 3..12 '0'..'9'
# (DIGIT + STEP * d). Every glyph has a box outline (WoW swaps glyphs without
# one for its default font's); digits get a wide one (see Build). unitsPerEm
# 1000; the widths must match KeyRead's constants.
$code = @"
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;

public static class MeasureFont {
    const int UPEM = 1000;
    // Advances in font units (UPEM 1000). At font size S, px = units * S / 1000.
    static void U16(List<byte> b, int v) { b.Add((byte)((v >> 8) & 0xFF)); b.Add((byte)(v & 0xFF)); }
    static void U32(List<byte> b, uint v) { b.Add((byte)(v >> 24)); b.Add((byte)(v >> 16)); b.Add((byte)(v >> 8)); b.Add((byte)v); }
    static void I64(List<byte> b, long v) { for (int i = 7; i >= 0; i--) b.Add((byte)(v >> (8 * i))); }
    static void Pad(List<byte> b) { while (b.Count % 4 != 0) b.Add(0); }
    static uint Sum(byte[] d) {
        uint s = 0;
        for (int i = 0; i < d.Length; i += 4) {
            uint v = 0;
            for (int j = 0; j < 4; j++) v = (v << 8) | (uint)(i + j < d.Length ? d[i + j] : 0);
            s = unchecked(s + v);
        }
        return s;
    }

    public static void Build(string path, string family, int plus, int digit, int step, int digitInk) {
        int n = 13;
        int[] adv = new int[n];
        adv[0] = 0; adv[1] = 0; adv[2] = plus;
        for (int d = 0; d <= 9; d++) adv[3 + d] = digit + step * d;
        int advMax = 0; foreach (int a in adv) advMax = Math.Max(advMax, a);
        int inkMax = Math.Max(100, digitInk);

        var tables = new SortedDictionary<string, byte[]>(StringComparer.Ordinal);

        // glyf: every glyph is a square-ish box (WoW takes a glyph without an
        // outline for a missing one and uses its default font's). Digits are
        // digitInk wide: WoW counts the last glyph of a line by its ink, and
        // the wrap test in KeyRead needs that ink. The text is never shown.
        var glyf = new List<byte>();
        var loca = new List<byte>();
        for (int g = 0; g < n; g++) {
            int w = g >= 3 ? digitInk : 100;
            U32(loca, (uint)glyf.Count);
            U16(glyf, 1); U16(glyf, 0); U16(glyf, 0); U16(glyf, w); U16(glyf, 100);
            U16(glyf, 3); U16(glyf, 0);
            for (int i = 0; i < 4; i++) glyf.Add(0x01);
            int[] xs = { 0, 0, w, 0 };    // deltas: (0,0) (0,100) (w,100) (w,0)
            int[] ys = { 0, 100, 0, -100 };
            foreach (int x in xs) U16(glyf, x & 0xFFFF);
            foreach (int y in ys) U16(glyf, y & 0xFFFF);
            Pad(glyf);
        }
        U32(loca, (uint)glyf.Count);
        tables["glyf"] = glyf.ToArray();
        tables["loca"] = loca.ToArray();

        var head = new List<byte>();
        U32(head, 0x00010000); U32(head, 0x00010000); U32(head, 0); U32(head, 0x5F0F3CF5);
        U16(head, 0x000B); U16(head, UPEM); I64(head, 0); I64(head, 0);
        U16(head, 0); U16(head, 0); U16(head, inkMax); U16(head, 100);
        U16(head, 0); U16(head, 8); U16(head, 2); U16(head, 1); U16(head, 0);
        tables["head"] = head.ToArray();

        var hhea = new List<byte>();
        U32(hhea, 0x00010000); U16(hhea, 800); U16(hhea, (-200) & 0xFFFF); U16(hhea, 0);
        U16(hhea, advMax); U16(hhea, 0); U16(hhea, 0); U16(hhea, inkMax);
        U16(hhea, 1); U16(hhea, 0); U16(hhea, 0);
        U16(hhea, 0); U16(hhea, 0); U16(hhea, 0); U16(hhea, 0);
        U16(hhea, 0); U16(hhea, n);
        tables["hhea"] = hhea.ToArray();

        var hmtx = new List<byte>();
        foreach (int a in adv) { U16(hmtx, a); U16(hmtx, 0); }
        tables["hmtx"] = hmtx.ToArray();

        var maxp = new List<byte>();
        U32(maxp, 0x00010000); U16(maxp, n); U16(maxp, 4); U16(maxp, 1);
        U16(maxp, 0); U16(maxp, 0); U16(maxp, 2); U16(maxp, 0); U16(maxp, 0);
        U16(maxp, 0); U16(maxp, 0); U16(maxp, 0); U16(maxp, 0); U16(maxp, 0); U16(maxp, 0);
        tables["maxp"] = maxp.ToArray();

        // cmap format 4: every character of U+0000..U+2FFF and U+FF00..U+FFEF
        // is mapped (so no fallback font steps in): '+' -> 2, '0'..'9' -> 3..12,
        // everything else -> 1 (empty, advance 0).
        int[][] segs = { new[] { 0x0000, 0x2FFF }, new[] { 0xFF00, 0xFFEF }, new[] { 0xFFFF, 0xFFFF } };
        var ids = new List<int>();
        int[] first = new int[segs.Length];
        for (int i = 0; i < segs.Length - 1; i++) {
            first[i] = ids.Count;
            for (int c = segs[i][0]; c <= segs[i][1]; c++) {
                int g = 1;
                if (c == 0x2B) g = 2;
                else if (c >= 0x30 && c <= 0x39) g = 3 + (c - 0x30);
                ids.Add(g);
            }
        }
        int segCount = segs.Length;
        int segX2 = segCount * 2;
        int searchRange = 2; int entrySel = 0;
        while (searchRange * 2 <= segX2) { searchRange *= 2; entrySel++; }
        var sub = new List<byte>();
        U16(sub, 4); U16(sub, 16 + segCount * 8 + ids.Count * 2); U16(sub, 0);
        U16(sub, segX2); U16(sub, searchRange); U16(sub, entrySel); U16(sub, segX2 - searchRange);
        foreach (var s in segs) U16(sub, s[1]);
        U16(sub, 0);
        foreach (var s in segs) U16(sub, s[0]);
        for (int i = 0; i < segCount; i++) U16(sub, i == segCount - 1 ? 1 : 0);                 // idDelta
        for (int i = 0; i < segCount; i++) U16(sub, i == segCount - 1 ? 0 : (segCount - i) * 2 + first[i] * 2);
        foreach (int g in ids) U16(sub, g);
        var cmap = new List<byte>();
        U16(cmap, 0); U16(cmap, 2);
        U16(cmap, 0); U16(cmap, 3); U32(cmap, 20);
        U16(cmap, 3); U16(cmap, 1); U32(cmap, 20);
        cmap.AddRange(sub);
        tables["cmap"] = cmap.ToArray();

        var post = new List<byte>();
        U32(post, 0x00030000); U32(post, 0); U16(post, (-100) & 0xFFFF); U16(post, 50);
        U32(post, 0); U32(post, 0); U32(post, 0); U32(post, 0); U32(post, 0);
        tables["post"] = post.ToArray();

        string[] names = { "", family, "Regular", family + " 1.0", family, "Version 1.0", family.Replace(" ", "") };
        var strs = new List<byte>();
        var recs = new List<byte>();
        for (int id = 1; id < names.Length; id++) {
            byte[] s = Encoding.BigEndianUnicode.GetBytes(names[id]);
            U16(recs, 3); U16(recs, 1); U16(recs, 0x409); U16(recs, id); U16(recs, s.Length); U16(recs, strs.Count);
            strs.AddRange(s);
        }
        var name = new List<byte>();
        U16(name, 0); U16(name, names.Length - 1); U16(name, 6 + recs.Count);
        name.AddRange(recs); name.AddRange(strs);
        tables["name"] = name.ToArray();

        var os2 = new List<byte>();
        U16(os2, 4); U16(os2, digit); U16(os2, 400); U16(os2, 5); U16(os2, 0);
        for (int i = 0; i < 10; i++) U16(os2, 0);       // subscript .. strikeout
        U16(os2, 0);                                     // sFamilyClass
        for (int i = 0; i < 10; i++) os2.Add(0);         // panose
        U32(os2, 1); U32(os2, 0); U32(os2, 0); U32(os2, 0);
        os2.AddRange(Encoding.ASCII.GetBytes("NONE"));
        U16(os2, 0x40); U16(os2, 0x20); U16(os2, 0x39);
        U16(os2, 800); U16(os2, (-200) & 0xFFFF); U16(os2, 0); U16(os2, 800); U16(os2, 200);
        U32(os2, 1); U32(os2, 0);
        U16(os2, 500); U16(os2, 700); U16(os2, 0); U16(os2, 0x20); U16(os2, 1);
        tables["OS/2"] = os2.ToArray();

        int num = tables.Count;
        int sr = 1, es = 0; while (sr * 2 <= num) { sr *= 2; es++; }
        var font = new List<byte>();
        U32(font, 0x00010000); U16(font, num); U16(font, sr * 16); U16(font, es); U16(font, num * 16 - sr * 16);
        int offset = 12 + num * 16;
        var body = new List<byte>();
        int headOffset = 0;
        foreach (var kv in tables) {
            byte[] data = kv.Value;
            font.AddRange(Encoding.ASCII.GetBytes(kv.Key));
            U32(font, Sum(data)); U32(font, (uint)(offset + body.Count)); U32(font, (uint)data.Length);
            if (kv.Key == "head") headOffset = offset + body.Count;
            body.AddRange(data); Pad(body);
        }
        font.AddRange(body);
        byte[] all = font.ToArray();
        uint adj = unchecked(0xB1B0AFBA - Sum(all));
        all[headOffset + 8] = (byte)(adj >> 24); all[headOffset + 9] = (byte)(adj >> 16);
        all[headOffset + 10] = (byte)(adj >> 8); all[headOffset + 11] = (byte)adj;
        File.WriteAllBytes(path, all);
    }
}
"@
Add-Type -TypeDefinition $code -Language CSharp
# KeyRead uses size 64: one px is 15.625 font units.
# GQEA-Measure: '+' 1280 px (wider than any "digit + word" line, see
# KeyRead), digit d 2560 + 128 * d px with 128 px of ink; everything else
# 0 px (WoW adds 1 px per glyph on its own).
$measure = Join-Path $Dir 'GQEA-Measure.ttf'
[MeasureFont]::Build($measure, 'GQEA Measure', 20000, 40000, 2000, 2000)
Get-Item $measure | Select-Object Name, Length

