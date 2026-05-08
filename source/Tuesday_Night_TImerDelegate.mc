import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! Input handler: maps physical watch buttons to race control and stopwatch actions.
//!
//! KEY_ENTER (center button):
//!   - In sync window (long-hold): show green overlay and snap-to-horn on release
//!   - While running (short press/release): cycle stopwatch (start/pause/reset)
//!
//! KEY_DOWN (down button):
//!   - Double-press while running: emergency exit (race ends)
//!
//! CIQ Challenge: SDK 6.2.x only exposes KeyEvent.DOWN / UP / ACTION, no PRESS_TYPE_HOLD.
//! To detect a sustained hold for sync mode, we use a 700ms timer from KEY_DOWN.
//!
//! CIQ SDK Quirk: onSelect() fires between physical KEY_ENTER down and up on the same gesture,
//! in addition to the onKeyReleased callback. We must suppress duplicate onSelect calls to avoid
//! double-cycling the stopwatch (once in onKeyReleased, once in onSelect).
//! Solution: set _suppressSelectUntilMs and check elapsed time in onSelect().
class Tuesday_Night_TimerDelegate extends WatchUi.BehaviorDelegate {

    private var _view as Tuesday_Night_TimerView;

    // --- Sync (hold KEY_ENTER in sync window) ---
    private var _holdTimer          as Timer.Timer? = null;
    private var _syncPending        as Boolean      = false;
    private var _syncActive         as Boolean      = false;
    private var _selectDown         as Boolean      = false;

    // --- Stop confirm (double-press KEY_DOWN while running) ---
    private var _lastDownPressMs    as Number       = 0;
    private const DOUBLE_TAP_MS     = 400;

    //! Stopwatch: physical KEY_ENTER outside sync — only short release cycles; long hold ignored.
    private var _swHoldTimer        as Timer.Timer? = null;
    private var _swEnterDown        as Boolean      = false;
    private var _swLongPress        as Boolean      = false;
    private var _suppressSelectUntilMs as Number    = 0;
    //! True after a short KEY_ENTER release already cycled the stopwatch — consume duplicate InputDelegate.onKey().
    private var _swReleaseDidCycle  as Boolean      = false;

    private const HOLD_MS = 700;
    //! Block delayed onSelect after the same physical click (ms from System.getTimer()).
    private const SW_SUPPRESS_SELECT_MS = 450;

    public function initialize(view as Tuesday_Night_TimerView) {
        WatchUi.BehaviorDelegate.initialize();
        _view = view;
    }

    // -------------------------------------------------------------------------
    // Low-level keys (physical)
    // -------------------------------------------------------------------------

