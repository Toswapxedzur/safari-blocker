# Safari build scripts

- `build-app.sh`: compiles and signs the standalone containing app, embedded Sparkle 2 framework and Safari Web Extension with Apple's macOS SDK. Production and development remain separate; all build verification runs on Mini2. A temporary signing keychain can be passed with `SAFARI_VAULT_SIGNING_KEYCHAIN`.

- `embed-profiles.py`: validates matching, current Apple provisioning profiles and their Vault App Group authorization, embeds them without logging private profile contents, and verifies final signatures/certificate authorization.
