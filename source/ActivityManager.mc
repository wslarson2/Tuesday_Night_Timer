import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! Wrapper around Garmin's ActivityRecording API for capturing race sessions.
//! Automatically records race activity (with sport type SPORT_BOATING when available, else SPORT_GENERIC).
//! Provides REC indicator blinking (1 Hz toggle) to show recording is active.
class ActivityManager {

    private var _session        as ActivityRecording.Session? = null;
    private var _recTimer       as Timer.Timer?               = null;
    private var _recIndicatorOn as Boolean                    = false;
    private var _onStateChange  as Method?;

    function initialize(onStateChange as Method?) {
        _onStateChange = onStateChange;
    }

    public function hasSession() as Boolean {
        return _session != null;
    }

    public function isIndicatorOn() as Boolean {
        return _recIndicatorOn;
    }

    //! Start a new activity recording session (called when race finishes).
    //! Silently fails if ActivityRecording API is not available on this device.
    public function startSession() as Void {
        if (!(Toybox has :ActivityRecording)) {
            return;
        }
        var sport = (Activity has :SPORT_BOATING)
            ? Activity.SPORT_BOATING
            : Activity.SPORT_GENERIC;
        try {
            var s = ActivityRecording.createSession({
                :name     => "Boating",
                :sport    => sport,
                :subSport => Activity.SUB_SPORT_GENERIC
            });
            s.start();
            _session = s;
            _startRecIndicatorTimer();
        } catch (ex instanceof Lang.Exception) {
            _session = null;
        }
    }

    //! Save the active session to the watch's fitness database.
    public function saveSession() as Void {
        if (_session != null) {
            _session.stop();
            _session.save();
            _session = null;
        }
        _stopRecIndicatorTimer();
    }

    //! Discard the active session without saving.
    public function discardSession() as Void {
        if (_session != null) {
            _session.stop();
            _session.discard();
            _session = null;
        }
        _stopRecIndicatorTimer();
    }

    //! Start the REC indicator blink timer (1 Hz, toggles _recIndicatorOn).
    private function _startRecIndicatorTimer() as Void {
        _stopRecIndicatorTimer();
        _recIndicatorOn = true;
        var t = new Timer.Timer();
        t.start(method(:_onRecIndicatorTick), 1000, true);
        _recTimer = t;
    }

    private function _stopRecIndicatorTimer() as Void {
        if (_recTimer != null) {
            _recTimer.stop();
            _recTimer = null;
        }
        _recIndicatorOn = false;
    }

    //! Called by indicator timer: toggle the REC dot visibility.
    public function _onRecIndicatorTick() as Void {
        _recIndicatorOn = !_recIndicatorOn;
        WatchUi.requestUpdate();
    }
}
