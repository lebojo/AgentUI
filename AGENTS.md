# Agent instructions

## Releases

Never create a new version without asking the user first and getting an explicit yes. This covers:

- creating or pushing a Git tag (any tag push triggers `.github/workflows/release.yml`, which builds, signs, notarizes and publishes a GitHub release);
- creating, editing or deleting a GitHub release;
- changing `MARKETING_VERSION` or the version shown on the site.

Approval for one version does not carry over to the next one. When the user approves, the release is made with:

```sh
git tag -a <version> -m "AgentUI <version>"
git push origin <version>
```

## Lint

SwiftUI views must declare their members in this order, with one blank line between sections and `private` where shown:

```swift
@AppStorage private var ...

@Environment private var ...
@EnvironmentObject private var ...

@State private var ...

@StateObject private var ...

@FocusState private var ...

@Binding var ...

@ObservedObject var ...
@ObservedRealmObject var ...
@ObservedResults private var ...
@Bindable var ...

let ...
private var ... {
}

var body: some View {}

private func ...
```

Check with `swift Scripts/lint-views.swift` and fix with `swift Scripts/lint-views.swift --fix`. Reordering stored properties changes the memberwise initializer, so update the call sites afterwards.
