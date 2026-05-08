import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! Main view: orchestrates the race engine, stopwatch, and activity manager.
//! Owns all drawing logic and lifecycle management (onShow, onHide, onUpdate).
class Tuesday_Night_TimerView extends WatchUi.View {

    private var _raceEngine     as RaceEngine;
    private var _stopwatch      as Stopwatch;
    private var _activityMgr    as ActivityManager;

    //! Main race timer callback (1 second).
    private var _raceTimer      as Timer.Timer?;

    //! Idle timeout: auto-exit app after 5 hours (18000 seconds) of no user interaction.
    private var _idleTimer      as Timer.Timer?               = null;
    private var _lastActivityMs as Number                     = 0;
    private static const IDLE_TIMEOUT_MS = 5 * 60 * 60 * 1000;  // 5 hours

    //! Racing screen: toggles between COG and elapsed-time display (onNextPage).
    private var _racingPage     as Number = 0;

    function initialize() {
        View.initialize();
        _raceEngine = new RaceEngine(method(:_onStateChange));
        _stopwatch = new Stopwatch(method(:_onStateChange));
        _activityMgr = new ActivityManager(method(:_onStateChange));
    }

    function onLayout(dc as Dc) as Void {
        setLayout(Rez.Layouts.MainLayout(dc));
    }

    //! Called when returning from another screen or after OS paused us.
    //! Catch up wall-clock and replay any missed haptics.
    function onShow() as Void {
        _resetIdleTimeout();
        if (_raceEngine.getState() == RaceEngine.STATE_RUNNING) {
            if (_raceEngine.processWallClockSeconds()) {
                // Race ended during suspension
                if (_activityMgr.hasSession()) {
                    _startRecIndicatorTimer();
                }
                return;
            }
            if (_stopwatch.isRunning()) {
                _stopwatch._onUiTick();
            }
        }
        if (_raceEngine.getState() == RaceEngine.STATE_FINISHED and _activityMgr.hasSession()) {
            _startRecIndicatorTimer();
        }
        WatchUi.requestUpdate();
    }

    //! Stops the UI timers. Race countdown keeps running under Menu2.
    function onHide() as Void {
        if (_stopwatch.isRunning()) {
            _stopwatch._onUiTick();  // Ensure final redraw
        }
        if (_idleTimer != null) {
            _idleTimer.stop();
            _idleTimer = null;
        }
    }

    //! Called by the 1-second race timer.
    public function _onRaceTimerTick() as Void {
        if (_raceEngine.processWallClockSeconds()) {
            // Race ended
            if (_activityMgr.hasSession()) {
                _startRecIndicatorTimer();
            }
            return;
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        if (_activityMgr.hasSession()) {
            _drawRacingScreen(dc);
            return;
        }

        var state = _raceEngine.getState();
        if (state == RaceEngine.STATE_READY) {
            _drawReadyScreen(dc);
        } else if (state == RaceEngine.STATE_RUNNING) {
            _drawRunningScreen(dc);
        } else {
            _drawFinishedScreen(dc);
        }
        _drawStopwatch(dc);
    }

    // =========================================================================
    // Drawing helpers
    // =========================================================================

    private function _topHalfHeight(dc as Dc) as Number {
        return dc.getHeight() / 2 + dc.getHeight() / 10;
    }

    private function _topHalfCenterY(dc as Dc) as Number {
        return _topHalfHeight(dc) / 2;
    }

    private function _countdownDrawY(dc as Dc) as Number {
        return _topHalfCenterY(dc) - dc.getHeight() / 14;
    }

    private function _bottomHalfCenterY(dc as Dc) as Number {
        var th = _topHalfHeight(dc);
        return th + (dc.getHeight() - th) / 2;
    }

    private function _clipTopHalf(dc as Dc) as Void {
        dc.setClip(0, 0, dc.getWidth(), _topHalfHeight(dc));
    }

    private function _clipBottomHalf(dc as Dc) as Void {
        var th = _topHalfHeight(dc);
        dc.setClip(0, th, dc.getWidth(), dc.getHeight() - th);
    }

    private function _clipFull(dc as Dc) as Void {
        dc.setClip(0, 0, dc.getWidth(), dc.getHeight());
    }

    private function _drawReadyScreen(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var ty = _countdownDrawY(dc);
        _clipTopHalf(dc);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, ty, Graphics.FONT_NUMBER_THAI_HOT, _formatTime(_raceEngine.getStartTimeSec()), Graphics.TEXT_JUSTIFY_CENTER);
        _clipFull(dc);
    }

