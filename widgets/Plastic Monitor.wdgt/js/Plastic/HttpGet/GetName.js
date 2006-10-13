var getName = {

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
    displayError("Error creating the XMLHttpRequest object.");
  else 
    return xmlHttp;
},

// the function handles that handles updating the document
makeRequest: function( $serverAddress, $plid )
{
  if(window.console) {
        window.console.log("Called getName.makeRequest()");
  }

  var xmlHttp = getName.createXmlHttpRequestObject();
  $serverAddress = $serverAddress + "plastic/hub/getName/plain?plid=" + $plid; 
 
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
 
        xmlHttp.open("GET", $serverAddress, false);
	xmlHttp.send(null);
      }
    }
    catch (e)
    {
      // display an error when failing to connect to the server
      displayError(e.toString());
    }
    
    var response ="ERROR";
    try
      {
        // read the response from the server

        response = xmlHttp.responseText;
        // server error?
       if (response.indexOf("ERRNO") >= 0 
         || response.indexOf("error:") >= 0
         || response.length == 0)
       throw(response.length == 0 ? "Server error." : response);
  
      }
      catch(e)
      {
        
        // display error message
        // display error message
        if( window.console) {
           window.console.log( "Error: response = xmlHttp.responseText;" );
           window.console.log( "Error: " + e.toString() );
        }
        displayError(e.toString());
      }
      
      // print to <div>
      return response; 
    
  }
}

}
