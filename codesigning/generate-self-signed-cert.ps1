# generate-self-signed-cert.ps1
#
# Rulat O SINGURA DATA, de Cristi, pe Windows real (nu de Claude - un
# certificat cu cheie privata nu trece niciodata prin conversatie, vezi
# CLAUDE.md, Regula 34). Genereaza un certificat Self-Signed de Code
# Signing STABIL (valabil 5 ani) - NU se regenereaza la fiecare build,
# ca sa nu rupa increderea deja acordata de colaboratori.
#
# IMPORTANT - certificatul e COMUN pentru toate aplicatiile GDC (decizie
# explicita a lui Cristi, vezi CLAUDE.md Regula 34): daca certificatul
# `gdc-selfsign.pfx` a fost DEJA generat pentru un alt repo (ex.
# CGConvertor), NU rula acest script din nou aici - reincarca DOAR
# secretele (comenzile de la pasul 3 mai jos) folosind acelasi .pfx deja
# existent, cu `--repo gordasgdc/MediaFlow-Monitor`. Ruleaza acest script
# de la zero doar daca certificatul nu exista inca deloc in ecosistem,
# sau daca a expirat/a fost compromis.
#
# Foloseste:
#   1. Ruleaza acest script o data (PowerShell, ca Administrator).
#   2. Produce doua fisiere in acelasi folder:
#      - gdc-selfsign.pfx  (PRIVAT, cu cheie - NU se distribuie,
#        NU se comite in git, NU se lipeste in chat/conversatie)
#      - gdc-selfsign.cer  (PUBLIC, fara cheie - se distribuie
#        colaboratorilor pentru import manual in Trusted Root)
#   3. Incarca .pfx-ul ca secrete GitHub Actions PE ACEST REPO (comenzile
#      exacte sunt afisate la finalul scriptului) - secretele se numesc
#      IDENTIC in toate repo-urile GDC (WIN_SELFSIGN_PFX_BASE64/
#      WIN_SELFSIGN_PFX_PASSWORD), dar se incarca SEPARAT, o data per
#      repo (GitHub Actions nu are secrete partajate intre repo-uri).

$ErrorActionPreference = "Stop"

$subject = "CN=GDC Ecosystem (Self-Signed, testare interna)"
$pfxPath = Join-Path $PSScriptRoot "gdc-selfsign.pfx"
$cerPath = Join-Path $PSScriptRoot "gdc-selfsign.cer"
$pfxPassword = Read-Host -Prompt "Alege o parola noua pentru fisierul .pfx (o vei pune ca secret CI)" -AsSecureString

Write-Host "==> Generez certificatul self-signed (valabil 5 ani)..."
$cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject $subject `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -NotAfter (Get-Date).AddYears(5) `
    -KeyUsage DigitalSignature `
    -KeyAlgorithm RSA `
    -KeyLength 2048

Write-Host "==> Exporting .pfx (PRIVAT - nu distribui acest fisier)..."
Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $pfxPassword | Out-Null

Write-Host "==> Exporting .cer (PUBLIC - acesta se distribuie colaboratorilor)..."
Export-Certificate -Cert $cert -FilePath $cerPath | Out-Null

Write-Host ""
Write-Host "==> Gata:"
Write-Host "    $pfxPath  (PRIVAT - foloseste-l DOAR pentru pasii de mai jos, apoi sterge-l local)"
Write-Host "    $cerPath  (PUBLIC - trimite-l colaboratorilor)"
Write-Host ""
Write-Host "==> Urmatorul pas - incarca secretele in GitHub Actions PE ACEST REPO (necesita 'gh' CLI autentificat):"
Write-Host ""
Write-Host '    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes("' -NoNewline
Write-Host "$pfxPath" -NoNewline
Write-Host '"))'
Write-Host '    gh secret set WIN_SELFSIGN_PFX_BASE64 --repo gordasgdc/MediaFlow-Monitor --body $b64'
Write-Host '    gh secret set WIN_SELFSIGN_PFX_PASSWORD --repo gordasgdc/MediaFlow-Monitor'
Write-Host "    (al doilea comand cere parola interactiv - foloseste ACEEASI parola aleasa mai sus)"
Write-Host ""
Write-Host "==> Daca ai deja acest .pfx generat pentru alt repo GDC (CGConvertor etc.),"
Write-Host "    SARI peste generarea de mai sus si ruleaza doar cele 2 comenzi `gh secret set`"
Write-Host "    de mai sus, cu calea catre .pfx-ul deja existent - acelasi certificat,"
Write-Host "    incarcat separat, o data per repo."
Write-Host ""
Write-Host "==> Dupa ce secretele sunt incarcate, sterge fisierul .pfx local (daca l-ai generat aici):"
Write-Host "    Remove-Item `"$pfxPath`" -Force"
Write-Host ""
Write-Host "==> Distribuie $cerPath colaboratorilor (o singura data, valabil pentru TOATE"
Write-Host "    aplicatiile GDC semnate cu acest certificat). Import manual pe masinile lor:"
Write-Host "    dublu-click pe .cer -> Install Certificate -> Local Machine ->"
Write-Host "    'Place all certificates in the following store' -> Trusted Root Certification Authorities."
