morse.v1.json is a versioned snapshot of the released v0.4.20 training data for
new native clients. It does not replace the existing Electron data at runtime.
Sources: ui/src/constants.js, Reception.jsx, utils/q_codes.js, morseProvider.js.
Standard alphabet maps and the existing Paloma override for zero are separate.
Keep character/lesson meaning in shared data; do not independently edit copies
inside SwiftUI and QML. Changes require an explicit catalog version and tests.
