// holds an instance of XMLHttpRequest
var xmlHttp = createXmlHttpRequestObject();
// holds the remote server address 
var serverAddress = "validate.cgi";
// when set to true, display detailed error messages
var showErrors = true;
// initialize the validation requests cache 
var cache = new Array();

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
    // assume IE6 or older
    var XmlHttpVersions = new Array("MSXML2.XMLHTTP.6.0",
                                    "MSXML2.XMLHTTP.5.0",
                                    "MSXML2.XMLHTTP.4.0",
                                    "MSXML2.XMLHTTP.3.0",
                                    "MSXML2.XMLHTTP",
                                    "Microsoft.XMLHTTP");
    // try every id until one works
    for (var i=0; i<XmlHttpVersions.length && !xmlHttp; i++) 
    {
      try 
      { 
        // try to create XMLHttpRequest object
        xmlHttp = new ActiveXObject(XmlHttpVersions[i]);
      } 
      catch (e) {} // ignore potential error
    }
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
    setTimeout("validate();", 10000);
  }
}

// the function handles the validation for any form field
function validate(inputValue, fieldID)
{
  if(window.console) {
        window.console.log("Called validate(" + inputValue + "," + fieldID + ")");
  }
  if ( fieldID == undefined ) {
        if ( window.console ) {
           window.console.log("Hiding undefined error from user");
        }
        return;
  }

  if( inputValue == undefined ) {
        if( window.console ) {
           window.console.log('Reseting inputValue to "" from an undefined value');
        }
        inputValue = "";
  }

  // only continue if xmlHttp isn't void
  if (xmlHttp)
  {
    // if we received non-null parameters, we add them to cache in the
    // form of the query string to be sent to the server for validation
    if (fieldID)
    {
      // encode values for safely adding them to an HTTP request query string
      inputValue = encodeURIComponent(inputValue);
      fieldID = encodeURIComponent(fieldID);
      // add the values to the queue
      cache.push("inputValue=" + inputValue + "&fieldID=" + fieldID);
    }
    // try to connect to the server
    try
    {
      // continue only if the XMLHttpRequest object isn't busy
      // and the cache is not empty
      if ((xmlHttp.readyState == 4 || xmlHttp.readyState == 0) 
         && cache.length > 0)
      {
        // get a new set of parameters from the cache
        var cacheEntry = cache.shift();
        // make a server request to validate the extracted data
        xmlHttp.open("GET", serverAddress +"?" + cacheEntry, true);
        xmlHttp.setRequestHeader("Content-Type", 
                                 "application/x-www-form-urlencoded");
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
        if ( e.toString == "undefined" ) {
          if ( window.console ) {
            window.console.log( "Error: undefined error" );
          }
          return;
        }
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

  if ( response == undefined ) {
       if( window.console ) {
          window.console.log( "readResponse(), hiding undefined response object from user" );
       }
       return;
  }

  if(window.console) {
        window.console.log( response );
  }

  // server error?
  if (response.indexOf("ERRNO") >= 0 
      || response.indexOf("error:") >= 0
      || response.length == 0)
    throw(response.length == 0 ? "Server error." : response);
  // get response in XML format (assume the response is valid XML)
  responseXml = xmlHttp.responseXML;
  // get the document element
  xmlDoc = responseXml.documentElement;
  result = xmlDoc.getElementsByTagName("result")[0].firstChild.data;
  fieldID = xmlDoc.getElementsByTagName("fieldid")[0].firstChild.data;
  // find the HTML element that displays the error
  message = document.getElementById(fieldID + "Failed");

  // show the error or hide the error
  message.className = (result == "0") ? "error" : "hidden";

  if ( fieldID == "previous_ivorn" ) {
     if ( result == "1" ) {
        if ( document.getElementById( "previous_ivorn").value == "" ) {
           document.getElementById( "cite_type" ).disabled = true;
           document.getElementById( "cite_type" ).value = "";
           document.getElementById( "hidden_toggle" ).value = "disabled";
        } else {
           document.getElementById( "cite_type" ).disabled = false;
           document.getElementById( "cite_type" ).value = "followup";
           document.getElementById( "hidden_toggle" ).value = "enabled";
        }
     } else {
        document.getElementById( "cite_type" ).disabled = true;
        document.getElementById( "cite_type" ).value = "";
        document.getElementById( "hidden_toggle" ).value = "disabled";
     }
  }

  // call validate() again, in case there are values left in the cache
  setTimeout("validate();", 500);
}

// sets focus on the first field of the form
function setFocus()    
{
  if(window.console) {
	window.console.log("Called setFocus()");
  }

  if( document.getElementById( "hidden_toggle" ).value == "disabled" ) {
     document.getElementById( "cite_type" ).disabled = true;
     document.getElementById( "cite_type" ).value = "";
  } else {
     document.getElementById( "cite_type" ).disabled = false;
  }  
  document.getElementById("description").focus();
}