    private function _drawRunningScreen(dc as Dc) as Void {
        var remaining = _raceEngine.raceRemaining();
        var string = "";
        var inWarnDigits = (_isScheduledHornMinute(remaining / 60) and (remaining % 60) <= 10) or remaining <= 10;
        if (inWarnDigits) {
            string = (remaining % 60).toString();
        } else {
            string = _formatTime(remaining);
        }
        _clipTopHalf(dc);
        if (_raceEngine.isInSyncMode()) {
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        } else if (inWarnDigits) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        }
        dc.drawText(dc.getWidth() / 2, _countdownDrawY(dc), Graphics.FONT_NUMBER_THAI_HOT, string, Graphics.TEXT_JUSTIFY_CENTER);
        _clipFull(dc);
    }

    private function _drawFinishedScreen(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var ty = _countdownDrawY(dc);
        _clipTopHalf(dc);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, ty, Graphics.FONT_NUMBER_THAI_HOT, "00:00", Graphics.TEXT_JUSTIFY_CENTER);
        if (_activityMgr.hasSession()) {
            var dotY = ty + dc.getFontHeight(Graphics.FONT_NUMBER_THAI_HOT) / 2 + 4;
            var dotX = cx - 20;
            var dotR = 5;
            dc.setColor(_activityMgr.isIndicatorOn() ? Graphics.COLOR_RED : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(dotX, dotY, dotR);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(dotX + dotR + 4, dotY - dotR, Graphics.FONT_XTINY, "REC", Graphics.TEXT_JUSTIFY_LEFT);
        }
        _clipFull(dc);
    }

    private function _drawStopwatch(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var timeY = _bottomHalfCenterY(dc) - 36;
        _clipBottomHalf(dc);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, timeY, Graphics.FONT_NUMBER_MEDIUM, _stopwatch.formatDisplay(), Graphics.TEXT_JUSTIFY_CENTER);
        _clipFull(dc);
    }

    private function _drawRacingScreen(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var h  = dc.getHeight();
        dc.clearClip();

        var info = Activity.getActivityInfo();

        // SOG — large number, top quarter
        var sogStr = "--.-";
        if (info != null && info.currentSpeed != null) {
            var kts = (info.currentSpeed as Float) * 1.94384f;
            sogStr = kts.format("%.1f");
        }
        var sogFontH = dc.getFontHeight(Graphics.FONT_NUMBER_THAI_HOT);
        var sogY = h / 10;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, sogY, Graphics.FONT_NUMBER_THAI_HOT, sogStr, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, sogY + sogFontH, Graphics.FONT_XTINY, "kt", Graphics.TEXT_JUSTIFY_CENTER);

        // COG string
        var cogStr = "---°";
        if (info != null && info.currentHeading != null) {
            var deg = ((info.currentHeading as Float) * (180.0f / Math.PI)).toNumber();
            if (deg < 0) { deg += 360; }
            cogStr = deg.toString() + "° " + _headingToCompass(deg);
        }

        // Elapsed string
        var elStr = "--:--";
        if (info != null && info.timerTime != null) {
            var ts = (info.timerTime as Number) / 1000;
            var em = ts / 60;
            var es = ts % 60;
            elStr = em.toString() + ":" + (es < 10 ? "0" : "") + es.toString();
        }

        // Primary field (COG or elapsed based on page), secondary below
        var primaryStr  = _racingPage == 0 ? cogStr  : elStr;
        var primaryLabel= _racingPage == 0 ? "COG"   : "ELAPSED";
        var secondaryStr  = _racingPage == 0 ? elStr   : cogStr;
        var secondaryLabel= _racingPage == 0 ? "ELAPSED": "COG";

        var primaryY = sogY + sogFontH + dc.getFontHeight(Graphics.FONT_XTINY) + h / 12;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, primaryY, Graphics.FONT_XTINY, primaryLabel, Graphics.TEXT_JUSTIFY_CENTER);
        var primaryValY = primaryY + dc.getFontHeight(Graphics.FONT_XTINY) + 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, primaryValY, Graphics.FONT_LARGE, primaryStr, Graphics.TEXT_JUSTIFY_CENTER);

        var secondaryY = primaryValY + dc.getFontHeight(Graphics.FONT_LARGE) + h / 18;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, secondaryY, Graphics.FONT_XTINY, secondaryLabel, Graphics.TEXT_JUSTIFY_CENTER);
        var secondaryValY = secondaryY + dc.getFontHeight(Graphics.FONT_XTINY) + 2;
        dc.drawText(cx, secondaryValY, Graphics.FONT_MEDIUM, secondaryStr, Graphics.TEXT_JUSTIFY_CENTER);

        // REC dot — bottom
        var dotY = h - h / 10;
        dc.setColor(_activityMgr.isIndicatorOn() ? Graphics.COLOR_RED : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - 16, dotY, 5);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 8, dotY - 8, Graphics.FONT_XTINY, "REC", Graphics.TEXT_JUSTIFY_LEFT);
    }

    private function _headingToCompass(deg as Number) as String {
        var pts = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"] as Array<String>;
        return pts[((deg + 11) / 22) % 16];
    }

    private function _formatTime(seconds as Number) as String {
        var mins = seconds / 60;
        var secs = seconds % 60;
        var mStr = mins < 10 ? "0" + mins.toString() : mins.toString();
        var sStr = secs < 10 ? "0" + secs.toString() : secs.toString();
        return mStr + ":" + sStr;
    }

    //! Helper to check if a whole-minute value is a scheduled horn minute (for color display).
    private function _isScheduledHornMinute(remainingWholeMins as Number) as Boolean {
        var raceStartMins = _raceEngine.getStartTimeSec() / 60;
        var hornMins = [5, 4, 1] as Array<Number>;
        if (remainingWholeMins >= raceStartMins) {
            return false;
        }
        for (var i = 0; i < hornMins.size(); i++) {
            if (hornMins[i] == remainingWholeMins) {
                return true;
            }
        }
        return false;
    }

    // =========================================================================
    // Public interface for Delegate
    // =========================================================================

    public function isRunning() as Boolean {
        return _raceEngine.getState() == RaceEngine.STATE_RUNNING;
    }

    public function hasActiveSession() as Boolean {
        return _activityMgr.hasSession();
    }

    public function cycleRacingPage() as Void {
        _racingPage = (_racingPage + 1) % 2;
        WatchUi.requestUpdate();
    }

    public function onPrimaryAction() as Void {
        _resetIdleTimeout();
        if (_raceEngine.getState() == RaceEngine.STATE_READY) {
            _stopwatch.reset();
            _raceEngine.start();
            _startRaceTimer();
            WatchUi.requestUpdate();
        } else if (_raceEngine.getState() == RaceEngine.STATE_FINISHED) {
            _activityMgr.discardSession();
            _stopwatch.reset();
            _raceEngine.reset();
            WatchUi.requestUpdate();
        }
    }

    public function handleBack() as Boolean {
        _resetIdleTimeout();
        var state = _raceEngine.getState();
        if (state == RaceEngine.STATE_RUNNING) {
            return true;  // block back during race
        } else if (state == RaceEngine.STATE_FINISHED) {
            _stopwatch.reset();
            _raceEngine.reset();
            WatchUi.requestUpdate();
            return true;
        }
        return false;  // READY: let framework exit normally
    }

    public function handleMenu() as Void {
        _resetIdleTimeout();
        var state = _raceEngine.getState();
        if (state == RaceEngine.STATE_READY) {
            var menu = new WatchUi.Menu2({:title => "Start Time"});
            menu.addItem(new WatchUi.MenuItem("5:00", null, 300, null));
            menu.addItem(new WatchUi.MenuItem("4:00", null, 240, null));
            menu.addItem(new WatchUi.MenuItem("3:00", null, 180, null));
            menu.addItem(new WatchUi.MenuItem("2:00", null, 120, null));
            menu.addItem(new WatchUi.MenuItem("1:00", null, 60, null));
            WatchUi.pushView(menu, new Tuesday_Night_TimerMenuDelegate(method(:_onStartTimeSelected)), WatchUi.SLIDE_UP);
        } else if (state == RaceEngine.STATE_RUNNING) {
            _stopRaceTimer();
            _raceEngine.cancelSync();
            _stopwatch.reset();
            _raceEngine.reset();
            WatchUi.requestUpdate();
        } else if (state == RaceEngine.STATE_FINISHED) {
            _activityMgr.discardSession();
            _stopwatch.reset();
            _raceEngine.reset();
            WatchUi.requestUpdate();
        }
    }

    public function stopTimer() as Void {
        _resetIdleTimeout();
        _raceEngine.cancelSync();
        _stopRaceTimer();
        _raceEngine.finishRaceNow();
        _stopwatch.freeze();
        _activityMgr.startSession();
        WatchUi.requestUpdate();
    }

    public function recordSyncPressAnchor() as Void {
        _raceEngine.recordSyncPressAnchor();
    }

    public function enterSyncMode() as Boolean {
        if (!_raceEngine.enterSyncMode()) {
            return false;
        }
        WatchUi.requestUpdate();
        return true;
    }

    public function finishSyncHoldRelease() as Void {
        _resetIdleTimeout();
        if (!_raceEngine.isInSyncMode()) {
            return;
        }
        _raceEngine.finishSync();
        WatchUi.requestUpdate();
    }

    public function cancelSyncMode() as Void {
        _resetIdleTimeout();
        _raceEngine.cancelSync();
        WatchUi.requestUpdate();
    }

    public function cycleStopwatch() as Void {
        _resetIdleTimeout();
        _stopwatch.cycle();
        WatchUi.requestUpdate();
    }

    public function saveActivitySession() as Void {
        _activityMgr.saveSession();
    }

    public function discardSession() as Void {
        _activityMgr.discardSession();
    }

    public function exitAppNow() as Void {
        _cleanupAndExit();
    }

    public function isInSyncWindow() as Boolean {
        return _raceEngine.isInSyncWindow();
    }

    public function setStartTime(seconds as Number) as Void {
        _raceEngine.setStartTimeSec(seconds);
        WatchUi.requestUpdate();
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    private function _onStartTimeSelected(sec as Number) as Void {
        setStartTime(sec);
    }

    private function _onStateChange() as Void {
        WatchUi.requestUpdate();
    }

    private function _startRaceTimer() as Void {
        var t = new Timer.Timer();
        t.start(method(:_onRaceTimerTick), 1000, true);
        _raceTimer = t;
    }

    private function _stopRaceTimer() as Void {
        if (_raceTimer != null) {
            _raceTimer.stop();
            _raceTimer = null;
        }
    }

    private function _startRecIndicatorTimer() as Void {
        _activityMgr.startSession();
    }

    private function _resetIdleTimeout() as Void {
        _lastActivityMs = System.getTimer();
        if (_idleTimer == null) {
            _idleTimer = new Timer.Timer();
            _idleTimer.start(method(:_onIdleCheck), 60000, true);
        }
    }

    public function _onIdleCheck() as Void {
        var now = System.getTimer();
        if ((now - _lastActivityMs) > IDLE_TIMEOUT_MS) {
            _cleanupAndExit();
        }
    }

    private function _cleanupAndExit() as Void {
        _stopRaceTimer();
        _raceEngine.freezeRace();
        _stopwatch.freeze();
        _activityMgr.discardSession();
        if (_idleTimer != null) {
            _idleTimer.stop();
            _idleTimer = null;
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
