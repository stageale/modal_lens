from graph_ml.healthcheck import environment_info

def test_environment_is_available() -> None:
    info = environment_info()
    
    assert info["status"] == "ok"
    assert info["python_version"].startswith("3.12.")
    assert info["implementation"] == "CPython"