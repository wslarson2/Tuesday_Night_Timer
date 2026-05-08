import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;

//! Race countdown engine for sailing race timing (ISAF Rule 26).
//! ISAF Rule 26 defines a warning sequence:
//!   5 minutes: first warning signal (horn)
//!   4 minutes: second warning signal
//!   1 minute: final warning signal
//!   0 seconds: start signal (gun)
//!
//! This class owns all timing state, haptic feedback, and the "sync" feature (helmsman
//! hears the physical horn and presses during a 10-second window to snap the watch to that horn).
//! The View handles drawing; the Delegate handles input.
class RaceEngine {

    static const STATE_READY    = 0;
    static const STATE_RUNNING  = 1;
    static const STATE_FINISHED = 2;

    private var _state             as Number  = STATE_READY;
    private var _startTimeSec      as Number  = 300;  // Default 5 minutes
    private var _raceElapsedSec    as Number  = 0;    // When not running, mirrors wall-clock on re-entry
    private var _raceAnchorMs      as Number  = 0;    // System.getTimer() anchor for wall-clock sync
    private var _lastFiredElapsedSec as Number = 0;   // Last second we fired haptics for; drives replay on app re-entry

    //! Sync mode: helmsman presses during 10-second window before horn to snap to that horn.
    private var _syncMode          as Boolean = false;
    private var _syncPressElapsedSec as Number = 0;   // What the race elapsed time was when key went down

    //! Major horn minutes (5–4–1) and final countdown ticks (10–5–3–2–1) before each horn and before start gun.
    private var _hornMinutes       as Array<Number> = [5, 4, 1] as Array<Number>;
    private var _finalCountdownTicks as Array<Number> = [10, 5, 3, 2, 1] as Array<Number>;

    //! Callback invoked when state changes or needs redraw (passed in by View/Delegate).
    private var _onStateChange     as Method?;

    function initialize(onStateChange as Method?) {
        _onStateChange = onStateChange;
    }

    //! Return current race state.
    public function getState() as Number {
        return _state;
    }

    //! Start time (in seconds) — typically 300 (5 min).
    public function getStartTimeSec() as Number {
        return _startTimeSec;
    }

    public function setStartTimeSec(sec as Number) as Void {
        _startTimeSec = sec;
    }

    //! Wall-clock elapsed seconds since race start (only accurate while STATE_RUNNING).
    //! Uses System.getTimer() as anchor; resyncs on app re-entry (onShow).
    private function _raceElapsedSecNow() as Number {
        if (_state != STATE_RUNNING) {
            return _raceElapsedSec;
        }
        var elapsedMs = System.getTimer() - _raceAnchorMs;
        if (elapsedMs < 0) {
            elapsedMs = 0;
        }
        var elapsedSec = elapsedMs / 1000;
        if (elapsedSec > _startTimeSec) {
            elapsedSec = _startTimeSec;
        }
        return elapsedSec;
    }

    public function raceRemaining() as Number {
        return _startTimeSec - _raceElapsedSecNow();
    }

    //! Begin the race: set anchor and start haptics replay loop.
    public function start() as Void {
        if (_state != STATE_READY) {
            return;
        }
        _raceElapsedSec = 0;
        _raceAnchorMs = System.getTimer();
        _lastFiredElapsedSec = 0;
        _state = STATE_RUNNING;
        _notifyStateChange();
    }

    //! Reset to READY state (called from Delegate menu/back button).
    public function reset() as Void {
        _raceElapsedSec = 0;
        _raceAnchorMs = 0;
        _lastFiredElapsedSec = 0;
        _syncMode = false;
        _state = STATE_READY;
        _notifyStateChange();
    }

    //! Called on every 1-second timer tick (and replayed onShow if missed while suspended).
    //! Advances haptics second by second, ends race at 0:00, returns true if race ended.
    public function processWallClockSeconds() as Boolean {
        if (_state != STATE_RUNNING) {
            return false;
        }
        var elapsedSec = _raceElapsedSecNow();
        while (_lastFiredElapsedSec < elapsedSec) {
            _lastFiredElapsedSec++;
            var remaining = _startTimeSec - _lastFiredElapsedSec;
            triggerHaptics(remaining);
            if (remaining <= 0) {
                _syncMode = false;
                _state = STATE_FINISHED;
                _raceElapsedSec = elapsedSec;
                _notifyStateChange();
                return true;
            }
        }
        _raceElapsedSec = elapsedSec;
        return false;
    }

    //! True if `remainingWholeMinutes` is in the scheduled horn list and before race start.
    private function _isScheduledHornMinute(remainingWholeMinutes as Number) as Boolean {
        if (remainingWholeMinutes >= (_startTimeSec / 60)) {
            return false;
        }
        for (var i = 0; i < _hornMinutes.size(); i++) {
            if (_hornMinutes[i] == remainingWholeMinutes) {
                return true;
            }
        }
        return false;
    }

    //! True if we should fire a final countdown tick (short haptic) for this remaining second.
    private function _isFinalCountdownTick(remaining as Number) as Boolean {
        var raceStartWholeMins = _startTimeSec / 60;
        for (var i = 0; i < _finalCountdownTicks.size(); i++) {
            var tick = _finalCountdownTicks[i] as Number;
            // Before start gun (0:00)
            if (tick == remaining) {
                return true;
            }
            // Before each scheduled horn minute
            for (var j = 0; j < _hornMinutes.size(); j++) {
                var m = _hornMinutes[j] as Number;
                if (m < raceStartWholeMins and m * 60 + tick == remaining) {
                    return true;
                }
            }
        }
        return false;
    }

