# Changelog — MediaFlow Monitor

Jurnal scurt, orientat spre utilizator, al schimbărilor livrate clienților
— o intrare per versiune, cu dată. Complementar jurnalului tehnic detaliat
din CLAUDE.md (acolo sunt și deciziile/motivele/pitfall-urile; aici doar
rezumatul a "ce s-a schimbat", ușor de scanat rapid).

## v1.9.1 (2026-08-31) — Preț dinamic din Furnizor (Mac + Windows)

Suma de donație din mesajul WhatsApp de activare se citește acum din
`pricing.json` (Furnizor), nu mai e fixă în cod — orice ofertă programată
apare automat, fără recompilare.

## v1.9.0 (2026-08-31) — GPU Monitor + Thermal Monitor

Două module noi de monitorizare, adăugate în Dashboard-ul Pro (Mac + Windows):
- **GPU Monitor** — utilizare GPU live (%), afișată ca grafic, alături de
  VRAM/CPU. Pe unele PC-uri/Mac-uri fără driver compatibil, afișează
  "Necunoscut" în loc de o valoare inventată.
- **Thermal Monitor** — avertizare când sistemul se apropie de/atinge
  throttling termic (notificare nativă + badge colorat în Dashboard).
