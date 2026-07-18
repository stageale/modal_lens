# Modellaufzählung über die Command Line

Dieses Dokument beschreibt die Auswahl des Analysemodus für die iterative Nitpick-Modellaufzählung.

Der Kommandozeilenaufruf verwendet immer genau eine Isabelle-Basistheorie und genau einen Modus. Die Basistheorie bleibt unverändert. Für jeden Nitpick-Lauf erzeugt `axiom_refiner` eine modusspezifische Search-Theory, welche die Basistheorie importiert und die bisher erzeugten Blocking-Axiome enthält.

## CLI vorbereiten

Das Escript wird im Projektverzeichnis gebaut:

```bash
mix escript.build
```

Danach steht das lokale Kommando zur Verfügung:

```bash
./axiom_refiner
```

## Grundform des Aufrufs

```bash
./axiom_refiner enumerate INPUT.thy \
  --mode MODE \
  --model-logic LOGIC \
  [weitere Optionen]
```

Zulässige CLI-Werte für `--mode` sind:

```text
countermodels
satisfying-models
consistency-check
```

Intern werden diese Werte als Elixir-Atome weitergereicht:

```text
countermodels      -> :countermodels
satisfying-models  -> :satisfying_models
consistency-check  -> :consistency_check
```

## Modus `countermodels`

Dieser Modus enumeriert Gegenmodelle zu einer in der Basistheorie benannten Aussage.

Aufruf:

```bash
./axiom_refiner enumerate examples/input/Chisholm.thy \
  --mode countermodels \
  --model-logic sdl \
  --relation R \
  --atoms go,tell \
  --max-models 5 \
  --out-dir out/chisholm_countermodels
```

Die Basistheorie muss die zu untersuchende Aussage unter dem vereinbarten Namen `axiom_refiner_query` bereitstellen:

```isabelle
abbreviation axiom_refiner_query :: bool where
  "axiom_refiner_query \<equiv> holds_at_actual (O tell)"
```

Die generierte Search-Theory verwendet anschließend einen normalen Nitpick-Aufruf:

```isabelle
lemma axiom_refiner_probe:
  "axiom_refiner_query"
  nitpick [user_axioms, card i = 2, show_consts, dont_specialize]
  oops
```

Nitpick sucht damit ein Modell, das die Axiome der Basistheorie erfüllt und `axiom_refiner_query` widerlegt.

## Modus `satisfying-models`

Dieser Modus enumeriert endliche Modelle, welche die Basistheorie erfüllen.

Aufruf:

```bash
./axiom_refiner enumerate examples/input/Chisholm.thy \
  --mode satisfying-models \
  --model-logic sdl \
  --relation R \
  --atoms go,tell \
  --max-models 10 \
  --out-dir out/chisholm_models
```

Für diesen Modus ist keine `axiom_refiner_query` erforderlich. Die Search-Theory verwendet eine triviale Probe zusammen mit Nitpicks `satisfy`-Option:

```isabelle
lemma axiom_refiner_probe:
  "True"
  nitpick [satisfy, user_axioms, card i = 2, show_consts, dont_specialize]
  oops
```

Nach jedem gefundenen Modell wird ein Blocking-Axiom erzeugt. Anschließend wird eine neue Search-Theory geschrieben und das nächste unterschiedliche Modell gesucht.

## Modus `consistency-check`

Dieser Modus sucht höchstens ein endliches Modell der Basistheorie.

Aufruf:

```bash
./axiom_refiner enumerate examples/input/Chisholm.thy \
  --mode consistency-check \
  --model-logic sdl \
  --relation R \
  --atoms go,tell \
  --out-dir out/chisholm_consistency
```

Die Nitpick-Probe entspricht dem Satisfy-Modus:

```isabelle
lemma axiom_refiner_probe:
  "True"
  nitpick [satisfy, user_axioms, card i = 2, show_consts, dont_specialize]
  oops
```

Der Enumerator beendet den Lauf nach dem ersten gefundenen Modell. Wird im untersuchten Scope kein Modell gefunden, ist das zunächst nur ein Hinweis auf mögliche Inkonsistenz. Es ist kein allgemeiner Isabelle-Beweis der Widersprüchlichkeit.

## Auswahl der Modelllogik

