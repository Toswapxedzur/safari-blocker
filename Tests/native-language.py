#!/usr/bin/env python3
"""Exercise the shipping native text loader without opening an app or browser."""
import json
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
catalogs = root.parent / "customBlocker" / "translation"
locales = ["en", "ar", "bn", "de", "es", "fr", "hi", "id", "it", "ja", "ko", "nl", "pa", "pl", "pt", "ru", "th", "tr", "vi", "zh"]
with tempfile.TemporaryDirectory(prefix="safari-language-") as temporary:
    app = Path(temporary) / "SafariLanguageProbe.app"
    executable = app / "Contents/MacOS/SafariLanguageProbe"
    resources = app / "Contents/Resources"
    executable.parent.mkdir(parents=True)
    resources.mkdir(parents=True)
    shutil.copytree(catalogs, resources / "translation")
    with (app / "Contents/Info.plist").open("wb") as file:
        plistlib.dump({"CFBundleIdentifier": "com.adamancia.vault.safari.language-tests",
                      "CFBundleExecutable": executable.name, "CFBundlePackageType": "APPL"}, file)
    subprocess.run(["xcrun", "swiftc", str(root / "Sources/SafariNativeLanguage.swift"),
                    str(root / "Tests/native-language.swift"), "-o", str(executable)], check=True)
    for locale in locales + ["zz"]:
        result = subprocess.run([str(executable), "-AppleLanguages", f"({locale})"],
                                check=True, capture_output=True, text=True)
        actual = json.loads(result.stdout)
        selected = locale if locale in locales else "en"
        expected = json.loads((catalogs / f"{selected}.json").read_text())
        assert actual.pop("language") == selected, (locale, "native language selection")
        assert actual.pop("unknown") == "Literal diagnostic <x>", (locale, "unknown diagnostic altered")
        for key, value in actual.items():
            assert value == expected[key], (locale, key, "native text differs from bundled catalog")
        print(f"PASS Safari native {locale}: selected catalog, six messages and literal fallback")
