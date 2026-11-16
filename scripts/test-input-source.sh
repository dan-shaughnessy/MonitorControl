#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/monitorcontrol-input-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
swiftc MonitorControl/Model/DDCInputSource.swift MonitorControl/Support/LGUSBInputControl.swift Tests/InputSourceTests.swift -o "$test_dir/protocol-tests"
"$test_dir/protocol-tests"
swiftc MonitorControl/Model/DDCInputSource.swift MonitorControl/Enums/PrefKey.swift MonitorControl/Support/InputSourceMenu.swift Tests/InputSourceMenuTests.swift -o "$test_dir/menu-tests"
"$test_dir/menu-tests"
swiftc Companion/Sources/CompanionConfig.swift Companion/Sources/TriggerPolicy.swift Companion/Sources/InputCommandExecutor.swift Companion/Sources/KeyboardIdentity.swift MonitorControl/Model/DDCInputSource.swift Tests/CompanionPolicyTests.swift -o "$test_dir/companion-tests"
"$test_dir/companion-tests"
