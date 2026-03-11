---
id: runbook-adding-docs
role: runbooks
status: active
canonicality: canonical
doc_type: guide
title: Adding Docs Guide
summary: How to add canonical documents
last_reviewed: 2026-02-18
depends_on: []
verifies_with:
  - scripts/ci/check-repo-index-consistency.sh
---

# 05-adding-docs.md

**Goal:** Correctly add a new canonical document to the Heimserver repository.

## 1. Create the File

Create your markdown file in the appropriate directory (`architecture/`, `runtime/`, `operations/`, or `runbooks/`).

**Template:**
```markdown
---
id: my-new-doc
role: norm
status: active
canonicality: canonical
doc_type: guide
title: Adding Docs Guide
summary: How to add canonical documents
last_reviewed: 2026-02-18
depends_on: []
verifies_with: []
---

# Title matching filename

Content...
```

## 2. Register in Manifest

Add the filename to `manifest/repo-index.yaml` under the correct zone.

**Example:**
```yaml
zones:
  norm:
    path: architecture/
    canonical_docs:
      - ...
      - my-new-doc.md
```

## 3. Verify Consistency

Run the consistency check to ensure the frontmatter is valid and the file is registered correctly.

```bash
bash scripts/ci/check-repo-index-consistency.sh
```

## 4. Update System Map

Regenerate the system map to include your new document.

```bash
python3 scripts/generate-system-map.py
```

## 5. Commit

Commit both the new file, the updated manifest, and the updated `SYSTEM_MAP.md`.
