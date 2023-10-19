import Toybox.Lang;
import Toybox.WatchUi;

class Tuesday_Night_TImerDelegate extends WatchUi.BehaviorDelegate {

    private var _view as Tuesday_Night_TImerView;

    public function initialize(view as Tuesday_Night_TImerView) {
        WatchUi.BehaviorDelegate.initialize();
        _view = view;
    }

    //! Stop the first timer on menu event
    //! @return true if handled, false otherwise
    public function onMenu() as Boolean {
        _view.stopTimer();
        return true;
    }

}