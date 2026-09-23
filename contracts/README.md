# Cross-repo contracts

Machine-readable contracts shared by more than one repository. Unlike `docs/`, which explains decisions to people, these files are **consumed by code** — a validator reads them, and a test fails when reality diverges from them.

## Why they live here

[ADR-037 §11](../docs/decisions/ADR-037-canonical-smart-home-device-model.md) settles it: what the backend, the mobile app and the Android plugin share is a **schema, not a runtime library**. PHP and Kotlin do not share a runtime, and extracting a service to hold a data shape would be separation for its own sake. So the contract is a document, checked in, and each language validates against it in its own idiom.

`ixora-infra` is where it belongs because it is already the canonical cross-repo tree; a contract living inside one of its consumers would quietly make that consumer the owner.

## The vendoring rule

**Consuming repos vendor a byte-identical copy**, because deployment pipelines build one repository and cannot reach a sibling. The copy here is canonical; the copies in consumers are replicas.

| Contract | Canonical | Vendored copies |
| --- | --- | --- |
| `smart-home/capability.v1.schema.json` | this repo | `back_vibes/contracts/smart-home/capability.v1.schema.json` |

Planned consumers, not yet vendored: `front_vibes` (TypeScript, CSDM-06) and the Android plugin (Kotlin, CSDM-04).

### Changing a contract

1. Edit the canonical copy here first.
2. Copy it verbatim into every consumer listed above, in the same change set.
3. Bump the version inside the document — semver against the schema itself. Additive (a new capability id, a new operation on an existing capability, a new optional field) is **minor**; changing an existing constraint's required shape is **major** and triggers the dual-read compatibility path of ADR-037 §8.
4. Run the consumer's suite. `back_vibes` has `CapabilityContractCoherenceTest`, which fails when its vendored copy and its PHP value objects disagree, and compares against this canonical copy whenever `ixora-infra` is checked out alongside.

**Drift between repositories is caught manually, not automatically.** No cross-repo CI exists, and inventing one was out of scope for CSDM-01. The coherence test closes the gap that matters most — schema versus code *inside* a repo — and skips the cross-repo comparison rather than pretending it ran. Worth revisiting if a fourth consumer appears.