    //! True if we're in the 10-second window before a scheduled horn (allows sync).
    private function _inTenSecWindowBeforeScheduledHorn(remaining as Number) as Boolean {
        var raceStartWholeMins = _startTimeSec / 60;
        for (var i = 0; i < _hornMinutes.size(); i++) {
            var m = _hornMinutes[i] as Number;
            if (m < raceStartWholeMins) {
                var t = m * 60;
                if (remaining >= t and remaining <= t + 10) {
                    return true;
                }
            }
        }
        return false;
    }

    //! Largest scheduled horn (seconds remaining) with time <= `maxRemaining`; includes 0 for start gun.
    //! Used by sync to snap to the last horn before the press moment.
    private function _largestScheduledHornNotAbove(maxRemaining as Number) as Number {
        var best = -1;
        var raceStartWholeMins = _startTimeSec / 60;
        for (var i = 0; i < _hornMinutes.size(); i++) {
            var m = _hornMinutes[i] as Number;
            var t = m * 60;
            if (m < raceStartWholeMins and t <= maxRemaining and t > best) {
                best = t;
            }
        }
        if (maxRemaining >= 0 and 0 > best) {
            best = 0;
        }
        return best;
    }

    //! Fire haptic feedback based on race state.
    //! Patterns: start gun (double long), warning horns (long), final ticks (short).
    //! Also turns on backlight in final 10 seconds (if device has :backlight).
    public function triggerHaptics(remaining as Number) as Void {
        //! Garmin Connect IQ does not allow Attention.vibrate() while the app is fully suspended.
        //! This method runs during the 1-second timer callback while the app is in foreground.
        //! The haptics will not fire if the app is in background. The replay logic (onShow)
        //! re-enters onShow and replays missed seconds' haptics once the app returns to foreground.
        if (remaining <= 10 and Attention has :backlight) {
            Attention.backlight(true);
        }
        if (!(Attention has :vibrate)) {
            return;
        }
        if (remaining == 0) {
            // Start gun: double long burst with gap
            Attention.vibrate([
                new Attention.VibeProfile(100, 800),
                new Attention.VibeProfile(0,   300),
                new Attention.VibeProfile(100, 800)
            ] as Array<Attention.VibeProfile>);
        } else if (remaining % 60 == 0 and _isScheduledHornMinute(remaining / 60)) {
            // Warning horn at scheduled minute: long burst
            Attention.vibrate([new Attention.VibeProfile(100, 800)] as Array<Attention.VibeProfile>);
        } else if (_isFinalCountdownTick(remaining)) {
            // Final countdown: short burst
            Attention.vibrate([new Attention.VibeProfile(100, 150)] as Array<Attention.VibeProfile>);
        }
    }

    //! True if we're in a sync-allowed window (final 10 seconds or 10 seconds before a scheduled horn).
    public function isInSyncWindow() as Boolean {
        if (_state != STATE_RUNNING) {
            return false;
        }
        var remaining = raceRemaining();
        if (_inTenSecWindowBeforeScheduledHorn(remaining)) {
            return true;
        }
        return remaining >= 0 and remaining <= 10;
    }

    //! Helmsman presses at key-down (during sync window) to anchor the snap-on-release.
    public function recordSyncPressAnchor() as Void {
        _syncPressElapsedSec = _raceElapsedSecNow();
    }

    //! Activate sync mode (long-press confirmed, show green overlay).
    //! Returns false if not in a valid sync window (Delegate should not treat as active).
    public function enterSyncMode() as Boolean {
        if (!isInSyncWindow()) {
            return false;
        }
        _syncMode = true;
        _notifyStateChange();
        return true;
    }

    //! Helmsman releases SELECT (not DOWN): snap to the last horn at-or-before `_syncPressElapsedSec`.
    //! If no horn was found, move to FINISHED.
    public function finishSync() as Void {
        if (!_syncMode) {
            return;
        }
        var pressedAtRemaining = _startTimeSec - _syncPressElapsedSec;
        var snapToRemaining = _largestScheduledHornNotAbove(pressedAtRemaining);
        _syncMode = false;
        if (snapToRemaining < 0) {
            _notifyStateChange();
            return;
        }
        if (snapToRemaining <= 0) {
            // Snapped to start gun: finish the race
            _raceElapsedSec = _startTimeSec;
            _lastFiredElapsedSec = _startTimeSec;
            _state = STATE_FINISHED;
            freezeRace();
            triggerHaptics(0);
        } else {
            // Snapped to a warning horn: re-anchor race to that moment
            _raceElapsedSec = _startTimeSec - (snapToRemaining - 1);
            _raceAnchorMs = System.getTimer() - (_raceElapsedSec * 1000);
            _lastFiredElapsedSec = _raceElapsedSec;
        }
        _notifyStateChange();
    }

    //! Cancel sync mode (helmsman pressed DOWN during long-hold).
    public function cancelSync() as Void {
        _syncMode = false;
        _notifyStateChange();
    }

    //! True if we're in sync mode (drawn with green overlay).
    public function isInSyncMode() as Boolean {
        return _syncMode;
    }

    //! End the race immediately (from Delegate stop button).
    //! Record the final elapsed time and transition to FINISHED.
    public function finishRaceNow() as Void {
        if (_state == STATE_RUNNING) {
            _raceElapsedSec = _raceElapsedSecNow();
            _state = STATE_FINISHED;
            triggerHaptics(0);
            _notifyStateChange();
        }
    }

    //! Freeze the race timer (pause without ending).
    //! Used during cleanup; does not change state.
    public function freezeRace() as Void {
        if (_state == STATE_RUNNING) {
            _raceElapsedSec = _raceElapsedSecNow();
        }
    }

    private function _notifyStateChange() as Void {
        if (_onStateChange != null) {
            _onStateChange.invoke();
        }
    }
}
