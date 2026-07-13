# AxiomRefiner

**Countermodel-guided iterative axiom refinement for modal/HOL experiments**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `axiom_refiner` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:axiom_refiner, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/axiom_refiner>.



## Chisholm Demo

First, execute in project ROOT 
```./cmd/setup_isabelle.sh```

Second, compile the project by ```mix compile```

Third, run the single_model.exs, enumeration.exs