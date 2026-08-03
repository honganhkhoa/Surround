import Foundation

public enum SnapshotPreflight {
    public static func validate(release: NormalizedRelease, snapshot: RemoteSnapshot) throws {
        guard snapshot.appId.nonempty,
              snapshot.bundleId == release.bundleId,
              snapshot.platform == release.platform,
              snapshot.requestedVersion == release.version else {
            throw ReleaseToolError.validation("Normalized release and remote snapshot identity do not agree")
        }
        guard snapshot.fingerprint == (try SnapshotService.fingerprint(snapshot: snapshot)) else {
            throw ReleaseToolError.validation("Remote snapshot fingerprint does not match its contents")
        }
        if let target = snapshot.targetVersion {
            guard target.versionString == release.version,
                  target.state == "PREPARE_FOR_SUBMISSION" else {
                throw ReleaseToolError.validation(
                    "Target version must be PREPARE_FOR_SUBMISSION"
                )
            }
            guard snapshot.appInfo?.state == "PREPARE_FOR_SUBMISSION" else {
                throw ReleaseToolError.validation(
                    "An existing target version requires PREPARE_FOR_SUBMISSION App Info"
                )
            }
        } else {
            guard let source = snapshot.sourceVersion,
                  ["READY_FOR_DISTRIBUTION", "READY_FOR_SALE"].contains(source.state ?? "") else {
                throw ReleaseToolError.validation(
                    "Creating a version requires a live source version; rejected or stale drafts are never inherited"
                )
            }
            let copyright = release.versionMetadata["copyright"]?.stringValue
                ?? source.attributes["copyright"]?.stringValue
            guard let copyright,
                  !copyright.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ReleaseToolError.validation(
                    "Creating a version requires an explicit or verifiable inherited copyright"
                )
            }
        }

        let releaseLocales = Set(release.localizations.map(\.appStoreLocale))
        guard releaseLocales.count == release.localizations.count else {
            throw ReleaseToolError.validation("Normalized release contains duplicate locales")
        }
        let baselineVersionLocales = Set(
            (snapshot.targetVersion ?? snapshot.sourceVersion)?.localizations.map(\.locale) ?? []
        )
        let baselineAppLocales = Set(snapshot.appInfo?.localizations.map(\.locale) ?? [])
        guard baselineVersionLocales.isSubset(of: releaseLocales) else {
            throw ReleaseToolError.validation(
                "App Store version has unmanaged locales: \(baselineVersionLocales.subtracting(releaseLocales).sorted())"
            )
        }
        guard baselineAppLocales.isSubset(of: releaseLocales) else {
            throw ReleaseToolError.validation(
                "App Info has unmanaged locales: \(baselineAppLocales.subtracting(releaseLocales).sorted())"
            )
        }
        for locale in release.localizations {
            let targetLocale = snapshot.targetVersion?.localizations.first { $0.locale == locale.appStoreLocale }
            let sourceLocale = snapshot.sourceVersion?.localizations.first { $0.locale == locale.appStoreLocale }
            let appInfoLocale = snapshot.appInfo?.localizations.first { $0.locale == locale.appStoreLocale }
            // A partial publish or manual setup may already have created draft
            // resources. The language remains new until it exists in the
            // released source version, so validate the effective draft values.
            if sourceLocale == nil {
                let requiredMetadata: [(field: String, value: JSONValue?)] = [
                    (
                        "versionMetadata.description",
                        locale.versionMetadata["description"]
                            ?? targetLocale?.attributes["description"]
                    ),
                    (
                        "versionMetadata.keywords",
                        locale.versionMetadata["keywords"] ?? targetLocale?.attributes["keywords"]
                    ),
                    (
                        "versionMetadata.supportUrl",
                        locale.versionMetadata["supportUrl"] ?? targetLocale?.attributes["supportUrl"]
                    ),
                    (
                        "appMetadata.name",
                        locale.appMetadata["name"] ?? appInfoLocale?.attributes["name"]
                    ),
                    (
                        "appMetadata.subtitle",
                        locale.appMetadata["subtitle"] ?? appInfoLocale?.attributes["subtitle"]
                    ),
                    (
                        "appMetadata.privacyPolicyUrl",
                        locale.appMetadata["privacyPolicyUrl"]
                            ?? appInfoLocale?.attributes["privacyPolicyUrl"]
                    ),
                ]
                let missing = requiredMetadata.compactMap { required -> String? in
                    guard case let .string(value)? = required.value,
                          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return required.field
                    }
                    return nil
                }
                guard missing.isEmpty else {
                    throw ReleaseToolError.validation(
                        "New language \(locale.appStoreLocale) requires non-empty "
                            + "\(missing.joined(separator: ", ")) in the release "
                            + "or reviewed draft metadata"
                    )
                }
            } else if appInfoLocale == nil {
                guard case let .string(name)? = locale.appMetadata["name"], name.count >= 2 else {
                    throw ReleaseToolError.validation(
                        "New App Info locale \(locale.appStoreLocale) requires an explicit localized name"
                    )
                }
            }
        }
    }
}

private extension String {
    var nonempty: Bool { !isEmpty }
}
