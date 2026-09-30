from __future__ import annotations

from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
APP = REPO / "mobile" / "research-os-ios" / "ResearchOSFlightRecorder"


def swift(name: str) -> str:
    return (APP / name).read_text(encoding="utf-8")


def test_v2_workflow_sources_are_present_and_native() -> None:
    required = {
        "ResearchWorkspace.swift",
        "WorkspaceLibraryView.swift",
        "ResearchInboxView.swift",
        "ResearchWorkflowViews.swift",
        "ResearchOSShortcuts.swift",
    }
    assert required.issubset({path.name for path in APP.glob("*.swift")})
    combined = "\n".join(swift(name) for name in sorted(required))
    assert "import SwiftUI" in combined
    assert "WKWebView" not in combined
    assert "URLSession" not in combined
    assert "RevenueCat" not in combined


def test_project_lifecycle_and_inbox_are_explicit() -> None:
    models = swift("ResearchWorkspace.swift")
    library = swift("WorkspaceLibraryView.swift")
    inbox = swift("ResearchInboxView.swift")
    for operation in (
        "createProject",
        "renameProject",
        "archiveProject",
        "restoreProject",
        "deleteProject",
    ):
        assert operation in models
    assert "NavigationSplitView" in library
    assert "confirmationDialog" in library
    assert "fileImporter" in inbox
    assert "InboxReviewState" in inbox
    assert "never become evidence" in inbox


def test_research_workflows_and_human_authority_are_visible() -> None:
    views = swift("ResearchWorkflowViews.swift")
    for workflow in (
        "ScopeProtocolView",
        "ClaimsEvidenceView",
        "ProofGateView",
        "ExplicitRepairsView",
        "DefenseView",
        "ReproducibilityView",
        "ResearchFSView",
    ):
        assert f"struct {workflow}" in views
    assert "Record my readiness decision" in views
    assert "does not claim independent validation" in views
    assert "Original wording stays visible" in swift("WorkspaceLibraryView.swift")
    assert "not independently validated" in views


def test_synthetic_and_user_created_states_cannot_be_conflated() -> None:
    models = swift("ResearchWorkspace.swift")
    library = swift("WorkspaceLibraryView.swift")
    assert 'case syntheticDemo = "SYNTHETIC_DEMO_ONLY"' in models
    assert 'case userCreated = "LOCAL_USER_CREATED_PROJECT"' in models
    assert "project.classification.label" in library
    assert "ProjectClassificationBanner" in library


def test_accessibility_and_progressive_disclosure_hooks_exist() -> None:
    combined = "\n".join(
        swift(name)
        for name in (
            "WorkspaceLibraryView.swift",
            "ResearchInboxView.swift",
            "ResearchWorkflowViews.swift",
        )
    )
    assert "NavigationSplitView" in combined
    # The deliberate UI merge uses ordered workbench rows with readable width,
    # while retaining every destination and native accessibility hooks.
    library = swift("WorkspaceLibraryView.swift")
    assert "LazyVStack(alignment: .leading" in library
    assert "WorkbenchLink(" in library
    destinations = ("Scope & protocol", "Claims & evidence", "Proof Gate", "Explicit repairs", "Defense", "Reproducibility", "ResearchFS")
    offsets = [library.index('title: "' + title + '"') for title in destinations]
    assert offsets == sorted(offsets)
    assert ".frame(maxWidth: 1_000)" in library
    assert ".frame(maxWidth: .infinity)" in library
    assert "DisclosureGroup" in combined
    assert ".accessibilityLabel" in combined
    assert ".accessibilityHint" in combined
    assert "ProgressView" in combined


def test_share_files_and_shortcuts_remain_user_initiated() -> None:
    workspace = swift("ResearchWorkspace.swift")
    library = swift("WorkspaceLibraryView.swift")
    research_fs = swift("ResearchWorkflowViews.swift")
    shortcuts = swift("ResearchOSShortcuts.swift")
    assert "completeFileProtection" in workspace
    assert "ShareLink" in library
    assert "ShareLink" in research_fs
    assert "AppShortcutsProvider" in shortcuts
    assert "openAppWhenRun = true" in shortcuts
    forbidden = ("upload", "submitForReview", "URLSession", "CloudKit")
    assert all(token not in workspace + shortcuts for token in forbidden)
