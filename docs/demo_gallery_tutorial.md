# Demo Gallery: Axiom Explanations ausführen

Diese Demo erzeugt eine kleine visuelle Galerie für Gegenmodelle. Für jedes ausgewählte Beispiel und jedes unterstützte Frame-Axiom werden die relevanten Kanten im Modell hervorgehoben.

Die Visualisierung folgt dieser Konvention:

- **rote Kanten**: vorhandene Kanten, die für eine Violation verantwortlich sind
- **rote gestrichelte Kanten**: fehlende Kanten, die durch das Axiom gefordert wären
- **rote Knotenränder**: Welten, die an der Violation beteiligt sind

## Voraussetzungen

Die Demo wird aus dem Elixir-Projekt heraus gestartet.

Zusätzlich sollte GraphViz installiert sein, wenn direkt SVG- oder PNG-Dateien erzeugt werden sollen:

```bash
sudo pacman -S graphviz
```

Zum Testen:

```bash
dot -V
```

Falls GraphViz nicht verfügbar ist, kann die Demo auch nur DOT-Dateien erzeugen.

## Demo starten

Starte zunächst eine interaktive Mix-Sitzung im Projektordner:

```bash
iex -S mix
```

Dann kann die Demo ausgeführt werden.

## Chisholm-Demo

Die Chisholm-Demo ist der empfohlene Einstiegspunkt:

```elixir
Src.VisualExplanations.DemoGallery.run(:chisholm)
```

Mit automatischem Öffnen der HTML-Übersicht:

```elixir
Src.VisualExplanations.DemoGallery.run(:chisholm, open?: true)
```

Optional kann die Anzahl der verwendeten Modelle begrenzt werden:

```elixir
Src.VisualExplanations.DemoGallery.run(:chisholm, limit: 4, open?: true)
```

## Ausgabeformat wählen

Standardmäßig rendert die Demo SVG-Dateien. Das ist für die HTML-Galerie meist am angenehmsten:

```elixir
Src.VisualExplanations.DemoGallery.run(:chisholm,
  render_fmt: "svg",
  open?: true
)
```

Alternativ können PNG-Dateien erzeugt werden:

```elixir
Src.VisualExplanations.DemoGallery.run(:chisholm,
  render_fmt: "png",
  open?: true
)
```

Nur DOT-Dateien ohne GraphViz-Rendering:

```elixir
Src.VisualExplanations.DemoGallery.run(:chisholm,
  render?: false
)
```

## Erzeugte Dateien

Die Demo schreibt ihre Ausgabe standardmäßig nach:

```text
demo_output/axiom_gallery/
```

Dort liegen insbesondere:

```text
demo_output/axiom_gallery/index.html
```

sowie die gerenderten Modellvisualisierungen unter:

```text
demo_output/axiom_gallery/assets/
```

Die `index.html` enthält eine kleine Galerieansicht, in der die erzeugten Visualisierungen betrachtet werden können.

## Was demonstriert wird

Die Demo zeigt für jedes Gegenmodell, welche strukturellen Violations zu einem bestimmten Axiom gehören. Dadurch wird sichtbar, warum ein Axiom als Kandidat für eine Theorieanreicherung plausibel sein kann.

Beispielhaft:

- Bei **Reflexivität** werden fehlende Selbstschleifen als gestrichelte rote Kanten eingezeichnet.
- Bei **Symmetrie** werden fehlende Rückkanten rot gestrichelt ergänzt, während die vorhandene Gegenkante rot markiert wird.
- Bei **Transitivität** werden Pfade der Form `u -> v -> w` rot markiert und die fehlende Abkürzung `u -> w` rot gestrichelt dargestellt.
- Bei **Euklidizität** werden zwei ausgehende Kanten `u -> v` und `u -> w` markiert und die fehlende Kante `v -> w` eingezeichnet.

## Typischer Demo-Befehl

Für eine kompakte Präsentation reicht meist:

```elixir
Src.VisualExplanations.DemoGallery.run(:chisholm,
  limit: 4,
  render_fmt: "svg",
  open?: true
)
```

## Fehlerbehebung

Wenn GraphViz fehlt, erscheint typischerweise eine Fehlermeldung zu `dot`.

Dann entweder GraphViz installieren:

```bash
sudo pacman -S graphviz
```

oder das Rendering deaktivieren:

```elixir
Src.VisualExplanations.DemoGallery.run(:chisholm,
  render?: false
)
```

Wenn die HTML-Datei nicht automatisch geöffnet wird, kann sie manuell im Browser geöffnet werden:

```bash
xdg-open demo_output/axiom_gallery/index.html
```
