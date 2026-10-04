#!/usr/bin/env python3
"""Offline catalog validation, checking ms/id by default or all supported locales.

Run from anywhere; the catalog defaults to this script's repository.
Checks runtime argument identities, including reordered positional specifiers,
literal percent signs, plural leaves and xcstrings named substitutions.
Baseline identity and exact task-inventory assertions are optional. Compiler
stringsdata can additionally validate current source-key coverage. No packages,
network requests, Xcode or simulator operations are required.
"""
import argparse
import collections
import hashlib
import json
import re
import sys
from pathlib import Path

TARGET_LOCALES = ("ms", "id")
PLURAL_CATEGORIES = {"zero", "one", "two", "few", "many", "other"}
NEUTRAL_SEPARATORS = {"–", "—"}
HERE = Path(__file__).resolve().parent
FORMAT = re.compile(
    r"%(?:(?P<position>[1-9]\d*)\$)?(?P<flags>[-+ #0']*)"
    r"(?P<width>\d+|\*(?:[1-9]\d*\$)?)?"
    r"(?P<precision>\.(?:\d+|\*(?:[1-9]\d*\$)?))?"
    r"(?P<length>hh|ll|h|l|L|q|z|t|j)?"
    r"(?P<conversion>[@diuoxXfFeEgGaAcCsSp])"
)
NAMED = re.compile(r"%#@([A-Za-z_][A-Za-z_0-9]*)@")
# These are verified DEBUG-only probes/previews, not shipping product strings.
# Exact source locations deliberately fail closed if an unlocalized product
# string later acquires the same key elsewhere. Refresh locations after edits.
EXCLUDED_COMPILER_KEYS = {
    "App review context": ("Views/AppReviewPresentation.swift", 150, "DEBUG UI-test context overlay"),
    "Hosted review coordinator": ("Views/AppReviewPresentation.swift", 219, "DEBUG hosted UI-test probe"),
    "absent": ("Views/AppReviewPresentation.swift", 221, "DEBUG hosted UI-test probe value"),
    "present": ("Views/AppReviewPresentation.swift", 221, "DEBUG hosted UI-test probe value"),
    "Finish pending UI": ("Views/AppReviewPresentation.swift", 222, "DEBUG hosted UI-test probe action"),
    "Start pending UI": ("Views/AppReviewPresentation.swift", 222, "DEBUG hosted UI-test probe action"),
    "Compact layout": ("UITesting/GameLayoutUITestHarness.swift", 40, "DEBUG opt-in layout harness"),
    "compact": ("UITesting/GameLayoutUITestHarness.swift", 44, "DEBUG opt-in layout harness value"),
    "regular": ("UITesting/GameLayoutUITestHarness.swift", 44, "DEBUG opt-in layout harness value"),
    "Regular layout": ("UITesting/GameLayoutUITestHarness.swift", 48, "DEBUG opt-in layout harness"),
    "View": ("Components/NotificationPopup.swift", (267, 268), "DEBUG notification preview"),
    "Back": ("Components/NotificationPopup.swift", 270, "DEBUG notification preview"),
    "Custom game": ("Views/CustomGameForm.swift", 779, "DEBUG custom-game preview"),
    "Preferred settings": ("Views/PreferredSettingsView.swift", 267, "DEBUG preferred-settings preview"),
    "The web view is unavailable in offline UI tests.": ("Services/NavigationService.swift", 400, "DEBUG offline browser placeholder"),
}


class CatalogError(ValueError):
    pass


def unique_object(pairs):
    obj = {}
    for key, value in pairs:
        if key in obj:
            raise CatalogError(f"Duplicate JSON key: {key!r}")
        obj[key] = value
    return obj


def read_json(path):
    return json.loads(path.read_text(), object_pairs_hook=unique_object)


def arguments(text, substitutions=None, substitution_arg=None):
    """Return ordered argument identity/type multiplicities and %% count.

    Numeric indexes are normalized so '%@ %lld' and '%2$lld %1$@' match.
    Named xcstrings references consume the argNum and formatSpecifier declared
    by their substitution. A substitution's '%arg' consumes that same arg.
    """
    substitutions = substitutions or {}
    result = []
    refs = []
    next_arg = 1
    explicit = implicit = False
    literal_percents = 0
    cursor = 0
    while cursor < len(text):
        if text[cursor] != "%":
            cursor += 1
            continue
        if text.startswith("%%", cursor):
            literal_percents += 1
            cursor += 2
            continue
        named = NAMED.match(text, cursor)
        if named:
            name = named[1]
            if name not in substitutions:
                raise CatalogError(f"Undeclared substitution {name!r}")
            sub = substitutions[name]
            result.append((sub["argNum"], sub["formatSpecifier"]))
            refs.append(name)
            explicit = True
            cursor = named.end()
            continue
        if text.startswith("%arg", cursor):
            if substitution_arg is None:
                raise CatalogError("%arg outside a substitution")
            result.append(substitution_arg)
            explicit = True
            cursor += 4
            continue
        token = FORMAT.match(text, cursor)
        if token is None:
            raise CatalogError(f"Unrecognized percent sequence: {text[cursor:cursor + 18]!r}")
        position = token["position"]
        if position:
            explicit = True
            arg_num = int(position)
        else:
            implicit = True
            arg_num = next_arg
            next_arg += 1
        # Dynamic width/precision are separate integer arguments in printf.
        for field in (token["width"], token["precision"]):
            if field and "*" in field:
                star_position = re.search(r"\*([1-9]\d*)\$", field)
                if star_position:
                    explicit = True
                    result.append((int(star_position[1]), "d:width"))
                else:
                    implicit = True
                    result.append((arg_num, "d:width"))
                    arg_num = next_arg
                    next_arg += 1
        specifier = "".join(token[name] or "" for name in (
            "flags", "width", "precision", "length", "conversion"
        ))
        result.append((arg_num, specifier))
        cursor = token.end()
    if explicit and implicit:
        raise CatalogError("Mixed positional and implicit format arguments")
    return collections.Counter(result), literal_percents, collections.Counter(refs)


