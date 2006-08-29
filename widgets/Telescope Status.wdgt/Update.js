// holds an instance of XMLHttpRequest
var xmlHttp = createXmlHttpRequestObject();
// holds the remote server address 
var serverAddress = "http://132.160.98.239/teldata";
// when set to true, display detailed error messages
var showErrors = false;
// update tracker
var updateTimer = null;
// counter, update every 30 seconds
var updateCounter = 30;

function currentEndpoint()
{
  if(window.console) {
        window.console.log("Called currentEndpoint( )");
  }
  return serverAddress;
}  

// creates an XMLHttpRequest instance
function createXmlHttpRequestObject() 
{
  // will store the reference to the XMLHttpRequest object
  var xmlHttp;
  // this should work for all browsers except IE6 and older
  try
  {
    // try to create XMLHttpRequest object
    xmlHttp = new XMLHttpRequest();
  }
  catch(e)
  {
  
  }
  // return the created object or display an error message
  if (!xmlHttp)
    displayError("Error creating the XMLHttpRequest object.");
  else 
    return xmlHttp;
}

// function that displays an error message
function displayError($message)
{

  unknownStatus( $message );
  
  // ignore errors if showErrors is false
  if (showErrors)
  {
    // turn error displaying Off
    showErrors = false;
    // display error message
    alert("Error encountered: \n" + $message);
  }
}

// change the URL we're looking at
function changeSite( $elem, $target )
{
  if(window.console) {
        window.console.log("Called changeSite( )");
  }
  serverAddress = $elem.options[$elem.selectedIndex].value;
  endDiv = document.getElementById( 'endpoint' );
  endDiv.innerHTML = serverAddress;
  if(window.console) {
        window.console.log("Setting serverAddress to " + serverAddress );
  }
  updateStatus();

}


// the function handles that handles updating the document
function updateStatus( )
{
  if(window.console) {
        window.console.log("Called updateStatus()");
  }

  // only continue if xmlHttp isn't void
  if (xmlHttp)
  {
  
    // try to connect to the server
    try
    {
      // continue only if the XMLHttpRequest object isn't busy
      // and the cache is not empty
      if ( xmlHttp.readyState == 4 || xmlHttp.readyState == 0 )
      {
 
        // make a server request to validate the extracted data
        xmlHttp.open("GET", serverAddress, true);
        xmlHttp.onreadystatechange = handleRequestStateChange;
        xmlHttp.send(null);
      }
    }
    catch (e)
    {
      // display an error when failing to connect to the server
      displayError(e.toString());
    }
  }
}

// function that handles the HTTP response
function handleRequestStateChange() 
{
  if(window.console) {
        window.console.log("Called handleReqestStateChange(" + xmlHttp.readyState + ")");
  }

  // when readyState is 4, we read the server response
  if (xmlHttp.readyState == 4) 
  {
    // continue only if HTTP status is "OK"
    if (xmlHttp.status == 200) 
    {
      try
      {
        // read the response from the server
        readResponse();
      }
      catch(e)
 
      {
        
        // display error message
        displayError(e.toString());
      }
    }
    else
    {
      // display error message
      displayError(xmlHttp.statusText);
    }
  }
}

