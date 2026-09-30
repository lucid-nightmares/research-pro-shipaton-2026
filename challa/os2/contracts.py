"""Frozen OS2 value contracts shared by every implementation lane.

These types are intentionally dependency-free.  They define identity and receipt
semantics; persistence, transport, and user-interface layers may serialize them
but may not weaken their validation rules.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from hashlib import sha256
import json
import re
from typing import Any, Mapping, Sequence


SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")


class ContractError(ValueError):
    """Raised when a value would violate an OS2 frozen contract."""


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def canonical_json(value: Any) -> str:
    return json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    )


def digest_bytes(value: bytes) -> str:
    return sha256(value).hexdigest()


def digest_json(value: Any) -> str:
    return digest_bytes(canonical_json(value).encode("utf-8"))


def require_id(name: str, value: str) -> str:
    if not isinstance(value, str) or not ID_RE.fullmatch(value):
        raise ContractError(f"{name} must be a stable 1-128 character identifier")
    return value


def require_sha256(name: str, value: str) -> str:
    if not isinstance(value, str) or not SHA256_RE.fullmatch(value):
        raise ContractError(f"{name} must be a lowercase SHA-256 digest")
    return value


@dataclass(frozen=True)
class SourceFormatId:
    """Format identity.  A bare integer schema version is never sufficient."""

    namespace: str
    schema_version: int
    structural_fingerprint: str

    def __post_init__(self) -> None:
        require_id("namespace", self.namespace)
        if self.schema_version < 1:
            raise ContractError("schema_version must be positive")
        require_sha256("structural_fingerprint", self.structural_fingerprint)

    @property
    def key(self) -> str:
        return f"{self.namespace}@{self.schema_version}:{self.structural_fingerprint}"


@dataclass(frozen=True, order=True)
class ObjectRef:
    project_id: str
    object_type: str
    logical_id: str
    version: int

    def __post_init__(self) -> None:
        require_id("project_id", self.project_id)
        require_id("object_type", self.object_type)
        require_id("logical_id", self.logical_id)
        if self.version < 1:
            raise ContractError("object version must be positive")

    @property
    def key(self) -> str:
        return f"{self.project_id}/{self.object_type}/{self.logical_id}@{self.version}"


@dataclass(frozen=True)
class EventEnvelope:
    event_id: str
    project_id: str
    branch_id: str
    sequence: int
    kind: str
    schema_id: str
    schema_version: int
    actor_ref: str
    authority_ref: str
    origin: str
    cause_refs: tuple[str, ...]
    object_refs: tuple[ObjectRef, ...]
    idempotency_key: str
    occurred_at: str
    parent_event_ids: tuple[str, ...]
    prior_project_digest: str
    payload_digest: str
    result_project_digest: str
    chain_digest: str
    payload: Mapping[str, Any] = field(compare=False, repr=False)

    def __post_init__(self) -> None:
        for name in (
            "event_id", "project_id", "branch_id", "kind", "schema_id",
            "actor_ref", "authority_ref", "origin", "idempotency_key",
        ):
            require_id(name, getattr(self, name))
        if self.sequence < 1 or self.schema_version < 1:
            raise ContractError("sequence and schema_version must be positive")
        for name in (
            "prior_project_digest", "payload_digest", "result_project_digest", "chain_digest"
        ):
            require_sha256(name, getattr(self, name))
        if digest_json(self.payload) != self.payload_digest:
            raise ContractError("payload_digest does not match the canonical payload")

    def header(self) -> dict[str, Any]:
        value = asdict(self)
        value.pop("payload")
        return value


@dataclass(frozen=True)
class ActionProposal:
    proposal_id: str
    actor_id: str
    project_id: str
    action_class: str
    exact_target: str
    data_classes: tuple[str, ...]
    path_scope: tuple[str, ...]
    host_scope: tuple[str, ...]
    input_digest: str
    idempotency_key: str
    risk_ceiling: str
    cost_ceiling_microunits: int
    policy_digest: str
    expires_at: str

    def __post_init__(self) -> None:
        for name in (
            "proposal_id", "actor_id", "project_id", "action_class",
            "idempotency_key", "risk_ceiling",
        ):
            require_id(name, getattr(self, name))
        require_sha256("input_digest", self.input_digest)
        require_sha256("policy_digest", self.policy_digest)
        if self.cost_ceiling_microunits < 0:
            raise ContractError("cost ceiling cannot be negative")
        if not self.exact_target:
            raise ContractError("exact_target is required")

    @property
    def digest(self) -> str:
        return digest_json(asdict(self))


@dataclass(frozen=True)
class ActionLease:
    lease_id: str
    proposal_digest: str
    granted_capabilities: tuple[str, ...]
    issued_at: str
    expires_at: str
    policy_digest: str
    broker_digest: str

    def __post_init__(self) -> None:
        require_id("lease_id", self.lease_id)
        for name in ("proposal_digest", "policy_digest", "broker_digest"):
            require_sha256(name, getattr(self, name))


@dataclass(frozen=True)
class ActionReceipt:
    receipt_id: str
    lease_id: str
    proposal_digest: str
    outcome: str
    output_digest: str
    settled_at: str
    prior_audit_digest: str
    audit_digest: str

    def __post_init__(self) -> None:
        for name in ("receipt_id", "lease_id", "outcome"):
            require_id(name, getattr(self, name))
        for name in (
            "proposal_digest", "output_digest", "prior_audit_digest", "audit_digest"
        ):
            require_sha256(name, getattr(self, name))


@dataclass(frozen=True)
class CanonicalResource:
    ref: ObjectRef
    media_type: str
    blob_digest: str
    metadata: Mapping[str, Any]
    provenance: Mapping[str, Any]

    def __post_init__(self) -> None:
        require_sha256("blob_digest", self.blob_digest)
        if not self.media_type:
            raise ContractError("media_type is required")

    @property
    def digest(self) -> str:
        return digest_json(asdict(self))


@dataclass(frozen=True)
class CanonicalResourceBatch:
    project_id: str
    resources: tuple[CanonicalResource, ...]
    source_snapshot_digest: str

    def __post_init__(self) -> None:
        require_id("project_id", self.project_id)
        require_sha256("source_snapshot_digest", self.source_snapshot_digest)
        if not self.resources:
            raise ContractError("a resource batch cannot be empty")
        if any(resource.ref.project_id != self.project_id for resource in self.resources):
            raise ContractError("every resource must belong to the batch project")

    @property
    def digest(self) -> str:
        return digest_json(asdict(self))


def stable_tuple(values: Sequence[str]) -> tuple[str, ...]:
    """Return a deterministic de-duplicated tuple for receipt fields."""

    return tuple(sorted(set(values)))