def leaves(node, path=""):
    if isinstance(node, dict):
        if "stringUnit" in node:
            yield path or "root", node["stringUnit"]
        if "variations" in node:
            for axis, variants in node["variations"].items():
                for category, child in variants.items():
                    yield from leaves(child, f"{path}/{axis}/{category}")


def formatting(text):
    """Preserve layout/Markdown punctuation without restricting grammar."""
    return {
        "leadingWhitespace": re.match(r"^\s*", text)[0],
        "trailingWhitespace": re.search(r"\s*$", text)[0],
        "newlines": text.count("\n"), "ellipsisGlyphs": text.count("…"),
        "asciiEllipses": len(re.findall(r"(?<!\.)\.{3}(?!\.)", text)),
        "boldMarkers": text.count("**"), "codeMarkers": text.count("`"),
        "middleDots": text.count("·"), "bullets": text.count("•"),
        "markdownLinkDestinations": sorted(re.findall(r"\]\(([^)]+)\)", text)),
    }


def source_text(node, default):
    """Use English other/main leaf, falling back to the source key."""
    if "stringUnit" in node:
        return node["stringUnit"]["value"]
    if "variations" in node:
        return source_text(node["variations"].get("plural", {}).get("other", {}), default)
    return default


def source_leaf_text(node, path, default):
    """Match singular/plural English wording before falling back to other."""
    unit = dict(leaves(node)).get(path)
    return unit["value"] if unit is not None else source_text(node, default)


def supported_locales(catalog, project=None):
    """Include registered regions even when a locale has no catalog entries."""
    locales = {catalog.get("sourceLanguage", "en")}
    for entry in catalog.get("strings", {}).values():
        locales.update(entry.get("localizations", {}))
    if project is not None:
        content = project.read_text()
        blocks = re.findall(r"\bknownRegions\s*=\s*\((.*?)\);", content, re.DOTALL)
        if len(blocks) != 1:
            raise CatalogError(f"Expected one project knownRegions list in {project}")
        for item in blocks[0].split(","):
            item = re.sub(r"/\*.*?\*/|//[^\n]*", "", item, flags=re.DOTALL).strip().strip('"')
            if item:
                locales.add(item)
    return tuple(sorted(locales - {"Base"}))


def plural_profiles(catalog):
    """Use established locale shapes, without imposing ms/id's rules elsewhere."""
    profiles = collections.defaultdict(collections.Counter)

    def collect(node, locale):
        if not isinstance(node, dict):
            return
        plural = node.get("variations", {}).get("plural")
        if isinstance(plural, dict):
            profiles[locale][frozenset(plural)] += 1
            for child in plural.values():
                collect(child, locale)
        for child in node.get("substitutions", {}).values():
            collect(child, locale)

    for entry in catalog.get("strings", {}).values():
        if entry.get("extractionState") != "stale":
            for locale, localization in entry.get("localizations", {}).items():
                collect(localization, locale)
    # A new or damaged entry must not create its own accepted locale pattern.
    return {locale: counts.most_common(1)[0][0] for locale, counts in profiles.items() if counts}


