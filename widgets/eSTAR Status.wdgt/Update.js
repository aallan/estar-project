// holds an instance of XMLHttpRequest
var xmlHttp = createXmlHttpRequestObject();
// holds the remote server address 
var serverAddress = "http://www.estar.org.uk/network.status";
// when set to true, display detailed error messages
var showErrors = false;

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
  // ignore errors if showErrors is false
  if (showErrors)
  {
    // turn error displaying Off
    showErrors = false;
    // display error message
 
    alert("Error encountered: \n" + $message);
    // retry validation after 10 seconds
    setTimeout("updateStatus();", 10000);
  }
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

// Individual blocks of status meta-data
//
// 00 # Wed Jun 28 19:00:04 2006

  // time stamp, array[0] 
  var timestamp = array[0];
  timestamp = timestamp.replace( /^#\s*/, "" );
  timestamp = timestamp.replace( /\s*$/, "" );
  timestamp = "Last updated: " + timestamp;
  
  timeDiv = document.getElementById( 'timestamp' );
  timeDiv.innerHTML = timestamp;
  
  // ping section, array[2] - [8]
  var exString = "<table>";
  var ftnString = "<table>";
  var ftsString = "<table>";
  var ftsString = "<table>";
  var ltString = "<table>";
  var jachString = "<table>";
  var raptorString = "<table>";

// 01 # MACHINES
// 02 estar.astro.ex.ac.uk PING
// 03 estar2.astro.ex.ac.uk PING
// 04 estar3.astro.ex.ac.uk PING
// 05 estar.ukirt.jach.hawaii.edu NACK
// 06 www.estar.org.uk NACK
// 07 132.160.98.239 NACK
// 08 161.72.57.3 NACK
// 09 150.203.153.202 NACK
  
  for( var j = 2; j <= 9; j ++ ) {
    var line = array[j].split( " " );

    // Exeter
    if( line[0].match( /astro\.ex\.ac\.uk/ ) ) {
       exString = exString + "<tr><td>" +
   	                         line[0] + "</td><td><font color='";
       if( line[1].match( /^PING$/ ) ) {
          exString = exString + "lightgreen'>OK</font></td></tr>";
       } else {
          exString = exString + "red'>NO</font></td></tr>";
       }
    } 
    
    // FTN
    if( line[0].match( /132\.160/ ) ) {
       if ( line[0].match( /132\.160\.98\.239/ ) ) {
          line[0] = "ftnproxy.ifa.hawaii.edu";
       }
       ftnString = ftnString + "<tr><td>" +
   	                         line[0] + "</td><td><font color='";
       if( line[1].match( /^PING$/ ) ) {
          ftnString = ftnString + "lightgreen'>OK</font></td></tr>";
       } else {
          ftnString = ftnString + "red'>NO</font></td></tr>";
       }
    }    
    
    // FTS
    if( line[0].match( /150\.203/ ) ) {
       if ( line[0].match( /150\.203\.153\.202/ ) ) {
          line[0] = "ftsproxy.aao.gov.au";
       }
       ftsString = ftsString + "<tr><td>" +
   	                         line[0] + "</td><td><font color='";
       if( line[1].match( /^PING$/ ) ) {
          ftsString = ftsString + "lightgreen'>OK</font></td></tr>";
       } else {
          ftsString = ftsString + "red'>NO</font></td></tr>";
       }
    } 
        
    // LT
    if( line[0].match( /161\.72/ ) ) {
       if ( line[0].match( /161\.72\.57\.3/ ) ) {
          line[0] = "ltproxy.ing.iac.es";
       }
       ltString = ltString + "<tr><td>" +
   	                         line[0] + "</td><td><font color='";
       if( line[1].match( /^PING$/ ) ) {
          ltString = ltString + "lightgreen'>OK</font></td></tr>";
       } else {
          ltString = ltString + "red'>NO</font></td></tr>";
       }
    }       
    
    // UKIRT
    if( line[0].match( /jach\.hawaii\.edu/ ) ) {
       jachString = jachString + "<tr><td>" +
   	                         line[0] + "</td><td><font color='";
       if( line[1].match( /^PING$/ ) ) {
          jachString = jachString + "lightgreen'>OK</font></td></tr>";
       } else {
          jachString = jachString + "red'>NO</font></td></tr>";
       }
    } 
        
    // RAPTOR
    // No machines to match as yet...


  }

// 10 # NODE AGENTS
// 11 FTN estar3.astro.ex.ac.uk 8077 UP
// 12 FTS estar3.astro.ex.ac.uk 8079 DOWN
// 13 LT estar3.astro.ex.ac.uk 8078 UP
// 14 RAPTOR estar2.astro.ex.ac.uk 8080 UP
// 15 UKIRT estar.ukirt.jach.hawaii.edu 8080 UP


  // node agents, array[11] - [15]
  for( var j = 11; j <= 15; j ++ ) {
    var line = array[j].split( " " );

    // FTN
    if( line[0].match( /FTN/ ) ) {
       ftnString = ftnString + "<tr><td>Node Agent</td><td><font color='";
       if( line[3].match( /^UP$/ ) ) {
          ftnString = ftnString + "lightgreen'>UP</font></td></tr>";
       } else {
          if ( line[3].match( /^DOWN$/ ) ) {
            ftnString = ftnString + "red'>DOWN</font></td></tr>";
          }
          if ( line[3].match( /^FAULT$/ ) ) {
            ftnString = ftnString + "orange'>FAULT</font></td></tr>";
          }	  
       }       
    }
    
    // FTS
    if( line[0].match( /FTS/ ) ) {
       ftsString = ftsString + "<tr><td>Node Agent</td><td><font color='";
       if( line[3].match( /^UP$/ ) ) {
          ftsString = ftsString + "lightgreen'>UP</font></td></tr>";
       } else {
          if ( line[3].match( /^DOWN$/ ) ) {
            ftsString = ftsString + "red'>DOWN</font></td></tr>";
          }
          if ( line[3].match( /^FAULT$/ ) ) {
            ftsString = ftsString + "orange'>FAULT</font></td></tr>";
          }	  
       }       
    }    

    // LT
    if( line[0].match( /LT/ ) ) {
       ltString = ltString + "<tr><td>Node Agent</td><td><font color='";
       if( line[3].match( /^UP$/ ) ) {
          ltString = ltString + "lightgreen'>UP</font></td></tr>";
       } else {
          if ( line[3].match( /^DOWN$/ ) ) {
            ltString = ltString + "red'>DOWN</font></td></tr>";
          }
          if ( line[3].match( /^FAULT$/ ) ) {
            ltString = ltString + "orange'>FAULT</font></td></tr>";
          }	  
       }       
    }    

    // RAPTOR
    if( line[0].match( /RAPTOR/ ) ) {
       raptorString = raptorString + "<tr><td>Gateway</td><td><font color='";
       if( line[3].match( /^UP$/ ) ) {
          raptorString = raptorString + "lightgreen'>UP</font></td></tr>";
       } else {
          if ( line[3].match( /^DOWN$/ ) ) {
            raptorString = raptorString + "red'>DOWN</font></td></tr>";
          }
          if ( line[3].match( /^FAULT$/ ) ) {
            raptorString = raptorString + "orange'>FAULT</font></td></tr>";
          }	  
       }       
    }    


    // UKIRT
    if( line[0].match( /RAPTOR/ ) ) {
       jachString = jachString + "<tr><td>Node Agent</td><td><font color='";
       if( line[3].match( /^UP$/ ) ) {
          jachString = jachString + "lightgreen'>UP</font></td></tr>";
       } else {
          if ( line[3].match( /^DOWN$/ ) ) {
            jachString = jachString + "red'>DOWN</font></td></tr>";
          }
          if ( line[3].match( /^FAULT$/ ) ) {
            jachString = jachString + "orange'>FAULT</font></td></tr>";
          }	  
       }       
    }  

  }
  
// 16 # USER AGENTS
// 17 EXO-PLANET estar3.astro.ex.ac.uk 8000 UP
// 18 GRB estar2.astro.ex.ac.uk 8000 UP

  // exo-planet, array[17] 
  var exo = array[17].split( " " );
  exString = exString + "<tr><td>Exo-planet Programme</td><td><font color='";
  if( exo[3].match( /^UP$/ ) ) {
     exString = exString + "lightgreen'>UP</font></td></tr>";
  } else {
     if ( exo[3].match( /^DOWN$/ ) ) {
       exString = exString + "red'>DOWN</font></td></tr>";
     }
     if ( exo[3].match( /^FAULT$/ ) ) {
       exString = exString + "orange'>FAULT</font></td></tr>";
     }       
  }	

  // grb, array[18] 
  var grb = array[18].split( " " );
  exString = exString + "<tr><td>GRB Programme</td><td><font color='";
  if( grb[3].match( /^UP$/ ) ) {
     exString = exString + "lightgreen'>UP</font></td></tr>";
  } else {
     if ( grb[3].match( /^DOWN$/ ) ) {
       exString = exString + "red'>DOWN</font></td></tr>";
     }
     if ( grb[3].match( /^FAULT$/ ) ) {
       exString = exString + "orange'>FAULT</font></td></tr>";
     }       
  }

// 19 # EVENT BROKERS
// 20 eSTAR estar3.astro.ex.ac.uk 9099 UP

  // estar, array[20] 
  var estar = array[20].split( " " );
  exString = exString + "<tr><td>Event Broker</td><td><font color='";
  if( estar[3].match( /^UP$/ ) ) {
     exString = exString + "lightgreen'>UP</font></td></tr>";
  } else {
     if ( estar[3].match( /^DOWN$/ ) ) {
       exString = exString + "red'>DOWN</font></td></tr>";
     }
     if ( estar[3].match( /^FAULT$/ ) ) {
       exString = exString + "orange'>FAULT</font></td></tr>";
     }       
  }

  // send to popups
  exString = exString + "</table>";
  ftnString = ftnString + "</table>";
  ftsString = ftsString + "</table>";
  ltsString = ltString + "</table>";
  jachString = jachString + "</table>";
  
  exeterMachine = document.getElementById( 'exetermachines' );
  exeterMachine.innerHTML = exString; 
    
  ftnMachine = document.getElementById( 'ftnmachines' );
  ftnMachine.innerHTML = ftnString;    
    
  ftsMachine = document.getElementById( 'ftsmachines' );
  ftsMachine.innerHTML = ftsString;
    
  ltMachine = document.getElementById( 'ltmachines' );
  ltMachine.innerHTML = ltString;
    
  raptorMachine = document.getElementById( 'raptormachines' );
  raptorMachine.innerHTML = raptorString;
      
  jachMachine = document.getElementById( 'jachmachines' );
  jachMachine.innerHTML = jachString;
  
}
