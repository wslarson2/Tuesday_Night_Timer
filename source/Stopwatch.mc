import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! Parallel stopwatch: runs during the race countdown. Independent start/pause/reset cycle.
//! States: IDLE (display 0:00:00) → RUNNING (ticking) → PAUSED (held) → IDLE (reset).
//! Manages its own 100ms UI timer for smooth centisecond display (0.01s precision).
class Stopwatch {

    static const SW_IDLE    = 0;
    static const SW_RUNNING = 1;
    static const SW_PAUSED  = 2;

    private var _state             as Number  = SW_IDLE;
    private var _elapsedMs         as Number  = 0;    // Total milliseconds accumulated
    private var _segmentStartMs    as Number  = 0;    // System.getTimer() anchor for current running segment
    private var _lastCycleMs       as Number  = 0;    // Debounce multiple cycles in rapid succession
    private const CYCLE_DEBOUNCE_MS = 45;             // Ignore cycles within 45ms of last one

    private var _timer             as Timer.Timer?    = null;
    private var _onStateChange     as Method?;

    function initialize(onStateChange as Method?) {
        _onStateChange = onStateChange;
    }

    public function getState() as Number {
        return _state;
    }

    public function isRunning() as Boolean {
        return _state == SW_RUNNING;
    }

    //! Total elapsed milliseconds (current segment + accumulated).
    private function _elapsedMsNow() as Number {
        if (_state == SW_RUNNING) {
            return _elapsedMs + (System.getTimer() - _segmentStartMs);
        }
        return _elapsedMs;
    }

    //! Total elapsed centiseconds (hundredths of a second).
    public function centiseconds() as Number {
        return _elapsedMsNow() / 10;
    }

    //! Format stopwatch display: M:SS:CS (minutes:seconds:centiseconds).
    public function formatDisplay() as String {
        var totalCs = centiseconds();
        var cs = totalCs % 100;
        var totalSec = totalCs / 100;
        var s = totalSec % 60;
        var m = totalSec / 60;
        var mStr = m.toString();
        var sStr = s < 10 ? "0" + s.toString() : s.toString();
        var csStr = cs < 10 ? "0" + cs.toString() : cs.toString();
        return mStr + ":" + sStr + ":" + csStr;
    }

    //! Cycle: IDLE→RUNNING, RUNNING→PAUSED, PAUSED→IDLE (reset).
    //! Debounces multiple cycles within CYCLE_DEBOUNCE_MS.
    public function cycle() as Void {
        var now = System.getTimer();
        if (_lastCycleMs != 0 and (now - _lastCycleMs) < CYCLE_DEBOUNCE_MS) {
            return;  // Ignore rapid double-cycles
        }
        _lastCycleMs = now;

        if (_state == SW_IDLE) {
            _elapsedMs = 0;
            _segmentStartMs = System.getTimer();
            _state = SW_RUNNING;
            _startUiTimer();
        } else if (_state == SW_RUNNING) {
            _elapsedMs += System.getTimer() - _segmentStartMs;
            _state = SW_PAUSED;
            _stopUiTimer();
        } else {
            _elapsedMs = 0;
            _state = SW_IDLE;
            _stopUiTimer();
        }
        _notifyStateChange();
    }

    //! Pause a running stopwatch (accumulate elapsed, don't reset).
    public function pause() as Void {
        if (_state == SW_RUNNING) {
            _elapsedMs += System.getTimer() - _segmentStartMs;
            _state = SW_PAUSED;
            _stopUiTimer();
            _notifyStateChange();
        }
    }

    //! Freeze the stopwatch at race end (same as pause, but semantic clarity).
    public function freeze() as Void {
        pause();
    }

    //! Reset stopwatch to IDLE state with 0 elapsed.
    public function reset() as Void {
        _stopUiTimer();
        _state = SW_IDLE;
        _elapsedMs = 0;
        _segmentStartMs = 0;
        _lastCycleMs = 0;
        _notifyStateChange();
    }

    //! Start the 100ms UI redraw timer for smooth centisecond updates.
    //! Fires ~10 times per second.
    private function _startUiTimer() as Void {
        _stopUiTimer();
        var t = new Timer.Timer();
        t.start(method(:_onUiTick), 100, true);
        _timer = t;
    }

    private function _stopUiTimer() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    //! Called by UI timer: request redraw for smooth centisecond animation.
    public function _onUiTick() as Void {
        if (_state == SW_RUNNING) {
            WatchUi.requestUpdate();
        }
    }

    private function _notifyStateChange() as Void {
        if (_onStateChange != null) {
            _onStateChange.invoke();
        }
    }
}
