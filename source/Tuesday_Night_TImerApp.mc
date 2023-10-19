import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class Tuesday_Night_TImerApp extends Application.AppBase {

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
    function getInitialView() as Array<Views or InputDelegates>? {
    var view = new $.Tuesday_Night_TImerView();
        var delegate = new $.Tuesday_Night_TImerDelegate(view);
        return [view, delegate] as Array<Views or InputDelegates>;


        //return [ new Tuesday_Night_TImerView(), new Tuesday_Night_TImerDelegate() ] as Array<Views or InputDelegates>;
    }

}

function getApp() as Tuesday_Night_TImerApp {
    return Application.getApp() as Tuesday_Night_TImerApp;
}