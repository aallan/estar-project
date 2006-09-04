function setup() {

   createGenericButton(
	document.getElementById("donePrefsButton"),"Done",hidePrefs,60);
   document.getElementById("donePrefsButton").display = "none";

  var eventSource = new Timeline.DefaultEventSource();
  var bandInfos = [
    Timeline.createBandInfo({
        eventSource:    eventSource,
        width:          "70%", 
        intervalUnit:   Timeline.DateTime.DAY, 
        intervalPixels: 100
    }),
    Timeline.createBandInfo({
        showEventText:  false,
        trackHeight:    0.5,
        trackGap:       0.2,
        eventSource:    eventSource,
        width:          "30%", 
        intervalUnit:   Timeline.DateTime.MONTH, 
        intervalPixels: 200
    })
  ];
  bandInfos[1].syncWith = 0;
  bandInfos[1].highlight = true;
  
  var tl = Timeline.create(document.getElementById("event_timeline"), bandInfos)
;
  Timeline.loadXML("http://vo.astro.ex.ac.uk/ogle/events/ogleWidget.xml", function(xml, url) { eventSource.loadXML(xml, url); });

}
