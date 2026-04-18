import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

class Tuesday_Night_TimerView extends WatchUi.View {
    private var _timer1 as Timer.Timer?;
    //! While RUNNING, wall-clock elapsed seconds = (System.getTimer() - _raceAnchorMs) / 1000; _count1 mirrors that for FINISHED/sync.
    private var _count1 as Number = 0;
    private var _raceAnchorMs as Number = 0;
    //! Last race elapsed second (0.._startTime) we already ran triggerHaptics for; see processRaceWallSeconds().
    private var _lastFiredRaceElapsed as Number = 0;

    static const STATE_READY    = 0;
    static const STATE_RUNNING  = 1;
    static const STATE_FINISHED = 2;

    //! Stopwatch: short SELECT while race runs cycles start → stop → reset.
    static const SW_IDLE    = 0;
    static const SW_RUNNING = 1;
    static const SW_PAUSED  = 2;

    private var _state     as Number  = STATE_READY;
    private var _startTime as Number  = 300;
    private var _syncMode  as Boolean = false;
    //! Race elapsed seconds (wall) when start key went down in sync window; release snaps from this instant only.
    private var _syncPressCount as Number  = 0;

    private var _swState         as Number = SW_IDLE;
    private var _swTimer         as Timer.Timer?;
    private var _swElapsedMs     as Number = 0;
    private var _swSegmentStartMs as Number = 0;

    //! Ignore duplicate cycleStopwatch within this window (select + key release same gesture).
    private var _swLastCycleMs as Number = 0;
    private const SW_CYCLE_DEBOUNCE_MS = 45;

