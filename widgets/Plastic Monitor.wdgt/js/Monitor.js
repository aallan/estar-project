
function changeInspected( $elem, $target ) {

  if(window.console) {
        window.console.log("Called changeInspected( )");
  }
  
  var plasticID = $elem.options[$elem.selectedIndex].value;

  if ( plasticID == "undefined" ) {
    nameDiv = document.getElementById( 'selectedName' );
    nameDiv.innerHTML = " ";  
    plidDiv = document.getElementById( 'selectedPlid' );
    plidDiv.innerHTML = " ";  
    verDiv = document.getElementById( 'selectedVersion' );
    verDiv.innerHTML = " ";        
    iconDiv = document.getElementById( 'selectedIcon' );
    iconDiv.innerHTML = " ";   
    ivornDiv = document.getElementById( 'selectedIvorn' );
    ivornDiv.innerHTML = " "; 
    descDiv = document.getElementById( 'selectedDescription' );
    descDiv.innerHTML = " "; 
    messDiv = document.getElementById( 'selectedMessages' );
    messDiv.innerHTML = " "; 
                     
  } else {   
 
    getNameAsync.makeRequest( plasticID );
    plidDiv = document.getElementById( 'selectedPlid' );
    plidDiv.innerHTML = "<small><i>" + plasticID + "</i></small>";  
    getVersion.makeRequest( plasticID );
    getIcon.makeRequest( plasticID );
    getIvorn.makeRequest( plasticID );
    getDescription.makeRequest( plasticID );
    getMessages.makeRequest( plasticID );
  
  }
  
  statusDiv = document.getElementById( 'widgetStatus' );
  if ( plasticID == "undefined" ) {
     statusDiv.innerHTML = "";   
  } else {
     statusDiv.innerHTML = "Inspecting " + plasticID;   
  }
}

function updateDropdown() {

   var plasticStatus = "Updating applications list...";
   
   statusDiv = document.getElementById( 'widgetStatus' );
   statusDiv.innerHTML = plasticStatus;
   
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
      plasticStatus = "Not running as a widget";
      
   }
   
   statusDiv = document.getElementById( 'widgetStatus' );
   statusDiv.innerHTML = plasticStatus;


}

