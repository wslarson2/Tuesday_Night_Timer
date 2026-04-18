import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class Tuesday_Night_TimerApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
    }

    // Return the initial view of your application here
    function getInitialView() {
        var view = new $.Tuesday_Night_TimerView();
        var delegate = new $.Tuesday_Night_TimerDelegate(view);
        return [view, delegate];
    }

}