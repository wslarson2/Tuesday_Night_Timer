import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Timer;
import Toybox.Lang;


class Tuesday_Night_TImerView extends WatchUi.View {
    private var _timer1 as Timer.Timer?;
    private var _count1 as Number = 0;
    private var _startTime as Number=(5*60)+10;
    private var _warnings as Dictionary<Number, String> = {5=>"start", 4=>"notice1" , 1=>"notice2"};

    function initialize() {
        View.initialize();
    }

    //! Callback for timer 
    public function callback() as Void {
        _count1++;
        WatchUi.requestUpdate();
    }

    // Load your resources here
    function onLayout(dc as Dc) as Void {

        var timer1 = new Timer.Timer();
        timer1.start(method(:callback), 1000, true);
        _timer1 = timer1;

        setLayout(Rez.Layouts.MainLayout(dc));
    }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() as Void {
    }

    // Update the view
    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var string;
        if((_warnings[((_startTime-_count1)/60)]!=null && ((_startTime-_count1)%60)<=10)or(_count1<=10)){
        string = ((_startTime-_count1)%60);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        }else{
        string = createStringTime();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        }
        
        dc.drawText((dc.getWidth()/2), (dc.getHeight() / 2) -60, Graphics.FONT_NUMBER_THAI_HOT, string, Graphics.TEXT_JUSTIFY_CENTER);
        // Call the parent onUpdate function to redraw the layout
        //View.onUpdate(dc);
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    function onHide() as Void {
    }

    public function createStringTime() as String{
        var minuteString = "";
        var secondString = "";

        if(((_startTime-_count1)/60)<10){
                 minuteString = "0" + ((_startTime-_count1)/60).toString();
            }else{
                minuteString = ((_startTime-_count1)/60).toString();
            }
        if(((_startTime-_count1)%60)<10){
                 secondString = "0" + ((_startTime-_count1)%60).toString();
            }else{
                secondString = ((_startTime-_count1)%60).toString();
            }
        if(_startTime-_count1 ==0){
                minuteString="00";
                secondString ="00";
                _timer1.stop();
            }
        return minuteString+":"+secondString;
    }

    public function stopTimer() as Void {
        if (_timer1 != null) {
            _timer1.stop();
        }
    }

}
