# Genereaza Instructiuni_Utilizare.pdf, RO/EN/ES, cu reportlab.
# Foloseste Arial (nu Helvetica standard-14) pentru diacriticele romanesti.
# Ruleaza cu: python3 installer/generate_pdf.py
import os
from reportlab.lib.pagesizes import A4
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import SimpleDocTemplate, Paragraph, ListFlowable, ListItem, PageBreak

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Instructiuni_Utilizare.pdf")

pdfmetrics.registerFont(TTFont("Arial", "/System/Library/Fonts/Supplemental/Arial.ttf"))
pdfmetrics.registerFont(TTFont("Arial-Bold", "/System/Library/Fonts/Supplemental/Arial Bold.ttf"))
styles = getSampleStyleSheet()
ACCENT = colors.HexColor("#C97D2E")
MUTED = colors.HexColor("#6a6a6a")
NOTE_BG = colors.HexColor("#FBF1E6")

title_style = ParagraphStyle("Title", parent=styles["Title"], fontName="Arial-Bold", fontSize=19, spaceAfter=2, textColor=colors.HexColor("#1a1a1a"))
subtitle_style = ParagraphStyle("Subtitle", parent=styles["Normal"], fontName="Arial", fontSize=11, textColor=MUTED, spaceAfter=20)
h2_style = ParagraphStyle("H2", parent=styles["Heading2"], fontName="Arial-Bold", fontSize=13, textColor=ACCENT, spaceBefore=16, spaceAfter=6)
body_style = ParagraphStyle("Body", parent=styles["Normal"], fontName="Arial", fontSize=10.5, leading=15, textColor=colors.HexColor("#1a1a1a"), spaceAfter=6)
step_style = ParagraphStyle("Step", parent=body_style, leftIndent=4, spaceAfter=5)
note_style = ParagraphStyle("Note", parent=body_style, backColor=NOTE_BG, leftIndent=10, fontSize=10)
footer_style = ParagraphStyle("Footer", parent=styles["Normal"], fontName="Arial", fontSize=8.5, textColor=colors.HexColor("#8a8a8a"), spaceBefore=20)


def numbered(items):
    return ListFlowable(
        [ListItem(Paragraph(it, step_style), leftIndent=16) for it in items],
        bulletType="1", start="1", leftIndent=16, spaceBefore=2, spaceAfter=8,
    )


def note(text):
    return Paragraph(text, note_style)


def page(d):
    flow = [Paragraph("MediaFlow Monitor", title_style), Paragraph(d["subtitle"], subtitle_style)]
    for h, body in d["sections"]:
        flow.append(Paragraph(h, h2_style))
        if isinstance(body, list):
            flow.append(numbered(body))
        elif isinstance(body, tuple):
            flow.append(note(body[0]))
        else:
            flow.append(Paragraph(body, body_style))
    flow.append(Paragraph("MediaFlow Monitor — github.com/gordasgdc/MediaFlow-Monitor", footer_style))
    return flow


RO = dict(
    subtitle="Instrucțiuni de instalare și utilizare — Română",
    sections=[
        ("1. Instalare", [
            "Descarcă arhiva de pe <b>gordas.dev/media-flow-monitor</b> și dezarhiveaz-o.",
            "Mută <b>MediaFlowMonitor.app</b> în folderul Applications.",
            "La prima deschidere, aplicația poate fi nesemnată/nenotarizată (fază de test): click-dreapta pe aplicație → <b>Deschide</b> (nu dublu-click), apoi confirmă în fereastra de avertisment. E necesar o singură dată.",
        ]),
        ("2. Cum funcționează", [
            "Aplicația rulează discret în fundal, cu o iconiță permanentă în bara de meniu (sus, lângă ceas/wifi).",
            "Apasă <b>Cmd+Shift+M</b> oricând, sau click pe iconiță → „Arată/Ascunde panoul”, pentru a deschide fereastra de monitorizare.",
            "Panoul arată RAM, Swap, VRAM (dacă e disponibil), spațiul liber pe discul de cache, și alertele recente din log-urile DaVinci Resolve (crash-uri de plugin, GPU Memory Full, cadre pierdute, etc.).",
            "Cardul de acțiune (ex. „Golește Cache”) apare doar când e relevant și deschide folderul de cache în Finder — nu șterge nimic automat, tu alegi ce ștergi.",
        ]),
        ("3. Licență & Donație", [
            "Probă gratuită: <b>15 zile</b>, acces complet, fără restricții.",
            "După cele 15 zile, aplicația continuă să funcționeze, dar te încurajăm să susții dezvoltarea printr-o <b>donație simbolică de 7€</b> (ofertă de lansare, acces pe viață) — nu este o vânzare, este o susținere a proiectului.",
            "Activare: click pe iconița din bara de meniu → „Activează licența (WhatsApp)…” — se deschide WhatsApp cu Machine ID-ul tău pre-completat. După donație, primești un cod de activare pe care îl introduci în aplicație.",
        ]),
        ("4. Actualizări", [
            "La lansare, aplicația verifică automat dacă există o versiune nouă.",
            "Dacă apare o fereastră de „Versiune nouă disponibilă”, apasă <b>Actualizează acum</b> — se deschide pagina de descărcare a pachetului nou. Instalarea rămâne un pas manual: descarci, înlocuiești aplicația veche, redeschizi.",
            "Poți verifica oricând manual din meniu: „Caută actualizări…”.",
        ]),
    ],
)

