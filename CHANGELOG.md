# Changelog — MediaFlow Monitor

## macOS v1.10.0 (2026-09-15) — Vizibilitate, siguranta si context NLE

### Added
- Banner de scurtatura in Dashboard: afiseaza combinatia reala (⌘⇧M), cu buton
  de copiere si bifa „Porneste minimizat" (preferinta persistenta).
- Confirmare inainte de „Optimizeaza memoria" si inainte de golirea cache-ului,
  cu explicatie a efectului; dialogul de cache are optiunea „Sterge si nu ma mai
  intreba".
- Tooltips pe toate cele patru butoane de actiune.
- Detectare NLE activ (DaVinci Resolve / Premiere Pro / Final Cut Pro) cu
  consumul propriu de RAM, afisat ca badge in cardul de stare.
- Avertizari de memorie cu recomandari concrete la RAM ≥85% si ≥95%, plus
  calificator de sanatate (Excelent / Atentie / Critic).

### Fixed
- `scripts/build-macos-app.sh` esua pentru ca `dist/version-manifest.json` a fost
  sters din greseala la v1.9.1, desi `sync-site.sh` il foloseste ca sursa de
  adevar pentru update.json. Fisierul a fost restaurat.

## Windows v1.9.4 (2026-09-14) — Contrast

### Fixed
- Fereastra de progres a actualizarii aparea alba cu text negru, indiferent de
  tema aplicatiei.
- Consola de actiuni ramanea inchisa la culoare si pe tema deschisa.

## Windows 1.9.3 (2026-09-11) — Semnare digitala a aplicatiei

Executabilul si installer-ul Windows sunt acum semnate digital la fiecare build.
Versiunea Mac ramane 1.9.2 (neschimbata - modificarea e strict pe Windows).

Jurnal scurt, orientat spre utilizator, al schimbărilor livrate clienților
— o intrare per versiune, cu dată. Complementar jurnalului tehnic detaliat
din CLAUDE.md (acolo sunt și deciziile/motivele/pitfall-urile; aici doar
rezumatul a "ce s-a schimbat", ușor de scanat rapid).

## v1.9.2 (2026-09-06) — Ghidul PDF, accesibil acum din fereastra de Ajutor

Ghidul PDF (`Instructiuni_Utilizare.pdf`) exista deja în arhiva de
descărcare, dar nu putea fi deschis din interiorul aplicației. Buton nou
„Deschide ghidul complet (PDF)” în fereastra de Ajutor (Help), sub
ghidul rapid deja existent.

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
