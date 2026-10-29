// Copies files the iOS keyboard bundles from their source of truth into ios-app.
// SwiftPM resources must live inside the target folder. tests/ios-app.test.js fails on drift.
import { copyFileSync } from 'node:fs';

const pairs = [
  ['ios/keyboard-prompt.txt', 'ios-app/ProtlyCore/Sources/ProtlyCore/Resources/keyboard-prompt.txt'],
];

for (const [from, to] of pairs) {
  copyFileSync(new URL(`../${from}`, import.meta.url), new URL(`../${to}`, import.meta.url));
  console.log(`synced ${to}`);
}