EN = dict(
    subtitle="Installation & usage instructions — English",
    sections=[
        ("1. Installation", [
            "Download the archive from <b>gordas.dev/media-flow-monitor</b> and unzip it.",
            "Move <b>MediaFlowMonitor.app</b> to your Applications folder.",
            "On first launch, the app may be unsigned/unnotarized (test phase): right-click the app → <b>Open</b> (not double-click), then confirm in the warning dialog. Needed only once.",
        ]),
        ("2. How it works", [
            "The app runs quietly in the background, with a permanent menu bar icon (top of screen, near the clock/wifi).",
            "Press <b>Cmd+Shift+M</b> anytime, or click the icon → “Show/Hide panel”, to open the monitoring window.",
            "The panel shows RAM, Swap, VRAM (if available), free space on the cache disk, and recent alerts from DaVinci Resolve logs (plugin crashes, GPU Memory Full, dropped frames, etc.).",
            "The action card (e.g. “Purge Cache”) only appears when relevant and opens the cache folder in Finder — it never deletes anything automatically, you choose what to remove.",
        ]),
        ("3. License & Donation", [
            "Free trial: <b>15 days</b>, full access, no restrictions.",
            "After 15 days, the app keeps working, but we encourage supporting development with a <b>symbolic 7€ donation</b> (launch offer, lifetime access) — this is support, not a sale.",
            "Activation: click the menu bar icon → “Activate license (WhatsApp)…” — opens WhatsApp with your Machine ID pre-filled. After donating, you receive an activation code to enter in the app.",
        ]),
        ("4. Updates", [
            "On launch, the app automatically checks for a new version.",
            "If a “New version available” window appears, click <b>Update now</b> — opens the download page for the new package. Installation stays a manual step: download, replace the old app, reopen.",
            "You can also check manually anytime from the menu: “Check for updates…”.",
        ]),
    ],
)

ES = dict(
    subtitle="Instrucciones de instalación y uso — Español",
    sections=[
        ("1. Instalación", [
            "Descarga el archivo desde <b>gordas.dev/media-flow-monitor</b> y descomprímelo.",
            "Mueve <b>MediaFlowMonitor.app</b> a la carpeta Aplicaciones.",
            "En el primer inicio, la app puede no estar firmada/notarizada (fase de prueba): clic derecho en la app → <b>Abrir</b> (no doble clic), luego confirma en el aviso. Solo es necesario una vez.",
        ]),
        ("2. Cómo funciona", [
            "La app se ejecuta discretamente en segundo plano, con un icono permanente en la barra de menú (arriba, junto al reloj/wifi).",
            "Pulsa <b>Cmd+Shift+M</b> en cualquier momento, o haz clic en el icono → “Mostrar/Ocultar panel”, para abrir la ventana de monitorización.",
            "El panel muestra RAM, Swap, VRAM (si está disponible), espacio libre en el disco de caché, y alertas recientes de los logs de DaVinci Resolve (fallos de plugin, GPU Memory Full, fotogramas perdidos, etc.).",
            "La tarjeta de acción (ej. “Purgar Caché”) solo aparece cuando es relevante y abre la carpeta de caché en Finder — nunca borra nada automáticamente, tú eliges qué eliminar.",
        ]),
        ("3. Licencia y Donación", [
            "Prueba gratuita: <b>15 días</b>, acceso completo, sin restricciones.",
            "Después de los 15 días, la app sigue funcionando, pero te animamos a apoyar el desarrollo con una <b>donación simbólica de 7€</b> (oferta de lanzamiento, acceso de por vida) — es un apoyo, no una venta.",
            "Activación: clic en el icono de la barra de menú → “Activar licencia (WhatsApp)…” — abre WhatsApp con tu Machine ID prellenado. Tras la donación, recibirás un código de activación para introducir en la app.",
        ]),
        ("4. Actualizaciones", [
            "Al iniciar, la app comprueba automáticamente si hay una versión nueva.",
            "Si aparece una ventana de “Nueva versión disponible”, pulsa <b>Actualizar ahora</b> — se abre la página de descarga del nuevo paquete. La instalación sigue siendo un paso manual: descargar, reemplazar la app antigua, reabrir.",
            "También puedes comprobarlo manualmente desde el menú: “Buscar actualizaciones…”.",
        ]),
    ],
)

doc = SimpleDocTemplate(OUT, pagesize=A4, topMargin=50, bottomMargin=40, leftMargin=50, rightMargin=50)
flow = page(RO) + [PageBreak()] + page(EN) + [PageBreak()] + page(ES)
doc.build(flow)
print("PDF generat:", OUT)