    //! Major horns at these whole-minute marks of remaining time (5–4–1); also drives 10 s sync windows and red digits.
    private var _scheduleHornMins as Array<Number> = [5, 4, 1] as Array<Number>;
    //! Short haptic ticks in the last seconds before 0:00 (0 is start gun, handled separately).
    private var _scheduleFinalTicks as Array<Number> = [10, 5, 3, 2, 1] as Array<Number>;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
        setLayout(Rez.Layouts.MainLayout(dc));
    }

    //! When returning from another screen or after the OS paused us, catch up wall-clock seconds and replay missed haptics.
    function onShow() as Void {
        if (_state == STATE_RUNNING) {
            if (processRaceWallSeconds()) {
                return;
            }
            if (_swState == SW_RUNNING) {
                startStopwatchUiTimer();
            }
        }
        WatchUi.requestUpdate();
    }

    //! Stops only the 10 Hz stopwatch redraw ticker. Race countdown uses wall time + 1 s callback and keeps running under Menu2.
    function onHide() as Void {
        stopStopwatchUiTimer();
    }

    //! Called by the 1-second timer — advances haptics from wall clock (may batch if we were away).
    public function callback() as Void {
        if (processRaceWallSeconds()) {
            return;
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (_state == STATE_READY) {
            drawReadyScreen(dc);
        } else if (_state == STATE_RUNNING) {
            drawRunningScreen(dc);
        } else {
            drawFinishedScreen(dc);
        }
        drawStopwatch(dc);
    }

    //! Countdown + clip region top edge → divider; ~10% of face below old 50% line (more room for countdown).
    private function topHalfHeight(dc as Dc) as Number {
        return dc.getHeight() / 2 + dc.getHeight() / 10;
    }

    private function topHalfCenterY(dc as Dc) as Number {
        return topHalfHeight(dc) / 2;
    }

    //! Shift countdown digits upward within the top region.
    private function countdownDrawY(dc as Dc) as Number {
        return topHalfCenterY(dc) - dc.getHeight() / 14;
    }

    private function bottomHalfCenterY(dc as Dc) as Number {
        var th = topHalfHeight(dc);
        return th + (dc.getHeight() - th) / 2;
    }

    private function clipTopHalf(dc as Dc) as Void {
        dc.setClip(0, 0, dc.getWidth(), topHalfHeight(dc));
    }

    private function clipFull(dc as Dc) as Void {
        dc.setClip(0, 0, dc.getWidth(), dc.getHeight());
    }

    private function drawReadyScreen(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var ty = countdownDrawY(dc);
        clipTopHalf(dc);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, ty, Graphics.FONT_NUMBER_THAI_HOT, formatTime(_startTime), Graphics.TEXT_JUSTIFY_CENTER);
        clipFull(dc);
    }

    private function drawRunningScreen(dc as Dc) as Void {
        var remaining = raceRemaining();
        var string = "";
        var inWarnDigits = (_hornAppliesToWholeMinute(remaining / 60) and (remaining % 60) <= 10) or remaining <= 10;
        if (inWarnDigits) {
            string = (remaining % 60).toString();
        } else {
            string = formatTime(remaining);
        }
        clipTopHalf(dc);
        if (_syncMode) {
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        } else if (inWarnDigits) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        }
        dc.drawText(dc.getWidth() / 2, countdownDrawY(dc), Graphics.FONT_NUMBER_THAI_HOT, string, Graphics.TEXT_JUSTIFY_CENTER);
        clipFull(dc);
    }

    private function drawFinishedScreen(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var ty = countdownDrawY(dc);
        clipTopHalf(dc);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, ty, Graphics.FONT_NUMBER_THAI_HOT, "00:00", Graphics.TEXT_JUSTIFY_CENTER);
        clipFull(dc);
    }

    private function stopwatchElapsedMs() as Number {
        if (_swState == SW_RUNNING) {
            return _swElapsedMs + (System.getTimer() - _swSegmentStartMs);
        }
        return _swElapsedMs;
    }

    private function stopwatchCentis() as Number {
        return stopwatchElapsedMs() / 10;
    }

    private function formatStopwatch(totalCs as Number) as String {
        var cs = totalCs % 100;
        var totalSec = totalCs / 100;
        var s = totalSec % 60;
        var m = totalSec / 60;
        var mStr = m.toString();
        var sStr = s < 10 ? "0" + s.toString() : s.toString();
        var csStr = cs < 10 ? "0" + cs.toString() : cs.toString();
        return mStr + ":" + sStr + ":" + csStr;
    }

    private function clipBottomHalf(dc as Dc) as Void {
        var th = topHalfHeight(dc);
        dc.setClip(0, th, dc.getWidth(), dc.getHeight() - th);
    }

    private function drawStopwatch(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        //! Numeric time sits higher in the bottom half (label removed).
        var timeY = bottomHalfCenterY(dc) - 36;
        clipBottomHalf(dc);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, timeY, Graphics.FONT_NUMBER_MEDIUM, formatStopwatch(stopwatchCentis()), Graphics.TEXT_JUSTIFY_CENTER);
        clipFull(dc);
    }

    private function formatTime(seconds as Number) as String {
        var mins = seconds / 60;
        var secs = seconds % 60;
        var mStr = mins < 10 ? "0" + mins.toString() : mins.toString();
        var sStr = secs < 10 ? "0" + secs.toString() : secs.toString();
        return mStr + ":" + sStr;
    }

    //! Wall-clock seconds since race start (only meaningful while STATE_RUNNING).
    private function raceElapsedSec() as Number {
        if (_state != STATE_RUNNING) {
            return _count1;
        }
        var dt = System.getTimer() - _raceAnchorMs;
        if (dt < 0) {
            dt = 0;
        }
        var e = dt / 1000;
        if (e > _startTime) {
            e = _startTime;
        }
        return e;
    }

    private function raceRemaining() as Number {
        return _startTime - raceElapsedSec();
    }

    //! Advances haptics for every whole second the wall clock passed since last fire; ends race at 0:00.
    //! CIQ cannot vibrate while our process is fully suspended; onShow + this loop replays missed seconds when possible.
    private function processRaceWallSeconds() as Boolean {
        if (_state != STATE_RUNNING) {
            return false;
        }
        var e = raceElapsedSec();
        while (_lastFiredRaceElapsed < e) {
            _lastFiredRaceElapsed++;
            var rem = _startTime - _lastFiredRaceElapsed;
            triggerHaptics(rem);
            if (rem <= 0) {
                _syncMode = false;
                stopTimerInternal();
                _state = STATE_FINISHED;
                _count1 = e;
                freezeStopwatchOnRaceEnd();
                WatchUi.requestUpdate();
                return true;
            }
        }
        _count1 = e;
        return false;
    }

    private function _raceStartWholeMins() as Number {
        return _startTime / 60;
    }

    //! True if `rm` is a scheduled major-horn minute mark and is before the configured start length.
    private function _hornAppliesToWholeMinute(rm as Number) as Boolean {
        if (rm >= _raceStartWholeMins()) {
            return false;
        }
        for (var i = 0; i < _scheduleHornMins.size(); i++) {
            if (_scheduleHornMins[i] == rm) {
                return true;
            }
        }
        return false;
    }

    private function _isFinalCountdownTick(remaining as Number) as Boolean {
        var sm = _raceStartWholeMins();
        for (var i = 0; i < _scheduleFinalTicks.size(); i++) {
            var tick = _scheduleFinalTicks[i] as Number;
            // Before start gun (0:00)
            if (tick == remaining) {
                return true;
            }
            // Before each scheduled horn minute
            for (var j = 0; j < _scheduleHornMins.size(); j++) {
                var m = _scheduleHornMins[j] as Number;
                if (m < sm and m * 60 + tick == remaining) {
                    return true;
                }
            }
        }
        return false;
    }

    //! True in the 10 s window before a scheduled major horn (same rule as sync for those horns).
    private function _inTenSecWindowBeforeScheduledHorn(remaining as Number) as Boolean {
        var sm = _raceStartWholeMins();
        for (var i = 0; i < _scheduleHornMins.size(); i++) {
            var m = _scheduleHornMins[i] as Number;
            if (m < sm) {
                var t = m * 60;
                if (remaining >= t and remaining <= t + 10) {
                    return true;
                }
            }
        }
        return false;
    }

    //! Largest scheduled horn (seconds remaining) with hornTime <= R0; includes 0 for start gun.
    private function maxSignalNotAbove(R0 as Number) as Number {
        var best = -1;
        var sm = _raceStartWholeMins();
        for (var i = 0; i < _scheduleHornMins.size(); i++) {
            var m = _scheduleHornMins[i] as Number;
            var t = m * 60;
            if (m < sm and t <= R0 and t > best) {
                best = t;
            }
        }
        if (R0 >= 0 and 0 > best) {
            best = 0;
        }
        return best;
    }

    private function triggerHaptics(remaining as Number) as Void {
        //! Vibrates only while this app is running; Garmin does not allow Attention in true background services.
        if (remaining <= 10 and Attention has :backlight) {
            Attention.backlight(true);
        }
        if (!(Attention has :vibrate)) { return; }
        if (remaining == 0) {
            // Start gun: double long burst
            Attention.vibrate([
                new Attention.VibeProfile(100, 800),
                new Attention.VibeProfile(0,   300),
                new Attention.VibeProfile(100, 800)
            ] as Array<Attention.VibeProfile>);
        } else if (remaining % 60 == 0 and _hornAppliesToWholeMinute(remaining / 60)) {
            // Signal gun at a warning minute: long burst
            Attention.vibrate([new Attention.VibeProfile(100, 800)] as Array<Attention.VibeProfile>);
        } else if (_isFinalCountdownTick(remaining)) {
            // Final countdown ticks: short burst
            Attention.vibrate([new Attention.VibeProfile(100, 150)] as Array<Attention.VibeProfile>);
        }
    }

    // --- Public interface for delegate ---

    public function isRunning() as Boolean {
        return _state == STATE_RUNNING;
    }

    //! True in a 10 s window before a scheduled major horn or in the final 10 s — only time sync is allowed.
    public function isInSyncWindow() as Boolean {
        if (_state != STATE_RUNNING) { return false; }
        var remaining = raceRemaining();
        if (_inTenSecWindowBeforeScheduledHorn(remaining)) {
            return true;
        }
        return remaining >= 0 and remaining <= 10;
    }

    //! Call on physical start key down in sync window — anchors snap-on-release to this tick.
    public function recordSyncPressAnchor() as Void {
        _syncPressCount = raceElapsedSec();
    }

    //! Long-press confirmed: same countdown as normal, drawn in green until release or cancel.
    //! @return false if not in a sync window (delegate should not treat as active).
    public function enterSyncMode() as Boolean {
        if (!isInSyncWindow()) {
            return false;
        }
        _syncMode = true;
        WatchUi.requestUpdate();
        return true;
    }

    //! SELECT released (not canceled): snap to one second after the latest horn not after
    //! remaining-at-press (always uses _syncPressCount from key-down, not current time).
    public function finishSyncHoldRelease() as Void {
        if (!_syncMode) {
            return;
        }
        var R0 = _startTime - _syncPressCount;
        var H = maxSignalNotAbove(R0);
        _syncMode = false;
        if (H < 0) {
            WatchUi.requestUpdate();
            return;
        }
        if (H <= 0) {
            _count1 = _startTime;
            _lastFiredRaceElapsed = _startTime;
            stopTimerInternal();
            _state = STATE_FINISHED;
            freezeStopwatchOnRaceEnd();
            triggerHaptics(0);
        } else {
            _count1 = _startTime - (H - 1);
            _raceAnchorMs = System.getTimer() - _count1 * 1000;
            _lastFiredRaceElapsed = _count1;
        }
        WatchUi.requestUpdate();
    }

    //! DOWN during hold-sync: keep current time; exit green overlay (normal colors/rules).
    public function cancelSyncMode() as Void {
        _syncMode = false;
        WatchUi.requestUpdate();
    }

    //! Called by the time-select menu when the user picks a new start time
    public function setStartTime(seconds as Number) as Void {
        _startTime = seconds;
        WatchUi.requestUpdate();
    }

    public function onPrimaryAction() as Void {
        if (_state == STATE_READY) {
            resetStopwatchForRace();
            _count1 = 0;
            _raceAnchorMs = System.getTimer();
            _lastFiredRaceElapsed = 0;
            var timer1 = new Timer.Timer();
            timer1.start(method(:callback), 1000, true);
            _timer1 = timer1;
            _state = STATE_RUNNING;
            WatchUi.requestUpdate();
        } else if (_state == STATE_FINISHED) {
            resetStopwatchForRace();
            _count1 = 0;
            _state = STATE_READY;
            WatchUi.requestUpdate();
        }
    }

    public function handleBack() as Boolean {
        if (_state == STATE_RUNNING) {
            return true;  // block back during race
        } else if (_state == STATE_FINISHED) {
            resetStopwatchForRace();
            _count1 = 0;
            _state = STATE_READY;
            WatchUi.requestUpdate();
            return true;
        }
        return false;  // READY: let framework exit the app normally
    }

    public function handleMenu() as Void {
        if (_state == STATE_READY) {
            var menu = new WatchUi.Menu2({:title => "Start Time"});
            menu.addItem(new WatchUi.MenuItem("5:00", null, 300, null));
            menu.addItem(new WatchUi.MenuItem("4:00", null, 240, null));
            menu.addItem(new WatchUi.MenuItem("3:00", null, 180, null));
            menu.addItem(new WatchUi.MenuItem("2:00", null, 120, null));
            menu.addItem(new WatchUi.MenuItem("1:00", null, 60, null));
            WatchUi.pushView(menu, new Tuesday_Night_TimerMenuDelegate(method(:setStartTime)), WatchUi.SLIDE_UP);
        } else if (_state == STATE_RUNNING) {
            if (_syncMode) {
                _syncMode = false;
            }
            stopTimerInternal();
            resetStopwatchForRace();
            _count1 = 0;
            _state = STATE_READY;
            WatchUi.requestUpdate();
        } else if (_state == STATE_FINISHED) {
            resetStopwatchForRace();
            _count1 = 0;
            _state = STATE_READY;
            WatchUi.requestUpdate();
        }
    }

    public function stopTimer() as Void {
        _syncMode = false;
        stopTimerInternal();
        _state = STATE_FINISHED;
        freezeStopwatchOnRaceEnd();
        WatchUi.requestUpdate();
    }

    private function stopMainRaceTicker() as Void {
        if (_timer1 != null) {
            _timer1.stop();
            _timer1 = null;
        }
    }

    private function stopTimerInternal() as Void {
        stopMainRaceTicker();
    }

    private function resetStopwatchForRace() as Void {
        stopStopwatchUiTimer();
        _raceAnchorMs = 0;
        _lastFiredRaceElapsed = 0;
        _swState = SW_IDLE;
        _swElapsedMs = 0;
        _swSegmentStartMs = 0;
        _swLastCycleMs = 0;
    }

    private function freezeStopwatchOnRaceEnd() as Void {
        if (_swState == SW_RUNNING) {
            _swElapsedMs += System.getTimer() - _swSegmentStartMs;
            _swState = SW_PAUSED;
        }
        stopStopwatchUiTimer();
    }

    //! Start / stop / reset cycle — only call from delegate on short SELECT or touch tap while running.
    public function cycleStopwatch() as Void {
        var now = System.getTimer();
        if (_swLastCycleMs != 0 and (now - _swLastCycleMs) < SW_CYCLE_DEBOUNCE_MS) {
            return;
        }
        _swLastCycleMs = now;
        if (_swState == SW_IDLE) {
            _swElapsedMs = 0;
            _swSegmentStartMs = System.getTimer();
            _swState = SW_RUNNING;
            startStopwatchUiTimer();
        } else if (_swState == SW_RUNNING) {
            _swElapsedMs += System.getTimer() - _swSegmentStartMs;
            _swState = SW_PAUSED;
            stopStopwatchUiTimer();
        } else {
            _swElapsedMs = 0;
            _swState = SW_IDLE;
            stopStopwatchUiTimer();
        }
        WatchUi.requestUpdate();
    }

    //! ~10 Hz while the stopwatch runs so M:SS:CS updates smoothly.
    public function onStopwatchUiTick() as Void {
        if (_swState != SW_RUNNING) {
            return;
        }
        WatchUi.requestUpdate();
    }

    private function startStopwatchUiTimer() as Void {
        stopStopwatchUiTimer();
        var t = new Timer.Timer();
        t.start(method(:onStopwatchUiTick), 100, true);
        _swTimer = t;
    }

    private function stopStopwatchUiTimer() as Void {
        if (_swTimer != null) {
            _swTimer.stop();
            _swTimer = null;
        }
    }

}
