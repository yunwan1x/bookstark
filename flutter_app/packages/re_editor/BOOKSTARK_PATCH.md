# Local lifecycle fix on upstream re_editor 0.10.0

Upstream: https://github.com/reqable/re-editor ; original MIT LICENSE retained.
Only lib/src/_code_editable.dart is changed. Cancel and own the 100ms mobile cursor-show timer and 50ms autocomplete timer on replacement/disposal, and guard the autocomplete callback by mounted. This fixes source-input then immediate page disposal leaving timers that can notify a disposed cursor controller. The app source-editor widget test deliberately exits immediately after delta input/undo/redo; it must pass without pumping pending timers away.

All other library sources are byte-identical to the pinned published package. The global pub cache is unchanged. Vendored dependency sources are excluded from application-style linting like hosted dependencies; application widgets and the fast-disposal regression remain analyzed and tested.