def shape(node, label, failures, locale="ms", profiles=None, reference=None,
          is_substitution=False, allow_empty=False, is_variant=False):
    if not isinstance(node, dict):
        failures.append(f"{label}: localization must be an object")
        return
    permitted = {"variations", "stringUnit"} | ({"argNum", "formatSpecifier"} if is_substitution else {"substitutions"})
    unexpected = set(node) - permitted
    if unexpected:
        failures.append(f"{label}: unknown localization fields {sorted(unexpected)}")
    has_unit = "stringUnit" in node
    has_variations = "variations" in node
    if reference and "variations" in reference and not has_variations:
        failures.append(f"{label}: baseline plural structure not preserved")
    if reference and "stringUnit" in reference and has_variations:
        failures.append(f"{label}: baseline stringUnit structure changed to variations")
    if is_variant and has_variations:
        failures.append(f"{label}: repeated nested plural axes are not supported")
    if has_unit == has_variations:
        failures.append(f"{label}: must have exactly one stringUnit or variations")
    if has_unit:
        unit = node["stringUnit"]
        if not isinstance(unit, dict) or set(unit) != {"state", "value"}:
            failures.append(f"{label}: stringUnit requires state and value")
        elif unit["state"] not in ({"translated", "new"} if locale == "en" else {"translated"}) or not isinstance(unit["value"], str) or (not unit["value"] and not allow_empty):
            failures.append(f"{label}: {'source' if locale == 'en' else 'translated'} stringUnit with a valid value/state required")
    if has_variations:
        axes = node["variations"]
        if not isinstance(axes, dict) or set(axes) != {"plural"}:
            failures.append(f"{label}: only plural variation axis supported by this catalog")
        else:
            plural = axes["plural"]
            if not isinstance(plural, dict):
                failures.append(f"{label}: plural variations must be an object")
            else:
                categories = set(plural)
                if "other" not in categories or categories - PLURAL_CATEGORIES:
                    failures.append(f"{label}: plural requires other and valid cardinal categories")
                if locale in TARGET_LOCALES:
                    expected = {"other"}
                elif locale == "en":
                    expected = {"one", "other"}
                else:
                    reference_plural = (reference or {}).get("variations", {}).get("plural")
                    expected = set(reference_plural) if isinstance(reference_plural, dict) else (profiles or {}).get(locale)
                if expected is not None and categories != expected:
                    failures.append(f"{label}: plural categories changed: {sorted(categories)} != {sorted(expected)}")
                for category, child in plural.items():
                    child_reference = ((reference or {}).get("variations", {}).get("plural", {}).get(category))
                    shape(child, label + "/plural/" + category, failures, locale, profiles,
                          child_reference, allow_empty=allow_empty, is_variant=True)
    if is_substitution:
        if not isinstance(node.get("argNum"), int) or isinstance(node.get("argNum"), bool) or node.get("argNum", 0) < 1:
            failures.append(f"{label}: positive integer argNum required")
        fmt = node.get("formatSpecifier")
        if not isinstance(fmt, str) or not FORMAT.fullmatch("%" + fmt):
            failures.append(f"{label}: invalid formatSpecifier")


def compiler_inventory(root, source_dir):
    extracted, excluded = {}, {}
    files = sorted(root.rglob("*.stringsdata"))
    if not files:
        raise CatalogError(f"No compiler .stringsdata files found under {root}")
    examined = 0
    for path in files:
        data = read_json(path)
        source = Path(data.get("source", ""))
        try:
            relative = source.resolve().relative_to(source_dir.resolve()).as_posix()
        except ValueError:
            continue  # Dependency or test-target source outside the app directory.
        entries = data.get("tables", {}).get("Localizable", [])
        examined += 1
        for entry in entries:
            key = entry["key"]
            location = entry.get("location", {})
            line = location.get("startingLine")
            exclusion = EXCLUDED_COMPILER_KEYS.get(key)
            if exclusion and relative == exclusion[0] and line in (
                exclusion[1] if isinstance(exclusion[1], tuple) else (exclusion[1],)
            ):
                excluded.setdefault(key, {"reason": exclusion[2], "source": relative, "lines": []})
                if line not in excluded[key]["lines"]:
                    excluded[key]["lines"].append(line)
            else:
                extracted.setdefault(key, [])
                record = {"source": relative, "line": line}
                if record not in extracted[key]:
                    extracted[key].append(record)
    if not examined or not extracted:
        raise CatalogError("No app Localizable strings found in compiler stringsdata")
    return extracted, excluded, examined


