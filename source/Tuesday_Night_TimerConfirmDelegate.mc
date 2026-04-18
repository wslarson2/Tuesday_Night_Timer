import Toybox.Lang;
import Toybox.WatchUi;

class Tuesday_Night_TimerConfirmDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as Tuesday_Night_TimerView;

    function initialize(view as Tuesday_Night_TimerView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (item.getId() == :yes) {
            _view.stopTimer();
        }
        // :no — just pop, timer keeps running
    }

}
