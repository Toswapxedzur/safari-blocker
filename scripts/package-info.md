# Safari build scripts

- `build-app.sh`: compiles and signs the standalone containing app and Safari Web Extension with Apple's macOS SDK. Production and development remain separate; all build verification runs on mini1.

- `embed-profiles.py`: validates matching, current Apple provisioning profiles and their Vault App Group authorization, then embeds them without logging private profile contents.