def validate(catalog, baseline=None, inventory=None, compiler=None, all_locales=False,
             structure_baseline=None, project=None):
    failures, warnings = [], []
    strings = catalog.get("strings", {})
    if not isinstance(strings, dict) or catalog.get("sourceLanguage") != "en" or catalog.get("version") != "1.0":
        return {"passed": False, "errors": ["Invalid strings, sourceLanguage or catalog version"], "warnings": []}
    locales = supported_locales(catalog, project) if all_locales else TARGET_LOCALES
    structure_baseline = structure_baseline or baseline
    profiles = plural_profiles(structure_baseline or catalog)
    preserved_formatting, preserved_structures, legacy_format_errors = [], [], []
    missing_translations = {locale: [] for locale in locales}
    source_fallbacks = 0

    def check_formatting(label, value, source_value, reference_unit, baseline_source_value):
        source_formatting, target_formatting = formatting(source_value), formatting(value)
        changed = [field for field in source_formatting if source_formatting[field] != target_formatting[field]]
        if changed:
            message = f"{label}: formatting changed: {', '.join(changed)}"
            if (reference_unit and value == reference_unit.get("value")
                    and baseline_source_value is not None
                    and source_formatting == formatting(baseline_source_value)):
                preserved_formatting.append(message)
            else:
                failures.append(message)

    def format_failure(message, value, reference_unit):
        failures.append(message)
        if reference_unit and value == reference_unit.get("value"):
            legacy_format_errors.append(message)
    if inventory:
        expected = set(inventory["expectedKeys"])
        if set(strings) != expected:
            failures.append(f"Key-set mismatch: missing={sorted(expected-set(strings))!r}; unexpected={sorted(set(strings)-expected)!r}")
    source_preserved = 0
    for key, old_entry in (baseline or {}).get("strings", {}).items():
        if key not in strings:
            failures.append(f"Removed baseline key {key!r}")
            continue
        current = strings[key].get("localizations", {})
        for locale, localization in old_entry.get("localizations", {}).items():
            if current.get(locale) != localization:
                failures.append(f"Existing locale changed: {key!r} [{locale}]")
            else:
                source_preserved += 1
    if baseline:
        for field in ("sourceLanguage", "version"):
            if catalog.get(field) != baseline.get(field):
                failures.append(f"Baseline catalog {field} changed")
    stale = {key for key, value in strings.items() if value.get("extractionState") == "stale"}
    if inventory and stale != set(inventory["expectedStaleKeys"]):
        failures.append(f"Stale-key mismatch: {sorted(stale)!r}")
    for key in (inventory or {}).get("revivedKeys", []):
        if key not in strings or strings[key].get("extractionState") == "stale":
            failures.append(f"Live Messages key still stale/missing: {key!r}")
    actual_neutral = {key for key, entry in strings.items() if entry.get("shouldTranslate") is False}
    inventory_neutral = set(inventory["explicitNeutralKeys"]) if inventory else actual_neutral
    neutral = inventory_neutral | (NEUTRAL_SEPARATORS & set(strings))
    if inventory and actual_neutral != inventory_neutral:
        failures.append(f"Explicit neutral key mismatch: {sorted(actual_neutral)!r}")
    coverage = {locale: 0 for locale in locales}
    plural_counts = {locale: 0 for locale in locales}
    substitution_counts = {locale: 0 for locale in locales}
    leaf_counts = {locale: 0 for locale in locales}
    retained_stale_objects = 0
    for key, entry in strings.items():
        if key in stale:
            # Obsolete keys retain previously reviewed translations. A supplied
            # identity baseline still rejects changes to those locale objects.
            retained_stale_objects += sum(locale in entry.get("localizations", {}) for locale in locales)
            continue
        if key in neutral:
            # Existing symbol leaves are valid, but cannot acquire language text.
            for locale in locales:
                localization = entry.get("localizations", {}).get(locale)
                if localization is not None:
                    label = f"{key!r} [{locale}]"
                    shape(localization, label, failures, locale, profiles, allow_empty=key == "")
                    for path, unit in leaves(localization):
                        if unit.get("value") != key:
                            failures.append(f"{label}{path}: neutral visible value changed")
            continue
        source = entry.get("localizations", {}).get("en", {})
        source_subs = source.get("substitutions", {})
        old_entry = (structure_baseline or {}).get("strings", {}).get(key, {})
        old_source = old_entry.get("localizations", {}).get("en", {})
        try:
            source_contract = arguments(key)[:2]
        except CatalogError as error:
            failures.append(f"Source key {key!r}: {error}")
            continue
        for locale in locales:
            label = f"{key!r} [{locale}]"
            localization = entry.get("localizations", {}).get(locale)
            if locale == "en" and localization is None:
                # Source-language values can live solely in the catalog key.
                localization = {"stringUnit": {"state": "translated", "value": key}}
                source_fallbacks += 1
            if localization is None:
                failures.append(f"Missing localization: {label}")
                missing_translations[locale].append(key)
                continue
            coverage[locale] += 1
            reference = old_entry.get("localizations", {}).get(locale)
            reference_leaves = dict(leaves(reference))
            shape(localization, label, failures, locale, profiles, reference)
            subs = localization.get("substitutions", {})
            reference_subs = (reference or {}).get("substitutions", {})
            if reference is not None and set(reference_subs) != set(subs):
                failures.append(f"{label}: baseline substitution structure/names not preserved")
            if "variations" in source and "variations" not in localization:
                if all_locales and locale not in TARGET_LOCALES and reference and "stringUnit" in reference:
                    preserved_structures.append(f"{label}: retained baseline stringUnit for an English plural key")
                else:
                    failures.append(f"{label}: source plural structure not preserved")
            if bool(source_subs) != bool(subs) or set(source_subs) != set(subs):
                failures.append(f"{label}: source substitution structure/names not preserved")
            if "variations" in localization:
                plural_counts[locale] += 1
            if subs:
                substitution_counts[locale] += len(subs)
            for name, sub in subs.items():
                sublabel = f"{label}/substitution/{name}"
                reference_sub = (reference or {}).get("substitutions", {}).get(name)
                reference_sub_leaves = dict(leaves(reference_sub))
                shape(sub, sublabel, failures, locale, profiles, reference_sub, is_substitution=True)
                source_sub = source_subs.get(name, {})
                if any(sub.get(field) != source_sub.get(field) for field in ("argNum", "formatSpecifier")):
                    failures.append(f"{sublabel}: source argument number/type changed")
                if reference_sub and any(sub.get(field) != reference_sub.get(field) for field in ("argNum", "formatSpecifier")):
                    failures.append(f"{sublabel}: baseline argument number/type changed")
                if "argNum" not in sub or "formatSpecifier" not in sub:
                    continue
                for path, unit in leaves(sub):
                    try:
                        contract, escaped, refs = arguments(unit["value"], substitution_arg=(sub["argNum"], sub["formatSpecifier"]))
                        if contract != collections.Counter({(sub["argNum"], sub["formatSpecifier"]): 1}) or escaped or refs:
                            format_failure(f"{sublabel}{path}: %arg contract changed", unit["value"], reference_sub_leaves.get(path))
                        old_source_sub = old_source.get("substitutions", {}).get(name, {})
                        check_formatting(sublabel + path, unit["value"], source_text(source_sub, "%arg"),
                                         reference_sub_leaves.get(path), source_text(old_source_sub, "%arg") if old_entry else None)
                    except (CatalogError, KeyError, TypeError) as error:
                        failures.append(f"{sublabel}{path}: {error}")
                    leaf_counts[locale] += 1
            for path, unit in leaves(localization):
                try:
                    contract, escaped, refs = arguments(unit["value"], subs)
                    source_value = source_leaf_text(source, path, key) if all_locales else source_text(source, key)
                    leaf_contract = arguments(source_value, source_subs)[:2] if all_locales and locale != "en" else source_contract
                    if all_locales and locale == "en" and path != "root" and not path.endswith("/other"):
                        # A singular English leaf can omit a displayed count;
                        # its enclosing plural rule still consumes that number.
                        # Unrelated arguments remain mandatory. If the driving
                        # number is ambiguous, no omission is accepted.
                        count_arguments = [argument for argument in source_contract[0]
                                           if argument[1].endswith(tuple("diuoxXfFeEgGaA"))]
                        singular_contract = source_contract[0].copy()
                        if len(count_arguments) == 1:
                            del singular_contract[count_arguments[0]]
                        valid = contract in (source_contract[0], singular_contract) and escaped == source_contract[1]
                    else:
                        valid = (contract, escaped) == leaf_contract
                    if not valid:
                        format_failure(f"{label}{path}: format contract changed: {dict(contract)!r} != {dict(leaf_contract[0])!r}", unit["value"], reference_leaves.get(path))
                    if subs and refs != collections.Counter({name: 1 for name in subs}):
                        failures.append(f"{label}{path}: substitution references missing/duplicated")
                    old_source_value = (source_leaf_text(old_source, path, key) if all_locales else source_text(old_source, key)) if old_entry else None
                    check_formatting(label + path, unit["value"], source_value, reference_leaves.get(path), old_source_value)
                    neutral_value = (inventory or {}).get("unchangedNeutralValues", {}).get(key)
                    if neutral_value is None and "%" not in key and not any(char.isalnum() for char in key):
                        neutral_value = key  # Preserve implicit punctuation-only entries such as —.
                    if neutral_value is not None and unit["value"] != neutral_value:
                        failures.append(f"{label}: neutral visible value changed")
                except (CatalogError, KeyError, TypeError) as error:
                    failures.append(f"{label}{path}: {error}")
                leaf_counts[locale] += 1
    identical = []
    for key, entry in strings.items():
        locs = entry.get("localizations", {})
        if "ms" in locs and "id" in locs and locs["ms"] == locs["id"]:
            identical.append(key)
    warnings.append("Identical ms/id entries include shared terms and format-only strings; natural-language quality requires review.")
    if preserved_formatting:
        warnings.append(f"Preserved {len(preserved_formatting)} baseline style/whitespace differences; see preservedBaselineFormatting.")
    if preserved_structures:
        warnings.append(f"Preserved {len(preserved_structures)} baseline simple units for English plural keys; see preservedBaselineStructures.")
    if all_locales and structure_baseline is None:
        warnings.append("Plural profiles come from the current catalog; supply --structure-baseline for a historical shape/style audit.")
    report = {
        "passed": not failures, "totalKeys": len(strings), "activeKeys": len(strings)-len(stale),
        "validatedLocales": list(locales), "explicitNeutralKeys": sorted(actual_neutral),
        "neutralKeys": sorted(neutral), "staleKeys": sorted(stale), "coverage": coverage,
        "expectedCoveragePerLocale": len(set(strings)-stale-neutral),
        "missingTranslations": missing_translations, "sourceFallbackEntries": source_fallbacks,
        "retainedStaleLocaleObjects": retained_stale_objects,
        "preservedBaselineFormatting": preserved_formatting,
        "preservedBaselineStructures": preserved_structures,
        "unresolvedLegacyFormatErrors": legacy_format_errors,
        "pluralProfiles": {locale: sorted(categories) for locale, categories in sorted(profiles.items())},
        "pluralEntries": plural_counts, "substitutions": substitution_counts, "translatedLeaves": leaf_counts,
        "existingLocaleObjectsPreserved": source_preserved if baseline else None, "identicalTargetEntryCount": len(identical),
        "identicalTargetEntries": identical, "excludedCompilerKeyCount": len((inventory or {}).get("excludedCompilerKeys", {})),
        "errors": failures, "warnings": warnings,
    }
    if compiler:
        extracted, excluded, file_count = compiler
        missing = set(extracted) - set(strings)
        live_stale = set(extracted) & stale
        if missing:
            failures.append(f"Compiler-extracted product keys missing from catalog: {sorted(missing)!r}")
        if live_stale:
            failures.append(f"Compiler-extracted live keys are stale: {sorted(live_stale)!r}")
        report.update({
            "compilerAppStringsdataFiles": file_count,
            "compilerProductKeys": len(extracted), "compilerMissingKeys": sorted(missing),
            "compilerLiveStaleKeys": sorted(live_stale), "compilerExcludedKeys": excluded,
            "compilerActiveNotExtractedKeys": sorted(set(strings)-stale-neutral-set(extracted)),
        })
    report["passed"] = not failures
    return report


