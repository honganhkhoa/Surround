#!/usr/bin/env python3
"""Offline ms/id catalog validation, preserving the inherited Messages baseline.

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


def shape(node, label, failures, is_substitution=False):
    if not isinstance(node, dict):
        failures.append(f"{label}: localization must be an object")
        return
    permitted = {"variations", "stringUnit"} | ({"argNum", "formatSpecifier"} if is_substitution else {"substitutions"})
    unexpected = set(node) - permitted
    if unexpected:
        failures.append(f"{label}: unknown localization fields {sorted(unexpected)}")
    has_unit = "stringUnit" in node
    has_variations = "variations" in node
    if has_unit == has_variations:
        failures.append(f"{label}: must have exactly one stringUnit or variations")
    if has_unit:
        unit = node["stringUnit"]
        if not isinstance(unit, dict) or set(unit) != {"state", "value"}:
            failures.append(f"{label}: stringUnit requires state and value")
        elif unit["state"] != "translated" or not isinstance(unit["value"], str) or not unit["value"]:
            failures.append(f"{label}: nonempty translated stringUnit required")
    if has_variations:
        axes = node["variations"]
        if not isinstance(axes, dict) or set(axes) != {"plural"}:
            failures.append(f"{label}: only plural variation axis supported by this catalog")
        elif set(axes["plural"]) != {"other"}:
            failures.append(f"{label}: ms/id plural categories must contain only other")
        else:
            shape(axes["plural"]["other"], label + "/plural/other", failures)
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


def validate(catalog, baseline=None, inventory=None, compiler=None):
    failures, warnings = [], []
    strings = catalog.get("strings", {})
    if not isinstance(strings, dict) or catalog.get("sourceLanguage") != "en" or catalog.get("version") != "1.0":
        return {"passed": False, "errors": ["Invalid strings, sourceLanguage or catalog version"], "warnings": []}
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
    neutral = set(inventory["explicitNeutralKeys"]) if inventory else actual_neutral
    if inventory and actual_neutral != neutral:
        failures.append(f"Explicit neutral key mismatch: {sorted(actual_neutral)!r}")
    coverage = {locale: 0 for locale in TARGET_LOCALES}
    plural_counts = {locale: 0 for locale in TARGET_LOCALES}
    substitution_counts = {locale: 0 for locale in TARGET_LOCALES}
    leaf_counts = {locale: 0 for locale in TARGET_LOCALES}
    for key, entry in strings.items():
        if key in stale:
            for locale in TARGET_LOCALES:
                if locale in entry.get("localizations", {}):
                    failures.append(f"Stale key newly localized: {key!r} [{locale}]")
            continue
        if key in neutral:
            if any(locale in entry.get("localizations", {}) for locale in TARGET_LOCALES):
                failures.append(f"Explicit neutral key localized: {key!r}")
            continue
        source = entry.get("localizations", {}).get("en", {})
        source_subs = source.get("substitutions", {})
        try:
            source_contract = arguments(key)[:2]
        except CatalogError as error:
            failures.append(f"Source key {key!r}: {error}")
            continue
        for locale in TARGET_LOCALES:
            label = f"{key!r} [{locale}]"
            localization = entry.get("localizations", {}).get(locale)
            if localization is None:
                failures.append(f"Missing localization: {label}")
                continue
            coverage[locale] += 1
            shape(localization, label, failures)
            subs = localization.get("substitutions", {})
            if "variations" in source and "variations" not in localization:
                failures.append(f"{label}: source plural structure not preserved")
            if bool(source_subs) != bool(subs) or set(source_subs) != set(subs):
                failures.append(f"{label}: source substitution structure/names not preserved")
            if "variations" in localization:
                plural_counts[locale] += 1
            if subs:
                substitution_counts[locale] += len(subs)
            for name, sub in subs.items():
                sublabel = f"{label}/substitution/{name}"
                shape(sub, sublabel, failures, is_substitution=True)
                source_sub = source_subs.get(name, {})
                if any(sub.get(field) != source_sub.get(field) for field in ("argNum", "formatSpecifier")):
                    failures.append(f"{sublabel}: source argument number/type changed")
                if "argNum" not in sub or "formatSpecifier" not in sub:
                    continue
                for path, unit in leaves(sub):
                    try:
                        contract, escaped, refs = arguments(unit["value"], substitution_arg=(sub["argNum"], sub["formatSpecifier"]))
                        if contract != collections.Counter({(sub["argNum"], sub["formatSpecifier"]): 1}) or escaped or refs:
                            failures.append(f"{sublabel}{path}: %arg contract changed")
                        if formatting(unit["value"]) != formatting(source_text(source_sub, "%arg")):
                            failures.append(f"{sublabel}{path}: whitespace/Markdown/ellipsis/bullet formatting changed")
                    except (CatalogError, KeyError, TypeError) as error:
                        failures.append(f"{sublabel}{path}: {error}")
                    leaf_counts[locale] += 1
            for path, unit in leaves(localization):
                try:
                    contract, escaped, refs = arguments(unit["value"], subs)
                    if (contract, escaped) != source_contract:
                        failures.append(f"{label}{path}: format contract changed: {dict(contract)!r} != {dict(source_contract[0])!r}")
                    if subs and refs != collections.Counter({name: 1 for name in subs}):
                        failures.append(f"{label}{path}: substitution references missing/duplicated")
                    source_formatting = formatting(source_text(source, key))
                    target_formatting = formatting(unit["value"])
                    changed_formatting = [field for field in source_formatting if source_formatting[field] != target_formatting[field]]
                    if changed_formatting:
                        failures.append(f"{label}{path}: formatting changed: {', '.join(changed_formatting)}")
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
    report = {
        "passed": not failures, "totalKeys": len(strings), "activeKeys": len(strings)-len(stale),
        "explicitNeutralKeys": sorted(neutral), "staleKeys": sorted(stale), "coverage": coverage,
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=HERE.parents[1] / "Surround/Localizable.xcstrings")
    parser.add_argument("--baseline", type=Path, help="Optional inherited catalog to preserve exactly")
    parser.add_argument("--expected-inventory", "--inventory", dest="inventory", type=Path, help="Optional exact key and stale/neutral inventory")
    parser.add_argument("--stringsdata-root", type=Path, help="Optional final compiler extraction tree")
    parser.add_argument("--output", type=Path, help="Optional JSON report path")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    self_test()
    if args.self_test:
        print("Validator self-tests passed")
        return 0
    try:
        compiler = compiler_inventory(args.stringsdata_root, args.catalog.parent) if args.stringsdata_root else None
        report = validate(read_json(args.catalog), read_json(args.baseline) if args.baseline else None,
                          read_json(args.inventory) if args.inventory else None, compiler)
    except (CatalogError, json.JSONDecodeError, KeyError, TypeError, AttributeError) as error:
        report = {"passed": False, "errors": [str(error)], "warnings": []}
    report["catalogSHA256"] = hashlib.sha256(args.catalog.read_bytes()).hexdigest()
    if args.baseline:
        report["baselineSHA256"] = hashlib.sha256(args.baseline.read_bytes()).hexdigest()
    if args.output:
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k not in ("identicalTargetEntries",)}, ensure_ascii=False, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
