var getRegistered = {

// creates an XMLHttpRequest instance
createXmlHttpRequestObject: function() 
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
    alert("Error creating the XMLHttpRequest object.");
  else 
    return xmlHttp;
},



// the function handles that handles updating the document
makeRequest: function( )
{
  if(window.console) {
        window.console.log("Called getRegistered.makeRequest()");
  }
      
  xmlHttp['register'] = getRegistered.createXmlHttpRequestObject();
   
  var serverAddress = plastic.httpEndpoint();
  serverAddress = serverAddress + "plastic/hub/getRegisteredIds/plain"; 

  // only continue if xmlHttp['register'] isn't void
  if (xmlHttp['register'])
  {

    // try to connect to the server
    try
    {
      // continue only if the XMLHttpRequest object isn't busy
      // and the cache is not empty
      if ( xmlHttp['register'].readyState == 4 || xmlHttp['register'].readyState == 0 )
      {
 
        // make a server request to validate the extracted data
        xmlHttp['register'].open("GET", serverAddress, true);
        xmlHttp['register'].onreadystatechange = getRegistered.handleRequestStateChange;
        xmlHttp['register'].send(null);

      }
    }
    catch (e)
    {
      // display an error when failing to connect to the server
      alert(e.toString());
    }
  }
},

// function that handles the HTTP response
handleRequestStateChange: function() 
{

  if(window.console) {
        window.console.log("Called getRegistered.handleRequestStateChange(" + xmlHttp['register'].readyState + ")");
  }

  // when readyState is 4, we read the server response
  if (xmlHttp['register'].readyState == 4) 
  {
    // continue only if HTTP status is "OK"
    if (xmlHttp['register'].status == 200) 
    {
      try
      {
        // read the response from the server
        getRegistered.readResponse();
      }
      catch(e)
 
      {
        
        // display error message
        alert(e.toString());
      }
    }
    else
    {
      // display error message
      alert(xmlHttp['register'].statusText);
    }
  }
},

// read server's response 
readResponse: function()
{

  if ( window.console ) {
    window.console.log("Called getRegistered.readResponse()");
  }

  // retrieve the server's response 
  var response;
  try 
  {
     response = xmlHttp['register'].responseText;
  }
  catch(e)
  {
        // display error message
        if( window.console) {
           window.console.log( 
	      "Error: response = xmlHttp['register'].responseText;" );
           window.console.log( "Error: " + e.toString() );
        }
        alert(e.toString());
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
  document.forms["form"].dropdown.options.length = 1;
  document.forms["form"].dropdown.options[0] = 
      new Option( "Choose an application...", undefined );
  var counter = 0;
  for( var i in array ) {
     counter = counter + 1;
     if ( array[i] != "" ) {
     
        // xmlrpc version
	var plasticName = getNameSync.makeRequest( array[i] );
	var option = new Option( plasticName, array[i] );
        document.forms["form"].dropdown.options[counter] = option;
     }	
  }    
  
}

}
