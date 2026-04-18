import Toybox.Lang;
import Toybox.WatchUi;

class Tuesday_Night_TimerMenuDelegate extends WatchUi.Menu2InputDelegate {

    //! Untyped: Monkey C rejects typed Method vs method(:setStartTime) (Number) -> Void at call site.
    private var _callback;

    function initialize(callback) {
        Menu2InputDelegate.initialize();
        _callback = callback;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        _callback.invoke(item.getId() as Number);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

}
