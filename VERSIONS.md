# Safari Vault version history

The owner approved this capability split on 2026-10-04. Existing tags and packaged downloads remain unchanged. All new records are **alpha, source-only**. A source record does not certify store submission, signing or native release acceptance.

Current source version: **3.1.1**. See the group-level `CHANGELOG.md` for the cross-product chapters.

## 3.1.1 — 2026-10-07 — Website recording resume

- Re-enabling website recording resumes the focused active tab without a tab change.
- Unfocused browser windows remain excluded when settings refresh or tab events arrive.
- Native rule, authentication and permission contracts are unchanged.

## 3.1.0 — 2026-10-04 — Separate Safari native runtime

Source: `release/v3.1.0`.

- Rebuild of the extension 3.1.0 engine and shared Settings/editor resources.
- Safari Vault now has its own containing app and native rule/file runtime with authenticated desktop pairing.
- Reviewed native language resources and bounded browser timer paging. Signed packaging and native Safari acceptance remain separate from this source record.

## 3.0.0 — 2026-09-27 — Rebuild of the shared policy and rule engine

Source: `7d0656091272de72f7381c6171e7f9237c295494`.

Retroactive milestone: the annotated tag names this exact historical snapshot. Its embedded version field retains the earlier number; no historical commit is rewritten and no package was distributed under this number.

- Actual Safari rebuild corresponding to the extension 3.0.0 engine milestone, including scope-based policies, linked budgets and the new bare rule contract.
- Rule state survives Run and disabled groups suppress rule effects.
- There was no separately matching Safari rebuild for the extension 2.5.0 snapshot, so no Safari 2.5.0 record is invented.

## Earlier versions

All existing `v*` tags, `release/v*` branches and published artifacts are retained. Their original details remain in the group changelog and website History.
