
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
    verdDiv.innerHTML = " ";        
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