Die Option `--model-logic` bestimmt, welcher interne Modelltyp für die Nitpick-Ausgabe erzeugt wird.

```text
sdl -> :sdl
DDL -> :ddl
```

Beispiele:

```bash
--model-logic sdl
```

```bash
--model-logic ddl
```

Die Option beeinflusst das Parsen, die ausgezeichnete Welt und die semantische Interpretation der Relation. Sie wählt nicht den Nitpick-Modus. Dafür ist ausschließlich `--mode` zuständig.

## Wichtige Optionen

```text
--mode MODE                 Analysemodus
--model-logic LOGIC         sdl oder ddl
--relation NAME             Name der Nitpick-Relation, standardmäßig R
--atoms a,b,c               Relevante atomare Prädikate
--auto-atoms                 Atome automatisch erkennen
--max-models N              Maximale Anzahl enumerierter Modelle
--out-dir DIR               Ausgabeverzeichnis
--search-theory-dir DIR     Verzeichnis der generierten Search-Theories
--isabelle-bin PATH         Pfad zum Isabelle-Executable
--threads N                 Anzahl der Isabelle-Threads
--include-atoms             Atombewertungen im Blocking-Axiom berücksichtigen
--include-designated-world  Ausgezeichnete Welt im Blocking-Axiom berücksichtigen
```

Bei `consistency-check` wird intern höchstens ein Modell gesucht. Ein zusätzliches `--max-models` ist für diesen Modus daher nicht erforderlich.

## Datenfluss des Modus

Der ausgewählte Modus wird einmal an der CLI in ein Elixir-Atom übersetzt und anschließend über dieselbe Optionsliste weitergereicht:

```text
CLI: --mode satisfying-models
        ↓
Src.Interface.CLI
        mode: :satisfying_models
        ↓
Src.ModelEnumeration.enumerate/2
        ↓
write_search_theory/3
        wählt SatisfyingModels.thy
        ↓
do_enumerate/8
        ↓
run_iteration/2
        ↓
parse_nitpick_result/2
        erkennt das modusspezifische Ende der Suche
        ↓
Src.Core.Parser.parse_nitpick_text/2
        parst ein tatsächlich gefundenes Modell
```

`Src.Core.Parser.parse_nitpick_text/2` benötigt den Modus nicht zur Erkennung eines positiven Ergebnisses. Die Nitpick-Ausgabe enthält bereits, ob ein `model` oder ein `counterexample` gefunden wurde. Der Modus wird in `parse_nitpick_result/2` benötigt, um zwischen „kein Gegenmodell“ und „kein erfüllendes Modell“ zu unterscheiden.

## Typische Chisholm-Aufrufe

Gegenmodelle zur benannten Chisholm-Query:

```bash
./axiom_refiner enumerate examples/input/Chisholm.thy \
  --mode countermodels \
  --model-logic sdl \
  --atoms go,tell \
  --max-models 5
```

Mehrere erfüllende Chisholm-Modelle:

```bash
./axiom_refiner enumerate examples/input/Chisholm.thy \
  --mode satisfying-models \
  --model-logic sdl \
  --atoms go,tell \
  --max-models 10
```

Endlicher Konsistenzzeuge für Chisholm:

```bash
./axiom_refiner enumerate examples/input/Chisholm.thy \
  --mode consistency-check \
  --model-logic sdl \
  --atoms go,tell
```

## Häufige Fehler

### `--mode` fehlt

Die Enumeration benötigt einen expliziten Modus. Dadurch wird verhindert, dass versehentlich Gegenmodelle statt erfüllender Modelle gesucht werden.

### `countermodels` ohne `axiom_refiner_query`

Der Countermodel-Wrapper referenziert `axiom_refiner_query`. Die Basistheorie muss diesen Namen daher bereitstellen.

### `satisfying-models` verwendet eine inhaltliche Query

Der Satisfy-Wrapper muss als Ziel `True` verwenden. Andernfalls werden nur Modelle enumeriert, in denen zusätzlich die Query wahr ist.

### Kein Modell im Scope

Ein Nitpick-Lauf untersucht nur den konfigurierten endlichen Scope. „Kein Modell gefunden“ ist deshalb nicht automatisch ein allgemeiner Inkonsistenzbeweis.
