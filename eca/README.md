# ECA Configuration

## Security Architecture

- **Encrypted Storage:** All credentials live securely in `~/.authinfo.gpg` (GPG encrypted).
- **Zero-Footprint Decryption:** No plaintext passwords are ever written to disk. The `eca-secure` wrapper seamlessly creates a randomized, RAM-backed temporary file (`mktemp`), passes it to the `eca` binary via the `ECA_CONFIG` environment variable, and instantly overwrites it using a `trap shred -u` if the process exits, crashes, or is forcefully killed.

## Key Management

```bash
# List providers (keys hidden)
./list-keys

# List providers with full keys
./list-keys --show-secrets

# Add/update/remove keys (opens editor)
./update-keys [editor]
```

## Usage

### CLI
```bash
# Just use standard commands; ~/bin/eca transparently routes through the secure wrapper
eca server
eca chat
```

### Emacs
```bash
# Emacs' eca-mode natively detects `~/bin/eca` in your $PATH.
# Emacs starts the ECA server securely in the background.
# Just run:
M-x eca-chat
```

## Troubleshooting

**ECA fails to start or decrypt:**
```bash
# Check if gpg-agent is running and you have keys configured
./list-keys
```

**Adding missing keys:**
```bash
./update-keys [editor]
```

## Scripts Overview

| Script | Purpose |
|--------|---------|
| `eca-secure` | Core wrapper that safely decrypts and ferries credentials to the `eca` binary |
| `list-keys` | View configured API keys |
| `update-keys` | Manually edit keys in a secure temporary buffer |
