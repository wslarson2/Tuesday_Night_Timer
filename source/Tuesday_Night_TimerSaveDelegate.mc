import Toybox.Lang;
import Toybox.WatchUi;

class Tuesday_Night_TimerSaveDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as Tuesday_Night_TimerView;

    function initialize(view as Tuesday_Night_TimerView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        var id = item.getId();
        if (id == :save) {
            _view.saveActivitySession();
            _view.handleBack();
        } else if (id == :discard) {
            _view.discardActivitySession();
            _view.handleBack();
        }
        // :keep — just dismiss the menu, stay in racing mode
    }

}