def self_test():
    def clone(value):
        return json.loads(json.dumps(value))

    def unit(value, state="translated"):
        return {"stringUnit": {"state": state, "value": value}}

    def plural(one=None, other="%lld items"):
        values = {"other": unit(other)}
        if one is not None:
            values["one"] = unit(one)
        return {"variations": {"plural": values}}

    assert arguments("%@ %lld %.1f")[:2] == arguments("%3$.1f %2$lld %1$@")[:2]
    assert arguments("%02d:%02d")[:2] == arguments("%1$02d:%2$02d")[:2]
    assert arguments("%.1f")[:2] != arguments("%f")[:2]
    assert arguments("%lld")[:2] != arguments("%d")[:2]
    assert arguments("%% %@")[1] == 1
    assert arguments("%lld %lld")[:2] != arguments("%1$lld %1$lld")[:2]
    for bad in ("%1$@ %@", "%#@undeclared@", "%arg", "%?invalid"):
        try:
            arguments(bad)
        except CatalogError:
            pass
        else:
            raise AssertionError(f"Accepted invalid format {bad!r}")
    sub = {"n": {"argNum": 1, "formatSpecifier": "lld"}}
    assert arguments("%#@n@", sub)[:2] == arguments("%lld")[:2]
    assert arguments("%arg", substitution_arg=(1, "lld"))[:2] == arguments("%lld")[:2]
    assert formatting(" **x**…\n· `y` ") != formatting("**x**...\n· `y`")
    try:
        json.loads('{"strings":{},"strings":{}}', object_pairs_hook=unique_object)
    except CatalogError:
        pass
    else:
        raise AssertionError("Duplicate JSON keys accepted")
    fixture = {"sourceLanguage": "en", "version": "1.0", "strings": {
        "Count %lld": {"localizations": {
            "ms": {"stringUnit": {"state": "translated", "value": "Jumlah %lld"}},
            "id": {"stringUnit": {"state": "translated", "value": "Jumlah %lld"}},
        }}
    }}
    assert validate(fixture)["passed"]
    fixture["strings"]["Count %lld"]["localizations"]["ms"]["stringUnit"]["value"] = "Jumlah %d"
    assert not validate(fixture)["passed"]
    fixture["strings"]["Count %lld"]["localizations"].pop("id")
    assert any("Missing localization" in e for e in validate(fixture)["errors"])

    complete = {"sourceLanguage": "en", "version": "1.0", "strings": {
        "Count %lld": {"localizations": {
            "de": unit("Anzahl %lld"), "ja": unit("%lld個"),
            "ms": unit("Jumlah %lld"), "id": unit("Jumlah %lld"),
        }},
    }}
    report = validate(complete, all_locales=True, structure_baseline=complete)
    assert report["passed"] and report["sourceFallbackEntries"] == 1
    assert report["coverage"]["en"] == 1
    assert report["validatedLocales"] == ["de", "en", "id", "ja", "ms"]
    # knownRegions must reveal an entirely absent target locale, not just
    # validate whichever locales happen to have one or more catalog entries.
    from tempfile import TemporaryDirectory
    with TemporaryDirectory(prefix="surround-localization-self-test-") as directory:
        project = Path(directory) / "project.pbxproj"
        project.write_text('knownRegions = (en, Base, de, "pt-PT",);\n')
        assert "Base" not in supported_locales(complete, project)
        report = validate(complete, all_locales=True, structure_baseline=complete, project=project)
        assert report["missingTranslations"]["pt-PT"] == ["Count %lld"]

    dropped = clone(complete)
    dropped["strings"]["Count %lld"]["localizations"]["de"] = unit("Anzahl")
    report = validate(dropped, all_locales=True, structure_baseline=complete)
    assert not report["passed"] and any("format contract changed" in e for e in report["errors"])
    assert not report["unresolvedLegacyFormatErrors"]
    # An unchanged but defective baseline is reported and remains a failure.
    report = validate(dropped, all_locales=True, structure_baseline=dropped)
    assert not report["passed"] and report["unresolvedLegacyFormatErrors"]
    wrong_state = clone(complete)
    wrong_state["strings"]["Count %lld"]["localizations"]["de"] = unit("Anzahl %lld", "needs_review")
    assert not validate(wrong_state, all_locales=True, structure_baseline=complete)["passed"]
    source_new = clone(complete)
    source_new["strings"]["Count %lld"]["localizations"]["en"] = unit("Count %lld", "new")
    assert validate(source_new, all_locales=True, structure_baseline=complete)["passed"]

    plurals = {"sourceLanguage": "en", "version": "1.0", "strings": {
        "See all %lld games": {"localizations": {
            "en": plural("See game", "See all %lld games"),
            "de": plural("Spiel ansehen", "Alle %lld Spiele ansehen"),
            "ja": unit("全%lld局を見る"),
            "ms": plural(other="Lihat semua %lld permainan"),
            "id": plural(other="Lihat semua %lld permainan"),
        }},
    }}
    report = validate(plurals, all_locales=True, structure_baseline=plurals)
    assert report["passed"] and len(report["preservedBaselineStructures"]) == 1
    bad_plural = clone(plurals)
    bad_plural["strings"]["See all %lld games"]["localizations"]["de"]["variations"]["plural"].pop("one")
    assert not validate(bad_plural, all_locales=True, structure_baseline=plurals)["passed"]
    bad_plural = clone(plurals)
    bad_plural["strings"]["See all %lld games"]["localizations"]["ms"]["variations"]["plural"]["one"] = unit("%lld permainan")
    assert not validate(bad_plural, all_locales=True, structure_baseline=plurals)["passed"]
    bad_plural = clone(plurals)
    bad_plural["strings"]["See all %lld games"]["localizations"]["de"] = unit("Alle %lld Spiele ansehen")
    assert not validate(bad_plural, all_locales=True, structure_baseline=plurals)["passed"]
    bad_plural = clone(plurals)
    bad_plural["strings"]["See all %lld games"]["localizations"]["ja"] = unit("全局を見る")
    assert not validate(bad_plural, all_locales=True, structure_baseline=plurals)["passed"]

    style = clone(complete)
    style["strings"]["Count %lld"]["localizations"]["de"] = unit("Anzahl %lld ")
    report = validate(style, all_locales=True, structure_baseline=style)
    assert report["passed"] and report["preservedBaselineFormatting"]
    changed_style = clone(style)
    changed_style["strings"]["Count %lld"]["localizations"]["de"] = unit("Gesamt %lld  ")
    assert not validate(changed_style, all_locales=True, structure_baseline=style)["passed"]
    changed_source_style = clone(complete)
    changed_source_style["strings"]["Count %lld"]["localizations"]["en"] = unit("Count %lld…")
    report = validate(changed_source_style, all_locales=True, structure_baseline=complete)
    assert not report["passed"] and not report["preservedBaselineFormatting"]

    dormant = clone(complete)
    dormant["strings"]["Count %lld"]["extractionState"] = "stale"
    report = validate(dormant, baseline=complete)
    assert report["passed"] and report["retainedStaleLocaleObjects"] == 2
    dormant["strings"]["Count %lld"]["localizations"]["ms"] = unit("Changed dormant text")
    assert not validate(dormant, baseline=complete)["passed"]
    separators = {"sourceLanguage": "en", "version": "1.0", "strings": {
        "–": {}, "—": {"shouldTranslate": False, "localizations": {
            "ms": unit("—"), "id": unit("—"),
        }},
    }}
    assert validate(separators)["passed"]
    separators["strings"]["—"]["localizations"]["ms"] = unit("Some words")
    assert not validate(separators)["passed"]

    substitution = {"sourceLanguage": "en", "version": "1.0", "strings": {
        "Count %lld": {"localizations": {
            locale: {"stringUnit": {"state": "translated", "value": "Count %#@n@"},
                     "substitutions": {"n": {"argNum": 1, "formatSpecifier": "lld",
                                             **plural("%arg item", "%arg items")}}}
            for locale in ("en", "de")
        }},
    }}
    assert validate(substitution, all_locales=True, structure_baseline=substitution)["passed"]
    changed_substitution = clone(substitution)
    changed_substitution["strings"]["Count %lld"]["localizations"]["de"]["substitutions"]["n"]["argNum"] = 2
    assert not validate(changed_substitution, all_locales=True, structure_baseline=substitution)["passed"]
    flattened_substitutions = clone(substitution)
    for locale in flattened_substitutions["strings"]["Count %lld"]["localizations"]:
        flattened_substitutions["strings"]["Count %lld"]["localizations"][locale] = unit("Count %lld")
    report = validate(flattened_substitutions, all_locales=True, structure_baseline=substitution)
    assert not report["passed"] and any("baseline substitution" in e for e in report["errors"])
    nested_plural = clone(plurals)
    nested_plural["strings"]["See all %lld games"]["localizations"]["de"]["variations"]["plural"]["one"] = plural("Spiel ansehen", "%lld Spiele ansehen")
    report = validate(nested_plural, all_locales=True, structure_baseline=plurals)
    assert not report["passed"] and any("nested plural" in e for e in report["errors"])
    multiple_arguments = {"sourceLanguage": "en", "version": "1.0", "strings": {
        "%lld games against %@": {"localizations": {
            "en": plural("Game against %2$@", "%lld games against %@"),
            "de": plural("Spiel gegen %2$@", "%lld Spiele gegen %@"),
        }},
    }}
    assert validate(multiple_arguments, all_locales=True, structure_baseline=multiple_arguments)["passed"]
    dropped_object = clone(multiple_arguments)
    for locale in ("en", "de"):
        dropped_object["strings"]["%lld games against %@"]["localizations"][locale]["variations"]["plural"]["one"] = unit("Game" if locale == "en" else "Spiel")
    assert not validate(dropped_object, all_locales=True, structure_baseline=multiple_arguments)["passed"]
    numeric_arguments = {"sourceLanguage": "en", "version": "1.0", "strings": {
        "%.1f points in %lld seconds": {"localizations": {
            "en": plural("%.1f point in %lld seconds", "%.1f points in %lld seconds"),
            "de": plural("%.1f Punkt in %lld Sekunden", "%.1f Punkte in %lld Sekunden"),
        }},
    }}
    assert validate(numeric_arguments, all_locales=True, structure_baseline=numeric_arguments)["passed"]
    dropped_duration = clone(numeric_arguments)
    for locale in ("en", "de"):
        dropped_duration["strings"]["%.1f points in %lld seconds"]["localizations"][locale]["variations"]["plural"]["one"] = unit("%.1f point" if locale == "en" else "%.1f Punkt")
    assert not validate(dropped_duration, all_locales=True, structure_baseline=numeric_arguments)["passed"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=HERE.parents[1] / "Surround/Localizable.xcstrings")
    parser.add_argument("--baseline", type=Path, help="Optional inherited catalog to preserve exactly")
    parser.add_argument("--all-locales", action="store_true", help="Check source English and every catalog/project locale, rather than only ms/id")
    parser.add_argument("--project", type=Path, help="Project whose knownRegions augment --all-locales (defaults to this repository's project)")
    parser.add_argument("--structure-baseline", type=Path, help="Prior catalog for locale plural shapes and preserved formatting differences; does not require identical wording")
    parser.add_argument("--expected-inventory", "--inventory", dest="inventory", type=Path, help="Optional exact key and stale/neutral inventory")
    parser.add_argument("--stringsdata-root", type=Path, help="Optional final compiler extraction tree")
    parser.add_argument("--output", type=Path, help="Optional JSON report path")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    self_test()
    if args.self_test:
        print("Validator self-tests passed")
        return 0
    project = args.project or HERE.parents[1] / "Surround.xcodeproj/project.pbxproj"
    try:
        compiler = compiler_inventory(args.stringsdata_root, args.catalog.parent) if args.stringsdata_root else None
        if args.all_locales and not project.is_file():
            raise CatalogError(f"Project not found for supported-region audit: {project}")
        report = validate(read_json(args.catalog), read_json(args.baseline) if args.baseline else None,
                          read_json(args.inventory) if args.inventory else None, compiler,
                          args.all_locales,
                          read_json(args.structure_baseline) if args.structure_baseline else None,
                          project if args.all_locales else None)
    except (CatalogError, json.JSONDecodeError, KeyError, TypeError, AttributeError, OSError) as error:
        report = {"passed": False, "errors": [str(error)], "warnings": []}
    if args.catalog.is_file():
        report["catalogSHA256"] = hashlib.sha256(args.catalog.read_bytes()).hexdigest()
    if args.baseline and args.baseline.is_file():
        report["baselineSHA256"] = hashlib.sha256(args.baseline.read_bytes()).hexdigest()
    if args.structure_baseline and args.structure_baseline.is_file():
        report["structureBaselineSHA256"] = hashlib.sha256(args.structure_baseline.read_bytes()).hexdigest()
    if args.all_locales:
        report["project"] = str(project)
    if args.output:
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k not in ("identicalTargetEntries",)}, ensure_ascii=False, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
