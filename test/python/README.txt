Copy the files into the corresponding test/python directory of Axiom Refiner.

Run all verbalization tests:

uv run pytest test/python/test_verbalization_*.py -q

The tests mock Ollama and Hugging Face inference. They do not require a running
Ollama server or model downloads. The Transformers test module requires the
transformers package to be installed; otherwise pytest skips that module.