    public function onKeyPressed(keyEvent as WatchUi.KeyEvent) as Boolean {
        if (_view.hasActiveSession()) {
            return true;  // swallow all low-level key events during racing
        }
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_ENTER) {
            if (_view.isRunning() and _view.isInSyncWindow()) {
                _resetSwEnterTracking();
                _view.recordSyncPressAnchor();
                _selectDown   = true;
                _syncPending  = true;
                if (_holdTimer != null) {
                    _holdTimer.stop();
                    _holdTimer = null;
                }
                _holdTimer = new Timer.Timer();
                _holdTimer.start(method(:onHoldThreshold), HOLD_MS, false);
                return true;
            } else if (_view.isRunning()) {
                _resetSwEnterTracking();
                _swReleaseDidCycle = false;
                _swEnterDown = true;
                _swLongPress = false;
                //! Block spurious onSelect that arrives after this press (same gesture as release cycle).
                _suppressSelectUntilMs = System.getTimer() + SW_SUPPRESS_SELECT_MS;
                _swHoldTimer = new Timer.Timer();
                _swHoldTimer.start(method(:onSwEnterLongThreshold), HOLD_MS, false);
                return true;
            }
        } else if (key == WatchUi.KEY_DOWN) {
            if (_view.isRunning() and !(_syncActive or _syncPending)) {
                var now = System.getTimer();
                if (now - _lastDownPressMs <= DOUBLE_TAP_MS) {
                    _lastDownPressMs = 0;
                    _view.exitAppNow();
                } else {
                    _lastDownPressMs = now;
                }
                return true;
            }
        }
        return false;
    }

    public function onKeyReleased(keyEvent as WatchUi.KeyEvent) as Boolean {
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_ENTER) {
            if (_selectDown) {
                _selectDown = false;
                if (_syncActive) {
                    _cancelHoldTimer();
                    _syncActive = false;
                    _view.finishSyncHoldRelease();
                    return true;
                }
                if (_syncPending) {
                    _cancelHoldTimer();
                    _syncPending = false;
                    //! Short press in sync window: still cycle stopwatch (long hold enters green sync).
                    if (_view.isRunning()) {
                        _suppressSelectUntilMs = System.getTimer() + SW_SUPPRESS_SELECT_MS;
                        _view.cycleStopwatch();
                    }
                    return true;
                }
            }
            if (_swEnterDown) {
                _cancelSwHoldTimer();
                _swEnterDown = false;
                var wasShort = !_swLongPress;
                _swLongPress = false;
                _suppressSelectUntilMs = System.getTimer() + SW_SUPPRESS_SELECT_MS;
                if (wasShort and _view.isRunning()) {
                    _view.cycleStopwatch();
                    _swReleaseDidCycle = true;
                }
                return true;
            }
            return false;
        }
        if (key == WatchUi.KEY_DOWN) {
            return false;
        }
        return false;
    }

    //! Garmin calls this after a full press+release; it can stack with onSelect — consume when release already cycled SW.
    public function onKey(keyEvent as WatchUi.KeyEvent) as Boolean {
        if (keyEvent.getKey() != WatchUi.KEY_ENTER) {
            return false;
        }
        if (!_view.isRunning() or _view.isInSyncWindow()) {
            return false;
        }
        if (_swReleaseDidCycle) {
            _swReleaseDidCycle = false;
            return true;
        }
        return false;
    }

    //! Fires while KEY_ENTER is still held; turns on green overlay if still valid.
    public function onHoldThreshold() as Void {
        _holdTimer = null;
        if (_syncPending and _selectDown and _view.isRunning() and _view.isInSyncWindow()) {
            _syncPending = false;
            if (_view.enterSyncMode()) {
                _syncActive = true;
            }
        } else {
            _syncPending = false;
        }
    }

    //! Fires while KEY_ENTER is held (running, outside sync): treat as long press — ignore stopwatch on release.
    public function onSwEnterLongThreshold() as Void {
        _swHoldTimer = null;
        if (_swEnterDown) {
            _swLongPress = true;
        }
    }

    // -------------------------------------------------------------------------
    // Behaviors
    // -------------------------------------------------------------------------

    public function onSelect() as Boolean {
        if (_view.hasActiveSession()) {
            _showFinishRaceConfirmation();
            return true;
        }
        if (_syncActive) {
            _syncActive = false;
            _view.finishSyncHoldRelease();
            return true;
        }
        if (_syncPending) {
            return true;
        }
        if (_view.isRunning()) {
            //! Physical KEY_ENTER: onSelect often fires between down/up — do not double-cycle with onKeyReleased.
            if (_swEnterDown) {
                return true;
            }
            if (System.getTimer() < _suppressSelectUntilMs) {
                return true;
            }
            _view.cycleStopwatch();
            return true;
        }
        _view.onPrimaryAction();
        return true;
    }

    public function onNextPage() as Boolean {
        if (_view.hasActiveSession()) {
            _view.cycleRacingPage();
            return true;
        }
        if (_syncActive or _syncPending) {
            var wasActive = _syncActive;
            _cancelHoldTimer();
            _resetSwEnterTracking();
            _syncPending = false;
            _syncActive  = false;
            _selectDown  = false;
            if (wasActive) {
                _view.cancelSyncMode();
            }
            return true;
        }
        return false;
    }

    public function onBack() as Boolean {
        if (_syncActive or _syncPending) {
            var wasActive = _syncActive;
            _cancelHoldTimer();
            _resetSwEnterTracking();
            _syncPending = false;
            _syncActive  = false;
            _selectDown  = false;
            if (wasActive) {
                _view.cancelSyncMode();
            }
            return true;
        }
        _resetSwEnterTracking();
        if (_view.hasActiveSession()) {
            _showFinishRaceConfirmation();
            return true;
        }
        return _view.handleBack();
    }

    public function onMenu() as Boolean {
        _cancelHoldTimer();
        _resetSwEnterTracking();
        _syncPending = false;
        _syncActive  = false;
        _selectDown  = false;
        _view.handleMenu();
        return true;
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    private function _cancelHoldTimer() as Void {
        if (_holdTimer != null) {
            _holdTimer.stop();
            _holdTimer = null;
        }
    }

    private function _cancelSwHoldTimer() as Void {
        if (_swHoldTimer != null) {
            _swHoldTimer.stop();
            _swHoldTimer = null;
        }
    }

    private function _resetSwEnterTracking() as Void {
        _cancelSwHoldTimer();
        _swEnterDown = false;
        _swLongPress = false;
        _swReleaseDidCycle = false;
    }

    private function _showStopConfirmation() as Void {
        var menu = new WatchUi.Menu2({:title => "Exit App?"});
        menu.addItem(new WatchUi.MenuItem("No - Continue", null, :no, null));
        menu.addItem(new WatchUi.MenuItem("Yes - Exit", null, :yes, null));
        WatchUi.pushView(menu, new Tuesday_Night_TimerConfirmDelegate(_view), WatchUi.SLIDE_UP);
    }

    private function _showFinishRaceConfirmation() as Void {
        var menu = new WatchUi.Menu2({:title => "Finish Race?"});
        menu.addItem(new WatchUi.MenuItem("Save & Exit",  null, :save,    null));
        menu.addItem(new WatchUi.MenuItem("Keep Racing",  null, :keep,    null));
        menu.addItem(new WatchUi.MenuItem("Discard",      null, :discard, null));
        WatchUi.pushView(menu, new Tuesday_Night_TimerSaveDelegate(_view), WatchUi.SLIDE_UP);
    }

}
