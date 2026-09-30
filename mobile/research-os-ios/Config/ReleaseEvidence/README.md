# Local provider review evidence

This directory contains no provider account evidence in the public repository. Provider configuration, signing material, customer identifiers and account-specific review receipts must remain local and ignored.

The build guard can read an account-holder-reviewed receipt through an ignored local setting:

```text
RC_RELEASE_EVIDENCE_FILE = $(SRCROOT)/Config/ReleaseEvidence/provider-review.json
```

The validator checks receipt completeness, key binding and referenced evidence hashes. It cannot create missing provider observations or independently verify provider signatures. Public source availability does not make a production build signed, configured, purchased or approved by Apple.
