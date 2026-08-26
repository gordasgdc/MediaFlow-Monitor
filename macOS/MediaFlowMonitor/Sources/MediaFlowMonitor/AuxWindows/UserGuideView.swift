import SwiftUI

/// Ghid de utilizare intern (RO/EN/ES — Regula 8 din CLAUDE.md, consistent
/// cu restul localizării ecosistemului GDC), afișat ca fereastră nativă
/// separată din meniul Help sau din meniul status item-ului.
struct UserGuideView: View {
    @State private var language: GuideLanguage = .ro

    enum GuideLanguage: String, CaseIterable, Identifiable {
        case ro = "RO", en = "EN", es = "ES"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $language) {
                ForEach(GuideLanguage.allCases) { lang in
                    Text(lang.rawValue).tag(lang)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(16)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(content(for: language)) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title).font(.headline)
                            Text(section.body).font(.system(size: 12.5)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 620, height: 560)
    }

    private struct Section: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }

    private func content(for lang: GuideLanguage) -> [Section] {
        switch lang {
        case .ro:
            return [
                Section(title: "1. Configurare CacheClip (discuri externe Thunderbolt)", body: """
Aplicația încearcă întâi auto-detectarea: verifică locația implicită DaVinci Resolve, apoi scanează volumele montate (/Volumes) după un folder numit „CacheClip”. Această detectare e euristică — DaVinci Resolve nu expune public calea reală de „Cache Files Location” a proiectului activ.

De aceea, pentru workflow-uri profesionale (cache pe disc extern Thunderbolt/RAID/DAS), folosește selecția manuală: în secțiunea „CacheClip disk” din Dashboard, apasă „Schimbă folderul…” și alege exact folderul/discul folosit de proiectul curent. Alegerea rămâne salvată până o schimbi din nou.
"""),
                Section(title: "2. Alertele din Real-time Log Decoder", body: """
• GPU Memory Full — placa video a rămas fără memorie video disponibilă; aplicația sugerează „Bypass FX” (dezactivează temporar efectele grele din Fusion/Color).
• Render Cache invalid — DaVinci a regenerat automat cache-ul de randare (de obicei după o schimbare de proiect/setări); nu necesită acțiune, dar poate indica nevoia unui „Purge Cache”.
• Timeline dropped frame — cadre pierdute la playback, de obicei semn de disc de cache prea lent sau supraîncărcat.
• Fusion composition slow rendering — un nod Fusion durează prea mult per cadru; verifică nodurile grele (Optical Flow, Delta Keyer pe rezoluții mari).
• Codec fallback to software — decodare software (mai lentă) în loc de accelerare hardware; posibil codec neacceptat de GPU.
• Database connection lost — conexiunea la baza de date a proiectelor DaVinci s-a întrerupt; verifică rețeaua dacă lucrezi pe un proiect colaborativ.
• Plugin crashed — un plugin OFX a crăpat; verifică Fusion Console din DaVinci pentru detalii.
"""),
                Section(title: "3. Acțiuni rapide", body: """
• Purge Cache — șterge tot conținutul folderului CacheClip activ (auto-detectat sau ales manual). Acțiune distructivă — cere confirmare explicită înainte de execuție. Progresul apare live într-o consolă stil Terminal.
• Force Sync Log — forțează o recitire imediată a log-ului DaVinci Resolve, fără să aștepte următorul eveniment de sistem.
• Optimise System — recalculează spațiul de disc și resincronizează log-ul; NU e un „buton magic” — nu șterge nimic și nu modifică setări de sistem, doar reîmprospătează datele afișate.
"""),
            ]
        case .en:
            return [
                Section(title: "1. Configuring CacheClip (external Thunderbolt disks)", body: """
The app first tries auto-detection: it checks the default DaVinci Resolve location, then scans mounted volumes (/Volumes) for a folder named "CacheClip". This detection is heuristic — DaVinci Resolve does not publicly expose the real "Cache Files Location" of the active project.

For professional workflows (cache on an external Thunderbolt/RAID/DAS drive), use manual selection instead: in the "CacheClip disk" section of the Dashboard, click "Change folder…" and pick the exact folder/disk used by your current project. The choice is saved until you change it again.
"""),
                Section(title: "2. Real-time Log Decoder alerts", body: """
• GPU Memory Full — the GPU ran out of available video memory; the app suggests "Bypass FX" (temporarily disables heavy Fusion/Color effects).
• Render Cache invalid — DaVinci automatically regenerated the render cache (usually after a project/settings change); no action required, but may indicate a "Purge Cache" is due.
• Timeline dropped frame — frames lost during playback, usually a sign the cache disk is too slow or overloaded.
• Fusion composition slow rendering — a Fusion node is taking too long per frame; check heavy nodes (Optical Flow, Delta Keyer at high resolutions).
• Codec fallback to software — software decoding (slower) instead of hardware acceleration; the codec may not be GPU-accelerated.
• Database connection lost — the connection to the DaVinci project database was interrupted; check the network if working on a collaborative project.
• Plugin crashed — an OFX plugin crashed; check DaVinci's Fusion Console for details.
"""),
                Section(title: "3. Quick actions", body: """
• Purge Cache — deletes all contents of the active CacheClip folder (auto-detected or manually chosen). Destructive action — requires explicit confirmation before running. Progress is shown live in a Terminal-style console.
• Force Sync Log — forces an immediate re-read of the DaVinci Resolve log, without waiting for the next system event.
• Optimise System — recalculates disk space and resyncs the log; it is NOT a "magic button" — it deletes nothing and changes no system settings, it just refreshes the displayed data.
"""),
            ]
        case .es:
            return [
                Section(title: "1. Configuración de CacheClip (discos externos Thunderbolt)", body: """
La aplicación primero intenta la detección automática: revisa la ubicación predeterminada de DaVinci Resolve y luego escanea los volúmenes montados (/Volumes) en busca de una carpeta llamada "CacheClip". Esta detección es heurística — DaVinci Resolve no expone públicamente la ruta real de "Cache Files Location" del proyecto activo.

Para flujos de trabajo profesionales (caché en un disco externo Thunderbolt/RAID/DAS), usa la selección manual: en la sección "CacheClip disk" del Dashboard, pulsa "Cambiar carpeta…" y elige exactamente la carpeta/disco usado por tu proyecto actual. La elección queda guardada hasta que la cambies de nuevo.
"""),
                Section(title: "2. Alertas del Real-time Log Decoder", body: """
• GPU Memory Full — la GPU se quedó sin memoria de vídeo disponible; la app sugiere "Bypass FX" (desactiva temporalmente los efectos pesados de Fusion/Color).
• Render Cache invalid — DaVinci regeneró automáticamente la caché de render (normalmente tras un cambio de proyecto/ajustes); no requiere acción, pero puede indicar que conviene un "Purge Cache".
• Timeline dropped frame — fotogramas perdidos durante la reproducción, normalmente indica que el disco de caché es demasiado lento o está saturado.
• Fusion composition slow rendering — un nodo de Fusion tarda demasiado por fotograma; revisa nodos pesados (Optical Flow, Delta Keyer en resoluciones altas).
• Codec fallback to software — decodificación por software (más lenta) en vez de aceleración por hardware; puede que el códec no esté acelerado por GPU.
• Database connection lost — se interrumpió la conexión a la base de datos de proyectos de DaVinci; revisa la red si trabajas en un proyecto colaborativo.
• Plugin crashed — un plugin OFX falló; revisa la Fusion Console de DaVinci para más detalles.
"""),
                Section(title: "3. Acciones rápidas", body: """
• Purge Cache — elimina todo el contenido de la carpeta CacheClip activa (autodetectada o elegida manualmente). Acción destructiva — requiere confirmación explícita antes de ejecutarse. El progreso se muestra en vivo en una consola estilo Terminal.
• Force Sync Log — fuerza una relectura inmediata del log de DaVinci Resolve, sin esperar al siguiente evento del sistema.
• Optimise System — recalcula el espacio en disco y resincroniza el log; NO es un "botón mágico" — no borra nada ni cambia ajustes del sistema, solo actualiza los datos mostrados.
"""),
            ]
        }
    }
}
