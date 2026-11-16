#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/monitorcontrol-input-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
swiftc MonitorControl/Model/DDCInputSource.swift MonitorControl/Support/LGUSBInputControl.swift Tests/InputSourceTests.swift -o "$test_dir/protocol-tests"
"$test_dir/protocol-tests"
swiftc MonitorControl/Model/DDCInputSource.swift MonitorControl/Enums/PrefKey.swift MonitorControl/Support/InputSourceMenu.swift Tests/InputSourceMenuTests.swift -o "$test_dir/menu-tests"
"$test_dir/menu-tests"
swiftc MonitorControl/Automation/AutomationConfig.swift MonitorControl/Automation/TriggerPolicy.swift MonitorControl/Automation/InputCommandExecutor.swift MonitorControl/Automation/KeyboardIdentity.swift MonitorControl/Model/DDCInputSource.swift Tests/CompanionPolicyTests.swift -o "$test_dir/companion-tests"
"$test_dir/companion-tests"
swiftc -import-objc-header MonitorControl/Support/Bridging-Header.h \
  -F /System/Library/PrivateFrameworks -framework CoreDisplay -framework IOBluetooth -framework AppKit \
  MonitorControl/Automation/AutomationConfig.swift MonitorControl/Automation/TriggerPolicy.swift \
  MonitorControl/Automation/InputCommandExecutor.swift MonitorControl/Automation/KeyboardIdentity.swift \
  MonitorControl/Automation/SystemSources.swift MonitorControl/Automation/AutomationController.swift \
  MonitorControl/Model/DDCInputSource.swift MonitorControl/Support/Arm64DDC.swift MonitorControl/Support/LGUSBInputControl.swift \
  Tests/AutomationControllerTests.swift -o "$test_dir/controller-tests"
"$test_dir/controller-tests"
