# codesigning/ — semnare Windows (Self-Signed, testare internă)

Vezi `CLAUDE.md` (Regula 34) pentru contextul complet al deciziei —
acest document acoperă DOAR pașii practici pentru repo-ul MediaFlow
Monitor. Implementarea de referință a acestui tipar trăiește în
`CGConvertor/codesigning/` — fișierele de aici sunt un port 1:1, adaptat
la structura acestui repo (`Windows/`, `Publish/Windows/win-<arch>/`,
`dist/`).

## De ce Self-Signed, și ce NU rezolvă

Un certificat self-signed **nu elimină avertismentul SmartScreen/"Unknown
publisher"** pentru publicul larg — doar un certificat real de la o CA
publică (cu reputație acumulată) sau un certificat EV fac asta. Self-signed
e util STRICT pentru:
- testare internă (buildurile pe care le rulează Cristi însuși),
- distribuire către un cerc restrâns de colaboratori care importă manual
  certificatul public (`.cer`) în Trusted Root o singură dată.

La lansarea comercială publică, planul e Azure Trusted Signing sau un
certificat EV (HSM cloud) — vezi CLAUDE.md Regula 34 pentru context complet.

## Certificatul e COMUN pentru toate aplicațiile GDC

Decizie explicită a lui Cristi: un SINGUR certificat self-signed, refolosit
pentru toate aplicațiile Windows din ecosistem (CGConvertor, MediaFlow
Monitor, orice aplicație viitoare) — secretele CI se numesc IDENTIC în
toate repo-urile (`WIN_SELFSIGN_PFX_BASE64`/`WIN_SELFSIGN_PFX_PASSWORD`),
dar GitHub Actions NU are secrete partajate între repo-uri — Cristi
încarcă aceeași valoare (`.pfx` base64 + parolă) separat, o dată per
repo. Un `.cer` public distribuit colaboratorilor le acoperă pe TOATE,
odată importat.

## Setup unic pe acest repo (o dată, făcut DIRECT de Cristi pe Windows real)

Certificatul (privat, cu cheie) nu trece niciodată prin conversația cu
Claude — la fel ca orice altă parolă/cheie din ecosistem.

**Dacă certificatul comun există deja** (ex. generat anterior pentru
CGConvertor) — sari peste generare, încarcă direct secretele pe acest
repo:
```powershell
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes("<cale-catre-gdc-selfsign.pfx-existent>"))
gh secret set WIN_SELFSIGN_PFX_BASE64 --repo gordasgdc/MediaFlow-Monitor --body $b64
gh secret set WIN_SELFSIGN_PFX_PASSWORD --repo gordasgdc/MediaFlow-Monitor
```
(al doilea comand cere parola interactiv — aceeași parolă folosită la
generarea inițială a certificatului.)

**Dacă certificatul nu există încă deloc în ecosistem** — generează-l:
1. Pe Windows real (Parallels e suficient), deschide PowerShell **ca
   Administrator** și rulează:
   ```powershell
   .\codesigning\generate-self-signed-cert.ps1
   ```
   Scriptul cere o parolă nouă (pentru `.pfx`) și produce două fișiere:
   - `gdc-selfsign.pfx` — **PRIVAT**, nu se distribuie, nu se comite în
     git.
   - `gdc-selfsign.cer` — **PUBLIC**, se distribuie colaboratorilor.
2. Încarcă `.pfx`-ul ca secrete GitHub Actions pe acest repo — comenzile
   exacte sunt afișate la finalul scriptului.
3. Șterge `.pfx`-ul local imediat după (`Remove-Item gdc-selfsign.pfx -Force`)
   — rămâne doar în secretele CI, criptate.
4. Distribuie `gdc-selfsign.cer` colaboratorilor (dacă nu l-au primit deja
   pentru alt repo GDC). Pe fiecare mașină a lor, o singură dată: dublu-click
   → **Install Certificate** → **Local Machine** → "Place all certificates
   in the following store" → **Trusted Root Certification Authorities**.

Odată făcuți pașii de mai sus, **fiecare build viitor din CI** (push pe
`main`) semnează automat `.exe`-ul și installer-ul cu ACELAȘI certificat —
colaboratorii nu mai trebuie să reimporte nimic la versiunile următoare.

## Ce face CI-ul automat (`.github/workflows/build-windows.yml`)

- Dacă secretele NU sunt setate: build-ul continuă **nesemnat**, exact ca
  până acum — nicio eroare, nicio schimbare de comportament.
- Dacă secretele SUNT setate: după ce `MediaFlowMonitor.exe`
  (`Publish\Windows\win-<arch>\MediaFlowMonitor.exe`) și installer-ul
  final Inno Setup (`dist\MediaFlowMonitorSetup-<arch>-<versiune>.exe`)
  există, ambele sunt semnate cu `signtool.exe` (localizat dinamic din
  Windows Kits, cu timestamp), apoi verificate cu
  `Get-AuthenticodeSignature` — confirmă DOAR că semnătura a fost atașată
  corect, fără să ceară lanț de încredere complet (asta ar eșua mereu pe
  un runner CI proaspăt, care nu are certificatul în Trusted Root — normal
  pentru self-signed, nu un bug). Un eșec real de semnare (fișier fără
  nicio semnătură) tot oprește build-ul (CI roșu). Copia STABILĂ
  (`MediaFlowMonitorSetup-<arch>.exe`, fără versiune în nume) e o copie
  directă a installer-ului DEJA semnat — moștenește semnătura automat.

## Regenerarea certificatului (dacă expiră sau e compromis)

Rulează din nou `generate-self-signed-cert.ps1`, reîncarcă secretele PE
TOATE repo-urile GDC (pasul de mai sus îi suprascrie pe cei vechi, dar
separat, pe fiecare repo) — și **toți colaboratorii trebuie să reimporte
noul `.cer`**, altfel văd din nou avertismentul pentru versiunile semnate
cu noul certificat. Evită regenerarea inutilă — de asta scriptul folosește
o valabilitate de 5 ani.
