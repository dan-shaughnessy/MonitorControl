#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d /tmp/desk-audio-tests.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
swiftc Vendor/AudioSync/Sources/AudioSync/{DeskPeer,DeskHandoff,DeskRouting}.swift Tests/DeskAudioTests.swift -o "$scratch/tests"
"$scratch/tests"
