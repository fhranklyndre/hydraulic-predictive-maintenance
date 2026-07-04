from pathlib import Path


def test_app_file_exists():
    assert Path("app.py").exists(), "app.py should exist for the Streamlit app."


def test_requirements_file_exists():
    assert Path("requirements.txt").exists(), "requirements.txt should exist."


def test_app_contains_streamlit_setup():
    app_content = Path("app.py").read_text(encoding="utf-8")

    assert "import streamlit as st" in app_content
    assert "st.set_page_config" in app_content
    assert "Hydraulic Predictive Maintenance" in app_content


def test_app_avoids_deprecated_width_stretch():
    app_content = Path("app.py").read_text(encoding="utf-8")

    assert 'width="stretch"' not in app_content