var setupDone = 0;

// create an array for global xmlHttpRequest objects
var xmlHttp = new Array();

function setup() {

   // horrible hack, I don't know why I'm doing this?
   if ( setupDone == 1 ) {
      return;
   }   

   var plasticStatus = "Building widget...";
   
   statusDiv = document.getElementById( 'widgetStatus' );
   statusDiv.innerHTML = plasticStatus;

   createGenericButton(
	document.getElementById("donePrefsButton"),"Done",hidePrefs,60);
   document.getElementById("donePrefsButton").display = "none";

   if( window.widget ) {   
      if ( plastic.isHubRunning() == 1 ) {
         var endpoint = plastic.xmlrpcEndpoint();
         var version = plastic.plasticVersion();
         endpointDiv = document.getElementById( 'xmlrpcEndpoint' );
         endpointDiv.innerHTML = endpoint + "  (version " + version + ")"; 
	 
	 plasticStatus ="Found PLASTIC Hub";
         getRegistered.makeRequest();
	 
      } else {
	 plasticStatus = "There is no PLASTIC Hub running";
	 
      }   
	 
   } else {
      plasticStatus = "Not running as a widget (from setup)";
      document.form2.refresh.disabled=true;
      
   }
   
   statusDiv = document.getElementById( 'widgetStatus' );
   statusDiv.innerHTML = plasticStatus;

   //var option = document.forms["form"].dropdown.selected;
   //statusDiv = document.getElementById( 'widgetStatus' );
   //statusDiv.innerHTML = "Current ID is " option.value;   
    	       
   setupDone = 1;  
}
