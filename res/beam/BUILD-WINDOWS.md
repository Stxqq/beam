# Beam auf einem Windows-PC bauen

Ergebnis: `C:\beam\Output\beam-1.5.1-x64-portable.exe` – die portable Beam-App
für den USB-Stick.

## Was du brauchst

- Windows 10 oder 11, 64 Bit
- **30 GB freien Platz** auf `C:`
- Admin-Rechte (Windows fragt ein paar Mal nach)
- Internet
- Zeit: beim ersten Mal **ca. 1,5–2,5 Stunden** (meist läuft es alleine durch).
  Spätere Builds gehen deutlich schneller.

## 1. Git installieren

PowerShell öffnen (Startmenü → „PowerShell") und eingeben:

```powershell
winget install -e --id Git.Git
```

Danach **PowerShell schließen und neu öffnen**, damit `git` gefunden wird.

## 2. Beam-Code holen

```powershell
git config --global core.longpaths true
git clone -b beam/windows-build --recursive https://github.com/Stxqq/beam.git C:\beam
```

Der Ordner muss kurz bleiben (`C:\beam`), sonst stößt Windows an Pfadlängen-Grenzen.

## 3. Bauen

```powershell
cd C:\beam
powershell -ExecutionPolicy Bypass -File res\beam\build-windows.ps1
```

Das Skript installiert alles Nötige selbst (Python, Visual Studio Build Tools,
LLVM, Rust, Flutter, vcpkg) und baut dann Beam. Werkzeuge landen in
`C:\beam-tools`.

Wenn Windows fragt „Möchten Sie zulassen, dass diese App Änderungen vornimmt?"
→ **Ja**.

Am Ende steht grün:

```
Done: C:\beam\Output\beam-1.5.1-x64-portable.exe (25 MB)
```

## 4. Auf den Stick

`C:\beam\Output\beam-1.5.1-x64-portable.exe` auf den USB-Stick kopieren. Fertig.

## Wenn etwas schiefgeht

- Das Skript einfach **nochmal starten** – fertige Schritte werden übersprungen.
- „Python … not found yet": PowerShell schließen, neu öffnen, Schritt 3 wiederholen.
- Bricht es mit rotem Text ab: die **letzten ~30 Zeilen** (oder ein Screenshot)
  an Claude schicken.

## Später neu bauen (nach Code-Änderungen)

```powershell
cd C:\beam
git pull
powershell -ExecutionPolicy Bypass -File res\beam\build-windows.ps1
```
