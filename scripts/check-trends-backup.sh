#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi
CHECK_DIR="$(mktemp -d /tmp/afu-data-checks.XXXXXX)"
cd "$PROJECT_ROOT"
xcrun --sdk macosx swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -target "$(uname -m)-apple-macosx15.6" \
    体脂秤/Models/Models.swift 体脂秤/Models/ComparisonModels.swift \
    体脂秤/Services/AppLanguage.swift \
    体脂秤/Services/UserProfile.swift \
    体脂秤/Services/BodyAlgorithm.swift 体脂秤/Models/MeasurementBackup.swift \
    体脂秤/Models/Repeatability.swift \
    体脂秤/Models/AssistedWeighing.swift \
    体脂秤/Models/MeasurementTrends.swift tests/TrendsBackupChecks.swift \
    -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks"
