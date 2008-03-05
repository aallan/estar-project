// update tracker
var updateTimer = null;

// counter, update every 600 seconds
var updateCounter = 600;

// Timeline event window
var eventSource = new Timeline.DefaultEventSource();

function setup() {

   createGenericButton(
	document.getElementById("donePrefsButton"),"Done",hidePrefs,60);
   document.getElementById("donePrefsButton").display = "none";

  var bandInfos = [
    Timeline.createBandInfo({
      eventSource:    eventSource,
      width:	      "70%", 
      intervalUnit:   Timeline.DateTime.DAY, 
      intervalPixels: 100
    }),
    Timeline.createBandInfo({
      showEventText:  false,
      trackHeight:    0.5,
      trackGap:       0.2,
      eventSource:    eventSource,
      width:	      "30%", 
      intervalUnit:   Timeline.DateTime.MONTH, 
      intervalPixels: 200
    })
  ];

  bandInfos[1].syncWith = 0;
  bandInfos[1].highlight = true;
  var tl = Timeline.create(document.getElementById("event_timeline"),bandInfos);

  reloadData();
  
}

// Startup and Shutdown the wdiget onshow() and onhide()

if (window.widget) {
   widget.onhide = onhide;
   widget.onshow = onshow;
}

function onshow () {
   if (updateTimer == null) {
      updateTimer = setInterval("countDown();", 1000 );
      update();
   }
}

function onhide () {
   if (updateTimer != null) {
      clearInterval(updateTimer);
      updateTimer = null;
      updateCounter = 600;
   }
}

function countDown () {
   updateCounter = updateCounter - 1;
   counterDiv = document.getElementById( 'countDown' );
   counterDiv.innerHTML = "Refresh widget in " + updateCounter + " seconds";
         
   if ( updateCounter == 0 ) {
      update();
   }   

}

function update() {
   counterDiv.innerHTML = 
      "Updating from http://estar6.astro.ex.ac.uk/ogle/events/ogleWidget.xml";  
   updateCounter = 600;
   Timeline.loadXML( "http://estar6.astro.ex.ac.uk/ogle/events/empty.xml",
   		 function(xml, url) { eventSource.loadXML(xml, url); });
   Timeline.paint();	  
   reloadData();
   counterDiv.innerHTML = "Done";
}


function reloadData() {		    
  Timeline.loadXML( "http://estar6.astro.ex.ac.uk/ogle/events/ogleWidget.xml",
                    function(xml, url) { eventSource.loadXML(xml, url); });
  Timeline.paint();		    
		    
}  