// read server's response 
function readResponse()
{

  if ( window.console ) {
    window.console.log("Called readResponse()");
  }

  // retrieve the server's response 
  var response;
  try 
  {
     response = xmlHttp.responseText;
  }
  catch(e)
  {
        // display error message
        if( window.console) {
           window.console.log( "Error: response = xmlHttp.responseText;" );
           window.console.log( "Error: " + e.toString() );
        }
        displayError(e.toString());
	
  }

  //if(window.console) {
  //      window.console.log( response );
  //}

  // server error?
  if (response.indexOf("ERRNO") >= 0 
      || response.indexOf("error:") >= 0
      || response.length == 0)
    throw(response.length == 0 ? "Server error." : response);
  
  
  // print to <div>
  var array = response.split("\n");

  // time stamp, array[4] 
  var timestamp = array[4];
  if ( /Unable to connect to/.test( timestamp ) ) {
     if( window.console) {
     	 window.console.log( "Error: " + array[4].toString() );
     }
     displayError( "<font color='red'>Unable to connect to " + serverAddress + "</font>" );
     return;
  }
  
  timestamp = timestamp.replace( /^.*Mechanisms:/, "" );
  timestamp = timestamp.replace( /^#\s*/, "" );
  timestamp = timestamp.replace( /\s*$/, "" );
  timestamp = timestamp.replace( /\($/, "" );
  
  var time = timestamp.split( /@/ );
  timestamp = "Last updated at " + time[1] + " on " + time[0];
  
  timeDiv = document.getElementById( 'timestamp' );
  timeDiv.innerHTML = timestamp;

  // WEBCAMERAS
  
  extCamDiv = document.getElementById( 'externalCamera' );
  extCamDiv.innerHTML = "<img width='160' height='116' src='png/testCard.png' /><br><i><small>External camera</small></i>";   
  intCamDiv = document.getElementById( 'internalCamera' );
  intCamDiv.innerHTML = "<img width='160' height='116' src='png/testCard.png' /><br><i><small>Telescope camera</small></i>";      


  if ( /132\.160\.98\.239/.test(serverAddress) ) {
     // FTN, no camera access
  }   
  if ( /150\.203\.153\.202/.test(serverAddress) ) {
     // FTS, no camera access
  }  
  if ( /estar3\.astro\.ex\.ac\.uk/.test(serverAddress) ) {
     // LT
     extCamDiv = document.getElementById( 'externalCamera' );
     extCamDiv.innerHTML = "<img width='160' height='116' src='http://telescope.livjm.ac.uk/pics/webcam_ext_1_th.jpg' /><br><i><small>External camera</small></i>";
     
     intCamDiv = document.getElementById( 'internalCamera' );
     intCamDiv.innerHTML = "<img width='160' height='116' src='http://telescope.livjm.ac.uk/pics/webcam_int_2_th.jpg' /><br><i><small>Telescope camera</small></i>";   
  }  
  
  // PARSE REST OF MECHANISM STATUS INFORMATION
  var enclosure1 = "UNKNOWN";
  var enclosure2 = "UNKNOWN";
  var mirrorCover = "UNKNOWN";
  var azimuth = "UNKNOWN";
  var altitude = "UNKNOWN";
  var cassRotator = "UNKNOWN";
  
  var azimuthPos = "0.0";
  var altitudePos = "0.0";
  var cassPos = "0.0";
  var secondaryFocus = "0.0";
  
  for (var i in array)
  {
  
     // ENCLOSURE
     if ( /Enclosure shutter 1 current position/.test(array[i]) ) {
        var enc1 = array[i];
	enc1 = enc1.replace( /Enclosure shutter 1 current position/, "" );
        enc1 = enc1.replace( /^\s*/, "" );
        enc1 = enc1.replace( /\s*$/, "" );
	enclosure1 = enc1;
     }
     if ( /Enclosure shutter 2 current position/.test(array[i]) ) {
        var enc2 = array[i];
	enc2 = enc2.replace( /Enclosure shutter 2 current position/, "" );
        enc2 = enc2.replace( /^\s*/, "" );
        enc2 = enc2.replace( /\s*$/, "" );
	enclosure2 = enc2;
     }   
     
     // MIRROR COVER
     if ( /Primary mirror cover current position/.test(array[i]) ) {
        var mirr = array[i];
	mirr = mirr.replace( /Primary mirror cover current position:/, "" );
        mirr = mirr.replace( /^\s*/, "" );
        mirr = mirr.replace( /\s*$/, "" );
	mirrorCover = mirr;
     }  
     
     // AZIMUTH
     if ( /Current Azimuth status/.test(array[i]) ) {
        var az = array[i];
	az = az.replace( /Current Azimuth status:/, "" );
        az = az.replace( /^\s*/, "" );
        az = az.replace( /\/\d{3}$/, "" );
        az = az.replace( /\s*$/, "" );
	azimuth = az;
     } 
     
     if ( /Current Azimuth position/.test(array[i]) ) {
        var azPos = array[i];
	azPos = azPos.replace( /Current Azimuth position:/, "" );
        azPos = azPos.replace( /^\s*/, "" );
        azPos = azPos.replace( /degrees\.$/, "" );
        azPos = azPos.replace( /\s*$/, "" );
	azimuthPos = azPos;
     } 

     // ALTITUDE
     if ( /Current Altitude status/.test(array[i]) ) {
        var alt = array[i];
	alt = alt.replace( /Current Altitude status:/, "" );
        alt = alt.replace( /^\s*/, "" );
        alt = alt.replace( /\/\d{3}$/, "" );
        alt = alt.replace( /\s*$/, "" );
	altitude = alt;
     } 
     
     if ( /Current Altitude position/.test(array[i]) ) {
        var altPos = array[i];
	altPos = altPos.replace( /Current Altitude position:/, "" );
        altPos = altPos.replace( /^\s*/, "" );
        altPos = altPos.replace( /degrees\.$/, "" );
        altPos = altPos.replace( /\s*$/, "" );
	altitudePos = altPos;
     }  
          
     // CASS ROTATOR 
     if ( /Rotator status/.test(array[i]) ) {
        var cass = array[i];
	cass = cass.replace( /Rotator status:/, "" );
        cass = cass.replace( /^\s*/, "" );
        cass = cass.replace( /\/\d{3}$/, "" );
        cass = cass.replace( /\s*$/, "" );
	cassRotator = cass;
     }     
     
     if ( /Current Rotator position/.test(array[i]) ) {
        var cassPos = array[i];
	cassPos = cassPos.replace( /Current Rotator position:/, "" );
        cassPos = cassPos.replace( /^\s*/, "" );
        cassPos = cassPos.replace( /degrees\.$/, "" );
        cassPos = cassPos.replace( /\s*$/, "" );
        cassPos = cassPos.replace( /-/, "" ); // mirrored, remove minus sign
	cassPos = cassPos;
     }  
  
     // FOCUS
     if ( /Current Secondary mirror position/.test(array[i]) ) {
        var focus2 = array[i];
	focus2 = focus2.replace( /Current Secondary mirror position/, "" );
        focus2 = focus2.replace( /^\s*/, "" );
        focus2 = focus2.replace( /mm\.$/, "" );
        focus2 = focus2.replace( /\s*$/, "" );
	secondaryFocus = focus2;
     }

  }
  
  // ENCLOSURE
  var enclosureStatus = "Status/Mechanism/Enclosure/Enc_Unknown.gif";
  
  if ( enclosure1 == "CLOSED" && enclosure2 == "CLOSED" ) {
     enclosureStatus = "Status/Mechanism/Enclosure/Enc_Closed.gif";
  }
  if ( enclosure1 == "OPEN" && enclosure2 == "OPEN" ) {
     enclosureStatus = "Status/Mechanism/Enclosure/Enc_Open.gif";
  }  
  if ( enclosure1 == "MOVING" && enclosure2 == "MOVING" ) {
     enclosureStatus = "Status/Mechanism/Enclosure/Enc_Moving.gif";
  }  
    
  encDiv = document.getElementById( 'enclosureImage' );
  encDiv.innerHTML = "<img src='" + enclosureStatus + "' />";  
  
  // MIRROR COVER
  var mirrorStatus = 
     "<img src='Status/Mechanism/MirrorCover/Mirror_" + mirrorCover + ".jpg' />";
    
  mirrDiv = document.getElementById( 'mirrorCoverImage' );
  mirrDiv.innerHTML = mirrorStatus;   
  
  // AZIMUTH, ALTITUDE, CASS
  var altazcassStatus = 
     "<table><tr><td align='left' style='font-variant: small-caps;'>Az</td><td valign='middle'><img src='Status/Mechanism/Axis/Axis_" + azimuth + ".jpg' /></td></tr>";

  altazcassStatus = altazcassStatus +
     "<tr><td align='left' style='font-variant: small-caps;'>Alt<td valign='middle'><img src='Status/Mechanism/Axis/Axis_" + altitude + ".jpg' /></td></tr>";
     
  altazcassStatus = altazcassStatus +
     "<tr><td align='left' style='font-variant: small-caps;'>Cas<td valign='middle'><img src='Status/Mechanism/Axis/Axis_" + cassRotator + ".jpg' /></td></tr>";     
     
  altazcassStatus = altazcassStatus + "</table>";
    
  altazcassDiv = document.getElementById( 'altazcassStatus' );
  altazcassDiv.innerHTML = altazcassStatus;  
  
  // POINTING
  var pointingStatus = "_Blank";
  if ( azimuthPos >= 0 && azimuthPos <= 45 ) {
     pointingStatus = "_0";
  }   
  if ( azimuthPos > 45 && azimuthPos <= 90 ) {
     pointingStatus = "_1";
  }
  if ( azimuthPos > 90 && azimuthPos <= 135 ) {
     pointingStatus = "_2";
  }
  if ( azimuthPos > 135 && azimuthPos <= 180 ) {
     pointingStatus = "_3";
  }
  if ( azimuthPos > 180 && azimuthPos <= 225 ) {
     pointingStatus = "_4";
  }
  if ( azimuthPos > 225 && azimuthPos <= 270 ) {
     pointingStatus = "_5";
  }
  if ( azimuthPos > 270 && azimuthPos <= 315 ) {
     pointingStatus = "_6";
  }
  if ( azimuthPos > 315 && azimuthPos <= 360 ) {
     pointingStatus = "_7";
  }
                
  if ( altitudePos >= 0 && altitudePos <= 30 ) {
     pointingStatus = "_Outer" + pointingStatus;
  }   
  if ( altitudePos > 30 && altitudePos <= 60 ) {
     pointingStatus = "_Inner" + pointingStatus;
  }
  if ( altitudePos > 60 && altitudePos <= 90 ) {
     pointingStatus = "_Zenith";
  }
  pointDiv = document.getElementById( 'pointingImage' );
  pointDiv.innerHTML = "<img src='Status/Mechanism/Pointing/Point" + pointingStatus + ".jpg' />";  
  
  // CASS ROTATOR
  var cassStatus = "_blank";
  if ( cassPos == 0 ) {
     cassStatus = "_0";
  }
  if ( cassPos > 0 && cassPos <= 22.5 ) {
     cassStatus = "_1";
  }     
  if ( cassPos > 22.5 && cassPos <= 45 ) {
     cassStatus = "_2";
  }   
  if ( cassPos > 45 && cassPos <= 67.5 ) {
     cassStatus = "_3";
  }  
  if ( cassPos > 67.5 && cassPos <= 90 ) {
     cassStatus = "_4";
  }  
  if ( cassPos > 90 && cassPos <= 112.5 ) {
     cassStatus = "_5";
  }  
  if ( cassPos > 112.5 && cassPos <= 125 ) {
     cassStatus = "_6";
  }  
  if ( cassPos > 125 && cassPos <= 147.5 ) {
     cassStatus = "_7";
  }
  if ( cassPos > 147.5 && cassPos <= 180 ) {
     cassStatus = "_8";
  }  
  if ( cassPos > 180 && cassPos <= 202.5 ) {
     cassStatus = "_9";
  }  
  if ( cassPos > 202.5 && cassPos <= 225 ) {
     cassStatus = "_10";
  }  
  if ( cassPos > 225 && cassPos <= 247.5 ) {
     cassStatus = "_11";
  }  
  if ( cassPos > 247.5 && cassPos <= 270 ) {
     cassStatus = "_12";
  }  
  rotDiv = document.getElementById( 'rotatorImage' );
  rotDiv.innerHTML = "<img src='Status/Mechanism/Cass/Cass"+ cassStatus + ".jpg' />"; 
  
  // SECONDARY FOCUS
  focusDiv = document.getElementById( 'secondaryFocus' );
  focusDiv.innerHTML = "<i><small>Secondary Focus " + secondaryFocus + " mm</small></i>";   
   
  // reset the update counter to 30 seconds
  updateCounter = 30;   
       
}


function unknownStatus( $message ) {

  // TIMESTAMP
  
  var error = $message;
  if ( $message == "OK" || $message == "undefined" ) {
     error = "<font color='red'>Problem accessing " + serverAddress + "</font>";
  }   
  timestamp = error;
  timeDiv = document.getElementById( 'timestamp' );
  timeDiv.innerHTML = timestamp;

  // WEBCAMERAS
  extCamDiv = document.getElementById( 'externalCamera' );
  extCamDiv.innerHTML = "<img src='png/testCard.png' /><br><i><small>External camera</small></i>";   
  intCamDiv = document.getElementById( 'internalCamera' );
  intCamDiv.innerHTML = "<img src='png/testCard.png' /><br><i><small>Telescope camera</small></i>";      

  // ENCLOSURE
  encDiv = document.getElementById( 'enclosureImage' );
  encDiv.innerHTML = "<img src='Status/Mechanism/Enclosure/Enc_Unknown.gif' />";  
  
  // MIRROR COVER
  mirrDiv = document.getElementById( 'mirrorCoverImage' );
  mirrDiv.innerHTML = "<img src='Status/Mechanism/MirrorCover/Mirror_UNKNOWN.jpg' />";   
  
  // AZIMUTH, ALTITUDE
  var altazcassStatus = 
     "<table><tr><td align='left' style='font-variant: small-caps;'>Az</td><td valign='middle'><img src='Status/Mechanism/Axis/Axis_UNKNOWN.jpg' /></td></tr><tr><td align='left' style='font-variant: small-caps;'>Alt<td valign='middle'><img src='Status/Mechanism/Axis/Axis_UNKNOWN.jpg' /></td></tr><tr><td align='left' style='font-variant: small-caps;'>Cas<td valign='middle'><img src='Status/Mechanism/Axis/Axis_UNKNOWN.jpg' /></td></tr></table>";
  altazcassDiv = document.getElementById( 'altazcassStatus' );
  altazcassDiv.innerHTML = altazcassStatus;  
  
  // POINTING
  pointDiv = document.getElementById( 'pointingImage' );
  pointDiv.innerHTML = "<img src='Status/Mechanism/Pointing/Point_Blank.jpg' />";  
  // ROTATOR
  rotDiv = document.getElementById( 'rotatorImage' );
  rotDiv.innerHTML = "<img src='Status/Mechanism/Cass/Cass_Blank.jpg' />";  

  // SECONDARY FOCUS
  focusDiv = document.getElementById( 'secondaryFocus' );
  focusDiv.innerHTML = ""; 
  
  // reset the update counter to 30 seconds
  updateCounter = 30;
}  


// Startup and Shutdown the wdiget onshow() and onhide()

if (window.widget) {
   widget.onhide = onhide;
   widget.onshow = onshow;
}

function onshow () {
   if (updateTimer == null) {
      updateTimer = setInterval("countDown();", 1000 );
      updateStatus();
   }
}

function onhide () {
   if (updateTimer != null) {
      unknownStatus( "Loading data from " + serverAddress );
      clearInterval(updateTimer);
      updateTimer = null;
      updateCounter = 30;
   }
}

function countDown () {
   countDiv = document.getElementById( 'nextUpdate' );
   countDiv.innerHTML = "<i><small>" + updateCounter+ " sec</small></i>";  
   updateCounter = updateCounter - 1;
   
   if ( updateCounter == 0 ) {
      timeDiv = document.getElementById( 'timestamp' );
      timeDiv.innerHTML = "Updating from " + serverAddress;  
      updateCounter = 30;
      updateStatus();
   }   

}
