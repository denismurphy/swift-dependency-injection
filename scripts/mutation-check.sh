#!/usr/bin/env bash
# Targeted mutation checks for the container's behavioural guarantees.
#
# Each mutant disables exactly one behaviour and names the test that must fail
# because of it. A mutant is KILLED only if that specific test reports an
# issue. A mutant that survives, does not apply (the code moved), or does not
# compile is reported as a failure of this script, never silently skipped.
#
# Mutations are applied to a scratch copy of the package. The working tree is
# never modified.
#
# Usage: scripts/mutation-check.sh            # run all mutants
#        scripts/mutation-check.sh M03 M07    # run selected mutants
set -euo pipefail

cd "$(dirname "$0")/.."
root=$PWD

work=$(mktemp -d "${TMPDIR:-/tmp}/di-mutation.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM
rsync -a --exclude .build --exclude .git --exclude .swiftpm ./ "$work/"

selected=("$@")
killed=0
failed=0

# mutant ID FILE PERL_SUBSTITUTION EXPECTED_TEST
mutant() {
    local id=$1 file=$2 subst=$3 expected=$4
    if [[ ${#selected[@]} -gt 0 ]] && [[ ! " ${selected[*]} " == *" $id "* ]]; then
        return
    fi

    cp "$root/$file" "$work/$file"
    perl -0pi -e "$subst" "$work/$file"
    if cmp -s "$work/$file" "$root/$file"; then
        printf '%-4s ERROR    mutation did not apply to %s (code moved?)\n' "$id" "$file"
        failed=$((failed + 1))
        return
    fi

    local output
    output=$(cd "$work" && swift test 2>&1 || true)
    cp "$root/$file" "$work/$file"

    if ! grep -q "Test run" <<<"$output"; then
        printf '%-4s ERROR    mutant did not compile or the run crashed\n' "$id"
        failed=$((failed + 1))
    elif grep -Eq "Test ${expected}\(\) recorded an issue" <<<"$output"; then
        printf '%-4s KILLED   %s\n' "$id" "$expected"
        killed=$((killed + 1))
    else
        printf '%-4s SURVIVED expected %s to fail\n' "$id" "$expected"
        failed=$((failed + 1))
    fi
}

container=Sources/DependencyInjection/Container.swift
scoping=Sources/DependencyInjection/Container+Scoping.swift
assembly=Sources/DependencyInjection/Assembly.swift
registration=Sources/DependencyInjection/Registration.swift
inject=Sources/DependencyInjection/Inject.swift
key=Sources/DependencyInjection/DependencyKey.swift
environment=Sources/DependencyInjectionSwiftUI/Container+Environment.swift

# --- Scopes ----------------------------------------------------------------------
mutant M01 "$container" 's/state\.singletons\[key\] = value/_ = value/' \
    singletonBuildsOnceAndIsShared
mutant M02 "$container" 's/(while this one waited\.\n\s*)if let cached = owner\.cachedSingleton\(for: key\) \{ return cached \}/$1/' \
    concurrentFirstResolutionBuildsTheSingletonOnce
mutant M03 "$container" 's/owner\.constructionLock\.lock\(\)\n\s*defer \{ owner\.constructionLock\.unlock\(\) \}//' \
    concurrentFirstResolutionBuildsTheSingletonOnce
mutant M04 "$assembly" 's/Registration\(key: concrete, scope: scope,/Registration(key: concrete, scope: .transient,/' \
    protocolAndConcreteSingletonResolveToOneInstance

# --- Keys ------------------------------------------------------------------------
mutant M05 "$key" 's/ && lhs\.name == rhs\.name//; s/hasher\.combine\(name\)//' \
    namedBindingsAreSeparateRegistrations

# --- Registration ----------------------------------------------------------------
mutant M06 "$container" 's/\n\s*state\.singletons\.removeValue\(forKey: registration\.key\)//' \
    reregisteringReplacesTheFactoryAndDiscardsTheCachedSingleton
mutant M07 "$container" 's/state\.entries\[key\]\?\.id == entry\.id/true/' \
    registrationReplacedDuringConstructionIsNotOverwrittenByTheStaleInstance
mutant M08 "$container" 's/(public func reset\(\) \{\n\s*state\.withLock \{ state in\n)\s*state\.entries\.removeAll\(\)/$1/' \
    resetRemovesRegistrationsAndSingletons

# --- Errors ----------------------------------------------------------------------
mutant M09 "$registration" 's/throw \.factoryFailed\(key, underlying: error\)/throw .notRegistered(key)/' \
    throwingFactoryIsReportedAgainstItsKey
mutant M10 "$registration" 's/(catch let error as DependencyError \{\n\s*)throw error/$1throw .factoryFailed(key, underlying: error)/' \
    missingNestedDependencyIsNotWrappedAsFactoryFailure
mutant M11 "$container" 's/throw \.typeMismatch\(key: key, actual: Swift\.type\(of: value\)\)/throw .notRegistered(key)/' \
    aliasForAProtocolTheTypeDoesNotAdoptReportsTypeMismatch
mutant M12 "$container" 's/return try resolve\(type, name: name\)\n\s*\}\n\n\s*func find/return try? resolve(type, name: name)\n    }\n\n    func find/' \
    resolveIfRegisteredReturnsNilOnlyForTheRequestedKey
mutant M13 "$container" 's/if path\.contains\(registration\.key\)/if path.count > 8 \&\& path.contains(registration.key)/' \
    cycleThroughFactoriesThrowsWithThePath

# --- Resolution context ----------------------------------------------------------
mutant M14 "$container" 's/build\(entry\.registration, resolver: Resolver\(container: self\)\)/build(entry.registration, resolver: Resolver(container: owner))/' \
    transientRegistrationInTheParentSeesTheOverriddenDependency
mutant M15 "$container" 's/build\(entry\.registration, resolver: Resolver\(container: owner\)\)/build(entry.registration, resolver: Resolver(container: self))/' \
    singletonInTheParentIsNotBuiltAgainstAnOverride

# --- Scoped overrides ------------------------------------------------------------
mutant M16 "$scoping" 's/Container\(parent: current\)/Container(parent: nil)/' \
    overrideShadowsTheParentAndFallsThroughForEverythingElse
mutant M17 "$scoping" 's/try await \$current\.withValue\(child,/try await \$current.withValue(current,/' \
    concurrentOverridesDoNotSeeEachOther

# --- Property wrappers -----------------------------------------------------------
mutant M18 "$inject" 's/resolve\(Value\.self, name: key\.name\)/resolve(Value.self, name: nil)/' \
    injectResolvesFromTheCurrentContainerOnEveryRead
mutant M19 "$inject" 's/return try Container\.current\.resolveIfRegistered\(Value\.self, name: key\.name\)/return nil/' \
    injectIfRegisteredReturnsTheValueWhenPresent

# --- SwiftUI ---------------------------------------------------------------------
mutant M20 "$environment" 's/environment\(\\\.container, container\)/environment(\\.container, .shared)/' \
    dependencyResolvesFromTheContainerInTheEnvironment
mutant M21 "$environment" 's/return try container\.resolve\(Value\.self, name: name\)/return try Container.shared.resolve(Value.self, name: name)/' \
    dependencyResolvesFromTheContainerInTheEnvironment

echo
echo "killed: $killed, not killed: $failed"
[[ $failed -eq 0 ]]
