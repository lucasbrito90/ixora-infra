# Cloud-init Review — Observability Host — Phase 8.8.6

**Status:** Review complete — cloud-init **retained** (not replaced)  
**Template:** `opentofu/staging/templates/observability-cloud-init.yaml.tftpl`  
**Phase:** 8.8.5 bootstrap; 8.8.6 documents limitations

---

## 1. Current cloud-init responsibilities

| Task | Implemented | Idempotent on re-run |
| --- | --- | --- |
| Package update/upgrade | ✅ | Partially |
| Install Docker Engine + Compose v2 | ✅ | ✅ (apt) |
| Install Caddy | ✅ | ✅ (apt) |
| Write Caddyfile | ✅ | Overwrites |
| Write systemd unit | ✅ | Overwrites |
| Write preflight script | ✅ | Overwrites |
| Create deploy directory | ✅ | ✅ |
| Enable Docker, Caddy, systemd unit | ✅ | ✅ |

**Secrets:** None — by design ([ADR-030](../../../decisions/ADR-030-observability-security-and-privacy.md)).

---

## 2. Current limitations

| ID | Limitation | Impact | Mitigation |
| --- | --- | --- | --- |
| CI-1 | cloud-init runs **once** at Droplet creation | Changing `user_data` in OpenTofu does not reconfigure existing host | Manual SSH or future CM |
| CI-2 | OpenTofu `ignore_changes` on `user_data` | Prevents accidental Droplet replacement | Document post-bootstrap updates |
| CI-3 | Caddyfile hostname baked at create time | Hostname change requires manual Caddy edit | tfvars change → new Droplet OR manual |
| CI-4 | No block volume mount | Strategy B requires manual steps | [storage-strategy.md](storage-strategy.md) |
| CI-5 | No deploy key / git clone | Repository delivery is separate step | [deployment-strategy.md](deployment-strategy.md) |
| CI-6 | `apt upgrade` on first boot | Unpredictable package versions on create date | Pin critical packages in future if needed |
| CI-7 | systemd unit enabled before compose file exists | Unit fails until first deploy | `ConditionPathExists` prevents start failure |

---

## 3. Idempotency concerns

### 3.1 Safe to re-run manually

Most `runcmd` steps are apt-based and safe if executed again on a running host (e.g., after snapshot restore).

### 3.2 Not safe to assume OpenTofu re-applies

```
tofu apply  →  user_data changed  →  IGNORED (ignore_changes)
                                     →  existing host UNCHANGED
```

Operators must use explicit post-bootstrap procedures for:

- Docker version upgrades
- Caddy configuration changes
- New system packages
- Block volume mounting

### 3.3 Recommended post-bootstrap update pattern

```bash
# Example: update Caddy after hostname change (manual)
vi /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy
```

---

## 4. Lifecycle interaction

| Event | cloud-init role |
| --- | --- |
| Droplet create | Full bootstrap |
| Droplet reboot | No re-run |
| `tofu apply` (same Droplet) | No re-run |
| Droplet replace | Full bootstrap on **new** instance |
| Reserved IP reassignment | No re-run on new Droplet — bootstrap runs on new instance |

---

## 5. Cloud-init vs Configuration Management

| Aspect | Cloud-init (current) | Configuration Management (future) |
| --- | --- | --- |
| **Tool** | cloud-init + shell | Ansible / similar (not chosen) |
| **Best for** | First boot provisioning | Ongoing drift correction |
| **Idempotent updates** | ❌ via OpenTofu | ✅ |
| **Secrets** | ❌ never | Vault/encrypted vars — careful design |
| **Complexity** | Low | Medium |
| **Team skill** | Standard DO pattern | Requires CM expertise |
| **Kubernetes path** | N/A | N/A — explicitly out of scope |

### 5.1 Recommendation

| Phase | Approach |
| --- | --- |
| Staging (now) | **Retain cloud-init** for bootstrap |
| Staging mature | Add **manual runbook** procedures for updates |
| Production | Evaluate **Ansible pull** or **immutable image** — requires ADR |
| Not recommended | Replacing cloud-init with Ansible in Phase 8.8.6 |

### 5.2 Future migration path (documentation only)

```
Stage 1 (current):  OpenTofu → cloud-init → manual deploy
Stage 2 (proposed): OpenTofu → cloud-init → CI/CD deploy script
Stage 3 (future):   OpenTofu → cloud-init → CM for drift → CI/CD deploy
Stage 4 (optional): Packer golden image → reduce cloud-init scope
```

**Ansible is explicitly not introduced in Phase 8.8.6.**

---

## 6. OpenTofu lifecycle review

### 6.1 Current protections

| Resource | Lifecycle rule | Rationale |
| --- | --- | --- |
| `digitalocean_droplet.observability` | `prevent_destroy = true` | Prevent accidental `tofu destroy` data loss |
| `digitalocean_droplet.observability` | `ignore_changes = [user_data]` | Prevent Droplet replace on template edit |
| `digitalocean_volume.observability` | None | Optional — consider `prevent_destroy` when Strategy B enabled |
| `digitalocean_firewall.observability` | None | Low risk — rules in Git |
| `digitalocean_reserved_ip.observability` | None | IP persists when Droplet destroyed — document carefully |

### 6.2 Additional protections recommended (documentation)

| Resource | Recommendation | Breaking? |
| --- | --- | --- |
| Block volume | Add `prevent_destroy = true` when `observability_use_block_volume = true` | No — literal required |
| Reserved IP | Document: do not destroy IP without DNS plan | N/A |
| Firewall | Current config sufficient | — |

**Note:** OpenTofu requires **literal** booleans in `lifecycle` blocks — cannot use variables for `prevent_destroy`.

### 6.3 Variables review

| Variable | Default | Change forces replace? |
| --- | --- | --- |
| `observability_droplet_size` | `s-4vcpu-8gb` | Resize in-place (may need power-off) |
| `observability_droplet_image` | `ubuntu-24-04-x64` | ⚠️ Yes — avoid after deploy |
| `observability_ssh_key_ids` | `[]` | No |
| `observability_use_block_volume` | `false` | Adds volume — no Droplet replace |
| `observability_use_reserved_ip` | `false` | Adds IP — no Droplet replace |

### 6.4 Outputs review

All observability outputs are **non-sensitive** — correct. No secrets exposed.

`observability_public_ipv4` returns Reserved IP when enabled — document for DNS.

---

## 7. Cross-references

| Document | Role |
| --- | --- |
| [observability-infrastructure-provisioning.md](observability-infrastructure-provisioning.md) | Bootstrap overview |
| [storage-strategy.md](storage-strategy.md) | Block volume manual steps |
| [observability-hardening.md](observability-hardening.md) | Hardening index |
